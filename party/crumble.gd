extends StaticBody2D
## Breaks a moment after someone stands on it. Comes back every round.

@export var delay: float = 0.45

var _broken := false
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
	var tw := create_tween()
	for i in 4:
		tw.tween_property(_sprite, "position:x", 3.0, delay / 8.0)
		tw.tween_property(_sprite, "position:x", -3.0, delay / 8.0)
	tw.tween_callback(func(): _shape.set_deferred("disabled", true))
	tw.tween_property(_sprite, "modulate:a", 0.0, 0.15)


func reset_round() -> void:
	_broken = false
	_shape.set_deferred("disabled", false)
	_sprite.position = Vector2.ZERO
	_sprite.modulate.a = 1.0
