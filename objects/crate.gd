class_name Crate
extends RigidBody2D
## A plain pushable box. Heavy enough to hold a button down.


func _init() -> void:
	collision_layer = Layers.CRATES
	collision_mask = Layers.WORLD | Layers.PLAYERS | Layers.CRATES
	z_index = 10  # in front of players


func _ready() -> void:
	add_to_group(LogicNode.OBJECT_GROUP)
	add_to_group("net_sync")
	if NetCheck.client(self):
		freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
		freeze = true  # online: placed where the host says


func net_state() -> Array:
	return [Vector2i(global_position.round()), snappedf(rotation, 0.01)]


var _net_target := Vector2.INF
var _net_rot := 0.0


func net_apply(s: Array) -> void:
	var pos := Vector2(s[0])
	if _net_target == Vector2.INF or global_position.distance_to(pos) > 200.0:
		global_position = pos
		rotation = s[1]
	_net_target = pos
	_net_rot = s[1]


func _process(delta: float) -> void:
	if _net_target != Vector2.INF:  # online client: glide to where the host has it
		var k := 1.0 - exp(-25.0 * delta)
		global_position = global_position.lerp(_net_target, k)
		rotation = lerp_angle(rotation, _net_rot, k)
