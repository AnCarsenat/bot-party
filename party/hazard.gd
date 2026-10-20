class_name Hazard
extends Area2D
## Eliminates any player who touches it. In party mode, `owner_slot` is the
## player who placed it (they get a point for each other player it gets).

var owner_slot := 0


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.PLAYERS
	monitorable = false
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("players") or body.get_meta("eliminated", false) or body.get_meta("finished", false):
		return
	var game := get_tree().current_scene.get_node_or_null("Game") if get_tree().current_scene else null
	if game:
		game.eliminate_player(body)
	for c in get_tree().get_nodes_in_group("party_controller"):
		c.on_trap_kill(owner_slot, body)
