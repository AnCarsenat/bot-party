class_name ItemMount
extends Node2D
## Attachment point on a moving party item (ferris wheel rim, pendulum).
## The host moves the mount; whatever is attached is its child and comes along.
## Attached items stay upright (they keep the turn they were placed with).
## Solid parts are given the speed they really move at (the mount's, plus their
## own for a lift), so players standing on them are carried too. Moving
## platforms (lifts, planks) follow the mount at once instead of staying put
## where their physics body was.

var velocity := Vector2.ZERO
var _prev := Vector2.INF


## Something is attached here.
func occupied() -> bool:
	for c in get_children():
		if not c.is_queued_for_deletion():
			return true
	return false


func _physics_process(delta: float) -> void:
	if _prev != Vector2.INF and delta > 0.0:
		velocity = (global_position - _prev) / delta
	_prev = global_position
	for body in find_children("*", "StaticBody2D", true, false):
		if body is AnimatableBody2D and body.sync_to_physics:
			# Synced bodies only follow their own moves, not their parent's: the
			# platform would stay where it was (and carry players like a belt).
			body.sync_to_physics = false
		if not body.has_meta("base_velocity"):
			body.set_meta("base_velocity", body.constant_linear_velocity)
		var at: Vector2 = body.global_position
		var was: Vector2 = body.get_meta("mount_prev", at)
		body.set_meta("mount_prev", at)
		var moved := (at - was) / delta if delta > 0.0 else Vector2.ZERO
		if moved.length() > 3000.0:
			moved = velocity  # (just attached, or a jump)
		body.constant_linear_velocity = body.get_meta("base_velocity") + moved


func _draw() -> void:
	if occupied():
		return
	# Free point: a little bolt you can hang things on.
	draw_circle(Vector2.ZERO, 9.0, Color.BLACK)
	draw_circle(Vector2.ZERO, 6.0, Color("d7ffac"))
	draw_circle(Vector2.ZERO, 2.0, Color.BLACK)


func _process(_d: float) -> void:
	queue_redraw()
