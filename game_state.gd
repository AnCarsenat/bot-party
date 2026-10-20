extends Node
## Autoload "GameState": player count, level list and progress (saved to disk).

signal player_count_changed(count: int)
signal joined_changed

const SAVE_PATH := "user://progress.cfg"
const MAX_PLAYERS := 8

## Levels in play order. Add new levels here.
var levels: Array[Dictionary] = [
	{"name": "Level 1 - Machine Room", "path": "res://map_1.tscn"},
	{"name": "Level 2 - Signals", "path": "res://map_2.tscn"},
]

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
## How many levels can be picked in the menu (1 = only the first).
var unlocked: int = 1


func _ready() -> void:
	_load()
	# When a level scene is run directly from the editor (F6), remember which one it is.
	var scene := get_tree().current_scene
	if scene:
		current_level = level_index(scene.scene_file_path)


func level_index(path: String) -> int:
	for i in levels.size():
		if levels[i].path == path:
			return i
	return -1


func level_name(index: int = current_level) -> String:
	return levels[index].name if index >= 0 and index < levels.size() else ""


func start_level(index: int) -> void:
	current_level = index
	_transition().change_scene(levels[index].path)


## Called by the finish door.
func complete_level() -> void:
	var finished := current_level
	if finished < 0:
		finished = level_index(get_tree().current_scene.scene_file_path)
	unlocked = maxi(unlocked, mini(finished + 2, levels.size()))
	_save()
	if finished >= 0 and finished + 1 < levels.size():
		current_level = finished + 1
		_transition().change_scene(levels[current_level].path, "Level complete")
	else:
		go_to_menu("Every level done. Well played!")


func restart_level() -> void:
	_transition().reload()


func go_to_menu(message := "") -> void:
	current_level = -1
	get_tree().paused = false
	_transition().change_scene("res://main_menu.tscn", message, 2.0 if message != "" else 0.0)


func _transition() -> Node:
	return get_tree().root.get_node("Transition")


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "unlocked", unlocked)
	cfg.set_value("settings", "joined", joined)
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
		unlocked = clampi(cfg.get_value("progress", "unlocked", 1), 1, levels.size())
		var j: Array[int] = []
		for v in cfg.get_value("settings", "joined", [1, 2]):
			j.append(int(v))
		joined = j if not j.is_empty() else [1] as Array[int]
		for k in settings:
			settings[k] = cfg.get_value("settings", k, settings[k])
	apply_settings()
