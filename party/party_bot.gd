class_name PartyBot
extends Node
## A computer player for party mode. It plays with the same controls as people
## (it presses its own slot's actions), so it follows the same rules:
##   pick:  walks its cursor to the item it likes best and takes it;
##   place: puts traps on the route the racers will take;
##   race:  every few frames it tries a handful of moves (walk, wait, short and
##          long jumps, both ways) in a small physics simulation and keeps the one
##          that gets closest to the flag without touching a trap or falling out.
##          "Closest" comes from a distance map of the arena, so it finds its way
##          around walls instead of running into them.

enum Skill { EASY, NORMAL, HARD }
const SKILL_NAMES := ["Easy", "Normal", "Hard"]

const CELL := 32.0
const BODY := Vector2(82, 82)  # the player's collision box (player.tscn)
const STEP := 1              # simulated frames per step
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "action_1", "action_2", "action_3"]
## How much the bot likes each item (traps first). Unknown items (mods): 2.
const LIKES := {"saw": 4.0, "crossbow": 3.5, "flamer": 3.0, "planes": 3.0, "spikes": 2.5, "mine": 2.5,
	"pendulum": 2.0, "ferris": 1.5, "slider": 1.5, "fan": 2.0, "conveyor": 1.5, "crumble": 1.5,
	"block": 1.2, "plank": 1.0, "trampoline": 1.0, "lift": 1.0, "bomb": 1.5, "nuke": 2.5}
const TRAPS := ["saw", "crossbow", "flamer", "planes", "spikes", "mine", "pendulum", "crumble", "fan", "conveyor"]

var slot := 0
var skill: int = Skill.NORMAL
var ctl: Node  # the PartyController

var _rng := RandomNumberGenerator.new()
var _held := {}            # action name -> true
var _taps := []            # [action, frames left]
var _erased := {}          # action name -> its keys (given back when the bot leaves)
# Pick / place.
var _wait := 0.0
var _want := -1
var _target := Vector2.INF
var _target_time := 0.0
# Race.
var _field := {}           # Vector2i -> distance to the flag, in cells
var _field_key := ""       # which arena layout it was made for
var _origin := Vector2.ZERO
var _phase := -1
## Distance maps shared by all bots: {key: [field, origin]} (only the latest is kept).
static var _shared := {}
var _plan: Array = []      # per frame: [dir, jump held]
var _commit := 0
var _dangers: Array = []   # [Rect2 now, Vector2 velocity, trap that switches on and off or null]
var _dangers_age := 99
var _seen_at := {}         # hazard shape id -> [where it was, physics frame] (to see it move)
var _best := INF
var _stuck := 0.0
var debug_log: Array = []   # filled when `debug` is on (tests)
var debug := false
var _query := PhysicsShapeQueryParameters2D.new()
var _motion := PhysicsTestMotionParameters2D.new()
var _result := PhysicsTestMotionResult2D.new()


func _init(for_slot := 0, bot_skill := Skill.NORMAL) -> void:
	slot = for_slot
	skill = bot_skill
	name = "Bot%d" % slot
	# Before the controller and the players: a press is seen the same frame.
	process_priority = -100
	process_physics_priority = -100


func _ready() -> void:
	_rng.randomize()
	# The keyboard keys of this slot no longer move this robot.
	for a in ACTIONS:
		var action := "p%d_%s" % [slot, a]
		if InputMap.has_action(action):
			_erased[action] = InputMap.action_get_events(action)
			InputMap.action_erase_events(action)


func _exit_tree() -> void:
	_release_all()
	for action in _erased:
		for e in _erased[action]:
			InputMap.action_add_event(action, e)
	_erased.clear()


func pace() -> float:
	return [0.45, 0.28, 0.16][skill]


# --- Pressing keys ----------------------------------------------------------------------

func _hold(a: String, on: bool) -> void:
	var action := "p%d_%s" % [slot, a]
	if on and not _held.has(action):
		Input.action_press(action)
		_held[action] = true
	elif not on and _held.has(action):
		Input.action_release(action)
		_held.erase(action)


