extends Node2D
## Map editor for party arenas. Maps are saved as JSON in user://maps (see ArenaMap)
## and show up in Party > Arena.
##
## Tools:  V Select   P Ground (click points)   R Box   L Plank   S Start   F Flag
## Select: click an object (Shift: add), drag it to move, drag on empty space to
##         select several. Selected ground shows its points: drag them, drag the
##         small dots between points to add one, right click a point to remove it.
##         Corner handles resize, the middle handle moves.
## Snapping: G toggles the grid, O toggles snapping to other objects' points and edges.
## Also: Delete, Ctrl+D duplicate, Ctrl+A select all, Ctrl+Z / Ctrl+Y undo / redo,
##       arrows nudge, middle drag (or Space + drag) pans, wheel zooms,
##       Ctrl+S save, F5 test, Esc back.

const TOOLS := ["select", "ground", "box", "plank", "start", "flag"]
const TOOL_NAMES := {"select": "Select", "ground": "Ground", "box": "Box", "plank": "Plank", "start": "Start", "flag": "Flag"}
const TOOL_KEYS := {KEY_V: "select", KEY_P: "ground", KEY_R: "box", KEY_L: "plank", KEY_S: "start", KEY_F: "flag"}
const GRIDS := [8, 16, 32, 64]
## Shapes in the palette (drag them onto the map). Points around (0, 0).
const SHAPES := {
	"Box": [[-64, -32], [64, -32], [64, 32], [-64, 32]],
	"Slab": [[-128, -16], [128, -16], [128, 16], [-128, 16]],
	"Pillar": [[-32, -96], [32, -96], [32, 96], [-32, 96]],
	"Ramp up": [[-96, 48], [96, -48], [96, 48]],
	"Ramp down": [[-96, -48], [96, 48], [-96, 48]],
	"Arch": [[-128, -32], [128, -32], [128, 64], [64, 64], [64, 16], [-64, 16], [-64, 64], [-128, 64]],
	"Plank": [],
}
const FLAG := preload("res://party/art/flag.webp")
const INK := Color.BLACK
const MINT := Color("b0e2bc")
const GREEN := Color("6cba7c")
const BLUE := Color("4aa3df")
const RED := Color("e64f3e")
const HANDLE := 7.0   # handle radius, in screen pixels
const SNAP_DIST := 14.0

var map := ArenaMap.blank()
var tool := "select"
var grid_on := true
var grid := 32
var snap_objects := true
## Selected objects: "g3" (ground 3), "p0" (plank 0), "start", "flag".
var selection: Array[String] = []
## Selected points of selected ground: [ground index, point index].
var points_sel: Array = []

var _undo: Array = []
var _redo: Array = []
var _dirty := false
var _leave_armed := false
# Dragging.
var _drag := ""           # "", "move", "points", "scale", "box", "new", "plank_end"
var _drag_from := Vector2.ZERO
var _drag_now := Vector2.ZERO
var _drag_start_map := {}
var _drag_info := {}
var _changed_in_drag := false
var _new_poly: Array = []  # points of the ground being drawn
var _snap_mark := Vector2.INF
var _mouse_world := Vector2.ZERO
# UI.
var _cam: Camera2D
var _ui: CanvasLayer
var _root: Control
var _canvas: Control
var _status: Label
var _name: LineEdit
var _tool_buttons := {}
var _grid_button: CheckButton
var _grid_size: OptionButton
var _obj_button: CheckButton
var _wind: CheckButton
var _meteors: CheckButton
var _list: ItemList
var _info: Label
var _loader: PanelContainer
var _syncing_list := false


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
	_refresh()


func _set_map(m: Dictionary) -> void:
	map = m
	selection.clear()
	points_sel.clear()
	_name.text = map.name
	_wind.set_pressed_no_signal(map.wind)
	_meteors.set_pressed_no_signal(map.meteors)
	_cam.position = ArenaMap.build_area(map).get_center()
	_refresh()


