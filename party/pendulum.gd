extends Node2D
## Pendulum: a weight swinging from a mount. It doesn't hurt by itself, but it has
## two attachment points (halfway down the arm and on the weight): place another
## item near one and it swings along. The dotted arc shows where the weight goes.

@export var length: float = 170.0
## Half the swing, in radians.
@export var swing: float = 1.05
@export var period: float = 2.6

var mirrored := false
var _t := 0.0
var _head: AnimatableBody2D
var _mounts: Array[ItemMount] = []


func set_mirrored(value: bool) -> void:
	mirrored = value


func _ready() -> void:
	add_to_group("net_sync")
	add_to_group("net_sync_slow")  # clients run the clock themselves
	# The weight is solid: you can bump into it or hop on it.
	_head = AnimatableBody2D.new()
	_head.collision_layer = Layers.WORLD
	_head.collision_mask = 0
	_head.sync_to_physics = false
	var core := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 18.0
	core.shape = c
	_head.add_child(core)
	add_child(_head)
	for k in 2:
		var m := ItemMount.new()
		m.name = "Mount%d" % k
		m.z_index = 1
		add_child(m)
		_mounts.append(m)
	_place()


## Attachment points (used by party mode): halfway down, and the weight.
func mounts() -> Array[ItemMount]:
	return _mounts


func angle() -> float:
	return sin(_t / period * TAU) * swing * (-1.0 if mirrored else 1.0)


## How far attachment point `m` will have moved `t` seconds from now (bots plan
## with it: what hangs there swings along).
func mount_moved_by(m: ItemMount, t: float) -> Vector2:
	var a := sin((_t + t) / period * TAU) * swing * (-1.0 if mirrored else 1.0)
	var k := 0.5 if _mounts.find(m) == 0 else 1.0
	return global_transform.basis_xform(Vector2(0, length * k).rotated(a) - m.position)


func reset_round() -> void:
	_t = 0.0
	_place()


func _physics_process(delta: float) -> void:
	_t += delta
	_place()


func _place() -> void:
	var a := angle()
	_head.position = Vector2(0, length).rotated(a)
	_head.rotation = a
	_mounts[0].position = Vector2(0, length * 0.5).rotated(a)
	_mounts[1].position = _head.position
	for m in _mounts:
		m.rotation = -global_rotation  # attached items stay upright


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	# Path: dotted arc the weight sweeps.
	var from := PI / 2.0 - swing
	var to := PI / 2.0 + swing
	for i in 13:
		var a := lerpf(from, to, i / 12.0)
		draw_circle(Vector2(cos(a), sin(a)) * length, 3.0, Color(0, 0, 0, 0.45))
	# Arm.
	var tip := _head.position if _head else Vector2(0, length)
	draw_line(Vector2.ZERO, tip, Color.BLACK, 8.0)
	draw_line(Vector2.ZERO, tip, Color("6cba7c"), 4.0)
	# Weight.
	draw_circle(tip, 20.0, Color.BLACK)
	draw_circle(tip, 17.0, Color("b0e2bc"))
	draw_circle(tip + Vector2(-5, -5), 5.0, Color("f0fff4"))
	# Mount at the top.
	draw_rect(Rect2(-22, -12, 44, 16), Color.BLACK)
	draw_rect(Rect2(-19, -9, 38, 10), Color("b0e2bc"))
	draw_circle(Vector2.ZERO, 6.0, Color.BLACK)
	draw_circle(Vector2.ZERO, 3.0, Color("f0fff4"))


# Online: clients follow the host's clock (corrected when they drift apart).
func net_state() -> Array:
	return [snappedf(_t, 0.01)]


func net_apply(s: Array) -> void:
	if absf(_t - s[0]) > 0.1:
		_t = s[0]
