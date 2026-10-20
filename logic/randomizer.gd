@tool
class_name Randomizer
extends LogicNode
## Each time its input gets pulsed (turns on), it has `chance` probability
## of sending its own pulse of `pulse_length` seconds.

@export_range(0.0, 1.0, 0.01) var chance: float = 0.5:
	set(value):
		chance = value
		queue_redraw()
@export_range(0.01, 60.0, 0.01, "or_greater", "suffix:s") var pulse_length: float = 0.5
## 0 = different every run. Any other value = same sequence every run (handy to test).
@export var random_seed: int = 0

var _rng := RandomNumberGenerator.new()
var _level := false
var _time_left := 0.0
var _last_roll_hit := false
var _flash := 0.0


func _start() -> void:
	if random_seed != 0:
		_rng.seed = random_seed
	else:
		_rng.randomize()


func _on_inputs_changed() -> void:
	var level := any_on(inputs)
	if level and not _level:
		_last_roll_hit = _rng.randf() < chance
		_flash = 0.3
		if _last_roll_hit:
			_time_left = pulse_length
			set_output(true)
	_level = level


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _flash > 0.0:
		_flash -= delta
		queue_redraw()
	if _time_left > 0.0:
		_time_left -= delta
		if _time_left <= 0.0:
			set_output(false)


func _default_texture() -> Texture2D:
	return preload("res://randomizer.webp")


func _label() -> PackedStringArray:
	var detail := "%d%%" % roundi(chance * 100.0)
	if _flash > 0.0:
		detail += "  HIT" if _last_roll_hit else "  miss"
	return PackedStringArray(["RANDOM", detail])
