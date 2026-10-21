class_name ArenaMap
## Party arena made in the map editor, stored as JSON (user://maps/<name>.json):
## {
##   "format": 2, "name": "My map", "author": "Elian",
##   "ground": [[[x, y], [x, y], ...], ...],  solid ground: polygons (any shape, no self-crossing)
##   "planks": [[x, y, w], ...],              one-way platforms (jump through from below)
##   "start":  [x, y, w, h],                  start area (players spawn here, no building)
##   "goal":   [x, y],                        where the flag stands (on the ground)
##   "wind": false, "meteors": false
## }
## Format 1 files had "blocks": [[x, y, w, h], ...] instead of "ground"; they still load.
## custom_arena.tscn builds the playable arena from it.

const FORMAT := 2
const GRID := 32
const DIR := "user://maps"
const SCENE := "res://party/custom_arena.tscn"


static func blank(name := "New map") -> Dictionary:
	return {
		"format": FORMAT, "name": name, "author": "",
		"ground": [_box(-192, 576, 640, 96), _box(576, 512, 448, 64), _box(1152, 448, 448, 64), _box(1728, 384, 512, 96)],
		"planks": [],
		"start": [-160, 384, 416, 192],
		"goal": [2048, 384],
		"wind": false, "meteors": false,
	}


static func _box(x: float, y: float, w: float, h: float) -> Array:
	var a := [int(x), int(y), int(x + w), int(y + h)]
	return [[a[0], a[1]], [a[2], a[1]], [a[2], a[3]], [a[0], a[3]]]


# --- Files -----------------------------------------------------------------------------

static func slug(name: String) -> String:
	var s := ""
	for c in name.to_lower():
		s += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "-"
	while s.contains("--"):
		s = s.replace("--", "-")
	s = s.trim_prefix("-").trim_suffix("-")
	return s if s != "" else "map"


static func save(map: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := "%s/%s.json" % [DIR, slug(map.name)]
	save_to(map, path)
	return path


static func save_to(map: Dictionary, path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(normalize(map), "  "))


static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return normalize(data) if data is Dictionary else {}


## Every map file: your own (user://maps) and the ones from mods. [{name, path, mod}]
static func list_all() -> Array:
	var out := []
	var mods := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Mods")
	for dir in [DIR] + (mods.map_dirs() if mods else []):
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".json"):
				var m := load_file(dir.path_join(f))
				if not m.is_empty():
					out.append({"name": m.name, "path": dir.path_join(f), "mod": dir != DIR})
	return out


## Fills in missing keys, fixes types (JSON numbers are floats) and upgrades old files.
static func normalize(data: Dictionary) -> Dictionary:
	var m := blank()
	for k in m:
		if data.has(k):
			m[k] = data[k]
	if not data.has("ground") and data.get("blocks") is Array:
		m.ground = []
		for b in data.blocks:
			if b is Array and b.size() >= 4:
				m.ground.append(_box(b[0], b[1], b[2], b[3]))
	m.format = FORMAT
	m.name = str(m.name).left(40)
	m.author = str(m.author).left(40)
	var ground := []
	if m.ground is Array:
		for poly in m.ground:
			var pts := []
			if poly is Array:
				for p in poly:
					if p is Array and p.size() >= 2:
						pts.append([int(round(float(p[0]))), int(round(float(p[1])))])
			if pts.size() >= 3:
				ground.append(pts)
	m.ground = ground
	var planks := []
	if m.planks is Array:
		for p in m.planks:
			if p is Array and p.size() >= 3:
				planks.append([int(p[0]), int(p[1]), maxi(32, int(p[2]))])
	m.planks = planks
	m.start = (m.start as Array).map(func(v): return int(v))
	m.goal = (m.goal as Array).map(func(v): return int(v))
	m.wind = bool(m.wind)
	m.meteors = bool(m.meteors)
	return m


# --- Geometry ---------------------------------------------------------------------------

static func rect(a: Array) -> Rect2:
	return Rect2(a[0], a[1], a[2], a[3])


static func points(poly: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(Vector2(p[0], p[1]))
	return out


static func poly_rect(poly: Array) -> Rect2:
	var pts := points(poly)
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r


static func plank_rect(p: Array) -> Rect2:
	return Rect2(p[0], p[1], p[2], 24)


static func start_zone(m: Dictionary) -> Rect2:
	return rect(m.start)


static func goal_zone(m: Dictionary) -> Rect2:
	return Rect2(m.goal[0] - 220, m.goal[1] - 240, 440, 260)


## Everything in the map, plus room to build above and around it.
static func build_area(m: Dictionary) -> Rect2:
	var r := start_zone(m).merge(goal_zone(m))
	for poly in m.ground:
		r = r.merge(poly_rect(poly))
	for p in m.planks:
		r = r.merge(plank_rect(p))
	return r.grow_individual(160, 420, 160, 120)


static func spawn_origin(m: Dictionary) -> Vector2:
	var z := start_zone(m)
	return Vector2(z.position.x + 50, z.position.y + 40)


## Is there something to stand on at `p`? (Inside ground, or on a plank.)
static func solid_at(m: Dictionary, p: Vector2) -> bool:
	for poly in m.ground:
		if Geometry2D.is_point_in_polygon(p, points(poly)):
			return true
	for pl in m.planks:
		if plank_rect(pl).has_point(p):
			return true
	return false


## Problems that stop the map from being playable ("" = fine).
static func problem(m: Dictionary) -> String:
	if m.ground.is_empty():
		return "Add some ground"
	for i in m.ground.size():
		if Geometry2D.triangulate_polygon(points(m.ground[i])).is_empty():
			return "Ground %d crosses itself" % (i + 1)
	var z := start_zone(m)
	if z.size.x < 160 or z.size.y < 96:
		return "The start area is too small"
	# Something to stand on near the spawn, inside the start area.
	var floor_found := false
	for y in range(int(z.position.y) + 40, int(z.end.y) + 5, 4):
		for x in range(int(z.position.x) + 40, int(z.position.x) + 124, 8):
			if solid_at(m, Vector2(x, y)):
				floor_found = true
	if not floor_found:
		return "The start area needs ground inside it"
	if goal_zone(m).intersects(z):
		return "The flag is too close to the start"
	var g := Vector2(m.goal[0], m.goal[1])
	if not solid_at(m, g + Vector2(0, 4)) or solid_at(m, g - Vector2(0, 4)):
		return "The flag must stand on top of ground"
	return ""
