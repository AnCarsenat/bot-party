extends Node2D
## Map editor for party arenas. Maps are saved as JSON in user://maps (see ArenaMap)
## and show up in Party > Arena. Mouse-driven:
##   1 Ground  2 Plank  3 Start  4 Flag  5 Erase   (or click the tool buttons)
##   Left drag: draw / place     Right click: erase
##   Middle drag or arrow keys: move around     Wheel / + -: zoom
##   Ctrl+Z: undo   Ctrl+S: save   F5: test   Esc: back to the menu

const G := ArenaMap.GRID
const TOOLS := ["block", "plank", "start", "goal", "erase"]
const TOOL_NAMES := {"block": "Ground", "plank": "Plank", "start": "Start", "goal": "Flag", "erase": "Erase"}
const FLAG := preload("res://party/art/flag.webp")
const INK := Color.BLACK
const MINT := Color("b0e2bc")
const GREEN := Color("6cba7c")

var map := ArenaMap.blank()
var tool := "block"
var _drag_from := Vector2.INF
var _panning := false
var _undo: Array = []
var _dirty := false
var _leave_armed := false
var _cam: Camera2D
var _ui: CanvasLayer
var _status: Label
var _name: LineEdit
var _tool_buttons := {}
var _wind: CheckButton
var _meteors: CheckButton
var _loader: PanelContainer


func _ready() -> void:
	_cam = Camera2D.new()
	_cam.zoom = Vector2(0.5, 0.5)
	add_child(_cam)
	_cam.make_current()
	_build_ui()
	if Party.session.has("map") and Party.session.get("editing", false):
		_set_map(ArenaMap.normalize(Party.session.map))  # back from a test run
	else:
		_set_map(ArenaMap.blank())
	_status_text()


func _set_map(m: Dictionary) -> void:
	map = m
	_name.text = map.name
	_wind.set_pressed_no_signal(map.wind)
	_meteors.set_pressed_no_signal(map.meteors)
	_cam.position = ArenaMap.build_area(map).get_center()
	queue_redraw()


# --- UI --------------------------------------------------------------------------------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	var root := Control.new()
	root.theme = UiTheme.make()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)

	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	root.add_child(bar)
	var row := HFlowContainer.new()  # wraps on small windows
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	bar.add_child(row)
	for i in TOOLS.size():
		var t: String = TOOLS[i]
		var b := Button.new()
		b.text = "%d %s" % [i + 1, TOOL_NAMES[t]]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): _select_tool(t))
		row.add_child(b)
		_tool_buttons[t] = b
	row.add_child(VSeparator.new())
	_name = LineEdit.new()
	_name.custom_minimum_size = Vector2(200, 0)
	_name.placeholder_text = "Map name"
	_name.text_changed.connect(func(t): _change(func(): map.name = t.strip_edges().left(40) if t.strip_edges() != "" else "New map"))
	_name.text_submitted.connect(func(_t): _name.release_focus())
	row.add_child(_name)
	_wind = CheckButton.new()
	_wind.text = "Wind"
	_wind.focus_mode = Control.FOCUS_NONE
	_wind.toggled.connect(func(on): _change(func(): map.wind = on))
	row.add_child(_wind)
	_meteors = CheckButton.new()
	_meteors.text = "Meteors"
	_meteors.focus_mode = Control.FOCUS_NONE
	_meteors.toggled.connect(func(on): _change(func(): map.meteors = on))
	row.add_child(_meteors)
	row.add_child(VSeparator.new())
	for spec in [["New", _new_map], ["Load", _open_loader], ["Save", _save], ["Test", _test], ["Exit", _exit]]:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(spec[1])
		row.add_child(b)

	for c in row.get_children():
		c.add_theme_font_size_override("font_size", 20)
	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_left = 16
	_status.offset_top = -40
	_status.add_theme_font_size_override("font_size", 20)
	_status.add_theme_color_override("font_outline_color", UiTheme.MARBLE)
	_status.add_theme_constant_override("outline_size", 6)
	root.add_child(_status)
	_select_tool("block")


func _select_tool(t: String) -> void:
	tool = t
	for k in _tool_buttons:
		_tool_buttons[k].set_pressed_no_signal(k == t)
	_status_text()