func _tap(a: String) -> void:
	_hold(a, false)
	_hold(a, true)
	_taps.append([a, 2])


func _release_all() -> void:
	for action in _held:
		Input.action_release(action)
	_held.clear()
	_taps.clear()


func _update_taps() -> void:
	for t in _taps.duplicate():
		t[1] -= 1
		if t[1] <= 0:
			_hold(t[0], false)
			_taps.erase(t)


# --- Pick and place ----------------------------------------------------------------------

func _process(delta: float) -> void:
	_update_taps()
	if not is_instance_valid(ctl):
		return
	if ctl.phase != _phase:
		_phase = ctl.phase
		_field_key = ""  # items were placed: the arena changed
		_plan.clear()
	match ctl.phase:
		ctl.Phase.PICK:
			_pick(delta)
		ctl.Phase.PLACE:
			_place(delta)
		ctl.Phase.RUN:
			pass
		_:
			if not _held.is_empty() and _taps.is_empty():
				_release_all()
			_want = -1
			_target = Vector2.INF


func _pick(delta: float) -> void:
	if ctl.picks.has(slot):
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = pace() * _rng.randf_range(0.8, 1.3)
	if _want < 0 or ctl._taken(_want):
		_want = _choose_card()
	var at: int = ctl.cursors.get(slot, 0)
	if at == _want:
		_tap("action_1")
		return
	# Shorter way round (the cursor wraps and skips taken cards).
	var n: int = ctl.box.size()
	_tap("move_right" if posmod(_want - at, n) <= posmod(at - _want, n) else "move_left")


func _choose_card() -> int:
	var best := -1
	var best_score := -INF
	for i in ctl.box.size():
		if ctl._taken(i):
			continue
		var id: String = ctl.box[i]
		var like: float = LIKES.get(id, 2.0)
		if _party().ITEMS.get(id, {}).get("bomb", false) and ctl.placed_items().is_empty():
			like = 0.1
		var noise: float = [2.0, 1.0, 0.4][skill]
		var score: float = like + _rng.randf() * noise
		if score > best_score:
			best_score = score
			best = i
	return best


func _place(delta: float) -> void:
	var g = ctl.ghosts.get(slot)
	if g == null or not is_instance_valid(g):
		return
	var id: String = g.get_meta("item_id")
	_target_time += delta
	if _target == Vector2.INF or _target_time > 4.0:
		_target = _choose_spot(id)
		_target_time = 0.0
		if _rng.randf() < 0.5:
			_tap("action_3")  # face the other way, sometimes
	var to: Vector2 = _target - ctl.cursor[slot]
	var close: float = ctl.ghost_speed * delta * 1.5
	_hold("move_right", to.x > close)
	_hold("move_left", to.x < -close)
	_hold("move_down", to.y > close)
	_hold("move_up", to.y < -close)
	if absf(to.x) <= close and absf(to.y) <= close:
		_wait -= delta
		if _wait <= 0.0:
			_wait = pace()
			if ctl.can_place(id, g.global_position, ctl.turns.get(slot, 0)):
				_tap("action_1")
				_target = Vector2.INF
			else:
				_target_time = 99.0  # somewhere else


## Where to put an item: traps on the route, near the ground; bombs on others' items.
func _choose_spot(id: String) -> Vector2:
	var def: Dictionary = _party().ITEMS.get(id, {})
	var turn: int = ctl.turns.get(slot, 0)
	if def.get("bomb", false):
		var others: Array = ctl.placed_items().filter(func(it): return it.get_meta("owner_slot", 0) != slot)
		if not others.is_empty():
			return others[_rng.randi() % others.size()].global_position
	var route := _route()
	var size: Vector2 = def.get("size", Vector2(64, 64))
	var offset: Vector2 = def.get("offset", Vector2.ZERO)
	for attempt in 40:
		var pos: Vector2
		if not route.is_empty() and attempt < 30:
			var k := int(route.size() * _rng.randf_range(0.3, 0.92))
			pos = route[k]
			if id in TRAPS or _rng.randf() < 0.6:
				var floor_y := _floor_below(pos)
				if floor_y != INF:
					pos.y = floor_y - size.y / 2.0 - offset.y
			else:
				pos += Vector2(_rng.randf_range(-60, 60), _rng.randf_range(-120, -20))
		else:
			var area: Rect2 = ctl.build_area
			pos = Vector2(_rng.randf_range(area.position.x, area.end.x), _rng.randf_range(area.position.y, area.end.y))
		if ctl.can_place(id, pos, turn):
			return pos
	return ctl.cursor[slot]


