@tool
class_name PlayerCountFilter
extends Node2D
## Container: its children only exist when the number of players is in range.
## Use it to make solo-only helpers or co-op-only puzzles inside one level.

@export_range(1, 8) var min_players: int = 1:
	set(value):
		min_players = value
		queue_redraw()
@export_range(1, 8) var max_players: int = 8:
	set(value):
		max_players = value
		queue_redraw()


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		return
	var gs := get_tree().root.get_node_or_null("GameState")
	var count: int = gs.player_count if gs else 2
	var top: Node = self
	while top.get_parent() != null and top.get_parent() != get_tree().root:
		top = top.get_parent()
	var spawner := _find_spawner(top)
	if spawner and spawner.force_player_count > 0:
		count = spawner.force_player_count
	if count < min_players or count > max_players:
		# Disabled nodes leave the physics world immediately; then remove them.
		process_mode = Node.PROCESS_MODE_DISABLED
		hide()
		queue_free()


func _find_spawner(root: Node) -> Node:
	if root == null:
		return null
	for n in root.find_children("*", "Node2D", true, false):
		if n is PlayerSpawner:
			return n
	return null


func _process(_d: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var text := "%d-%d players" % [min_players, max_players]
	if min_players == max_players:
		text = "%d player%s only" % [min_players, "" if min_players == 1 else "s"]
	elif max_players == 8:
		text = "%d+ players" % min_players
	draw_string(ThemeDB.fallback_font, Vector2(0, -8), "[" + text + "]", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.85, 0.3))
