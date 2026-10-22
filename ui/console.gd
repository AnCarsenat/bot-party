extends CanvasLayer
## Autoload "Console": commands for testing and fun.
## Open / close with the key left of 1 (` or ² on AZERTY) or F1. Type "help".
## Up / Down: history. Tab: complete. Esc: close.
## Offline, the game pauses while it's open. Online, only the host can change the
## game (clients can chat with "say", and look things up).

const TOGGLE_KEYS := [KEY_QUOTELEFT, KEY_F1]
const MAX_LINES := 300

var _panel: PanelContainer
var _log: RichTextLabel
var _line: LineEdit
var _toasts: VBoxContainer
var _fps: Label
var _keys: _KeyTester
var _history: Array[String] = []
var _history_pos := 0
var _paused_by_us := false
var _commands := {}   # name -> {fn, args, help, host}


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_register_all()
	print_line("[b]Bot Party console[/b]. Type [color=#6cba7c]help[/color].")


# --- UI ------------------------------------------------------------------------

func _build() -> void:
	var root := Control.new()
	root.name = "UiRoot"
	root.theme = UiTheme.make()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_panel.offset_bottom = 240
	_panel.self_modulate.a = 0.8  # see the game through it (the text stays solid)
	_panel.hide()
	root.add_child(_panel)
	var col := VBoxContainer.new()
	_panel.add_child(col)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 16)
	_log.add_theme_font_size_override("bold_font_size", 16)
	_log.add_theme_color_override("default_color", UiTheme.INK)
	col.add_child(_log)
	_line = LineEdit.new()
	_line.placeholder_text = "command  (help)"
	_line.add_theme_font_size_override("font_size", 17)
	_line.text_submitted.connect(_submit)
	_line.gui_input.connect(_on_input_key)
	col.add_child(_line)

	# Last messages, shown for a few seconds even when the console is closed (chat).
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_toasts.offset_left = 16
	_toasts.offset_top = -190
	_toasts.offset_bottom = -44
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toasts)

	_fps = Label.new()
	_fps.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps.offset_left = -140
	_fps.offset_top = 64
	_fps.offset_right = -16
	_fps.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps.add_theme_font_size_override("font_size", 18)
	_fps.add_theme_color_override("font_outline_color", UiTheme.MARBLE)
	_fps.add_theme_constant_override("outline_size", 5)
	_fps.hide()
	root.add_child(_fps)

	_keys = _KeyTester.new()
	_keys.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_keys.offset_left = -470
	_keys.offset_right = -16
	_keys.offset_top = -170
	_keys.offset_bottom = 214
	_keys.hide()
	root.add_child(_keys)


func is_open() -> bool:
	return _panel.visible


func toggle(open: bool) -> void:
	_panel.visible = open
	if open:
		_line.grab_focus()
		_line.clear()
		if not Net.is_online() and not get_tree().paused:
			get_tree().paused = true
			_paused_by_us = true
	else:
		_line.release_focus()
		if _paused_by_us:
			get_tree().paused = false
			_paused_by_us = false


