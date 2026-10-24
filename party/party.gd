extends Node
## Autoload "Party": the party-mode session (scores, placed obstacles) and its save file.
## The session is saved after every placement and every round, so a party can be
## continued from the main menu, or after "Restart level" in the pause menu.

const TARGET_SCORE := 50  # default "First to" score (see rules)
## Party rules (Party > Rules). Each party keeps the rules it started with.
const RULE_DEFAULTS := {"target": 50, "round_time": 0, "coins": true, "surprises": true, "equal_odds": false, "mode": "classic", "specials": 1}
## Chance that a card in the box is a Special crate, for the "specials" rule (off, rare, often).
const SPECIAL_ODDS := [0.0, 0.04, 0.12]
const SPECIAL_NAMES := ["Off", "Rare", "Often"]
var rules := RULE_DEFAULTS.duplicate()
const SAVE_PATH := "user://party_session.json"
## Arenas a party can be played in (one is picked at random for each new party).
const ARENAS := ["res://party/party_arena.tscn", "res://party/party_arena_2.tscn",
	"res://party/party_arena_3.tscn", "res://party/party_arena_4.tscn"]
const ARENA_NAMES := ["Steps", "Pillar", "Windy heights", "Meteor field"]
const POINTS_COIN := 5
const POINTS_FINISH := 10
const POINTS_FIRST := 5
const POINTS_TRAP := 2

