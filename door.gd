@tool
class_name Door
extends Node2D
## Exit door: leads to another level.
## - No inputs: always open. With inputs: open while active (HOLD) or flips on each pulse (TOGGLE).
## - When open and every player still in the game stands in front of it,
##   the game switches to `next_level`.

signal level_completed

enum InputMode { HOLD, TOGGLE }

## Scene loaded when everyone is through the door.
## Empty = use the level order in GameState (next level, or back to the menu after the last).
@export_file("*.tscn") var next_level: String = ""
@export var finish_message: String = "Level complete"
## true: all remaining players must be at the door. false: the first player is enough.
@export var require_all_players: bool = true
@export var player_group: StringName = &"players"
const TEXTURE := preload("res://door.webp")

@export var size: Vector2 = Vector2(64, 128):
	set(value):
		size = value
		_update_area()
## Extra width on each side that still counts as "at the door"
## (players collide with each other, so they can't all fit in the doorway).
@export var reach: float = 64.0:
	set(value):
		reach = value
		_update_area()

@export_group("Logic")
@export var inputs: Array[Node] = []:
	set(value):
		inputs = value
		queue_redraw()
@export var input_mode: InputMode = InputMode.HOLD
## Closed by default, inputs close it instead of opening it.
@export var inverted: bool = false

var is_open: bool = true
var players_inside: int = 0
var players_needed: int = 0

var _toggled_on := false
var _leaving := false

@onready var _area: Area2D = $Area2D
@onready var _shape: CollisionShape2D = $Area2D/CollisionShape2D


func _ready() -> void:
	_area.collision_layer = 0
	_area.collision_mask = Layers.PLAYERS
	_update_area()
	if Engine.is_editor_hint():
		return
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	LogicNode.on_debug_view_changed(self, queue_redraw)
	if not inputs.is_empty():
		Wires.attach(self)
	LogicNode.connect_inputs(inputs, _on_input_toggled, _on_input_pressed)
	_update_open()


func _update_area() -> void:
	if is_node_ready():
		(_shape.shape as RectangleShape2D).size = size + Vector2(reach * 2.0, 0)
	queue_redraw()


func _on_input_toggled(_state: bool) -> void:
	_update_open()


func _on_input_pressed() -> void:
	if input_mode == InputMode.TOGGLE:
		_toggled_on = not _toggled_on
		_update_open()


func _update_open() -> void:
	var raw: bool
	if inputs.is_empty():
		raw = true
	elif input_mode == InputMode.HOLD:
		raw = LogicNode.any_on(inputs)
	else:
		raw = _toggled_on
	is_open = raw != inverted
	queue_redraw()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	if _leaving:
		return

	var alive := 0
	var inside := 0
	var overlapping := _area.get_overlapping_bodies()
	for p in get_tree().get_nodes_in_group(player_group):
		if p.get_meta("eliminated", false) or not p.is_visible_in_tree():
			continue
		alive += 1
		if p in overlapping:
			inside += 1

	if inside != players_inside or alive != players_needed:
		players_inside = inside
		players_needed = alive
		queue_redraw()

	if not is_open or inside == 0:
		return
	if inside == alive or not require_all_players:
		_leave()


func _leave() -> void:
	_leaving = true
	level_completed.emit()
	var gs := get_tree().root.get_node_or_null("GameState")
	var transition := get_tree().root.get_node_or_null("Transition")
	if next_level == "" and gs:
		gs.complete_level()
	elif next_level == "":
		get_tree().reload_current_scene()
	elif transition:
		transition.change_scene(next_level, finish_message)
	else:
		get_tree().call_deferred("change_scene_to_file", next_level)


func _draw() -> void:
	var debug := LogicNode.debug_visible(self)
	if Engine.is_editor_hint():
		LogicNode.draw_wires(self, inputs)

	var r := Rect2(-size / 2.0, size)
	if debug and Engine.is_editor_hint() and reach > 0.0:
		draw_rect(r.grow_individual(reach, 0, reach, 0), Color(1, 1, 1, 0.25), false, 1.0)

	if is_open:
		draw_texture_rect(TEXTURE, r, false)
	else:
		# Locked: darker doorway with bars across it.
		draw_texture_rect(TEXTURE, r, false, Color(0.55, 0.55, 0.55))
		var bar := Color(0.75, 0.75, 0.8)
		for i in 4:
			var x := r.position.x + r.size.x * (i + 0.5) / 4.0
			draw_line(Vector2(x, r.position.y + r.size.y * 0.3), Vector2(x, r.end.y), bar, 3.0)
		draw_line(Vector2(r.position.x + 4, r.position.y + r.size.y * 0.6), Vector2(r.end.x - 4, r.position.y + r.size.y * 0.6), bar, 3.0)

	var font := ThemeDB.fallback_font
	var text := ""
	if Engine.is_editor_hint():
		text = "EXIT" if next_level != "" else "EXIT (next level)"
	elif not is_open:
		text = "LOCKED"
	elif require_all_players and players_needed > 1 and players_inside > 0:
		text = "%d/%d" % [players_inside, players_needed]
	if text != "":
		draw_string(font, Vector2(-80, r.position.y + 10), text,
			HORIZONTAL_ALIGNMENT_CENTER, 160, 16, Color.WHITE)
