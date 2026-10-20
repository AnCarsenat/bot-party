extends CharacterBody2D

@export var speed: float = 400.0
@export var jump_speed: float = -800.0
@export var gravity: float = 1500.0
@export var input_prefix: String = "p1"

## Grace period after leaving a ledge during which a jump still works (late press).
@export var coyote_time: float = 0.1
## How long a jump press is remembered before landing (early press).
@export var jump_buffer_time: float = 0.12
## Releasing jump early multiplies the upward speed by this (short hops).
@export_range(0.1, 1.0, 0.05) var jump_cut: float = 0.5
## Fall faster than you rise: feels snappier.
@export var fall_gravity_multiplier: float = 1.35
@export var max_fall_speed: float = 1400.0
## Horizontal acceleration on the ground / in the air (pixels/s²). Higher = snappier.
@export var ground_accel: float = 6000.0
@export var air_accel: float = 3500.0
## Strength of the push applied to crates.
@export var push_strength: float = 60.0
## Background machines this light (or lighter) get shoved when you walk through them.
@export var machine_push_max_mass: float = 4.0
## How strongly machines follow your movement when you walk through them.
@export var machine_push_strength: float = 0.25

enum MovementTypes {
	PLATFORMER,
	TOP_DOWN
}

@export var movement_type: MovementTypes = MovementTypes.PLATFORMER

var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0

var _was_on_floor := true
var _jumping := false
var _base_scale := Vector2.ONE
var _squash := Vector2.ONE
var _machine_query := PhysicsShapeQueryParameters2D.new()
## Players standing on me -> physics frame they last reported it.
var _riders := {}

@onready var _sprite: Sprite2D = $Sprite2D


func _init() -> void:
	# Players collide with the world, each other and crates - never with machines.
	collision_layer = Layers.PLAYERS
	collision_mask = Layers.WORLD | Layers.PLAYERS | Layers.CRATES
	# Another player is never a "moving platform": we don't ride their motion and
	# don't inherit their upward speed when leaving them (that gave free height).
	platform_floor_layers = 0xFFFFFFFF & ~Layers.PLAYERS


func _ready() -> void:
	_base_scale = _sprite.scale
	_machine_query.collision_mask = Layers.MACHINES
	_machine_query.shape = $CollisionShape2D.shape


func _physics_process(delta: float) -> void:
	match movement_type:
		MovementTypes.PLATFORMER:
			platformer_movement(delta)
		MovementTypes.TOP_DOWN:
			top_down_movement()
	_push_bodies()
	_shove_machines()
	_animate(delta)


func _jump_held() -> bool:
	return Input.is_action_pressed(input_prefix + "_action_1") \
		or Input.is_action_pressed(input_prefix + "_move_up")


func platformer_movement(delta: float) -> void:
	if not is_on_floor():
		var g := gravity * (fall_gravity_multiplier if velocity.y > 0.0 else 1.0)
		velocity.y = minf(velocity.y + g * delta, max_fall_speed)
	elif velocity.y > 0.0:
		velocity.y = 0.0

	# Coyote time: refill while grounded, count down once airborne.
	# Standing on another player only counts if that player is grounded too,
	# otherwise A could "land" on a rising B mid-air and jump again (infinite height).
	if is_supported():
		coyote_timer = coyote_time
		_jumping = false
	else:
		coyote_timer -= delta

	# Jump buffer: remember a press for a short while.
	if Input.is_action_just_pressed(input_prefix + "_action_1") \
			or Input.is_action_just_pressed(input_prefix + "_move_up"):
		jump_buffer_timer = jump_buffer_time
	else:
		jump_buffer_timer -= delta

	if jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		velocity.y = jump_speed
		jump_buffer_timer = 0.0
		coyote_timer = 0.0  # prevents a double jump within the coyote window
		_jumping = true
		_squash = Vector2(0.75, 1.25)

	# Variable jump height: let go early for a short hop.
	if _jumping and velocity.y < 0.0 and not _jump_held():
		velocity.y *= jump_cut
		_jumping = false

	var direction := Input.get_axis(
		input_prefix + "_move_left",
		input_prefix + "_move_right"
	)
	var accel := ground_accel if is_on_floor() else air_accel
	velocity.x = move_toward(velocity.x, direction * speed, accel * delta)

	_report_to_player_below()
	var riders := _current_riders()
	# Riders go up first (so they never act as a ceiling for our jump)
	# and are launched with us.
	var planned_up := minf(velocity.y * delta, 0.0)
	if planned_up < 0.0:
		for r in riders:
			r.move_and_collide(Vector2(0.0, planned_up))
			r.velocity.y = minf(r.velocity.y, velocity.y)
	var before := global_position
	move_and_slide()
	# Then they follow the rest of our actual movement (sideways, and down when we fall).
	var moved := global_position - before
	var follow := Vector2(moved.x, maxf(moved.y, 0.0))
	if follow != Vector2.ZERO:
		for r in riders:
			r.move_and_collide(follow)

	if is_on_floor() and not _was_on_floor:
		_squash = Vector2(1.25, 0.8)  # landing
	_was_on_floor = is_on_floor()


