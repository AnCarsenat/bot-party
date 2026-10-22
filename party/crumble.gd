extends StaticBody2D
## Breaks a moment after someone stands on it. Comes back every round.

@export var delay: float = 0.45

var _broken := false
var _break_left := 0.0
var _tween: Tween
@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var _sprite: Sprite2D = $Sprite2D
@onready var _sensor: Area2D = $Sensor


func _ready() -> void:
	_sensor.collision_layer = 0
	_sensor.collision_mask = Layers.PLAYERS | Layers.CRATES
	_sensor.body_entered.connect(func(_b): _start_break())
	add_to_group("net_sync")


func net_state() -> Array:
	return [_broken]


func net_apply(s: Array) -> void:
	if s[0] and not _broken:
		_start_break()
	elif not s[0] and _broken:
		reset_round()


func _start_break() -> void:
	if _broken:
		return
	_broken = true
	_break_left = delay
	_kill_tween()
	_tween = create_tween()
	for i in 4:
		_tween.tween_property(_sprite, "position:x", 3.0, delay / 8.0)
		_tween.tween_property(_sprite, "position:x", -3.0, delay / 8.0)


## The block gives way on a timer (not a tween callback), so the collision and
## the picture can't get out of step.
func _physics_process(delta: float) -> void:
	if _break_left > 0.0:
		_break_left -= delta
		if _break_left <= 0.0:
			_shape.set_deferred("disabled", true)
			_kill_tween()
			_tween = create_tween()
			_tween.tween_property(_sprite, "modulate:a", 0.0, 0.15)


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null


func reset_round() -> void:
	_kill_tween()
	_broken = false
	_break_left = 0.0
	_shape.set_deferred("disabled", false)
	_sprite.position = Vector2.ZERO
	_sprite.modulate.a = 1.0
