extends Node2D
## Special item: a weak magnet. During the race it pulls robots within reach
## toward it, gently: anyone can still walk away from it. It doesn't hurt.

const TEX := preload("res://party/art/magnet.webp")

@export var reach := 280.0
## Pull (pixels per second added) right next to it; it fades with distance.
@export var strength := 230.0

var _t := 0.0


func _physics_process(delta: float) -> void:
	_t += delta
	if NetCheck.client(self):
		return
	var ctl = get_tree().get_first_node_in_group("party_controller")
	if ctl == null or ctl.phase != ctl.Phase.RUN:
		return
	for p in get_tree().get_nodes_in_group("players"):
		if p.get_meta("eliminated", false) or p.get_meta("finished", false) or not p.has_method("pull"):
			continue
		var to: Vector2 = global_position - p.global_position
		var d := to.length()
		if d < reach and d > 1.0:
			p.pull(to / d * strength * (1.0 - d / reach * 0.7))


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	# Field lines drifting inwards.
	for k in 3:
		var r := reach * (1.0 - fmod(_t * 0.35 + k / 3.0, 1.0))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(0.9, 0.31, 0.24, 0.35 * (1.0 - r / reach) + 0.15), 4.0)
	# Its reach, so you can see what it'll pull.
	draw_arc(Vector2.ZERO, reach, 0.0, TAU, 64, Color(0.9, 0.31, 0.24, 0.3), 2.0)
	draw_texture_rect(TEX, Rect2(-32, -32, 64, 64), false)