func _floor_below(pos: Vector2) -> float:
	var q := PhysicsRayQueryParameters2D.create(pos, pos + Vector2(0, 400), Layers.WORLD)
	var hit := ctl.get_viewport().world_2d.direct_space_state.intersect_ray(q)
	return hit.position.y if hit else INF


# --- Race -----------------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(ctl) or ctl.phase != ctl.Phase.RUN:
		return
	var p = ctl.players.get(slot)
	if not is_instance_valid(p) or p.get_meta("eliminated", false) or p.get_meta("finished", false) or not p.is_physics_processing():
		if not _held.is_empty():
			_release_all()
		return
	if _field_key == "":
		_make_field()
	var d := _dist(p.global_position)
	if d < _best - 0.5:
		_best = d
		_stuck = 0.0
	else:
		_stuck += 1.0 / 60.0
	_commit -= 1
	if _plan.is_empty() or _commit <= 0:
		_make_plan(p)
	var step = _plan.pop_front()
	_hold("move_left", step[0] < 0)
	_hold("move_right", step[0] > 0)
	_hold("action_1", step[1])


## The plans worth trying from here, as per-frame inputs.
func _candidates(p: Node) -> Array:
	var out := []
	var long := [6, 12, 24]
	# A jump needs a fresh press: let go for a frame first if the key is still down.
	var now := 1 if _held.has("p%d_action_1" % slot) else 0
	if p.is_on_floor() or p.coyote_timer > 0.0:
		for dir in [-1, 0, 1]:
			out.append(_inputs(dir, 0, 0, 30))
		for dir in [-1, 1]:
			for hold in long:
				out.append(_inputs(dir, now, hold, 46))
			out.append(_inputs(dir, 8, 24, 52))  # run up, then jump
		out.append(_inputs(0, now, 24, 46))      # straight up
	else:
		var rising: bool = p.velocity.y < 0.0
		for dir in [-1, 0, 1]:
			out.append(_inputs(dir, 0, 40 if rising else 0, 46))
			if rising:
				out.append(_inputs(dir, 0, 0, 46))  # let go: drop sooner
	return out


func _inputs(dir: int, jump_after: int, hold: int, frames: int) -> Array:
	var steps := []
	for f in frames:
		var jump := hold > 0 and f >= jump_after and f < jump_after + hold
		steps.append([dir, jump])
	return steps


func _make_plan(p: Node) -> void:
	if _dangers_age > 6:
		_dangers = _find_dangers(p)
		_dangers_age = 0
	_dangers_age += 1
	var scored := []
	for plan in _candidates(p):
		var sim := _simulate(p, plan)
		scored.append([_score(sim, plan), plan.slice(0, maxi(1, sim.frames))])
	scored.sort_custom(func(a, b): return a[0] < b[0])
	# A good plan still works if the jump comes a little late (edges are tight):
	# check the best few, drop the fragile ones.
	for k in mini(4, scored.size()):
		if scored[k][0] < 1e7 and _fragile(p, scored[k][1]):
			scored[k][0] += 1e7
	scored.sort_custom(func(a, b): return a[0] < b[0])
	var pick := 0
	# Easier bots sometimes take a worse (but not deadly) move; stuck bots try things.
	var sloppy: float = [0.3, 0.08, 0.0][skill]
	if _stuck > 2.5:
		sloppy = 0.6
		if _stuck > 4.0:
			_stuck = 0.0
			_best = INF
	if scored.size() > 1 and _rng.randf() < sloppy and scored[1][0] < 1e7:
		pick = 1 + _rng.randi() % mini(2, scored.size() - 1)
		if scored[pick][0] >= 1e7:
			pick = 1
	_plan = scored[pick][1].duplicate()
	if debug:
		var desc = func(pl):
			var j: int = pl.filter(func(st): return st[1]).size()
			var first: int = pl.find_custom(func(st): return st[1])
			return "d%d j%d@%d" % [pl[0][0], j, first]
		var sim := _simulate(p, _plan)
		debug_log.append("pos %s v %s fl %s co %.2f | %s score %.1f -> end %s dead %s | alts %s" % [p.global_position.round(), p.velocity.round(), p.is_on_floor(), p.coyote_timer,
			desc.call(_plan), scored[pick][0], sim.pos.round(), sim.dead, scored.slice(0, 4).map(func(e): return "%s=%.1f" % [desc.call(e[1]), e[0]])])
	# Keep at it for a while (longer for jumps: the hold decides the height).
	var holds := 0
	for s in _plan:
		if s[1]:
			holds += 1
	_commit = maxi([10, 6, 3][skill], holds + 2) if holds > 0 else [10, 6, 3][skill]


