@tool
class_name LogicNode
extends RigidBody2D
## Base class for every logic component (gates, delayer, clock...).
##
## Logic components are background machines: they fall and bump into each
## other, never block players, and players shove them aside when they are light
## enough (`mass` <= the player's `machine_push_max_mass`). Cables connect them.
## Tick `freeze` (RigidBody2D > Freeze) to pin one in place.
##
## Everything that can be wired (PressureButton, LogicNode subclasses) follows
## the same small protocol, so any output can be plugged into any input:
##   var is_pressed: bool         -> current output (on / off)
##   signal toggled(is_pressed)   -> output changed
##   signal pressed / released    -> output went on / off
##
## Drag sources into `inputs` in the Inspector.
## Wires and details are drawn in the editor and in debug view (F3 in game).

signal toggled(is_pressed: bool)
signal pressed
signal released

## Group of all machines.
const MACHINE_GROUP := &"machines"
## Group of foreground objects that press buttons (crates).
const OBJECT_GROUP := &"objects"
const BOX_SIZE := Vector2(88, 36)
## Screen pixels per texture pixel (player sprite uses ~2.5).
const TEX_SCALE := 2.5
const COLOR_ON := Color(0.35, 0.95, 0.45)
const COLOR_OFF := Color(0.85, 0.3, 0.3)
const COLOR_EDITOR := Color(0.55, 0.8, 1.0)
const COLOR_BOX := Color(0.12, 0.12, 0.16, 0.9)

## Sources feeding this component (buttons or other logic components).
@export var inputs: Array[Node] = []:
	set(value):
		inputs = value
		queue_redraw()
## Sprite for this component. Empty = the default one for its type.
@export var texture: Texture2D:
	set(value):
		texture = value
		_update_shape()
		queue_redraw()
## Show the sprite in game. Wires and details only show in debug view anyway.
@export var show_in_game: bool = true

var is_pressed: bool = false

var _pop := 1.0
var _auto_shape: CollisionShape2D


func _init() -> void:
	# Sensible defaults for a pushable block (the Inspector can still change them).
	lock_rotation = true
	mass = 2.0
	collision_layer = Layers.MACHINES
	collision_mask = Layers.WORLD | Layers.MACHINES
	z_index = -150
	var mat := PhysicsMaterial.new()
	mat.friction = 0.8
	physics_material_override = mat


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_update_shape()
	if Engine.is_editor_hint():
		return
	add_to_group(MACHINE_GROUP)
	if not show_in_game:
		hide()
	Wires.attach(self)
	on_debug_view_changed(self, queue_redraw)
	connect_inputs(inputs, _on_any_input_toggled)
	_start()
	_on_inputs_changed()


func _process(_delta: float) -> void:
	# Wires must follow objects that move (being pushed, falling...).
	if debug_visible(self):
		queue_redraw()


## Builds a collision box from the sprite's visible pixels, unless you added
## your own CollisionShape2D / CollisionPolygon2D as a child.
func _update_shape() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		if child != _auto_shape and (child is CollisionShape2D or child is CollisionPolygon2D):
			return
	var rect := _visible_rect()
	if _auto_shape == null:
		_auto_shape = CollisionShape2D.new()
		_auto_shape.shape = RectangleShape2D.new()
		add_child(_auto_shape, false, Node.INTERNAL_MODE_BACK)
	(_auto_shape.shape as RectangleShape2D).size = rect.size
	_auto_shape.position = rect.get_center()


## Visible area of the sprite in local pixels (or the box when there is none).
func _visible_rect() -> Rect2:
	var tex := _current_texture()
	if tex == null:
		return Rect2(-BOX_SIZE / 2.0, BOX_SIZE)
	var used := Rect2(Vector2.ZERO, tex.get_size())
	var img := tex.get_image()
	if img != null:
		if img.is_compressed():
			img.decompress()
		var r := img.get_used_rect()
		if r.size != Vector2i.ZERO:
			used = Rect2(r)
	return Rect2((used.position - tex.get_size() / 2.0) * TEX_SCALE, used.size * TEX_SCALE)


func _current_texture() -> Texture2D:
	return texture if texture != null else _default_texture()


# --- To override in subclasses ---------------------------------------------

## Called once when the game starts, before the first evaluation.
func _start() -> void:
	pass


## Called whenever any input turns on or off (and once at start).
func _on_inputs_changed() -> void:
	set_output(any_on(inputs))


## Text shown in the box: [title, detail].
func _label() -> PackedStringArray:
	return PackedStringArray(["LOGIC", ""])


## Text always printed under the sprite (e.g. the gate type). Empty = none.
func _always_label() -> String:
	return ""


## Texture used when `texture` is empty.
func _default_texture() -> Texture2D:
	return null


## 0..1 progress bar under the box (timers), or -1 for none.
func _progress() -> float:
	return -1.0


# --- Output ------------------------------------------------------------------

