extends Control
## Title screen. The menu is one of the game's machines: every option sits on a
## pressure button, and a live cable runs from the machine to the selected one.
##   Up/Down (arrows or any player's keys) move, Enter / Space / any jump key
##   chooses, Left/Right change a setting, Esc goes back.
## "Players" is the lobby: each player presses their own jump key to join.

const TITLE := "Bot Party"
const VERSION := "v0.22"
const NAV_REPEAT := 0.16  # seconds between moves when a pad stick is held
const LIST_TOP := 24.0
const ROW_STEP := 66.0     # row height + separation
const ROWS_VISIBLE := 6

const TEX_BASE := preload("res://objects/button_base.webp")
const TEX_CAP := preload("res://objects/button_cap.webp")
const TEX_PLAYER_BODY := preload("res://player/player_body.webp")
const TEX_PLAYER_FACE := preload("res://player/player_face.webp")
const MACHINES := {
	"main": preload("res://logic/gate.webp"), "campaign": preload("res://logic/delayer.webp"),
	"party": preload("res://logic/randomizer.webp"), "settings": preload("res://logic/prolongator.webp"),
}

var _screen := "main"
var _items: Array = []      # [{text, on_accept, on_left, on_right, enabled, info, key}]
var _index := 0
var _rows: Array[Control] = []
var _list: VBoxContainer
var _clip: Control
var _heading: Label
var _machine: TextureRect
var _info: Label
var _cable: _Cable
var _lobby: _Lobby
var _footer: HBoxContainer
var _hint: Label
var _nav_cooldown := 0.0


func _ready() -> void:
	theme = UiTheme.make()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_layout()
	GameState.joined_changed.connect(func(): _refresh_footer(); if _screen == "players": _lobby.queue_redraw())
	Net.status.connect(func(t): _hint.text = t)
	Net.connected.connect(func(): if _screen in ["online", "servers"]: _show("online_lobby"))
	Net.failed.connect(func(reason):
		if is_inside_tree() and _screen in ["online", "servers", "online_lobby"]:
			_show("online")
			_hint.text = reason)
	Net.roster_changed.connect(func():
		if _screen == "online_lobby":
			_show("online_lobby", true))
	Net.servers_listed.connect(_on_servers)
	# Coming back from a level while online: straight to the online lobby.
	_show("online_lobby" if Net.is_online() else "main")


# --- Layout -------------------------------------------------------------------

func _build_layout() -> void:
	var bg := TextureRect.new()
	bg.texture = preload("res://levels/tile.webp")
	bg.stretch_mode = TextureRect.STRETCH_TILE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.modulate = Color(0.93, 0.92, 0.95)
	bg.size = Vector2(4000, 3000)
	bg.scale = Vector2(2.5, 2.5)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_cable = _Cable.new()
	_cable.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cable.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cable)

	var title := Label.new()
	title.text = TITLE
	title.position = Vector2(64, 36)
	title.add_theme_font_override("font", UiTheme.FONT_BOLD)
	title.add_theme_font_size_override("font_size", 84)
	add_child(title)

	_heading = Label.new()
	_heading.position = Vector2(70, 136)
	_heading.add_theme_font_override("font", UiTheme.FONT_MEDIUM)
	_heading.add_theme_font_size_override("font_size", 28)
	_heading.add_theme_color_override("font_color", UiTheme.MUTED)
	add_child(_heading)

	# The option list scrolls inside this box when it's too long (Party > Items).
	_clip = Control.new()
	_clip.position = Vector2(40, 172)
	_clip.size = Vector2(760, 520)
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)
	_list = VBoxContainer.new()
	_list.position = Vector2(16, LIST_TOP)
	_list.add_theme_constant_override("separation", 2)
	_clip.add_child(_list)

	_machine = TextureRect.new()
	_machine.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_machine.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_machine.size = Vector2(160, 160)
	_machine.anchor_left = 1.0
	_machine.anchor_right = 1.0
	_machine.offset_left = -440
	_machine.offset_right = -280
	_machine.offset_top = 150
	_machine.offset_bottom = 310
	add_child(_machine)

	_info = Label.new()
	_info.anchor_left = 1.0
	_info.anchor_right = 1.0
	_info.offset_left = -520
	_info.offset_right = -120
	_info.offset_top = 330
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", 24)
	add_child(_info)

	_lobby = _Lobby.new()
	_lobby.anchor_left = 1.0
	_lobby.anchor_right = 1.0
	_lobby.offset_left = -700
	_lobby.offset_right = -60
	_lobby.offset_top = 150
	_lobby.offset_bottom = 560
	_lobby.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lobby)

	# Joined players, top-right like the in-game HUD.
	_footer = HBoxContainer.new()
	_footer.anchor_left = 1.0
	_footer.anchor_right = 1.0
	_footer.offset_left = -460
	_footer.offset_right = -48
	_footer.offset_top = 52
	_footer.alignment = BoxContainer.ALIGNMENT_END
	_footer.add_theme_constant_override("separation", 8)
	add_child(_footer)

	_hint = Label.new()
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = 64
	_hint.offset_top = -48
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_color", UiTheme.MUTED)
	add_child(_hint)

	var version := Label.new()
	version.text = VERSION
	version.anchor_left = 1.0
	version.anchor_top = 1.0
	version.anchor_right = 1.0
	version.anchor_bottom = 1.0
	version.offset_left = -90
	version.offset_top = -44
	version.add_theme_font_size_override("font_size", 16)
	version.add_theme_color_override("font_color", UiTheme.MUTED)
	add_child(version)


