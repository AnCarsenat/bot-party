class_name Hazard
extends Area2D
## Damage zone: eliminates any player whose hurtbox touches it.
## Traps keep their solid part (what you can stand on or bump into) in a separate
## body; the hazard area is a few pixels bigger, so touching the trap is enough.
## In party mode, `owner_slot` is the player who placed it (they get a point for
## each other player it gets).

signal hit(player: Node)

var owner_slot := 0


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.HURTBOX
	monitorable = false
	area_entered.connect(_on_area_entered)


## Party mode: projectiles vanish in the start area (no shooting people before
## the race starts).
static func in_start_area(node: Node, pos: Vector2) -> bool:
	if not node.is_inside_tree():
		return false
	var c = node.get_tree().get_first_node_in_group("party_controller")
	return c != null and c.start_zone.has_point(pos)


## Where a projectile going from `from` along `dir` would stop: the first solid
## thing in `stoppers` (0 = flies through everything), the start area, or `max_len`.
static func path_end(node: Node2D, from: Vector2, dir: Vector2, max_len: float, stoppers: int) -> Vector2:
	var to := from + dir * max_len
	if stoppers != 0:
		var q := PhysicsRayQueryParameters2D.create(from, to, stoppers)
		q.hit_from_inside = true  # starting inside a block: stops at once
		var hit := node.get_world_2d().direct_space_state.intersect_ray(q)
		if hit:
			to = hit.position
	var length := from.distance_to(to)
	var d := 0.0
	while d < length:
		if in_start_area(node, from + dir * d):
			return from + dir * d
		d += 8.0
	return to


func _on_area_entered(area: Area2D) -> void:
	var p = area.get_meta("player", null)
	if p != null and is_instance_valid(p):
		hurt(p)


## Eliminates `body` (if it's a player still in the race). Returns true if it did.
func hurt(body: Node) -> bool:
	if NetCheck.client(self):
		return false  # online: only the host's traps count
	if not body.is_in_group("players") or body.get_meta("eliminated", false) or body.get_meta("finished", false):
		return false
	if body.get_meta("god", false):
		return false  # console: god mode
	hit.emit(body)
	var scene := get_tree().current_scene
	var game := scene.get_node_or_null("Game") if scene else null
	if game:
		game.eliminate_player(body)
	for c in get_tree().get_nodes_in_group("party_controller"):
		c.on_trap_kill(owner_slot, body)
	return true
