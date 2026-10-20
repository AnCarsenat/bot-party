@tool
class_name TogglePlatform
extends Node2D

const TEX_ENABLED := preload("res://toggle_platform_enabled.webp")
const TEX_DISABLED := preload("res://toggle_platform_disabled.webp")
## Size of one texture pixel on screen.
const PIXEL_SCALE := 3.0

enum Mode {
	HOLD,   ## Solid while at least one of the buttons is pressed.
	TOGGLE, ## Each new press on any button flips the platform on/off.
}

## Buttons that control this platform. In HOLD mode, any one of them is enough.
@export var buttons: Array[PressureButton] = []
@export var mode: Mode = Mode.HOLD
## Invert the logic: solid by default, disappears when activated.
@export var inverted: bool = false
## Platform size in pixels.
@export var size: Vector2 = Vector2(150, 30):
	set(value):
		size = value
		if is_node_ready():
			_update_size()

var _toggled_on: bool = false

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _shape: CollisionShape2D = $StaticBody2D/CollisionShape2D


func _ready() -> void:
	_update_size()

	if Engine.is_editor_hint():
		_set_solid(not inverted)
		return

	if buttons.is_empty():
		push_warning("%s has no buttons assigned." % name)

	for b in buttons:
		if b == null:
			continue
		b.toggled.connect(_on_button_toggled)
		b.pressed.connect(_on_button_pressed)

	_refresh()


func _on_button_toggled(_is_pressed: bool) -> void:
	if mode == Mode.HOLD:
		_refresh()


func _on_button_pressed() -> void:
	if mode == Mode.TOGGLE:
		_toggled_on = not _toggled_on
		_refresh()


func _refresh() -> void:
	var active := _toggled_on
	if mode == Mode.HOLD:
		active = buttons.any(func(b): return b != null and b.is_pressed)
	_set_solid(active != inverted)


func _set_solid(solid: bool) -> void:
	_sprite.texture = TEX_ENABLED if solid else TEX_DISABLED
	_sprite.modulate.a = 1.0 if solid else 0.5
	# Deferred: changing collision during a physics callback is not allowed.
	_shape.set_deferred("disabled", not solid)


func _update_size() -> void:
	(_shape.shape as RectangleShape2D).size = size
	_sprite.scale = Vector2.ONE * PIXEL_SCALE
	_sprite.region_rect = Rect2(Vector2.ZERO, size / PIXEL_SCALE)
