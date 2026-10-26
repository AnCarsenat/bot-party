extends Node
## Autoload "Mods" (first autoload): finds and loads mods. See MODDING.md.
##
## A mod is one of:
##  - a mod pack: user://mods/<id>.pck (or .zip), made in Godot with editor/mod_kit.tscn.
##    Its files show up at res://mods/<id>/, so its scenes, scripts and pictures load
##    like the game's own.
##  - a folder: user://mods/<id>/mod.json, with plain files next to it.
##  - a folder in the game project, res://mods/<id>/ (while you make a mod in Godot;
##    off until you switch it on, and never part of the exported game).
## Each has a mod.json listing its items, game modes, maps and texture changes.
##
## Textures are replaced in _init(), before the rest of the game loads, so a change
## to them needs a restart. Items, modes and maps follow the on/off switches right away.

const DIR := "user://mods"
const PROJECT_DIR := "res://mods"
const CFG := "user://mods.cfg"

## Every mod found: [{id, name, author, version, description, path, kind ("pack",
## "folder" or "project"), pack (file), enabled, items: {id: def}, modes,
## textures: {game path: file}, maps: dir, problems: []}]
var mods: Array = []
var _keep: Array = []  # replaced textures (kept alive)
var _mounted := {}  # pack file -> [mod ids in it]
## Packs the host of an online game sent us (user://mods_net/): on while we're in
## that game, off again after (gone at the next start).
var _net_files := {}
var _net_on := false
const NET_DIR := "user://mods_net"
const CACHE_DIR := "user://mods_cache"


func _init() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	for file in _pack_files():
		if bool(cfg.get_value("enabled", _pack_id(file), true)):
			_mount(file)
	scan()
	for m in mods:
		if m.enabled:
			_apply_textures(m)


## Reads every mod (and the on/off switches).
func scan() -> void:
	mods.clear()
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)
	var found := []  # [mod, default on/off]
	var folders := DirAccess.get_directories_at(DIR)
	folders.sort()
	for folder in folders:
		var m := _read(DIR.path_join(folder))
		if not m.is_empty():
			m.kind = "folder"
			found.append([m, true])
	# (Packs from a host first: they're the version that game needs.)
	var mounted := _mounted.keys()
	mounted.sort_custom(func(a, b): return a in _net_files and not b in _net_files)
	for file in mounted:
		for id in _mounted[file]:
			var m := _read(PROJECT_DIR.path_join(id))
			if not m.is_empty():
				m.kind = "pack"
				m.pack = file
				found.append([m, true])
	# Mods being made in the game project (when running the game from Godot).
	var mine := DirAccess.get_directories_at(PROJECT_DIR)
	mine.sort()
	for id in mine:
		var m := _read(PROJECT_DIR.path_join(id))
		if not m.is_empty():
			m.kind = "project"
			found.append([m, false])
	# Packs that aren't loaded: switched off, or hidden by the project's own folder.
	for file in _pack_files():
		if _mounted.has(file):
			continue
		var off := _entry(_pack_id(file), file.get_file())
		off.kind = "pack"
		off.pack = file
		if _shadowed(file):
			for f in found:
				if f[0].id == off.id:
					f[0].problems.append("%s in the mods folder isn't loaded: this folder is used instead." % file.get_file())
			continue
		off.description = "Switch it on to load it."
		found.append([off, true])
	# A mod the host sent wins over our own copy of it (another version).
	if _net_on:
		var net := found.filter(func(f): return f[0].get("pack", "") in _net_files)
		found = net + found.filter(func(f): return not f[0].get("pack", "") in _net_files)
	var seen := {}
	for f in found:
		var m: Dictionary = f[0]
		if seen.has(m.id):
			continue  # same mod twice (a pack and its project folder): the first wins
		seen[m.id] = true
		m.enabled = bool(cfg.get_value("enabled", m.id, f[1])) and (m.kind != "pack" or m.has("pack") and _mounted.has(m.pack))
		if m.get("pack", "") in _net_files:
			m.net = true
			m.enabled = _net_on  # the host's: only while in its game
		mods.append(m)


