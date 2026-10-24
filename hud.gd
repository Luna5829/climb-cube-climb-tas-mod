extends CanvasLayer

@onready var hud = $Hud
@onready var label = $Hud/Label
@onready var panel = $Hud/Label/Panel
var panel_style

var mod_id: String
var path_to_dir: String

var is_dragging = false
var drag_start_mouse
var drag_start
var playback
var player
var stats_info
var decimal_precision
var rounding

func _ready():
    var font = FontFile.new()
    font.load_dynamic_font("res://fixedsys.ttf")

    font.multichannel_signed_distance_field = true
    font.generate_mipmaps = true

    label.add_theme_font_override("font", font)
    label.add_theme_color_override("font_color", Color.WHITE)

    panel.gui_input.connect(_on_gui_input)

    hud.scale = Vector2(0.5, 0.5)
    hud.position = Vector2(10, 55)

    panel_style = panel.get_theme_stylebox("panel")


func _on_gui_input(event: InputEvent):
    if not event is InputEventMouseButton:
        return

    if event.button_mask & 1 == 1:
        is_dragging = true
        drag_start_mouse = get_mpos()
        drag_start = hud.position

    else:
        is_dragging = false


func get_mpos():
    return get_viewport().get_mouse_position()


func format_number(number):
    var return_value = str(snapped(number, rounding)).pad_decimals(decimal_precision)
    # if number >= 0:
    #     return_value = "+" + return_value
    return return_value


func format_numbers(format_string, numbers = null):
    if numbers == null:
        return snapped(format_string, rounding)
    return format_string % numbers.map(format_number)


func _physics_process(_delta):
    if ModLoader.all_mods[mod_id].hud_toggle == false:
        hud.hide()
        return

    player = ModLoader.all_mods[mod_id].node.get_tree().get_first_node_in_group("player")
    if not player:
        hud.hide()
        return

    hud.show()

    if is_dragging:
        hud.position = drag_start + get_mpos() - drag_start_mouse

    panel_style.bg_color = ModLoader.all_mods[mod_id].background_color
    label.add_theme_color_override("font_color", ModLoader.all_mods[mod_id].text_color)

    decimal_precision = ModLoader.all_mods[mod_id].rounding
    rounding = 0.1 ** decimal_precision

    playback = ModLoader.all_mods[mod_id].playback
    stats_info = {
        "current frame": playback.current_frame if playback != null else -1,
        "frames since last input": playback.frames_since_last_input if playback != null else -1,
        "current line": playback.current_line if playback != null else "",
        "position": format_numbers("%s, %s", [player.position.x, player.position.y]),
        "velocity": format_numbers("%s, %s", [player.velocity.x, player.velocity.y]),
        "player state": player.state_names[player.state].to_pascal_case(),
        "touching ground": player.is_on_floor(),
        "can walljump": (player.get_node("Colliders/WallCheckLeft").is_colliding() or player.get_node("Colliders/WallCheckRight").is_colliding()) or player.get_node("Timers/WallLeaveTimer").time_left > 0,
        "can walljump (buzzsaw)": (player.get_node("Timers/WallLeaveTimer2").time_left > 0 and player.velocity.y < 0 and player.get_node("Timers/WallSaw").time_left > 0),
    }

    var display_text = ""
    for stat_name in stats_info:
        var stat_value = stats_info[stat_name]
        display_text += "%s: %s\n" % [stat_name, stat_value]
    display_text = display_text.strip_edges()

    label.text = display_text