## Everything a player can pick. size/offset describe the item's footprint
## (used to stop building in the start and goal areas). weight: how often it
## shows up in the box by default (players can change it in Party > Items).
## kind: "help" (gets you to the flag), "trap" or "bomb". Every box has at least
## one helpful item and one trap.
const BUILT_IN_ITEMS := {
	"block": {"name": "Block", "scene": "res://party/items/block.tscn", "icon": "res://party/art/block.webp", "size": Vector2(64, 64), "weight": 8, "kind": "help"},
	"plank": {"name": "Plank", "scene": "res://objects/platform.tscn", "icon": "res://objects/toggle_platform_enabled.webp", "size": Vector2(192, 30), "props": {"size": Vector2(192, 30), "one_way": true}, "weight": 9, "kind": "help"},
	"spikes": {"name": "Spikes", "scene": "res://party/items/spikes.tscn", "icon": "res://party/art/spikes.webp", "size": Vector2(64, 28), "weight": 9, "kind": "trap"},
	"saw": {"name": "Saw", "scene": "res://party/items/saw.tscn", "icon": "res://party/art/saw.webp", "size": Vector2(240, 64), "weight": 9, "kind": "trap"},
	"trampoline": {"name": "Trampoline", "scene": "res://objects/trampoline.tscn", "icon": "res://objects/trampoline.webp", "size": Vector2(80, 40), "offset": Vector2(0, -20), "weight": 8, "kind": "help"},
	"crossbow": {"name": "Crossbow", "scene": "res://party/items/crossbow.tscn", "icon": "res://party/art/crossbow.webp", "size": Vector2(64, 64), "weight": 8, "kind": "trap"},
	"planes": {"name": "Plane launcher", "scene": "res://party/items/plane_launcher.tscn", "icon": "res://party/art/plane_launcher.webp", "size": Vector2(64, 56), "offset": Vector2(0, 4), "weight": 5, "kind": "help"},
	"crumble": {"name": "Crumbling block", "scene": "res://party/items/crumble.tscn", "icon": "res://party/art/crumble.webp", "size": Vector2(96, 28), "weight": 6, "kind": "trap"},
	"conveyor": {"name": "Conveyor", "scene": "res://party/items/conveyor.tscn", "icon": "res://party/art/conveyor.webp", "size": Vector2(96, 28), "weight": 6, "kind": "help"},
	"mine": {"name": "Mine", "scene": "res://party/items/mine.tscn", "icon": "res://party/art/landmine.webp", "size": Vector2(64, 24), "weight": 7, "kind": "trap"},
	"fan": {"name": "Fan", "scene": "res://party/items/fan.tscn", "icon": "res://party/art/fan.webp", "size": Vector2(64, 270), "offset": Vector2(0, -120), "weight": 5, "kind": "help"},
	"lift": {"name": "Lift", "scene": "res://objects/platform.tscn", "icon": "res://party/art/lift.webp", "size": Vector2(128, 250), "offset": Vector2(0, -110),
		"props": {"size": Vector2(128, 24), "move_offset": Vector2(0, -220), "move_time": 1.6, "pause_time": 0.4}, "weight": 6, "kind": "help"},
	"ferris": {"name": "Ferris wheel", "host": true, "scene": "res://party/items/ferris.tscn", "icon": "res://party/art/ferris.webp", "size": Vector2(360, 380), "offset": Vector2(0, 28), "weight": 4, "kind": "help"},
	"slider": {"name": "Slider", "scene": "res://party/items/slider.tscn", "icon": "res://party/art/slider.webp", "size": Vector2(220, 40), "host": true, "weight": 5, "kind": "help"},
	"pendulum": {"name": "Pendulum", "host": true, "scene": "res://party/items/pendulum.tscn", "icon": "res://party/art/pendulum.webp", "size": Vector2(350, 220), "offset": Vector2(0, 95), "weight": 6, "kind": "trap"},
	"flamer": {"name": "Flamethrower", "scene": "res://party/items/flamer.tscn", "icon": "res://party/art/flamer.webp", "size": Vector2(64, 236), "offset": Vector2(0, -86), "weight": 6, "kind": "trap"},
	"bomb": {"name": "Bomb", "bomb": true, "radius": 130.0, "icon": "res://party/art/bomb.webp", "size": Vector2(64, 64), "weight": 5, "kind": "bomb"},
	"nuke": {"name": "Nuke", "bomb": true, "radius": 260.0, "icon": "res://party/art/nuke.webp", "size": Vector2(64, 64), "weight": 2, "kind": "bomb"},
	# Special items: never in the box themselves. A Special crate card (rare) gives
	# one of them, picked with these weights.
	"big_ferris": {"name": "Big ferris wheel", "special": true, "host": true, "scene": "res://party/items/ferris.tscn", "icon": "res://party/art/big_ferris.webp",
		"props": {"radius": 240.0, "gondolas": 9, "spin": 0.32}, "size": Vector2(540, 580), "offset": Vector2(0, 30), "weight": 4, "kind": "help"},
	"follower": {"name": "Follower", "special": true, "host": true, "scene": "res://party/items/follower.tscn", "icon": "res://party/art/follower.webp", "size": Vector2(64, 80), "offset": Vector2(0, 4), "weight": 5, "kind": "help"},
	"sine_saw": {"name": "Sine saw", "special": true, "scene": "res://party/items/sine_saw.tscn", "icon": "res://party/art/sine_saw.webp", "size": Vector2(404, 196), "weight": 7, "kind": "trap"},
	"h_bomb": {"name": "Hydrogen bomb", "special": true, "bomb": true, "radius": 450.0, "icon": "res://party/art/h_bomb.webp", "size": Vector2(64, 64), "weight": 3, "kind": "bomb"},
	"bear_trap": {"name": "Bear trap", "special": true, "scene": "res://party/items/bear_trap.tscn", "icon": "res://party/art/bear_trap.webp", "size": Vector2(64, 44), "offset": Vector2(0, 6), "weight": 8, "kind": "trap"},
	"glove": {"name": "Punching glove", "special": true, "scene": "res://party/items/glove.tscn", "icon": "res://party/art/glove.webp", "size": Vector2(64, 64), "weight": 7, "kind": "help"},
	"spitter": {"name": "Spitter", "special": true, "scene": "res://party/items/spitter.tscn", "icon": "res://party/art/spitter.webp", "size": Vector2(64, 236), "offset": Vector2(0, -86), "weight": 6, "kind": "trap"},
	"special_crate": {"name": "Special crate", "special": true, "scene": "res://party/items/special_crate.tscn", "icon": "res://party/art/special_crate.webp", "size": Vector2(64, 64), "weight": 4, "kind": "trap"},
	"magnet": {"name": "Magnet", "special": true, "scene": "res://party/items/magnet.tscn", "icon": "res://party/art/magnet.webp", "size": Vector2(64, 64), "weight": 6, "kind": "trap"},
	"ice_block": {"name": "Ice block", "special": true, "scene": "res://party/items/ice_block.tscn", "icon": "res://party/art/ice_block.webp", "size": Vector2(64, 64), "weight": 7, "kind": "trap"},
	"glue_pad": {"name": "Glue pad", "special": true, "scene": "res://party/items/glue_pad.tscn", "icon": "res://party/art/glue_pad.webp", "size": Vector2(64, 36), "offset": Vector2(0, 12), "weight": 7, "kind": "trap"},
	"alt_plank": {"name": "Alternating plank", "special": true, "scene": "res://party/items/alt_plank.tscn", "icon": "res://party/art/alt_plank.webp", "size": Vector2(192, 30), "weight": 7, "kind": "help"},
	"balloon": {"name": "Balloon", "special": true, "scene": "res://party/items/balloon.tscn", "icon": "res://party/art/balloon.webp", "size": Vector2(48, 64), "weight": 6, "kind": "help"},
	"black_hole": {"name": "Black hole", "special": true, "bomb": true, "black_hole": true, "radius": 340.0, "icon": "res://party/art/black_hole.webp", "size": Vector2(64, 64), "weight": 3, "kind": "bomb"},
	# The card itself: turns into a special item when it's picked.
	"special": {"name": "Special crate", "card": true, "icon": "res://party/art/special_crate.webp", "size": Vector2(64, 64), "weight": 0},
}
## Built-in items plus the ones from enabled mods (see reload_items).
var ITEMS: Dictionary = BUILT_IN_ITEMS.duplicate(true)
const MAX_WEIGHT := 20
const ITEMS_PATH := "user://party_items.cfg"

