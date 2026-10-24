extends Node

# set this to true if you want to have control while the tas is playing
var dont_disable_inputs = false

var mod_id: String

var is_recording = false
var recording_images = []
var img_index = 0
var player
var saved_events = {}
var lines = []
var tas_inputs = []
var current_frame = -1
var frames_since_last_input = -1
var pressed_keys = []
var joystick_input_processing = null
var joypad_keys = []
var current_line = ""


func disable_inputs():
    if dont_disable_inputs:
        return

    for action in ["ui_accept", "ui_cancel", "ui_left", "ui_right", "ui_up", "ui_down", "jump", "move_left_controller", "move_right_controller", "move_down_controller", "move_up_controller", "action", "pause", "restart", "screenshot", "action_2", "cycle_skin_left", "cycle_skin_right", "reset_pos", "save_pos", "load_pos", "ability_1_toggle", "ability_2_toggle", "increase_speed", "decrease_speed", "practice_mode", "toggle_flight", "jump_kb", "jump_controller", "action_kb", "action_controller", "action_2_kb", "action_2_controller", "move_up_kb", "move_down_kb", "move_left_kb", "move_right_kb", "move_left", "move_right", "legacy_jump", "select"]:
        saved_events[action] = InputMap.action_get_events(action)
        InputMap.action_erase_events(action) # removes all keybinds


func enable_inputs():
    if dont_disable_inputs:
        return

    for action in saved_events:
        for event in saved_events[action]:
            InputMap.action_add_event(action, event) # re-adds keybinds
    saved_events = {}


func stop_tas():
    current_frame = -1
    for input in pressed_keys:
        Input.action_release(input)
    pressed_keys = []
    if joystick_input_processing != null:
        joystick_event(0, 0)
        joystick_input_processing = null


func play_inputs(inputs):
    tas_inputs = inputs.map(func(input_item): return input_item[0])
    lines = inputs.map(func(input_item): return input_item[1])

    disable_inputs()
    stop_tas()
    current_frame = 0
    pressed_keys = []


func combine_images(dir):
    if OS.execute("which", ["ffmpeg"]) != 0:
        push_error("ffmpeg not installed, skipping video creation")
        return

    var commands = [
        "-f", "concat",
        "-safe", "0",
        "-i", dir + "/video/files.txt",
        "-c:v", "libx264",
        "-preset", "ultrafast",
        "-pix_fmt", "yuv420p",
        "-an",
        "-shortest",
        dir + "/output.mp4"
    ]

    await ModLoader.all_mods[mod_id].node.get_tree().create_timer(10.0).timeout

    var output = []
    var exit_code = OS.execute("ffmpeg", commands, output, true)
    if exit_code != 0:
        push_error("ffmpeg error: ", output)
    else:
        print("ffmpeg finished")


