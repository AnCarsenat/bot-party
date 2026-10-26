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
## Extra cost of a cell on (or next to) a trap, for finding the way: a few cells
## of detour are better than going past a trap.
const TRAP_COST := 4
## Frames a bot looks ahead at the spot where a move ends: a trap coming
## through there soon makes it a bad place to stop.
const REST_LOOK := 45
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
## Its character for the whole party (Party.bot_traits): aggro (traps for the
## others), care (makes the way easier), greed (coins), spite (gets back at whoever got it).
var traits := {}
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
# The arena as a grid of cells, flat arrays (index y * _w + x): fast to go through.
var _w := 0
var _h := 0
var _field := PackedInt32Array()      # distance to the flag, in steps (FAR: can't get there)
var _free := PackedByteArray()        # 1: a robot fits in that cell
var _height := PackedInt32Array()     # how high above the floor
var _trap_cost := PackedInt32Array()  # extra cost (near traps)
var _coin_field := PackedInt32Array() # distance to the coin
var _coin_for := Vector2.INF
var _coin_to_flag := 0.0
var _coin_mood := true     # does it fancy the coin this time
# What happened last round, and what it means to do about it.
var _mood := ""            # "help": make it easier (it didn't make it), "attack": make it harder, "": its usual
var _target_slot := 0      # who it's after when attacking
var _smart_tries := 0      # spots tried for that this placing
var _watch_paths := {}     # (first bot, during the race) slot -> where each player went
var _watch_out := {}       # slot -> where they went out
var _going_coin := false
var _coin_check := 0
var _field_key := ""       # which arena layout it was made for
var _origin := Vector2.ZERO
var _phase := -1
## Distance maps shared by all bots: {key: [field, origin]} (only the latest is kept).
static var _shared := {}
static var _shared_coin := {}
static var _base := {}  # arena -> cells free of the arena itself (items left out): scanned once  # field key + coin cell -> distance to the coin (one for all bots)
const FAR := 1 << 30
var _plan: Array = []      # per frame: [dir, jump held]
var _commit := 0
var _dangers: Array = []   # [Rect2 now, Vector2 velocity, trap that switches on and off or null,
						   #  track or null, how it moves: [item, host, mount] or null]
var _shooters: Array = []  # crossbows: [muzzle, bolt velocity, next shot in, interval, bolt flight time, size]
var _dangers_age := 99
var _reach: Array[Rect2] = []  # per danger: everywhere it can be while a plan runs
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

## Planning is the costly part: all bots together get this much per physics frame
## (a bot that still has moves left waits a frame rather than make the game stutter).
const PLAN_BUDGET_USEC := 16000
static var _budget_frame := -1
static var _budget_used := 0


## A character for a new bot: its style leans it one way, the rest is chance.
static func roll_traits(for_style: String) -> Dictionary:
	var lean: float = {"trapper": 0.8, "builder": 0.25, "chaos": 0.6}.get(for_style, 0.5)
	var aggro := clampf(lean + randf_range(-0.2, 0.2), 0.0, 1.0)
	return {"aggro": snappedf(aggro, 0.01), "care": snappedf(clampf(1.0 - aggro + randf_range(-0.2, 0.2), 0.0, 1.0), 0.01),
		"greed": snappedf(randf_range(0.2, 1.0), 0.01), "spite": snappedf(randf(), 0.01)}


func _init(for_slot := 0, bot_skill := Skill.NORMAL, bot_style := "normal") -> void:
	slot = for_slot
	_coin_check = 3 + slot * 3  # not all bots on the same frame
	skill = bot_skill
	style = bot_style if bot_style in STYLES else "normal"
	name = "Bot%d" % slot
	# Before the controller and the players: a press is seen the same frame.
	process_priority = -100
	process_physics_priority = -100


func _ready() -> void:
	_rng.randomize()
	if traits.is_empty():
		traits = _party().bot_traits(slot)
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
		if _phase == ctl.Phase.RUN and slot == _first_bot():
			_write_notes()
		_phase = ctl.phase
		if _phase == ctl.Phase.PICK:
			_decide_mood()
		elif _phase == ctl.Phase.COUNTDOWN:
			_watch_paths.clear()
			_watch_out.clear()
		_field_key = ""  # items were placed: the arena changed
		_plan.clear()
		_clock = 0.0
		_want = -1
		_looks.clear()
		_smart_tries = 0
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


