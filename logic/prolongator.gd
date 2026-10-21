@tool
class_name Prolongator
extends LogicNode
## Turns on instantly with its input, but stays on `duration` seconds
## after the input turns off. Turning the input back on resets the timer.

@export_range(0.0, 60.0, 0.05, "or_greater", "suffix:s") var duration: float = 2.0:
	set(value):
		duration = value
		queue_redraw()

var _time_left := 0.0


func _on_inputs_changed() -> void:
	if any_on(inputs):
		_time_left = 0.0
		set_output(true)
	elif is_pressed:
		_time_left = duration
		if duration <= 0.0:
			set_output(false)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _time_left <= 0.0:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		set_output(false)
	queue_redraw()


func _default_texture() -> Texture2D:
	return preload("res://logic/prolongator.webp")


func _label() -> PackedStringArray:
	return PackedStringArray(["PROLONG", "+%ss" % snappedf(duration, 0.01)])


func _progress() -> float:
	if _time_left <= 0.0 or duration <= 0.0:
		return -1.0
	return _time_left / duration