# --- Screens ------------------------------------------------------------------

func _show(screen: String, keep_index := false) -> void:
	_screen = screen
	_items.clear()
	match screen:
		"main":
			_items = [
				{"text": "Campaign", "on_accept": func(): _show("campaign"), "info": "%s campaign\nIt changes with the number of players." % GameState.campaign().name},
				{"text": "Party", "on_accept": func(): _show("party"), "info": "Place traps. Reach the flag."},
				{"text": "Online", "on_accept": func(): _show("online"), "info": "Play with friends on other computers."},
				{"text": "Players", "on_accept": func(): _show("players")},
				{"text": "Settings", "on_accept": func(): _show("settings")},
			]
			if OS.get_name() != "Web":
				_items.append({"text": "Quit", "on_accept": func(): get_tree().quit()})
		"campaign":
			# One campaign per group size: this is the one for whoever has joined.
			for i in GameState.levels.size():
				var locked := i >= GameState.unlocked
				_items.append({"text": "%d  %s" % [i + 1, GameState.level_name(i)], "enabled": not locked,
					"on_accept": func(): _start(func(): GameState.start_level(i)), "info": "Locked" if locked else ""})
			_items.append({"text": "Back", "on_accept": func(): _back()})
		"party":
			_items.append({"text": "New party", "on_accept": func(): _start(func(): Party.new_game()),
				"info": "First to %d wins." % Party.TARGET_SCORE})
			if Party.has_save():
				_items.append({"text": "Continue", "on_accept": func(): _start(func(): Party.continue_game()), "info": Party.describe_save()})
			_items.append({"text": "Items", "on_accept": func(): _show("party_items"), "info": "Which items show up, and how often."})
			_items.append({"text": "Back", "on_accept": func(): _back()})
		"party_items":
			for id in Party.ITEMS:
				var def: Dictionary = Party.ITEMS[id]
				_items.append({"text": def.name, "icon": load(def.icon), "size": 34, "info": "Left / right: how often\nJump: on / off",
					"value": func(): return _item_value(id),
					"on_left": func(): _set_item_weight(id, Party.weight(id) - 1),
					"on_right": func(): _set_item_weight(id, Party.weight(id) + 1),
					"on_accept": func(): _set_item_weight(id, 0 if Party.weight(id) > 0 else int(def.get("weight", 10)))})
			_items.append({"text": "Reset", "on_accept": func(): Party.reset_weights(); _refresh_info(), "info": "Back to the default odds."})
			_items.append({"text": "Back", "on_accept": func(): _back()})
		"players":
			_items = [{"text": "Done", "on_accept": func(): _back()}]
		"online":
			_items = [
				{"text": "Host public game", "on_accept": func(): _start(func(): _host(true)),
					"info": "Listed on the server list. Friends can join from anywhere."},
				{"text": "Host private game", "on_accept": func(): _start(func(): _host(false)),
					"info": "Not listed: friends join with your address (UDP port %d)." % Net.GAME_PORT},
				{"text": "Server list", "on_accept": func(): _listing = true; _servers.clear(); _show("servers"); Net.list_servers(),
					"info": "Games hosted by others." if Net.lobby_url != "" else "Set the server list address first."},
				{"text": "Join by address", "on_accept": func(): _start(func(): _edit_text("Host address (ip or ip:port)", _last_address,
					func(t): _last_address = t; _hint.text = "Connecting..."; Net.join_address(t))), "info": "Type the host's address."},
				{"text": "Name: " + Net.player_name, "on_accept": func(): _edit_text("Your name", Net.player_name, _set_name),
					"size": 34, "info": "Shown to the others."},
				{"text": "List: " + (Net.lobby_url if Net.lobby_url != "" else "not set"), "on_accept": func(): _edit_text("Server list address (your VPS)", Net.lobby_url, _set_lobby_url),
					"size": 34, "info": "Address of the server list (server/lobby_server.py)."},
				{"text": "Back", "on_accept": func(): _back()},
			]
		"servers":
			if _servers.is_empty():
				_items.append({"text": "Searching..." if _listing else "No games found", "enabled": false})
			for e in _servers:
				var entry: Dictionary = e
				var full: bool = int(entry.players) >= int(entry.max)
				_items.append({"text": "%s  %d/%d" % [entry.name, int(entry.players), int(entry.max)], "size": 34,
					"enabled": not full, "info": "%s%s" % [str(entry.mode).capitalize(), "\n(relay available)" if entry.get("relay", false) else ""],
					"on_accept": func(): _start(func(): _hint.text = "Connecting..."; Net.join_listed(entry, entry.you))})
			_items.append({"text": "Refresh", "on_accept": func(): _listing = true; _servers.clear(); _show("servers", true); Net.list_servers()})
			_items.append({"text": "Back", "on_accept": func(): _back()})
		"online_lobby":
			if Net.is_host():
				_items = [
					{"text": "Campaign", "on_accept": func(): _show("campaign")},
					{"text": "Party", "on_accept": func(): Party.new_game()},
					{"text": "Close game", "on_accept": func(): Net.leave(); _show("online")},
				]
			else:
				_items = [{"text": "Leave", "on_accept": func(): Net.leave(); _show("online")}]
		"settings":
			_items = [
				{"text": "Music", "key": "music_volume", "on_left": func(): _bump("music_volume", -0.1), "on_right": func(): _bump("music_volume", 0.1), "on_accept": func(): _bump("music_volume", 0.1, true), },
				{"text": "Sounds", "key": "sfx_volume", "on_left": func(): _bump("sfx_volume", -0.1), "on_right": func(): _bump("sfx_volume", 0.1), "on_accept": func(): _bump("sfx_volume", 0.1, true)},
				{"text": "Fullscreen", "key": "fullscreen", "on_left": func(): _toggle("fullscreen"), "on_right": func(): _toggle("fullscreen"), "on_accept": func(): _toggle("fullscreen")},
				{"text": "Back", "on_accept": func(): _back()},
			]
	_heading.text = {"main": "", "campaign": _campaign_heading(), "party": "Party", "party_items": "Party items", "players": "Players",
		"settings": "Settings", "online": "Online", "servers": "Server list", "online_lobby": _online_heading()}[screen]
	if not keep_index:
		_index = 0
	_index = clampi(_index, 0, _items.size() - 1)
	while not _items[_index].get("enabled", true):
		_index = (_index + 1) % _items.size()
	var lobby := screen == "players" or screen == "online_lobby"
	_lobby.visible = lobby
	_machine.visible = not lobby
	_info.visible = not lobby
	_machine.texture = MACHINES.get(screen, MACHINES.party if screen == "party_items" else MACHINES.main)
	_rebuild_list()
	_refresh_info()
	_refresh_footer()
	_hint.text = "Jump to join or leave" if lobby else ""
	if screen == "online_lobby" and Net.is_client():
		_hint.text = "Jump to join or leave.  Waiting for the host to start."
	_cable.snap = true


