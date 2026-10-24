extends Node

const ModSetting = preload("res://mod_setting.gd")

var mod_id: String
var path_to_dir: String

var tas_file: ModSetting
var keybinds_file: ModSetting

var player
var advance_frame = false
var parser
var playback


class FakeInputEvent:
    var mod_id
    var _pressed := {}
    var _released := {}

    func execute() -> void:
        ModLoader.all_mods[mod_id].node.get_tree().get_first_node_in_group("player")._input(self)
        _pressed.clear()
        _released.clear()

    func press(action: StringName) -> void:
        _pressed[action] = true
        execute()

    func release(action: StringName) -> void:
        _released[action] = true
        execute()

    func is_action_pressed(action: StringName) -> bool:
        return _pressed.get(action, false)

    func is_action_released(action: StringName) -> bool:
        return _released.get(action, false)


var fake_input = FakeInputEvent.new()

func _ready():
    fake_input.mod_id = mod_id

    ModLoader.register_setting(mod_id, ModSetting.toggle("hud_toggle", "HUD enabled", true))

    ModLoader.register_setting(mod_id, ModSetting.int_slider("rounding", "Decimal rounding", 3, 0, 10))

    tas_file = ModLoader.register_setting(mod_id, ModSetting.file("tas_file", "TAS file path", path_to_dir + "/inputs.tas", PackedStringArray(["*.tas ; TAS Input Files"])))
    keybinds_file = ModLoader.register_setting(mod_id, ModSetting.file("keybinds_file", "Keybinds path", path_to_dir + "/keybinds.json", PackedStringArray(["*.json ; JSON Files"])))

    ModLoader.register_setting(mod_id, ModSetting.color("background_color", "Background color", Color.BLACK))
    ModLoader.register_setting(mod_id, ModSetting.color("text_color", "Text color", Color.WHITE))

    process_mode = Node.PROCESS_MODE_ALWAYS
    process_physics_priority = -1000

    bind_key("advance_frame", KEY_BRACKETLEFT)
    bind_key("resume", KEY_BRACKETRIGHT)
    bind_key("start_tas", KEY_BACKSLASH)
    bind_key("stop_tas", KEY_SEMICOLON)
    bind_key("update_inputs", KEY_APOSTROPHE)

    var hud_scene = load(path_to_dir + "/hud.tscn").instantiate()
    var hud_script = load(path_to_dir + "/hud.gd")
    hud_scene.set_script(hud_script)
    hud_scene.mod_id = mod_id
    hud_scene.path_to_dir = path_to_dir
    add_child(hud_scene)


func bind_key(action_name: String, keycode: int) -> void:
    if not InputMap.has_action(action_name):
        InputMap.add_action(action_name)

    var event := InputEventKey.new()
    event.physical_keycode = keycode
    InputMap.action_add_event(action_name, event)


func start_tas():
    if tas_file.value != "" and keybinds_file.value != "":
        if playback != null and playback.current_frame != -1:
            playback.stop_tas()
            playback.enable_inputs()
            playback = null

        # ResourceLoader.load(path, type_hint, cache_mode)
        parser = ResourceLoader.load(path_to_dir + "/parser.gd", "", 0).new()
        playback = ResourceLoader.load(path_to_dir + "/playback.gd", "", 0).new()
        ModLoader.all_mods[mod_id].playback = playback
        playback.mod_id = mod_id
        playback.play_inputs(parser.read(tas_file.value, keybinds_file.value))


func close_file(file):
    await get_tree().create_timer(1).timeout
    file.close()


func _physics_process(delta):
    if advance_frame:
        advance_frame = false
        get_tree().paused = true

    if Input.is_action_just_pressed("start_tas"):
        start_tas()

    if Input.is_action_just_pressed("stop_tas"):
        if playback != null and playback.current_frame != -1:
            playback.stop_tas()
            playback.enable_inputs()
            playback = null

    if Input.is_action_just_pressed("advance_frame"):
        advance_frame = true
        get_tree().paused = false

    if Input.is_action_just_pressed("resume"):
        get_tree().paused = false

    if Input.is_action_just_pressed("update_inputs") and tas_file.value != "" and keybinds_file.value != "":
        parser = ResourceLoader.load(path_to_dir + "/parser.gd", "", 0).new()
        var inputs = parser.read(tas_file.value, keybinds_file.value)
        playback.tas_inputs = inputs.map(func(input_item): return input_item[0])
        playback.lines = inputs.map(func(input_item): return input_item[1])

    if get_tree().paused:
        return

    playback.update(fake_input)
