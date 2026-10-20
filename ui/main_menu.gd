extends Control
## Title screen. The menu is one of the game's machines: every option sits on a
## pressure button, and a live cable runs from the machine to the selected one.
##   Up/Down (arrows or any player's keys) move, Enter / Space / any jump key
##   chooses, Left/Right change a setting, Esc goes back.
## "Players" is the lobby: each player presses their own jump key to join.

const TITLE := "Machine Room"
const VERSION := "v0.12"
const NAV_REPEAT := 0.16  # seconds between moves when a pad stick is held

const TEX_BASE := preload("res://button_base.webp")
const TEX_CAP := preload("res://button_cap.webp")
const TEX_PLAYER := preload("res://player.webp")
const MACHINES := {
	"main": preload("res://gate.webp"), "campaign": preload("res://delayer.webp"),
	"party": preload("res://randomizer.webp"), "settings": preload("res://prolongator.webp"),
}

var _screen := "main"
var _items: Array = []      # [{text, on_accept, on_left, on_right, enabled, info, key}]
var _index := 0
var _rows: Array[Control] = []
var _list: VBoxContainer
var _heading: Label
var _machine: TextureRect
var _info: Label
var _cable: _Cable
var _lobby: _Lobby
var _footer: HBoxContainer
var _hint: Label
var _nav_cooldown := 0.0


func _ready() -> void:
	theme = UiTheme.make()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_layout()
	GameState.joined_changed.connect(func(): _refresh_footer(); if _screen == "players": _lobby.queue_redraw())
	_show("main")


# --- Layout -------------------------------------------------------------------

func _build_layout() -> void:
	var bg := TextureRect.new()
	bg.texture = preload("res://tile.webp")
	bg.stretch_mode = TextureRect.STRETCH_TILE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.modulate = Color(0.93, 0.92, 0.95)
	bg.size = Vector2(4000, 3000)
	bg.scale = Vector2(2.5, 2.5)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_cable = _Cable.new()
	_cable.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cable.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cable)

	var title := Label.new()
	title.text = TITLE
	title.position = Vector2(64, 36)
	title.add_theme_font_override("font", UiTheme.FONT_BOLD)
	title.add_theme_font_size_override("font_size", 84)
	add_child(title)

	_heading = Label.new()
	_heading.position = Vector2(70, 136)
	_heading.add_theme_font_override("font", UiTheme.FONT_MEDIUM)
	_heading.add_theme_font_size_override("font_size", 28)
	_heading.add_theme_color_override("font_color", UiTheme.MUTED)
	add_child(_heading)

	_list = VBoxContainer.new()
	_list.position = Vector2(56, 196)
	_list.add_theme_constant_override("separation", 2)
	add_child(_list)

	_machine = TextureRect.new()
	_machine.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_machine.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_machine.size = Vector2(160, 160)
	_machine.anchor_left = 1.0
	_machine.anchor_right = 1.0
	_machine.offset_left = -440
	_machine.offset_right = -280
	_machine.offset_top = 150
	_machine.offset_bottom = 310
	add_child(_machine)

	_info = Label.new()
	_info.anchor_left = 1.0
	_info.anchor_right = 1.0
	_info.offset_left = -520
	_info.offset_right = -120
	_info.offset_top = 330
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", 24)
	add_child(_info)

	_lobby = _Lobby.new()
	_lobby.anchor_left = 1.0
	_lobby.anchor_right = 1.0
	_lobby.offset_left = -700
	_lobby.offset_right = -60
	_lobby.offset_top = 150
	_lobby.offset_bottom = 560
	_lobby.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lobby)

	_footer = HBoxContainer.new()
	_footer.anchor_top = 1.0
	_footer.anchor_bottom = 1.0
	_footer.offset_left = 64
	_footer.offset_top = -100
	_footer.offset_bottom = -64
	_footer.add_theme_constant_override("separation", 8)
	add_child(_footer)

	_hint = Label.new()
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = 64
	_hint.offset_top = -48
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_color", UiTheme.MUTED)
	add_child(_hint)

	var version := Label.new()
	version.text = VERSION
	version.anchor_left = 1.0
	version.anchor_top = 1.0
	version.anchor_right = 1.0
	version.anchor_bottom = 1.0
	version.offset_left = -90
	version.offset_top = -44
	version.add_theme_font_size_override("font_size", 16)
	version.add_theme_color_override("font_color", UiTheme.MUTED)
	add_child(version)


# --- Screens ------------------------------------------------------------------

