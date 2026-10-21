extends CanvasLayer
## Autoload "Transition": fades to black, changes scene, fades back in.

@export var fade_time: float = 0.35

var _rect := ColorRect.new()
var _label := Label.new()
var _busy := false
var _queued := []


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect.color = Color(0.05, 0.05, 0.07, 0.0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_override("font", UiTheme.FONT_BOLD)
	_label.add_theme_font_size_override("font_size", 56)
	_label.add_theme_color_override("font_color", Color("ece9ee"))
	_label.modulate.a = 0.0
	add_child(_label)


## Fades out, optionally shows `message` for `message_time` seconds, loads `path`, fades in.
func change_scene(path: String, message := "", message_time := 1.5) -> void:
	var net := get_tree().root.get_node_or_null("Net")
	if net and not net.allow_scene_change(path, message, message_time):
		return  # online client: the host decides
	if _busy:
		if net and net.applying():
			_queued = [path, message, message_time]  # the host moved on during our fade
		return
	_busy = true
	var tw := create_tween()
	tw.tween_property(_rect, "color:a", 1.0, fade_time)
	await tw.finished
	if message != "":
		_label.text = message
		tw = create_tween()
		tw.tween_property(_label, "modulate:a", 1.0, 0.25)
		await get_tree().create_timer(message_time).timeout
		tw = create_tween()
		tw.tween_property(_label, "modulate:a", 0.0, 0.25)
		await tw.finished
	get_tree().paused = false
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	tw = create_tween()
	tw.tween_property(_rect, "color:a", 0.0, fade_time)
	await tw.finished
	_busy = false
	if not _queued.is_empty():
		var q := _queued
		_queued = []
		_busy = false
		net = get_tree().root.get_node_or_null("Net")
		if net:
			net._applying = true
		change_scene(q[0], q[1], q[2])
		if net:
			net._applying = false


func reload(message := "") -> void:
	var scene := get_tree().current_scene
	if scene and scene.scene_file_path != "":
		change_scene(scene.scene_file_path, message)
