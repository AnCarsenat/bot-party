@tool
class_name Delayer
extends LogicNode
## Repeats its input `delay` seconds later.
## Every on/off change is replayed after the delay, so short pulses stay pulses.

@export_range(0.0, 60.0, 0.05, "or_greater", "suffix:s") var delay: float = 1.0:
	set(value):
		delay = value
		queue_redraw()

var _level := false
var _queue: Array = []  # [seconds_left, value]


func _on_inputs_changed() -> void:
	var level := any_on(inputs)
	if level == _level:
		return
	_level = level
	if delay <= 0.0:
		set_output(level)
	else:
		_queue.append([delay, level])


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _queue.is_empty():
		return
	for entry in _queue:
		entry[0] -= delta
	while not _queue.is_empty() and _queue[0][0] <= 0.0:
		set_output(_queue.pop_front()[1])
	queue_redraw()


func _default_texture() -> Texture2D:
	return preload("res://logic/delayer.webp")


func _label() -> PackedStringArray:
	return PackedStringArray(["DELAY", "%ss" % snappedf(delay, 0.01)])


func _progress() -> float:
	if _queue.is_empty() or delay <= 0.0:
		return -1.0
	return 1.0 - _queue[0][0] / delay
