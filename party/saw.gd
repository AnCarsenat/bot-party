extends Node2D
## A spinning blade sliding back and forth along its rail (the rail shows the path).

@export var travel: float = 90.0
@export var period: float = 2.4
@export var spin_speed: float = 9.0

var _t := 0.0
@onready var _blade: Node2D = $Blade
@onready var _sprite: Node2D = $Blade/Sprite2D


func _ready() -> void:
	add_to_group("net_sync")
	add_to_group("net_sync_slow")  # clients run the clock themselves


func _physics_process(delta: float) -> void:
	_t += delta
	_blade.position.x = sin(_t / period * TAU) * travel
	_sprite.rotation += spin_speed * delta


func reset_round() -> void:
	_t = 0.0
	_blade.position.x = 0.0


func _draw() -> void:
	# Rail: where the blade will go.
	var a := Vector2(-travel, 0)
	var b := Vector2(travel, 0)
	draw_line(a, b, Color.BLACK, 8.0)
	draw_line(a, b, Color("6cba7c"), 4.0)
	for p in [a, b]:
		draw_circle(p, 7.0, Color.BLACK)
		draw_circle(p, 4.0, Color("b0e2bc"))


# Online: clients follow the host's clock (corrected when they drift apart).
func net_state() -> Array:
	return [snappedf(_t, 0.01)]


func net_apply(s: Array) -> void:
	if absf(_t - s[0]) > 0.1:
		_t = s[0]
