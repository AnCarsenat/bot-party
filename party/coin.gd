extends Area2D
## Grab it and reach the flag with it for bonus points. Drops back if you're out.

signal taken(by: Node)

var carrier: Node2D
var home := Vector2.ZERO
var _t := 0.0
@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	home = global_position
	collision_layer = 0
	collision_mask = Layers.PLAYERS
	monitorable = false
	body_entered.connect(_on_body)
	add_to_group("net_sync")


func net_state() -> Array:
	return [Vector2i(global_position.round()), visible]


func net_apply(s: Array) -> void:
	global_position = Vector2(s[0])
	visible = s[1]


func _on_body(b: Node) -> void:
	if NetCheck.client(self):
		return  # online: the host decides who has it
	if carrier == null and b.is_in_group("players") and not b.get_meta("eliminated", false):
		carrier = b
		b.set_meta("coin", true)
		taken.emit(b)


func _process(delta: float) -> void:
	_t += delta
	if carrier != null and not NetCheck.client(self):
		if not is_instance_valid(carrier) or carrier.get_meta("eliminated", false):
			if is_instance_valid(carrier):
				carrier.set_meta("coin", false)
			carrier = null
			global_position = home
			set_deferred("monitoring", true)
		else:
			global_position = carrier.global_position + Vector2(0, -90)
			set_deferred("monitoring", false)
	_sprite.position.y = sin(_t * 4.0) * 4.0
	_sprite.scale.x = 2.5 * absf(cos(_t * 3.0)) + 0.3