## Like a person: ranks the cards it can take by how much it likes them, then
## picks one at random, the higher ranked ones more likely (each rank is
## RANK_ODDS times as likely as the one above it: Hard bots stick to their
## favourite more, Easy ones less).
const RANK_ODDS := [0.75, 0.6, 0.45]


func _choose_card() -> int:
	var ranked := []
	for i in ctl.box.size():
		if ctl._taken(i):
			continue
		var id: String = ctl.box[i]
		var like: float = _like(id)
		if _party().ITEMS.get(id, {}).get("bomb", false) and ctl.placed_items().is_empty():
			like = 0.1
		ranked.append([like + _rng.randf() * 0.3, i])
	if ranked.is_empty():
		return -1
	ranked.sort_custom(func(a, b): return a[0] > b[0])
	var odds: float = RANK_ODDS[skill]
	var total := 0.0
	for k in ranked.size():
		total += pow(odds, k)
	var roll := _rng.randf() * total
	for k in ranked.size():
		roll -= pow(odds, k)
		if roll <= 0.0:
			return ranked[k][1]
	return ranked[0][1]


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
	# What last round calls for.
	match _mood:
		"help":
			if _helps(id):
				like *= 2.0 + float(traits.care) * 2.0
			elif _traps(id):
				like *= 0.5
			if def.get("bomb", false) and _my_trap() != null:
				like *= 2.5  # blow up what got it
		"attack":
			if _traps(id):
				like *= 1.5 + float(traits.aggro)
			elif _helps(id):
				like *= 0.6
			if def.get("bomb", false) and _help_on(_target_path()) != null:
				like *= 1.8  # take away what helps the one it's after
	return like


func _traps(id: String) -> bool:
	return id in TRAPS or _party().ITEMS.get(id, {}).get("kind", "") == "trap"


func _helps(id: String) -> bool:
	return id in PLATFORMS or _party().ITEMS.get(id, {}).get("kind", "") == "help"


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
	# (Not over and over: if it can't be put there, the usual way.)
	_smart_tries += 1
	var smart := _smart_spot(id, def, turn) if _smart_tries <= 2 else Vector2.INF
	if smart != Vector2.INF:
		return smart
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
			if _traps(id) or _rng.randf() < 0.6:
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
			if not _traps(id) or route.is_empty() or skill == Skill.EASY:
				return pos
			var score := _coverage(id, pos, turn, route) + _rng.randf() * 0.5
			if score > best_score:
				best_score = score
				best = pos
			tried += 1
			if tried >= [1, 6, 24][skill]:
				break
	return best if best != Vector2.INF else ctl.cursor[slot]


# --- Strategy (from what happened last round) ---------------------------------------------

## The first bot watches the race: where everyone goes, where they go out.
func _watch() -> void:
	var frame := Engine.get_physics_frames()
	for s in ctl.players:
		var p = ctl.players[s]
		if not is_instance_valid(p) or _watch_out.has(s) or p.get_meta("finished", false):
			continue
		if p.get_meta("eliminated", false):
			var path: PackedVector2Array = _watch_paths.get(s, PackedVector2Array())
			# Where it went out (falling off the bottom: where it was last seen).
			var at: Vector2 = p.global_position
			if not path.is_empty() and at.distance_to(path[-1]) > 400.0:
				at = path[-1]
			_watch_out[s] = at
		elif frame % 12 == 0:
			if not _watch_paths.has(s):
				_watch_paths[s] = PackedVector2Array()
			if _watch_paths[s].size() < 400:
				_watch_paths[s].append(p.global_position)


## Kept in the party (and the save) for every bot to think about.
func _write_notes() -> void:
	var paths := {}
	for s in _watch_paths:
		var flat := []
		for v in _watch_paths[s]:
			flat.append(roundf(v.x))
			flat.append(roundf(v.y))
		paths[str(s)] = flat
	var outs := {}
	for s in _watch_out:
		var by := 0
		for k in ctl.kills:
			if int(k[0]) == int(s):
				by = int(k[1])
		outs[str(s)] = [roundf(_watch_out[s].x), roundf(_watch_out[s].y), by]
	_party().session.bot_notes = {"round": int(_party().session.get("round", 0)),
		"finished": ctl.finished.map(func(x): return int(x)), "players": ctl.slots.size(),
		"outs": outs, "paths": paths}


## Last round's notes, if they're about the round just played.
func _notes() -> Dictionary:
	var n: Dictionary = _party().session.get("bot_notes", {})
	if n.is_empty() or int(n.get("round", -1)) != int(_party().session.get("round", 0)):
		return {}
	return n


