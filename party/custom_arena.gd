extends Node2D
## A party arena built from a map file (see ArenaMap). The map comes from the
## party session (Party.session.map), so a saved party or an online game (the host
## sends it along with the scene) rebuilds the same arena.

const SYNC := preload("res://objects/synced_polygon.gd")
const PLATFORM := preload("res://objects/platform.tscn")


func _enter_tree() -> void:
	# Runs before the controller and the rest are ready, so they see the real map.
	var m: Dictionary = ArenaMap.normalize(Party.session.get("map", ArenaMap.blank()))
	var level := $Level
	var i := 0
	for poly in m.ground:
		_ground(level, "Ground%d" % i, ArenaMap.points(poly))
		i += 1
	i = 0
	for p in m.planks:
		var plank := PLATFORM.instantiate()
		plank.name = "Plank%d" % i
		plank.size = Vector2(p[2], 24)
		plank.one_way = true
		plank.position = Vector2(p[0] + p[2] / 2.0, p[1] + 12)
		level.add_child(plank)
		i += 1
	var ctl := $PartyController
	ctl.start_zone = ArenaMap.start_zone(m)
	ctl.goal_zone = ArenaMap.goal_zone(m)
	var area := ArenaMap.build_area(m)
	ctl.build_area = area
	ctl.spawn_origin = ArenaMap.spawn_origin(m)
	ctl.follow_camera = true
	$PlayerSpawner.position = ctl.spawn_origin
	$Goal.position = Vector2(m.goal[0], m.goal[1] - 65)
	var cam := $Camera2D
	cam.position = area.get_center()
	cam.boundary_left = area.position.x - 400
	cam.boundary_right = area.end.x + 400
	cam.boundary_top = area.position.y - 2000
	cam.boundary_bottom = area.end.y + 500
	$Weather.wind = m.wind
	$Weather.meteors = m.meteors
	set_meta("title", m.name)
	_add_scene_nodes(level, str(m.get("scene", "")))


## A map made in Godot can have nodes of its own (see ArenaMap.load_scene): they
## join the arena, on every computer of an online game (each runs its own copy).
func _add_scene_nodes(level: Node, path: String) -> void:
	if path == "" or not ResourceLoader.exists(path):
		return
	var packed = load(path)
	if not packed is PackedScene:
		return
	var root: Node = packed.instantiate()
	var extras := Node2D.new()
	extras.name = "MapScene"
	for c in ArenaMap.extra_nodes(root):
		root.remove_child(c)
		_clear_owner(c)
		extras.add_child(c)
	root.free()
	level.add_child(extras)


func _clear_owner(n: Node) -> void:
	n.owner = null
	for c in n.get_children():
		_clear_owner(c)


func _ground(parent: Node, n: String, pts: PackedVector2Array) -> void:
	var body := StaticBody2D.new()
	body.name = n
	var col := CollisionPolygon2D.new()
	col.polygon = pts
	body.add_child(col)
	var vis := Polygon2D.new()
	vis.polygon = pts
	vis.set_script(SYNC)
	body.add_child(vis)
	parent.add_child(body)
