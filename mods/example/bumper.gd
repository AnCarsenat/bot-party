extends Node
## Example item script: a pinball bumper. Touch it and you get knocked away.
## The game adds this node as a child of the item, so get_parent() is the item
## (here the built-in block: a StaticBody2D with a Sprite2D).

const PUSH := 750.0

var item: Node2D


func _ready() -> void:
	item = get_parent()
	# Our own picture instead of the block's (files sit next to this script).
	var sprite: Sprite2D = item.get_node("Sprite2D")
	sprite.texture = Mods.texture(get_script().resource_path.get_base_dir().path_join("bumper.png"))
	# Round body instead of the square one.
	var shape: CollisionShape2D = item.get_node("CollisionShape2D")
	var circle := CircleShape2D.new()
	circle.radius = 30
	shape.set_deferred("shape", circle)
	# A slightly bigger sensor that notices players touching it.
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 2  # players
	var sensor := CollisionShape2D.new()
	var round_sensor := CircleShape2D.new()
	round_sensor.radius = 36
	sensor.shape = round_sensor
	area.add_child(sensor)
	area.body_entered.connect(_on_touch)
	item.add_child.call_deferred(area)


func _on_touch(body: Node2D) -> void:
	if body.has_method("bounce"):
		var away := (body.global_position - item.global_position).normalized()
		body.bounce(PUSH, 1.0, away)
		var tw := item.create_tween()  # a little squash, for the feel
		tw.tween_property(item, "scale", Vector2(1.15, 1.15), 0.05)
		tw.tween_property(item, "scale", Vector2.ONE, 0.12)
