extends Node2D
## Special item: a saw whose blade goes back and forth along a long, wavy path,
## speeding up and slowing down. Each one gets its own path when it's placed
## (from its id, so it's the same on every computer online).

@export var travel := 170.0
@export var spin_speed := 11.0

var period := 3.2
var amplitude := 60.0
var waves := 1.5
var wobble := 0.6
var _t := 0.0
@onready var _blade: Node2D = $Blade
@onready var _sprite: Node2D = $Blade/Sprite2D


func _ready() -> void:
	add_to_group("net_sync")
	add_to_group("net_sync_slow")  # clients run the clock themselves
	var rng := RandomNumberGenerator.new()
	rng.seed = int(get_meta("record", {}).get("uid", 0)) * 7919 + 13
	period = rng.randf_range(2.6, 4.2)
	amplitude = rng.randf_range(40.0, 90.0) * (1.0 if rng.randf() < 0.5 else -1.0)
	waves = rng.randf_range(1.0, 2.5)
	wobble = rng.randf_range(0.3, 0.9)
	_blade.position = path_at(0.0)


## Where the blade is `t` seconds into the round.
func path_at(t: float) -> Vector2:
	var u := TAU * t / period + wobble * sin(TAU * t / (period * 0.61))
	var x := sin(u) * travel
	return Vector2(x, sin(PI * waves * x / travel) * amplitude)


func _physics_process(delta: float) -> void:
	_t += delta
	_blade.position = path_at(_t)
	_sprite.rotation += spin_speed * delta


func reset_round() -> void:
	_t = 0.0
	_blade.position = path_at(0.0)


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	# The path: a dotted rail.
	var n := 40
	for i in n + 1:
		var x := -travel + 2.0 * travel * i / n
		var p := Vector2(x, sin(PI * waves * x / travel) * amplitude)
		draw_circle(p, 5.0, Color.BLACK)
		draw_circle(p, 3.0, Color("6cba7c"))


func net_state() -> Array:
	return [snappedf(_t, 0.01)]


func net_apply(s: Array) -> void:
	if absf(_t - s[0]) > 0.1:
		_t = s[0]
