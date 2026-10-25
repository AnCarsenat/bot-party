extends Node2D
## Slider: a carriage going back and forth along a rail, exactly like the saw blade,
## but harmless. It's an attachment point: place another item near the carriage and
## it rides along. Turn it to slide up and down instead.

@export var travel: float = 90.0
@export var period: float = 2.4

var _t := 0.0
var _mount: ItemMount


func _ready() -> void:
	add_to_group("net_sync")
	add_to_group("net_sync_slow")  # clients run the clock themselves
	_mount = ItemMount.new()
	_mount.name = "Mount0"
	_mount.z_index = 1
	add_child(_mount)
	_place()


## Attachment points (used by party mode).
func mounts() -> Array[ItemMount]:
	return [_mount]


func _physics_process(delta: float) -> void:
	_t += delta
	_place()


func _place() -> void:
	_mount.position = Vector2(sin(_t / period * TAU) * travel, 0)
	_mount.rotation = -global_rotation  # attached items stay upright
	queue_redraw()


## How far the attachment point will have moved `t` seconds from now (bots).
func mount_moved_by(m: ItemMount, t: float) -> Vector2:
	return global_transform.basis_xform(Vector2(sin((_t + t) / period * TAU) * travel, 0) - m.position)


func reset_round() -> void:
	_t = 0.0
	_place()


func _draw() -> void:
	# Rail, with stops at both ends (same look as the saw's).
	var a := Vector2(-travel, 0)
	var b := Vector2(travel, 0)
	draw_line(a, b, Color.BLACK, 8.0)
	draw_line(a, b, Color("6cba7c"), 4.0)
	for p in [a, b]:
		draw_circle(p, 7.0, Color.BLACK)
		draw_circle(p, 4.0, Color("b0e2bc"))
	# Carriage under the attachment point.
	var c := _mount.position if _mount else Vector2.ZERO
	draw_rect(Rect2(c + Vector2(-16, -12), Vector2(32, 24)), Color.BLACK)
	draw_rect(Rect2(c + Vector2(-13, -9), Vector2(26, 18)), Color("b0e2bc"))
	draw_rect(Rect2(c + Vector2(-13, 4), Vector2(26, 5)), Color("6cba7c"))


# Online: clients follow the host's clock (corrected when they drift apart).
func net_state() -> Array:
	return [snappedf(_t, 0.01)]


func net_apply(s: Array) -> void:
	# Online client: a little ahead of the host's clock (what we see is what
	# the host will check our robot against).
	var host_t: float = s[0] + NetCheck.lead(self)
	if absf(_t - host_t) > 0.08:
		_t = host_t
