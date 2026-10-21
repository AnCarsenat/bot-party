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
	for b in m.blocks:
		_block(level, "Block%d" % i, ArenaMap.rect(b))
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


func _block(parent: Node, n: String, r: Rect2) -> void:
	var body := StaticBody2D.new()
	body.name = n
	body.position = r.get_center()
	var hw := r.size.x / 2.0
	var hh := r.size.y / 2.0
	var poly := PackedVector2Array([Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)])
	var col := CollisionPolygon2D.new()
	col.polygon = poly
	body.add_child(col)
	var vis := Polygon2D.new()
	vis.polygon = poly
	vis.set_script(SYNC)
	body.add_child(vis)
	parent.add_child(body)
