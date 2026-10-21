extends StaticBody2D
## Flamethrower: the base is solid; every few seconds it shoots a column of fire.
## It sputters just before firing. The dashed box shows how far the flames reach.

const TEX_FLAME := preload("res://party/art/flame.webp")

@export var reach: float = 192.0
@export var on_time: float = 1.2
@export var off_time: float = 1.8
@export var warn_time: float = 0.45

## Top of the chimney (where the flames come out), from the sprite.
const NOZZLE_Y := -10.0

var _t := 0.0
var _hazard: Hazard
var _flames: Array[Sprite2D] = []


func _ready() -> void:
	add_to_group("net_sync")
	add_to_group("net_sync_slow")  # clients run the clock themselves
	collision_layer = Layers.WORLD
	# Solid parts follow the sprite: a wide base and the chimney on top of it.
	for part in [[Vector2(-3, 14), Vector2(42, 16)], [Vector2(0, -2), Vector2(20, 16)]]:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = part[1]
		shape.shape = rect
		shape.position = part[0]
		add_child(shape)
	_hazard = Hazard.new()
	_hazard.name = "Hazard"
	var hs := CollisionShape2D.new()
	var h := RectangleShape2D.new()
	h.size = Vector2(40, reach)
	hs.shape = h
	hs.position = Vector2(0, NOZZLE_Y - reach / 2.0)
	_hazard.add_child(hs)
	add_child(_hazard)
	var n := ceili(reach / 64.0)
	for i in n:
		var f := Sprite2D.new()
		f.texture = TEX_FLAME
		f.hframes = 4
		f.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		f.scale = Vector2(2, 2)
		f.position = Vector2(0, NOZZLE_Y - 32 - i * 64)
		f.show_behind_parent = true
		add_child(f)
		_flames.append(f)
	_apply(false)


func firing() -> bool:
	return fmod(_t, on_time + off_time) >= off_time


func reset_round() -> void:
	_t = 0.0
	_apply(false)


func _physics_process(delta: float) -> void:
	var was := firing()
	_t += delta
	if firing() != was:
		_apply(firing())


func _apply(on: bool) -> void:
	_hazard.set_deferred("monitoring", on)
	for f in _flames:
		f.visible = on


func _process(_d: float) -> void:
	var cyc := fmod(_t, on_time + off_time)
	for i in _flames.size():
		_flames[i].frame = (int(_t * 12.0) + i) % 4
	queue_redraw()
	# Sputter: the lowest flame flickers in just before it fires.
	if not firing() and cyc > off_time - warn_time and not _flames.is_empty():
		_flames[0].visible = int(_t * 20.0) % 2 == 0


func _draw() -> void:
	var r := Rect2(-20, NOZZLE_Y - reach, 40, reach)
	var c := Color(0.9, 0.31, 0.24, 0.55)
	var y := r.position.y
	while y < r.end.y:
		draw_line(Vector2(r.position.x, y), Vector2(r.position.x, minf(y + 8, r.end.y)), c, 2.0)
		draw_line(Vector2(r.end.x, y), Vector2(r.end.x, minf(y + 8, r.end.y)), c, 2.0)
		y += 16.0
	draw_line(r.position, Vector2(r.end.x, r.position.y), c, 2.0)
	# Base sprite drawn by hand so it sits in front of the flames.
	draw_texture_rect(preload("res://party/art/flamer.webp"), Rect2(-32, -32 + 0, 64, 64), false)


# Online: clients follow the host's clock (corrected when they drift apart).
func net_state() -> Array:
	return [snappedf(_t, 0.01)]


func net_apply(s: Array) -> void:
	if absf(_t - s[0]) > 0.1:
		_t = s[0]
