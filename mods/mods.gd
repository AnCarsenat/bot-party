extends Node
## Autoload "Mods" (first autoload): finds mods in user://mods/<folder>/mod.json.
## A mod can add party items, add maps and replace textures. See MODDING.md.
##
## Textures are replaced in _init(), before the rest of the game loads, so a change
## to them needs a restart. Items and maps follow the on/off switches right away.

const DIR := "user://mods"
const CFG := "user://mods.cfg"

## Every mod found: [{id, name, author, version, description, path, enabled,
## items: {id: def}, textures: {game path: file}, maps: dir, problems: []}]
var mods: Array = []
var _keep: Array = []  # replaced textures (kept alive)


func _init() -> void:
	scan()
	for m in mods:
		if m.enabled:
			_apply_textures(m)


## Reads every mod folder (and the on/off switches).
func scan() -> void:
	mods.clear()
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)
	var folders := DirAccess.get_directories_at(DIR)
	folders.sort()
	for folder in folders:
		var m := _read(DIR.path_join(folder))
		if m.is_empty():
			continue
		m.enabled = bool(cfg.get_value("enabled", m.id, true))
		mods.append(m)


func set_enabled(id: String, on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	cfg.set_value("enabled", id, on)
	cfg.save(CFG)
	for m in mods:
		if m.id == id:
			m.enabled = on
	var party := get_node_or_null("/root/Party")
	if party:
		party.reload_items()


func get_mod(id: String) -> Dictionary:
	for m in mods:
		if m.id == id:
			return m
	return {}


## Items of every enabled mod, ready for Party.ITEMS ({"<mod>.<item>": def}).
func items() -> Dictionary:
	var out := {}
	for m in mods:
		if m.enabled:
			out.merge(m.items)
	return out


## Game modes of every enabled mod ({"<mod>.<mode>": {name, description, script}}).
func modes() -> Dictionary:
	var out := {}
	for m in mods:
		if m.enabled:
			out.merge(m.get("modes", {}))
	return out


## Folders with map files from enabled mods (ArenaMap.list_all reads them).
func map_dirs() -> Array:
	var out := []
	for m in mods:
		if m.enabled and m.maps != "":
			out.append(m.maps)
	return out


## Mods other players need to join an online game of ours: the ones adding items
## ("id@version"). Maps travel with the game and textures are only looks.
func required() -> Array:
	var out := []
	for m in mods:
		if m.enabled and (not m.items.is_empty() or not m.get("modes", {}).is_empty()):
			out.append("%s@%s" % [m.id, m.version])
	return out


func open_folder() -> void:
	OS.shell_open(ProjectSettings.globalize_path(DIR))


# --- Reading a mod -------------------------------------------------------------------

func _read(path: String) -> Dictionary:
	var file := path.path_join("mod.json")
	if not FileAccess.file_exists(file):
		return {}
	var id := ArenaMap.slug(path.get_file())
	var m := {"id": id, "name": path.get_file(), "author": "", "version": "1", "description": "",
		"path": path, "enabled": true, "items": {}, "textures": {}, "maps": "", "problems": []}
	var data = JSON.parse_string(FileAccess.get_file_as_string(file))
	if not data is Dictionary:
		m.problems.append("mod.json isn't valid JSON")
		return m
	for k in ["name", "author", "version", "description"]:
		if data.has(k):
			m[k] = str(data[k])
	var maps := path.path_join(str(data.get("maps", "maps")))
	if DirAccess.dir_exists_absolute(maps):
		m.maps = maps
	var tex = data.get("textures", {})
	if tex is Dictionary:
		for game_path in tex:
			var full := str(game_path) if str(game_path).begins_with("res://") else "res://" + str(game_path)
			if not ResourceLoader.exists(full):
				m.problems.append("No game texture %s" % full)
			elif not FileAccess.file_exists(path.path_join(str(tex[game_path]))):
				m.problems.append("Missing file %s" % tex[game_path])
			else:
				m.textures[full] = path.path_join(str(tex[game_path]))
	m.modes = {}
	var modes = data.get("modes", {})
	if modes is Dictionary:
		for mode_id in modes:
			var d = modes[mode_id]
			var script := _file(m, str(d.get("script", ""))) if d is Dictionary else ""
			if not script.ends_with(".gd") or not FileAccess.file_exists(script):
				m.problems.append("Mode %s: script not found" % mode_id)
				continue
			m.modes["%s.%s" % [id, ArenaMap.slug(str(mode_id))]] = {"name": str(d.get("name", mode_id)).left(24),
				"description": str(d.get("description", "")).left(160), "script": script, "mod": id}
	var items = data.get("items", {})
	if items is Dictionary:
		for item_id in items:
			var def := _item(m, str(item_id), items[item_id])
			if not def.is_empty():
				m.items["%s.%s" % [id, ArenaMap.slug(str(item_id))]] = def
	return m


## Turns an item from mod.json into a Party.ITEMS entry.
func _item(m: Dictionary, item_id: String, d) -> Dictionary:
	if not d is Dictionary:
		m.problems.append("Item %s isn't an object" % item_id)
		return {}
	var def := {"name": str(d.get("name", item_id)).left(24), "mod": m.id,
		"size": _value(d.get("size", [64, 64])), "weight": clampi(int(d.get("weight", 8)), 0, 20)}
	if d.has("offset"):
		def.offset = _value(d.offset)
	for flag in ["host", "bomb"]:
		if d.get(flag, false):
			def[flag] = true
	if def.get("bomb", false):
		def.radius = float(d.get("radius", 130))
	else:
		var scene := _file(m, str(d.get("scene", "")))
		if scene == "" or not ResourceLoader.exists(scene):
			m.problems.append("Item %s: scene not found (%s)" % [item_id, d.get("scene", "")])
			return {}
		def.scene = scene
	if d.has("props") and d.props is Dictionary:
		def.props = {}
		for k in d.props:
			def.props[str(k)] = _value(d.props[k])
	if d.has("script"):
		var script := _file(m, str(d.script))
		if not script.ends_with(".gd") or not FileAccess.file_exists(script):
			m.problems.append("Item %s: script not found (%s)" % [item_id, d.script])
			return {}
		def.script = script  # loaded when the item is placed
	# Icon: a picture in the mod folder, or one of the game's.
	var icon := _file(m, str(d.get("icon", "")))
	if icon.begins_with("res://") and ResourceLoader.exists(icon):
		def.icon = icon
	elif icon != "" and FileAccess.file_exists(icon):
		def.icon = icon
		def.icon_texture = texture(icon)
	else:
		def.icon = "res://party/art/block.webp"
	return def


## "res://..." stays as it is, anything else is a file in the mod folder.
func _file(m: Dictionary, p: String) -> String:
	if p == "" or p.begins_with("res://"):
		return p
	return m.path.path_join(p).simplify_path()


## JSON -> Godot values: [x, y] is a Vector2, "#rrggbb" a Color.
func _value(v):
	if v is Array and v.size() == 2 and (v[0] is float or v[0] is int):
		return Vector2(v[0], v[1])
	if v is String and v.begins_with("#") and Color.html_is_valid(v):
		return Color.html(v)
	return v


## Loads a picture file (png, jpg, webp) from a mod folder as a texture.
func texture(file: String) -> Texture2D:
	var img := Image.load_from_file(file)
	return ImageTexture.create_from_image(img) if img else null


func _apply_textures(m: Dictionary) -> void:
	for game_path in m.textures:
		var t := texture(m.textures[game_path])
		if t:
			t.take_over_path(game_path)
			_keep.append(t)
