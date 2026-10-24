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

@export_group("Fixed camera")
## A camera that doesn't follow (follow speed 0) can still move this far (pixels)
## from where it's placed, and zoom out down to `fixed_zoom_out` times its zoom,
## so robots at the edges, above all at the top and bottom, stay in view.
@export var fixed_slack: Vector2 = Vector2(100, 200)
@export var fixed_zoom_out: float = 0.85

var _home := Vector2.INF
var _home_zoom := Vector2.ONE
## Screen shake (explosions): 0..1, fades out.
var _trauma := 0.0
var _rng := RandomNumberGenerator.new()


## Shakes the screen (Settings > Screen shake turns it off).
func shake(amount: float) -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs and not gs.settings.get("screen_shake", true):
		return
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

func _ready() -> void:
	# Bubbles for robots off the screen (Settings > Distant players).
	if not Engine.is_editor_hint() and DisplayServer.get_name() != "headless":
		add_child(DistantPlayers.new())


func _process(delta: float) -> void:
	_trauma = maxf(0.0, _trauma - delta * 1.4)
	var k := _trauma * _trauma
	offset = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 28.0 * k / zoom.x
	if _home == Vector2.INF:
		_home = global_position
		_home_zoom = zoom
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
		if follow_speed <= 0.0 and _home != Vector2.INF:
			# Nobody to watch (between rounds): back to where it belongs.
			var t := 1.0 - exp(-3.0 * delta)
			global_position = global_position.lerp(_home, t)
			zoom = zoom.lerp(_home_zoom, t)
		return

	if follow_speed <= 0.0:
		_fixed_view(bounds, delta)
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

## A fixed camera: stays put while everyone's in view, otherwise leans and zooms
## out a little toward the robots near the edges.
func _fixed_view(players: Rect2, delta: float) -> void:
	var view := get_viewport_rect().size
	var margin := Vector2(120, 140)  # keep a robot's whole body in view
	var want_zoom := _home_zoom
	var need := players.size + margin * 2.0
	var fit := minf(view.x / need.x, view.y / need.y)
	if fit < _home_zoom.x:
		want_zoom = Vector2.ONE * maxf(fit, _home_zoom.x * fixed_zoom_out)
	var half := view / want_zoom / 2.0
	var want := _home
	# Lean toward robots past the edges of the view (as far as the slack allows).
	var lo := players.position - margin
	var hi := players.end + margin
	if lo.x < want.x - half.x:
		want.x -= (want.x - half.x) - lo.x
	elif hi.x > want.x + half.x:
		want.x += hi.x - (want.x + half.x)
	if lo.y < want.y - half.y:
		want.y -= (want.y - half.y) - lo.y
	elif hi.y > want.y + half.y:
		want.y += hi.y - (want.y + half.y)
	want = want.clamp(_home - fixed_slack, _home + fixed_slack)
	var t := 1.0 - exp(-3.0 * delta)
	global_position = global_position.lerp(want, t)
	zoom = zoom.lerp(want_zoom, t)


func is_out_of_bounds(pos: Vector2) -> bool:
	return (
		pos.x < boundary_left
		or pos.x > boundary_right
		or pos.y < boundary_top
		or pos.y > boundary_bottom
	)