func _show(screen: String, keep_index := false) -> void:
	_screen = screen
	_items.clear()
	match screen:
		"main":
			_items = [
				{"text": "Campaign", "on_accept": func(): _show("campaign"), "info": "Get through the levels together. Buttons, wires and machines open the way."},
				{"text": "Party", "on_accept": func(): _show("party"), "info": "Everyone places a trap, then you race to the flag. You score when you make it and the others don't."},
				{"text": "Players", "on_accept": func(): _show("players"), "info": "%d playing. Join or leave here." % GameState.joined.size()},
				{"text": "Settings", "on_accept": func(): _show("settings"), "info": "Volume and window."},
			]
			if OS.get_name() != "Web":
				_items.append({"text": "Quit", "on_accept": func(): get_tree().quit(), "info": "Close the game."})
		"campaign":
			for i in GameState.levels.size():
				var locked := i >= GameState.unlocked
				_items.append({"text": GameState.level_name(i), "enabled": not locked,
					"on_accept": func(): _start(func(): GameState.start_level(i)),
					"info": ("Finish the level before it to unlock this one." if locked else "Level %d of %d." % [i + 1, GameState.levels.size()])})
			_items.append({"text": "Back", "on_accept": func(): _back()})
		"party":
			_items.append({"text": "New party", "on_accept": func(): _start(func(): Party.new_game()),
				"info": "First to %d points wins. Traps you place stay for the whole party." % Party.TARGET_SCORE})
			if Party.has_save():
				_items.append({"text": "Continue", "on_accept": func(): _start(func(): Party.continue_game()), "info": Party.describe_save()})
			_items.append({"text": "Back", "on_accept": func(): _back()})
		"players":
			_items = [{"text": "Done", "on_accept": func(): _back()}]
		"settings":
			_items = [
				{"text": "Music", "key": "music_volume", "on_left": func(): _bump("music_volume", -0.1), "on_right": func(): _bump("music_volume", 0.1), "on_accept": func(): _bump("music_volume", 0.1, true), "info": "Left and right to change."},
				{"text": "Sounds", "key": "sfx_volume", "on_left": func(): _bump("sfx_volume", -0.1), "on_right": func(): _bump("sfx_volume", 0.1), "on_accept": func(): _bump("sfx_volume", 0.1, true), "info": "Left and right to change."},
				{"text": "Fullscreen", "key": "fullscreen", "on_left": func(): _toggle("fullscreen"), "on_right": func(): _toggle("fullscreen"), "on_accept": func(): _toggle("fullscreen"), "info": "Switch between a window and the whole screen."},
				{"text": "Back", "on_accept": func(): _back()},
			]
	_heading.text = {"main": "", "campaign": "Campaign", "party": "Party", "players": "Players", "settings": "Settings"}[screen]
	if not keep_index:
		_index = 0
	_index = clampi(_index, 0, _items.size() - 1)
	while not _items[_index].get("enabled", true):
		_index = (_index + 1) % _items.size()
	var lobby := screen == "players"
	_lobby.visible = lobby
	_machine.visible = not lobby
	_info.visible = not lobby
	_machine.texture = MACHINES.get(screen, MACHINES.main)
	_rebuild_list()
	_refresh_info()
	_refresh_footer()
	_hint.text = "Press your jump key to join, your down key to leave. Enter or Esc when everyone is in." if lobby \
		else "Arrows or your own keys to move.  Enter or jump to choose.  Esc to go back."
	_cable.snap = true


func _rebuild_list() -> void:
	for r in _rows:
		r.queue_free()
	_rows.clear()
	for i in _items.size():
		var row := _Row.new()
		row.menu = self
		row.index = i
		row.custom_minimum_size = Vector2(520, 70)
		row.mouse_entered.connect(func(): _select(i))
		row.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: _select(i); _accept())
		_list.add_child(row)
		_rows.append(row)


func _refresh_info() -> void:
	if not _items.is_empty():
		_info.text = _items[_index].get("info", "")
	for r in _rows:
		r.queue_redraw()


func _refresh_footer() -> void:
	for c in _footer.get_children():
		c.queue_free()
	for slot in GameState.joined:
		var chip := UiTheme.player_chip(slot)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_footer.add_child(chip)


## Where the cable should end: the selected row's button cap (in our coordinates).
func cable_target() -> Vector2:
	if _screen == "players" or _rows.is_empty() or not is_instance_valid(_rows[_index]):
		return Vector2.INF
	var r: _Row = _rows[_index]
	return r.global_position - global_position + r.socket()


func cable_start() -> Vector2:
	if not _machine.visible:
		return Vector2.INF
	return _machine.global_position - global_position + Vector2(10, 100)


# --- Settings helpers -----------------------------------------------------------

func _bump(key: String, delta: float, wrap := false) -> void:
	var v: float = GameState.settings[key] + delta
	if wrap and v > 1.001:
		v = 0.0
	GameState.settings[key] = clampf(snappedf(v, 0.1), 0.0, 1.0)
	GameState.apply_settings()
	GameState.save_settings()
	_refresh_info()