func _rebuild_list() -> void:
	for r in _rows:
		r.queue_free()
	_rows.clear()
	for i in _items.size():
		var row := _Row.new()
		row.menu = self
		row.index = i
		row.custom_minimum_size = Vector2(520, 64)
		row.mouse_entered.connect(func(): _select(i))
		row.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: _select(i); _accept())
		_list.add_child(row)
		_rows.append(row)


func _refresh_info() -> void:
	if not _items.is_empty():
		_info.text = _items[_index].get("info", "")
		if _items[_index].has("icon"):
			_machine.texture = _items[_index].icon
		elif _screen == "party_items":
			_machine.texture = MACHINES.party
	for r in _rows:
		r.queue_redraw()
	# Scroll so the selected option stays in view.
	var first := clampi(_index - ROWS_VISIBLE / 2, 0, maxi(0, _items.size() - ROWS_VISIBLE))
	var y := LIST_TOP - first * ROW_STEP
	if _list.position.y != y:
		create_tween().tween_property(_list, "position:y", y, 0.12)
	# Only the rows in the window are shown (no half-cut rows at the edges).
	for k in _rows.size():
		var shown := k >= first and k < first + ROWS_VISIBLE
		_rows[k].modulate.a = 1.0 if shown else 0.0


## Party > Items row value: chance in % (or Off) plus a bar for the weight.
# --- Online -----------------------------------------------------------------------