## Surprise rules for some rounds.
const MODIFIERS := {
	"Low gravity": {"gravity": 0.55},
	"Speedy": {"speed": 1.4},
	"Moon jump": {"jump_speed": 1.25, "gravity": 0.8},
}

var session: Dictionary = {}
## Item id -> weight chosen in Party > Items (0 = never shows up).
var weights := {}


func _ready() -> void:
	reload_items()
	GameState.joined_changed.connect(_on_joined_changed)


## Items from mods come and go with their on/off switch.
func reload_items() -> void:
	ITEMS = BUILT_IN_ITEMS.duplicate(true)
	var mods := get_node_or_null("/root/Mods")
	if mods:
		ITEMS.merge(mods.items())
	load_weights()


## An item's picture (mods can bring their own).
func icon(id: String) -> Texture2D:
	var def: Dictionary = ITEMS.get(id, {})
	if def.has("icon_texture"):
		return def.icon_texture
	return load(def.get("icon", "res://party/art/block.webp"))


# --- Item odds -------------------------------------------------------------------

func weight(id: String) -> int:
	return int(weights.get(id, ITEMS[id].get("weight", 10)))


func set_weight(id: String, value: int) -> void:
	weights[id] = clampi(value, 0, MAX_WEIGHT)
	save_weights()


func reset_weights() -> void:
	weights.clear()
	save_weights()


func is_special(id: String) -> bool:
	return ITEMS.get(id, {}).get("special", false)


## Items listed in Party > Items (not the Special crate card).
func listed_items() -> Array:
	return ITEMS.keys().filter(func(k): return not ITEMS[k].get("card", false))


