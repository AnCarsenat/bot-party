class_name ArenaMap
## Party arena made in the map editor, stored as JSON (user://maps/<name>.json):
## {
##   "format": 1, "name": "My map", "author": "Elian",
##   "blocks": [[x, y, w, h], ...],   solid ground (pixels, multiples of 32)
##   "planks": [[x, y, w], ...],      one-way platforms (jump through from below)
##   "start":  [x, y, w, h],          start area (players spawn here, no building)
##   "goal":   [x, y],                where the flag stands (on the ground)
##   "wind": false, "meteors": false
## }
## custom_arena.tscn builds the playable arena from it.

const FORMAT := 1
const GRID := 32
const DIR := "user://maps"
const SCENE := "res://party/custom_arena.tscn"


static func blank(name := "New map") -> Dictionary:
	return {
		"format": FORMAT, "name": name, "author": "",
		"blocks": [[-192, 576, 640, 96], [576, 512, 448, 64], [1152, 448, 448, 64], [1728, 384, 512, 96]],
		"planks": [],
		"start": [-160, 384, 416, 192],
		"goal": [2048, 384],
		"wind": false, "meteors": false,
	}


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
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(map, "  "))
	return path


static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return normalize(data) if data is Dictionary else {}


## Every map file: your own (user://maps) and the ones from mods. [{name, path}]
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


## Fills in missing keys and fixes types (JSON numbers are floats).
static func normalize(data: Dictionary) -> Dictionary:
	var m := blank()
	for k in m:
		if data.has(k):
			m[k] = data[k]
	m.format = FORMAT
	m.name = str(m.name).left(40)
	m.author = str(m.author).left(40)
	for key in ["blocks", "planks"]:
		var list := []
		for r in m[key]:
			if r is Array and r.size() >= (4 if key == "blocks" else 3):
				list.append(r.map(func(v): return int(v)))
		m[key] = list
	m.start = (m.start as Array).map(func(v): return int(v))
	m.goal = (m.goal as Array).map(func(v): return int(v))
	m.wind = bool(m.wind)
	m.meteors = bool(m.meteors)
	return m


# --- Geometry ---------------------------------------------------------------------------

static func rect(a: Array) -> Rect2:
	return Rect2(a[0], a[1], a[2], a[3])


static func start_zone(m: Dictionary) -> Rect2:
	return rect(m.start)


static func goal_zone(m: Dictionary) -> Rect2:
	return Rect2(m.goal[0] - 220, m.goal[1] - 240, 440, 260)


## Everything in the map, plus room to build above and around it.
static func build_area(m: Dictionary) -> Rect2:
	var r := start_zone(m).merge(goal_zone(m))
	for b in m.blocks:
		r = r.merge(rect(b))
	for p in m.planks:
		r = r.merge(Rect2(p[0], p[1], p[2], 24))
	return r.grow_individual(160, 420, 160, 120)


static func spawn_origin(m: Dictionary) -> Vector2:
	var z := start_zone(m)
	return Vector2(z.position.x + 50, z.position.y + 40)


## Problems that stop the map from being playable ("" = fine).
static func problem(m: Dictionary) -> String:
	if m.blocks.is_empty():
		return "Add some ground"
	var z := start_zone(m)
	if z.size.x < 160 or z.size.y < 96:
		return "The start area is too small"
	var floor_found := false
	for b in m.blocks:
		var r := rect(b)
		if r.position.y >= z.position.y + 40 and r.position.y <= z.end.y and r.position.x < z.position.x + 120 and r.end.x > z.position.x + 40:
			floor_found = true
	if not floor_found:
		return "The start area needs ground inside it"
	if goal_zone(m).intersects(z):
		return "The flag is too close to the start"
	var goal_ground := false
	for b in m.blocks:
		var r := rect(b)
		if absf(r.position.y - m.goal[1]) < 4 and r.position.x <= m.goal[0] and r.end.x >= m.goal[0]:
			goal_ground = true
	for p in m.planks:
		if absf(p[1] - m.goal[1]) < 4 and p[0] <= m.goal[0] and p[0] + p[2] >= m.goal[0]:
			goal_ground = true
	if not goal_ground:
		return "The flag must stand on top of ground"
	return ""
