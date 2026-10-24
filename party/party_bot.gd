class_name PartyBot
extends Node
## A computer player for party mode. It plays with the same controls as people
## (it presses its own slot's actions), so it follows the same rules:
##   pick:  looks over the cards for a few seconds, like a person, then takes the
##          item it likes best;
##   place: moves the item to a spot, which depends on how it plays (its style):
##          traps on the route or near the flag, platforms that help, or anywhere;
##   race:  every few frames it tries a handful of moves (walk, wait, short and
##          long jumps, both ways) in a small physics simulation and keeps the one
##          that gets closest to the flag without touching a trap or falling out.
##          "Closest" comes from a distance map of the arena, so it finds its way
##          around walls instead of running into them.

enum Skill { EASY, NORMAL, HARD }
const SKILL_NAMES := ["Easy", "Normal", "Hard"]
## How a bot plays, picked at random for each party:
##   normal:  traps and helpful items, depending on the round;
##   trapper: hazards, near the flag or on the main path;
##   builder: platforms, where they help it reach the flag;
##   chaos:   bombs and odd items, anywhere.
const STYLES := ["normal", "trapper", "builder", "chaos"]
## Seconds a bot takes to pick an item, by skill.
const PICK_TIME := [Vector2(3.0, 4.5), Vector2(2.5, 3.5), Vector2(2.0, 2.5)]
## Seconds before it puts its item down (moving it there included).
const PLACE_TIME := [Vector2(2.0, 4.0), Vector2(1.5, 3.0), Vector2(1.0, 2.0)]

const CELL := 32.0
const BODY := Vector2(82, 82)  # the player's collision box (player.tscn)
const STEP := 1              # simulated frames per step
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "action_1", "action_2", "action_3"]
## How much the bot likes each item (traps first). Unknown items (mods): 2.
const LIKES := {"saw": 4.0, "crossbow": 3.5, "flamer": 3.0, "planes": 1.2, "spikes": 2.5, "mine": 2.5,
	"pendulum": 2.0, "ferris": 1.5, "slider": 1.5, "fan": 2.0, "conveyor": 1.5, "crumble": 1.5,
	"block": 1.2, "plank": 1.0, "trampoline": 1.0, "lift": 1.0, "bomb": 1.5, "nuke": 2.5,
	# Special items (and the card that gives one).
	"special": 3.0, "big_ferris": 1.5, "follower": 1.5, "sine_saw": 4.0, "h_bomb": 3.0, "bear_trap": 3.0,
	"glove": 2.0, "spitter": 2.5, "special_crate": 2.0, "magnet": 1.5, "ice_block": 1.5, "glue_pad": 2.0,
	"alt_plank": 1.2, "balloon": 1.2, "black_hole": 2.5}
const TRAPS := ["saw", "crossbow", "flamer", "spikes", "mine", "pendulum", "crumble", "fan", "conveyor",
	"sine_saw", "bear_trap", "spitter", "glue_pad", "ice_block", "magnet", "special_crate"]
## Things that help you get to the flag.
const PLATFORMS := ["block", "plank", "trampoline", "lift", "ferris", "slider", "big_ferris", "alt_plank", "balloon", "glove"]
## Odd items a "chaos" bot goes for (besides bombs).
const ODD := ["planes", "fan", "conveyor", "magnet", "balloon", "follower", "special", "special_crate", "glove", "pendulum"]

var slot := 0
var skill: int = Skill.NORMAL
var style := "normal"
var ctl: Node  # the PartyController

var _rng := RandomNumberGenerator.new()
var _held := {}            # action name -> true
var _taps := []            # [action, frames left]
var _erased := {}          # action name -> its keys (given back when the bot leaves)
# Pick / place.
var _wait := 0.0
var _want := -1
var _clock := 0.0          # seconds since the pick (or place) started
var _decide_at := 0.0      # when it picks (or places)
var _looks: Array = []     # cards it looks at before going to the one it wants
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
var _dangers: Array = []   # [Rect2 now, Vector2 velocity, trap that switches on and off or null,
                           #  track or null, how it moves: [item, host, mount] or null]
