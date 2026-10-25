extends CanvasLayer
## Online chat (the console, for commands, is separate: console.gd).
## C or / opens it, Enter sends, Esc closes, Up / Down: what you typed before.
## Messages show at the bottom left for a while: small and see-through in the
## levels, under the boxes in the online lobby. In an online party a faint bar
## invites you to chat. While typing, this computer's players stand still (net.gd).

const SHOW_FOR := 8.0     # seconds a message stays when the chat is closed
const KEEP := 50
const OPEN_KEYS := [KEY_C, KEY_SLASH]

var _lines: Array = []    # [who ("" = the game), text, time]
var _panel: Control
var _scroll: ScrollContainer
var _list: VBoxContainer
var _input: LineEdit
var _bar: Label           # "C  Chat..." when closed (online party)
var _shown := ""
var _docked := false
var _dock_rect := Rect2()
var _history: Array[String] = []
var _history_pos := 0


func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = Control.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.alignment = BoxContainer.ALIGNMENT_END
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_list)
	_input = LineEdit.new()
	_input.placeholder_text = "Say something  (Enter: send, Esc: close)"
	_input.max_length = 200
	_input.add_theme_font_override("font", UiTheme.FONT_MEDIUM)
	_input.add_theme_font_size_override("font_size", 18)
	var box := StyleBoxFlat.new()
	box.bg_color = Color.WHITE
	box.border_color = UiTheme.INK
	box.set_border_width_all(3)
	box.set_content_margin_all(4)
	_input.add_theme_stylebox_override("normal", box)
	_input.add_theme_stylebox_override("focus", box)
	_input.add_theme_color_override("font_color", UiTheme.INK)
	_input.add_theme_color_override("font_placeholder_color", UiTheme.MUTED)
	_input.add_theme_color_override("caret_color", UiTheme.INK)
	_input.text_submitted.connect(_send)
	_input.gui_input.connect(_on_key)
	_input.focus_exited.connect(func(): if _input.visible: close.call_deferred())
	_input.hide()
	_panel.add_child(_input)
	_bar = Label.new()
	_bar.text = "C  Chat..."
	_bar.add_theme_font_override("font", UiTheme.FONT_MEDIUM)
	_bar.add_theme_font_size_override("font_size", 16)
	_bar.add_theme_color_override("font_color", Color(UiTheme.INK, 0.6))
	var faint := StyleBoxFlat.new()
	faint.bg_color = Color(1, 1, 1, 0.35)
	faint.border_color = Color(UiTheme.INK, 0.35)
	faint.set_border_width_all(2)
	faint.set_content_margin_all(5)
	_bar.add_theme_stylebox_override("normal", faint)
	_bar.hide()
	_panel.add_child(_bar)
	_layout()
	get_viewport().size_changed.connect(_layout)
	get_node("/root/Net").chat_received.connect(add)


## Where the chat shows: a rectangle of the screen (the online lobby puts it
## under the computers' boxes), or null for the usual bottom left corner.
func dock(rect) -> void:
	_docked = rect is Rect2
	if _docked:
		_dock_rect = rect
	_layout()
	_shown = ""


func _layout() -> void:
	var screen := get_viewport().get_visible_rect().size
	# Small: a corner of the screen (a bit taller while typing).
	var h := 230.0 if is_open() else 150.0
	var r := _dock_rect if _docked else Rect2(16, screen.y - h - 46, 380, h)
	_panel.position = r.position
	_panel.size = r.size
	var input_h := 32.0
	_input.position = Vector2(0, r.size.y - input_h)
	_input.size = Vector2(r.size.x, input_h)
	_bar.position = Vector2(0, r.size.y - 28)
	_bar.size = Vector2(120, 26)
	var bottom := r.size.y - (input_h + 6 if is_open() or _bar.visible else 0.0)
	_scroll.position = Vector2.ZERO
	_scroll.size = Vector2(r.size.x, maxf(0.0, bottom))


func is_open() -> bool:
	return _input.visible


## Opens the chat (online), `start` already typed.
func open(start := "") -> void:
	var net := get_node("/root/Net")
	if is_open() or not net.is_online():
		return
	_input.show()
	_input.text = start
	_input.caret_column = start.length()
	_input.grab_focus()
	_history_pos = _history.size()
	net.typing = true
	_layout()
	_shown = ""


func close() -> void:
	if not _input.visible:
		return
	_input.hide()
	_input.release_focus()
	var net := get_node_or_null("/root/Net")
	if net:
		net.typing = false
	_layout()
	_shown = ""


## A message from someone ("" = the game itself).
func add(who: String, text: String) -> void:
	_lines.append([who, text, _now()])
	if _lines.size() > KEEP:
		_lines.pop_front()
	_shown = ""


func clear() -> void:
	_lines.clear()
	_shown = ""


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _send(text: String) -> void:
	text = text.strip_edges()
	if text != "":
		_history.append(text)
		get_node("/root/Net").chat(text)
	close()


func _on_key(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed):
		return
	match e.keycode:
		KEY_ESCAPE:
			close()
		KEY_UP:
			_recall(-1)
		KEY_DOWN:
			_recall(1)
		_:
			return
	_input.accept_event()


func _recall(step: int) -> void:
	if _history.is_empty():
		return
	_history_pos = clampi(_history_pos + step, 0, _history.size())
	_input.text = _history[_history_pos] if _history_pos < _history.size() else ""
	_input.caret_column = _input.text.length()


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


## In a level (not the menus): small and see-through.
func _in_level() -> bool:
	var s := get_tree().current_scene
	return s != null and not s.scene_file_path.ends_with("main_menu.tscn")


func _process(_d: float) -> void:
	var net := get_node("/root/Net")
	var in_level := _in_level()
	# The faint bar: online, in a party, chat closed.
	var bar: bool = net.is_online() and not is_open() and not _docked and in_level \
		and get_tree().current_scene.has_node("PartyController")
	if bar != _bar.visible:
		_bar.visible = bar
		_layout()
	var now := _now()
	var show := []
	var keep := 3 if _docked else (12 if is_open() else 5)
	for l in _lines.slice(-keep):
		var age: float = now - l[2]
		if is_open() or age < SHOW_FOR:
			show.append([l, 1.0 if is_open() else clampf(SHOW_FOR - age, 0.0, 1.0)])
	var key := str(show.map(func(s): return [s[0][2], snappedf(s[1], 0.1)])) + str([is_open(), in_level, _docked])
	if key == _shown:
		return
	_shown = key
	for c in _list.get_children():
		c.queue_free()
	var size := 19 if _docked else (15 if in_level and not is_open() else 17)
	var see_through := 0.75 if in_level and not is_open() else 1.0
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
		row.add_theme_font_size_override("normal_font_size", size)
		row.add_theme_font_size_override("bold_font_size", size)
		row.add_theme_color_override("default_color", UiTheme.INK)
		row.add_theme_color_override("font_outline_color", UiTheme.MARBLE)
		row.add_theme_constant_override("outline_size", 5)
		var who := str(l[0])
		if who == "":
			row.text = "[color=#5c5a68]%s[/color]" % str(l[1]).replace("[", "[lb]")
		else:
			row.text = "[b]%s:[/b] %s" % [who.replace("[", "[lb]"), str(l[1]).replace("[", "[lb]")]
		row.modulate.a = s[1] * see_through
		_list.add_child(row)
	# Newest at the bottom.
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
