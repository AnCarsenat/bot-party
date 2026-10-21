@tool
class_name SyncedPolygon
extends Polygon2D
## Keeps this visual Polygon2D and a CollisionPolygon2D identical.
## Edit EITHER one in the editor (points or position) and the other follows.
## Put it next to a CollisionPolygon2D (same parent); it finds it automatically.

## Leave empty to use the first CollisionPolygon2D sibling.
@export var collision: CollisionPolygon2D

## Level look: black outline like the sprites and a mint top edge.
@export var styled: bool = true:
	set(value):
		styled = value
		_apply_style()
@export var cap_color: Color = Color("b0e2bc")
@export var cap_height: float = 9.0

var _last_points := PackedVector2Array()
var _last_xform := Transform2D()


func _ready() -> void:
	_apply_style()
	if collision == null:
		collision = _find_collision()
	if collision == null:
		push_warning("%s: no CollisionPolygon2D sibling found." % get_path())
		return
	# On load, the collision shape is the reference.
	_copy_from_collision()
	# Only needed while editing; the saved scene already holds synced values.
	set_process(Engine.is_editor_hint())


func _process(_delta: float) -> void:
	if not is_instance_valid(collision):
		collision = _find_collision()
		if collision == null:
			return

	if collision.polygon != _last_points or collision.transform != _last_xform:
		_copy_from_collision()
	elif polygon != _last_points or transform != _last_xform:
		_copy_to_collision()


func _copy_from_collision() -> void:
	polygon = collision.polygon
	transform = collision.transform
	_remember()


func _copy_to_collision() -> void:
	collision.polygon = polygon
	collision.transform = transform
	_remember()


func _remember() -> void:
	_last_points = polygon
	_last_xform = transform


func _find_collision() -> CollisionPolygon2D:
	var parent := get_parent()
	if parent == null:
		return null
	for child in parent.get_children():
		if child is CollisionPolygon2D:
			return child
	return null


func _apply_style() -> void:
	if not is_inside_tree():
		return
	queue_redraw()


func _draw() -> void:
	if not styled or polygon.size() < 3:
		return
	var pts := polygon
	var n := pts.size()
	# Mossy cap on every top-facing edge.
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var d := b - a
		if absf(d.y) > absf(d.x) * 0.35 or absf(d.x) < 4.0:
			continue
		var mid := (a + b) / 2.0
		if Geometry2D.is_point_in_polygon(mid + Vector2(0, 4), pts) and not Geometry2D.is_point_in_polygon(mid - Vector2(0, 4), pts):
			var down := Vector2(0, cap_height)
			draw_colored_polygon(PackedVector2Array([a, b, b + down, a + down]), cap_color)
			draw_line(a + down, b + down, Color.BLACK, 3.0)
	# Black outline.
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, Color.BLACK, 4.0)
