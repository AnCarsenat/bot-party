@tool
class_name Platform
extends Node2D
## All-in-one platform: optional logic inputs, one-way, moving.
##
## - No inputs: always active.
## - `controls` decides what the logic does:
##     SOLIDITY          - solid only while active (ghost otherwise)
##     MOVE_TO_END       - goes to `move_offset` while active, comes back otherwise
##     LOOP_WHILE_ACTIVE - ping-pongs between start and `move_offset` while active
## - `one_way`: players can jump through from below and land on top.
##   Rotate the platform to change the direction. Arrows showing the direction
##   are drawn in the editor and in debug view (F3 in game).

const TEX_SOLID := preload("res://toggle_platform_enabled.webp")
const TEX_GHOST := preload("res://toggle_platform_disabled.webp")
const TEX_ARROW := preload("res://one_way.webp")

enum InputMode {
	HOLD,   ## Active while at least one input is on.
	TOGGLE, ## Each new input pulse flips active on/off.
}
enum Controls { SOLIDITY, MOVE_TO_END, LOOP_WHILE_ACTIVE }

@export_group("Shape")
@export var size: Vector2 = Vector2(150, 30):
	set(value):
		size = value.max(Vector2(4, 4))
		_refresh_visuals()
@export var one_way: bool = false:
	set(value):
		one_way = value
		_refresh_visuals()
## Size of one texture pixel on screen.
@export_range(1.0, 8.0, 0.5) var pixel_scale: float = 3.0:
	set(value):
		pixel_scale = value
		_refresh_visuals()
@export var solid_texture: Texture2D = TEX_SOLID:
	set(value):
		solid_texture = value
		_refresh_visuals()
@export var ghost_texture: Texture2D = TEX_GHOST:
	set(value):
		ghost_texture = value
		_refresh_visuals()

@export_group("Logic")
@export var inputs: Array[Node] = []:
	set(value):
		inputs = value
		queue_redraw()
@export var input_mode: InputMode = InputMode.HOLD
@export var controls: Controls = Controls.SOLIDITY
## Swap active/inactive (e.g. solid by default, vanishes when a button is pressed).
@export var inverted: bool = false

@export_group("Movement")
## Where the platform travels to, relative to its start. (0, 0) = doesn't move.
@export var move_offset: Vector2 = Vector2.ZERO:
	set(value):
		move_offset = value
		queue_redraw()
## Seconds for one trip.
@export_range(0.05, 30.0, 0.05, "or_greater", "suffix:s") var move_time: float = 2.0
## Seconds to wait at each end when looping.
@export_range(0.0, 30.0, 0.05, "or_greater", "suffix:s") var pause_time: float = 0.5

var active: bool = true
var solid: bool = true

var _toggled_on := false
var _progress := 0.0     # 0 = start, 1 = at move_offset
var _direction := 1.0    # looping direction
var _pause_left := 0.0

@onready var _body: AnimatableBody2D = $Body
@onready var _shape: CollisionShape2D = $Body/CollisionShape2D
@onready var _sprite: Sprite2D = $Body/Sprite2D


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_refresh_visuals()
	if Engine.is_editor_hint():
		return
	LogicNode.on_debug_view_changed(self, queue_redraw)
	if not inputs.is_empty():
		Wires.attach(self)
	LogicNode.connect_inputs(inputs, _on_input_toggled, _on_input_pressed)
	_update_active()


func _on_input_toggled(_state: bool) -> void:
	_update_active()


func _on_input_pressed() -> void:
	if input_mode == InputMode.TOGGLE:
		_toggled_on = not _toggled_on
		_update_active()


func _update_active() -> void:
	var raw: bool
	if inputs.is_empty():
		raw = true
	elif input_mode == InputMode.HOLD:
		raw = LogicNode.any_on(inputs)
	else:
		raw = _toggled_on
	active = raw != inverted
	_set_solid(active if controls == Controls.SOLIDITY else true)
	queue_redraw()


func _set_solid(value: bool) -> void:
	var changed := value != solid
	solid = value
	# Deferred: collision can't change in the middle of a physics step.
	_shape.set_deferred("disabled", not solid)
	_refresh_visuals()
	if changed and not Engine.is_editor_hint() and is_inside_tree():
		# Fade + small pop so the change is easy to notice.
		_sprite.modulate.a = 0.45 if solid else 1.0
		var tw := create_tween().set_parallel()
		tw.tween_property(_sprite, "modulate:a", 1.0 if solid else 0.45, 0.18)
		if solid:
			var rest := Vector2.ONE * pixel_scale
			_sprite.scale = rest * Vector2(1.04, 1.3)
			tw.tween_property(_sprite, "scale", rest, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	if move_offset == Vector2.ZERO:
		return

	var step := delta / maxf(move_time, 0.01)
	var moving := false
	match controls:
		Controls.MOVE_TO_END:
			var target := 1.0 if active else 0.0
			_progress = move_toward(_progress, target, step)
			moving = true
		Controls.LOOP_WHILE_ACTIVE, Controls.SOLIDITY:
			# SOLIDITY with an offset loops forever (logic only toggles solidity).
			if controls == Controls.SOLIDITY or active:
				if _pause_left > 0.0:
					_pause_left -= delta
				else:
					_progress += step * _direction
					if _progress >= 1.0 or _progress <= 0.0:
						_progress = clampf(_progress, 0.0, 1.0)
						_direction = -_direction
						_pause_left = pause_time
				moving = true
	if moving:
		# Smooth start/stop; AnimatableBody2D carries the players standing on it.
		_body.position = move_offset * smoothstep(0.0, 1.0, _progress)
		if one_way and LogicNode.debug_visible(self):
			queue_redraw()  # arrows follow the body


func _refresh_visuals() -> void:
	if not is_node_ready():
		return
	(_shape.shape as RectangleShape2D).size = size
	_shape.one_way_collision = one_way
	_shape.one_way_collision_margin = 12.0
	_sprite.texture = solid_texture if solid else ghost_texture
	_sprite.modulate.a = 1.0 if solid else 0.45
	_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_sprite.region_enabled = true
	_sprite.scale = Vector2.ONE * pixel_scale
	_sprite.region_rect = Rect2(Vector2.ZERO, size / pixel_scale)
	queue_redraw()


func _draw() -> void:
	if not LogicNode.debug_visible(self):
		return
	if Engine.is_editor_hint():
		LogicNode.draw_wires(self, inputs)

	var body_pos := _body.position if is_node_ready() else Vector2.ZERO

	# Movement preview (editor only): ghost outline at the end position.
	if Engine.is_editor_hint() and move_offset != Vector2.ZERO:
		var c := Color(1, 1, 1, 0.5)
		draw_dashed_line(Vector2.ZERO, move_offset, c, 2.0, 8.0)
		draw_rect(Rect2(move_offset - size / 2.0, size), c, false, 2.0)

	# One-way arrows, drawn on top of the platform and pointing "up" (local).
	if one_way:
		var arrow := clampf(size.y * 1.6, 24.0, 64.0)
		var count := maxi(1, int(size.x / (arrow * 1.5)))
		var spacing := size.x / count
		var alpha := 0.9 if solid else 0.35
		for i in count:
			var x := -size.x / 2.0 + spacing * (i + 0.5)
			var r := Rect2(body_pos + Vector2(x - arrow / 2.0, -arrow / 2.0), Vector2(arrow, arrow))
			draw_texture_rect(TEX_ARROW, r, false, Color(1, 1, 1, alpha))
