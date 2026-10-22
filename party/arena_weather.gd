extends Node2D
## Arena effects for party mode, active only while racing:
##  - wind: gusts that push everyone left or right (announced a second before)
##  - meteors: rocks fall on a marked spot and blow up whoever is close.
##    Solid ground stops them; the start area is never targeted.

@export var wind := false
@export var wind_strength := 280.0
@export var gust_every := 6.5
@export var gust_time := 3.0
@export var meteors := false
@export var meteor_every := 1.5
@export var meteor_radius := 80.0
@export var meteor_warn := 1.2

const TEX_METEOR := preload("res://party/art/meteor.webp")
const TEX_WIND := preload("res://party/art/wind.webp")
const FALL_TIME := 0.6
const RAY_MASK := Layers.WORLD | Layers.CRATES

var gust_dir := 0.0        # -1, 0 or 1 while a gust blows
var _gust_t := 0.0
var _gust_power := 0.0
var _meteor_t := 0.0
var _falling: Array[Dictionary] = []  # {target, t}
var _rng := RandomNumberGenerator.new()
var _hz: Hazard
var _sign: TextureRect
var _arrows: Control


func _ready() -> void:
	_rng.randomize()
	z_index = 40
	add_to_group("net_sync")
	_hz = Hazard.new()  # used to eliminate players (no trap points: nobody owns the weather)
	_hz.monitoring = false
	add_child(_hz)
	var layer := CanvasLayer.new()
	layer.layer = 39
	add_child(layer)
	_sign = TextureRect.new()
	_sign.texture = TEX_WIND
	_sign.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sign.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sign.pivot_offset = Vector2(48, 48)
	_sign.anchor_left = 0.5
	_sign.anchor_right = 0.5
	_sign.offset_left = -48
	_sign.offset_right = 48
	_sign.offset_top = 110
	_sign.offset_bottom = 206
	_sign.hide()
	layer.add_child(_sign)
	# Arrows beside it: which way it blows.
	_arrows = _Arrows.new()
	_arrows.weather = self
	_arrows.position = Vector2(-80, 0)
	_arrows.size = Vector2(256, 96)
	_sign.add_child(_arrows)


func _controller() -> Node:
	return get_tree().get_first_node_in_group("party_controller")


func racing() -> bool:
	var c := _controller()
	return c != null and c.phase == c.Phase.RUN


func _physics_process(delta: float) -> void:
	if not racing():
		_calm()
		return
	var client := NetCheck.client(self)
	if wind:
		_update_wind(delta, client)
	if meteors:
		_update_meteors(delta, client)


# Online: clients get the gusts and the meteors from the host (their impacts only
# show effects there; the host's eliminate the players).
var _meteor_id := 0
var _seen_meteors := {}


func net_state() -> Array:
	var falling := []
	for m in _falling:
		falling.append([m.get("id", 0), m.target])
	return [gust_dir, snappedf(_gust_t, 0.05), falling]


func net_apply(s: Array) -> void:
	gust_dir = s[0]
	if absf(_gust_t - s[1]) > 0.2:
		_gust_t = s[1]
	for f in s[2]:
		if not _seen_meteors.has(f[0]):
			_seen_meteors[f[0]] = true
			_falling.append({"id": f[0], "target": f[1], "t": meteor_warn})


func _calm() -> void:
	gust_dir = 0.0
	_gust_t = 0.0
	_gust_power = 0.0
	_meteor_t = 0.0
	_falling.clear()
	_sign.hide()
	for p in get_tree().get_nodes_in_group("players"):
		if "wind_vx" in p:
			p.wind_vx = 0.0


# --- Wind -----------------------------------------------------------------------

func _update_wind(delta: float, client := false) -> void:
	_gust_t += delta
	var warn_at := gust_every - 1.0
	if _gust_t >= warn_at and _gust_t < gust_every and gust_dir == 0.0 and not client:
		gust_dir = 1.0 if _rng.randf() < 0.5 else -1.0
		_gust_power = 0.0
	var blowing := _gust_t >= gust_every
	if blowing:
		_gust_power = minf(1.0, _gust_power + delta * 2.0)
		if _gust_t >= gust_every + gust_time:
			_gust_t = 0.0
			gust_dir = 0.0
	else:
		_gust_power = maxf(0.0, _gust_power - delta * 2.0)
	# Sign: flashes while warning, steady while blowing.
	_sign.visible = gust_dir != 0.0 and (blowing or int(_gust_t * 6.0) % 2 == 0)
	_sign.flip_h = gust_dir < 0.0
	for p in get_tree().get_nodes_in_group("players"):
		if "wind_vx" in p:
			p.wind_vx = gust_dir * wind_strength * _gust_power


# --- Meteors ----------------------------------------------------------------------