func update(fake_input):
    if current_frame == -1:
        return

    if current_frame >= len(tas_inputs):
        stop_tas()
        enable_inputs()
        return

    if is_recording:
        var img_path = "%s/video/%s.jpg" % [ModLoader.all_mods[mod_id].path_to_dir, img_index]
        var img = ModLoader.all_mods[mod_id].node.get_viewport().get_texture().get_image()
        WorkerThreadPool.add_task(func():
            img.save_jpg(img_path, 0.85)
        )
        recording_images.append([img_path, Engine.get_physics_ticks_per_second()])
        img_index += 1

    var no_input = true
    while no_input:
        if lines[current_frame] == current_line:
            frames_since_last_input += 1
        else:
            frames_since_last_input = 1
        current_line = lines[current_frame]
        no_input = false
        var frame_inputs = tas_inputs[current_frame]
        for input in frame_inputs:
            input = input.to_lower()
            var function = input.split("(")[0]
            var args = input.split("(")[1].split(")")[0].split(",")

            if input == "instantinput":
                for action in frame_inputs[1]:
                    if action in pressed_keys:
                        pressed_keys.erase(action)
                        Input.action_release(action)
                        fake_input.release(action)
                    fake_input.press(action)
                    Input.action_press(action)
                    fake_input.release(action)
                    Input.action_release(action)
                no_input = true
                break

            elif input == "noinput":
                no_input = true

            elif function == "joystick":
                var angle = float(args[0]) - 90
                var force = float(args[1])
                joystick_event(angle, force)
                joystick_input_processing = true

            elif function == "print":
                player = ModLoader.all_mods[mod_id].node.get_tree().get_first_node_in_group("player")

                var print_map = {
                    "pos": player.position if player else "",
                    "position": player.position if player else "",
                    "vel": player.velocity if player else "",
                    "velocity": player.velocity if player else "",
                }
                var print_string = ""
                args.remove_at(0)
                for arg in args:
                    if arg in print_map:
                        print_string += str(print_map[arg]) + " "
                    else:
                        if "\\n" in arg:
                            print_string += arg.replace("\\n", "\n")
                        else:
                            print_string += arg + " "
                print(print_string)

            elif function == "pause":
                ModLoader.all_mods[mod_id].node.get_tree().paused = true

            elif function == "desync_check":
                player = ModLoader.all_mods[mod_id].node.get_tree().get_first_node_in_group("player")
                var pos = ["%.3f" % player.position.x, "%.3f" % player.position.y]
                if pos == [args[1], args[2]]:
                    return
                print("desync: ", pos, " - ", [args[1], args[2]])

            elif function == "start_recording":
                var dir_access = DirAccess.open(ModLoader.all_mods[mod_id].path_to_dir)
                if not dir_access.dir_exists("video"):
                    dir_access.make_dir("video")

                is_recording = true
                recording_images = []
                img_index = 0

            elif function == "end_recording":
                is_recording = false
                var make_video = args[0] == "true"

                var dir = ModLoader.all_mods[mod_id].path_to_dir
                var file = FileAccess.open(dir + "/video/files.txt", FileAccess.WRITE)
                file.store_line("ffconcat version 1.0")
                for index in range(recording_images.size()):
                    var img_path = recording_images[index][0]
                    file.store_line("file '%s'" % img_path)
                    if index == 0:
                        file.store_line("duration 1") # makes first frame longer
                    else:
                        file.store_line("duration %f" % (1.0 / recording_images[index][1]))
                file.close()

                if make_video:
                    Thread.new().start(combine_images.bind(dir))

            elif function == "restart":
                for old_scene in ModLoader.all_mods[mod_id].node.get_tree().get_nodes_in_group("loaded_scenes"):
                    old_scene.queue_free()

                var container = ModLoader.all_mods[mod_id].node.get_tree().get_first_node_in_group("container")
                var current_scene = container.get_child(-1).scene_file_path
                if current_scene == "res://levels/main_menu.tscn":
                    current_scene = "res://levels/main_area_demo.tscn"

                var loaded_scene = load("res://levels/main_menu.tscn").instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
                container.add_child(loaded_scene)

                await ModLoader.all_mods[mod_id].node.get_tree().process_frame

                loaded_scene.queue_free()
                loaded_scene = load(current_scene).instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
                container.add_child(loaded_scene)
                loaded_scene.add_to_group("loaded_scenes")

                player = ModLoader.all_mods[mod_id].node.get_tree().get_first_node_in_group("player")
                player.position = Vector2(0, 0)
                player.cam.position_smoothing_enabled = false
                # player.practice_mode = true

            elif function == "save_state":
                var dir = ModLoader.all_mods[mod_id].path_to_dir
                var file = FileAccess.open(dir + args[0], FileAccess.WRITE)

                player = ModLoader.all_mods[mod_id].node.get_tree().get_first_node_in_group("player")

                file.store_line(str(player.position.x))
                file.store_line(str(player.position.y))
                file.store_line(str(player.velocity.x))
                file.store_line(str(player.velocity.y))
                file.close()

            elif function == "load_state":
                var dir = ModLoader.all_mods[mod_id].path_to_dir
                if not FileAccess.file_exists(dir + args[0]):
                    return

                var file = FileAccess.open(dir + args[0], FileAccess.READ)
                var pos_x = float(file.get_line())
                var pos_y = float(file.get_line())
                var vel_x = float(file.get_line())
                var vel_y = float(file.get_line())
                file.close()

                player = ModLoader.all_mods[mod_id].node.get_tree().get_first_node_in_group("player")

                player.position = Vector2(pos_x, pos_y)
                player.velocity = Vector2(vel_x, vel_y)

            else:
                Input.action_press(input)
                if input not in pressed_keys:
                    fake_input.press(input)
                    pressed_keys.append(input)

        current_frame += 1

        if no_input:
            continue

        for input in pressed_keys:
            if input not in frame_inputs:
                pressed_keys.erase(input)
                var joystick_command = null
                for new_input in frame_inputs:
                    if "joystick" in new_input:
                        joystick_command = new_input
                        break
                if joystick_command == null:
                    fake_input.release(input)
                    Input.action_release(input)
                else:
                    var angle_radians = deg_to_rad(float(joystick_command.split("(")[1].split(")")[0].split(",")[0]) - 90)
                    var axis_x = cos(angle_radians)
                    var axis_y = sin(angle_radians)
                    var key_x = "move_left" if axis_x < 0 else "move_right" if axis_x > 0 else ""
                    var key_y = "move_up" if axis_y < 0 else "move_down" if axis_y > 0 else ""
                    for key in joypad_keys:
                        if key != key_x and key != key_y:
                            fake_input.release(key)
                            Input.action_release(key)
                    if input not in joypad_keys:
                        fake_input.release(input)
                        Input.action_release(input)

        if joystick_input_processing == false:
            joystick_event(0, 0)
            joystick_input_processing = null

        if joystick_input_processing == true:
            joystick_input_processing = false


func joystick_event(degrees, force):
    var angle_radians = deg_to_rad(degrees)

    var axis_x = cos(angle_radians) * force
    var axis_y = sin(angle_radians) * force

    axis_x = clamp(axis_x, -1.0, 1.0)
    axis_y = clamp(axis_y, -1.0, 1.0)

    var key_x = "move_left_kb" if axis_x < 0 else "move_right_kb" if axis_x > 0 else ""
    var key_y = "move_up_kb" if axis_y < 0 else "move_down_kb" if axis_y > 0 else ""

    for key in joypad_keys:
        if key != key_x and key != key_y:
            Input.action_release(key)

    joypad_keys.clear()

    if key_x != "":
        Input.action_press(key_x, abs(axis_x))
        joypad_keys.append(key_x)

    if key_y != "":
        Input.action_press(key_y, abs(axis_y))
        joypad_keys.append(key_y)
