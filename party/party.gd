extends Node
## Autoload "Party": the party-mode session (scores, placed obstacles) and its save file.
## The session is saved after every placement and every round, so a party can be
## continued from the main menu, or after "Restart level" in the pause menu.

const TARGET_SCORE := 50
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
const BUILT_IN_ITEMS := {
	"block": {"name": "Block", "scene": "res://party/items/block.tscn", "icon": "res://party/art/block.webp", "size": Vector2(64, 64), "weight": 10},
	"plank": {"name": "Plank", "scene": "res://objects/platform.tscn", "icon": "res://objects/toggle_platform_enabled.webp", "size": Vector2(192, 30), "props": {"size": Vector2(192, 30), "one_way": true}, "weight": 10},
	"spikes": {"name": "Spikes", "scene": "res://party/items/spikes.tscn", "icon": "res://party/art/spikes.webp", "size": Vector2(64, 28), "weight": 10},
	"saw": {"name": "Saw", "scene": "res://party/items/saw.tscn", "icon": "res://party/art/saw.webp", "size": Vector2(240, 64), "weight": 10},
	"trampoline": {"name": "Trampoline", "scene": "res://objects/trampoline.tscn", "icon": "res://objects/trampoline.webp", "size": Vector2(80, 40), "offset": Vector2(0, -20), "weight": 10},
	"crossbow": {"name": "Crossbow", "scene": "res://party/items/crossbow.tscn", "icon": "res://party/art/crossbow.webp", "size": Vector2(64, 64), "weight": 10},
	"planes": {"name": "Plane launcher", "scene": "res://party/items/plane_launcher.tscn", "icon": "res://party/art/plane_launcher.webp", "size": Vector2(64, 56), "offset": Vector2(0, 4), "weight": 7},
	"crumble": {"name": "Crumbling block", "scene": "res://party/items/crumble.tscn", "icon": "res://party/art/crumble.webp", "size": Vector2(96, 28), "weight": 8},
	"conveyor": {"name": "Conveyor", "scene": "res://party/items/conveyor.tscn", "icon": "res://party/art/conveyor.webp", "size": Vector2(96, 28), "weight": 8},
	"mine": {"name": "Mine", "scene": "res://party/items/mine.tscn", "icon": "res://party/art/landmine.webp", "size": Vector2(64, 24), "weight": 8},
	"fan": {"name": "Fan", "scene": "res://party/items/fan.tscn", "icon": "res://party/art/fan.webp", "size": Vector2(64, 270), "offset": Vector2(0, -120), "weight": 8},
	"lift": {"name": "Lift", "scene": "res://objects/platform.tscn", "icon": "res://party/art/lift.webp", "size": Vector2(128, 250), "offset": Vector2(0, -110),
		"props": {"size": Vector2(128, 24), "move_offset": Vector2(0, -220), "move_time": 1.6, "pause_time": 0.4}, "weight": 8},
	"ferris": {"name": "Ferris wheel", "host": true, "scene": "res://party/items/ferris.tscn", "icon": "res://party/art/ferris.webp", "size": Vector2(360, 380), "offset": Vector2(0, 28), "weight": 5},
	"slider": {"name": "Slider", "scene": "res://party/items/slider.tscn", "icon": "res://party/art/slider.webp", "size": Vector2(220, 40), "host": true, "weight": 7},
	"pendulum": {"name": "Pendulum", "host": true, "scene": "res://party/items/pendulum.tscn", "icon": "res://party/art/pendulum.webp", "size": Vector2(350, 220), "offset": Vector2(0, 95), "weight": 6},
	"flamer": {"name": "Flamethrower", "scene": "res://party/items/flamer.tscn", "icon": "res://party/art/flamer.webp", "size": Vector2(64, 236), "offset": Vector2(0, -86), "weight": 6},
	"bomb": {"name": "Bomb", "bomb": true, "radius": 130.0, "icon": "res://party/art/bomb.webp", "size": Vector2(64, 64), "weight": 6},
	"nuke": {"name": "Nuke", "bomb": true, "radius": 260.0, "icon": "res://party/art/nuke.webp", "size": Vector2(64, 64), "weight": 1},
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


## Share of the box this item gets, 0..1 (what the Items screen shows as a %).
func chance(id: String) -> float:
	var total := 0
	for k in ITEMS:
		total += weight(k)
	return float(weight(id)) / total if total > 0 else 0.0


## Random item id, following the weights. `skip` ids are left out.
func pick_item(rng: RandomNumberGenerator, skip: Array = []) -> String:
	var total := 0
	for k in ITEMS:
		if not k in skip:
			total += weight(k)
	if total <= 0:
		return "block"
	var roll := rng.randi_range(1, total)
	for k in ITEMS:
		if k in skip:
			continue
		roll -= weight(k)
		if roll <= 0:
			return k
	return "block"


func save_weights() -> void:
	var cfg := ConfigFile.new()
	for k in weights:
		cfg.set_value("weights", k, weights[k])
	cfg.set_value("party", "arena", arena_choice)
	cfg.save(ITEMS_PATH)


func load_weights() -> void:
	weights.clear()
	var cfg := ConfigFile.new()
	if cfg.load(ITEMS_PATH) == OK:
		arena_choice = str(cfg.get_value("party", "arena", "random"))
	if cfg.load(ITEMS_PATH) == OK and cfg.has_section("weights"):
		for k in cfg.get_section_keys("weights"):
			if ITEMS.has(k):
				weights[k] = clampi(int(cfg.get_value("weights", k)), 0, MAX_WEIGHT)


## Which arena new parties use: "random", a built-in arena path, or "map:<file>".
var arena_choice := "random"
## Set while testing a map from the editor: going back to the menu returns there.
var return_to_editor := false


func new_session(players: Array, choice := "") -> void:
	var scores := {}
	for s in players:
		scores[str(s)] = 0
	session = {"round": 1, "scores": scores, "players": players.duplicate(), "items": [],
		"arena": ARENAS[randi() % ARENAS.size()]}
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
		parts.append("P%d: %d" % [int(s), int(data.scores.get(str(int(s)), 0))])
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