func _toggle(key: String) -> void:
	GameState.settings[key] = not GameState.settings[key]
	GameState.apply_settings()
	GameState.save_settings()
	_refresh_info()


# --- Input --------------------------------------------------------------------

func _start(action: Callable) -> void:
	if GameState.joined.is_empty():
		_show("players")
		return
	action.call()


func _back() -> void:
	var back_to := {"campaign": 0, "party": 1, "players": 2, "settings": 3}
	var idx: int = back_to.get(_screen, 0)
	_show("main")
	_select(idx)


func _select(i: int) -> void:
	if i == _index or i < 0 or i >= _items.size() or not _items[i].get("enabled", true):
		return
	_index = i
	_refresh_info()


func _move(dir: int) -> void:
	var i := _index
	for k in _items.size():
		i = (i + dir + _items.size()) % _items.size()
		if _items[i].get("enabled", true):
			break
	_select(i)


func _accept() -> void:
	var item: Dictionary = _items[_index]
	if item.get("enabled", true) and item.has("on_accept"):
		if _index < _rows.size():
			_rows[_index].press()
		item.on_accept.call()


func _process(delta: float) -> void:
	_nav_cooldown = maxf(0.0, _nav_cooldown - delta)


## Returns the player slot (1-8) whose `suffix` action this event is, or 0.
func _player_action(event: InputEvent, suffix: String) -> int:
	for slot in range(1, GameState.MAX_PLAYERS + 1):
		var a := "p%d_%s" % [slot, suffix]
		if InputMap.has_action(a) and event.is_action_pressed(a, false, true):
			return slot
	return 0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		return
	var stick := event is InputEventJoypadMotion
	if stick and _nav_cooldown > 0.0:
		return

	if _screen == "players":
		var joiner := _player_action(event, "action_1")
		var leaver := _player_action(event, "move_down")
		if joiner and not GameState.is_joined(joiner):
			GameState.join(joiner)
			_lobby.joined_now(joiner)
			_handled(stick); return
		if leaver and GameState.is_joined(leaver):
			GameState.leave(leaver)
			_handled(stick); return
		var enter: bool = event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]
		if enter or event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
			_back()
			_handled(stick)
		return

	if event.is_action_pressed("ui_up", true) or _player_action(event, "move_up"):
		_move(-1); _handled(stick)
	elif event.is_action_pressed("ui_down", true) or _player_action(event, "move_down"):
		_move(1); _handled(stick)
	elif event.is_action_pressed("ui_left", true) or _player_action(event, "move_left"):
		if _items[_index].has("on_left"): _items[_index].on_left.call()
		_handled(stick)
	elif event.is_action_pressed("ui_right", true) or _player_action(event, "move_right"):
		if _items[_index].has("on_right"): _items[_index].on_right.call()
		_handled(stick)
	elif event.is_action_pressed("ui_accept") or _player_action(event, "action_1"):
		_accept(); _handled(stick)
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		if _screen != "main":
			_back()
		_handled(stick)


func _handled(stick: bool) -> void:
	if stick:
		_nav_cooldown = NAV_REPEAT
	get_viewport().set_input_as_handled()


# --- Drawing pieces ----------------------------------------------------------------

