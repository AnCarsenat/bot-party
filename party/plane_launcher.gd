extends StaticBody2D
## Paper plane launcher: every few seconds, a paper plane glides out (left, or right
## when mirrored) and flies straight on, bobbing a little. When it hits a wall or a
## block it crumples into a paper ball that drops away. Touching a plane takes you
## out. Planes vanish in the start area.

const TEX_PLANE := preload("res://party/art/paper_plane.webp")
const TEX_BALL := preload("res://party/art/paper_ball.webp")

@export var interval: float = 2.8
@export var plane_speed: float = 230.0
## How far a plane goes before it's gone.
@export var reach: float = 2600.0
## Planes crumple on solid things (off: they fly through everything).
@export var stopped_by_walls := true

var mirrored := false
var _t := 0.0
@onready var _sprite: Sprite2D = $Sprite2D


func set_mirrored(value: bool) -> void:
	mirrored = value
	if is_node_ready():
		_sprite.flip_h = value


func _ready() -> void:
	collision_layer = Layers.WORLD
	_sprite.flip_h = mirrored
	add_to_group("net_sync")
	add_to_group("net_sync_slow")  # clients run the clock themselves


func net_state() -> Array:
	return [snappedf(_t, 0.01)]


func net_apply(s: Array) -> void:
	if absf(_t - s[0]) > 0.1:
		_t = s[0]


func forward() -> Vector2:
	return Vector2(1 if mirrored else -1, 0).rotated(global_rotation)


func muzzle() -> Vector2:
	return global_position + forward() * 36.0 + Vector2(0, 5).rotated(global_rotation)


## Where a plane goes (placing preview).
func bolt_end(_space = null) -> Vector2:
	return Hazard.path_end(self, muzzle(), forward(), reach,
		(Layers.WORLD | Layers.CRATES) if stopped_by_walls else 0)


func reset_round() -> void:
	_t = 0.0


func _physics_process(delta: float) -> void:
	_t += delta
	_sprite.position.x = lerpf(_sprite.position.x, 0.0, 10.0 * delta)
	if _t >= interval:
		_t = 0.0
		_fire()


func _fire() -> void:
	var plane := _Plane.new()
	plane.velocity = forward() * plane_speed
	plane.life = reach / plane_speed
	plane.stoppers = (Layers.WORLD | Layers.CRATES) if stopped_by_walls else 0
	plane.mirrored = mirrored
	plane.owner_slot = get_meta("owner_slot", 0)
	plane.add_to_group("bolts")
	var level := get_tree().current_scene if get_tree().current_scene else get_parent()
	level.add_child(plane)
	plane.global_position = muzzle()
	plane.rotation = global_rotation
	plane.start = plane.global_position
	_sprite.position.x = 5.0 if not mirrored else -5.0


class _Plane extends Hazard:
	var velocity := Vector2.ZERO
	var life := 10.0
	var stoppers := 0
	var mirrored := false
	var start := Vector2.ZERO
	var _t := 0.0
	var _sprite: Sprite2D

	func _ready() -> void:
		super()
		collision_mask = Layers.HURTBOX
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(44, 18)
		shape.shape = rect
		add_child(shape)
		_sprite = Sprite2D.new()
		_sprite.texture = TEX_PLANE
		_sprite.scale = Vector2(2, 2)
		_sprite.flip_h = mirrored
		add_child(_sprite)

	func _physics_process(delta: float) -> void:
		_t += delta
		var along := start + velocity * _t
		# Gentle bob up and down, across the flight direction.
		var side := velocity.normalized().orthogonal() * sin(_t * 3.5) * 10.0
		var to := along + side
		if stoppers != 0:
			var q := PhysicsRayQueryParameters2D.create(global_position, to, stoppers)
			q.hit_from_inside = true
			var hit := get_world_2d().direct_space_state.intersect_ray(q)
			if hit:
				_crumple(hit.position)
				queue_free()
				return
		if Hazard.in_start_area(self, to) or _t >= life:
			queue_free()
			return
		global_position = to
		_sprite.rotation = cos(_t * 3.5) * 0.15 * (1.0 if mirrored else -1.0)

	## Hit a wall: the plane becomes a paper ball that bounces off and drops.
	func _crumple(at: Vector2) -> void:
		var ball := _PaperBall.new()
		ball.texture = TEX_BALL
		ball.scale = Vector2(2, 2)
		ball.velocity = -velocity.normalized() * 90.0 + Vector2(0, -160)
		ball.z_index = 20
		get_parent().add_child(ball)
		ball.global_position = at - velocity.normalized() * 10.0


class _PaperBall extends Sprite2D:
	var velocity := Vector2.ZERO
	var _t := 0.0

	func _physics_process(delta: float) -> void:
		_t += delta
		velocity.y += 1100.0 * delta
		var to := global_position + velocity * delta
		var q := PhysicsRayQueryParameters2D.create(global_position, to + Vector2(0, 12), Layers.WORLD | Layers.CRATES)
		var hit := get_world_2d().direct_space_state.intersect_ray(q)
		if hit and velocity.y > 0.0:
			velocity = Vector2(velocity.x * 0.6, -velocity.y * 0.35)  # little bounce
			to = hit.position - Vector2(0, 12)
		global_position = to
		rotation += velocity.x * delta * 0.05
		if _t > 1.0:
			modulate.a = maxf(0.0, 1.0 - (_t - 1.0) / 0.4)
		if _t > 1.4:
			queue_free()