var _shooters: Array = []  # crossbows: [muzzle, bolt velocity, next shot in, interval, bolt flight time, size]
var _dangers_age := 99
var _fans: Array = []      # [Rect2, push direction, strength, max speed]
var _pads: Array = []      # trampolines: [Rect2, up direction, bounce speed]
var _flickers: Array = []  # planks that come and go: [body RID, plank]
var _seen_at := {}         # hazard shape id -> [where it was, physics frame] (to see it move)
var _best := INF
var _stuck := 0.0
var debug_log: Array = []   # filled when `debug` is on (tests)
var debug := false
var _query := PhysicsShapeQueryParameters2D.new()
var _motion := PhysicsTestMotionParameters2D.new()
var _result := PhysicsTestMotionResult2D.new()


func _init(for_slot := 0, bot_skill := Skill.NORMAL, bot_style := "normal") -> void:
	slot = for_slot
	skill = bot_skill
	style = bot_style if bot_style in STYLES else "normal"
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
		_clock = 0.0
		_want = -1
		_looks.clear()
		var span: Vector2 = (PICK_TIME if _phase == ctl.Phase.PICK else PLACE_TIME)[skill]
		_decide_at = _rng.randf_range(span.x, span.y)
		_wait = _rng.randf_range(0.4, 0.8)
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
	_clock += delta
	_wait -= delta
	if _wait > 0.0:
		return
	# A person's pace: one card at a time, now and then.
	_wait = _rng.randf_range(0.35, 0.75)
	if _want < 0 or ctl._taken(_want):
		_want = _choose_card()
		# Look at a card or two on the way (not every time).
		_looks.clear()
		for k in _rng.randi_range(0, 2):
			_looks.append(_rng.randi() % ctl.box.size())
	var n: int = ctl.box.size()
	var at: int = ctl.cursors.get(slot, 0)
	var left := _decide_at - _clock
	# Running out of time: no more looking around, straight to the card it wants.
	if left < (mini(posmod(_want - at, n), posmod(at - _want, n)) + 2) * 0.45:
		_looks.clear()
	var target: int = _want
	while not _looks.is_empty() and ctl._taken(_looks[0]):
		_looks.pop_front()
	if not _looks.is_empty():
		target = _looks[0]
	if at == target:
		if target != _want:
			_looks.pop_front()
			_wait = _rng.randf_range(0.5, 1.0)  # a look at it
			return
		if left <= 0.0:
			_tap("action_1")
		else:
			_wait = left  # then take it
		return
	var steps := mini(posmod(target - at, n), posmod(at - target, n))
	if target == _want and left < steps * 0.6:
		_wait = clampf(left / maxf(1.0, steps + 1.0), 0.12, 0.4)  # hurry
	# Shorter way round (the cursor wraps and skips taken cards).
	_tap("move_right" if posmod(target - at, n) <= posmod(at - target, n) else "move_left")


func _choose_card() -> int:
	var best := -1
	var best_score := -INF
	for i in ctl.box.size():
		if ctl._taken(i):
			continue
		var id: String = ctl.box[i]
		var like: float = _like(id)
		if _party().ITEMS.get(id, {}).get("bomb", false) and ctl.placed_items().is_empty():
			like = 0.1
		var noise: float = [2.0, 1.0, 0.4][skill]
		var score: float = like + _rng.randf() * noise
		if score > best_score:
			best_score = score
			best = i
	return best


## How much this bot wants an item, for its style.
func _like(id: String) -> float:
	var like: float = LIKES.get(id, 2.0)
	var def: Dictionary = _party().ITEMS.get(id, {})
	match style:
		"trapper":
			like *= 1.7 if id in TRAPS else 0.5
			if id == "follower" and not ctl.placed_items().is_empty():
				like = 3.0  # traps can ride it
		"builder":
			like *= 2.0 if id in PLATFORMS else 0.5
		"chaos":
			like *= 2.2 if def.get("bomb", false) or id in ODD else 0.8
	return like