func _status_text(extra := "") -> void:
	var p := ArenaMap.problem(map)
	var hint: String = {"block": "Drag to draw ground", "plank": "Drag sideways for a one-way plank",
		"start": "Drag the start area (players spawn here)", "goal": "Click on top of the ground to put the flag",
		"erase": "Click ground or a plank to remove it"}[tool]
	var text: String = hint + "   ·   Right click: erase   Middle drag / arrows: move   Wheel: zoom   Ctrl+Z: undo"
	if p != "":
		text = "! " + p + "   ·   " + text
	if extra != "":
		text = extra + "   ·   " + text
	_status.text = text
	_status.add_theme_color_override("font_color", UiTheme.RED if p != "" else UiTheme.INK)


# --- Editing ----------------------------------------------------------------------------

## Every change goes through here, so it can be undone.
func _change(edit: Callable) -> void:
	_undo.append(map.duplicate(true))
	if _undo.size() > 100:
		_undo.pop_front()
	edit.call()
	_dirty = true
	_leave_armed = false
	queue_redraw()
	_status_text()


func _undo_last() -> void:
	if _undo.is_empty():
		return
	map = _undo.pop_back()
	_set_map(map)
	_status_text("Undone")


func _snap(p: Vector2) -> Vector2:
	return (p / G).round() * G


func _mouse() -> Vector2:
	return get_global_mouse_position()


func _unhandled_input(event: InputEvent) -> void:
	if _loader:
		return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom(1.15)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom(1.0 / 1.15)
			MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					_erase_at(_mouse())
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_press(_mouse())
				else:
					_release(_mouse())
		queue_redraw()
	elif event is InputEventMouseMotion:
		if _panning:
			_cam.position -= event.relative / _cam.zoom
		queue_redraw()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and event.keycode == KEY_Z:
			_undo_last()
		elif event.ctrl_pressed and event.keycode == KEY_S:
			_save()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_5:
			_select_tool(TOOLS[event.keycode - KEY_1])
		elif event.keycode == KEY_F5:
			_test()
		elif event.keycode in [KEY_PLUS, KEY_KP_ADD, KEY_EQUAL]:
			_zoom(1.2)
		elif event.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
			_zoom(1.0 / 1.2)
		elif event.keycode == KEY_ESCAPE:
			_exit()
		else:
			return
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _name.has_focus() or _loader:
		return
	var dir := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if dir != Vector2.ZERO:
		_cam.position += dir * 900.0 * delta / _cam.zoom.x
		queue_redraw()


func _zoom(k: float) -> void:
	var before := _mouse()
	_cam.zoom = (_cam.zoom * k).clamp(Vector2(0.15, 0.15), Vector2(2, 2))
	_cam.position += before - _mouse()  # zoom towards the mouse


func _press(p: Vector2) -> void:
	match tool:
		"block", "plank", "start":
			_drag_from = _snap(p)
		"goal":
			var s := _snap(p)
			_change(func(): map.goal = [int(s.x), int(s.y)])
		"erase":
			_erase_at(p)


func _release(p: Vector2) -> void:
	if _drag_from == Vector2.INF:
		return
	var a := _drag_from
	var b := _snap(p)
	_drag_from = Vector2.INF
	var r := Rect2(a, Vector2.ZERO).expand(b).abs()
	match tool:
		"block":
			r.size = r.size.max(Vector2(G, G))
			_change(func(): map.blocks.append([int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y)]))
		"plank":
			var w := maxf(r.size.x, G * 2)
			_change(func(): map.planks.append([int(r.position.x), int(a.y), int(w)]))
		"start":
			r.size = r.size.max(Vector2(G * 5, G * 3))
			_change(func(): map.start = [int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y)])


func _erase_at(p: Vector2) -> void:
	for i in range(map.planks.size() - 1, -1, -1):
		var pl: Array = map.planks[i]
		if Rect2(pl[0], pl[1] - 8, pl[2], 40).has_point(p):
			_change(func(): map.planks.remove_at(i))
			return
	for i in range(map.blocks.size() - 1, -1, -1):
		if ArenaMap.rect(map.blocks[i]).has_point(p):
			_change(func(): map.blocks.remove_at(i))
			return


# --- Files ---------------------------------------------------------------------------------

func _new_map() -> void:
	_change(func(): pass)
	_set_map(ArenaMap.blank())
	_status_text("New map")


func _save() -> bool:
	var p := ArenaMap.problem(map)
	if p != "":
		_status_text("Not saved: " + p)
		return false
	var path := ArenaMap.save(map)
	_dirty = false
	_status_text("Saved (%s)" % path.get_file())
	return true


func _test() -> void:
	var p := ArenaMap.problem(map)
	if p != "":
		_status_text("Can't test: " + p)
		return
	ArenaMap.save(map)
	_dirty = false
	if GameState.joined.is_empty():
		GameState.join(1)  # someone has to play it
	Party.test_map(map)


