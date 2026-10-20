@tool
class_name SyncedPolygon
extends Polygon2D
## Keeps this visual Polygon2D and a CollisionPolygon2D identical.
## Edit EITHER one in the editor (points or position) and the other follows.
## Put it next to a CollisionPolygon2D (same parent); it finds it automatically.

## Leave empty to use the first CollisionPolygon2D sibling.
@export var collision: CollisionPolygon2D

var _last_points := PackedVector2Array()
var _last_xform := Transform2D()


func _ready() -> void:
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
