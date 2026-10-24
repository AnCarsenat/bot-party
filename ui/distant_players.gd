class_name DistantPlayers
extends CanvasLayer
## Settings > Distant players: a robot that's off the screen gets a bubble at the
## edge, pointing towards it, with a small live view around it.
## The camera adds one of these (core/camera_script.gd).
## Settings > Bubble view / Bubble size tune them; the menu shows a live preview
## (DistantPlayers.Preview).

const SIZE := Vector2(208, 148)  # bubble size at the default "Bubble size"
const INSET := 24.0

var _bubbles := {}  # player instance id -> Bubble


## Bubble camera zoom from Settings > Bubble view (0..1 -> 1.0 close .. 0.2 far).
static func zoom() -> float:
	var v: float = GameState.settings.get("bubble_view", 0.8)
	return lerpf(1.0, 0.2, clampf(v, 0.0, 1.0))


## Bubble size from Settings > Bubble size (0..1 -> 0.6x .. 1.6x, default 0.4 = 1x).
static func bubble_size() -> Vector2:
	var v: float = GameState.settings.get("bubble_size", 0.4)
	return (SIZE * lerpf(0.6, 1.6, clampf(v, 0.0, 1.0))).round()


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
			var b: Bubble = _bubbles.get(id)
			if b == null:
				b = Bubble.new()
				b.setup(get_viewport().world_2d, p.get_meta("color", Color.WHITE))
				add_child(b)
				_bubbles[id] = b
			b.follow(p, screen, view)
	for id in _bubbles.keys():
		if not seen.has(id):
			_bubbles[id].queue_free()
			_bubbles.erase(id)


## One bubble: a small view of the world around a robot, and an arrow to it.
class Bubble extends Control:
	var _box: SubViewportContainer
	var _view: SubViewport
	var _cam: Camera2D
	var _color := Color.WHITE
	var _arrow := Vector2.RIGHT

	func setup(world: World2D, color: Color) -> void:
		_color = color
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_box = SubViewportContainer.new()
		_box.stretch = true
		_box.position = Vector2(6, 6)
		_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_box)
		_view = SubViewport.new()
		_view.world_2d = world  # the same world: it draws the real level
		_view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		_box.add_child(_view)
		_cam = Camera2D.new()
		_view.add_child(_cam)
		refresh()

	## Picks up the current Bubble view / Bubble size settings.
	func refresh() -> void:
		var s := DistantPlayers.bubble_size()
		if size != s:
			size = s
			_box.size = s - Vector2(12, 12)
			queue_redraw()
		_cam.zoom = Vector2.ONE * DistantPlayers.zoom()

	## Looks at `world_pos`, with the arrow pointing along `dir`.
	func aim(world_pos: Vector2, dir: Vector2) -> void:
		refresh()
		_cam.global_position = world_pos
		if dir != _arrow:
			_arrow = dir
			queue_redraw()

	func follow(p: Node2D, screen: Vector2, view: Rect2) -> void:
		# On the screen's edge, on the line from the middle to the robot.
		var mid := view.get_center()
		var dir := (screen - mid).normalized()
		aim(p.global_position, dir)
		var half := view.size / 2.0 - size / 2.0 - Vector2(INSET, INSET)
		var k := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
		position = mid + dir * k - size / 2.0

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r.grow(3), Color.BLACK)
		draw_rect(r, _color)
		# Arrow on the side facing the robot.
		var c := size / 2.0
		var tip := c + _arrow * (size.length() / 2.0 + 10.0)
		var edge := c + _arrow * minf(size.x / 2.0 / maxf(absf(_arrow.x), 0.001), size.y / 2.0 / maxf(absf(_arrow.y), 0.001))
		var side := _arrow.orthogonal() * 14.0
		draw_colored_polygon(PackedVector2Array([edge + side, tip, edge - side]), Color.BLACK)
		draw_colored_polygon(PackedVector2Array([edge + side * 0.6, tip - _arrow * 5.0, edge - side * 0.6]), _color)


## Settings preview: a bubble on a small made-up level (its own world), with a
## robot walking back and forth, so the Bubble view / size settings can be seen.
class Preview extends Control:
	const TEX_TILE := preload("res://levels/tile.webp")
	const TEX_CRATE := preload("res://objects/crate.webp")
	const TEX_BASE := preload("res://objects/button_base.webp")
	const TEX_CAP := preload("res://objects/button_cap.webp")
	const TEX_BODY := preload("res://player/player_body.webp")
	const TEX_FACE := preload("res://player/player_face.webp")

	var _world: SubViewport  # holds the little level; never shown itself
	var _robot: Node2D
	var _bubble: Bubble
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_world = SubViewport.new()
		_world.size = Vector2i(4, 4)
		_world.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_world.world_2d = World2D.new()
		add_child(_world)
		_build_level(_world)
		var color: Color = PlayerSpawner.COLORS[1]
		_bubble = Bubble.new()
		_bubble.setup(_world.world_2d, color)
		add_child(_bubble)

	func _build_level(root: Node) -> void:
		root.add_child(preload("res://levels/background.tscn").instantiate())
		# Ground, two steps and a high ledge, styled like the levels.
		for rect in [
			Rect2(-900, 0, 1800, 260),
			Rect2(260, -90, 260, 90),
			Rect2(520, -180, 380, 180),
			Rect2(-700, -330, 320, 60),
		]:
			var poly := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
			var body := StaticBody2D.new()
			var shape := CollisionPolygon2D.new()
			shape.polygon = poly
			body.add_child(shape)
			var p := SyncedPolygon.new()
			p.polygon = poly
			body.add_child(p)
			root.add_child(body)
		_sprite(root, TEX_CRATE, Vector2(-260, -40), 2.5)
		_sprite(root, TEX_CRATE, Vector2(-180, -40), 2.5)
		_sprite(root, TEX_CRATE, Vector2(-220, -120), 2.5)
		_sprite(root, TEX_BASE, Vector2(120, -40), 2.5)
		_sprite(root, TEX_CAP, Vector2(120, -40), 2.5).modulate = PlayerSpawner.COLORS[2]
		_robot = Node2D.new()
		var body := _sprite(_robot, TEX_BODY, Vector2.ZERO, 2.5)
		body.region_enabled = true
		body.region_rect = Rect2(0, 0, 32, 32)
		body.modulate = PlayerSpawner.COLORS[1]
		var face := _sprite(_robot, TEX_FACE, Vector2.ZERO, 2.5)
		face.region_enabled = true
		face.region_rect = Rect2(0, 0, 32, 32)
		root.add_child(_robot)

	func _sprite(parent: Node, tex: Texture2D, pos: Vector2, s: float) -> Sprite2D:
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.position = pos
		sp.scale = Vector2(s, s)
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		parent.add_child(sp)
		return sp

	## Where the menu's cable plugs in: the bubble's left edge (global).
	func cable_point() -> Vector2:
		return _bubble.global_position + Vector2(-3, _bubble.size.y / 2.0)

	func _process(delta: float) -> void:
		_t += delta
		# Walk back and forth on the ground.
		var x := sin(_t * 0.7) * 160.0
		_robot.position = Vector2(x, -40)
		_robot.scale.x = 1.0 if cos(_t * 0.7) >= 0.0 else -1.0
		_bubble.aim(_robot.position, Vector2.RIGHT)
		# Centred in this box; the arrow points out to the right.
		_bubble.position = ((size - _bubble.size) / 2.0).round()
