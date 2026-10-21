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
## How fast the speed inherited from a player you jumped off fades (pixels/s²).
@export var carry_momentum_decay: float = 500.0

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
var _last_below: CharacterBody2D
## Sideways speed kept after leaving a moving player (fades out in the air).
var _carry_vx := 0.0
## How fast we actually moved last frame (includes being carried).
var actual_velocity := Vector2.ZERO
## Sideways push from the arena (wind). Added to where we're trying to go.
var wind_vx := 0.0
var _prev_position := Vector2.INF

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _face: Sprite2D = $Sprite2D/Face

# Sprite sheet frames (player_body.webp / player_face.webp).
const FRAME_IDLE := 0      # 0-1
const FRAME_RUN := 2       # 2-5
const FRAME_JUMP := 6
const FRAME_FALL := 7
const FACE_BLINK := 8
var _anim_time := 0.0
var _blink_in := 3.0


func _init() -> void:
	# Players collide with the world, each other and crates - never with machines.
	collision_layer = Layers.PLAYERS
	collision_mask = Layers.WORLD | Layers.PLAYERS | Layers.CRATES
	# Another player is never a "moving platform": we don't ride their motion and
	# don't inherit their upward speed when leaving them (that gave free height).
	platform_floor_layers = 0xFFFFFFFF & ~Layers.PLAYERS


## Traps hurt this box, which is a bit smaller than the body: brushing past a
## spike with a pixel of your outline doesn't count.
const HURTBOX_INSET := 6.0

var _base_sprite_pos := Vector2.ZERO


func _ready() -> void:
	_base_scale = _sprite.scale
	_base_sprite_pos = _sprite.position
	_machine_query.collision_mask = Layers.MACHINES
	_machine_query.shape = $CollisionShape2D.shape
	_add_hurtbox()
	add_to_group("net_sync")
	if NetCheck.client(self):
		set_physics_process(false)  # online client: the host moves us


# --- Online ---------------------------------------------------------------------

var _net_target := Vector2.INF


func net_state() -> Array:
	return [Vector2i(global_position.round()), _sprite.frame, _face.frame, _sprite.flip_h,
		_sprite.scale, visible, get_meta("eliminated", false), get_meta("finished", false),
		get_meta("coin", false), snappedf(modulate.a, 0.05)]


func net_apply(s: Array) -> void:
	set_physics_process(false)
	var pos := Vector2(s[0])
	if _net_target == Vector2.INF or global_position.distance_to(pos) > 200.0:
		global_position = pos  # first update or teleport (respawn, door...)
	_net_target = pos
	_sprite.frame = s[1]
	_face.frame = s[2]
	_sprite.flip_h = s[3]
	_face.flip_h = s[3]
	_sprite.scale = s[4]
	visible = s[5]
	set_meta("finished", s[7])
	set_meta("coin", s[8])
	modulate.a = s[9]
	if s[6] and not get_meta("eliminated", false):
		var scene := get_tree().current_scene
		var game := scene.get_node_or_null("Game") if scene else null
		if game:
			game.eliminate_player(self)


func _process(delta: float) -> void:
	if _net_target != Vector2.INF:
		global_position = global_position.lerp(_net_target, 1.0 - exp(-30.0 * delta))


func _add_hurtbox() -> void:
	var body_shape := $CollisionShape2D.shape as RectangleShape2D
	var box := Area2D.new()
	box.name = "Hurtbox"
	box.collision_layer = Layers.HURTBOX
	box.collision_mask = 0
	box.monitoring = false
	box.set_meta("player", self)
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = (body_shape.size if body_shape else Vector2(82, 82)) - Vector2.ONE * HURTBOX_INSET * 2.0
	cs.shape = rect
	cs.position = $CollisionShape2D.position
	box.add_child(cs)
	add_child(box)


## Party mode: players run through each other (no standing on heads, no riding).
func set_ghostly(value: bool) -> void:
	if value:
		collision_mask &= ~Layers.PLAYERS
	else:
		collision_mask |= Layers.PLAYERS


