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
## Effects on the robot (party traps): name -> seconds left. The host runs them;
## online clients only show them.
##   stuck     held in place, even in mid-air (bear trap)
##   slippery  hardly any grip (spitter, ice)
##   slowed    half speed, lower jumps (glue)
##   floating  drifts up slowly (balloon)
var statuses := {}
const STATUSES := ["stuck", "slippery", "slowed", "floating"]
## A pull towards something (magnets): a speed added this physics frame.
var _pull := Vector2.ZERO
var _pull_frame := -10
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
		# Online client: the host moves the others; our own robots move here
		# right away (predicted) and are nudged to where the host has them.
		set_physics_process(_predicted())


# --- Online ---------------------------------------------------------------------

var _net_target := Vector2.INF


func net_state() -> Array:
	return [Vector2i(global_position.round()), _sprite.frame, _face.frame, _sprite.flip_h,
		_sprite.scale, visible, get_meta("eliminated", false), get_meta("finished", false),
		get_meta("coin", false), snappedf(modulate.a, 0.05), [] if get_meta("eliminated", false) else statuses.keys(),
		# Can it move (a finished robot is switched off as a whole), and how it
		# moves (surprise rules; party robots go through each other).
		can_process() and is_physics_processing(),
		[gravity, speed, jump_speed, collision_mask & Layers.PLAYERS == 0]]


## Online client: is this one of our own robots (moved here, not by the host)?
func _predicted() -> bool:
	var net := get_tree().root.get_node_or_null("Net") if is_inside_tree() else null
	return net != null and net.is_client() and net.my_slots().has(get_meta("player_index", 0) + 1)


var _history: Array = []  # predicted: [msec, position] of the last second
var _net_vel := Vector2.ZERO  # others: how fast they were going (between news)
var _net_at := 0              # msec of the last news about them
var _nudge := Vector2.ZERO    # predicted: correction still to make up


func net_apply(s: Array) -> void:
	var pos := Vector2(s[0])
	var predicted := _predicted()
	if s.size() > 12:
		gravity = s[12][0]
		speed = s[12][1]
		jump_speed = s[12][2]
		set_ghostly(s[12][3])
	if predicted:
		# Moving it ourselves (the host says when it can move at all).
		var can_move: bool = (s[11] if s.size() > 11 else true) and not s[7]
		set_physics_process(can_move)
		_net_target = Vector2.INF
		_correct(pos)
	else:
		set_physics_process(false)
		net_move(pos)
		_sprite.frame = s[1]
		_face.frame = s[2]
		_sprite.flip_h = s[3]
		_face.flip_h = s[3]
		_sprite.scale = s[4]
	visible = s[5]
	set_meta("finished", s[7])
	if s[7]:
		remove_from_group("camera_follow")  # made it: the camera keeps to the others
	set_meta("coin", s[8])
	modulate.a = s[9]
	if s.size() > 10:
		statuses.clear()
		for k in s[10]:
			statuses[k] = 1.0  # shown only: the host keeps the time
	if s[6] and not get_meta("eliminated", false):
		var scene := get_tree().current_scene
		var game := scene.get_node_or_null("Game") if scene else null
		if game:
			game.eliminate_player(self)


## Online client: where the host has one of the others now (snapshots, and
## every frame in between). Shown smoothly, a little ahead along its speed.
func net_move(pos: Vector2) -> void:
	if _predicted():
		return
	var now := Time.get_ticks_msec()
	if _net_target == Vector2.INF or global_position.distance_to(pos) > 200.0:
		global_position = pos  # first update or teleport (respawn, door...)
		_net_vel = Vector2.ZERO
	elif now > _net_at and _net_target != pos:
		_net_vel = _net_vel.lerp((pos - _net_target) / ((now - _net_at) / 1000.0), 0.5)
	elif _net_target == pos:
		_net_vel = Vector2.ZERO
	_net_target = pos
	_net_at = now


func _process(delta: float) -> void:
	if _net_target != Vector2.INF:
		var ahead := clampf((Time.get_ticks_msec() - _net_at) / 1000.0, 0.0, 0.08)
		var aim := _net_target + _net_vel * ahead
		global_position = global_position.lerp(aim, 1.0 - exp(-18.0 * delta))
	elif _nudge != Vector2.ZERO:
		# Predicted: a correction made up over a few frames, not in one jump.
		var step := _nudge * minf(1.0, 12.0 * delta)
		global_position += step
		_nudge -= step
		for h in _history:
			h[1] += step  # (so the same difference isn't made up twice)
		if _nudge.length() < 0.5:
			_nudge = Vector2.ZERO