# --- UI ----------------------------------------------------------------------------------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	_root = Control.new()
	_root.theme = _compact_theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_root)

	# The map area: a full-screen control under the panels takes the mouse and drops.
	_canvas = _Canvas.new()
	_canvas.editor = self
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_canvas)

	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_root.add_child(bar)
	var row := HFlowContainer.new()  # wraps on small windows
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	bar.add_child(row)
	for t in TOOLS:
		var key: String = OS.get_keycode_string(TOOL_KEYS.find_key(t))
		var b := _button(row, "%s %s" % [key, TOOL_NAMES[t]], func(): _select_tool(t))
		b.toggle_mode = true
		_tool_buttons[t] = b
	row.add_child(VSeparator.new())
	_grid_button = _check(row, "Grid", grid_on, func(on): grid_on = on; _refresh())
	_grid_size = OptionButton.new()
	_grid_size.focus_mode = Control.FOCUS_NONE
	for g in GRIDS:
		_grid_size.add_item(str(g))
	_grid_size.select(GRIDS.find(grid))
	_grid_size.item_selected.connect(func(i): grid = GRIDS[i]; _refresh())
	row.add_child(_grid_size)
	_obj_button = _check(row, "Snap to objects", snap_objects, func(on): snap_objects = on; _refresh())
	row.add_child(VSeparator.new())
	_name = LineEdit.new()
	_name.custom_minimum_size = Vector2(180, 0)
	_name.placeholder_text = "Map name"
	_name.text_submitted.connect(func(_t): _name.release_focus())
	_name.focus_exited.connect(func(): set_map_name(_name.text))
	row.add_child(_name)
	_wind = _check(row, "Wind", false, func(on): _change(func(): map.wind = on))
	_meteors = _check(row, "Meteors", false, func(on): _change(func(): map.meteors = on))
	row.add_child(VSeparator.new())
	for spec in [["New", _new_map], ["Load", _open_loader], ["Save", _save], ["Test", _test], ["Exit", _exit]]:
		_button(row, spec[0], spec[1])

	# Explorer: the objects in the map, and shapes to drag in.
	var side := PanelContainer.new()
	side.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	side.offset_left = -250
	side.offset_top = 100
	side.offset_bottom = -48
	_root.add_child(side)
	var col := VBoxContainer.new()
	side.add_child(col)
	col.add_child(_small_title("Objects"))
	_list = ItemList.new()
	_list.select_mode = ItemList.SELECT_MULTI
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.focus_mode = Control.FOCUS_NONE
	_list.add_theme_color_override("font_color", UiTheme.INK)
	_list.add_theme_color_override("font_selected_color", UiTheme.INK)
	_list.multi_selected.connect(func(_i, _on): _list_to_selection())
	_list.item_activated.connect(func(i): _focus_on(_list.get_item_metadata(i)))
	col.add_child(_list)
	var actions := HBoxContainer.new()
	col.add_child(actions)
	for spec in [["Copy", _duplicate], ["Delete", _delete], ["Up", func(): _reorder(1)], ["Down", func(): _reorder(-1)]]:
		var b := _button(actions, spec[0], spec[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 14)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_info)
	col.add_child(_small_title("Drag onto the map"))
	var shapes := GridContainer.new()
	shapes.columns = 2
	col.add_child(shapes)
	for s in SHAPES:
		var b := _ShapeButton.new()
		b.shape = s
		b.text = s
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = "Drag me onto the map"
		shapes.add_child(b)

	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_left = 16
	_status.offset_top = -40
	_status.add_theme_font_size_override("font_size", 19)
	_status.add_theme_color_override("font_outline_color", UiTheme.MARBLE)
	_status.add_theme_constant_override("outline_size", 6)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_status)
	_select_tool("select")


## The game's look, but smaller: the editor has lots of buttons.
func _compact_theme() -> Theme:
	var t := UiTheme.make()
	t.default_font_size = 19
	t.set_font_size("font_size", "Button", 19)
	for state in ["normal", "hover", "focus", "pressed", "disabled"]:
		var box: StyleBox = t.get_stylebox(state, "Button").duplicate()
		box.content_margin_left = 9
		box.content_margin_right = 9
		box.content_margin_top = 5
		box.content_margin_bottom = 7
		t.set_stylebox(state, "Button", box)
	var panel: StyleBox = t.get_stylebox("panel", "PanelContainer").duplicate()
	panel.content_margin_left = 10
	panel.content_margin_right = 10
	panel.content_margin_top = 8
	panel.content_margin_bottom = 8
	t.set_stylebox("panel", "PanelContainer", panel)
	return t


func _button(parent: Control, text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(fn)
	parent.add_child(b)
	return b


func _check(parent: Control, text: String, on: bool, fn: Callable) -> CheckButton:
	var b := CheckButton.new()
	b.text = text
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.toggled.connect(fn)
	parent.add_child(b)
	return b


func _small_title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.FONT_BOLD)
	l.add_theme_font_size_override("font_size", 17)
	return l


func _select_tool(t: String) -> void:
	if tool == "ground" and t != "ground":
		_finish_polygon()
	tool = t
	for k in _tool_buttons:
		_tool_buttons[k].set_pressed_no_signal(k == t)
	_refresh()


func set_map_name(text: String) -> void:
	var t := text.strip_edges().left(40)
	if t != "" and t != map.name:
		_change(func(): map.name = t)


## Redraw, refill the explorer, update the status line.
func _refresh(extra := "") -> void:
	_fill_list()
	_status_text(extra)
	queue_redraw()


func _status_text(extra := "") -> void:
	var p := ArenaMap.problem(map)
	var hint: String = {
		"select": "Click to select, drag to move, drag on empty space to select several",
		"ground": "Click to add points; click the first point (or Enter) to finish; Backspace: undo a point",
		"box": "Drag to draw a box of ground",
		"plank": "Drag sideways for a one-way plank",
		"start": "Drag the start area (players spawn here)",
		"flag": "Click on top of the ground to put the flag"}[tool]
	var text: String = hint + "   ·   Grid %s (G)   Snap to objects %s (O)" % ["on" if grid_on else "off", "on" if snap_objects else "off"]
	if p != "":
		text = "! " + p + "   ·   " + text
	if extra != "":
		text = extra + "   ·   " + text
	_status.text = text
	_status.add_theme_color_override("font_color", UiTheme.RED if p != "" else UiTheme.INK)


# --- Explorer ---------------------------------------------------------------------------------

func _object_ids() -> Array[String]:
	var out: Array[String] = ["start", "flag"]
	for i in map.ground.size():
		out.append("g%d" % i)
	for i in map.planks.size():
		out.append("p%d" % i)
	return out


func _object_name(id: String) -> String:
	match id:
		"start":
			return "Start area"
		"flag":
			return "Flag"
	var i := int(id.substr(1))
	if id[0] == "g":
		return "Ground %d  (%d points)" % [i + 1, map.ground[i].size()]
	return "Plank %d  (%d wide)" % [i + 1, map.planks[i][2]]