func set_output(value: bool) -> void:
	if value == is_pressed:
		return
	is_pressed = value
	if is_pressed and is_inside_tree():
		# Little "pop" when switching on.
		var tw := create_tween()
		tw.tween_method(func(v: float): _pop = v; queue_redraw(), 1.2, 1.0, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	toggled.emit(is_pressed)
	if is_pressed:
		pressed.emit()
	else:
		released.emit()
	queue_redraw()


func _on_any_input_toggled(_state: bool) -> void:
	_on_inputs_changed()
	queue_redraw()


# --- Shared helpers (also used by Platform and Door) -------------------------

## True in the editor, or in game while debug view is on (autoload "DebugView").
static func debug_visible(node: Node) -> bool:
	if Engine.is_editor_hint():
		return true
	if not node.is_inside_tree():
		return false
	var dv := node.get_tree().root.get_node_or_null("DebugView")
	return dv != null and dv.enabled


## Calls `callback` whenever debug view is switched on/off (no-op in the editor).
static func on_debug_view_changed(node: Node, callback: Callable) -> void:
	if Engine.is_editor_hint() or not node.is_inside_tree():
		return
	var dv := node.get_tree().root.get_node_or_null("DebugView")
	if dv != null:
		dv.changed.connect(func(_on: bool): callback.call())


## `node` is untyped on purpose: it may be a node that was freed (e.g. removed by
## a PlayerCountFilter), which simply counts as "off".
static func is_on(node) -> bool:
	return is_instance_valid(node) and node.get("is_pressed") == true


static func any_on(nodes: Array) -> bool:
	for n in nodes:
		if is_on(n):
			return true
	return false


static func count_on(nodes: Array) -> int:
	var c := 0
	for n in nodes:
		if is_on(n):
			c += 1
	return c


static func count_valid(nodes: Array) -> int:
	var c := 0
	for n in nodes:
		if is_instance_valid(n):
			c += 1
	return c


static func connect_inputs(nodes: Array, on_toggled: Callable, on_pressed := Callable()) -> void:
	for n in nodes:
		if not is_instance_valid(n):
			continue
		if n.has_signal("toggled"):
			n.toggled.connect(on_toggled)
		else:
			push_warning("%s is not a logic source (no 'toggled' signal)." % n.name)
		if on_pressed.is_valid() and n.has_signal("pressed"):
			n.pressed.connect(on_pressed)


## Draws a wire from every input to `target` (local position of `canvas`).
static func draw_wires(canvas: CanvasItem, nodes: Array, target := Vector2.ZERO) -> void:
	var editor := Engine.is_editor_hint()
	for n in nodes:
		if not (is_instance_valid(n) and n is Node2D and n.is_inside_tree()):
			continue
		var from: Vector2 = canvas.to_local(n.global_position)
		var color := COLOR_EDITOR if editor else (COLOR_ON if is_on(n) else COLOR_OFF)
		color.a = 0.8
		canvas.draw_line(from, target, color, 2.0, true)
		# Arrow head at the middle, pointing toward the target.
		var dir := (target - from).normalized()
		if dir != Vector2.ZERO:
			var mid := from.lerp(target, 0.5)
			var side := dir.orthogonal() * 6.0
			canvas.draw_colored_polygon(
				PackedVector2Array([mid + dir * 8.0, mid - dir * 4.0 + side, mid - dir * 4.0 - side]),
				color)


# --- Drawing -------------------------------------------------------------------

func _draw() -> void:
	var debug := debug_visible(self)
	var editor := Engine.is_editor_hint()
	var state_color := COLOR_EDITOR if editor else (COLOR_ON if is_pressed else COLOR_OFF)
	var tex := _current_texture()
	var font := ThemeDB.fallback_font
	var text := _label()

	if editor:
		draw_wires(self, inputs)  # in game the Wires node draws cables

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * _pop)
	var bottom: float
	if tex != null:
		# Sprite: bright when on, dimmed when off.
		var tex_size := tex.get_size() * TEX_SCALE
		var tint := Color.WHITE if (editor or is_pressed) else Color(0.62, 0.62, 0.62)
		draw_texture_rect(tex, Rect2(-tex_size / 2.0, tex_size), false, tint)
		bottom = _visible_rect().end.y
	else:
		var rect := Rect2(-BOX_SIZE / 2.0, BOX_SIZE)
		draw_rect(rect, COLOR_BOX)
		draw_rect(rect, state_color, false, 2.0)
		bottom = BOX_SIZE.y / 2.0
	draw_set_transform(Vector2.ZERO)

	var always := _always_label()
	if always != "":
		# Printed on the sprite's face so it reads like a label.
		draw_string_outline(font, Vector2(-60, 6), always, HORIZONTAL_ALIGNMENT_CENTER, 120, 16, 4, Color.BLACK)
		draw_string(font, Vector2(-60, 6), always, HORIZONTAL_ALIGNMENT_CENTER, 120, 16, Color.WHITE)

	if debug:
		var caption := text[0] + ("  " + text[1] if text.size() > 1 and text[1] != "" else "")
		draw_string(font, Vector2(-80, bottom + 16), caption,
			HORIZONTAL_ALIGNMENT_CENTER, 160, 12, state_color)

	# Timer progress bar, sitting on top of the object.
	var p := _progress()
	if p >= 0.0 and not editor:
		var top := _visible_rect().position.y
		var w := 56.0
		draw_rect(Rect2(-w / 2.0, top - 9, w, 5), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(-w / 2.0, top - 9, w * clampf(p, 0, 1), 5), state_color)
