@tool
extends Node
## Mod kit: make mods for Bot Party in Godot. Open editor/mod_kit.tscn, select the
## ModKit node, and use the buttons in the inspector:
##
##   1. Type a name in "New mod" and press "Create the mod": this makes the folder
##      res://mods/<name>/ with a mod.json, and a map scene in its maps folder.
##   2. Put your scenes, scripts, pictures and map scenes in that folder, and list
##      them in mod.json (see MODDING.md). Run the game (F5) to try the mod: when
##      the game runs from Godot, it uses the folder directly.
##   3. Press "Export the mod pack": this writes <name>.pck to the game's mods
##      folder, where the installed game finds it. Give that file to other players
##      (also copied to "Copy to", if you set it).

const PACKER := preload("res://editor/mod_packer.gd")
const TEMPLATE := "res://editor/arena_template.tscn"

@export_group("New mod")
## Lower case, no spaces: it's the mod's id (like my_mod).
@export var new_mod := "my_mod"
@export_tool_button("Create the mod", "Add") var create_button := create_mod

@export_group("Mod")
## The mod folder to work on.
@export_dir var mod_folder := "res://mods/example"
@export_tool_button("New map scene in this mod", "PackedScene") var map_button := new_map
@export_tool_button("Switch it on in the game", "GuiVisibilityVisible") var on_button := switch_on
## Where else to put the exported pack (to share it), besides the game's mods folder.
@export_global_dir var copy_to := ""
@export_tool_button("Export the mod pack", "Save") var export_button := export_pack
@export_tool_button("Open the game's mods folder", "Folder") var open_button := open_mods


func create_mod() -> void:
	var id := new_mod.strip_edges().to_lower().replace(" ", "_").replace("-", "_")
	var dir := "res://mods".path_join(id)
	if id == "" or not id.is_valid_filename():
		push_error("Mod kit: \"%s\" can't be a folder name" % new_mod)
		return
	if DirAccess.dir_exists_absolute(dir):
		push_error("Mod kit: %s already exists" % dir)
		return
	DirAccess.make_dir_recursive_absolute(dir.path_join("maps"))
	var info := {"name": new_mod.capitalize(), "author": "", "version": "1.0",
		"description": "", "items": {}, "modes": {}, "textures": {}, "maps": "maps"}
	var f := FileAccess.open(dir.path_join("mod.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(info, "  ") + "\n")
	f = null
	mod_folder = dir
	new_map()
	switch_on()
	notify_property_list_changed()
	print("Mod kit: made %s. Next: add your things and list them in its mod.json (see MODDING.md)." % dir)


## Copies the map template into the mod's maps folder and opens it.
func new_map() -> void:
	var maps := mod_folder.path_join("maps")
	DirAccess.make_dir_recursive_absolute(maps)
	var n := 1
	while FileAccess.file_exists(maps.path_join("map_%d.tscn" % n)):
		n += 1
	var path := maps.path_join("map_%d.tscn" % n)
	var scene: PackedScene = load(TEMPLATE)
	var root := scene.instantiate()
	root.set("map_name", "%s map %d" % [mod_folder.get_file().capitalize(), n])
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	ResourceSaver.save(packed, path)
	if Engine.is_editor_hint() and Engine.has_singleton("EditorInterface"):
		var ed = Engine.get_singleton("EditorInterface")
		ed.get_resource_filesystem().scan()
		ed.open_scene_from_path.call_deferred(path)
	print("Mod kit: new map scene ", path)


## Turns the mod on in the game's Settings > Mods (it's off at first).
func switch_on() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://mods.cfg")
	cfg.set_value("enabled", mod_folder.get_file(), true)
	cfg.save("user://mods.cfg")
	print("Mod kit: %s is on in the game (Settings > Mods)" % mod_folder.get_file())


func export_pack() -> void:
	var id := mod_folder.trim_suffix("/").get_file()
	var out := "user://mods".path_join(id + ".pck")
	var err: String = PACKER.pack(mod_folder, out)
	if err != "":
		push_error("Mod kit: " + err)
		return
	print("Mod kit: exported ", ProjectSettings.globalize_path(out))
	if copy_to != "":
		var copy := copy_to.path_join(id + ".pck")
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(out), copy) == OK:
			print("Mod kit: copied to ", copy)
		else:
			push_error("Mod kit: couldn't copy to " + copy)


func open_mods() -> void:
	DirAccess.make_dir_recursive_absolute("user://mods")
	OS.shell_open(ProjectSettings.globalize_path("user://mods"))