## After a round: make it easier if it didn't make it (or nobody did), harder
## if everybody did, and go after whoever is about to win (or got it).
func _decide_mood() -> void:
	_mood = ""
	_target_slot = 0
	var n := _notes()
	if n.is_empty() or _rng.randf() > [0.45, 0.8, 1.0][skill]:
		return  # round one, or an easy bot not thinking it through
	var fin: Array = n.get("finished", []).map(func(x): return int(x))
	var made := slot in fin
	var aggro: float = traits.get("aggro", 0.5)
	var care: float = traits.get("care", 0.5)
	if fin.is_empty():
		_mood = "help"
	elif fin.size() >= int(n.get("players", 0)):
		_mood = "attack"
	elif not made:
		_mood = "help" if _rng.randf() < 0.35 + care * 0.6 else "attack"
	elif _rng.randf() < 0.3 + aggro * 0.6:
		_mood = "attack"
	# Whoever leads (someone close to winning: stop them).
	var leader := 0
	var lead := 0
	for s in ctl.slots:
		if s != slot and _party().score(s) > lead:
			lead = _party().score(s)
			leader = s
	if leader != 0 and lead >= _party().target_score() - _party().POINTS_FINISH - _party().POINTS_FIRST and _mood != "help":
		_mood = "attack"
	if _mood == "attack":
		_target_slot = leader
	# Spiteful bots go after whoever got them.
	var out = n.get("outs", {}).get(str(slot))
	if out != null and int(out[2]) != 0 and int(out[2]) != slot and _rng.randf() < float(traits.get("spite", 0.5)):
		_target_slot = int(out[2])
		if _mood == "":
			_mood = "attack"
	if _mood == "attack" and _target_slot == 0:
		_target_slot = fin[_rng.randi() % fin.size()] if not fin.is_empty() else 0


func _path_of(s: int) -> Array:
	var flat: Array = _notes().get("paths", {}).get(str(s), [])
	var out := []
	for i in range(0, flat.size() - 1, 2):
		out.append(Vector2(flat[i], flat[i + 1]))
	return out


## Where the one it's after went (or everyone who made it).
func _target_path() -> Array:
	var path := _path_of(_target_slot) if _target_slot != 0 else []
	if path.is_empty():
		for s in _notes().get("finished", []):
			if int(s) != slot:
				path += _path_of(int(s))
	return path


## The trap that got it last round (still there), or null.
func _my_trap() -> Node:
	var out = _notes().get("outs", {}).get(str(slot))
	if out == null:
		return null
	return _item_near(Vector2(out[0], out[1]), true, 220.0)


func _item_near(at: Vector2, trap: bool, within: float) -> Node:
	var best: Node = null
	for it in ctl.placed_items():
		if not is_instance_valid(it):
			continue
		var id: String = it.get_meta("record", {}).get("id", "")
		if (_traps(id) if trap else _helps(id)) and it.global_position.distance_to(at) < within:
			within = it.global_position.distance_to(at)
			best = it
	return best


## Someone else's helpful item on `path` (the one it helps most), or null.
func _help_on(path: Array) -> Node:
	if path.is_empty():
		return null
	var best: Node = null
	var most := 0.0
	for it in ctl.placed_items():
		if not is_instance_valid(it) or it.get_meta("owner_slot", 0) == slot:
			continue
		var rec: Dictionary = it.get_meta("record", {})
		if not _helps(rec.get("id", "")):
			continue
		var n := _coverage(rec.id, it.global_position, int(rec.get("rot", 0)), path)
		if n > most:
			most = n
			best = it
	return best


