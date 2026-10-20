class_name Wires
extends Node2D
## Draws hanging cables from every source in `owner_node.inputs` to `owner_node`.
## Created automatically by machines, platforms and doors; lives behind everything.

const OUTER := Color(0.1, 0.1, 0.13, 0.9)
const CORE_ON := Color(0.45, 1.0, 0.55)
const CORE_OFF := Color(0.55, 0.25, 0.25)
const SEGMENTS := 20

var owner_node: Node2D
var _time := 0.0


static func attach(node: Node2D) -> Wires:
	var w := Wires.new()
	w.owner_node = node
	w.top_level = true
	w.z_as_relative = false
	w.z_index = -160
	node.add_child(w, false, Node.INTERNAL_MODE_FRONT)
	return w


func _process(delta: float) -> void:
	_time += delta
	global_position = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(owner_node) or not owner_node.is_visible_in_tree():
		return
	var to := owner_node.global_position
	for src in owner_node.get("inputs"):
		if not (is_instance_valid(src) and src is Node2D and src.is_inside_tree()):
			continue
		var on := LogicNode.is_on(src)
		var points := _cable(src.global_position, to)
		draw_polyline(points, OUTER, 7.0, true)
		draw_polyline(points, CORE_ON if on else CORE_OFF, 3.0, true)
		# Plugs at both ends.
		for p in [points[0], points[-1]]:
			draw_circle(p, 6.0, OUTER)
			draw_circle(p, 3.0, CORE_ON if on else CORE_OFF)
		# Signal pulses travelling along live cables.
		if on:
			for k in 3:
				var t := fmod(_time * 0.8 + k / 3.0, 1.0)
				var idx := t * (points.size() - 1)
				var a := points[int(idx)]
				var b := points[mini(int(idx) + 1, points.size() - 1)]
				draw_circle(a.lerp(b, idx - int(idx)), 4.0, Color(0.85, 1.0, 0.85))


## Sagging curve between two points (quadratic Bézier with a dropped middle).
func _cable(a: Vector2, b: Vector2) -> PackedVector2Array:
	var sag := 30.0 + a.distance_to(b) * 0.12
	var ctrl := (a + b) / 2.0 + Vector2(0, sag)
	var pts := PackedVector2Array()
	for i in SEGMENTS + 1:
		var t := float(i) / SEGMENTS
		pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
	return pts
