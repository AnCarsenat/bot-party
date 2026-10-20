class_name Crate
extends RigidBody2D
## A plain pushable box. Heavy enough to hold a button down.


func _init() -> void:
	collision_layer = Layers.CRATES
	collision_mask = Layers.WORLD | Layers.PLAYERS | Layers.CRATES
	z_index = 10  # in front of players


func _ready() -> void:
	add_to_group(LogicNode.OBJECT_GROUP)
