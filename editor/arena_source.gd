@tool
class_name ArenaSource
extends Node2D
## Make party maps in the Godot editor instead of the game's map editor.
## Open editor/arena_template.tscn, save it under a new name, then edit:
##   Ground/  any number of Polygon2D: solid ground (edit their points with
##            Godot's polygon tools; no self-crossing shapes)
##   Planks/  Polygon2D rectangles: one-way planks (only their width and top count)
##   Start    a Polygon2D rectangle: the start area
##   Flag     a Marker2D: where the flag stands (on top of ground)
##   Items/   party items already in place when the party starts: instance the
##            item scenes (res://party/items/..., platform.tscn, trampoline.tscn);
##            turn them by quarter turns, flip them with scale.x = -1
## Then press "Save map" in the inspector: the map goes to user://maps (shows up
## in Party > Arena and in the game's map editor), or into `save_folder` (a mod's
## maps folder, for example). Run the scene (F6) to play it straight away.

@export var map_name := "My map"
@export var author := ""
@export var wind := false
@export var meteors := false
## Leave empty for user://maps. Or a folder of yours, like a mod's "maps" folder.
@export_global_dir var save_folder := ""
@export_tool_button("Save map", "Save") var save_button := save_map
## A map file to bring in (replaces what's in the scene).
@export_global_file("*.json", "*.tscn") var load_file := ""
@export_tool_button("Load the map file", "Load") var load_button := load_map


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(true)
		return
	# Run on its own (F6): play it.
	var m := to_map()
	var p := ArenaMap.problem(m)
	if p != "":
		push_error("Can't play this map: " + p)
		return
	var party := get_node("/root/Party")
	var gs := get_node("/root/GameState")
	if gs.joined.is_empty():
		gs.join(1)
	party.test_map.call_deferred(m)


func _process(_d: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()


## The scene as a map (ArenaMap format).
func to_map() -> Dictionary:
	var m := {"format": ArenaMap.FORMAT, "name": map_name, "author": author, "ground": [], "planks": [],
		"wind": wind, "meteors": meteors}
	for poly in _polys("Ground"):
		var pts := []
		for p in _global_points(poly):
			pts.append([int(round(p.x)), int(round(p.y))])
		m.ground.append(pts)
	for poly in _polys("Planks"):
		var r := _rect_of(poly)
		m.planks.append([int(r.position.x), int(r.position.y), int(r.size.x)])
	var start := get_node_or_null("Start")
	if start is Polygon2D:
		var r := _rect_of(start)
		m.start = [int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y)]
	var flag := get_node_or_null("Flag")
	if flag is Node2D:
		var g := _xform(flag).origin
		m.goal = [int(round(g.x)), int(round(g.y))]
	m.items = []
	var items := get_node_or_null("Items")
	if items:
		for it in items.get_children():
			var id := _item_id(it)
			if id == "":
				continue
			var xf := _xform(it)
			var mirrored: bool = it.get("mirrored") == true or it.scale.x < 0.0
			m.items.append({"id": id, "x": int(round(xf.origin.x)), "y": int(round(xf.origin.y)),
				"rot": posmod(int(round(it.rotation / (PI / 2.0))), 4), "mirror": mirrored})
	return ArenaMap.normalize(m)


## Which party item a scene instance is (by its scene file and settings), or "".
func _item_id(node: Node) -> String:
	var party := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Party")
	if party == null or node.scene_file_path == "":
		return ""
	var best := ""
	for id in party.ITEMS:
		var def: Dictionary = party.ITEMS[id]
		if def.get("scene", "") != node.scene_file_path:
			continue
		var same := true
		for k in def.get("props", {}):
			if node.get(k) != def.props[k]:
				same = false
		if same:
			return id
		if best == "":
			best = id
	return best