func _update_meteors(delta: float, client := false) -> void:
	_meteor_t += delta
	if _meteor_t >= meteor_every and not client:
		_meteor_t = _rng.randf_range(-0.4, 0.2)
		var target := _pick_target()
		if target != Vector2.INF:
			_meteor_id += 1
			_falling.append({"id": _meteor_id, "target": target, "t": meteor_warn})
	for m in _falling.duplicate():
		m.t -= delta
		if m.t <= 0.0:
			_falling.erase(m)
			_impact(m.target)


func _pick_target() -> Vector2:
	var c := _controller()
	var area: Rect2 = c.build_area
	var x := _rng.randf_range(area.position.x, area.end.x)
	# Half of them aim near someone.
	var alive := []
	for p in get_tree().get_nodes_in_group("players"):
		if not p.get_meta("eliminated", false) and not p.get_meta("finished", false):
			alive.append(p)
	if not alive.is_empty() and _rng.randf() < 0.5:
		x = alive[_rng.randi_range(0, alive.size() - 1)].global_position.x + _rng.randf_range(-160, 160)
	var start: Rect2 = c.start_zone
	if x > start.position.x - meteor_radius and x < start.end.x + meteor_radius:
		return Vector2.INF  # never on the start area
	var from := Vector2(x, area.position.y - 200)
	var hit := get_world_2d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters2D.create(from, from + Vector2(0, area.size.y + 800), RAY_MASK))
	return hit.position if hit else Vector2.INF


func _impact(at: Vector2) -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if p.global_position.distance_to(at) <= meteor_radius + 30.0:
			_hz.hurt(p)
	get_parent().add_child(Effects.ring(at, meteor_radius, Color("e8b270")))
	get_parent().add_child(Effects.burst(at, Color("6cba7c"), 16, 320.0, [Color("6cba7c"), Color("e8b270"), Color("e64f3e")]))


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	# Meteors: warning ring on the ground, then the rock coming down.
	for m in _falling:
		var target: Vector2 = m.target
		var k: float = 1.0 - m.t / meteor_warn
		var red := Color(0.9, 0.31, 0.24, 0.35 + 0.45 * k)
		draw_circle(target, meteor_radius * (0.4 + 0.6 * k), Color(red, 0.18))
		draw_arc(target, meteor_radius, 0, TAU, 40, red, 4.0)
		if m.t < FALL_TIME:
			var f: float = 1.0 - m.t / FALL_TIME
			var p := target + Vector2(260, -900).lerp(Vector2.ZERO, f)
			draw_set_transform(p, Vector2(-260, 900).angle() - PI / 2.0, Vector2(3, 3))
			draw_texture(TEX_METEOR, Vector2(-16, -24))
			draw_set_transform(Vector2.ZERO)
	# Wind: streaks across the view.
	if _gust_power > 0.01:
		var view := get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_visible_rect()
		var t := Time.get_ticks_msec() / 1000.0
		for i in 26:
			var y := view.position.y + fmod(i * 97.0, view.size.y)
			var x := view.position.x + fposmod(i * 211.0 + gust_dir * t * 1400.0, view.size.x)
			var len := 60.0 + (i % 4) * 30.0
			draw_line(Vector2(x, y), Vector2(x - gust_dir * len, y), Color(1, 1, 1, 0.5 * _gust_power), 4.0)


# --- Console ------------------------------------------------------------------------

## Drops a meteor on the ground below x (host).
func drop_meteor(x: float) -> bool:
	var c := _controller()
	var top: float = c.build_area.position.y - 200 if c else -800.0
	var hit := get_world_2d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters2D.create(Vector2(x, top), Vector2(x, top + 4000), RAY_MASK))
	if not hit:
		return false
	_meteor_id += 1
	_falling.append({"id": _meteor_id, "target": hit.position, "t": meteor_warn})
	return true


## Starts a gust now (dir -1 left, 1 right, 0 stops the wind).
func gust(dir: float) -> void:
	wind = dir != 0.0 or wind
	gust_dir = dir
	_gust_t = gust_every if dir != 0.0 else 0.0


## Three chevrons pointing where the wind blows, sliding that way.
class _Arrows extends Control:
	var weather: Node

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var dir: float = weather.gust_dir
		if dir == 0.0:
			return
		var t := fmod(Time.get_ticks_msec() / 1000.0 * 3.0, 1.0)
		var mid := size / 2.0
		for i in 3:
			var x := (-1.5 + i + t * dir) * 34.0 * dir + 128.0 * dir
			var c := mid + Vector2(x, 0)
			var pts := PackedVector2Array([c + Vector2(-10 * dir, -18), c + Vector2(10 * dir, 0), c + Vector2(-10 * dir, 18)])
			draw_polyline(pts, Color.BLACK, 12.0)
			draw_polyline(pts, Color("f0fff4"), 6.0)