## Share this item gets, 0..1 (what the Items screen shows as a %): of the box for
## the usual items, of the Special crate for special ones.
func chance(id: String) -> float:
	var total := 0
	for k in listed_items():
		if is_special(k) == is_special(id):
			total += weight(k)
	return float(weight(id)) / total if total > 0 else 0.0


## Random item id for the box, following the weights. `skip` ids are left out.
## Special items are never picked here (see pick_special).
func pick_item(rng: RandomNumberGenerator, skip: Array = []) -> String:
	return _pick(rng, listed_items().filter(func(k): return not is_special(k) and not k in skip))


## Random special item (what a Special crate card gives), or "" if they're all off.
func pick_special(rng: RandomNumberGenerator) -> String:
	var out := _pick(rng, listed_items().filter(func(k): return is_special(k)), "")
	return out


## Chance that a card in the box is a Special crate (Party > Rules > Specials).
func special_odds() -> float:
	return SPECIAL_ODDS[clampi(int(rule("specials")), 0, 2)]


func _pick(rng: RandomNumberGenerator, ids: Array, fallback := "block") -> String:
	var total := 0
	for k in ids:
		total += _odds(k)
	if total <= 0:
		return fallback
	var roll := rng.randi_range(1, total)
	for k in ids:
		roll -= _odds(k)
		if roll <= 0:
			return k
	return fallback


## How likely an item is in the box: its weight, or the same for every item that's
## on when the "Equal odds" rule is on.
func _odds(id: String) -> int:
	if rule("equal_odds"):
		return 1 if weight(id) > 0 else 0
	return weight(id)


## Game modes: "classic", plus the ones from enabled mods ({id: {name, description, script}}).
func modes() -> Dictionary:
	var out := {"classic": {"name": "Classic", "description": PartyMode.new().description}}
	var mods := get_node_or_null("/root/Mods")
	if mods:
		out.merge(mods.modes())
	return out


## The mode with this id (Classic if it's unknown, e.g. its mod was turned off).
func make_mode(id: String) -> PartyMode:
	var def: Dictionary = modes().get(id, {})
	if def.has("script"):
		var script = load(def.script)
		if script is Script:
			var m = script.new()
			if m is PartyMode:
				return m
	return PartyMode.new()


## A rule of the party being played (or of the next one, between parties).
func rule(name: String):
	return session.get("rules", rules).get(name, RULE_DEFAULTS[name])


func target_score() -> int:
	return int(rule("target"))


func save_weights() -> void:
	var cfg := ConfigFile.new()
	for k in weights:
		cfg.set_value("weights", k, weights[k])
	cfg.set_value("party", "arena", arena_choice)
	var list := {}
	for b in bot_list:
		list[str(b)] = bot_list[b]
	cfg.set_value("party", "bot_list", list)
	for k in rules:
		cfg.set_value("rules", k, rules[k])
	cfg.save(ITEMS_PATH)


func load_weights() -> void:
	weights.clear()
	var cfg := ConfigFile.new()
	if cfg.load(ITEMS_PATH) == OK:
		arena_choice = str(cfg.get_value("party", "arena", "random"))
		bot_list.clear()
		var list = cfg.get_value("party", "bot_list", {}) if cfg.has_section_key("party", "bot_list") else null
		if list is Dictionary:
			for k in list:
				if str(k).is_valid_int() and int(k) >= 1 and int(k) <= GameState.MAX_PLAYERS:
					bot_list[int(k)] = clampi(int(list[k]), 0, 2)
		else:  # older settings: a number of bots, all as good
			_fill_bots(int(cfg.get_value("party", "bots", 0)), int(cfg.get_value("party", "bot_skill", 1)))
		for k in RULE_DEFAULTS:
			rules[k] = type_convert(cfg.get_value("rules", k, RULE_DEFAULTS[k]), typeof(RULE_DEFAULTS[k]))
	if cfg.load(ITEMS_PATH) == OK and cfg.has_section("weights"):
		for k in cfg.get_section_keys("weights"):
			if ITEMS.has(k):
				weights[k] = clampi(int(cfg.get_value("weights", k)), 0, MAX_WEIGHT)


