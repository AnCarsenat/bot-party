class_name DistantPlayers
extends CanvasLayer
## Settings > Distant players: a robot that's off the screen gets a bubble at the
## edge, pointing towards it, with a small live view around it.
## The camera adds one of these (core/camera_script.gd).

const SIZE := Vector2(208, 148)
const INSET := 24.0

var _bubbles := {}  # player instance id -> _Bubble


func _ready() -> void:
	layer = 30


func _process(_d: float) -> void:
	var on: bool = GameState.settings.get("distant_players", true)
	var view := get_viewport().get_visible_rect()
	var xf := get_viewport().get_canvas_transform()
	var seen := {}
	if on:
		for p in get_tree().get_nodes_in_group("camera_follow"):
			if not p is CharacterBody2D or p.get_meta("eliminated", false) or not p.visible:
				continue
			var screen: Vector2 = xf * p.global_position
			if view.grow(-20).has_point(screen):
				continue
			var id := p.get_instance_id()
			seen[id] = true
			var b: _Bubble = _bubbles.get(id)
			if b == null:
				b = _Bubble.new()
				b.setup(get_viewport().world_2d, p.get_meta("color", Color.WHITE))
				add_child(b)
				_bubbles[id] = b
			b.follow(p, screen, view)
	for id in _bubbles.keys():
		if not seen.has(id):
			_bubbles[id].queue_free()
			_bubbles.erase(id)


## One bubble: a small view of the world around a robot, and an arrow to it.
class _Bubble extends Control:
	var _view: SubViewport
	var _cam: Camera2D
	var _color := Color.WHITE
	var _arrow := Vector2.RIGHT

	func setup(world: World2D, color: Color) -> void:
		_color = color
		size = SIZE
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := SubViewportContainer.new()
		box.stretch = true
		box.position = Vector2(6, 6)
		box.size = SIZE - Vector2(12, 12)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(box)
		_view = SubViewport.new()
		_view.world_2d = world  # the same world: it draws the real level
		_view.size = Vector2i(box.size)
		_view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		box.add_child(_view)
		_cam = Camera2D.new()
		_cam.zoom = Vector2(0.35, 0.35)
		_view.add_child(_cam)
		_cam.make_current()

	func follow(p: Node2D, screen: Vector2, view: Rect2) -> void:
		_cam.global_position = p.global_position
		# On the screen's edge, on the line from the middle to the robot.
		var mid := view.get_center()
		var dir := (screen - mid).normalized()
		var half := view.size / 2.0 - SIZE / 2.0 - Vector2(INSET, INSET)
		var k := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
		position = mid + dir * k - SIZE / 2.0
		_arrow = dir
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, SIZE)
		draw_rect(r.grow(3), Color.BLACK)
		draw_rect(r, _color)
		# Arrow on the side facing the robot.
		var c := SIZE / 2.0
		var tip := c + _arrow * (SIZE.length() / 2.0 + 10.0)
		var edge := c + _arrow * minf(SIZE.x / 2.0 / maxf(absf(_arrow.x), 0.001), SIZE.y / 2.0 / maxf(absf(_arrow.y), 0.001))
		var side := _arrow.orthogonal() * 14.0
		draw_colored_polygon(PackedVector2Array([edge + side, tip, edge - side]), Color.BLACK)
		draw_colored_polygon(PackedVector2Array([edge + side * 0.6, tip - _arrow * 5.0, edge - side * 0.6]), _color)
