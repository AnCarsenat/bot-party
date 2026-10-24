extends Node2D
## Special item: a punching glove on a spring. When a robot steps in front of it,
## it winds up for 3 seconds (shaking), then punches whoever is there at 45°, up
## and in the direction it faces. Turn it and flip it while placing it.

const TEX := preload("res://party/art/glove.webp")
const WIND_UP := 3.0
const COOLDOWN := 1.0

@export var punch_speed := 1300.0

var _wind := -1.0   # seconds of wind-up left (-1: waiting for someone)
var _cool := 0.0
var _punch := 0.0   # glove sticking out (looks)
var _zone: Area2D


func _ready() -> void:
	add_to_group("net_sync")
	var base := StaticBody2D.new()
	base.collision_layer = Layers.WORLD
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(40, 30)
	cs.shape = r
	cs.position = Vector2(-14, 18)
	base.add_child(cs)
	add_child(base)
	_zone = Area2D.new()
	_zone.name = "Zone"
	_zone.collision_layer = 0
	_zone.collision_mask = Layers.PLAYERS
	_zone.monitorable = false
	var zs := CollisionShape2D.new()
	var zr := RectangleShape2D.new()
	zr.size = Vector2(110, 90)
	zs.shape = zr
	zs.position = Vector2(30, -20)
	_zone.add_child(zs)
	add_child(_zone)


## Up and forward at 45°, whichever way it's turned or flipped.
func direction() -> Vector2:
	var fwd := global_transform.x.normalized()
	var up := -global_transform.y.normalized()
	return (fwd + up).normalized()


func reset_round() -> void:
	_wind = -1.0
	_cool = 0.0
	_punch = 0.0


func _physics_process(delta: float) -> void:
	_punch = maxf(0.0, _punch - delta * 3.0)
	if NetCheck.client(self):
		return
	if _cool > 0.0:
		_cool -= delta
		return
	var inside := _robots()
	if _wind < 0.0:
		if not inside.is_empty():
			_wind = WIND_UP
		return
	_wind -= delta
	if _wind <= 0.0:
		for p in inside:
			p.bounce(punch_speed, 1.0, direction())
		_wind = -1.0
		_cool = COOLDOWN
		_punch = 1.0


func _robots() -> Array:
	return _zone.get_overlapping_bodies().filter(func(b): return b.has_method("bounce") and not b.get_meta("eliminated", false))


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	var shake := Vector2.ZERO
	if _wind > 0.0:
		var k := 1.0 - _wind / WIND_UP
		shake = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * (1.0 + k * 3.0)
	var out := Vector2(18, -18) * _punch
	draw_texture_rect(TEX, Rect2(Vector2(-32, -32) + shake + out, Vector2(64, 64)), false)


func net_state() -> Array:
	return [snappedf(_wind, 0.05), snappedf(_punch, 0.05)]


func net_apply(s: Array) -> void:
	_wind = s[0]
	_punch = maxf(_punch, s[1])
