extends Node

## Restart the level automatically when every player has been eliminated.
@export var restart_when_all_out: bool = true
@export var restart_delay: float = 1.0

var eliminated_players: Array[Node] = []
var next_player_number: int = 1


func assign_player_input(player: CharacterBody2D) -> void:
	var prefix := "p%d" % next_player_number

	# Only hand out prefixes that actually exist in the Input Map,
	# so the player count can never exceed the configured actions.
	if not InputMap.has_action(prefix + "_move_left"):
		push_warning("No input actions defined for %s: maximum players reached." % prefix)
		return

	player.input_prefix = prefix
	next_player_number += 1


func eliminate_player(player: Node) -> void:
	if not is_instance_valid(player):
		return
	if NetCheck.client(self) and not NetCheck.applying(self):
		return  # online: the host decides who is out
	if player.get_meta("god", false) and not NetCheck.applying(self):
		return  # console: god mode

	if player.get_meta("eliminated", false):
		return

	player.set_meta("eliminated", true)
	player.remove_from_group("camera_follow")
	eliminated_players.append(player)

	if player is CharacterBody2D:
		player.velocity = Vector2.ZERO

	player.set_physics_process(false)
	player.set_process(false)
	if player is Node2D and player.is_inside_tree():
		get_parent().add_child(Effects.burst(player.global_position, player.get_meta("color", Color.WHITE), 22))
	player.hide()
	# Stop colliding too (otherwise an invisible body keeps blocking others).
	player.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)

	print(player.name, " has been eliminated!")

	if restart_when_all_out and _alive_players() == 0:
		await get_tree().create_timer(restart_delay).timeout
		restart_level()


func restart_level() -> void:
	var transition := get_tree().root.get_node_or_null("Transition")
	if transition:
		transition.reload()
	else:
		get_tree().reload_current_scene()


func _alive_players() -> int:
	var n := 0
	for p in get_tree().get_nodes_in_group("players"):
		if not p.get_meta("eliminated", false):
			n += 1
	return n