func _fragile(p: Node, plan: Array) -> bool:
	var first := -1
	for i in plan.size():
		if plan[i][1]:
			first = i
			break
	if first < 0:
		return false
	var late := plan.duplicate()
	late.insert(first, [plan[first][0], false])
	late.insert(first, [plan[first][0], false])
	return _simulate(p, late).dead


## Lower is better: distance to the flag where the plan ends; traps and falls are out.
func _score(sim: Dictionary, plan: Array) -> float:
	if sim.dead:
		return 1e9 - sim.at  # if nothing is safe: what keeps us alive longest
	var d := _dist(sim.pos)
	if d == INF:
		return 1e8
	var score := d
	if not sim.floor:
		score += 1.5
	if plan[0][1] or plan[mini(10, plan.size() - 1)][1]:
		score += 0.3  # don't jump for nothing
	return score


## A small copy of the player's movement (player.gd), run ahead with test moves.
func _simulate(p: Node, plan: Array) -> Dictionary:
	var pos: Vector2 = p.global_position
	var vel: Vector2 = p.velocity
	var on_floor: bool = p.is_on_floor()
	# Start from the robot's real state: a jump key already held isn't a new press.
	var jumping: bool = p._jumping
	var was_held: bool = _held.has("p%d_action_1" % slot)
	var coyote: float = p.coyote_timer
	var dt := STEP / 60.0
	var cam = ctl._camera()
	var airborne := false
	var i := 0
	# The plan stops at its end or when we land after a jump. Then no keys: we
	# must come to rest on the ground (a plan ending over a pit, or landing so
	# fast we slide off a ledge, is a deadly plan).
	var stop_at := plan.size()
	var resting := 0
	var limit := plan.size() + 100
	while i < limit:
		var dir: int = plan[i][0] if i < stop_at else 0
		var held: bool = plan[i][1] if i < stop_at else false
		if i >= stop_at:
			resting = resting + 1 if on_floor else 0
			if resting > 8:
				break
		var pressed := held and not was_held
		was_held = held
		if not on_floor:
			var g: float = p.gravity * (p.fall_gravity_multiplier if vel.y > 0.0 else 1.0)
			vel.y = minf(vel.y + g * dt, p.max_fall_speed)
			coyote -= dt
		else:
			coyote = p.coyote_time
			jumping = false
		if pressed and coyote > 0.0:
			vel.y = p.jump_speed
			coyote = 0.0
			jumping = true
			on_floor = false
		if jumping and vel.y < 0.0 and not held:
			vel.y *= p.jump_cut
			jumping = false
		var accel: float = p.ground_accel if on_floor else p.air_accel
		vel.x = move_toward(vel.x, dir * p.speed + p.wind_vx, accel * dt)
		# Move and slide (twice: along a wall or the floor after a hit).
		var motion := vel * dt
		for k in 2:
			_motion.from = Transform2D(0.0, pos)
			_motion.motion = motion
			if PhysicsServer2D.body_test_motion(p.get_rid(), _motion, _result):
				pos += _result.get_travel()
				var n := _result.get_collision_normal()
				if n.y < -0.6:
					vel.y = minf(vel.y, 0.0)
				elif n.y > 0.6:
					vel.y = maxf(vel.y, 0.0)
				else:
					vel.x = 0.0
				motion = _result.get_remainder().slide(n)
			else:
				pos += motion
				break
		var floor_was := on_floor
		_motion.from = Transform2D(0.0, pos)
		_motion.motion = Vector2(0, 2)
		on_floor = vel.y >= 0.0 and PhysicsServer2D.body_test_motion(p.get_rid(), _motion, _result) \
			and _result.get_collision_normal().y < -0.6
		if on_floor:
			vel.y = 0.0
		if not on_floor:
			airborne = true
		for d in _dangers:
			# Where that trap or bolt will be by then.
			if d[2] != null and is_instance_valid(d[2]) and not d[2].firing_in(i / 60.0 + [0.0, 0.1, 0.15][skill]):
				continue
			if d[0].has_point(pos - d[1] * (i / 60.0)):
				return {"pos": pos, "dead": true, "floor": on_floor, "frames": stop_at, "at": i}
		if cam and cam.has_method("is_out_of_bounds") and cam.is_out_of_bounds(pos):
			return {"pos": pos, "dead": true, "floor": false, "frames": stop_at, "at": i}
		if airborne and on_floor and not floor_was and i > 6 and i < stop_at:
			stop_at = i + 1  # landed
		i += STEP
	return {"pos": pos, "dead": false, "floor": on_floor, "frames": stop_at}


