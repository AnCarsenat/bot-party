@tool
class_name PressureButton
extends Area2D
## Pressed while a player or a physical object (crate, logic block) is on it.

## Emitted when the button goes from released to pressed.
signal pressed
## Emitted when the button goes from pressed to released.
signal released
## Emitted on every state change.
signal toggled(is_pressed: bool)

## Colour of the button's cap.
@export var color: Color = Color("e64f3e"):
	set(value):
		color = value
		if is_node_ready():
			_cap.modulate = color
## Bodies in any of these groups press the button (machines never do: they're background).
@export var activator_groups: Array[StringName] = [&"players", &"objects"]
## If true, the button stays pressed forever once activated.
@export var stays_pressed: bool = false

## How far the cap sinks when pressed, in texture pixels.
const PRESS_DEPTH := 2.0

var is_pressed: bool = false

var _cap_rest_y := 0.0
var _tween: Tween

@onready var _cap: Sprite2D = $Cap


func _init() -> void:
	collision_layer = 0
	collision_mask = Layers.PLAYERS | Layers.CRATES


func _ready() -> void:
	_cap.modulate = color
	_cap_rest_y = _cap.position.y
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	monitoring = true
	add_to_group("net_sync")


func net_state() -> Array:
	return [is_pressed]


func net_apply(s: Array) -> void:
	if s[0] != is_pressed:
		_set_pressed(s[0])


func _physics_process(_delta: float) -> void:
	if stays_pressed and is_pressed:
		return
	if NetCheck.client(self):
		return  # online: pressed when the host says so

	var occupied := false
	for body in get_overlapping_bodies():
		if _is_valid_activator(body):
			occupied = true
			break

	if occupied != is_pressed:
		_set_pressed(occupied)


func _is_valid_activator(body: Node) -> bool:
	if not body.is_visible_in_tree() or body.get_meta("eliminated", false):
		return false
	for g in activator_groups:
		if body.is_in_group(g):
			return true
	return false


func _set_pressed(value: bool) -> void:
	is_pressed = value
	_animate_cap()
	toggled.emit(is_pressed)
	if is_pressed:
		pressed.emit()
	else:
		released.emit()


func _animate_cap() -> void:
	if _tween:
		_tween.kill()
	var depth := PRESS_DEPTH * _cap.scale.y
	var target := _cap_rest_y + (depth if is_pressed else 0.0)
	_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_cap, "position:y", target, 0.08)
	# Slightly darker while held down.
	_tween.parallel().tween_property(_cap, "modulate", color.darkened(0.25) if is_pressed else color, 0.08)