## Which arena new parties use: "random", a built-in arena path, or "map:<file>".
var arena_choice := "random"
## Computer players added to new parties (offline only): slot -> skill (PartyBot.Skill).
## A person joining a bot's slot moves the bot to a free one.
var bot_list := {}
## Set while testing a map from the editor: going back to the menu returns there.
var return_to_editor := false


func new_session(players: Array, choice := "") -> void:
	var scores := {}
	for s in players:
		scores[str(s)] = 0
	session = {"round": 1, "scores": scores, "players": players.duplicate(), "items": [], "rules": rules.duplicate(),
		"arena": ARENAS[randi() % ARENAS.size()]}
	# Bots, in their own slots. Each gets a way of playing for this party.
	var bots := {}
	var styles := {}
	if not get_node("/root/Net").is_online():
		for s in bot_slots():
			if not s in session.players and session.players.size() < GameState.MAX_PLAYERS:
				session.players.append(s)
				session.scores[str(s)] = 0
				bots[str(s)] = bot_list[s]
				styles[str(s)] = PartyBot.STYLES[randi() % PartyBot.STYLES.size()]
		session.players.sort()
	session.bots = bots
	session.bot_styles = styles
	if choice == "":
		choice = arena_choice
	if choice.begins_with("map:"):
		var m := ArenaMap.load_file(choice.trim_prefix("map:"))
		if not m.is_empty():
			use_map(m)
	elif choice in ARENAS:
		session.arena = choice


## The party is played on a map from the editor.
func use_map(m: Dictionary) -> void:
	session.arena = ArenaMap.SCENE
	session.map = m
	# Items that come with the map are there from the start (anyone's to blow up).
	session.items = []
	var uid := 1
	for it in m.get("items", []):
		if ITEMS.has(it.id) and not ITEMS[it.id].get("bomb", false):
			session.items.append({"id": it.id, "x": float(it.x), "y": float(it.y), "owner": 0,
				"rot": int(it.get("rot", 0)), "mirror": bool(it.get("mirror", false)), "uid": uid})
			uid += 1
	session.next_uid = uid


## Arena choices for the menu: [{id, name}].
func arena_options() -> Array:
	var out := [{"id": "random", "name": "Random"}]
	for i in ARENAS.size():
		out.append({"id": ARENAS[i], "name": ARENA_NAMES[i]})
	for m in ArenaMap.list_all():
		out.append({"id": "map:" + m.path, "name": m.name + ("  (mod)" if m.mod else "")})
	return out


func arena_choice_name() -> String:
	for o in arena_options():
		if o.id == arena_choice:
			return o.name
	arena_choice = "random"
	return "Random"


## Plays a map straight from the editor (comes back to the editor afterwards).
func test_map(m: Dictionary) -> void:
	new_session(GameState.joined, "random")
	use_map(m)
	session["editing"] = true  # not saved: "Continue" keeps your real party
	return_to_editor = true
	get_tree().root.get_node("Transition").change_scene(ArenaMap.SCENE, m.name, 0.8)


func new_game() -> void:
	new_session(GameState.joined)
	save()
	get_tree().root.get_node("Transition").change_scene(arena(), "Party time", 1.0)


func continue_game() -> void:
	if not load_save():
		new_game()
		return
	var slots: Array[int] = []
	for s in session.players:
		slots.append(int(s))
	GameState.joined = slots
	get_tree().root.get_node("Transition").change_scene(arena(), "Round %d" % session.round, 1.0)