## Areas that take players out (grown by the player's size), and projectiles.
func _find_dangers(p: Node) -> Array:
	var out: Array = []
	var half := BODY / 2.0 - Vector2(6, 6)  # the hurtbox is a bit smaller than the body
	var margin: float = [-4.0, 4.0, 8.0][skill]
	for h in ctl.get_parent().find_children("*", "Area2D", true, false):
		if not h is Hazard or not h.is_inside_tree():
			continue
		# Traps that switch on and off (flamethrowers) say when they'll be on.
		var timed = h.get_parent() if h.get_parent() and h.get_parent().has_method("firing_in") else null
		if not h.monitoring and timed == null:
			continue
		for c in h.get_children():
			if c is CollisionShape2D and not c.disabled and c.shape:
				var r: Rect2 = c.global_transform * c.shape.get_rect()
				# Moving traps (saws, traps riding a wheel): where they'll be soon too.
				var now := Engine.get_physics_frames()
				var id := c.get_instance_id()
				var seen = _seen_at.get(id)
				_seen_at[id] = [r.get_center(), now]
				var v := Vector2.ZERO
				if seen and now > seen[1]:
					v = (r.get_center() - seen[0]) / ((now - seen[1]) / 60.0)
				out.append([r.grow_individual(half.x + margin, half.y + margin, half.x + margin, half.y + margin), v, timed])
		# Mines blow up around them.
		var blast = h.get_parent().get("radius") if h.get_parent() else null
		if blast is float and h.get_parent().has_method("_on_touch"):
			var c: Vector2 = h.get_parent().global_position
			out.append([Rect2(c, Vector2.ZERO).grow(blast + margin), Vector2.ZERO, null])
	for b in get_tree().get_nodes_in_group("bolts"):
		if b is Node2D:
			var v = b.get("velocity")
			out.append([Rect2(b.global_position, Vector2.ZERO).grow_individual(half.x + 24, half.y + 24, half.x + 24, half.y + 24),
				v if v is Vector2 else Vector2.ZERO, null])
	return out


# --- Distance map ------------------------------------------------------------------------------