func _fill_list() -> void:
	if _list == null:
		return
	_syncing_list = true
	_list.clear()
	for id in _object_ids():
		var i := _list.add_item(_object_name(id))
		_list.set_item_metadata(i, id)
		if id in selection:
			_list.select(i, false)
	_syncing_list = false
	if selection.size() == 1:
		var id: String = selection[0]
		var info := _object_name(id)
		if id[0] == "g":
			var r := ArenaMap.poly_rect(map.ground[int(id.substr(1))])
			info += "\n%d × %d at %d, %d" % [r.size.x, r.size.y, r.position.x, r.position.y]
			if not points_sel.is_empty():
				info += "\n%d point%s selected (Delete removes)" % [points_sel.size(), "s" if points_sel.size() > 1 else ""]
		_info.text = info
	elif selection.size() > 1:
		_info.text = "%d objects selected" % selection.size()
	else:
		_info.text = "Nothing selected"


func _list_to_selection() -> void:
	if _syncing_list:
		return
	selection.clear()
	for i in _list.get_selected_items():
		selection.append(_list.get_item_metadata(i))
	points_sel.clear()
	_refresh()


func _focus_on(id: String) -> void:
	_cam.position = _bounds(id).get_center()
	queue_redraw()


# --- Editing (everything goes through _change or _push_undo, for undo) ----------------------------

func _snapshot() -> Dictionary:
	return {"map": map.duplicate(true), "sel": selection.duplicate(), "pts": points_sel.duplicate(true)}


func _restore(s: Dictionary) -> void:
	map = s.map
	selection.assign(s.sel)
	points_sel = s.pts
	_name.text = map.name
	_wind.set_pressed_no_signal(map.wind)
	_meteors.set_pressed_no_signal(map.meteors)


func _push_undo(snap_now := {}) -> void:
	_undo.append(_snapshot() if snap_now.is_empty() else snap_now)
	if _undo.size() > 200:
		_undo.pop_front()
	_redo.clear()
	_dirty = true
	_leave_armed = false


func _change(edit: Callable) -> void:
	_push_undo()
	edit.call()
	_refresh()


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(_snapshot())
	_restore(_undo.pop_back())
	_refresh("Undone")


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(_snapshot())
	_restore(_redo.pop_back())
	_refresh("Redone")


func _delete() -> void:
	if not points_sel.is_empty():
		_delete_points()
		return
	var ids := selection.filter(func(id): return id != "start" and id != "flag")
	if ids.is_empty():
		return
	_change(func():
		_remove_objects(ids)
		selection.clear())


func _remove_objects(ids: Array) -> void:
	var gs := []
	var ps := []
	for id in ids:
		if id[0] == "g":
			gs.append(int(id.substr(1)))
		elif id[0] == "p":
			ps.append(int(id.substr(1)))
	gs.sort()
	ps.sort()
	for k in range(gs.size() - 1, -1, -1):
		map.ground.remove_at(gs[k])
	for k in range(ps.size() - 1, -1, -1):
		map.planks.remove_at(ps[k])


func _delete_points() -> void:
	var by_poly := {}
	for ps in points_sel:
		if not by_poly.has(ps[0]):
			by_poly[ps[0]] = []
		by_poly[ps[0]].append(ps[1])
	for g in by_poly:
		if map.ground[g].size() - by_poly[g].size() < 3:
			_refresh("Ground needs at least 3 points")
			return
	_change(func():
		for g in by_poly:
			var idx: Array = by_poly[g]
			idx.sort()
			for k in range(idx.size() - 1, -1, -1):
				map.ground[g].remove_at(idx[k])
		points_sel.clear())


func _duplicate() -> void:
	var ids := selection.filter(func(id): return id[0] == "g" or id[0] == "p")
	if ids.is_empty():
		return
	_change(func():
		var off := grid * 2
		var new_sel: Array[String] = []
		for id in ids:
			var i := int(id.substr(1))
			if id[0] == "g":
				map.ground.append(map.ground[i].map(func(p): return [p[0] + off, p[1] + off]))
				new_sel.append("g%d" % (map.ground.size() - 1))
			else:
				var pl: Array = map.planks[i]
				map.planks.append([pl[0] + off, pl[1] + off, pl[2]])
				new_sel.append("p%d" % (map.planks.size() - 1))
		selection = new_sel
		points_sel.clear())


## Draw order of ground: later ones are drawn on top.
func _reorder(step: int) -> void:
	if selection.size() != 1 or selection[0][0] != "g":
		return
	var i := int(selection[0].substr(1))
	var j := clampi(i + step, 0, map.ground.size() - 1)
	if i == j:
		return
	_change(func():
		var poly = map.ground[i]
		map.ground.remove_at(i)
		map.ground.insert(j, poly)
		selection.assign(["g%d" % j]))


func select_all() -> void:
	selection.assign(_object_ids())
	points_sel.clear()
	_refresh()


# --- Geometry helpers -----------------------------------------------------------------------------

func _bounds(id: String, m := {}) -> Rect2:
	if m.is_empty():
		m = map
	match id:
		"start":
			return ArenaMap.start_zone(m)
		"flag":
			return Rect2(m.goal[0] - 40, m.goal[1] - 160, 80, 160)
	var i := int(id.substr(1))
	if id[0] == "g":
		return ArenaMap.poly_rect(m.ground[i])
	return ArenaMap.plank_rect(m.planks[i])


func _selection_bounds() -> Rect2:
	var r := Rect2()
	var first := true
	for id in selection:
		var b := _bounds(id)
		r = b if first else r.merge(b)
		first = false
	return r


