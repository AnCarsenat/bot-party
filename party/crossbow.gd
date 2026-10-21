extends Node2D
## Shoots a bolt every `interval` seconds, forwards (left, or right when mirrored).
## Turning the crossbow turns where it shoots. Bolts stop on walls and crates.

@export var interval: float = 1.6
@export var bolt_speed: float = 560.0
@export var bolt_life: float = 4.0

const BOLT_STOPPERS := Layers.WORLD | Layers.CRATES

var mirrored := false
var _t := 0.0
@onready var _sprite: Sprite2D = $Sprite2D


func set_mirrored(value: bool) -> void:
	mirrored = value
	if is_node_ready():
		_sprite.flip_h = value


func _ready() -> void:
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
	return global_position + forward() * 34.0 + Vector2(0, 2).rotated(global_rotation)


## Where a bolt fired now would stop (for the placing preview).
func bolt_end(_space = null) -> Vector2:
	return Hazard.path_end(self, muzzle(), forward(), bolt_speed * bolt_life, BOLT_STOPPERS)


func reset_round() -> void:
	_t = 0.0


func _physics_process(delta: float) -> void:
	_t += delta
	# Little recoil on the sprite right after a shot.
	_sprite.position.x = lerpf(_sprite.position.x, 0.0, 12.0 * delta)
	if _t >= interval:
		_t = 0.0
		_fire()


func _fire() -> void:
	var bolt := _Bolt.new()
	bolt.velocity = forward() * bolt_speed
	bolt.life = bolt_life
	bolt.rotation = forward().angle() + PI
	bolt.owner_slot = get_meta("owner_slot", 0)
	bolt.add_to_group("bolts")
	# Into the level itself, so bolts fly straight even from a moving mount.
	var level := get_tree().current_scene if get_tree().current_scene else get_parent()
	level.add_child(bolt)
	bolt.global_position = muzzle()
	_sprite.position.x = 4.0 if not mirrored else -4.0


class _Bolt extends Hazard:
	var velocity := Vector2.ZERO
	var life := 4.0

	func _ready() -> void:
		super()
		collision_mask = Layers.HURTBOX | BOLT_STOPPERS
		body_entered.connect(func(_b): queue_free())
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(30, 8)
		shape.shape = rect
		add_child(shape)
		var s := Sprite2D.new()
		s.texture = preload("res://party/art/bolt.webp")
		s.scale = Vector2(2, 2)
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(s)

	func _physics_process(delta: float) -> void:
		var from := global_position
		var to := from + velocity * delta
		# Stops in anything solid, even if it starts inside it (crossbow in a block)
		# or would skip through something thin in one step.
		var q := PhysicsRayQueryParameters2D.create(from, to, BOLT_STOPPERS)
		q.hit_from_inside = true
		if get_world_2d().direct_space_state.intersect_ray(q) or Hazard.in_start_area(self, to):
			queue_free()
			return
		global_position = to
		life -= delta
		if life <= 0.0:
			queue_free()

	func _on_area_entered(area: Area2D) -> void:
		super(area)
		if area.has_meta("player"):
			queue_free()
