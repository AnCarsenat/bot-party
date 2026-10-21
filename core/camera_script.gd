extends Camera2D

@export var follow_speed: float = 5.0
@export var player_group: StringName = &"camera_follow"

@export var boundary_left: float = -2000.0
@export var boundary_right: float = 2000.0
@export var boundary_top: float = -1500.0
@export var boundary_bottom: float = 1500.0

@export var game_manager: Node

@export_group("Zoom")
## Zoom out automatically so every player stays on screen.
@export var dynamic_zoom: bool = true
## Closest zoom (players together).
@export var max_zoom: float = 0.85
## Farthest zoom (players far apart).
@export var min_zoom: float = 0.45
## Space kept around the players, in pixels.
@export var zoom_margin: Vector2 = Vector2(500, 380)
@export var zoom_speed: float = 3.0

func _process(delta: float) -> void:
	var players = get_tree().get_nodes_in_group(player_group)
	var total_position := Vector2.ZERO
	var count := 0
	var bounds := Rect2()

	for player in players:
		if not is_instance_valid(player) or not player is Node2D:
			continue
		if player.get_meta("eliminated", false):
			continue

		# Players outside the boundaries are out (other followed things, like
		# party items being placed, are just followed).
		if player is CharacterBody2D and is_out_of_bounds(player.global_position):
			if game_manager:
				game_manager.eliminate_player(player)
			continue

		total_position += player.global_position
		bounds = Rect2(player.global_position, Vector2.ZERO) if count == 0 else bounds.expand(player.global_position)
		count += 1

	if count == 0:
		return

	var average_position := total_position / count
	global_position = global_position.lerp(
		average_position,
		1.0 - exp(-follow_speed * delta)
	)

	if dynamic_zoom:
		var view := get_viewport_rect().size
		var needed := bounds.size + zoom_margin
		var z := clampf(minf(view.x / needed.x, view.y / needed.y), min_zoom, max_zoom)
		zoom = zoom.lerp(Vector2(z, z), 1.0 - exp(-zoom_speed * delta))

func is_out_of_bounds(pos: Vector2) -> bool:
	return (
		pos.x < boundary_left
		or pos.x > boundary_right
		or pos.y < boundary_top
		or pos.y > boundary_bottom
	)
