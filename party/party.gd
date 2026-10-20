extends Node
## Autoload "Party": the party-mode session (scores, placed obstacles) and its save file.
## The session is saved after every placement and every round, so a party can be
## continued from the main menu, or after "Restart level" in the pause menu.

const TARGET_SCORE := 50
const SAVE_PATH := "user://party_session.json"
const ARENA := "res://party/party_arena.tscn"
const POINTS_FINISH := 10
const POINTS_FIRST := 5
const POINTS_TRAP := 2

## Everything a player can pick. size/offset describe the item's footprint
## (used to stop building in the start and goal areas).
const ITEMS := {
	"block": {"name": "Block", "scene": "res://party/items/block.tscn", "icon": "res://party/art/block.webp", "size": Vector2(64, 64)},
	"plank": {"name": "Plank", "scene": "res://platform.tscn", "icon": "res://toggle_platform_enabled.webp", "size": Vector2(192, 30), "props": {"size": Vector2(192, 30), "one_way": true}},
	"spikes": {"name": "Spikes", "scene": "res://party/items/spikes.tscn", "icon": "res://party/art/spikes.webp", "size": Vector2(64, 28)},
	"saw": {"name": "Saw", "scene": "res://party/items/saw.tscn", "icon": "res://party/art/saw.webp", "size": Vector2(240, 64)},
	"trampoline": {"name": "Trampoline", "scene": "res://trampoline.tscn", "icon": "res://trampoline.webp", "size": Vector2(80, 40), "offset": Vector2(0, -20)},
	"bomb": {"name": "Bomb", "bomb": true, "icon": "res://party/art/bomb.webp", "size": Vector2(64, 64)},
}

var session: Dictionary = {}


func new_session(players: Array) -> void:
	var scores := {}
	for s in players:
		scores[str(s)] = 0
	session = {"round": 1, "scores": scores, "players": players.duplicate(), "items": []}


func new_game() -> void:
	new_session(GameState.joined)
	save()
	get_tree().root.get_node("Transition").change_scene(ARENA, "Party time", 1.0)


func continue_game() -> void:
	if not load_save():
		new_game()
		return
	var slots: Array[int] = []
	for s in session.players:
		slots.append(int(s))
	GameState.joined = slots
	get_tree().root.get_node("Transition").change_scene(ARENA, "Round %d" % session.round, 1.0)


func end_game(message: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	session = {}
	GameState.go_to_menu(message)


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
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(session, "  "))


func load_save() -> bool:
	var data = _read()
	if data == null:
		return false
	session = data
	session.round = int(session.round)
	return true


func _read():
	if not has_save():
		return null
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or not data.has("players"):
		return null
	return data
