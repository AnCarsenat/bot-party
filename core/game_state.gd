extends Node
## Autoload "GameState": player count, level list and progress (saved to disk).

signal player_count_changed(count: int)
signal joined_changed

const SAVE_PATH := "user://progress.cfg"
const MAX_PLAYERS := 8

## Campaigns, one per group size. The menu offers the one that matches how many
## people have joined; each keeps its own progress. Add levels here.
## (A level can be in several campaigns; PlayerCountFilter nodes adapt it.)
const L_MACHINE := {"name": "Machine room", "path": "res://levels/map_1.tscn"}
const L_SIGNALS := {"name": "Signals", "path": "res://levels/map_2.tscn"}
const L_SPIKES := {"name": "Spikes", "path": "res://levels/map_3.tscn"}
const L_LADDER := {"name": "Ladder", "path": "res://levels/map_4.tscn"}
const L_TOWER := {"name": "Tower", "path": "res://levels/map_5.tscn"}
const CAMPAIGNS := [
	{"id": "solo", "name": "Solo", "min": 1, "max": 1, "levels": [
		L_MACHINE, L_SIGNALS, L_SPIKES,
		{"name": "Crate climb", "path": "res://levels/solo_crates.tscn"},
	]},
	{"id": "duo", "name": "Duo", "min": 2, "max": 2, "levels": [
		L_MACHINE, L_SIGNALS,
		{"name": "Two keys", "path": "res://levels/duo_keys.tscn"},
		L_SPIKES,
	]},
	{"id": "trio", "name": "Trio", "min": 3, "max": 3, "levels": [
		L_MACHINE, L_SIGNALS, L_LADDER,
		{"name": "Three switches", "path": "res://levels/trio_switches.tscn"},
	]},
	{"id": "squad", "name": "Squad", "min": 4, "max": 8, "levels": [
		L_MACHINE, L_LADDER, L_TOWER,
		{"name": "All hands", "path": "res://levels/squad_hands.tscn"},
	]},
]

## The campaign being played (set when a level starts), or "" to follow the player count.
var campaign_id := ""

## Levels of the current campaign, in play order.
var levels: Array:
	get:
		return campaign().levels

## Which player slots have joined (1 = keys of p1, 2 = keys of p2, ...).
var joined: Array[int] = [1, 2]:
	set(value):
		joined = value
		joined.sort()
		joined_changed.emit()
		player_count_changed.emit(joined.size())

## Number of joined players. Setting it joins slots 1..n (handy for tests).
var player_count: int:
	get:
		return joined.size()
	set(value):
		var slots: Array[int] = []
		for i in clampi(value, 1, MAX_PLAYERS):
			slots.append(i + 1)
		joined = slots


func is_joined(slot: int) -> bool:
	return slot in joined


func join(slot: int) -> void:
	if slot >= 1 and slot <= MAX_PLAYERS and not is_joined(slot):
		var j := joined.duplicate()
		j.append(slot)
		joined = j
		save_settings()


func leave(slot: int) -> void:
	if is_joined(slot):
		var j := joined.duplicate()
		j.erase(slot)
		joined = j
		save_settings()
var current_level: int = -1
## Player-facing options, saved with the progress.
var settings := {"music_volume": 0.8, "sfx_volume": 0.8, "fullscreen": false}
## Campaign id -> how many of its levels can be picked in the menu (1 = only the first).
var _unlocked := {}
var unlocked: int:
	get:
		return int(_unlocked.get(campaign().id, 1))
	set(value):
		_unlocked[campaign().id] = clampi(value, 1, levels.size())


## The campaign for `count` players (default: the people who joined).
func campaign_for(count: int) -> Dictionary:
	for c in CAMPAIGNS:
		if count >= c.min and count <= c.max:
			return c
	return CAMPAIGNS[-1] if count > 1 else CAMPAIGNS[0]


func campaign() -> Dictionary:
	if campaign_id != "":
		for c in CAMPAIGNS:
			if c.id == campaign_id:
				return c
	return campaign_for(maxi(1, joined.size()))


func _ready() -> void:
	_load()
	# When a level scene is run directly from the editor (F6), remember which one it is.
	var scene := get_tree().current_scene
	if scene:
		current_level = level_index(scene.scene_file_path)
		if current_level < 0:
			_adopt_campaign_of(scene.scene_file_path)


## A level started some other way (editor, tests): use a campaign that has it.
func _adopt_campaign_of(path: String) -> void:
	var preferred := campaign_for(maxi(1, joined.size()))
	for c in [preferred] + CAMPAIGNS:
		for i in c.levels.size():
			if c.levels[i].path == path:
				campaign_id = c.id
				current_level = i
				return


func level_index(path: String) -> int:
	for i in levels.size():
		if levels[i].path == path:
			return i
	return -1


func level_name(index: int = current_level) -> String:
	return levels[index].name if index >= 0 and index < levels.size() else ""


func start_level(index: int) -> void:
	campaign_id = campaign().id  # stick to this campaign even if someone drops in
	current_level = index
	_transition().change_scene(levels[index].path)


## Called by the finish door.
func complete_level() -> void:
	var finished := current_level
	if finished < 0:
		finished = level_index(get_tree().current_scene.scene_file_path)
	# Next level this group can play (levels needing more people are unlocked but skipped).
	var next := finished + 1
	while next < levels.size() and not can_play(next):
		next += 1
	unlocked = maxi(unlocked, mini(maxi(next, finished + 1) + 1, levels.size()))
	_save()
	if finished >= 0 and next < levels.size():
		current_level = next
		_transition().change_scene(levels[current_level].path, "Level complete")
	else:
		go_to_menu("Every level done. Well played!")


func min_players(_index: int = 0) -> int:
	return int(campaign().min)


func can_play(index: int) -> bool:
	return joined.size() >= min_players(index)


func restart_level() -> void:
	_transition().reload()


func go_to_menu(message := "") -> void:
	current_level = -1
	campaign_id = ""
	get_tree().paused = false
	_transition().change_scene("res://ui/main_menu.tscn", message, 2.0 if message != "" else 0.0)


func _transition() -> Node:
	return get_tree().root.get_node("Transition")


func _save() -> void:
	var cfg := ConfigFile.new()
	for k in _unlocked:
		cfg.set_value("progress", "unlocked_" + k, _unlocked[k])
	var net := get_tree().root.get_node_or_null("Net") if is_inside_tree() else null
	cfg.set_value("settings", "joined", net.offline_joined() if net else joined)
	for k in settings:
		cfg.set_value("settings", k, settings[k])
	cfg.save(SAVE_PATH)


func save_settings() -> void:
	_save()


func apply_settings() -> void:
	for bus in [["Music", "music_volume"], ["SFX", "sfx_volume"]]:
		var idx := AudioServer.get_bus_index(bus[0])
		if idx >= 0:
			var v: float = settings[bus[1]]
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
			AudioServer.set_bus_mute(idx, v <= 0.001)
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		for c in CAMPAIGNS:
			_unlocked[c.id] = clampi(int(cfg.get_value("progress", "unlocked_" + c.id, 1)), 1, c.levels.size())
		var j: Array[int] = []
		for v in cfg.get_value("settings", "joined", [1, 2]):
			j.append(int(v))
		joined = j if not j.is_empty() else [1] as Array[int]
		for k in settings:
			settings[k] = cfg.get_value("settings", k, settings[k])
	apply_settings()
