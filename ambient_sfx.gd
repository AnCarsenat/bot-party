extends Node
## Autoload "AmbientSfx": plays a random sound from `sounds` at random intervals.
## Keeps playing across level changes.

@export var sounds: Array[AudioStream] = []
## Seconds between two sounds (picked at random between min and max).
@export_range(0.0, 600.0, 0.5, "suffix:s") var min_interval: float = 60.0
@export_range(0.0, 600.0, 0.5, "suffix:s") var max_interval: float = 180.0
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var volume_db: float = -9.0
## Random pitch variation, e.g. 0.1 = between 0.9x and 1.1x.
@export_range(0.0, 0.5, 0.01) var pitch_variation: float = 0.08
@export var enabled: bool = true

var _rng := RandomNumberGenerator.new()
var _last := -1
var _time_left := 0.0
var _player := AudioStreamPlayer.new()


func _ready() -> void:
	_rng.randomize()
	_player.max_polyphony = 3
	_player.bus = &"SFX"
	add_child(_player)
	_schedule()


func _process(delta: float) -> void:
	if not enabled or sounds.is_empty():
		return
	_time_left -= delta
	if _time_left <= 0.0:
		play_random()
		_schedule()


func play_random() -> void:
	if sounds.is_empty():
		return
	var index := _rng.randi_range(0, sounds.size() - 1)
	if sounds.size() > 1 and index == _last:
		index = (index + 1) % sounds.size()  # never the same sound twice in a row
	_last = index
	_player.stream = sounds[index]
	_player.volume_db = volume_db
	_player.pitch_scale = 1.0 + _rng.randf_range(-pitch_variation, pitch_variation)
	_player.play()


func _schedule() -> void:
	_time_left = _rng.randf_range(min_interval, maxf(min_interval, max_interval))