## A spot chosen for what happened last round, or Vector2.INF (then the usual way).
func _smart_spot(id: String, def: Dictionary, turn: int) -> Vector2:
	if _mood == "" or _notes().is_empty():
		return Vector2.INF
	if _mood == "help":
		var trap := _my_trap()
		if def.get("bomb", false):
			return trap.global_position if trap else Vector2.INF
		if _traps(id):
			return _out_of_the_way(id, turn)  # nobody needs it harder now
		if not _helps(id):
			return Vector2.INF
		var anchors := []
		var mine := _path_of(slot)
		var out = _notes().get("outs", {}).get(str(slot))
		if trap:
			# Caught by a trap: a way over it.
			for dx in [0.0, -90.0, 90.0]:
				anchors.append(trap.global_position + Vector2(dx, -150))
		elif not mine.is_empty():
			# Fell (or got stuck): from the last place it stood, the ledge made
			# longer towards the flag, then a step up.
			var ahead := signf(ctl._goal.global_position.x - mine[-1].x)
			var top: float = def.get("size", Vector2(64, 64)).y / 2.0 - def.get("offset", Vector2.ZERO).y
			for k in range(mine.size() - 1, -1, -1):
				var fy := _floor_below(mine[k])
				if fy != INF and fy - mine[k].y < 160.0:  # over the ground (standing, or a hop)
					if out == null:
						anchors.append(mine[k] + Vector2(ahead * 40.0, -110))  # stuck: a step up
					anchors.append(Vector2(mine[k].x + ahead * 110.0, fy + top))
					anchors.append(Vector2(mine[k].x + ahead * 230.0, fy + top))
					break
		if anchors.is_empty() and out != null:
			anchors.append(Vector2(out[0], out[1]) + Vector2(0, -60))
		for a in anchors:
			for r in [0.0, 40.0, 80.0, 130.0]:
				for k in (1 if r == 0.0 else 8):
					var pos: Vector2 = a + Vector2(r, 0).rotated(k * TAU / 8.0)
					if ctl.can_place(id, pos, turn):
						return pos
		return Vector2.INF
	# Attack: on the way the one it's after went.
	var path := _target_path()
	if path.size() < 4:
		return Vector2.INF
	if def.get("bomb", false):
		var it := _help_on(path)
		return it.global_position if it else Vector2.INF
	if not _traps(id):
		return Vector2.INF
	var mine := _path_of(slot)
	var size: Vector2 = def.get("size", Vector2(64, 64))
	var offset: Vector2 = def.get("offset", Vector2.ZERO)
	var best := Vector2.INF
	var best_score := 0.0
	var tries := 0
	for attempt in 80:
		var pos: Vector2 = path[int(path.size() * _rng.randf_range(0.1, 0.97))]
		var fy := _floor_below(pos)
		if fy != INF and fy - pos.y < 260.0:
			pos.y = fy - size.y / 2.0 - offset.y
		if not ctl.can_place(id, pos, turn):
			continue
		# Right where they went; less so where it goes itself.
		var score := _coverage(id, pos, turn, path) - 0.4 * _coverage(id, pos, turn, mine) + _rng.randf() * 0.5
		if score > best_score:
			best_score = score
			best = pos
		tries += 1
		if tries >= [3, 10, 24][skill]:
			break
	return best


## A trap somewhere nobody went last round (when nobody needs it harder).
func _out_of_the_way(id: String, turn: int) -> Vector2:
	var all := []
	for s in _notes().get("paths", {}):
		all += _path_of(int(s))
	var area: Rect2 = ctl.build_area
	var best := Vector2.INF
	var least := INF
	for attempt in 40:
		var pos := Vector2(_rng.randf_range(area.position.x, area.end.x), _rng.randf_range(area.position.y, area.end.y))
		if not ctl.can_place(id, pos, turn):
			continue
		var n := _coverage(id, pos, turn, all)
		if n < least:
			least = n
			best = pos
			if n == 0.0:
				break
	return best


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
	if not is_instance_valid(ctl):
		return
	if ctl.phase == ctl.Phase.COUNTDOWN and _field_key == "" and slot == _first_bot():
		_make_field()  # ready before the race (the others share it)
	if ctl.phase != ctl.Phase.RUN:
		return
	if slot == _first_bot():
		_watch()
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
	_coin_check -= 1
	if _coin_check <= 0:
		_coin_check = 20
		_think_coin(p)
	var d := _dist(p.global_position)
	if d < _best - 0.5:
		_best = d
		_stuck = 0.0
	else:
		_stuck += 1.0 / 60.0
	_commit -= 1
	if _plan.is_empty() or _commit <= 0:
		var frame := Engine.get_physics_frames()
		if _budget_frame != frame:
			_budget_frame = frame
			_budget_used = 0
		if _plan.is_empty() or _budget_used < PLAN_BUDGET_USEC or _commit < -2:
			var t0 := Time.get_ticks_usec()
			_make_plan(p)
			_budget_used += Time.get_ticks_usec() - t0
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
		# Short steps, then stop: to get to the edge before a jump.
		for dir in [-1, 1]:
			for steps in [5, 12]:
				out.append(_inputs(dir, 0, 0, steps))
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
	_find_reach()
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
	if sim.get("coin", false):
		d = _field_at(_field, sim.pos, ctl._goal.global_position) - 2.0  # got it: on to the flag
	if d == INF:
		return 1e8
	var score := d
	if not sim.floor:
		score += 1.5
	if sim.get("crumble", false):
		score += 2.0  # don't stop on a crumbling block
	# Stopping where a trap is about to sweep through: a dead end (the sooner, the worse).
	score += sim.get("threat", 0.0) * 30.0
	# Through a bear trap or spit: only if there's no other way (it costs time, not the round).
	if sim.get("soft", false):
		score += 40.0
	if plan[0][1] or plan[mini(10, plan.size() - 1)][1]:
		score += 0.3  # don't jump for nothing
	return score


