class_name Inspector
extends PanelContainer
## In-game inspector (console "inspect"): the scene's nodes on top, the selected
## node's properties below, editable while the game runs (a bit like Godot's
## editor). "Pick" then a click in the game selects what's under the mouse.

const KINDS := [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_COLOR]

var node: Node
var _tree: Tree
var _props: VBoxContainer
var _title: Label
var _picking := false
var _filter: LineEdit
var _editors := {}   # property -> [control, kind]


func _ready() -> void:
	theme = UiTheme.make()
	set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	offset_left = -420
	offset_top = 250
	offset_bottom = -10
	self_modulate.a = 0.92
	var col := VBoxContainer.new()
	add_child(col)
	var top := HBoxContainer.new()
	col.add_child(top)
	_title = Label.new()
	_title.text = "Inspector"
	_title.add_theme_font_override("font", UiTheme.FONT_BOLD)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	top.add_child(_title)
	for spec in [["Pick", func(): _picking = true; _title.text = "Click something in the game..."],
			["Refresh", refresh], ["Close", queue_free]]:
		var b := Button.new()
		b.text = spec[0]
		b.add_theme_font_size_override("font_size", 16)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(spec[1])
		top.add_child(b)
	_tree = Tree.new()
	_tree.custom_minimum_size = Vector2(0, 200)
	_tree.add_theme_font_size_override("font_size", 15)
	_tree.item_selected.connect(func(): select(_tree.get_selected().get_metadata(0)))
	col.add_child(_tree)
	_filter = LineEdit.new()
	_filter.placeholder_text = "Filter properties"
	_filter.add_theme_font_size_override("font_size", 15)
	_filter.text_changed.connect(func(_t): _fill_props())
	col.add_child(_filter)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_props = VBoxContainer.new()
	_props.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_props)
	refresh()


## Rebuilds the node tree (the scene can change under us).
func refresh() -> void:
	_tree.clear()
	var scene := get_tree().current_scene
	if scene == null:
		return
	var root := _tree.create_item()
	_add(scene, root, 0)
	if not is_instance_valid(node):
		select(scene)


func _add(n: Node, item: TreeItem, depth: int) -> void:
	item.set_text(0, "%s  (%s)" % [n.name, n.get_class()])
	item.set_metadata(0, n)
	if n == node:
		item.select(0)
	item.collapsed = depth >= 1
	for c in n.get_children():
		if c is CanvasLayer and depth == 0 and c.name.begins_with("@"):
			continue
		_add(c, _tree.create_item(item), depth + 1)


func select(n: Node) -> void:
	if not is_instance_valid(n):
		return
	node = n
	_title.text = str(n.get_path()).trim_prefix("/root/")
	_fill_props()


## One row per property we can edit: script variables first, then the node's own.
func _fill_props() -> void:
	for c in _props.get_children():
		c.queue_free()
	_editors.clear()
	if not is_instance_valid(node):
		return
	var props := node.get_property_list()
	var script_props := props.filter(func(p): return p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE)
	var own := props.filter(func(p): return p.usage & PROPERTY_USAGE_EDITOR and not p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE)
	for p in script_props + own:
		if not p.type in KINDS or p.name.begins_with("_"):
			continue
		if _filter.text != "" and not p.name.to_lower().contains(_filter.text.to_lower()):
			continue
		_row(p.name, p.type)


func _row(prop: String, kind: int) -> void:
	var row := HBoxContainer.new()
	_props.add_child(row)
	var l := Label.new()
	l.text = prop
	l.custom_minimum_size = Vector2(150, 0)
	l.clip_text = true
	l.add_theme_font_size_override("font_size", 15)
	row.add_child(l)
	var v = node.get(prop)
	var ed: Control
	match kind:
		TYPE_BOOL:
			var cb := CheckBox.new()
			cb.button_pressed = v
			cb.toggled.connect(func(on): _apply(prop, on))
			ed = cb
		TYPE_INT, TYPE_FLOAT:
			var sp := SpinBox.new()
			sp.allow_greater = true
			sp.allow_lesser = true
			sp.step = 1.0 if kind == TYPE_INT else 0.01
			sp.value = v
			sp.value_changed.connect(func(x): _apply(prop, int(x) if kind == TYPE_INT else x))
			ed = sp
		TYPE_STRING, TYPE_STRING_NAME:
			var le := LineEdit.new()
			le.text = str(v)
			le.text_submitted.connect(func(t): _apply(prop, t))
			ed = le
		TYPE_VECTOR2, TYPE_VECTOR2I:
			var box := HBoxContainer.new()
			var xs := SpinBox.new()
			var ys := SpinBox.new()
			for sp in [xs, ys]:
				sp.allow_greater = true
				sp.allow_lesser = true
				sp.step = 1.0 if kind == TYPE_VECTOR2I else 0.1
				sp.custom_minimum_size = Vector2(110, 0)
				box.add_child(sp)
			xs.value = v.x
			ys.value = v.y
			var apply := func(_x): _apply(prop, Vector2i(xs.value, ys.value) if kind == TYPE_VECTOR2I else Vector2(xs.value, ys.value))
			xs.value_changed.connect(apply)
			ys.value_changed.connect(apply)
			ed = box
		TYPE_COLOR:
			var cp := ColorPickerButton.new()
			cp.color = v
			cp.custom_minimum_size = Vector2(80, 30)
			cp.color_changed.connect(func(c): _apply(prop, c))
			ed = cp
	ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ed)
	_editors[prop] = [ed, kind]


func _apply(prop: String, value) -> void:
	if is_instance_valid(node):
		node.set(prop, value)
		if node is CanvasItem:
			node.queue_redraw()


func _input(event: InputEvent) -> void:
	if not _picking or not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if get_global_rect().has_point(event.position):
		return
	_picking = false
	get_viewport().set_input_as_handled()
	var world: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * event.position
	var picked := pick(world)
	if picked:
		select(picked)
		refresh()
	else:
		_title.text = "Nothing there"


## The thing at `world`: a body or area, else the closest Node2D.
func pick(world: Vector2) -> Node:
	var q := PhysicsPointQueryParameters2D.new()
	q.position = world
	q.collide_with_areas = true
	var hits := get_viewport().world_2d.direct_space_state.intersect_point(q, 8)
	for h in hits:
		if h.collider is Node and get_tree().current_scene.is_ancestor_of(h.collider):
			return h.collider
	var best: Node = null
	var best_d := 80.0
	for n in get_tree().current_scene.find_children("*", "Node2D", true, false):
		var d: float = n.global_position.distance_to(world)
		if d < best_d:
			best_d = d
			best = n
	return best
