extends Node2D
## Ferris wheel: gondolas go round and stay upright. Stand on their roofs to ride.
## Between the gondolas, the rim has attachment points: place another item near
## one and it hangs there, going round with the wheel. Mirror it to spin the other way.

const TEX_GONDOLA := preload("res://party/art/gondola.webp")

@export var radius: float = 150.0
@export var gondolas: int = 6
## Radians per second.
@export var spin: float = 0.45

var mirrored := false
var _angle := 0.0
var _cars: Array[AnimatableBody2D] = []
var _mounts: Array[ItemMount] = []


func set_mirrored(value: bool) -> void:
	mirrored = value


func _ready() -> void:
	add_to_group("net_sync")
	add_to_group("net_sync_slow")  # clients run the clock themselves
	for i in gondolas:
		var car := AnimatableBody2D.new()
		car.collision_layer = Layers.WORLD
		car.collision_mask = 0
		car.sync_to_physics = false
		var s := Sprite2D.new()
		s.texture = TEX_GONDOLA
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.scale = Vector2(2, 2)
		s.position = Vector2(0, 32)  # hangs from its top centre
		car.add_child(s)
		var cs := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(46, 8)
		cs.shape = rect
		cs.position = Vector2(0, 22)  # the roof
		cs.one_way_collision = true
		car.add_child(cs)
		add_child(car)
		_cars.append(car)
		var m := ItemMount.new()
		m.name = "Mount%d" % i
		m.z_index = 1
		add_child(m)
		_mounts.append(m)
	_place_cars()


## Attachment points (used by party mode).
func mounts() -> Array[ItemMount]:
	return _mounts


## How far attachment point `m` will have moved `t` seconds from now (bots plan
## with it: what hangs there goes round).
func mount_moved_by(m: ItemMount, t: float) -> Vector2:
	var i := _mounts.find(m)
	var a := _angle + spin * t * (-1.0 if mirrored else 1.0) + TAU * i / _cars.size() + PI / _cars.size()
	return global_transform.basis_xform(Vector2(cos(a), sin(a)) * radius - m.position)


func reset_round() -> void:
	_angle = 0.0
	_place_cars()


func _physics_process(delta: float) -> void:
	_angle += spin * delta * (-1.0 if mirrored else 1.0)
	_place_cars()


func _place_cars() -> void:
	for i in _cars.size():
		var a := _angle + TAU * i / _cars.size()
		_cars[i].position = Vector2(cos(a), sin(a)) * radius
		_cars[i].rotation = -global_rotation  # always upright
		var b := a + PI / _cars.size()  # halfway to the next gondola
		_mounts[i].position = Vector2(cos(b), sin(b)) * radius
		_mounts[i].rotation = -global_rotation

func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	var ink := Color.BLACK
	var green := Color("6cba7c")
	var mint := Color("b0e2bc")
	# Legs down to the ground.
	for side in [-1.0, 1.0]:
		var foot := Vector2(side * 110.0, radius + 60.0)
		draw_line(Vector2.ZERO, foot, ink, 14.0)
		draw_line(Vector2.ZERO, foot, green, 8.0)
	# Rim and spokes.
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, ink, 12.0)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, mint, 6.0)
	for i in _cars.size():
		var a := _angle + TAU * i / _cars.size()
		var p := Vector2(cos(a), sin(a)) * radius
		draw_line(Vector2.ZERO, p, ink, 7.0)
		draw_line(Vector2.ZERO, p, green, 3.0)
		draw_circle(p, 6.0, ink)
		draw_circle(p, 3.0, Color("f0fff4"))
	draw_circle(Vector2.ZERO, 14.0, ink)
	draw_circle(Vector2.ZERO, 9.0, Color("f0fff4"))


# Online: clients follow the host's clock (corrected when they drift apart).
func net_state() -> Array:
	return [snappedf(_angle, 0.001)]


func net_apply(s: Array) -> void:
	if absf(_angle - s[0]) > 0.02:
		_angle = s[0]