## A small copy of the player's movement (player.gd), run ahead with test moves.
func _simulate(p: Node, plan: Array) -> Dictionary:
	if _reach.size() != _dangers.size():
		_find_reach()
	var pos: Vector2 = p.global_position
	var vel: Vector2 = p.velocity
	var on_floor: bool = p.is_on_floor()
	# Start from the robot's real state: a jump key already held isn't a new press.
	var jumping: bool = p._jumping
	var was_held: bool = _held.has("p%d_action_1" % slot)
	var coyote: float = p.coyote_timer
	var dt := STEP / 60.0
	var cam = ctl._camera()
	if cam and not cam.has_method("is_out_of_bounds"):
		cam = null
	# The player's numbers, read once (reading them off the node every step is slow).
	var gravity: float = p.gravity
	var fall_mult: float = p.fall_gravity_multiplier
	var max_fall: float = p.max_fall_speed
	var coyote_time: float = p.coyote_time
	var jump_speed: float = p.jump_speed
	var jump_cut: float = p.jump_cut
	var ground_accel: float = p.ground_accel
	var air_accel: float = p.air_accel
	var run_speed: float = p.speed
	var wind: float = p.wind_vx
	var rid: RID = p.get_rid()
	var flicker_lead: float = [0.25, 0.15, 0.1][skill]
	var lag: float = [0.0, 0.1, 0.15][skill]
	var airborne := false
	var floor_vel := Vector2.ZERO
	var on_crumble := false
	var on_flicker: Node = null  # the plank that comes and goes we're standing on
	var soft := false  # went through something best avoided (bear trap, spit)
	var got_coin := false  # passed through the coin it's going for
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
			var g: float = gravity * (fall_mult if vel.y > 0.0 else 1.0)
			vel.y = minf(vel.y + g * dt, max_fall)
			coyote -= dt
		else:
			coyote = coyote_time
			jumping = false
		if pressed and coyote > 0.0:
			vel.y = jump_speed
			coyote = 0.0
			jumping = true
			on_floor = false
		if jumping and vel.y < 0.0 and not held:
			vel.y *= jump_cut
			jumping = false
		var accel: float = ground_accel if on_floor else air_accel
		vel.x = move_toward(vel.x, dir * run_speed + wind, accel * dt)
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
				if is_instance_valid(f[1]) and not f[1].solid_in(i / 60.0 + flicker_lead):
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
			if PhysicsServer2D.body_test_motion(rid, _motion, _result):
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
		on_floor = vel.y >= 0.0 and PhysicsServer2D.body_test_motion(rid, _motion, _result) \
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
		if _going_coin and not got_coin and pos.distance_to(_coin_for) < 64.0:
			got_coin = true
		for di in _dangers.size():
			if not _reach[di].has_point(pos):
				continue  # nowhere near anything it can do while the plan runs
			var d: Array = _dangers[di]
			# Where that trap or bolt will be by then.
			if d[2] != null and is_instance_valid(d[2]):
				# On and off traps (flamethrowers): out if it's on at any time close to then.
				var t := i / 60.0
				if not (d[2].firing_in(t) or d[2].firing_in(t + lag) or d[2].firing_in(maxf(0.0, t - lag))):
					continue
			if _moved(d, i / 60.0).has_point(pos):
				if d.size() > 7 and d[7]:
					soft = true  # a bear trap or spit: best avoided, but not the end
					continue
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
		if cam and cam.is_out_of_bounds(pos):
			return {"pos": pos, "dead": true, "floor": false, "frames": stop_at, "at": i}
		if airborne and on_floor and not floor_was and i > 6 and i < stop_at:
			stop_at = i + 1  # landed
		i += STEP
	_motion.exclude_bodies = [] as Array[RID]
	# Standing where we stop: does a trap come through soon?
	var threat := 0.0
	if on_floor:
		for j in range(0, REST_LOOK, 3):
			var t := (i + j) / 60.0
			for di in _dangers.size():
				if not _reach[di].has_point(pos):
					continue
				var d: Array = _dangers[di]
				if d[2] != null and is_instance_valid(d[2]) and not d[2].firing_in(t):
					continue
				if _moved(d, t).has_point(pos):
					threat = 1.0 - float(j) / REST_LOOK
					break
			if threat > 0.0:
				break
	# Ending up on a plank that's about to go: like a crumbling block, not a place to stop.
	if on_floor and on_flicker != null and is_instance_valid(on_flicker) and not on_flicker.solid_in(i / 60.0 + 0.9):
		on_crumble = true
	return {"pos": pos, "dead": false, "floor": on_floor, "frames": stop_at, "crumble": on_crumble and on_floor, "threat": threat, "soft": soft, "coin": got_coin}


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