## Distance (in cells) from every free spot of the arena to the flag, going round
## walls. Climbing costs more than walking or falling, and spots far above any
## floor cost a bit more, so routes follow the ground.
func _make_field() -> void:
	_best = INF
	_field_key = "%d:%s:%d:%d" % [ctl.get_instance_id(), str(_party().session.get("round", 0)), _phase, ctl.placed_items().size()]
	if _shared.has(_field_key):
		_field = _shared[_field_key][0]
		_origin = _shared[_field_key][1]
		return
	_field = {}
	var area: Rect2 = ctl.build_area.grow(200)
	_origin = area.position
	var w := int(area.size.x / CELL) + 1
	var h := int(area.size.y / CELL) + 1
	var shape := RectangleShape2D.new()
	shape.size = BODY - Vector2(6, 6)
	_query.shape = shape
	_query.collision_mask = Layers.WORLD | Layers.CRATES
	_query.collide_with_areas = false
	var space: PhysicsDirectSpaceState2D = ctl.get_viewport().world_2d.direct_space_state
	var cam = ctl._camera()
	var free := {}
	for y in h:
		for x in w:
			var c := Vector2i(x, y)
			var pos := _center(c)
			if cam and cam.has_method("is_out_of_bounds") and cam.is_out_of_bounds(pos):
				continue
			_query.transform = Transform2D(0.0, pos)
			if _solid(space.intersect_shape(_query, 4)):
				continue
			free[c] = true
	# How high above the floor each free cell is (0 = standing height).
	var height := {}
	for x in w:
		var above := 99
		for y in range(h - 1, -1, -1):
			var c := Vector2i(x, y)
			if not free.has(c):
				above = -1
			else:
				above += 1
				height[c] = above
	# Dijkstra from the flag (costs are small integers: bucket queue).
	var goal: Vector2 = ctl._goal.global_position
	var buckets := {0: []}
	for c in free:
		if _center(c).distance_to(goal) < 72.0:
			_field[c] = 0
			buckets[0].append(c)
	var cost := 0
	var left := buckets.size()
	while left > 0 and cost < 20000:
		var list: Array = buckets.get(cost, [])
		buckets.erase(cost)
		left = buckets.size()
		for c in list:
			if _field.get(c, INF) < cost:
				continue
			for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = c + dir
				if not free.has(n):
					continue
				# We search backwards from the flag: going "down" here is climbing for the racer.
				var step := 1
				if dir == Vector2i.DOWN:
					step = 3
				if height.get(n, 99) > 4:
					step += 2
				var nc := cost + step
				if nc < _field.get(n, INF):
					_field[n] = nc
					if not buckets.has(nc):
						buckets[nc] = []
					buckets[nc].append(n)
		left = buckets.size()
		cost += 1
	_shared = {_field_key: [_field, _origin]}


func _solid(hits: Array) -> bool:
	for hit in hits:
		var body = hit.collider
		if body is CollisionObject2D:
			var owner_id: int = body.shape_find_owner(hit.shape)
			if body.is_shape_owner_one_way_collision_enabled(owner_id):
				continue  # planks: you can jump up through them
		return true
	return false


func _center(c: Vector2i) -> Vector2:
	return _origin + (Vector2(c) + Vector2(0.5, 0.5)) * CELL


func _cell(pos: Vector2) -> Vector2i:
	return Vector2i(((pos - _origin) / CELL).floor())


## Distance to the flag from `pos` (the best of its cell and the ones around it).
func _dist(pos: Vector2) -> float:
	var c := _cell(pos)
	var best: float = _field.get(c, INF)
	if best == INF:
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				best = minf(best, _field.get(c + Vector2i(dx, dy), INF) + 1.0)
	# A little extra precision inside the cell.
	return best + (pos.distance_to(ctl._goal.global_position) / CELL) * 0.01


## The way to the flag from the start, as points (for placing traps on it).
func _route() -> Array:
	if _field_key == "":
		_make_field()
	var c := _cell(ctl.spawn_origin)
	if not _field.has(c):
		var best := INF
		for k in _field:
			var d := Vector2(k - c).length()
			if d < best:
				best = d
				c = k
	var out := []
	for i in 400:
		out.append(_center(c))
		var here: int = _field.get(c, 0)
		if here == 0:
			break
		var next := c
		for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if _field.get(c + dir, INF) < _field.get(next, INF):
				next = c + dir
		if next == c:
			break
		c = next
	return out


func _party() -> Node:
	return get_node("/root/Party")