## The object under `p` (topmost first), or "".
func hit(p: Vector2) -> String:
	if Rect2(map.goal[0] - 40, map.goal[1] - 160, 80, 160).has_point(p):
		return "flag"
	for i in range(map.planks.size() - 1, -1, -1):
		if ArenaMap.plank_rect(map.planks[i]).grow(6).has_point(p):
			return "p%d" % i
	for i in range(map.ground.size() - 1, -1, -1):
		if Geometry2D.is_point_in_polygon(p, ArenaMap.points(map.ground[i])):
			return "g%d" % i
	if ArenaMap.start_zone(map).has_point(p):
		return "start"
	return ""


func _handle_r() -> float:
	return HANDLE / _cam.zoom.x


## Grid and object snapping. `skip` = what's being moved (don't snap to itself).
func snap(p: Vector2, skip := {}) -> Vector2:
	_snap_mark = Vector2.INF
	if snap_objects:
		var best := SNAP_DIST / _cam.zoom.x
		var found := Vector2.INF
		for q in _snap_points(skip):
			var d := p.distance_to(q)
			if d < best:
				best = d
				found = q
		if found == Vector2.INF:
			# Onto an edge (ground sides, plank tops).
			for e in _snap_edges(skip):
				var q := Geometry2D.get_closest_point_to_segment(p, e[0], e[1])
				var d := p.distance_to(q)
				if d < best:
					best = d
					found = q
		if found != Vector2.INF:
			_snap_mark = found
			return found.round()
	if grid_on:
		return (p / grid).round() * grid
	return p.round()


func _snap_points(skip: Dictionary) -> Array:
	var out := []
	for g in map.ground.size():
		if skip.has("g%d" % g):
			continue
		for k in map.ground[g].size():
			if not skip.has("%d:%d" % [g, k]):
				out.append(Vector2(map.ground[g][k][0], map.ground[g][k][1]))
	for i in map.planks.size():
		if skip.has("p%d" % i):
			continue
		var r := ArenaMap.plank_rect(map.planks[i])
		out.append(r.position)
		out.append(Vector2(r.end.x, r.position.y))
	if not skip.has("start"):
		var z := ArenaMap.start_zone(map)
		out.append_array([z.position, Vector2(z.end.x, z.position.y), z.end, Vector2(z.position.x, z.end.y)])
	return out


func _snap_edges(skip: Dictionary) -> Array:
	var out := []
	for g in map.ground.size():
		if skip.has("g%d" % g):
			continue
		var pts := ArenaMap.points(map.ground[g])
		for k in pts.size():
			if skip.has("%d:%d" % [g, k]) or skip.has("%d:%d" % [g, (k + 1) % pts.size()]):
				continue
			out.append([pts[k], pts[(k + 1) % pts.size()]])
	for i in map.planks.size():
		if not skip.has("p%d" % i):
			var r := ArenaMap.plank_rect(map.planks[i])
			out.append([r.position, Vector2(r.end.x, r.position.y)])
	return out


## Handles of the current selection: [{kind, pos, ...}].
func handles() -> Array:
	var out := []
	if tool != "select" or selection.is_empty():
		return out
	for id in selection:
		if id[0] == "g":
			var g := int(id.substr(1))
			var pts := ArenaMap.points(map.ground[g])
			for k in pts.size():
				out.append({"kind": "point", "pos": pts[k], "g": g, "k": k})
				out.append({"kind": "insert", "pos": (pts[k] + pts[(k + 1) % pts.size()]) / 2.0, "g": g, "k": k + 1})
		elif id[0] == "p" and selection.size() == 1:
			var r := ArenaMap.plank_rect(map.planks[int(id.substr(1))])
			out.append({"kind": "plank_end", "pos": Vector2(r.position.x, r.get_center().y), "side": -1})
			out.append({"kind": "plank_end", "pos": Vector2(r.end.x, r.get_center().y), "side": 1})
	var b := _selection_bounds()
	var scalable := selection.any(func(id): return id[0] == "g" or id == "start")
	if scalable:
		var corners := [b.position, Vector2(b.end.x, b.position.y), b.end, Vector2(b.position.x, b.end.y)]
		for k in 4:
			out.append({"kind": "scale", "pos": corners[k], "anchor": corners[(k + 2) % 4]})
	out.append({"kind": "move", "pos": b.get_center()})
	return out


func _handle_at(p: Vector2) -> Dictionary:
	var r := _handle_r() * 1.4
	var best := {}
	var best_d := r
	for h in handles():
		var d: float = p.distance_to(h.pos)
		var bias := 0.0 if h.kind == "point" else 0.5  # points win over handles on top of them
		if d + bias < best_d:
			best_d = d + bias
			best = h
	return best


# --- Mouse (world positions; tests call these directly) ------------------------------------------