func set_enabled(id: String, on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	cfg.set_value("enabled", id, on)
	cfg.save(CFG)
	var rescan := false
	for m in mods:
		if m.id == id:
			if on and m.kind == "pack" and not _mounted.has(m.pack) and not _shadowed(m.pack):
				_mount(m.pack)  # loaded now; it stays loaded until the game restarts
				rescan = true
			else:
				m.enabled = on
	if rescan:
		scan()
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


## Hats and other cosmetics of every enabled mod ({"<mod>.<look>": {name,
## picture, slot ("head": on the robot, "face": moves with its face)}}).
func cosmetics() -> Dictionary:
	var out := {}
	for m in mods:
		if m.enabled:
			out.merge(m.get("cosmetics", {}))
	return out


var _look_textures := {}
var _icons := {}          # icon file or repository -> texture
## A cosmetic's picture (loaded once).
## A mod's icon (mod.json "icon"), or null.
func icon_texture(m: Dictionary) -> Texture2D:
	var file: String = m.get("icon", "")
	if file == "":
		return null
	if not _icons.has(file):
		_icons[file] = texture(file)
	return _icons[file]


## Mods > Explore: the icon of a repository's mod (its mod.json "icon", or
## icon.png), downloaded once. `done` gets the texture, or null.
func repo_icon(full_name: String, done: Callable) -> void:
	if _icons.has(full_name):
		done.call(_icons[full_name])
		return
	var raw := "https://raw.githubusercontent.com/%s/HEAD/" % full_name
	_http_raw(raw + "mod.json", func(body: PackedByteArray):
		var data = JSON.parse_string(body.get_string_from_utf8()) if body.size() > 0 else null
		var file := str(data.get("icon", "icon.png")) if data is Dictionary else "icon.png"
		_http_raw(raw + file.uri_encode().replace("%2F", "/"), func(png: PackedByteArray):
			var img := Image.new()
			var tex: Texture2D = null
			if png.size() > 0 and png.size() < 2_000_000 and img.load_png_from_buffer(png) == OK:
				tex = ImageTexture.create_from_image(img)
			_icons[full_name] = tex
			done.call(tex)))


func _http_raw(url: String, done: Callable) -> void:
	var req := HTTPRequest.new()
	req.timeout = 15.0
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h, body: PackedByteArray):
		req.queue_free()
		done.call(body if result == HTTPRequest.RESULT_SUCCESS and code == 200 else PackedByteArray()))
	if req.request(url, ["User-Agent: BotParty"]) != OK:
		req.queue_free()
		done.call(PackedByteArray())


func look_texture(id: String) -> Texture2D:
	if not _look_textures.has(id):
		var d: Dictionary = cosmetics().get(id, {})
		_look_textures[id] = texture(d.picture) if not d.is_empty() else null
	return _look_textures[id]


## Folders with map files from enabled mods (ArenaMap.list_all reads them).
func map_dirs() -> Array:
	var out := []
	for m in mods:
		if m.enabled and m.maps != "":
			out.append(m.maps)
	return out


## Mods other players need to join an online game of ours ("id@version"): the ones
## adding items or game modes, and Godot mods (packs) with maps, whose scenes may
## hold their own nodes. Plain map files travel with the game; textures are only looks.
func required() -> Array:
	var out := []
	for m in mods:
		if m.enabled and (not m.items.is_empty() or not m.get("modes", {}).is_empty()
				or not m.get("cosmetics", {}).is_empty() or m.maps.begins_with("res://")):
			out.append("%s@%s" % [m.id, m.version])
	return out


# --- Online: the host sends its mods ------------------------------------------------

## Host: a pack file of mod `id` to send to a player who doesn't have it: its own
## pack, or one made from its folder (kept in user://mods_cache/). "" if it can't.
func pack_for(id: String) -> String:
	var m := get_mod(id)
	if m.is_empty() or not m.enabled:
		return ""
	if m.kind == "pack" and FileAccess.file_exists(m.get("pack", "")):
		return m.pack
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var out := CACHE_DIR.path_join("%s.pck" % id)
	if m.kind == "project":
		var err: String = load("res://editor/mod_packer.gd").pack(m.path, out)
		return out if err == "" else ""
	# A mod folder: its plain files, put where a pack's would be (res://mods/<id>/).
	var files := []
	_walk_files(m.path, files)
	var pck := PCKPacker.new()
	if pck.pck_start(out) != OK:
		return ""
	for f in files:
		pck.add_file(PROJECT_DIR.path_join(id).path_join(f.trim_prefix(m.path).trim_prefix("/")), f)
	return out if pck.flush() == OK else ""


