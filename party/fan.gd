extends Node2D
## Blows players (and crates) upwards inside the column above it.

@export var strength: float = 3800.0
@export var max_up_speed: float = 620.0

var _t := 0.0
@onready var _column: Area2D = $Column


func _ready() -> void:
	_column.collision_layer = 0
	_column.collision_mask = Layers.PLAYERS | Layers.CRATES
	_column.monitorable = false


func _physics_process(delta: float) -> void:
	var dir := Vector2.UP.rotated(global_rotation)
	for b in _column.get_overlapping_bodies():
		if b is CharacterBody2D:
			var along: float = b.velocity.dot(dir)
			if along < max_up_speed:
				b.velocity += dir * minf(strength * delta, max_up_speed - along)
			if absf(dir.x) > 0.5 and "_carry_vx" in b:
				b._carry_vx = move_toward(b._carry_vx, dir.x * max_up_speed, strength * delta)
		elif b is RigidBody2D:
			b.apply_central_force(dir * strength * b.mass * 0.4)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	# Air lines drifting up.
	for i in 6:
		var x := -24.0 + (i % 3) * 24.0
		var y := -30.0 - fmod(_t * 220.0 + i * 47.0, 240.0)
		draw_line(Vector2(x, y), Vector2(x, y - 22), Color(1, 1, 1, 0.55), 3.0)