func _physics_process(delta: float) -> void:
	if _prev_position != Vector2.INF and delta > 0.0:
		actual_velocity = (global_position - _prev_position) / delta
	_prev_position = global_position
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
	if get_meta("noclip", false):
		_noclip_movement(delta)
		return
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
		if is_instance_valid(_last_below) and player_below() == _last_below:
			_carry_vx = _last_below.actual_velocity.x
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
	if is_on_floor() and player_below() == null:
		_carry_vx = 0.0
	elif not is_on_floor():
		_carry_vx = move_toward(_carry_vx, 0.0, carry_momentum_decay * delta)
	var accel := ground_accel if is_on_floor() else air_accel
	var target := direction * speed + (0.0 if is_on_floor() else _carry_vx) + wind_vx
	velocity.x = move_toward(velocity.x, target, accel * delta)

	var below := player_below()
	if below != null:
		below.add_rider(self)
		_last_below = below
	var riders := _current_riders()
	# Riders (and their riders) go up first, so they never act as a ceiling for
	# our jump, and they are launched with us.
	var planned_up := minf(velocity.y * delta, 0.0)
	if planned_up < 0.0:
		for r in riders:
			r.carry(Vector2(0.0, planned_up), velocity.y, actual_velocity.x)
	# Riders can't block our own movement either (they come along anyway).
	for r in riders:
		add_collision_exception_with(r)
	var before := global_position
	move_and_slide()
	for r in riders:
		if is_instance_valid(r):
			remove_collision_exception_with(r)
	# Then the whole stack follows the rest of our movement.
	var moved := global_position - before
	var follow := Vector2(moved.x, maxf(moved.y, 0.0))
	if follow != Vector2.ZERO:
		for r in riders:
			r.carry(follow)

	if is_on_floor() and not _was_on_floor:
		_squash = Vector2(1.25, 0.8)  # landing
	_was_on_floor = is_on_floor()


## Console "noclip": fly through everything in all four directions.
func _noclip_movement(delta: float) -> void:
	var dir := Vector2(
		Input.get_axis(input_prefix + "_move_left", input_prefix + "_move_right"),
		Input.get_axis(input_prefix + "_move_up", input_prefix + "_move_down"))
	velocity = dir * speed * 1.6
	global_position += velocity * delta
	_was_on_floor = false


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
func bounce(speed: float, hold_boost: float = 1.0, direction := Vector2.UP) -> void:
	var v := direction.normalized() * speed * (hold_boost if _jump_held() else 1.0)
	if absf(direction.y) > 0.3:
		velocity.y = v.y
	velocity.x += v.x
	_carry_vx = v.x  # sideways launches aren't cancelled by air control
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


## Moves us (and everyone standing on us) by `offset`. Called by the player below.
## `launch_vy` / `launch_vx`: the speed we leave with if the player below is jumping.
func carry(offset: Vector2, launch_vy := 0.0, launch_vx := 0.0, depth := 0) -> void:
	if depth > 8:
		return
	var riders := _current_riders()
	if offset.y < 0.0:
		for r in riders:
			r.carry(Vector2(0.0, offset.y), launch_vy, launch_vx, depth + 1)
	# Don't let the players we stand on / who stand on us block the carry.
	var linked: Array = riders.duplicate()
	if is_instance_valid(_last_below):
		linked.append(_last_below)
	for o in linked:
		add_collision_exception_with(o)
	var before := global_position
	move_and_collide(offset)
	var moved := global_position - before
	for o in linked:
		if is_instance_valid(o):
			remove_collision_exception_with(o)
	if launch_vy < 0.0:
		velocity.y = minf(velocity.y, launch_vy)
		_carry_vx = launch_vx
	var follow := Vector2(moved.x, maxf(moved.y, 0.0))
	if follow != Vector2.ZERO and offset.y >= 0.0:
		for r in riders:
			r.carry(follow, 0.0, 0.0, depth + 1)
	elif moved.x != 0.0:
		for r in riders:
			r.carry(Vector2(moved.x, 0.0), 0.0, 0.0, depth + 1)


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
	_sprite.position = _base_sprite_pos + Vector2(0.0, (1.0 - _squash.y) * 41.0)
	if absf(velocity.x) > 10.0:
		_sprite.flip_h = velocity.x < 0.0
		_face.flip_h = _sprite.flip_h

	# Pick the animation frame.
	var frame := FRAME_IDLE
	var moving := absf(actual_velocity.x) > 30.0
	if not is_on_floor():
		frame = FRAME_JUMP if velocity.y < 0.0 else FRAME_FALL
	elif moving:
		_anim_time += delta * clampf(absf(actual_velocity.x) / 60.0, 4.0, 12.0)
		frame = FRAME_RUN + int(_anim_time) % 4
	else:
		_anim_time += delta * 2.0
		frame = FRAME_IDLE + int(_anim_time) % 2
	_sprite.frame = frame
	_face.frame = frame
	# Blink now and then (only when standing still, where the blink frame lines up).
	_blink_in -= delta
	if _blink_in <= 0.0:
		if frame == FRAME_IDLE:
			_face.frame = FACE_BLINK
		if _blink_in < -0.12:
			_blink_in = randf_range(2.0, 5.0)
