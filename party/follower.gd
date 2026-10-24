extends Node2D
## Special item: an attachment point that slowly drifts toward the nearest racer
## during the race, carrying whatever hangs from it. It stops at walls, and goes
## back to where it was placed at the start of every round.

const TEX := preload("res://party/art/follower.webp")

@export var speed := 60.0

var _home := Vector2.ZERO
var _mount: ItemMount
var _bob := 0.0


func _ready() -> void:
	add_to_group("net_sync")
	_home = position
	_mount = ItemMount.new()
	_mount.name = "Mount0"
	_mount.position = Vector2(0, 44)
	add_child(_mount)


## Attachment points (party mode).
func mounts() -> Array[ItemMount]:
	return [_mount]


func reset_round() -> void:
	position = _home


func _physics_process(delta: float) -> void:
	_bob += delta
	if NetCheck.client(self):
		return
	var ctl = get_tree().get_first_node_in_group("party_controller")
	if ctl == null or ctl.phase != ctl.Phase.RUN:
		return
	var target := Vector2.INF
	var best := INF
	for p in get_tree().get_nodes_in_group("players"):
		if p.get_meta("eliminated", false) or p.get_meta("finished", false) or not p.visible:
			continue
		var d: float = global_position.distance_to(p.global_position)
		if d < best:
			best = d
			target = p.global_position
	if target == Vector2.INF or best < 8.0:
		return
	var step := (target - global_position).limit_length(speed * delta)
	# Each way on its own, so it slides along a wall instead of stopping dead.
	for part in [Vector2(step.x, 0), Vector2(0, step.y)]:
		if part != Vector2.ZERO and not _blocked(part):
			global_position += part


func _blocked(step: Vector2) -> bool:
	var from := global_position
	var q := PhysicsRayQueryParameters2D.create(from, from + step + step.normalized() * 34.0, Layers.WORLD)
	q.exclude = _own_bodies()
	return not get_world_2d().direct_space_state.intersect_ray(q).is_empty()


## What hangs from it doesn't block it.
func _own_bodies() -> Array[RID]:
	var out: Array[RID] = []
	for b in find_children("*", "CollisionObject2D", true, false):
		out.append(b.get_rid())
	return out


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	var y := sin(_bob * 3.0) * 3.0
	draw_texture_rect(TEX, Rect2(-32, -40 + y, 64, 64), false)


func net_state() -> Array:
	return [Vector2i(position.round())]


func net_apply(s: Array) -> void:
	position = position.lerp(Vector2(s[0]), 0.5)