func top_down_movement() -> void:
	var direction := Vector2(
		Input.get_axis(
			input_prefix + "_move_left",
			input_prefix + "_move_right"
		),
		Input.get_axis(
			input_prefix + "_move_up",
			input_prefix + "_move_down"
		)
	).normalized()

	velocity = direction * speed
	move_and_slide()


## Called by trampolines.
func bounce(speed: float, hold_boost: float = 1.0) -> void:
	velocity.y = -speed * (hold_boost if _jump_held() else 1.0)
	_jumping = false          # a bounce can't be cut short
	coyote_timer = 0.0
	jump_buffer_timer = 0.0
	_squash = Vector2(0.7, 1.3)


## On solid ground: the floor, a crate, or a player who is itself supported.
func is_supported(depth: int = 0) -> bool:
	if not is_on_floor():
		return false
	if depth > 8:
		return true
	var found := false
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_normal().dot(up_direction) < 0.7:
			continue  # wall or ceiling, not something we stand on
		found = true
		if _support_ok(c.get_collider(), depth):
			return true
	if found:
		return false
	# Standing still: move_and_slide reported nothing, so probe just below the feet.
	var probe := move_and_collide(Vector2(0, 4), true, 0.08, true)
	if probe == null or probe.get_normal().dot(up_direction) < 0.7:
		return false  # nothing under our feet any more (e.g. the player below fell away)
	return _support_ok(probe.get_collider(), depth)


## The player we are standing on, if any.
func player_below() -> CharacterBody2D:
	if not is_on_floor():
		return null
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_normal().dot(up_direction) >= 0.7 and c.get_collider() is CharacterBody2D:
			return c.get_collider()
	var probe := move_and_collide(Vector2(0, 4), true, 0.08, true)
	if probe and probe.get_normal().dot(up_direction) >= 0.7 and probe.get_collider() is CharacterBody2D:
		return probe.get_collider()
	return null


func _report_to_player_below() -> void:
	var below := player_below()
	if below != null and below.has_method("add_rider"):
		below.add_rider(self)


func add_rider(rider: CharacterBody2D) -> void:
	_riders[rider] = Engine.get_physics_frames()


func _current_riders() -> Array:
	var now := Engine.get_physics_frames()
	var list := []
	for r in _riders.keys():
		if not is_instance_valid(r) or now - _riders[r] > 1 or r.get_meta("eliminated", false):
			_riders.erase(r)
		else:
			list.append(r)
	return list


func _support_ok(other: Object, depth: int) -> bool:
	if other != null and other.has_method("is_supported"):
		return other.is_supported(depth + 1)
	return true


## Push crates / logic blocks we walk into (sideways only).
func _push_bodies() -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var body := c.get_collider() as RigidBody2D
		if body == null or body.freeze:
			continue
		var n := c.get_normal()
		if absf(n.x) > 0.5:
			body.apply_central_impulse(Vector2(-n.x * push_strength, 0.0))


## Machines don't block us, but light ones get nudged along as we pass.
func _shove_machines() -> void:
	if absf(velocity.x) < 10.0:
		return
	_machine_query.transform = global_transform
	for hit in get_world_2d().direct_space_state.intersect_shape(_machine_query, 8):
		var m := hit.collider as RigidBody2D
		if m == null or m.freeze or m.mass > machine_push_max_mass:
			continue
		var dv := velocity.x - m.linear_velocity.x
		if signf(dv) == signf(velocity.x):
			m.apply_central_impulse(Vector2(dv * m.mass * machine_push_strength, 0.0))


## Squash & stretch and facing direction (sprite only, the hitbox never changes).
func _animate(delta: float) -> void:
	_squash = _squash.lerp(Vector2.ONE, 1.0 - exp(-14.0 * delta))
	_sprite.scale = _base_scale * _squash
	# Keep the feet on the ground while squashing.
	_sprite.position.y = (1.0 - _squash.y) * 41.0
	if absf(velocity.x) > 10.0:
		_sprite.flip_h = velocity.x < 0.0
