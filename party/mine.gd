extends StaticBody2D
## Explodes when a player touches it, taking out everyone close by. Rearms every round.
## The base is solid; the trigger sits just above it.

@export var radius: float = 110.0

var _armed := true
var _blink := 0.0
@onready var _trigger: Hazard = $Trigger
@onready var _sprite: Sprite2D = $Sprite2D
@onready var _solid: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	_trigger.hit.connect(_on_touch)
	add_to_group("net_sync")


func net_state() -> Array:
	return [_armed]


func net_apply(s: Array) -> void:
	if s[0] and not _armed:
		reset_round()
	elif not s[0] and _armed:
		_armed = false
		_boom()


func _process(delta: float) -> void:
	_blink += delta
	queue_redraw()


func _draw() -> void:
	# Blinking warning light on the pressure plate.
	if not _armed:
		return
	var on := fmod(_blink, 1.0) < 0.35
	var c := Color("ff5a45") if on else Color("6a2a24")
	draw_rect(Rect2(-3, -12, 6, 4), Color.BLACK)
	draw_rect(Rect2(-2, -11, 4, 2), c)
	if on:
		draw_circle(Vector2(0, -10), 7.0, Color(1, 0.35, 0.25, 0.25))


func _on_touch(body: Node) -> void:
	if not _armed:
		return
	_armed = false
	for p in get_tree().get_nodes_in_group("players"):
		if p != body and p.global_position.distance_to(global_position) <= radius:
			_trigger.hurt(p)
	_boom()


func _boom() -> void:
	_sprite.hide()
	_solid.set_deferred("disabled", true)  # gone: nothing left to bump into
	_trigger.set_deferred("monitoring", false)
	var level := get_tree().current_scene if get_tree().current_scene else get_parent()
	level.add_child(Effects.ring(global_position, radius, Color(1, 0.55, 0.2)))


func reset_round() -> void:
	_armed = true
	_sprite.show()
	_solid.set_deferred("disabled", false)
	_trigger.set_deferred("monitoring", true)