var _servers: Array = []
var _listing := false
var _last_address := ""
var _editor: PanelContainer


func _host(public: bool) -> void:
	if Net.host(public) == OK:
		_show("online_lobby")


func _set_name(t: String) -> void:
	Net.player_name = t.strip_edges().left(16) if t.strip_edges() != "" else "Player"
	Net.save_config()
	_show("online", true)


func _set_lobby_url(t: String) -> void:
	Net.lobby_url = t.strip_edges()
	Net.save_config()
	_show("online", true)


func _on_servers(list: Array) -> void:
	_listing = false
	_servers = list
	if _screen == "servers":
		_show("servers", true)
		if list.is_empty():
			_hint.text = "Server list unreachable or empty" if Net.lobby_url != "" else "Set the server list address first"


func _online_heading() -> String:
	if Net.is_host():
		return "Your game: %d / %d players" % [Net.roster.size(), GameState.MAX_PLAYERS]
	return ("In %s's game" % Net.name_of(1)) if Net.name_of(1) != "" else "Online"


## Small text box for names and addresses. Enter confirms, Esc cancels.
func _edit_text(title: String, initial: String, done: Callable) -> void:
	_close_editor()
	_editor = PanelContainer.new()
	_editor.set_anchors_preset(Control.PRESET_CENTER)
	_editor.offset_left = -330
	_editor.offset_right = 330
	_editor.offset_top = -80
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_editor.add_child(col)
	var l := Label.new()
	l.text = title
	col.add_child(l)
	var edit := LineEdit.new()
	edit.text = initial
	edit.custom_minimum_size = Vector2(600, 48)
	edit.add_theme_font_size_override("font_size", 28)
	col.add_child(edit)
	var hint := Label.new()
	hint.text = "Enter: OK   Esc: cancel"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", UiTheme.MUTED)
	col.add_child(hint)
	add_child(_editor)
	edit.grab_focus()
	edit.caret_column = initial.length()
	edit.text_submitted.connect(func(t):
		_close_editor()
		done.call(t))
	edit.gui_input.connect(func(e):
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			_close_editor()
			get_viewport().set_input_as_handled())


func _close_editor() -> void:
	if _editor:
		_editor.queue_free()
		_editor = null


func _campaign_heading() -> String:
	var c: Dictionary = GameState.campaign()
	return "Campaign: %s" % c.name


func _item_value(id: String) -> Dictionary:
	var w := Party.weight(id)
	if w == 0:
		return {"text": "Off", "bar": 0.0}
	return {"text": "%d%%" % roundi(Party.chance(id) * 100.0), "bar": float(w) / Party.MAX_WEIGHT}