func _walk_files(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if not f.begins_with("."):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			_walk_files(dir.path_join(d), out)


## Client: loads a pack the host sent (saved as `file`), on for this game only.
## Its files replace those of an older version we may have.
func mount_net(file: String) -> bool:
	var before := DirAccess.get_directories_at(PROJECT_DIR)
	if not ProjectSettings.load_resource_pack(file, true):
		return false
	var ids := []
	for d in DirAccess.get_directories_at(PROJECT_DIR):
		if not d in before:
			ids.append(d)
	if ids.is_empty():
		ids.append(_pack_id(file))
	_mounted[file] = ids
	_net_files[file] = true
	set_net_on(true)
	return true


## The host's mods on (in its game) or off (after).
func set_net_on(on: bool) -> void:
	if _net_on == on and not on:
		return
	_net_on = on
	scan()
	var party := get_node_or_null("/root/Party")
	if party:
		party.reload_items()


# --- Installing mods: from a file, or from GitHub (Mods > Explore) -------------------

## GitHub repositories with this topic are listed in Mods > Explore.
const TOPIC := "bot-party-mod"
const API := "https://api.github.com"


## Copies a mod pack (.pck / .zip) into the mods folder and loads it. Returns an
## error message, or "".
func install_pack(from: String) -> String:
	var ext := from.get_extension().to_lower()
	if not ext in ["pck", "zip"]:
		return "Choose a mod pack (.pck or .zip)"
	DirAccess.make_dir_recursive_absolute(DIR)
	var to := DIR.path_join(from.get_file())
	if ProjectSettings.globalize_path(to) != ProjectSettings.globalize_path(from):
		if DirAccess.copy_absolute(from, to) != OK:
			return "Couldn't copy it into the mods folder"
	return _load_installed(to)


func _load_installed(file: String) -> String:
	if not _mounted.has(file):
		_mount(file)
	if not _mounted.has(file):
		return "Couldn't load %s (a mod pack for another version of the game?)" % file.get_file()
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	for id in _mounted[file]:
		cfg.set_value("enabled", id, true)
	cfg.save(CFG)
	scan()
	var party := get_node_or_null("/root/Party")
	if party:
		party.reload_items()
	return ""


## How Mods > Explore can sort.
const EXPLORE_SORTS := ["Stars", "Date", "Name", "Downloads"]


## Mods > Explore: repositories tagged as Bot Party mods, matching `search` (words
## in their name or description), sorted by `sort` (one of EXPLORE_SORTS).
## `done` gets [{name, full_name, description, stars, author, url, updated,
## downloads (-1: not counted)}] (or [] and an error).
func explore(done: Callable, search := "", sort := "Stars") -> void:
	var q := "topic:%s" % TOPIC
	if search.strip_edges() != "":
		q = search.strip_edges().uri_encode() + "+" + q
	var api_sort: String = {"Stars": "&sort=stars&order=desc", "Date": "&sort=updated&order=desc"}.get(sort, "")
	_http_get(API + "/search/repositories?q=%s%s&per_page=40" % [q, api_sort], func(ok: bool, data):
		if not ok or not data is Dictionary:
			done.call([], "Couldn't reach GitHub")
			return
		var out := []
		for r in data.get("items", []):
			out.append({"name": _repo_title(str(r.get("name", ""))), "full_name": str(r.get("full_name", "")),
				"description": str(r.get("description", "") if r.get("description") != null else ""),
				"stars": int(r.get("stargazers_count", 0)), "author": str(r.get("owner", {}).get("login", "")),
				"url": str(r.get("html_url", "")), "updated": str(r.get("pushed_at", r.get("updated_at", ""))).left(10),
				"downloads": -1})
		match sort:
			"Name":
				out.sort_custom(func(a, b): return a.name.to_lower() < b.name.to_lower())
				done.call(out, "")
			"Downloads":
				# GitHub's search doesn't say: count each one's release downloads
				# (the first 20: GitHub limits how often we may ask).
				_count_downloads(out, 0, func():
					out.sort_custom(func(a, b): return a.downloads > b.downloads)
					done.call(out, ""))
			_:
				done.call(out, "")
	)


## "bot-party-hats" -> "Hats".
static func _repo_title(repo: String) -> String:
	for prefix in ["bot-party-", "botparty-", "bot_party_"]:
		if repo.to_lower().begins_with(prefix) and repo.length() > prefix.length():
			repo = repo.substr(prefix.length())
	return repo.replace("-", " ").replace("_", " ").capitalize() if repo == repo.to_lower() else repo


func _count_downloads(list: Array, i: int, then: Callable) -> void:
	if i >= mini(list.size(), 20):
		then.call()
		return
	_http_get(API + "/repos/%s/releases?per_page=10" % list[i].full_name, func(ok: bool, data):
		var n := 0
		if ok and data is Array:
			for rel in data:
				for a in rel.get("assets", []):
					n += int(a.get("download_count", 0))
		list[i].downloads = n
		_count_downloads(list, i + 1, then))


## Downloads the mod pack of a repository's latest release and installs it.
## `done` gets an error message, or "".
func install_from_repo(full_name: String, done: Callable) -> void:
	_http_get(API + "/repos/%s/releases/latest" % full_name, func(ok: bool, data):
		if not ok or not data is Dictionary:
			done.call("No release to download in %s" % full_name)
			return
		var asset = null
		for a in data.get("assets", []):
			if str(a.get("name", "")).get_extension().to_lower() in ["pck", "zip"]:
				asset = a
				break
		if asset == null:
			done.call("Its latest release has no mod pack (.pck)")
			return
		DirAccess.make_dir_recursive_absolute(DIR)
		var file := DIR.path_join(str(asset.name).get_file())
		var req := HTTPRequest.new()
		req.download_file = file
		req.timeout = 120.0
		add_child(req)
		req.request_completed.connect(func(result: int, code: int, _h, _b):
			req.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				DirAccess.remove_absolute(file)
				done.call("The download didn't work")
				return
			done.call(_load_installed(file))
		)
		if req.request(str(asset.browser_download_url), ["User-Agent: BotParty", "Accept: application/octet-stream"]) != OK:
			req.queue_free()
			done.call("The download didn't work")
	)


func _http_get(url: String, done: Callable) -> void:
	var req := HTTPRequest.new()
	req.timeout = 15.0
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h, body: PackedByteArray):
		req.queue_free()
		var data = JSON.parse_string(body.get_string_from_utf8()) if body.size() > 0 else null
		done.call(result == HTTPRequest.RESULT_SUCCESS and code == 200, data)
	)
	if req.request(url, ["User-Agent: BotParty", "Accept: application/vnd.github+json"]) != OK:
		req.queue_free()
		done.call(false, null)


