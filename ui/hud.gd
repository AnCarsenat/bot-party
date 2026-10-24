extends CanvasLayer
## Autoload "Hud": in-level overlay (level name, players) and the pause menu.

var _top: HBoxContainer
var _level_label: Label
var _players_box: HBoxContainer
var _hint: Label
var _pause: Control
var _resume_button: Button
var _restart_button: Button
var _menu_button: Button
var _scene: Node


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.theme = UiTheme.make()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_top = HBoxContainer.new()
	_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top.offset_left = 16
	_top.offset_right = -16
	_top.offset_top = 10
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_top)
	_level_label = Label.new()
	_level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level_label.add_theme_font_override("font", UiTheme.FONT_BOLD)
	_level_label.add_theme_font_size_override("font_size", 28)
	_level_label.add_theme_color_override("font_outline_color", UiTheme.MARBLE)
	_level_label.add_theme_constant_override("outline_size", 6)
	_top.add_child(_level_label)
	_players_box = HBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 12)
	_top.add_child(_players_box)

	_hint = Label.new()
	_hint.text = "Esc: pause"
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_outline_color", UiTheme.MARBLE)
	_hint.add_theme_constant_override("outline_size", 5)
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.offset_left = 16
	_hint.offset_top = -34
	root.add_child(_hint)

	_pause = _build_pause()
	root.add_child(_pause)
	_pause.hide()


func _build_pause() -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0.92, 0.91, 0.94, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	col.add_child(UiTheme.title("Paused", 48))
	_resume_button = UiTheme.button("Resume", func(): set_paused(false))
	col.add_child(_resume_button)
	_restart_button = UiTheme.button("Restart level", func(): set_paused(false); GameState.restart_level())
	col.add_child(_restart_button)
	_menu_button = UiTheme.button("Main menu", func(): set_paused(false); _to_menu())
	col.add_child(_menu_button)
	return dim


## Online host: everyone goes back to the online lobby. Online client: leaves the game.
func _to_menu() -> void:
	if Net.is_client():
		Net.leave()
	GameState.go_to_menu()


func in_level() -> bool:
	var s := get_tree().current_scene
	return s != null and s.has_node("Game")


func set_paused(value: bool) -> void:
	if value and not in_level():
		return
	# Online, the game keeps running for everyone else: the menu is just an overlay.
	get_tree().paused = value and not Net.is_online()
	_pause.visible = value
	if value:
		_restart_button.visible = not Net.is_client()
		_menu_button.text = "Leave game" if Net.is_client() else ("Back to lobby" if Net.is_host() else "Main menu")
		_resume_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and in_level():
		set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	var level := in_level()
	_top.visible = level
	_hint.visible = level
	if not level:
		if _pause.visible:
			set_paused(false)
		return
	var scene := get_tree().current_scene
	if scene != _scene:
		_scene = scene
		_level_label.text = GameState.level_name(GameState.level_index(scene.scene_file_path))
		_hint.modulate.a = 1.0
		create_tween().tween_property(_hint, "modulate:a", 0.0, 1.0).set_delay(5.0)
	if scene.has_meta("title"):
		_level_label.text = scene.get_meta("title")
	_update_players()


var _chip_state := ""


## Status icons (party traps) shown under a player's chip.
const STATUS_ICONS := {
	"stuck": preload("res://party/art/status_stuck.webp"),
	"slippery": preload("res://party/art/status_slippery.webp"),
	"slowed": preload("res://party/art/status_slowed.webp"),
	"floating": preload("res://party/art/status_floating.webp"),
}


func _update_players() -> void:
	var players := get_tree().get_nodes_in_group("players")
	var state := ""
	for p in players:
		var st = p.get("statuses")
		state += "%d%s%s," % [p.get_meta("player_index", 0), "x" if p.get_meta("eliminated", false) else "",
			":".join(st.keys()) if st is Dictionary else ""]
	if state == _chip_state:
		return
	_chip_state = state
	for c in _players_box.get_children():
		c.queue_free()
	for p in players:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		col.add_child(UiTheme.player_chip(p.get_meta("player_index", 0) + 1, p.get_meta("eliminated", false)))
		var icons := HBoxContainer.new()
		icons.alignment = BoxContainer.ALIGNMENT_CENTER
		icons.add_theme_constant_override("separation", 2)
		icons.custom_minimum_size = Vector2(0, 32)
		var st = p.get("statuses")
		if st is Dictionary and not p.get_meta("eliminated", false):
			for k in st:
				if STATUS_ICONS.has(k):
					var t := TextureRect.new()
					t.texture = STATUS_ICONS[k]
					t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
					t.custom_minimum_size = Vector2(32, 32)
					t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					t.tooltip_text = k.capitalize()
					icons.add_child(t)
		col.add_child(icons)
		_players_box.add_child(col)