func end_game(message: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	session = {}
	GameState.go_to_menu(message)


func arena() -> String:
	return session.get("arena", ARENAS[0])


func score(slot: int) -> int:
	return int(session.scores.get(str(slot), 0))


# --- Bots --------------------------------------------------------------------------

func bot_slots() -> Array:
	var out := bot_list.keys()
	out.sort()
	return out


## Adds a bot (in `slot`, or the first free slot). Returns its slot, or 0 if full.
func add_bot(skill := 1, slot := 0) -> int:
	if slot == 0:
		slot = _free_slot()
	if slot < 1 or slot > GameState.MAX_PLAYERS or GameState.is_joined(slot) or bot_list.has(slot):
		return 0
	bot_list[slot] = clampi(skill, 0, 2)
	save_weights()
	return slot


func remove_bot(slot: int) -> void:
	if bot_list.erase(slot):
		save_weights()


func set_bot_skill(slot: int, skill: int) -> void:
	if bot_list.has(slot):
		bot_list[slot] = posmod(skill, 3)
		save_weights()


## `count` bots, all as good (console, command line).
func set_bots(count: int, skill: int) -> void:
	_fill_bots(count, skill)
	save_weights()


func _fill_bots(count: int, skill: int) -> void:
	bot_list.clear()
	for k in clampi(count, 0, GameState.MAX_PLAYERS - 1):
		var s := _free_slot()
		if s == 0:
			break
		bot_list[s] = clampi(skill, 0, 2)


func _free_slot() -> int:
	for s in range(1, GameState.MAX_PLAYERS + 1):
		if not GameState.is_joined(s) and not bot_list.has(s):
			return s
	return 0


## A person took a bot's slot: the bot moves to a free one (or goes if there's none).
func _on_joined_changed() -> void:
	var moved := false
	for s in bot_slots():
		if GameState.is_joined(s):
			var skill: int = bot_list[s]
			bot_list.erase(s)
			var to := _free_slot()
			if to != 0:
				bot_list[to] = skill
			moved = true
	if moved:
		save_weights()


## "P3" for a person, "B1", "B2"... for the bots (numbered in slot order).
## In a party, its own bots; in the menus, the bots set up for the next party.
func label(slot: int) -> String:
	var list: Array
	if session.has("bots"):
		list = session.bots.keys().map(func(k): return int(k))
	else:
		list = bot_list.keys()
	list.sort()
	var i := list.find(slot)
	return ("B%d" % (i + 1)) if i >= 0 else ("P%d" % slot)


## How this party's bot in `slot` plays (one of PartyBot.STYLES).
func bot_style(slot: int) -> String:
	return str(session.get("bot_styles", {}).get(str(slot), "normal"))


## Slot -> skill of the computer players in this party.
func bots() -> Dictionary:
	var out := {}
	for k in session.get("bots", {}):
		out[int(k)] = int(session.bots[k])
	return out


func players() -> Array[int]:
	var out: Array[int] = []
	for s in session.get("players", []):
		out.append(int(s))
	return out


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func describe_save() -> String:
	var data = _read()
	if data == null:
		return ""
	var parts := []
	for s in data.players:
		var bots: Array = data.get("bots", {}).keys().map(func(k): return int(k))
		bots.sort()
		var n := bots.find(int(s))
		parts.append("%s: %d" % [("B%d" % (n + 1)) if n >= 0 else ("P%d" % int(s)), int(data.scores.get(str(int(s)), 0))])
	return "Round %d   -   %d obstacles placed\n%s" % [int(data.round), data.items.size(), "   ".join(parts)]


func save() -> void:
	if NetCheck.client(self) or session.get("editing", false):
		return  # online: the host keeps the party / testing a map: keep the real save
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(session, "  "))


func load_save() -> bool:
	var data = _read()
	if data == null:
		return false
	session = data
	session.round = int(session.round)
	# Items from a mod that's been turned off since are left out.
	session.items = session.get("items", []).filter(func(r): return r is Dictionary and ITEMS.has(str(r.get("id", ""))))
	return true


func _read():
	if not has_save():
		return null
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or not data.has("players"):
		return null
	return data
