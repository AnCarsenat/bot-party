extends Node2D
## Special item: steel jaws on the ground. A robot that steps in is held in place
## for a second; then the trap needs 3 seconds to open again.

const TEX := preload("res://party/art/bear_trap.webp")
const HOLD := 1.0
const REARM := 3.0

var _closed := 0.0  # seconds until it's open again
var _jaws: StatusArea


func _ready() -> void:
	add_to_group("net_sync")
	_jaws = StatusArea.new()
	_jaws.name = "Jaws"
	_jaws.status = "stuck"
	_jaws.seconds = HOLD
	_jaws.avoid = true
	_jaws.set_box(Vector2(48, 22), Vector2(0, 14))
	_jaws.touched.connect(_snap)
	add_child(_jaws)


func _snap(_p: Node) -> void:
	_closed = REARM
	_jaws.set_deferred("monitoring", false)


func reset_round() -> void:
	_closed = 0.0
	_jaws.set_deferred("monitoring", true)


func _physics_process(delta: float) -> void:
	if _closed > 0.0:
		_closed -= delta
		if _closed <= 0.0 and not NetCheck.client(self):
			_jaws.set_deferred("monitoring", true)
	queue_redraw()


func _draw() -> void:
	if _closed <= 0.0:
		draw_texture_rect(TEX, Rect2(-32, -32, 64, 64), false)
		return
	# Shut: the jaws meet in the middle.
	draw_rect(Rect2(-28, 18, 56, 10), Color.BLACK)
	draw_rect(Rect2(-26, 20, 52, 6), Color("6d7a71"))
	draw_rect(Rect2(-22, -2, 44, 22), Color.BLACK)
	draw_rect(Rect2(-20, 0, 40, 18), Color("d2d5d3"))
	for x in range(-18, 18, 6):
		draw_colored_polygon(PackedVector2Array([Vector2(x, 9), Vector2(x + 3, 3), Vector2(x + 6, 9)]), Color.WHITE)
	draw_line(Vector2(-20, 9), Vector2(20, 9), Color.BLACK, 2.0)


func net_state() -> Array:
	return [snappedf(_closed, 0.05)]


func net_apply(s: Array) -> void:
	_closed = s[0]