func _place(delta: float) -> void:
	var g = ctl.ghosts.get(slot)
	if g == null or not is_instance_valid(g):
		return
	var id: String = g.get_meta("item_id")
	_clock += delta
	_target_time += delta
	if _target == Vector2.INF or _target_time > 4.0:
		_target = _choose_spot(id)
		_target_time = 0.0
		if _flip_for(id) != ctl.mirrors.get(slot, false):
			_tap("action_3")
	var to: Vector2 = _target - ctl.cursor[slot]
	var close: float = ctl.ghost_speed * delta * 1.5
	_hold("move_right", to.x > close)
	_hold("move_left", to.x < -close)
	_hold("move_down", to.y > close)
	_hold("move_up", to.y < -close)
	if absf(to.x) <= close and absf(to.y) <= close and _clock >= _decide_at:
		_wait -= delta
		if _wait <= 0.0:
			_wait = pace()
			if ctl.can_place(id, g.global_position, ctl.turns.get(slot, 0)):
				_tap("action_1")
				_target = Vector2.INF
			else:
				_target_time = 99.0  # somewhere else


## Mirrored or not: a punching glove launches towards the flag for a builder,
## back towards the start for the others. Anything else: either way.
func _flip_for(id: String) -> bool:
	if id == "glove":
		var flag_right: bool = ctl.goal_zone.get_center().x > ctl.start_zone.get_center().x
		return not flag_right if style == "builder" else flag_right
	return _rng.randf() < 0.5


## Where to put an item: traps on the route, near the ground; bombs on others' items.
## Trappers go near the flag, builders fill gaps on the way, chaos bots go anywhere.
func _choose_spot(id: String) -> Vector2:
	var def: Dictionary = _party().ITEMS.get(id, {})
	var turn: int = ctl.turns.get(slot, 0)
	if def.get("bomb", false):
		var others: Array = ctl.placed_items().filter(func(it): return it.get_meta("owner_slot", 0) != slot)
		if not others.is_empty():
			return others[_rng.randi() % others.size()].global_position
	# A trap hanging from a free attachment point (a follower takes it to the racers).
	if style == "trapper" and id in TRAPS and ctl.can_attach(id) and _rng.randf() < 0.6:
		var mounts: Array = ctl.free_mounts()
		if not mounts.is_empty():
			return mounts[_rng.randi() % mounts.size()].global_position
	var route := _route()
	var size: Vector2 = def.get("size", Vector2(64, 64))
	var offset: Vector2 = def.get("offset", Vector2.ZERO)
	var span := Vector2(0.3, 0.92)
	match style:
		"trapper":
			span = Vector2(0.65, 0.97)
		"builder":
			span = Vector2(0.2, 0.85)
	if style == "builder" and id in PLATFORMS and not route.is_empty():
		var gap := _gap_on(route)
		if gap != Vector2.INF and ctl.can_place(id, gap, turn):
			return gap
	var best := Vector2.INF
	var best_score := -1.0
	var tried := 0
	for attempt in 60:
		var pos: Vector2
		if style == "chaos" and attempt < 20:
			var area: Rect2 = ctl.build_area
			pos = Vector2(_rng.randf_range(area.position.x, area.end.x), _rng.randf_range(area.position.y, area.end.y))
		elif not route.is_empty() and attempt < 50:
			var k := int(route.size() * _rng.randf_range(span.x, span.y))
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
			# Traps: better bots try more spots and keep the one that covers most
			# of the way the racers go.
			if not id in TRAPS or route.is_empty() or skill == Skill.EASY:
				return pos
			var score := _coverage(id, pos, turn, route) + _rng.randf() * 0.5
			if score > best_score:
				best_score = score
				best = pos
			tried += 1
			if tried >= [1, 6, 24][skill]:
				break
	return best if best != Vector2.INF else ctl.cursor[slot]


## How much of the route a trap at `pos` sits on (route points inside its
## footprint, a little grown: the robot's body is big).
func _coverage(id: String, pos: Vector2, turn: int, route: Array) -> float:
	var r: Rect2 = ctl._footprint(id, pos, turn).grow(36)
	var n := 0.0
	for p in route:
		if r.has_point(p):
			n += 1.0
	return n