func _set_item_weight(id: String, w: int) -> void:
	Party.set_weight(id, w)
	_refresh_info()


func _refresh_footer() -> void:
	for c in _footer.get_children():
		c.queue_free()
	for slot in GameState.joined:
		var chip := UiTheme.player_chip(slot)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_footer.add_child(chip)


## Where the cable should end: the selected row's button cap (in our coordinates).
func cable_target() -> Vector2:
	if _screen == "players" or _rows.is_empty() or not is_instance_valid(_rows[_index]):
		return Vector2.INF
	var r: _Row = _rows[_index]
	return r.global_position - global_position + r.socket()


func cable_start() -> Vector2:
	if not _machine.visible:
		return Vector2.INF
	return _machine.global_position - global_position + Vector2(10, 100)


# --- Settings helpers -----------------------------------------------------------

func _bump(key: String, delta: float, wrap := false) -> void:
	var v: float = GameState.settings[key] + delta
	if wrap and v > 1.001:
		v = 0.0
	GameState.settings[key] = clampf(snappedf(v, 0.1), 0.0, 1.0)
	GameState.apply_settings()
	GameState.save_settings()
	_refresh_info()


func _toggle(key: String) -> void:
	GameState.settings[key] = not GameState.settings[key]
	GameState.apply_settings()
	GameState.save_settings()
	_refresh_info()


# --- Input --------------------------------------------------------------------

func _start(action: Callable) -> void:
	if GameState.joined.is_empty():
		_show("players")
		return
	action.call()


func _back() -> void:
	if _screen == "campaign" and Net.is_online():
		_show("online_lobby")
		return
	if _screen == "online_lobby":
		return  # leave with the Leave / Close option
	if _screen == "servers":
		_show("online")
		_select(2)
		return
	if _screen == "party_items":
		_show("party")
		_select(_items.size() - 2)  # "Items"
		return
	var back_to := {"campaign": 0, "party": 1, "online": 2, "players": 3, "settings": 4}
	var idx: int = back_to.get(_screen, 0)
	_show("main")
	_select(idx)


func _select(i: int) -> void:
	if i == _index or i < 0 or i >= _items.size() or not _items[i].get("enabled", true):
		return
	_index = i
	_refresh_info()


func _move(dir: int) -> void:
	var i := _index
	for k in _items.size():
		i = (i + dir + _items.size()) % _items.size()
		if _items[i].get("enabled", true):
			break
	_select(i)


func _accept() -> void:
	var item: Dictionary = _items[_index]
	if item.get("enabled", true) and item.has("on_accept"):
		if _index < _rows.size():
			_rows[_index].press()
		item.on_accept.call()


func _process(delta: float) -> void:
	_nav_cooldown = maxf(0.0, _nav_cooldown - delta)


## Returns the player slot (1-8) whose `suffix` action this event is, or 0.
func _player_action(event: InputEvent, suffix: String) -> int:
	for slot in range(1, GameState.MAX_PLAYERS + 1):
		var a := "p%d_%s" % [slot, suffix]
		if InputMap.has_action(a) and event.is_action_pressed(a, false, true):
			return slot
	return 0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		return
	var stick := event is InputEventJoypadMotion
	if stick and _nav_cooldown > 0.0:
		return

	if _editor:
		return
	if _screen == "online_lobby":
		var who := _player_action(event, "action_1")
		if who:
			if who in Net.my_slots().values():
				Net.request_leave(who)
			else:
				Net.request_join(who)
			_handled(stick)
			return
	if _screen == "players":
		var toggler := _player_action(event, "action_1")
		if toggler:
			if GameState.is_joined(toggler):
				GameState.leave(toggler)
			else:
				GameState.join(toggler)
				_lobby.joined_now(toggler)
			_handled(stick); return
		var enter: bool = event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]
		if enter or event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
			_back()
			_handled(stick)
		return

	if event.is_action_pressed("ui_up", true) or _player_action(event, "move_up"):
		_move(-1); _handled(stick)
	elif event.is_action_pressed("ui_down", true) or _player_action(event, "move_down"):
		_move(1); _handled(stick)
	elif event.is_action_pressed("ui_left", true) or _player_action(event, "move_left"):
		if _items[_index].has("on_left"): _items[_index].on_left.call()
		_handled(stick)
	elif event.is_action_pressed("ui_right", true) or _player_action(event, "move_right"):
		if _items[_index].has("on_right"): _items[_index].on_right.call()
		_handled(stick)
	elif event.is_action_pressed("ui_accept") or _player_action(event, "action_1"):
		_accept(); _handled(stick)
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		if _screen != "main":
			_back()
		_handled(stick)