## Predicted robot: where the host has it is where we were about one round
## trip ago; if that's off, the difference is made up over a few frames (at
## once when far: a respawn or a teleport).
func _correct(host_pos: Vector2) -> void:
	var net := get_tree().root.get_node("Net")
	var then: float = Time.get_ticks_msec() - net.round_trip_ms() - 20
	var was := global_position
	for i in _history.size():
		if _history[i][0] > then:
			if i > 0:
				# Between the two samples around that moment.
				var a: Array = _history[i - 1]
				var b: Array = _history[i]
				var t := clampf((then - a[0]) / maxf(1.0, b[0] - a[0]), 0.0, 1.0)
				was = Vector2(a[1]).lerp(b[1], t)
			break
		was = _history[i][1]
	var off := host_pos - was - _nudge
	if (host_pos - was).length() > 220.0:
		global_position = host_pos
		_history.clear()
		_nudge = Vector2.ZERO
	elif off.length() > 10.0:
		_nudge += off * 0.5


func _record_history() -> void:
	var now := Time.get_ticks_msec()
	_history.append([now, global_position])
	while not _history.is_empty() and now - _history[0][0] > 1000:
		_history.pop_front()


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


# --- Statuses -------------------------------------------------------------------

## Puts an effect on the robot for `seconds` (or longer, if it already has it).
func add_status(status: String, seconds: float) -> void:
	if get_meta("eliminated", false) or get_meta("finished", false) or get_meta("god", false):
		return
	statuses[status] = maxf(float(statuses.get(status, 0.0)), seconds)


func has_status(status: String) -> bool:
	if get_meta("eliminated", false) and not statuses.is_empty():
		statuses.clear()  # out of the round: no more effects
	return statuses.has(status)


## Pulled towards something (a magnet), for this physics frame.
func pull(v: Vector2) -> void:
	if _pull_frame != Engine.get_physics_frames():
		_pull = Vector2.ZERO
		_pull_frame = Engine.get_physics_frames()
	_pull += v


func _tick_statuses(delta: float) -> void:
	if get_meta("eliminated", false):
		statuses.clear()
	for k in statuses.keys():
		statuses[k] -= delta
		if statuses[k] <= 0.0:
			statuses.erase(k)


func _physics_process(delta: float) -> void:
	var predicted := NetCheck.client(self)  # (only our own robots move on a client)
	if not predicted:
		_tick_statuses(delta)  # a client shows the host's statuses
	if _prev_position != Vector2.INF and delta > 0.0:
		actual_velocity = (global_position - _prev_position) / delta
	_prev_position = global_position
	match movement_type:
		MovementTypes.PLATFORMER:
			platformer_movement(delta)
		MovementTypes.TOP_DOWN:
			top_down_movement()
	if predicted:
		_record_history()
	else:
		_push_bodies()  # crates and machines: the host moves them
		_shove_machines()
	_animate(delta)


func _jump_held() -> bool:
	return Input.is_action_pressed(input_prefix + "_action_1") \
		or Input.is_action_pressed(input_prefix + "_move_up")


func platformer_movement(delta: float) -> void:
	if get_meta("noclip", false):
		_noclip_movement(delta)
		return
	var stuck := has_status("stuck")
	var slowed := has_status("slowed")
	if stuck:
		velocity = Vector2.ZERO  # held where it was caught, even in mid-air
	elif has_status("floating"):
		velocity.y = move_toward(velocity.y, -170.0, 2400.0 * delta)
	elif not is_on_floor():
		var g := gravity * (fall_gravity_multiplier if velocity.y > 0.0 else 1.0)
		velocity.y = minf(velocity.y + g * delta, max_fall_speed)
	elif velocity.y > 0.0:
		velocity.y = 0.0
	var pulled := _pull if _pull_frame >= Engine.get_physics_frames() - 1 else Vector2.ZERO
	if pulled.y != 0.0 and not stuck:
		velocity.y += pulled.y * delta * 4.0

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

	if jump_buffer_timer > 0.0 and coyote_timer > 0.0 and not stuck:
		velocity.y = jump_speed * (0.75 if slowed else 1.0)
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
	if stuck:
		direction = 0.0
	if is_on_floor() and player_below() == null:
		_carry_vx = 0.0
	elif not is_on_floor():
		_carry_vx = move_toward(_carry_vx, 0.0, carry_momentum_decay * delta)
	var accel := ground_accel if is_on_floor() else air_accel
	if has_status("slippery"):
		accel *= 0.07 if is_on_floor() else 0.35  # on ice: hard to start, harder to stop
	var target := direction * speed * (0.5 if slowed else 1.0) + (0.0 if is_on_floor() else _carry_vx) + wind_vx + pulled.x
	if stuck:
		velocity.x = 0.0
	else:
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
