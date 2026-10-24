extends Node2D
## Special item: a balloon. The robot that touches it floats up slowly for 2
## seconds, and the balloon pops (it's back next round).

const TEX := preload("res://party/art/balloon.webp")

var _popped := false
var _t := 0.0
var _area: StatusArea


func _ready() -> void:
	add_to_group("net_sync")
	_area = StatusArea.new()
	_area.name = "Balloon"
	_area.status = "floating"
	_area.seconds = 2.0
	_area.set_box(Vector2(44, 52), Vector2(0, -8))
	_area.touched.connect(func(_p): _pop())
	add_child(_area)


func _pop() -> void:
	_popped = true
	_area.set_deferred("monitoring", false)
	if is_inside_tree():
		get_tree().current_scene.add_child(Effects.ring(global_position, 40.0, Color(0.9, 0.31, 0.24)))


func reset_round() -> void:
	_popped = false
	_area.set_deferred("monitoring", true)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if not _popped:
		draw_texture_rect(TEX, Rect2(Vector2(-32, -32 + sin(_t * 2.5) * 4.0), Vector2(64, 64)), false)


func net_state() -> Array:
	return [_popped]


func net_apply(s: Array) -> void:
	_popped = s[0]
