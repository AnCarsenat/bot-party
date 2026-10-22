class_name SaveStates
## Save states (console "savestate" / "loadstate", or --state=NAME at start): where
## everyone is in a level, the party (scores, placed items, round) and crates.
## Kept in user://states/<name>.state (Godot text format, readable).
## Doors and lifts follow their buttons, so they come back on their own; toggle
## switches and timers start fresh.

const DIR := "user://states"


static func _path(name: String) -> String:
	return "%s/%s.state" % [DIR, ArenaMap.slug(name)]


static func list() -> Array:
	var out := []
	if DirAccess.dir_exists_absolute(DIR):
		for f in DirAccess.get_files_at(DIR):
			if f.ends_with(".state"):
				out.append(f.trim_suffix(".state"))
	return out


## Saves the running level. Returns a message.
static func save(tree: SceneTree, name: String) -> String:
	var scene := tree.current_scene
	if scene == null or scene.scene_file_path == "":
		return "Nothing to save here"
	var gs := tree.root.get_node("GameState")
	var party := tree.root.get_node("Party")
	var data := {
		"scene": scene.scene_file_path,
		"level": gs.current_level,
		"campaign": gs.campaign_id,
		"joined": Array(gs.joined),
		"party": party.session.duplicate(true) if scene.has_node("PartyController") else {},
		"players": {},
		"bodies": {},
		"time": Time.get_datetime_string_from_system(),
	}
	for p in tree.get_nodes_in_group("players"):
		if p is CharacterBody2D and p.is_inside_tree():
			data.players[p.name] = {"pos": p.global_position, "vel": p.velocity,
				"eliminated": p.get_meta("eliminated", false), "finished": p.get_meta("finished", false)}
	for b in scene.find_children("*", "RigidBody2D", true, false):
		data.bodies[str(scene.get_path_to(b))] = {"pos": b.global_position, "rot": b.global_rotation,
			"vel": b.linear_velocity, "spin": b.angular_velocity}
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(_path(name), FileAccess.WRITE)
	if f == null:
		return "Can't write " + _path(name)
	f.store_string(var_to_str(data))
	return "Saved state \"%s\"" % ArenaMap.slug(name)


## Loads a state: opens its level, then puts everyone back. Returns a message.
static func load_state(tree: SceneTree, name: String) -> String:
	var path := _path(name)
	if not FileAccess.file_exists(path):
		return "No state \"%s\" (try: states)" % name
	var data = str_to_var(FileAccess.get_file_as_string(path))
	if not data is Dictionary or not ResourceLoader.exists(str(data.get("scene", ""))):
		return "That state can't be read"
	var gs := tree.root.get_node("GameState")
	var party := tree.root.get_node("Party")
	if data.campaign != "":
		gs.campaign_id = data.campaign
	gs.current_level = int(data.level)
	if not data.joined.is_empty():
		gs.joined.assign(data.joined)
	if not data.party.is_empty():
		party.session = data.party
	var old := tree.current_scene
	tree.root.get_node("Transition").change_scene(data.scene)
	_restore.call_deferred(tree, data, old)
	return "Loading state \"%s\" (%s)" % [ArenaMap.slug(name), data.time]


static func _restore(tree: SceneTree, data: Dictionary, old: Node) -> void:
	# Wait for the new level to be there (not the one we were in) and its players to appear.
	for k in 600:
		await tree.physics_frame
		var scene := tree.current_scene
		if scene and scene != old and is_instance_valid(scene) and scene.scene_file_path == data.scene:
			break
	await tree.physics_frame
	await tree.physics_frame
	var scene := tree.current_scene
	if scene == null:
		return
	for n in data.players:
		var p = scene.get_node_or_null(NodePath(n))
		if p is CharacterBody2D:
			p.global_position = data.players[n].pos
			p.velocity = data.players[n].vel
			if data.players[n].finished:
				p.set_meta("finished", true)
	for path in data.bodies:
		var b = scene.get_node_or_null(NodePath(path))
		if b is RigidBody2D:
			var st: Dictionary = data.bodies[path]
			PhysicsServer2D.body_set_state(b.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(st.rot, st.pos))
			b.linear_velocity = st.vel
			b.angular_velocity = st.spin