func to_world(screen: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen


func on_press(w: Vector2, shift := false) -> void:
	_drag_from = w
	_drag_now = w
	_mouse_world = w
	_drag_start_map = _snapshot()
	_changed_in_drag = false
	_drag_info = {}
	match tool:
		"select":
			_press_select(w, shift)
		"ground":
			var p := snap(w)
			if _new_poly.size() >= 3 and p.distance_to(Vector2(_new_poly[0][0], _new_poly[0][1])) < _handle_r() * 2:
				_finish_polygon()
			else:
				_new_poly.append([int(p.x), int(p.y)])
		"box", "plank", "start":
			_drag = "new"
			_drag_from = snap(w)
		"flag":
			var p := snap(w)
			_change(func(): map.goal = [int(p.x), int(p.y)])
	_refresh()


func _press_select(w: Vector2, shift: bool) -> void:
	var h := _handle_at(w)
	if not h.is_empty():
		match h.kind:
			"point":
				var key := [h.g, h.k]
				if not _has_point(key):
					if not shift:
						points_sel.clear()
					points_sel.append(key)
				_drag = "points"
			"insert":
				_push_undo()
				_changed_in_drag = true
				map.ground[h.g].insert(h.k, [int(h.pos.x), int(h.pos.y)])
				points_sel = [[h.g, h.k]]
				_drag = "points"
			"scale":
				_drag = "scale"
				_drag_info = {"anchor": h.anchor, "corner": h.pos}
			"move":
				_drag = "move"
			"plank_end":
				_drag = "plank_end"
				_drag_info = {"side": h.side}
		return
	var id := hit(w)
	if id == "":
		_drag = "box"  # (the selection changes when the box is let go)
		return
	if shift:
		if id in selection:
			selection.erase(id)
		else:
			selection.append(id)
	elif not id in selection:
		selection.assign([id])
	points_sel.clear()
	_drag = "move"


func _has_point(key: Array) -> bool:
	for ps in points_sel:
		if ps[0] == key[0] and ps[1] == key[1]:
			return true
	return false


func on_drag(w: Vector2) -> void:
	_mouse_world = w
	_drag_now = w
	if _drag in ["", "box", "new"]:
		if tool != "select":
			snap(w)
		queue_redraw()
		return
	if _drag == "move" and selection.is_empty():
		return
	if not _changed_in_drag:
		_push_undo(_drag_start_map)
		_changed_in_drag = true
	if not _drag_info.has("base"):
		_drag_info.base = map.duplicate(true)  # (after a point was added, for "insert")
	var base: Dictionary = _drag_info.base
	match _drag:
		"move":
			# Snap the selection's corner, move everything by the same amount.
			var skip := {}
			for id in selection:
				skip[id] = true
			var ref := _bounds(selection[0], base).position
			var delta := snap(ref + (w - _drag_from), skip) - ref
			map = base.duplicate(true)
			for id in selection:
				_move_object(id, delta)
		"points":
			var skip := {}
			for ps in points_sel:
				skip["%d:%d" % [ps[0], ps[1]]] = true
			var first: Array = points_sel[0]
			var ref := Vector2(base.ground[first[0]][first[1]][0], base.ground[first[0]][first[1]][1])
			var delta := snap(ref + (w - _drag_from), skip) - ref
			map = base.duplicate(true)
			for ps in points_sel:
				var pt: Array = map.ground[ps[0]][ps[1]]
				map.ground[ps[0]][ps[1]] = [int(pt[0] + delta.x), int(pt[1] + delta.y)]
		"scale":
			var anchor: Vector2 = _drag_info.anchor
			var corner: Vector2 = _drag_info.corner
			var to := snap(w)
			var k := Vector2(
				(to.x - anchor.x) / (corner.x - anchor.x) if absf(corner.x - anchor.x) > 1 else 1.0,
				(to.y - anchor.y) / (corner.y - anchor.y) if absf(corner.y - anchor.y) > 1 else 1.0)
			if absf(k.x) < 0.05 or absf(k.y) < 0.05:
				return
			map = base.duplicate(true)
			for id in selection:
				_scale_object(id, anchor, k)
		"plank_end":
			var i := int(selection[0].substr(1))
			var pl: Array = base.planks[i]
			var x := snap(w, {selection[0]: true}).x
			map = base.duplicate(true)
			if _drag_info.side < 0:
				var right: int = pl[0] + pl[2]
				var left := mini(int(x), right - 32)
				map.planks[i] = [left, pl[1], right - left]
			else:
				map.planks[i] = [pl[0], pl[1], maxi(32, int(x) - pl[0])]
	_refresh()


func _move_object(id: String, d: Vector2) -> void:
	match id:
		"start":
			map.start = [int(map.start[0] + d.x), int(map.start[1] + d.y), map.start[2], map.start[3]]
		"flag":
			map.goal = [int(map.goal[0] + d.x), int(map.goal[1] + d.y)]
		_:
			var i := int(id.substr(1))
			if id[0] == "g":
				map.ground[i] = map.ground[i].map(func(p): return [int(p[0] + d.x), int(p[1] + d.y)])
			else:
				var pl: Array = map.planks[i]
				map.planks[i] = [int(pl[0] + d.x), int(pl[1] + d.y), pl[2]]


func _scale_object(id: String, anchor: Vector2, k: Vector2) -> void:
	var f := func(p: Vector2) -> Vector2: return (anchor + (p - anchor) * k).round()
	if id[0] == "g":
		var i := int(id.substr(1))
		var pts: Array = map.ground[i].map(func(p):
			var q: Vector2 = f.call(Vector2(p[0], p[1]))
			return [int(q.x), int(q.y)])
		if k.x * k.y < 0:
			pts.reverse()  # mirrored: keep the points going the same way round
		map.ground[i] = pts
	elif id == "start":
		var a: Vector2 = f.call(Vector2(map.start[0], map.start[1]))
		var b: Vector2 = f.call(Vector2(map.start[0] + map.start[2], map.start[1] + map.start[3]))
		var r := Rect2(a, Vector2.ZERO).expand(b)
		map.start = [int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y)]
	elif id == "flag":
		var q: Vector2 = f.call(Vector2(map.goal[0], map.goal[1]))
		map.goal = [int(q.x), int(q.y)]
	elif id[0] == "p":
		var i := int(id.substr(1))
		var a: Vector2 = f.call(Vector2(map.planks[i][0], map.planks[i][1]))
		var b: Vector2 = f.call(Vector2(map.planks[i][0] + map.planks[i][2], map.planks[i][1]))
		map.planks[i] = [int(minf(a.x, b.x)), int(a.y), maxi(32, int(absf(b.x - a.x)))]


