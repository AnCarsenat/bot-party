extends Node2D
## Special item: a saw whose blade glides back and forth along a long S-shaped
## rail, always the same way, so it can be timed. Turn and flip it while placing
## it to change which way the wave goes.

@export var travel := 170.0
## Height of the wave above and below the middle.
@export var amplitude := 64.0
## How many half-waves along the rail (2: one full S).
@export var waves := 2.0
## Seconds for a full trip there and back.
@export var period := 3.6
@export var spin_speed := 11.0

var _t := 0.0
@onready var _blade: Node2D = $Blade
@onready var _sprite: Node2D = $Blade/Sprite2D


func _ready() -> void:
	add_to_group("net_sync")
	add_to_group("net_sync_slow")  # clients run the clock themselves
	_blade.position = path_at(0.0)


## Where the blade is `t` seconds into the round.
func path_at(t: float) -> Vector2:
	var x := sin(TAU * t / period) * travel
	return Vector2(x, _wave(x))


## How far the blade will have moved `t` seconds from now (bots plan with it).
func moved_by(t: float) -> Vector2:
	return global_transform.basis_xform(path_at(_t + t) - _blade.position)


func _wave(x: float) -> float:
	return -sin(PI * waves * (x + travel) / (2.0 * travel)) * amplitude


func _physics_process(delta: float) -> void:
	_t += delta
	_blade.position = path_at(_t)
	_sprite.rotation += spin_speed * delta


func reset_round() -> void:
	_t = 0.0
	_blade.position = path_at(0.0)


func _draw() -> void:
	# The rail, like the saw's: where the blade will go.
	var pts := PackedVector2Array()
	for i in 49:
		var x := -travel + 2.0 * travel * i / 48.0
		pts.append(Vector2(x, _wave(x)))
	draw_polyline(pts, Color.BLACK, 8.0)
	draw_polyline(pts, Color("6cba7c"), 4.0)
	for p in [pts[0], pts[pts.size() - 1]]:
		draw_circle(p, 7.0, Color.BLACK)
		draw_circle(p, 4.0, Color("b0e2bc"))


func net_state() -> Array:
	return [snappedf(_t, 0.01)]


func net_apply(s: Array) -> void:
	if absf(_t - s[0]) > 0.1:
		_t = s[0]
