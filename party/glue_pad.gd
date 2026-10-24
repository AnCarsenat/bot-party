extends Node2D
## Special item: a puddle of glue. Robots in it move at half speed and jump lower.

const TEX := preload("res://party/art/glue_pad.webp")


func _ready() -> void:
	var glue := StatusArea.new()
	glue.name = "Glue"
	glue.status = "slowed"
	glue.seconds = 0.3
	glue.refresh = true
	glue.set_box(Vector2(60, 30), Vector2(0, 12))
	add_child(glue)


func _draw() -> void:
	draw_texture_rect(TEX, Rect2(-32, -32, 64, 64), false)