func on_release(w: Vector2, shift := false) -> void:
	match _drag:
		"box":
			_box_select(Rect2(_drag_from, Vector2.ZERO).expand(w).abs(), shift)
		"new":
			var a := _drag_from
			var b := snap(w)
			var r := Rect2(a, Vector2.ZERO).expand(b).abs()
			match tool:
				"box":
					r.size = r.size.max(Vector2(grid, grid))
					_change(func():
						map.ground.append(ArenaMap._box(int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y)))
						selection.assign(["g%d" % (map.ground.size() - 1)]))
				"plank":
					var wdt := maxf(r.size.x, 64)
					_change(func():
						map.planks.append([int(r.position.x), int(a.y), int(wdt)])
						selection.assign(["p%d" % (map.planks.size() - 1)]))
				"start":
					r.size = r.size.max(Vector2(160, 96))
					_change(func(): map.start = [int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y)])
	_drag = ""
	_drag_info = {}
	_snap_mark = Vector2.INF
	_refresh()


## Box selection: points of the selected ground if the box catches any, else objects.
func _box_select(r: Rect2, add: bool) -> void:
	if r.size.length() < 4:
		if not add:
			selection.clear()  # a click on empty space
			points_sel.clear()
		return
	var pts: Array = []
	for id in selection:
		if id[0] == "g":
			var g := int(id.substr(1))
			for k in map.ground[g].size():
				if r.has_point(Vector2(map.ground[g][k][0], map.ground[g][k][1])):
					pts.append([g, k])
	if not pts.is_empty():
		points_sel = pts
		return
	if not add:
		selection.clear()
	for id in _object_ids():
		if r.intersects(_bounds(id)) and not id in selection:
			if id == "start" and not r.encloses(_bounds(id)):
				continue  # the start area is big: only when it's all inside
			selection.append(id)
	points_sel.clear()


func on_right_click(w: Vector2) -> void:
	if tool == "ground" and not _new_poly.is_empty():
		_new_poly.pop_back()
		queue_redraw()
		return
	var h := _handle_at(w)
	if not h.is_empty() and h.kind == "point":
		points_sel = [[h.g, h.k]]
		_delete_points()
		return
	var id := hit(w)
	if id != "" and id != "start" and id != "flag":
		selection.assign([id])
		points_sel.clear()
		_delete()


func _finish_polygon() -> void:
	if _new_poly.size() >= 3:
		var poly := _new_poly.duplicate()
		_change(func():
			map.ground.append(poly)
			selection.assign(["g%d" % (map.ground.size() - 1)]))
	_new_poly.clear()
	queue_redraw()


## A shape from the palette was dropped on the map.
func drop_shape(shape: String, w: Vector2) -> void:
	var at := snap(w)
	if shape == "Plank":
		_change(func():
			map.planks.append([int(at.x - 80), int(at.y), 160])
			selection.assign(["p%d" % (map.planks.size() - 1)]))
	else:
		var pts: Array = SHAPES[shape].map(func(p): return [int(at.x + p[0]), int(at.y + p[1])])
		_change(func():
			map.ground.append(pts)
			selection.assign(["g%d" % (map.ground.size() - 1)]))
	points_sel.clear()
	_select_tool("select")


func zoom_at(k: float, screen: Vector2) -> void:
	var before := to_world(screen)
	_cam.zoom = (_cam.zoom * k).clamp(Vector2(0.12, 0.12), Vector2(3, 3))
	_cam.force_update_scroll()
	_cam.position += before - to_world(screen)
	queue_redraw()


func pan(screen_delta: Vector2) -> void:
	_cam.position -= screen_delta / _cam.zoom
	queue_redraw()


# --- Keys -------------------------------------------------------------------------------------

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or _loader or _name.has_focus():
		return
	if key(event.keycode, event.ctrl_pressed or event.meta_pressed, event.shift_pressed):
		get_viewport().set_input_as_handled()