## Everywhere each danger can be in the next few seconds (as long as a plan and
## its look ahead), so the simulation skips the ones far away at a glance.
const REACH_TIME := 3.6
func _find_reach() -> void:
	_reach.resize(_dangers.size())
	for di in _dangers.size():
		var d: Array = _dangers[di]
		var r: Rect2 = d[0]
		if d.size() > 4 and d[4] != null:
			var t := 0.0
			while t <= REACH_TIME:
				r = r.merge(_moved(d, t))
				t += 0.05
			r = r.grow(12.0)  # between the looks
		elif d[1] != Vector2.ZERO:
			if d[3] != null:
				r = r.merge(d[3])
			else:
				r = r.merge(Rect2(r.position + d[1] * REACH_TIME, r.size))
		_reach[di] = r


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
					c, half + Vector2(margin, margin), avoid])
		# Mines: touching the trigger is out (that's the hazard above). The blast
		# only matters when someone else is about to touch it (right next to it
		# and coming closer).
		var blast = h.get_parent().get("radius") if h.get_parent() else null
		if blast is float and h.get_parent().has_method("_on_touch") and h.monitoring:
			var c: Vector2 = h.get_parent().global_position
			var others := false
			for o in ctl.players.values():
				if is_instance_valid(o) and o != p and not o.get_meta("eliminated", false) and not o.get_meta("finished", false):
					var to: Vector2 = c - o.global_position
					var soon: Vector2 = o.global_position + o.velocity * 0.25
					if to.length() < 70.0 or soon.distance_to(c) < 60.0:
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
	_field_key = _layout_key()
	_coin_field = PackedInt32Array()
	if _shared.has(_field_key):
		var sh: Array = _shared[_field_key]
		_field = sh[0]
		_origin = sh[1]
		_free = sh[2]
		_height = sh[3]
		_trap_cost = sh[4]
		_w = sh[5]
		_h = sh[6]
		return
	var area: Rect2 = ctl.build_area.grow(200)
	_origin = area.position
	var w := int(area.size.x / CELL) + 1
	var h := int(area.size.y / CELL) + 1
	_w = w
	_h = h
	var shape := RectangleShape2D.new()
	shape.size = BODY - Vector2(6, 6)
	_query.shape = shape
	_query.collision_mask = Layers.WORLD | Layers.CRATES
	_query.collide_with_areas = false
	var space: PhysicsDirectSpaceState2D = ctl.get_viewport().world_2d.direct_space_state
	var cam = ctl._camera()
	var bounds: bool = cam != null and cam.has_method("is_out_of_bounds")
	# The arena itself doesn't change: scanned once, then only the cells round the
	# items are looked at again.
	var base_key := "%d:%s" % [ctl.get_instance_id(), area]
	if not _base.has(base_key):
		var base := PackedByteArray()
		base.resize(w * h)
		for y in h:
			for x in w:
				var pos := _center(Vector2i(x, y))
				if bounds and cam.is_out_of_bounds(pos):
					continue
				_query.transform = Transform2D(0.0, pos)
				if _solid(space.intersect_shape(_query, 8), true):
					continue
				base[y * w + x] = 1
		_base = {base_key: base}
	var free: PackedByteArray = _base[base_key].duplicate()
	var movers: Array = ctl.placed_items()
	for n in ctl.get_parent().find_children("*", "CollisionObject2D", true, false):
		if n.collision_layer & Layers.CRATES and _item_of(n) == null:
			movers.append(n)
	for item in movers:
		if not is_instance_valid(item):
			continue
		var r := _item_rect(item).grow(BODY.x)
		var a := _cell(r.position)
		var b := _cell(r.end)
		for y in range(maxi(a.y, 0), mini(b.y + 1, h)):
			for x in range(maxi(a.x, 0), mini(b.x + 1, w)):
				if free[y * w + x] == 0:
					continue
				_query.transform = Transform2D(0.0, _center(Vector2i(x, y)))
				if _solid(space.intersect_shape(_query, 4)):
					free[y * w + x] = 0
	# How high above the floor each free cell is (0 = standing height).
	var height := PackedInt32Array()
	height.resize(w * h)
	for x in w:
		var above := 99
		for y in range(h - 1, -1, -1):
			if free[y * w + x] == 0:
				above = -1
			else:
				above += 1
				height[y * w + x] = above
	_free = free
	_height = height
	_trap_cost = _trap_cells()
	_field = _dijkstra(ctl._goal.global_position)
	_shared = {_field_key: [_field, _origin, _free, _height, _trap_cost, _w, _h]}
	_shared_coin.clear()