## Rebuilds the scene from a map.
func from_map(m: Dictionary) -> void:
	m = ArenaMap.normalize(m)
	map_name = m.name
	author = m.author
	wind = m.wind
	meteors = m.meteors
	for group in ["Ground", "Planks"]:
		var node := get_node_or_null(group)
		if node == null:
			node = Node2D.new()
			node.name = group
			add_child(node)
			node.owner = _owner()
		for c in node.get_children():
			node.remove_child(c)
			c.queue_free()
	for i in m.ground.size():
		_add_poly(get_node("Ground"), "Ground%d" % (i + 1), ArenaMap.points(m.ground[i]), Color.WHITE)
	for i in m.planks.size():
		var r := ArenaMap.plank_rect(m.planks[i])
		_add_poly(get_node("Planks"), "Plank%d" % (i + 1), _rect_points(r), Color("f0fff4"))
	var start := get_node_or_null("Start")
	if start == null:
		start = _add_poly(self, "Start", PackedVector2Array(), Color(0.42, 0.73, 0.49, 0.3))
	start.position = Vector2.ZERO
	start.polygon = _rect_points(ArenaMap.start_zone(m))
	var flag := get_node_or_null("Flag")
	if flag == null:
		flag = Marker2D.new()
		flag.name = "Flag"
		add_child(flag)
		flag.owner = _owner()
	flag.position = Vector2(m.goal[0], m.goal[1])
	var items := get_node_or_null("Items")
	if items == null:
		items = Node2D.new()
		items.name = "Items"
		add_child(items)
		items.owner = _owner()
	for c in items.get_children():
		items.remove_child(c)
		c.queue_free()
	var party := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Party")
	for it in m.get("items", []):
		var def: Dictionary = party.ITEMS.get(it.id, {}) if party else {}
		if not def.has("scene"):
			continue
		var node: Node2D = load(def.scene).instantiate()
		for k in def.get("props", {}):
			node.set(k, def.props[k])
		node.position = Vector2(it.x, it.y)
		node.rotation = it.rot * PI / 2.0
		if it.mirror:
			if "mirrored" in node:
				node.set("mirrored", true)
			else:
				node.scale.x = -1.0
		items.add_child(node)
		node.owner = _owner()


func save_map() -> String:
	var m := to_map()
	var p := ArenaMap.problem(m)
	if p != "":
		push_warning("Saved, but it can't be played yet: " + p)
	var path: String
	if save_folder != "":
		path = save_folder.path_join(ArenaMap.slug(m.name) + ".json")
		ArenaMap.save_to(m, path)
	else:
		path = ArenaMap.save(m)
	print("Map saved: ", ProjectSettings.globalize_path(path))
	return path


func load_map() -> void:
	var m := ArenaMap.load_file(load_file)
	if m.is_empty():
		push_error("Not a map file: " + load_file)
		return
	from_map(m)


# --- Helpers --------------------------------------------------------------------------

func _polys(group: String) -> Array:
	var node := get_node_or_null(group)
	if node == null:
		return []
	return node.find_children("*", "Polygon2D", true, false).filter(func(p): return p.polygon.size() >= 3)


## `node`'s transform relative to this scene's root (works outside the tree too).
func _xform(node: Node) -> Transform2D:
	var xf := Transform2D.IDENTITY
	var n := node
	while n != null and n != self:
		if n is Node2D:
			xf = n.transform * xf
		n = n.get_parent()
	return xf


func _global_points(poly: Polygon2D) -> PackedVector2Array:
	var out := PackedVector2Array()
	var xf := _xform(poly)
	for p in poly.polygon:
		out.append(xf * (p + poly.offset))
	return out


func _rect_of(poly: Polygon2D) -> Rect2:
	var pts := _global_points(poly)
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r


func _rect_points(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


func _add_poly(parent: Node, n: String, pts: PackedVector2Array, color: Color) -> Polygon2D:
	var p := Polygon2D.new()
	p.name = n
	p.polygon = pts
	p.color = color
	parent.add_child(p)
	p.owner = _owner()
	return p


func _owner() -> Node:
	return owner if owner else self


## In the editor: where items can be built, the flag's no-build zone, a flag sketch.
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var m := to_map()
	draw_rect(ArenaMap.build_area(m), Color(1, 1, 1, 0.35), false, 2.0)
	draw_rect(ArenaMap.goal_zone(m), Color(0.9, 0.31, 0.24, 0.6), false, 2.0)
	var g := Vector2(m.goal[0], m.goal[1])
	draw_line(g, g + Vector2(0, -150), Color.BLACK, 4.0)
	draw_rect(Rect2(g + Vector2(0, -150), Vector2(60, 40)), Color.BLACK)
	for poly in _polys("Ground"):
		var pts := _global_points(poly)
		pts.append(pts[0])
		draw_polyline(pts, Color.BLACK, 3.0)
	var p := ArenaMap.problem(m)
	draw_string(ThemeDB.fallback_font, ArenaMap.build_area(m).position + Vector2(10, 30),
		("Problem: " + p) if p != "" else "Playable: %s" % m.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 24,
		Color(0.9, 0.31, 0.24) if p != "" else Color.WHITE)
