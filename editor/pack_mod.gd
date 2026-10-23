extends SceneTree
## Makes a mod pack from the command line (the builds use it for the example mod):
##   godot --headless --path . --script res://editor/pack_mod.gd -- res://mods/example example.pck
## Run `godot --headless --import --path .` once before, so pictures are imported.

const PACKER := preload("res://editor/mod_packer.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("usage: --script res://editor/pack_mod.gd -- res://mods/<id> <file.pck>")
		quit(1)
		return
	var out := args[1]
	if not out.begins_with("res://") and not out.begins_with("user://") and not out.is_absolute_path():
		out = OS.get_environment("PWD").path_join(out)
	var err: String = PACKER.pack(args[0], out)
	if err != "":
		printerr(err)
		quit(1)
		return
	print("Mod pack written: ", out)
	quit()