## Where an item is solid now (its spot, and its bodies wherever they've got to).
func _item_rect(item: Node) -> Rect2:
	var rec: Dictionary = item.get_meta("record", {})
	var r := Rect2(item.global_position, Vector2.ZERO).grow(64.0)
	if _party().ITEMS.has(rec.get("id", "")):
		r = r.merge(ctl._footprint(rec.id, item.global_position, int(rec.get("rot", 0))))
	for c in item.find_children("*", "CollisionShape2D", true, false):
		if c.shape and c.get_parent() is CollisionObject2D and not (c.get_parent() is Area2D):
			r = r.merge(c.global_transform * c.shape.get_rect())
	return r


## What the grid depends on: the round and where the items are.
func _layout_key() -> String:
	var items: Array = ctl.placed_items()
	var sum := Vector2.ZERO
	for it in items:
		if is_instance_valid(it):
			sum += (it.global_position / 8.0).round()
	return "%d:%s:%d:%s" % [ctl.get_instance_id(), str(_party().session.get("round", 0)), items.size(), sum]


## Extra cost of going through each cell: on a trap's spot, or along its track.
## So bots take a way round traps when there's one.
func _trap_cells() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(_w * _h)
	var party := _party()
	for item in ctl.placed_items():
		var rec: Dictionary = item.get_meta("record", {})
		if party.ITEMS.get(rec.get("id", ""), {}).get("kind", "") != "trap":
			continue
		var r: Rect2 = ctl._footprint(rec.id, item.global_position, int(rec.get("rot", 0))).grow(BODY.x * 0.5)
		var a := _cell(r.position)
		var b := _cell(r.end)
		for y in range(maxi(a.y, 0), mini(b.y + 1, _h)):
			for x in range(maxi(a.x, 0), mini(b.x + 1, _w)):
				out[y * _w + x] += TRAP_COST
	return out


## Distance (in steps) from every free cell to `goal`, round walls (Dijkstra,
## from the goal; costs are small integers: bucket queue).
func _dijkstra(goal: Vector2) -> PackedInt32Array:
	var w := _w
	var n_cells := _w * _h
	var field := PackedInt32Array()
	field.resize(n_cells)
	field.fill(FAR)
	var buckets := {}
	var first := PackedInt32Array()
	var gc := _cell(goal)
	for y in range(maxi(gc.y - 3, 0), mini(gc.y + 4, _h)):
		for x in range(maxi(gc.x - 3, 0), mini(gc.x + 4, _w)):
			var i := y * w + x
			if _free[i] == 1 and _center(Vector2i(x, y)).distance_to(goal) < 72.0:
				field[i] = 0
				first.append(i)
	buckets[0] = first
	var cost := 0
	while not buckets.is_empty() and cost < 20000:
		if buckets.has(cost):
			var list: PackedInt32Array = buckets[cost]
			buckets.erase(cost)
			for i in list:
				if field[i] < cost:
					continue
				var x := i % w
				# We search backwards from the goal: going "down" here is climbing for the racer.
				for k in 4:
					var n := i
					var step := 1
					if k == 0:
						if x == 0: continue
						n = i - 1
					elif k == 1:
						if x == w - 1: continue
						n = i + 1
					elif k == 2:
						n = i - w
						if n < 0: continue
					else:
						n = i + w
						if n >= n_cells: continue
						step = 3
					if _free[n] == 0:
						continue
					if _height[n] > 4:
						step += 2
					var nc := cost + step + _trap_cost[n]
					if nc < field[n]:
						field[n] = nc
						if buckets.has(nc):
							var b: PackedInt32Array = buckets[nc]
							b.append(n)
							buckets[nc] = b
						else:
							buckets[nc] = PackedInt32Array([n])
		cost += 1
	return field