## Builders: a spot on the way with nothing to stand on below (a gap to fill),
## just under where the route goes.
func _gap_on(route: Array) -> Vector2:
	var picks := []
	for k in range(int(route.size() * 0.15), int(route.size() * 0.9)):
		var p: Vector2 = route[k]
		var fy := _floor_below(p)
		if fy == INF or fy - p.y > 220.0:
			picks.append(p + Vector2(0, 70))
	return picks[_rng.randi() % picks.size()] if not picks.is_empty() else Vector2.INF


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
	if p.has_method("has_status") and p.has_status("stuck"):
		_release_all()  # caught: nothing to do but wait
		_plan.clear()
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
	var long := [6, 12, 24, 40]
	# A jump needs a fresh press: let go for a frame first if the key is still down.
	var now := 1 if _held.has("p%d_action_1" % slot) else 0
	if p.is_on_floor() or p.coyote_timer > 0.0:
		for dir in [-1, 0, 1]:
			out.append(_inputs(dir, 0, 0, 30))
		for dir in [-1, 1]:
			for hold in long:
				out.append(_inputs(dir, now, hold, 56))
			out.append(_inputs(dir, 8, 24, 60))  # run up, then jump
			# High jump, then stop moving sideways (land short, before a trap).
			for stop in [12, 22]:
				out.append(_inputs(dir, now, 40, 56, stop))
			# Straight up first, then sideways (hop onto a ledge right above).
			out.append(_inputs(0, now, 40, 56, -1, 14, dir))
		out.append(_inputs(0, now, 24, 46))      # straight up
	else:
		var rising: bool = p.velocity.y < 0.0
		for dir in [-1, 0, 1]:
			out.append(_inputs(dir, 0, 40 if rising else 0, 46))
			if rising:
				out.append(_inputs(dir, 0, 0, 46))  # let go: drop sooner
	return out


## Per-frame keys: `dir` sideways, jump held from `jump_after` for `hold` frames.
## `stop`: sideways keys let go from that frame. `turn_at`/`then`: switch to
## direction `then` from that frame.
func _inputs(dir: int, jump_after: int, hold: int, frames: int, stop := -1, turn_at := -1, then := 0) -> Array:
	var steps := []
	for f in frames:
		var jump := hold > 0 and f >= jump_after and f < jump_after + hold
		var d := dir
		if stop >= 0 and f >= stop:
			d = 0
		if turn_at >= 0 and f >= turn_at:
			d = then
		steps.append([d, jump])
	return steps


func _make_plan(p: Node) -> void:
	if _dangers_age > 6:
		_dangers = _find_dangers(p)
		_find_pushers()
		_dangers_age = 0
	else:
		_refresh_dangers()
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
	if sim.get("crumble", false):
		score += 2.0  # don't stop on a crumbling block
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
	var floor_vel := Vector2.ZERO
	var on_crumble := false
	var on_flicker: Node = null  # the plank that comes and goes we're standing on
	var gone: Array[RID] = []   # planks gone at this moment of the plan
	_motion.exclude_bodies = gone
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
		# Fans blow, trampolines launch (as fan.gd and trampoline.gd do).
		for f in _fans:
			if f[0].has_point(pos):
				var along: float = vel.dot(f[1])
				if along < f[3]:
					vel += f[1] * minf(f[2] * dt, f[3] - along)
		for t in _pads:
			if t[0].has_point(pos) and vel.dot(t[1]) <= 10.0:
				var v: Vector2 = t[1] * t[2]
				if absf(t[1].y) > 0.3:
					vel.y = v.y
				vel.x += v.x
				jumping = false
				on_floor = false
		# Planks that come and go: not there when they'll be gone.
		if not _flickers.is_empty():
			var now: Array[RID] = []
			for f in _flickers:
				if is_instance_valid(f[1]) and not f[1].solid_in(i / 60.0 + [0.25, 0.15, 0.1][skill]):
					now.append(f[0])
			if now != gone:
				gone = now
				_motion.exclude_bodies = gone
		# Move and slide (twice: along a wall or the floor after a hit). Standing
		# on a conveyor or a moving plane carries us along.
		var motion := vel * dt + floor_vel * dt
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
		floor_vel = Vector2.ZERO
		if on_floor:
			vel.y = 0.0
			var under = _result.get_collider()
			if under is StaticBody2D:
				floor_vel = under.constant_linear_velocity
			if under != null and "delay" in under and "_broken" in under:
				on_crumble = true  # it'll give way
			on_flicker = under.get_parent() if under != null and under.get_parent().has_method("solid_in") else null
		if not on_floor:
			airborne = true
		for d in _dangers:
			# Where that trap or bolt will be by then.
			if d[2] != null and is_instance_valid(d[2]):
				# On and off traps (flamethrowers): out if it's on at any time close to then.
				var t := i / 60.0
				var lag: float = [0.0, 0.1, 0.15][skill]
				if not (d[2].firing_in(t) or d[2].firing_in(t + lag) or d[2].firing_in(maxf(0.0, t - lag))):
					continue
			if _moved(d, i / 60.0).has_point(pos):
				return {"pos": pos, "dead": true, "floor": on_floor, "frames": stop_at, "at": i}
		# Bolts crossbows haven't shot yet.
		for s in _shooters:
			var t := i / 60.0
			for k in 3:
				var since: float = t - (s[2] + k * s[3])
				if since < 0.0:
					break
				if since <= s[4] and Rect2(s[0] + s[1] * since, Vector2.ZERO).grow_individual(s[5].x, s[5].y, s[5].x, s[5].y).has_point(pos):
					return {"pos": pos, "dead": true, "floor": on_floor, "frames": stop_at, "at": i}
		if cam and cam.has_method("is_out_of_bounds") and cam.is_out_of_bounds(pos):
			return {"pos": pos, "dead": true, "floor": false, "frames": stop_at, "at": i}
		if airborne and on_floor and not floor_was and i > 6 and i < stop_at:
			stop_at = i + 1  # landed
		i += STEP
	_motion.exclude_bodies = [] as Array[RID]
	# Ending up on a plank that's about to go: like a crumbling block, not a place to stop.
	if on_floor and on_flicker != null and is_instance_valid(on_flicker) and not on_flicker.solid_in(i / 60.0 + 0.9):
		on_crumble = true
	return {"pos": pos, "dead": false, "floor": on_floor, "frames": stop_at, "crumble": on_crumble and on_floor}