## Keyboard shortcuts. Returns true if the key did something.
func key(k: Key, ctrl := false, shift := false) -> bool:
	if ctrl and k == KEY_Z:
		redo() if shift else undo()
	elif ctrl and k == KEY_Y:
		redo()
	elif ctrl and k == KEY_S:
		_save()
	elif ctrl and k == KEY_D:
		_duplicate()
	elif ctrl and k == KEY_A:
		select_all()
	elif k in [KEY_DELETE, KEY_BACKSPACE] and tool == "ground" and not _new_poly.is_empty():
		_new_poly.pop_back()
		queue_redraw()
	elif k in [KEY_DELETE, KEY_BACKSPACE]:
		_delete()
	elif k in [KEY_ENTER, KEY_KP_ENTER] and tool == "ground":
		_finish_polygon()
	elif not ctrl and TOOL_KEYS.has(k):
		_select_tool(TOOL_KEYS[k])
	elif k == KEY_G:
		grid_on = not grid_on
		_grid_button.set_pressed_no_signal(grid_on)
		_refresh()
	elif k == KEY_O:
		snap_objects = not snap_objects
		_obj_button.set_pressed_no_signal(snap_objects)
		_refresh()
	elif k == KEY_F5:
		_test()
	elif k in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN] and not selection.is_empty():
		var d := Vector2(int(k == KEY_RIGHT) - int(k == KEY_LEFT), int(k == KEY_DOWN) - int(k == KEY_UP)) * (grid if grid_on else 1)
		_change(func():
			if points_sel.is_empty():
				for id in selection:
					_move_object(id, d)
			else:
				for ps in points_sel:
					var pt: Array = map.ground[ps[0]][ps[1]]
					map.ground[ps[0]][ps[1]] = [int(pt[0] + d.x), int(pt[1] + d.y)])
	elif k in [KEY_PLUS, KEY_KP_ADD, KEY_EQUAL]:
		zoom_at(1.2, get_viewport().get_visible_rect().get_center())
	elif k in [KEY_MINUS, KEY_KP_SUBTRACT]:
		zoom_at(1.0 / 1.2, get_viewport().get_visible_rect().get_center())
	elif k == KEY_ESCAPE:
		if tool == "ground" and not _new_poly.is_empty():
			_new_poly.clear()
			queue_redraw()
		elif not selection.is_empty():
			selection.clear()
			points_sel.clear()
			_refresh()
		else:
			_exit()
	else:
		return false
	return true


func _process(delta: float) -> void:
	if _name.has_focus() or _loader or not selection.is_empty():
		return
	var dir := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if dir != Vector2.ZERO:
		_cam.position += dir * 900.0 * delta / _cam.zoom.x
		queue_redraw()


# --- Files ---------------------------------------------------------------------------------------

func _new_map() -> void:
	_push_undo()
	_set_map(ArenaMap.blank())
	_refresh("New map")


func _save() -> bool:
	var p := ArenaMap.problem(map)
	if p != "":
		_refresh("Not saved: " + p)
		return false
	var path := ArenaMap.save(map)
	_dirty = false
	_refresh("Saved (%s)" % path.get_file())
	return true


func _test() -> void:
	var p := ArenaMap.problem(map)
	if p != "":
		_refresh("Can't test: " + p)
		return
	ArenaMap.save(map)
	_dirty = false
	if GameState.joined.is_empty():
		GameState.join(1)  # someone has to play it
	Party.test_map(map)


func _exit() -> void:
	if _dirty and not _leave_armed:
		_leave_armed = true
		_refresh("Unsaved changes: press Exit / Esc again to leave anyway")
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
			_push_undo()
			_set_map(ArenaMap.load_file(m.path))
			_close_loader()
			_refresh("Loaded " + m.name))
		list.add_child(b)
	var close := Button.new()
	close.text = "Cancel"
	close.pressed.connect(_close_loader)
	col.add_child(close)
	_root.add_child(_loader)


func _close_loader() -> void:
	if _loader:
		_loader.queue_free()
		_loader = null


# --- Drawing -----------------------------------------------------------------------------------------