## A grid value at a cell (FAR outside the grid or where it can't be reached).
func _grid(arr: PackedInt32Array, c: Vector2i) -> float:
	if c.x < 0 or c.y < 0 or c.x >= _w or c.y >= _h or arr.is_empty():
		return INF
	var v := arr[c.y * _w + c.x]
	return INF if v >= FAR else float(v)


func _solid(hits: Array, arena_only := false) -> bool:
	for hit in hits:
		var body = hit.collider
		if arena_only and body is Node and (_item_of(body) != null or (body is CollisionObject2D and body.collision_layer & Layers.CRATES)):
			continue  # an item or a crate (they move): looked at separately
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


## How far `pos` still is: to the flag, or (going for the coin) to the coin and
## then on to the flag.
func _dist(pos: Vector2) -> float:
	if _going_coin and not _coin_field.is_empty():
		return _field_at(_coin_field, pos, _coin_for) + _coin_to_flag
	return _field_at(_field, pos, ctl._goal.global_position)


## A distance map's value at `pos` (the best of its cell and the ones around it).
func _field_at(field: PackedInt32Array, pos: Vector2, goal: Vector2) -> float:
	var c := _cell(pos)
	var best: float = _grid(field, c)
	if best == INF:
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				best = minf(best, _grid(field, c + Vector2i(dx, dy)) + 1.0)
	# A little extra precision inside the cell.
	return best + (pos.distance_to(goal) / CELL) * 0.01


## Is the coin worth a detour (even going back for it)? Looked at now and then
## during the race: the extra way it costs, against how much the bot wants it.
func _think_coin(p: Node) -> void:
	var coin = ctl._coin if is_instance_valid(ctl._coin) else null
	var want := false
	if coin and coin.visible and coin.get("carrier") == null and not p.get_meta("coin", false):
		var at: Vector2 = coin.global_position
		if _coin_field.is_empty() or _coin_for.distance_to(at) > 40.0:
			var key := "%s|%s" % [_field_key, _cell(at)]
			if not _shared_coin.has(key):
				_shared_coin[key] = _dijkstra(at)
			_coin_field = _shared_coin[key]
			_coin_for = at
			# Greedy bots nearly always go for it, others now and then.
			_coin_mood = _rng.randf() < float(traits.get("greed", 0.6)) * [0.8, 1.0, 1.1][skill]
		_coin_to_flag = _field_at(_field, at, ctl._goal.global_position)
		var direct := _field_at(_field, p.global_position, ctl._goal.global_position)
		var detour := _field_at(_coin_field, p.global_position, at) + _coin_to_flag - direct
		var limit: float = [10.0, 18.0, 28.0][skill] * (0.6 + float(traits.get("greed", 0.6)))
		if _going_coin and _stuck > 3.0:
			_coin_mood = false  # can't get to it: forget it
		want = _coin_mood and detour < limit
	if want != _going_coin:
		_going_coin = want
		_best = INF  # a new goal: what counts as progress changes
		_stuck = 0.0
		_plan.clear()


## The way to the flag from the start, as points (for placing traps on it).
func _route() -> Array:
	if _field_key == "":
		_make_field()
	var c := _cell(ctl.spawn_origin)
	if _grid(_field, c) == INF:
		var best := INF
		for i in _field.size():
			if _field[i] < FAR:
				var k := Vector2i(i % _w, i / _w)
				var d := Vector2(k - c).length()
				if d < best:
					best = d
					c = k
	var out := []
	for i in 400:
		out.append(_center(c))
		var here := _grid(_field, c)
		if here == 0 or here == INF:
			break
		var next := c
		for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if _grid(_field, c + dir) < _grid(_field, next):
				next = c + dir
		if next == c:
			break
		c = next
	return out


## The lowest slot that's a bot (it does the shared work).
func _first_bot() -> int:
	var low := slot
	for b in get_parent().get_children():
		if b != self and "slot" in b and b.get_script() == get_script():
			low = mini(low, b.slot)
	return low


func _party() -> Node:
	return get_node("/root/Party")