func _exit() -> void:
	if _dirty and not _leave_armed:
		_leave_armed = true
		_status_text("Unsaved changes: press Exit / Esc again to leave anyway")
		return
	Party.return_to_editor = false
	GameState.go_to_menu()


func _open_loader() -> void:
	_loader = PanelContainer.new()
	_loader.set_anchors_preset(Control.PRESET_CENTER)
	_loader.offset_left = -260
	_loader.offset_right = 260
	_loader.offset_top = -220
	_loader.offset_bottom = 220
	var col := VBoxContainer.new()
	_loader.add_child(col)
	col.add_child(UiTheme.title("Load a map", 32))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, 320)
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var maps := ArenaMap.list_all()
	if maps.is_empty():
		var l := Label.new()
		l.text = "No maps yet. Save one first!"
		list.add_child(l)
	for m in maps:
		var b := Button.new()
		b.text = m.name + ("  (mod)" if m.mod else "")
		b.pressed.connect(func():
			_change(func(): pass)
			_set_map(ArenaMap.load_file(m.path))
			_close_loader()
			_status_text("Loaded " + m.name))
		list.add_child(b)
	var close := Button.new()
	close.text = "Cancel"
	close.pressed.connect(_close_loader)
	col.add_child(close)
	_ui.get_child(0).add_child(_loader)


func _close_loader() -> void:
	if _loader:
		_loader.queue_free()
		_loader = null


# --- Drawing --------------------------------------------------------------------------------

func _draw() -> void:
	var view := get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_visible_rect()
	# Grid.
	var x0 := floorf(view.position.x / G) * G
	var y0 := floorf(view.position.y / G) * G
	var thin := Color(1, 1, 1, 0.08)
	var x := x0
	while x < view.end.x:
		draw_line(Vector2(x, view.position.y), Vector2(x, view.end.y), Color(1, 1, 1, 0.16) if int(x) % (G * 8) == 0 else thin, 1.0)
		x += G
	var y := y0
	while y < view.end.y:
		draw_line(Vector2(view.position.x, y), Vector2(view.end.x, y), Color(1, 1, 1, 0.16) if int(y) % (G * 8) == 0 else thin, 1.0)
		y += G
	# Build area (where items can be placed).
	draw_rect(ArenaMap.build_area(map), Color(1, 1, 1, 0.35), false, 2.0)
	# Start area.
	var z := ArenaMap.start_zone(map)
	draw_rect(z, Color(GREEN, 0.18))
	draw_rect(z, GREEN, false, 4.0)
	draw_string(UiTheme.FONT_BOLD, z.position + Vector2(10, 30), "START", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, GREEN)
	# Ground and planks, in the game's style.
	for b in map.blocks:
		var r := ArenaMap.rect(b)
		draw_rect(r, Color.WHITE)
		draw_rect(Rect2(r.position, Vector2(r.size.x, minf(9, r.size.y))), MINT)
		draw_rect(r, INK, false, 4.0)
	for p in map.planks:
		var r := Rect2(p[0], p[1], p[2], 24)
		draw_rect(r, Color("f0fff4"))
		draw_rect(r, INK, false, 3.0)
		for k in int(p[2] / 48):
			var c := Vector2(p[0] + 24 + k * 48, p[1] + 12)
			draw_line(c + Vector2(-6, 4), c + Vector2(0, -4), GREEN, 3.0)
			draw_line(c + Vector2(6, 4), c + Vector2(0, -4), GREEN, 3.0)
	# Flag and its no-build zone.
	draw_rect(ArenaMap.goal_zone(map), Color(0.9, 0.31, 0.24, 0.5), false, 2.0)
	draw_texture_rect(FLAG, Rect2(Vector2(map.goal[0] - 40, map.goal[1] - 160), Vector2(80, 160)), false)
	# What's being dragged.
	if _drag_from != Vector2.INF:
		var b := _snap(_mouse())
		var r := Rect2(_drag_from, Vector2.ZERO).expand(b).abs()
		if tool == "plank":
			r = Rect2(Vector2(r.position.x, _drag_from.y), Vector2(maxf(r.size.x, G * 2), 24))
		draw_rect(r, Color(1, 1, 1, 0.4))
		draw_rect(r, INK, false, 2.0)
	# Cursor.
	var m := _snap(_mouse())
	draw_circle(m, 5.0, INK)
	draw_circle(m, 3.0, MINT)
