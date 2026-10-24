class_name ArenaPreview
extends Control
## Party > Arena: a small picture of the arena that's chosen (ground, planks,
## start area, flag, items that come with it).

var _shapes := {}  # see _read()
static var _cache := {}


func set_choice(id: String) -> void:
	if not _cache.has(id):
		_cache[id] = _read(id)
	_shapes = _cache[id]
	queue_redraw()


## Forget what's been read (maps change in the editor).
static func clear_cache() -> void:
	_cache.clear()


static func _read(id: String) -> Dictionary:
	var out := {"ground": [], "planks": [], "items": [], "start": Rect2(), "goal": Vector2.INF, "area": Rect2()}
	if id.begins_with("map:"):
		var m := ArenaMap.load_file(id.trim_prefix("map:"))
		if m.is_empty():
			return {}
		for poly in m.ground:
			out.ground.append(ArenaMap.points(poly))
		for p in m.planks:
			out.planks.append(ArenaMap.plank_rect(p))
		for it in m.get("items", []):
			out.items.append([ArenaMap.item_rect(it), it.id])
		out.start = ArenaMap.start_zone(m)
		out.goal = Vector2(m.goal[0], m.goal[1])
		out.area = ArenaMap.build_area(m)
		return out
	if not ResourceLoader.exists(id):
		return {}
	var root: Node = load(id).instantiate()
	# Solid ground: the collision shapes of the arena's level.
	for n in root.find_children("*", "", true, false):
		if not n.get_parent() is StaticBody2D:
			continue
		var xf := _xform(root, n)
		if n is CollisionPolygon2D:
			var pts := PackedVector2Array()
			for p in n.polygon:
				pts.append(xf * p)
			out.ground.append(pts)
		elif n is CollisionShape2D and n.shape is RectangleShape2D:
			var r := Rect2(-n.shape.size / 2.0, n.shape.size)
			var pts := PackedVector2Array([xf * r.position, xf * Vector2(r.end.x, r.position.y), xf * r.end, xf * Vector2(r.position.x, r.end.y)])
			if n.one_way_collision:
				out.planks.append(Rect2(pts[0], Vector2.ZERO).expand(pts[2]))
			else:
				out.ground.append(pts)
	var ctl := root.get_node_or_null("PartyController")
	if ctl:
		out.start = ctl.start_zone
		out.area = ctl.build_area
	var goal := root.get_node_or_null("Goal")
	if goal is Node2D:
		out.goal = goal.position + Vector2(0, 65)
	root.free()
	# Built-in arenas: the picture covers what's in them.
	var r: Rect2 = out.start
	for pts in out.ground:
		for p in pts:
			r = r.expand(p)
	out.area = r.grow(80)
	return out


static func _xform(root: Node, n: Node) -> Transform2D:
	var xf := Transform2D.IDENTITY
	while n != null and n != root:
		if n is Node2D:
			xf = n.transform * xf
		n = n.get_parent()
	return xf


func _draw() -> void:
	var frame := Rect2(Vector2.ZERO, size)
	draw_rect(frame, Color("8f8ca0"))
	draw_rect(frame, UiTheme.INK, false, 4.0)
	if _shapes.is_empty():
		return
	var area: Rect2 = _shapes.area
	var k := minf((size.x - 24) / area.size.x, (size.y - 24) / area.size.y)
	var off := (size - area.size * k) / 2.0 - area.position * k
	draw_set_transform(off, 0.0, Vector2(k, k))
	var px := 1.0 / k
	draw_rect(_shapes.start, Color(0.42, 0.73, 0.49, 0.45))
	for pts in _shapes.ground:
		if not Geometry2D.triangulate_polygon(pts).is_empty():
			draw_colored_polygon(pts, Color.WHITE)
		var closed: PackedVector2Array = pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, UiTheme.INK, 2.0 * px)
	for r in _shapes.planks:
		draw_rect(r, Color("f0fff4"))
		draw_rect(r, UiTheme.INK, false, 2.0 * px)
	for it in _shapes.items:
		var party := get_node_or_null("/root/Party")
		if party and party.ITEMS.has(it[1]):
			var r: Rect2 = it[0]
			var side := minf(minf(r.size.x, r.size.y), 96.0)
			draw_texture_rect(party.icon(it[1]), Rect2(r.get_center() - Vector2(side, side) / 2.0, Vector2(side, side)), false)
	if _shapes.goal != Vector2.INF:
		var g: Vector2 = _shapes.goal
		draw_line(g, g + Vector2(0, -150), UiTheme.INK, 6.0 * px)
		draw_rect(Rect2(g + Vector2(0, -150), Vector2(60, 40)), UiTheme.RED)
	draw_set_transform(Vector2.ZERO)