func _handled(stick: bool) -> void:
	if stick:
		_nav_cooldown = NAV_REPEAT
	get_viewport().set_input_as_handled()


# --- Drawing pieces ----------------------------------------------------------------

## One menu option: a pressure button and its name (plus a value for settings).
class _Row extends Control:
	var menu
	var index := 0
	var _press := 0.0

	func press() -> void:
		_press = 1.0

	const TEXT_X := 92.0
	const VALUE_X := 400.0
	const TEXT_SIZE := 44

	## Where the cable plugs in: just after the option's name.
	func socket() -> Vector2:
		var item: Dictionary = menu._items[index]
		var w := UiTheme.FONT_BOLD.get_string_size(item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, item.get("size", TEXT_SIZE)).x
		if item.has("value"):
			return Vector2(VALUE_X + 225.0, 34)
		if item.has("key"):
			return Vector2(420.0 + (190.0 if typeof(GameState.settings[item.key]) != TYPE_BOOL else 70.0), 34)
		return Vector2(TEXT_X + 10.0 + w + 26.0, 34)

	func _process(delta: float) -> void:
		if _press > 0.0:
			_press = maxf(0.0, _press - delta * 4.0)
			queue_redraw()

	func _draw() -> void:
		var item: Dictionary = menu._items[index]
		var selected: bool = index == menu._index
		var enabled: bool = item.get("enabled", true)
		# Button: the cap sinks when selected, a bit more when chosen.
		var sink := (6.0 if selected else 0.0) + 4.0 * _press
		var cap_color: Color = UiTheme.RED if enabled else Color("b8b5c0")
		if selected:
			cap_color = cap_color.darkened(0.15)
		draw_texture_rect(TEX_CAP, Rect2(Vector2(4, -22 + sink), Vector2(64, 64)), false, cap_color)
		draw_texture_rect(TEX_BASE, Rect2(Vector2(4, -22), Vector2(64, 64)), false)
		# Name.
		var font: Font = UiTheme.FONT_BOLD if selected else UiTheme.FONT_MEDIUM
		var color: Color = UiTheme.INK if enabled else Color("9a97a6")
		if not selected and enabled:
			color = Color("3a3844")
		var x := TEXT_X + (10.0 if selected else 0.0)
		draw_string(font, Vector2(x, 46 if item.has("size") else 48), item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, item.get("size", TEXT_SIZE), color)
		# Setting value.
		if item.has("key"):
			var v = GameState.settings[item.key]
			var vx := 420.0
			if typeof(v) == TYPE_BOOL:
				draw_string(UiTheme.FONT_MEDIUM, Vector2(vx, 46), "On" if v else "Off", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, UiTheme.INK)
			else:
				for k in 10:
					var r := Rect2(vx + k * 17, 22, 13, 22)
					draw_rect(r, UiTheme.LIVE if k < roundi(v * 10) else UiTheme.MARBLE)
					draw_rect(r, UiTheme.INK, false, 3.0)
		elif item.has("value"):
			var val: Dictionary = item.value.call()
			var bar: float = val.bar
			for k in 10:
				var r := Rect2(VALUE_X + k * 14, 24, 10, 20)
				draw_rect(r, UiTheme.LIVE if k < ceili(bar * 10.0 - 0.01) else UiTheme.MARBLE)
				draw_rect(r, UiTheme.INK, false, 2.0)
			draw_string(UiTheme.FONT_MEDIUM, Vector2(VALUE_X + 150, 46), val.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30,
				UiTheme.INK if bar > 0.0 else Color("9a97a6"))


