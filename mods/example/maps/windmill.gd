@tool
extends Node2D
## Part of the example map scene windmill_hill.tscn: a windmill whose sails turn.
## A map scene can hold any node or script made in Godot. In an online game, each
## computer runs its own copy, so keep such things to looks, or to motion that
## only depends on time.

@export var speed := 0.8


func _process(delta: float) -> void:
	$Sails.rotation += speed * delta
