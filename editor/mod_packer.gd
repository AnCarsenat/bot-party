extends RefCounted
## Turns a mod folder of the game project (res://mods/<id>/) into a mod pack
## (<id>.pck) that the game loads from its mods folder. Used by the mod kit
## (editor/mod_kit.tscn) and by editor/pack_mod.gd (command line).
##
## The pack holds the folder's files as Godot sees them: scenes, scripts, mod.json,
## and the imported versions of pictures and sounds, so they load in the game
## exactly like in the editor.


## Checks a mod folder. Returns what's wrong with it, or "".
static func problem(dir: String) -> String:
	dir = dir.trim_suffix("/")
	if not dir.begins_with("res://mods/") or dir.count("/") != 3:
		return "A mod is a folder directly in res://mods/ (like res://mods/my_mod), not %s" % dir
	var id := dir.get_file()
	if id != id.to_lower() or not id.is_valid_filename() or " " in id:
		return "Name the folder in lower case without spaces (like my_mod): it's the mod's id"
	if FileAccess.file_exists(dir.path_join(".gdignore")):
		return "Remove the .gdignore file from %s: Godot doesn't import a folder that has one" % dir
	var json := dir.path_join("mod.json")
	if FileAccess.file_exists(json):
		if not JSON.parse_string(FileAccess.get_file_as_string(json)) is Dictionary:
			return "mod.json isn't valid JSON"
	elif not DirAccess.dir_exists_absolute(dir.path_join("maps")):
		return "No mod.json (and no maps folder) in " + dir
	return ""


## Writes the pack. Returns an error message, or "" when it worked.
static func pack(dir: String, out: String) -> String:
	dir = dir.trim_suffix("/")
	var p := problem(dir)
	if p != "":
		return p
	var files := []
	_walk(dir, files)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var pck := PCKPacker.new()
	if pck.pck_start(out) != OK:
		return "Can't write " + out
	var added := {}
	for f in files:
		if f.ends_with(".import"):
			# The imported file (in .godot/imported) is what the game loads.
			var cfg := ConfigFile.new()
			cfg.load(f)
			var found := false
			for k in (cfg.get_section_keys("remap") if cfg.has_section("remap") else PackedStringArray()):
				var imported := str(cfg.get_value("remap", k))
				if k.begins_with("path") and FileAccess.file_exists(imported):
					found = true
					if not added.has(imported):
						pck.add_file(imported, imported)
						added[imported] = true
			if not found and not cfg.get_value("remap", "importer", "") in ["keep", "skip"]:
				return "%s isn't imported yet: open the project in Godot first" % f.trim_suffix(".import")
		pck.add_file(f, f)
	if pck.flush() != OK:
		return "Can't write " + out
	return ""


static func _walk(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if not f.begins_with(".") and not f.ends_with("~"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			_walk(dir.path_join(d), out)