## The live cable from the machine to the selected option.
class _Cable extends Control:
	var snap := false
	var _end := Vector2.ZERO
	var _time := 0.0

	func _process(delta: float) -> void:
		_time += delta
		var menu = get_parent()
		var target: Vector2 = menu.cable_target()
		if target != Vector2.INF:
			_end = target if snap or _end == Vector2.ZERO else _end.lerp(target, 1.0 - exp(-14.0 * delta))
			snap = false
		queue_redraw()

	func _draw() -> void:
		var menu = get_parent()
		var a: Vector2 = menu.cable_start()
		if a == Vector2.INF or menu.cable_target() == Vector2.INF:
			return
		var b := _end
		var sag := 16.0 + a.distance_to(b) * 0.1
		var ctrl := (a + b) / 2.0 + Vector2(0, sag)
		var pts := PackedVector2Array()
		for i in 33:
			var t := i / 32.0
			pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
		draw_polyline(pts, UiTheme.INK, 9.0, true)
		draw_polyline(pts, UiTheme.LIVE, 4.0, true)
		for p in [a, b]:
			draw_circle(p, 8.0, UiTheme.INK)
			draw_circle(p, 4.0, UiTheme.LIVE)
		# Signal travelling from the machine to the button.
		for k in 3:
			var t := fmod(_time * 0.9 + k / 3.0, 1.0)
			var idx := t * (pts.size() - 1)
			var p: Vector2 = pts[int(idx)].lerp(pts[mini(int(idx) + 1, pts.size() - 1)], idx - int(idx))
			draw_circle(p, 5.0, Color("f0fff4"))


## Lobby: one pressure button per player slot; joining drops your character on it.
class _Lobby extends Control:
	var _joined_at := {}

	func joined_now(slot: int) -> void:
		_joined_at[slot] = Time.get_ticks_msec()

	func _process(_d: float) -> void:
		if visible:
			queue_redraw()

	func _draw() -> void:
		var cols := 4
		var cell := Vector2(size.x / cols, 200)
		for i in GameState.MAX_PLAYERS:
			var slot := i + 1
			var joined := GameState.is_joined(slot)
			var color: Color = PlayerSpawner.COLORS[i % 8]
			var c := Vector2((i % cols + 0.5) * cell.x, (i / cols) * cell.y + 110)
			# Button the player stands on.
			var cap := color if joined else Color("c9c6d2")
			var sink := 6.0 if joined else 0.0
			draw_texture_rect(TEX_CAP, Rect2(c + Vector2(-48, -60 + sink), Vector2(96, 96)), false, cap)
			draw_texture_rect(TEX_BASE, Rect2(c + Vector2(-48, -60), Vector2(96, 96)), false)
			if joined:
				var t := clampf((Time.get_ticks_msec() - _joined_at.get(slot, 0)) / 250.0, 0.0, 1.0)
				var drop := (1.0 - t) * (1.0 - t) * -70.0
				var r := Rect2(c + Vector2(-40, -86 + sink + drop), Vector2(80, 80))
				var frame := 0 if t >= 1.0 else 7  # falling frame while dropping in
				draw_texture_rect_region(TEX_PLAYER_BODY, r, Rect2(frame * 32, 0, 32, 32), color)
				draw_texture_rect_region(TEX_PLAYER_FACE, r, Rect2(frame * 32, 0, 32, 32))
			var label := "P%d" % slot
			draw_string(UiTheme.FONT_BOLD, c + Vector2(-60, 44), label, HORIZONTAL_ALIGNMENT_CENTER, 120, 26,
				UiTheme.INK if joined else Color("8a8796"))
			var sub := "" if joined else UiTheme.jump_key_text(slot)
			if Net.is_online():
				sub = Net.name_of(slot) if joined else ""
			draw_string(UiTheme.FONT_REGULAR, c + Vector2(-80, 68), sub, HORIZONTAL_ALIGNMENT_CENTER, 160, 18,
				UiTheme.ACCENT if joined else UiTheme.MUTED)
