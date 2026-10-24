extends StaticBody2D
## Special item: a block of ice. Robots standing on it are slippery.


func _ready() -> void:
	var top := StatusArea.new()
	top.name = "Ice"
	top.status = "slippery"
	top.seconds = 0.25
	top.refresh = true
	top.set_box(Vector2(60, 12), Vector2(0, -36))
	add_child(top)
