extends Node2D
## A spinning blade sliding back and forth.

@export var travel: float = 90.0
@export var period: float = 2.4
@export var spin_speed: float = 9.0

var _t := 0.0
@onready var _blade: Node2D = $Blade


func _physics_process(delta: float) -> void:
	_t += delta
	_blade.position.x = sin(_t / period * TAU) * travel
	_blade.rotation += spin_speed * delta