## Traps where they are now (the list is only made again every few plans; the
## predictions start from now).
func _refresh_dangers() -> void:
	for d in _dangers:
		if d.size() > 6 and is_instance_valid(d[5]) and d[5].is_inside_tree() and d[5].shape:
			var g: Vector2 = d[6]
			d[0] = (d[5].global_transform * d[5].shape.get_rect()).grow_individual(g.x, g.y, g.x, g.y)
	for s in _shooters:
		s[2] -= (Engine.get_physics_frames() - int(s[6])) / 60.0
		s[6] = Engine.get_physics_frames()


## Where a danger will be `t` seconds from now (bouncing back and forth on its track).
func _moved(d: Array, t: float) -> Rect2:
	var r: Rect2 = d[0]
	if d.size() > 4 and d[4] != null:
		# A trap that can say where it'll be (saws, things on a pendulum or a wheel).
		var off := Vector2.ZERO
		var how: Array = d[4]
		if how[0] != null and is_instance_valid(how[0]):
			off += how[0].moved_by(t)
		if how[1] != null and is_instance_valid(how[1]) and is_instance_valid(how[2]):
			off += how[1].mount_moved_by(how[2], t)
		return Rect2(r.position + off, r.size)
	var v: Vector2 = d[1]
	if v == Vector2.ZERO:
		return r
	var c := r.get_center() + v * t
	if d[3] != null:
		var track: Rect2 = d[3]
		var lo := track.position + r.size / 2.0
		var hi := track.end - r.size / 2.0
		c = Vector2(_bounce(c.x, lo.x, hi.x), _bounce(c.y, lo.y, hi.y))
	return Rect2(c - r.size / 2.0, r.size)


## Folds `x` back into [lo, hi] like something bouncing between two walls.
static func _bounce(x: float, lo: float, hi: float) -> float:
	if hi <= lo:
		return (lo + hi) / 2.0
	var span := hi - lo
	var k := fposmod(x - lo, span * 2.0)
	return lo + (k if k <= span else span * 2.0 - k)


## The party item a node belongs to (the ancestor with a placement record).
func _item_of(n: Node) -> Node:
	while n != null and n != ctl:
		if n.has_meta("record"):
			return n
		n = n.get_parent()
	return null


