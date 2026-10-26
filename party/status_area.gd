class_name StatusArea
extends Area2D
## Puts an effect on players who touch it (see the player's statuses): bear traps,
## spitter spit, ice, glue, balloons. `refresh`: the effect lasts while they're
## inside (ice, glue); otherwise it's given once when they come in.
## `avoid`: bots stay away from it.

signal touched(player: Node)

@export var status := "stuck"
@export var seconds := 1.0
@export var refresh := false
var avoid := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.PLAYERS
	monitorable = false
	body_entered.connect(_on_body)


## (Online: the computer that moves a robot gives it its statuses.)
func _on_body(body: Node) -> void:
	if not monitoring or not NetCheck.moves(body):
		return
	if body.has_method("add_status") and not body.get_meta("eliminated", false):
		body.add_status(status, seconds)
		touched.emit(body)


func _physics_process(_d: float) -> void:
	if not refresh or not monitoring:
		return
	for b in get_overlapping_bodies():
		if b.has_method("add_status") and NetCheck.moves(b):
			b.add_status(status, seconds)


## A rectangle shape, centred at `at`.
func set_box(size: Vector2, at := Vector2.ZERO) -> void:
	for c in get_children():
		if c is CollisionShape2D:
			c.queue_free()
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size
	cs.shape = r
	cs.position = at
	add_child(cs)
