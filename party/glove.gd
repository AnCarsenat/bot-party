extends Node2D
## Special item: a punching glove on a spring. It punches every 3 seconds (it
## shakes just before), launching whoever is in front of it at 45°, up and in the
## direction it faces. Turn it and flip it while placing it.

const TEX_BASE := preload("res://party/art/glove_base.webp")
const TEX_FIST := preload("res://party/art/glove_fist.webp")
## Where the spring comes out of the stand (local, the stand facing right).
const MOUTH := Vector2(8, -8)
## How far the glove shoots out.
const REACH := 72.0
## Seconds between punches.
const PERIOD := 3.0
## It shakes this long before each punch.
const WARN := 0.8

@export var punch_speed := 1300.0

var _t := 0.0
var _zone: Area2D


func _ready() -> void:
	add_to_group("net_sync")
	add_to_group("net_sync_slow")  # clients run the clock themselves
	var base := StaticBody2D.new()
	base.collision_layer = Layers.WORLD
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(54, 20)
	cs.shape = r
	cs.position = Vector2(-2, 18)
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
	_t = 0.0


## Seconds until the next punch (bots and looks).
func next_punch() -> float:
	return PERIOD - fmod(_t, PERIOD)


func _physics_process(delta: float) -> void:
	var before := int(_t / PERIOD)
	_t += delta
	if int(_t / PERIOD) == before:
		return
	# Punch!
	if NetCheck.client(self):
		return
	for p in _robots():
		p.bounce(punch_speed, 1.0, direction())


func _robots() -> Array:
	return _zone.get_overlapping_bodies().filter(func(b): return b.has_method("bounce") and not b.get_meta("eliminated", false))


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	var shake := Vector2.ZERO
	var left := next_punch()
	if left < WARN:
		shake = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * (1.0 + (1.0 - left / WARN) * 3.0)
	# The punch: the glove shoots out fast, stays a moment, then the spring pulls it back.
	var since := fmod(_t, PERIOD) if _t >= PERIOD else 99.0
	var out := 0.0
	if since < 0.07:
		out = since / 0.07
	elif since < 0.22:
		out = 1.0
	elif since < 0.6:
		out = 1.0 - (since - 0.22) / 0.38
	var dir := Vector2(1, -1).normalized()
	var fist := MOUTH + dir * (12.0 + REACH * out) + shake
	# Spring: a zigzag from the stand to the glove.
	var a := MOUTH + shake * 0.5
	var b := fist - dir * 10.0
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([a])
	var turns := 6
	for i in range(1, turns):
		pts.append(a.lerp(b, float(i) / turns) + side * (5.0 if i % 2 == 0 else -5.0))
	pts.append(b)
	draw_polyline(pts, Color.BLACK, 6.0)
	draw_polyline(pts, Color("d2d5d3"), 2.5)
	draw_texture_rect(TEX_BASE, Rect2(Vector2(-32, -32) + shake * 0.5, Vector2(64, 64)), false)
	draw_texture_rect(TEX_FIST, Rect2(fist - Vector2(16, 16), Vector2(32, 32)), false)


func net_state() -> Array:
	return [snappedf(_t, 0.01)]


func net_apply(s: Array) -> void:
	# Online client: a little ahead of the host's clock (what we see is what
	# the host will check our robot against).
	var host_t: float = s[0] + NetCheck.lead(self)
	if absf(_t - host_t) > 0.08:
		_t = host_t