func _draw() -> void:
	var px := 1.0 / _cam.zoom.x  # one screen pixel
	var view := get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_visible_rect()
	# Grid.
	if grid_on:
		var step := float(grid)
		while step * _cam.zoom.x < 8.0:
			step *= 2.0
		var x := floorf(view.position.x / step) * step
		while x < view.end.x:
			draw_line(Vector2(x, view.position.y), Vector2(x, view.end.y), Color(1, 1, 1, 0.18 if int(x) % 256 == 0 else 0.07), px)
			x += step
		var y := floorf(view.position.y / step) * step
		while y < view.end.y:
			draw_line(Vector2(view.position.x, y), Vector2(view.end.x, y), Color(1, 1, 1, 0.18 if int(y) % 256 == 0 else 0.07), px)
			y += step
	# Build area.
	draw_rect(ArenaMap.build_area(map), Color(1, 1, 1, 0.35), false, 2.0 * px)
	# Start area.
	var z := ArenaMap.start_zone(map)
	draw_rect(z, Color(GREEN, 0.18))
	draw_rect(z, GREEN, false, 4.0)
	draw_string(UiTheme.FONT_BOLD, z.position + Vector2(10, 30), "START", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, GREEN)
	# Ground, in the game's style (mint cap on top-facing edges). Red outline: crosses itself.
	for g in map.ground.size():
		var pts := ArenaMap.points(map.ground[g])
		var ok := not Geometry2D.triangulate_polygon(pts).is_empty()
		if ok:
			draw_colored_polygon(pts, Color.WHITE)
		for k in pts.size():
			var a := pts[k]
			var b := pts[(k + 1) % pts.size()]
			var d := b - a
			if absf(d.y) <= absf(d.x) * 0.35 and absf(d.x) >= 4.0:
				var mid := (a + b) / 2.0
				if Geometry2D.is_point_in_polygon(mid + Vector2(0, 4), pts) and not Geometry2D.is_point_in_polygon(mid - Vector2(0, 4), pts):
					draw_colored_polygon(PackedVector2Array([a, b, b + Vector2(0, 9), a + Vector2(0, 9)]), MINT)
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, INK if ok else RED, 4.0)
	for p in map.planks:
		var r := ArenaMap.plank_rect(p)
		draw_rect(r, Color("f0fff4"))
		draw_rect(r, INK, false, 3.0)
		for k in int(p[2] / 48):
			var c := Vector2(p[0] + 24 + k * 48, p[1] + 12)
			draw_line(c + Vector2(-6, 4), c + Vector2(0, -4), GREEN, 3.0)
			draw_line(c + Vector2(6, 4), c + Vector2(0, -4), GREEN, 3.0)
	# Flag and its no-build zone.
	draw_rect(ArenaMap.goal_zone(map), Color(RED, 0.5), false, 2.0 * px)
	draw_texture_rect(FLAG, Rect2(Vector2(map.goal[0] - 40, map.goal[1] - 160), Vector2(80, 160)), false)
	# Selection outline and handles.
	for id in selection:
		if id[0] == "g":
			var pts := ArenaMap.points(map.ground[int(id.substr(1))])
			pts.append(pts[0])
			draw_polyline(pts, BLUE, 3.0 * px)
		else:
			draw_rect(_bounds(id).grow(3 * px), BLUE, false, 3.0 * px)
	if not selection.is_empty() and tool == "select":
		draw_rect(_selection_bounds(), Color(BLUE, 0.6), false, px)
		var hr := _handle_r()
		var order := ["scale", "move", "insert", "plank_end", "point"]  # points on top
		var hs := handles()
		hs.sort_custom(func(a, b): return order.find(a.kind) < order.find(b.kind))
		for h in hs:
			match h.kind:
				"point":
					var box := Rect2(h.pos - Vector2(hr, hr), Vector2(hr, hr) * 2)
					draw_rect(box, BLUE if _has_point([h.g, h.k]) else Color.WHITE)
					draw_rect(box, INK, false, 2.0 * px)
				"insert":
					draw_circle(h.pos, hr * 0.55, Color(BLUE, 0.7))
				"scale":
					var box := Rect2(h.pos - Vector2(hr, hr) * 0.8, Vector2(hr, hr) * 1.6)
					draw_rect(box, Color.WHITE)
					draw_rect(box, BLUE, false, 2.0 * px)
				"plank_end":
					draw_circle(h.pos, hr, Color.WHITE)
					draw_arc(h.pos, hr, 0, TAU, 16, BLUE, 2.0 * px)
				"move":
					draw_circle(h.pos, hr * 1.4, Color(BLUE, 0.85))
					for dir in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
						draw_line(h.pos, h.pos + dir * hr * 1.1, Color.WHITE, 2.0 * px)
	# Box selection.
	if _drag == "box":
		var r := Rect2(_drag_from, Vector2.ZERO).expand(_drag_now).abs()
		draw_rect(r, Color(BLUE, 0.12))
		draw_rect(r, BLUE, false, px)
	# Shapes being drawn.
	if _drag == "new":
		var r := Rect2(_drag_from, Vector2.ZERO).expand(snap(_drag_now)).abs()
		if tool == "plank":
			r = Rect2(Vector2(r.position.x, _drag_from.y), Vector2(maxf(r.size.x, 64), 24))
		draw_rect(r, Color(1, 1, 1, 0.4))
		draw_rect(r, INK, false, 2.0 * px)
	if tool == "ground" and not _new_poly.is_empty():
		var pts := PackedVector2Array()
		for p in _new_poly:
			pts.append(Vector2(p[0], p[1]))
		pts.append(snap(_mouse_world))
		draw_polyline(pts, BLUE, 3.0 * px)
		for p in pts:
			draw_circle(p, _handle_r() * 0.7, BLUE)
		draw_arc(pts[0], _handle_r() * 2, 0, TAU, 20, BLUE, 2.0 * px)
	# Snap marker and cursor.
	if _snap_mark != Vector2.INF:
		draw_arc(_snap_mark, _handle_r() * 1.6, 0, TAU, 20, Color("ffd65a"), 3.0 * px)
	if tool != "select":
		draw_circle(snap(_mouse_world), 4 * px, INK)


# --- Inner classes ---------------------------------------------------------------------------------

## The map area: passes the mouse to the editor and takes shapes dropped from the palette.
class _Canvas extends Control:
	var editor: Node
	var _pressed := false
	var _panning := false

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var w: Vector2 = editor.to_world(event.position)
			match event.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					if event.pressed:
						editor.zoom_at(1.15, event.position)
				MOUSE_BUTTON_WHEEL_DOWN:
					if event.pressed:
						editor.zoom_at(1.0 / 1.15, event.position)
				MOUSE_BUTTON_MIDDLE:
					_panning = event.pressed
				MOUSE_BUTTON_RIGHT:
					if event.pressed:
						editor.on_right_click(w)
				MOUSE_BUTTON_LEFT:
					if event.pressed and event.double_click and editor.tool == "ground":
						editor._finish_polygon()
					elif event.pressed:
						_pressed = true
						editor.on_press(w, event.shift_pressed)
					elif _pressed:
						_pressed = false
						editor.on_release(w, event.shift_pressed)
			accept_event()
		elif event is InputEventMouseMotion:
			if _panning or (event.button_mask & MOUSE_BUTTON_MASK_LEFT and Input.is_key_pressed(KEY_SPACE)):
				editor.pan(event.relative)
			else:
				editor.on_drag(editor.to_world(event.position))
			accept_event()

	func _can_drop_data(_pos: Vector2, data) -> bool:
		return data is Dictionary and data.has("shape")

	func _drop_data(pos: Vector2, data) -> void:
		editor.drop_shape(data.shape, editor.to_world(pos))


## A palette button you drag onto the map.
class _ShapeButton extends Button:
	var shape := ""

	func _get_drag_data(_pos: Vector2):
		var l := Label.new()
		l.text = shape
		l.add_theme_font_size_override("font_size", 20)
		set_drag_preview(l)
		return {"shape": shape}