## One menu option: a pressure button and its name (plus a value for settings).
class _Row extends Control:
	var menu
	var index := 0
	var _press := 0.0

	func press() -> void:
		_press = 1.0

	const TEXT_X := 92.0
	const TEXT_SIZE := 44

	## Where the cable plugs in: just after the option's name.
	func socket() -> Vector2:
		var item: Dictionary = menu._items[index]
		var w := UiTheme.FONT_BOLD.get_string_size(item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x
		if item.has("key"):
			return Vector2(420.0 + (190.0 if typeof(GameState.settings[item.key]) != TYPE_BOOL else 70.0), 34)
		return Vector2(TEXT_X + 10.0 + w + 26.0, 34)

	func _process(delta: float) -> void:
		if _press > 0.0:
			_press = maxf(0.0, _press - delta * 4.0)
			queue_redraw()

	func _draw() -> void:
		var item: Dictionary = menu._items[index]
		var selected: bool = index == menu._index
		var enabled: bool = item.get("enabled", true)
		# Button: the cap sinks when selected, a bit more when chosen.
		var sink := (6.0 if selected else 0.0) + 4.0 * _press
		var cap_color: Color = UiTheme.RED if enabled else Color("b8b5c0")
		if selected:
			cap_color = cap_color.darkened(0.15)
		draw_texture_rect(TEX_CAP, Rect2(Vector2(4, -22 + sink), Vector2(64, 64)), false, cap_color)
		draw_texture_rect(TEX_BASE, Rect2(Vector2(4, -22), Vector2(64, 64)), false)
		# Name.
		var font: Font = UiTheme.FONT_BOLD if selected else UiTheme.FONT_MEDIUM
		var color: Color = UiTheme.INK if enabled else Color("9a97a6")
		if not selected and enabled:
			color = Color("3a3844")
		var x := TEXT_X + (10.0 if selected else 0.0)
		draw_string(font, Vector2(x, 48), item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, color)
		# Setting value.
		if item.has("key"):
			var v = GameState.settings[item.key]
			var vx := 420.0
			if typeof(v) == TYPE_BOOL:
				draw_string(UiTheme.FONT_MEDIUM, Vector2(vx, 46), "On" if v else "Off", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, UiTheme.INK)
			else:
				for k in 10:
					var r := Rect2(vx + k * 17, 22, 13, 22)
					draw_rect(r, UiTheme.LIVE if k < roundi(v * 10) else UiTheme.MARBLE)
					draw_rect(r, UiTheme.INK, false, 3.0)


## The live cable from the machine to the selected option.
class _Cable extends Control:
	var snap := false
	var _end := Vector2.ZERO
	var _time := 0.0

	func _process(delta: float) -> void:
		_time += delta
		var menu = get_parent()
		var target: Vector2 = menu.cable_target()
		if target != Vector2.INF:
			_end = target if snap or _end == Vector2.ZERO else _end.lerp(target, 1.0 - exp(-14.0 * delta))
			snap = false
		queue_redraw()

	func _draw() -> void:
		var menu = get_parent()
		var a: Vector2 = menu.cable_start()
		if a == Vector2.INF or menu.cable_target() == Vector2.INF:
			return
		var b := _end
		var sag := 16.0 + a.distance_to(b) * 0.1
		var ctrl := (a + b) / 2.0 + Vector2(0, sag)
		var pts := PackedVector2Array()
		for i in 33:
			var t := i / 32.0
			pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
		draw_polyline(pts, UiTheme.INK, 9.0, true)
		draw_polyline(pts, UiTheme.LIVE, 4.0, true)
		for p in [a, b]:
			draw_circle(p, 8.0, UiTheme.INK)
			draw_circle(p, 4.0, UiTheme.LIVE)
		# Signal travelling from the machine to the button.
		for k in 3:
			var t := fmod(_time * 0.9 + k / 3.0, 1.0)
			var idx := t * (pts.size() - 1)
			var p: Vector2 = pts[int(idx)].lerp(pts[mini(int(idx) + 1, pts.size() - 1)], idx - int(idx))
			draw_circle(p, 5.0, Color("f0fff4"))


## Lobby: one pressure button per player slot; joining drops your character on it.
class _Lobby extends Control:
	var _joined_at := {}

	func joined_now(slot: int) -> void:
		_joined_at[slot] = Time.get_ticks_msec()

	func _process(_d: float) -> void:
		if visible:
			queue_redraw()

	func _draw() -> void:
		var cols := 4
		var cell := Vector2(size.x / cols, 200)
		for i in GameState.MAX_PLAYERS:
			var slot := i + 1
			var joined := GameState.is_joined(slot)
			var color: Color = PlayerSpawner.COLORS[i % 8]
			var c := Vector2((i % cols + 0.5) * cell.x, (i / cols) * cell.y + 110)
			# Button the player stands on.
			var cap := color if joined else Color("c9c6d2")
			var sink := 6.0 if joined else 0.0
			draw_texture_rect(TEX_CAP, Rect2(c + Vector2(-48, -60 + sink), Vector2(96, 96)), false, cap)
			draw_texture_rect(TEX_BASE, Rect2(c + Vector2(-48, -60), Vector2(96, 96)), false)
			if joined:
				var t := clampf((Time.get_ticks_msec() - _joined_at.get(slot, 0)) / 250.0, 0.0, 1.0)
				var drop := (1.0 - t) * (1.0 - t) * -70.0
				draw_texture_rect(TEX_PLAYER, Rect2(c + Vector2(-40, -86 + sink + drop), Vector2(80, 80)), false, color)
			var name := "P%d" % slot
			draw_string(UiTheme.FONT_BOLD, c + Vector2(-60, 44), name, HORIZONTAL_ALIGNMENT_CENTER, 120, 26,
				UiTheme.INK if joined else Color("8a8796"))
			var sub := "Ready" if joined else "Press " + UiTheme.jump_key_text(slot)
			draw_string(UiTheme.FONT_REGULAR, c + Vector2(-80, 68), sub, HORIZONTAL_ALIGNMENT_CENTER, 160, 18,
				UiTheme.ACCENT if joined else UiTheme.MUTED)
