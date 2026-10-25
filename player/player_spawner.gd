@tool
class_name PlayerSpawner
extends Node2D
## Spawns one player per person (GameState.player_count) when the level starts,
## in rows of `per_row`, starting at this node's position.

const PLAYER_SCENE := preload("res://player/player.tscn")
## One colour per player (P1, P2, ...).
const COLORS: Array[Color] = [
	Color(1.0, 1.0, 1.0), Color(1.0, 0.55, 0.5), Color(0.55, 0.8, 1.0), Color(0.6, 1.0, 0.55),
	Color(1.0, 0.9, 0.45), Color(0.85, 0.6, 1.0), Color(0.5, 1.0, 0.95), Color(1.0, 0.7, 0.3),
]

@export var spacing: float = 100.0
@export var per_row: int = 4
## Overrides GameState.player_count when > 0 (handy for testing a level).
@export_range(0, 8) var force_player_count: int = 0

var players: Array[CharacterBody2D] = []


## Online: people who join while the level runs appear in it.
@export var allow_drop_in: bool = true
## Local players who haven't joined drop in by pressing their jump key. Off: people
## join from the Players screen, so a stray key press doesn't add a robot (and
## change the campaign for a bigger group).
@export var keyboard_drop_in: bool = false
## Spawn the joined players when the level starts (party mode spawns them itself).
@export var auto_spawn: bool = true


func _ready() -> void:
	if Engine.is_editor_hint() or not auto_spawn:
		return
	var slots: Array[int] = []
	if force_player_count > 0:
		for i in force_player_count:
			slots.append(i + 1)
	else:
		var gs := get_tree().root.get_node_or_null("GameState")
		slots = gs.joined.duplicate() if gs else [1, 2] as Array[int]
	for i in slots.size():
		var pos := position + Vector2((i % per_row) * spacing, -(i / per_row) * spacing)
		spawn(slots[i], pos, slots.size() > 1, true)


## Creates the player for `slot` (1-8) at `pos`.
func spawn(slot: int, pos: Vector2, show_tag: bool, deferred := false) -> CharacterBody2D:
	var p: CharacterBody2D = PLAYER_SCENE.instantiate()
	var color := COLORS[(slot - 1) % COLORS.size()]
	p.name = "Player%d" % slot
	p.input_prefix = "p%d" % slot
	p.position = pos
	p.add_to_group("players")
	p.add_to_group("camera_follow")
	p.set_meta("player_index", slot - 1)
	p.set_meta("color", color)
	p.get_node("Sprite2D").self_modulate = color  # the face (child) keeps its own colours
	if show_tag:
		_add_tag(p, slot - 1)
	if deferred:
		get_parent().add_child.call_deferred(p)
	else:
		get_parent().add_child(p)
	players.append(p)
	return p


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or not allow_drop_in or not keyboard_drop_in:
		return
	if NetCheck.online(self):
		return  # online: people join from the lobby
	for slot in range(1, 9):
		var action := "p%d_action_1" % slot
		if not InputMap.has_action(action) or not Input.is_action_just_pressed(action):
			continue
		if get_parent().has_node("Player%d" % slot):
			continue
		_drop_in(slot)


func _drop_in(slot: int) -> void:
	# Appear just above a player who is still in the game (or at the spawn point).
	var pos := position
	for p in get_tree().get_nodes_in_group("players"):
		if not p.get_meta("eliminated", false):
			pos = p.global_position + Vector2(0, -120)
			break
	var p := spawn(slot, pos, true)
	p.set("_squash", Vector2(0.2, 1.8))  # pop in
	var gs := get_tree().root.get_node_or_null("GameState")
	if gs:
		gs.join(slot)
	# Give existing players a tag now that there are several.
	for other in get_tree().get_nodes_in_group("players"):
		if other != p and not other.has_node("Tag"):
			_add_tag(other, other.get_meta("player_index", 0))


func _add_tag(p: Node2D, i: int) -> void:
	var tag := Label.new()
	tag.name = "Tag"
	var net := get_tree().root.get_node_or_null("Net")
	tag.text = net.player_label(i + 1) if net and net.is_online() else "P%d" % (i + 1)  # online: "Zoe", "Zoe 2"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.position = Vector2(-80, -78)
	tag.size = Vector2(160, 20)
	tag.add_theme_font_override("font", UiTheme.FONT_BOLD)
	tag.add_theme_font_size_override("font_size", 18)
	tag.add_theme_color_override("font_color", COLORS[i % COLORS.size()])
	tag.add_theme_color_override("font_outline_color", Color.BLACK)
	tag.add_theme_constant_override("outline_size", 6)
	p.add_child(tag)


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	for i in 4:
		var r := Rect2(Vector2(i * spacing - 41, -41), Vector2(82, 82))
		draw_rect(r, Color(1, 1, 1, 0.35 if i else 0.7), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(-41, -50), "SPAWN", HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
