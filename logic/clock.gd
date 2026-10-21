@tool
class_name LogicClock
extends LogicNode
## Sends a pulse every `period` seconds; each pulse lasts `on_time` seconds.
## No inputs: always ticking. With inputs: ticks only while an input is on
## (and restarts from the beginning each time it gets enabled).

@export_range(0.05, 120.0, 0.05, "or_greater", "suffix:s") var period: float = 2.0:
	set(value):
		period = maxf(value, 0.05)
		queue_redraw()
@export_range(0.01, 120.0, 0.01, "or_greater", "suffix:s") var on_time: float = 0.5
## Where in the cycle the clock starts (0 = starts with a pulse).
@export_range(0.0, 120.0, 0.05, "or_greater", "suffix:s") var phase: float = 0.0

var _time := 0.0


func _start() -> void:
	_time = fmod(phase, period)


func _on_inputs_changed() -> void:
	pass  # handled every physics frame


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var enabled := inputs.is_empty() or any_on(inputs)
	if not enabled:
		_time = fmod(phase, period)
		set_output(false)
		return
	set_output(_time < on_time)
	_time = fmod(_time + delta, period)
	queue_redraw()


func _default_texture() -> Texture2D:
	return preload("res://logic/clock.webp")


func _label() -> PackedStringArray:
	return PackedStringArray(["CLOCK", "%ss / %ss" % [snappedf(period, 0.01), snappedf(on_time, 0.01)]])


func _progress() -> float:
	if not inputs.is_empty() and not any_on(inputs):
		return -1.0
	return _time / period