func open_folder() -> void:
	OS.shell_open(ProjectSettings.globalize_path(DIR))


# --- Reading a mod -------------------------------------------------------------------

func _read(path: String) -> Dictionary:
	var file := path.path_join("mod.json")
	var data = {}
	if FileAccess.file_exists(file):
		var json := JSON.new()
		data = json.data if json.parse(FileAccess.get_file_as_string(file)) == OK else null
	elif not DirAccess.dir_exists_absolute(path.path_join("maps")):
		return {}  # not a mod (a map pack needs no mod.json, only maps/)
	var m := _entry(ArenaMap.slug(path.get_file()), path.get_file())
	var id: String = m.id
	m.path = path
	if not data is Dictionary:
		m.problems.append("mod.json isn't valid JSON")
		return m
	for k in ["name", "author", "version", "description"]:
		if data.has(k):
			m[k] = str(data[k])
	# Its picture in the Mods screens: "icon" (or icon.png if there's one).
	var icon := _file(m, str(data.get("icon", "icon.png")))
	if _exists(icon):
		m.icon = icon
	elif data.has("icon"):
		m.problems.append("Missing file %s" % data.icon)
	var maps := path.path_join(str(data.get("maps", "maps")))
	if DirAccess.dir_exists_absolute(maps):
		m.maps = maps
	var tex = data.get("textures", {})
	if tex is Dictionary:
		for game_path in tex:
			var full := str(game_path) if str(game_path).begins_with("res://") else "res://" + str(game_path)
			if not ResourceLoader.exists(full):
				m.problems.append("No game texture %s" % full)
			elif not _exists(_file(m, str(tex[game_path]))):
				m.problems.append("Missing file %s" % tex[game_path])
			else:
				m.textures[full] = _file(m, str(tex[game_path]))
	m.cosmetics = {}
	var looks = data.get("cosmetics", {})
	if looks is Dictionary:
		for look_id in looks:
			var d = looks[look_id]
			var pic := _file(m, str(d.get("picture", ""))) if d is Dictionary else ""
			if pic == "" or not _exists(pic):
				m.problems.append("Cosmetic %s: picture not found" % look_id)
				continue
			m.cosmetics["%s.%s" % [id, ArenaMap.slug(str(look_id))]] = {"name": str(d.get("name", look_id)).left(20),
				"picture": pic, "slot": "face" if str(d.get("slot", "head")) == "face" else "head", "mod": id,
				"offset": _value(d.get("offset", [0, 0])) if _value(d.get("offset", [0, 0])) is Vector2 else Vector2.ZERO}
	m.modes = {}
	var modes = data.get("modes", {})
	if modes is Dictionary:
		for mode_id in modes:
			var d = modes[mode_id]
			var script := _file(m, str(d.get("script", ""))) if d is Dictionary else ""
			if not script.ends_with(".gd") or not _exists(script):
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
	if str(d.get("kind", "")) in ["help", "trap", "bomb"]:
		def.kind = str(d.kind)
	for flag in ["host", "bomb", "special"]:
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
		if not script.ends_with(".gd") or not _exists(script):
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