func _input(event: InputEvent) -> void:
	if _keys.visible and (event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed():
		_keys.last = _describe(event)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in TOGGLE_KEYS or event.keycode in TOGGLE_KEYS:
			toggle(not is_open())
			get_viewport().set_input_as_handled()
		elif is_open() and event.keycode == KEY_ESCAPE:
			toggle(false)
			get_viewport().set_input_as_handled()


func _on_input_key(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed):
		return
	match e.keycode:
		KEY_UP:
			_recall(-1)
		KEY_DOWN:
			_recall(1)
		KEY_TAB:
			_complete()
		_:
			return
	_line.accept_event()


func _recall(step: int) -> void:
	if _history.is_empty():
		return
	_history_pos = clampi(_history_pos + step, 0, _history.size())
	_line.text = _history[_history_pos] if _history_pos < _history.size() else ""
	_line.caret_column = _line.text.length()


func _complete() -> void:
	var words := _line.text.split(" ")
	var last := words[-1]
	var pool: Array = _commands.keys() if words.size() == 1 else Party.ITEMS.keys() + Party.MODIFIERS.keys() + ["all", "left", "right", "off"]
	var hits := pool.filter(func(w): return str(w).begins_with(last))
	if hits.size() == 1:
		words[-1] = hits[0]
		_line.text = " ".join(words) + " "
		_line.caret_column = _line.text.length()
	elif hits.size() > 1:
		print_line(" ".join(hits))


func _process(_d: float) -> void:
	if _fps.visible:
		var extra := ""
		if Net.is_online() and Net._peer:
			extra = "\n%d ms" % _ping()
		_fps.text = "%d fps%s" % [Engine.get_frames_per_second(), extra]


func _ping() -> int:
	var id := 1 if Net.is_client() else (multiplayer.get_peers()[0] if not multiplayer.get_peers().is_empty() else 0)
	var p = Net._peer.get_peer(id) if id else null
	return int(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if p else 0


func print_line(text: String) -> void:
	_log.append_text(text + "\n")
	if _log.get_line_count() > MAX_LINES:
		_log.remove_paragraph(0)


## Short message at the bottom left, for a few seconds (and in the log).
func toast(text: String) -> void:
	print_line(text)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_outline_color", UiTheme.MARBLE)
	l.add_theme_constant_override("outline_size", 6)
	_toasts.add_child(l)
	while _toasts.get_child_count() > 5:
		_toasts.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


# --- Running commands ---------------------------------------------------------------

func _submit(text: String) -> void:
	_line.clear()
	text = text.strip_edges()
	if text == "":
		return
	_history.append(text)
	_history_pos = _history.size()
	print_line("[color=#6cba7c]> %s[/color]" % text)
	run(text)


## Runs one command line ("help", "give saw 2"...). Returns what it printed.
func run(text: String) -> String:
	var parts := text.strip_edges().split(" ")
	if parts.is_empty():
		return ""
	var name := parts[0].to_lower()
	var args := parts.slice(1)
	if not _commands.has(name):
		return _say("Unknown command \"%s\". Type help." % name)
	var c: Dictionary = _commands[name]
	if c.host and Net.is_client():
		return _say("Only the host can do that online.")
	var out = c.fn.call(args)
	return _say(str(out)) if out != null and str(out) != "" else ""


func _say(text: String) -> String:
	print_line(text)
	return text


## Commands anyone can use online (the rest change the game: host only).
const FOR_EVERYONE := ["keys", "help", "clear", "fps", "debug", "items", "where", "confetti", "net", "say", "name"]


func _add(name: String, usage: String, help: String, fn: Callable) -> void:
	_commands[name] = {"fn": fn, "usage": usage, "help": help, "host": not name in FOR_EVERYONE}


# --- Helpers -----------------------------------------------------------------------------

func _ui_root() -> Control:
	return get_node("UiRoot")


func _scene() -> Node:
	return get_tree().current_scene


func _ctl() -> Node:
	return get_tree().get_first_node_in_group("party_controller")


## Players named by the arguments: "2", "p2", "all" (default: P1, or everyone).
func _players(arg: String, default_all := false) -> Array:
	var out := []
	var everyone := get_tree().get_nodes_in_group("players")
	if arg == "" and default_all or arg == "all":
		return everyone
	var n := int(arg.trim_prefix("p").trim_prefix("P")) if arg != "" else 1
	for p in everyone:
		if p.get_meta("player_index", -1) + 1 == n:
			out.append(p)
	return out


func _arg(args: Array, i: int, default := "") -> String:
	return args[i] if i < args.size() else default


func _view_center() -> Vector2:
	var cam := get_viewport().get_camera_2d()
	return cam.get_screen_center_position() if cam else Vector2.ZERO


# --- Commands -----------------------------------------------------------------------------

func _register_all() -> void:
	_add("help", "help [command]", "List commands, or explain one.", func(a):
		if a.size() > 0 and _commands.has(a[0]):
			var c: Dictionary = _commands[a[0]]
			return "%s\n  %s" % [c.usage, c.help]
		var names := _commands.keys()
		names.sort()
		var lines := []
		for n in names:
			lines.append("[color=#6cba7c]%s[/color]  %s" % [_commands[n].usage, _commands[n].help])
		return "\n".join(lines))
	_add("clear", "clear", "Clear this log.", func(_a): _log.clear(); return "")
	_add("fps", "fps", "Show / hide FPS (and ping online).", func(_a): _fps.visible = not _fps.visible; return "")
	_add("keys", "keys", "Key tester: every player's keys light up when the game receives them.", func(_a):
		_keys.visible = not _keys.visible
		if _keys.visible:
			toggle(false)
			return "Key tester on (type keys again to hide it). Press each player's keys: a box that never lights means that key never reaches the game."
		return "Key tester off")
	_add("debug", "debug", "Show / hide logic wires and arrows (same as F3).", func(_a):
		var dv := get_tree().root.get_node_or_null("DebugView")
		if dv:
			dv.enabled = not dv.enabled
			return "Debug view %s" % ("on" if dv.enabled else "off")
		return "")
	_add("timescale", "timescale <x>", "Game speed (1 = normal, 0.25 = slow motion).", func(a):
		Engine.time_scale = clampf(float(_arg(a, 0, "1")), 0.05, 4.0)
		return "Time scale %.2f" % Engine.time_scale)

	# Levels and modes.
	_add("level", "level <n>", "Start campaign level n of the current campaign.", func(a):
		var i := int(_arg(a, 0, "1")) - 1
		if i < 0 or i >= GameState.levels.size():
			return "Levels 1-%d: %s" % [GameState.levels.size(), ", ".join(GameState.levels.map(func(l): return l.name))]
		toggle(false)
		GameState.start_level(i)
		return "")
	_add("next", "next", "Finish this level, or (party) skip to the next round.", func(_a):
		if _ctl():
			return _ctl().skip_round()
		if _scene() == null or not _scene().has_node("Game"):
			return "Not in a level"
		toggle(false)
		GameState.complete_level()
		return "")
	_add("inspect", "inspect [node path]", "Open the inspector: nodes and their properties, editable live.", func(a):
		var ins = _ui_root().get_node_or_null("Inspector")
		if ins == null:
			ins = Inspector.new()
			ins.name = "Inspector"
			_ui_root().add_child(ins)
		if a.size() > 0 and _scene():
			var n = _scene().get_node_or_null(NodePath(_arg(a, 0)))
			if n == null:
				return "No node " + _arg(a, 0)
			ins.select.call_deferred(n)
		return "Inspector open (Pick, then click something in the game)")
	_add("savestate", "savestate [name]", "Save where everyone is (level, party, crates).", func(a):
		return SaveStates.save(get_tree(), _arg(a, 0, "quick")))
	_add("loadstate", "loadstate [name]", "Go back to a saved state.", func(a):
		if Net.is_client():
			return "Online, only the host can"
		toggle(false)
		return SaveStates.load_state(get_tree(), _arg(a, 0, "quick")))
	_add("states", "states", "List the saved states.", func(_a):
		var l := SaveStates.list()
		return "No saved states yet (savestate [name])" if l.is_empty() else ", ".join(l))
	_add("restart", "restart", "Restart the level.", func(_a): toggle(false); GameState.restart_level(); return "")
	_add("menu", "menu", "Back to the menu.", func(_a): toggle(false); GameState.go_to_menu(); return "")
	_add("players", "players <1-8>", "How many players play on this computer (offline).", func(a):
		if Net.is_online():
			return "Online, people join from the lobby"
		GameState.player_count = clampi(int(_arg(a, 0, "2")), 1, 8)
		GameState.save_settings()
		return "%d players: %s" % [GameState.joined.size(), GameState.joined])
	_add("party", "party [arena 1-%d]" % Party.ARENAS.size(), "Start a new party (in a given arena).", func(a):
		toggle(false)
		Party.new_session(GameState.joined)
		if a.size() > 0:
			Party.session.arena = Party.ARENAS[clampi(int(a[0]) - 1, 0, Party.ARENAS.size() - 1)]
		Party.save()
		get_tree().root.get_node("Transition").change_scene(Party.arena(), "Party time", 1.0)
		return "")

	# Party.
	_add("bots", "bots <count> [easy|normal|hard]", "Party: computer players for the next new party.", func(a):
		if a.is_empty():
			return "%d bots, %s" % [Party.bot_count, PartyBot.SKILL_NAMES[Party.bot_skill]]
		Party.bot_count = clampi(int(_arg(a, 0)), 0, GameState.MAX_PLAYERS - 1)
		var names := PartyBot.SKILL_NAMES.map(func(n): return n.to_lower())
		if a.size() > 1 and _arg(a, 1).to_lower() in names:
			Party.bot_skill = names.find(_arg(a, 1).to_lower())
		Party.save_weights()
		return "%d bots, %s (from the next new party)" % [Party.bot_count, PartyBot.SKILL_NAMES[Party.bot_skill]])
	_add("items", "items", "List party item names.", func(_a): return ", ".join(Party.ITEMS.keys()))
	var place_fn := func(a):
		if not _ctl():
			return "Not in party mode"
		var id := _arg(a, 0)
		if not Party.ITEMS.has(id):
			return "Unknown item. Try: items"
		return _ctl().place_item(int(_arg(a, 1, "1").trim_prefix("p")), id)
	_add("place", "place <item> [player]", "Party: a player places this item now (any time, even mid-race).", place_fn)
	_add("give", "give <item> [player]", "Same as place.", place_fn)
	_add("spawn", "spawn <item> [x y]", "Party: place an item now (middle of the screen, or at x y).", func(a):
		if not _ctl():
			return "Not in party mode"
		var id := _arg(a, 0)
		if not Party.ITEMS.has(id) or Party.ITEMS[id].get("bomb", false):
			return "Unknown or not placeable. Try: items"
		var pos := _view_center()
		if a.size() >= 3:
			pos = Vector2(float(a[1]), float(a[2]))
		_ctl().spawn_now(id, pos)
		return "Placed %s at %s" % [id, pos.round()])
	_add("clearitems", "clearitems", "Party: remove every placed item.", func(_a):
		return "Removed %d items" % _ctl().clear_items() if _ctl() else "Not in party mode")
	_add("modifier", "modifier <name|list>", "Party: the next round's rule.", func(a):
		var names := Party.MODIFIERS.keys()
		var want := " ".join(a)
		var hit := names.filter(func(n): return n.to_lower() == want.to_lower())
		if not _ctl() or hit.is_empty():
			return "Rules: " + ", ".join(names)
		_ctl().forced_modifier = hit[0]
		return "Next round: %s" % hit[0])
	_add("score", "score <player> <points>", "Party: set a player's score.", func(a):
		if Party.session.is_empty() or a.size() < 2:
			return "score <player> <points>"
		Party.session.scores[str(int(a[0].trim_prefix("p")))] = int(a[1])
		Party.save()
		return "P%s: %s points" % [a[0].trim_prefix("p"), a[1]])
	_add("meteor", "meteor [x]", "Party race in the meteor field: drop a meteor (on P1 by default).", func(a):
		var w := _scene().get_node_or_null("Weather") if _scene() else null
		if w == null:
			return "No weather in this arena"
		var x: float = float(a[0]) if a.size() > 0 else (_players("1")[0].global_position.x if not _players("1").is_empty() else _view_center().x)
		return "Incoming!" if w.drop_meteor(x) else "Nothing to land on there")
	_add("wind", "wind <left|right|off>", "Party race: a gust right now.", func(a):
		var w := _scene().get_node_or_null("Weather") if _scene() else null
		if w == null:
			return "No weather in this arena"
		w.gust({"left": -1.0, "right": 1.0}.get(_arg(a, 0, "right"), 0.0))
		return "Whoosh")

	# Players.
	_add("god", "god [player|all]", "Traps and falls can't take them out (toggle).", func(a):
		var ps := _players(_arg(a, 0))
		for p in ps:
			p.set_meta("god", not p.get_meta("god", false))
		return ", ".join(ps.map(func(p): return "P%d god %s" % [p.get_meta("player_index") + 1, "on" if p.get_meta("god") else "off"])))
	_add("noclip", "noclip [player|all]", "Fly through everything with the move keys (toggle).", func(a):
		var ps := _players(_arg(a, 0))
		for p in ps:
			p.set_meta("noclip", not p.get_meta("noclip", false))
			p.velocity = Vector2.ZERO
		return ", ".join(ps.map(func(p): return "P%d noclip %s" % [p.get_meta("player_index") + 1, "on" if p.get_meta("noclip") else "off"])))
	_add("kill", "kill [player|all]", "Take a player out.", func(a):
		var game := _scene().get_node_or_null("Game") if _scene() else null
		if game == null:
			return "Not in a level"
		var ps := _players(_arg(a, 0))
		for p in ps:
			p.set_meta("god", false)
			game.eliminate_player(p)
		return "Bye (%d)" % ps.size())
	_add("tp", "tp <player> <x> <y> | tp <player> <other player>", "Teleport.", func(a):
		var ps := _players(_arg(a, 0))
		if ps.is_empty():
			return "No such player"
		var to := Vector2.INF
		if a.size() >= 3:
			to = Vector2(float(a[1]), float(a[2]))
		elif a.size() == 2 and not _players(a[1]).is_empty():
			to = _players(a[1])[0].global_position + Vector2(0, -100)
		if to == Vector2.INF:
			return "tp <player> <x> <y>"
		for p in ps:
			p.global_position = to
			p.velocity = Vector2.ZERO
		return "Teleported to %s" % to.round())
	_add("where", "where [player]", "Position of a player (handy for tp and spawn).", func(a):
		var ps := _players(_arg(a, 0))
		return "P%d at %s" % [ps[0].get_meta("player_index") + 1, ps[0].global_position.round()] if not ps.is_empty() else "No such player")
	for prop in [["speed", "speed", "Run speed"], ["jump", "jump_speed", "Jump strength"], ["gravity", "gravity", "Gravity"]]:
		var key: String = prop[1]
		_add(prop[0], "%s <x> [player|all]" % prop[0], "%s times x (1 = back to normal)." % prop[2], func(a):
			var x := float(_arg(a, 0, "1"))
			var ps := _players(_arg(a, 1), true)
			for p in ps:
				if not p.has_meta("base_" + key):
					p.set_meta("base_" + key, p.get(key))
				p.set(key, p.get_meta("base_" + key) * x)
			return "%s x%.2f for %d players" % [prop[2], x, ps.size()])
	_add("size", "size <x> [player|all]", "Big or tiny robots.", func(a):
		var x := clampf(float(_arg(a, 0, "1")), 0.25, 4.0)
		var ps := _players(_arg(a, 1), true)
		for p in ps:
			p.scale = Vector2(x, x)
		return "Size x%.2f" % x)
	_add("confetti", "confetti", "Celebrate.", func(_a):
		for p in get_tree().get_nodes_in_group("players"):
			_scene().add_child(Effects.burst(p.global_position + Vector2(0, -50), Color.WHITE, 40, 420.0,
				[Color("e64f3e"), Color("ffd65a"), Color("70e890"), Color("78c8f0"), Color("d7ffac")]))
		return "")
	_add("boom", "boom [radius]", "Explosion around P1: party items and other players nearby are gone.", func(a):
		var r := float(_arg(a, 0, "160"))
		var ps := _players("1")
		if ps.is_empty():
			return "No P1"
		var at: Vector2 = ps[0].global_position
		_scene().add_child(Effects.ring(at, r, Color(1, 0.55, 0.2)))
		if _ctl():
			_ctl()._explode(at, r)
		var game := _scene().get_node_or_null("Game")
		for p in get_tree().get_nodes_in_group("players"):
			if p != ps[0] and p.global_position.distance_to(at) <= r and game:
				game.eliminate_player(p)
		return "BOOM")

	# Online.
	_add("net", "net", "Online status: who's here, ping, data sent.", func(_a):
		if not Net.is_online():
			return "Offline"
		var lines := ["%s, %d players" % ["Hosting" if Net.is_host() else "Connected", Net.roster.size()]]
		for r in Net.roster:
			lines.append("  P%d  %s%s" % [r.slot, r.name, "  (this computer)" if int(r.peer) == Net.my_id() else ""])
		lines.append("Ping: %d ms" % _ping())
		return "\n".join(lines))
	_add("say", "say <message>", "Chat with everyone in the online game.", func(a):
		if not Net.is_online():
			return "Not online"
		Net.chat(" ".join(a))
		return "")
	_add("name", "name <name>", "Your name online.", func(a):
		if a.is_empty():
			return Net.player_name
		Net.player_name = " ".join(a).left(16)
		Net.save_config()
		return "You are %s" % Net.player_name)


func _describe(e: InputEvent) -> String:
	if e is InputEventKey:
		var phys := OS.get_keycode_string(e.physical_keycode) if e.physical_keycode else "?"
		var typed := OS.get_keycode_string(e.keycode) if e.keycode else "?"
		return "key %s (physical %s)" % [typed, phys]
	if e is InputEventJoypadButton:
		return "pad %d button %d" % [e.device, e.button_index]
	return ""


## Live view of every player's actions (console "keys").
class _KeyTester extends PanelContainer:
	const NAMES := ["left", "right", "up", "down", "jump", "turn", "flip"]
	var last := ""

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d: float) -> void:
		if visible:
			queue_redraw()

	func _draw() -> void:
		var y := 26.0
		draw_string(UiTheme.FONT_BOLD, Vector2(18, y), "Key tester", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UiTheme.INK)
		draw_string(UiTheme.FONT_REGULAR, Vector2(150, y), last, HORIZONTAL_ALIGNMENT_LEFT, 280, 16, UiTheme.MUTED)
		for slot in range(1, 9):
			y = 30.0 + slot * 38.0
			var joined := GameState.is_joined(slot)
			draw_string(UiTheme.FONT_BOLD, Vector2(18, y + 20), "P%d" % slot, HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
				UiTheme.INK if joined else Color("9a97a6"))
			for i in NAMES.size():
				var action := "p%d_%s" % [slot, Net.ACTIONS[i]]
				var on := InputMap.has_action(action) and Input.is_action_pressed(action)
				var r := Rect2(62 + i * 54, y, 50, 28)
				# Lit = dark box (not just a colour: P1 is white).
				draw_rect(r, UiTheme.INK if on else UiTheme.MARBLE)
				draw_rect(r, UiTheme.INK, false, 2.0)
				var tc: Color = PlayerSpawner.COLORS[(slot - 1) % 8] if on else UiTheme.INK
				draw_string(UiTheme.FONT_BOLD if on else UiTheme.FONT_MEDIUM, r.position + Vector2(0, 20), NAMES[i],
					HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 14, tc)
