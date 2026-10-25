extends CanvasLayer
## Online chat. C (or /) opens a line to type in, Enter sends, Esc closes.
## Messages show at the bottom left for a while (all the recent ones while
## typing). While typing, this computer's players don't move (net.gd).

const SHOW_FOR := 8.0     # seconds a message stays when the chat is closed
const KEEP := 12          # messages shown while typing
const OPEN_KEYS := [KEY_C, KEY_SLASH]

var _lines: Array = []    # [who ("" = the game), text, time]
var _panel: PanelContainer
var _list: VBoxContainer
var _input: LineEdit
var _shown := ""


func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.offset_left = 16
	_panel.offset_right = 576
	_panel.offset_top = -330
	_panel.offset_bottom = -64
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiTheme.MARBLE, 0.0)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_END
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(col)
	_list = VBoxContainer.new()
	_list.alignment = BoxContainer.ALIGNMENT_END
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_list)
	_input = LineEdit.new()
	_input.placeholder_text = "Say something  (Enter: send, Esc: close)"
	_input.max_length = 200
	_input.add_theme_font_override("font", UiTheme.FONT_MEDIUM)
	_input.add_theme_font_size_override("font_size", 22)
	var box := StyleBoxFlat.new()
	box.bg_color = Color.WHITE
	box.border_color = UiTheme.INK
	box.set_border_width_all(3)
	box.set_content_margin_all(6)
	_input.add_theme_stylebox_override("normal", box)
	_input.add_theme_stylebox_override("focus", box)
	_input.add_theme_color_override("font_color", UiTheme.INK)
	_input.add_theme_color_override("font_placeholder_color", UiTheme.MUTED)
	_input.add_theme_color_override("caret_color", UiTheme.INK)
	_input.text_submitted.connect(_send)
	_input.gui_input.connect(func(e):
		if e is InputEventKey and e.pressed and e.physical_keycode == KEY_ESCAPE:
			close()
			_input.accept_event())
	_input.focus_exited.connect(func(): if _input.visible: close.call_deferred())
	_input.hide()
	col.add_child(_input)
	var net := get_node("/root/Net")
	net.chat_received.connect(add)


## Where the chat shows: a rectangle of the screen (the online lobby puts it
## under the computers' boxes), or null for the usual bottom left corner.
func dock(rect) -> void:
	if rect is Rect2:
		_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_panel.position = rect.position
		_panel.size = rect.size
		_panel.custom_minimum_size = Vector2.ZERO
	else:
		_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_panel.offset_left = 16
		_panel.offset_right = 576
		_panel.offset_top = -330
		_panel.offset_bottom = -64
	_docked = rect is Rect2
	_shown = ""


var _docked := false


func is_open() -> bool:
	return _input.visible


func open() -> void:
	var net := get_node("/root/Net")
	if not net.is_online() or is_open():
		return
	_input.show()
	_input.clear()
	_input.grab_focus()
	net.typing = true
	_shown = ""


func close() -> void:
	_input.hide()
	_input.release_focus()
	var net := get_node_or_null("/root/Net")
	if net:
		net.typing = false
	_shown = ""


func add(who: String, text: String) -> void:
	_lines.append([who, text, Time.get_ticks_msec() / 1000.0])
	if _lines.size() > 50:
		_lines.pop_front()
	_shown = ""


func clear() -> void:
	_lines.clear()
	_shown = ""


func _send(text: String) -> void:
	get_node("/root/Net").chat(text)
	close()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo) or is_open():
		return
	if not get_node("/root/Net").is_online():
		return
	var console := get_node_or_null("/root/Console")
	if console and console.is_open():
		return
	var k: Key = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if k in OPEN_KEYS and not _key_taken(k):
		open()
		get_viewport().set_input_as_handled()


## A key some player plays with doesn't open the chat.
func _key_taken(k: Key) -> bool:
	for action in InputMap.get_actions():
		if action.begins_with("k") or action.begins_with("p"):
			for e in InputMap.action_get_events(action):
				if e is InputEventKey and (e.physical_keycode == k or e.keycode == k):
					return true
	return false


func _process(_d: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var show := []
	var keep := 3 if _docked else KEEP
	for l in _lines.slice(-keep):
		var age: float = now - l[2]
		if is_open() or age < SHOW_FOR:
			show.append([l, 1.0 if is_open() else clampf(SHOW_FOR - age, 0.0, 1.0)])
	var key := str(show.map(func(s): return [s[0][2], snappedf(s[1], 0.1)])) + str(is_open())
	if key == _shown:
		return
	_shown = key
	for c in _list.get_children():
		c.queue_free()
	for s in show:
		var l: Array = s[0]
		var row := RichTextLabel.new()
		row.bbcode_enabled = true
		row.fit_content = true
		row.scroll_active = false
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_font_override("normal_font", UiTheme.FONT_MEDIUM)
		row.add_theme_font_override("bold_font", UiTheme.FONT_BOLD)
		row.add_theme_font_size_override("normal_font_size", 19 if _docked else 22)
		row.add_theme_font_size_override("bold_font_size", 19 if _docked else 22)
		row.add_theme_color_override("default_color", UiTheme.INK)
		row.add_theme_color_override("font_outline_color", UiTheme.MARBLE)
		row.add_theme_constant_override("outline_size", 6)
		var text := str(l[1]).replace("[", "[lb]")
		if str(l[0]) == "":
			row.text = "[color=#5c5a68]%s[/color]" % text
		else:
			row.text = "[b]%s:[/b] %s" % [str(l[0]).replace("[", "[lb]"), text]
		row.modulate.a = s[1]
		_list.add_child(row)
