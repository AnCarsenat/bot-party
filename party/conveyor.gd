extends StaticBody2D
## Carries whoever stands on it. Mirror it (action 3 while placing) to reverse it.

@export var speed: float = -170.0

var mirrored := false
var _scroll := 0.0

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	_apply()


func set_mirrored(value: bool) -> void:
	mirrored = value
	if is_inside_tree():
		_apply()


func _apply() -> void:
	var s := -speed if mirrored else speed
	constant_linear_velocity = Vector2(s, 0).rotated(global_rotation)
	_sprite.flip_h = mirrored


func _process(delta: float) -> void:
	_scroll += delta * absf(speed) / 24.0
	var f := int(_scroll) % _sprite.hframes
	_sprite.frame = (_sprite.hframes - 1 - f) if mirrored else f
