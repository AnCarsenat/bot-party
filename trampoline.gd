class_name Trampoline
extends Node2D
## Launches players and crates that land on it.
## Place it with its origin (bottom centre) on the ground.

@export var bounce_speed: float = 1250.0
## Players holding jump while landing go this much higher.
@export var hold_jump_boost: float = 1.15
## Crates bounce a bit less.
@export var crate_factor: float = 0.8

var _cooldown := {}

@onready var _pad: Area2D = $Pad
@onready var _sprite: Sprite2D = $Sprite2D
@onready var _rest_scale := _sprite.scale


func _ready() -> void:
	_pad.collision_layer = 0
	_pad.collision_mask = Layers.PLAYERS | Layers.CRATES


func _physics_process(delta: float) -> void:
	for body in _cooldown.keys():
		_cooldown[body] -= delta
		if _cooldown[body] <= 0.0:
			_cooldown.erase(body)

	for body in _pad.get_overlapping_bodies():
		if _cooldown.has(body):
			continue
		var launched := false
		if body is CharacterBody2D and body.velocity.y >= -10.0 and body.has_method("bounce"):
			body.bounce(bounce_speed, hold_jump_boost)
			launched = true
		elif body is RigidBody2D and body.linear_velocity.y >= -10.0:
			body.linear_velocity.y = -bounce_speed * crate_factor
			launched = true
		if launched:
			_cooldown[body] = 0.2
			_boing()


func _boing() -> void:
	_sprite.scale = _rest_scale * Vector2(1.15, 0.7)
	var tw := create_tween()
	tw.tween_property(_sprite, "scale", _rest_scale, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