## Fans and trampolines, to know where we'd be pushed.
func _find_pushers() -> void:
	_fans.clear()
	_pads.clear()
	_flickers.clear()
	for n in ctl.get_parent().find_children("*", "Node2D", true, false):
		if n.has_method("solid_in") and n.has_method("body_rid"):
			_flickers.append([n.body_rid(), n])
		elif n is Trampoline and n.has_node("Pad"):
			for c in n.get_node("Pad").get_children():
				if c is CollisionShape2D and c.shape:
					_pads.append([c.global_transform * c.shape.get_rect(), Vector2.UP.rotated(n.global_rotation), n.bounce_speed])
		elif "max_up_speed" in n and n.has_node("Column"):
			var up: Vector2 = -n.global_transform.y.normalized()
			for c in n.get_node("Column").get_children():
				if c is CollisionShape2D and c.shape:
					_fans.append([c.global_transform * c.shape.get_rect(), up, n.strength, n.max_up_speed])


## Areas that take players out (grown by the player's size), and projectiles.
func _find_dangers(p: Node) -> Array:
	var out: Array = []
	var half := BODY / 2.0 - Vector2(6, 6)  # the hurtbox is a bit smaller than the body
	var margin: float = [-4.0, 4.0, 8.0][skill]
	for h in ctl.get_parent().find_children("*", "Area2D", true, false):
		# Traps that take you out, and the ones best avoided (bear traps, spit).
		var avoid: bool = h is StatusArea and h.avoid
		if not (h is Hazard or avoid) or not h.is_inside_tree():
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
				# A trap going back and forth (a saw on its rail) stays on its track.
				var track = null
				var item := _item_of(h)
				if item and v != Vector2.ZERO and not item.get_meta("record", {}).has("host"):
					var rec: Dictionary = item.get_meta("record")
					track = ctl._footprint(rec.id, Vector2(rec.x, rec.y), int(rec.get("rot", 0)))
				# Better: traps that can say where they'll be.
				var how = null
				if item:
					var mover = item if item.has_method("moved_by") else null
					var mount = item.get_parent() if item.get_parent() is ItemMount else null
					var host = mount.get_parent() if mount and mount.get_parent().has_method("mount_moved_by") else null
					if mover or host:
						how = [mover, host, mount]
				out.append([r.grow_individual(half.x + margin, half.y + margin, half.x + margin, half.y + margin), v, timed,
					track.grow_individual(half.x + margin, half.y + margin, half.x + margin, half.y + margin) if track else null, how,
					c, half + Vector2(margin, margin)])
		# Mines: touching the trigger is out (that's the hazard above). The blast
		# only matters when someone else is close enough to set it off.
		var blast = h.get_parent().get("radius") if h.get_parent() else null
		if blast is float and h.get_parent().has_method("_on_touch") and h.monitoring:
			var c: Vector2 = h.get_parent().global_position
			var others := false
			for o in ctl.players.values():
				if is_instance_valid(o) and o != p and not o.get_meta("eliminated", false) and not o.get_meta("finished", false) \
						and o.global_position.distance_to(c) < blast + 120.0:
					others = true
			if others:
				out.append([Rect2(c, Vector2.ZERO).grow(blast + margin), Vector2.ZERO, null, null])
	# Crossbows: the bolts they're going to shoot.
	_shooters.clear()
	for n in ctl.get_parent().find_children("*", "Node2D", true, false):
		if n.has_method("next_shot") and n.has_method("bolt_end") and n.has_meta("record"):
			var from: Vector2 = n.muzzle()
			var flight: float = from.distance_to(n.bolt_end()) / n.bolt_speed
			_shooters.append([from, n.forward() * n.bolt_speed, n.next_shot(), n.interval, flight,
				half + Vector2(15 + margin, 4 + margin), Engine.get_physics_frames()])
	for b in get_tree().get_nodes_in_group("bolts"):
		if b is Node2D:
			var v = b.get("velocity")
			out.append([Rect2(b.global_position, Vector2.ZERO).grow_individual(half.x + 24, half.y + 24, half.x + 24, half.y + 24),
				v if v is Vector2 else Vector2.ZERO, null, null])
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