## Loads a picture from a mod: imported by Godot (packs, res://) or a plain png, jpg
## or webp file (folders).
func texture(file: String) -> Texture2D:
	if file.begins_with("res://") and ResourceLoader.exists(file):
		return ResourceLoader.load(file, "", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	var img := Image.load_from_file(file)
	return ImageTexture.create_from_image(img) if img else null


func _apply_textures(m: Dictionary) -> void:
	for game_path in m.textures:
		var t := texture(m.textures[game_path])
		if t:
			t.take_over_path(game_path)
			_keep.append(t)


## A blank mod entry.
func _entry(id: String, name: String) -> Dictionary:
	return {"id": id, "name": name, "author": "", "version": "1", "description": "", "path": "", "icon": "",
		"kind": "folder", "enabled": true, "items": {}, "modes": {}, "cosmetics": {}, "textures": {}, "maps": "", "problems": []}


## A file of a mod: a scene, script or picture (Godot export may have renamed it).
func _exists(p: String) -> bool:
	return ResourceLoader.exists(p) or FileAccess.file_exists(p)


# --- Mod packs ------------------------------------------------------------------------

func _pack_files() -> Array:
	var out := []
	for f in DirAccess.get_files_at(DIR):
		if f.get_extension().to_lower() in ["pck", "zip"]:
			out.append(DIR.path_join(f))
	out.sort()
	return out


## A pack's id before it's loaded: its file name (the mod kit names it after the mod).
func _pack_id(file: String) -> String:
	return ArenaMap.slug(file.get_file().get_basename())


## True when the game project has the pack's folder (you're making that mod in Godot):
## the pack would hide your latest changes, so it isn't loaded.
func _shadowed(file: String) -> bool:
	return DirAccess.dir_exists_absolute(PROJECT_DIR.path_join(_pack_id(file))) and not _mounted.has(file) \
		and not _mounted.values().any(func(ids): return _pack_id(file) in ids)


## Loads a pack: its files show up in res://mods/<id>/. Packs never replace the
## game's own files.
func _mount(file: String) -> void:
	if _shadowed(file):
		return
	var before := DirAccess.get_directories_at(PROJECT_DIR)
	if not ProjectSettings.load_resource_pack(file, false):
		push_warning("Mods: couldn't load " + file)
		return
	var ids := []
	for d in DirAccess.get_directories_at(PROJECT_DIR):
		if not d in before:
			ids.append(d)
	if ids.is_empty() and DirAccess.dir_exists_absolute(PROJECT_DIR.path_join(_pack_id(file))):
		ids.append(_pack_id(file))
	_mounted[file] = ids
