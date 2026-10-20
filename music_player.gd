extends Node
## Autoload "Music": background music playlist.
##
## Drop .ogg / .mp3 / .wav files into res://music/ and they are found automatically,
## or list them in `tracks`. Plays them shuffled (never the same twice in a row),
## fading between tracks. Keeps playing across level changes.

@export var tracks: Array[AudioStream] = []
@export var music_folder: String = "res://music"
@export var shuffle: bool = true
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var volume_db: float = -10.0
@export_range(0.0, 10.0, 0.1, "suffix:s") var fade_time: float = 2.0
## Silence between two tracks.
@export_range(0.0, 60.0, 0.5, "suffix:s") var gap: float = 3.0
@export var autoplay: bool = true

var current_index := -1

var _player := AudioStreamPlayer.new()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_player.bus = &"Music"
	add_child(_player)
	_player.finished.connect(_on_finished)
	_load_folder()
	if autoplay and not tracks.is_empty():
		play_next()


func _load_folder() -> void:
	if not DirAccess.dir_exists_absolute(music_folder):
		return
	for file in ResourceLoader.list_directory(music_folder):
		var path := music_folder.path_join(file)
		if file.get_extension().to_lower() in ["ogg", "mp3", "wav"]:
			var stream := load(path) as AudioStream
			if stream != null and not tracks.has(stream):
				tracks.append(stream)


## Starts the next track (random if `shuffle`), fading it in.
func play_next() -> void:
	if tracks.is_empty():
		return
	var index := (current_index + 1) % tracks.size()
	if shuffle and tracks.size() > 1:
		index = _rng.randi_range(0, tracks.size() - 2)
		if index >= current_index:
			index += 1  # skip the one that just played
	play_track(index)


func play_track(index: int) -> void:
	current_index = index
	_player.stream = tracks[index]
	# Tracks should not loop on their own: the playlist moves on instead.
	if "loop" in _player.stream:
		_player.stream.loop = false
	_player.volume_db = -60.0 if fade_time > 0.0 else volume_db
	_player.play()
	if fade_time > 0.0:
		create_tween().tween_property(_player, "volume_db", volume_db, fade_time)


func stop(fade := true) -> void:
	if fade and fade_time > 0.0:
		var tw := create_tween()
		tw.tween_property(_player, "volume_db", -60.0, fade_time)
		await tw.finished
	_player.stop()


func _on_finished() -> void:
	if gap > 0.0:
		await get_tree().create_timer(gap).timeout
	play_next()
