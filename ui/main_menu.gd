extends Control
## Title screen. The menu is one of the game's machines: every option sits on a
## pressure button, and a live cable runs from the machine to the selected one.
##   Up/Down (arrows or any player's keys) move, Enter / Space / any jump key
##   chooses, Left/Right change a setting, Esc goes back.
## "Players" is the lobby: each player presses their own jump key to join.

const TITLE := "Bot Party"
const VERSION := "v0.27"
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
var _controls_slot := 1   # Settings > Controls: whose keys
var _capture := ""        # the action waiting for a key press
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
var _preview: Control  # Settings: live bubble preview (DistantPlayers.Preview)
const PREVIEW_KEYS := ["distant_players", "bubble_view", "bubble_size"]


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
	_info.offset_left = -480
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
	_lobby.offset_bottom = 580
	_lobby.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lobby.menu = self
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
				"info": "First to %d wins." % Party.rules.target})
			if Party.has_save():
				_items.append({"text": "Continue", "on_accept": func(): _start(func(): Party.continue_game()), "info": Party.describe_save()})
			_items.append({"text": "Arena", "info": "Left / right: where new parties are played.\nYour own maps are listed too.",
				"value": func(): return "< %s >" % Party.arena_choice_name().left(12),
				"on_left": func(): _cycle_arena(-1), "on_right": func(): _cycle_arena(1),
				"on_accept": func(): _cycle_arena(1)})
			_items.append({"text": "Rules", "on_accept": func(): _show("party_rules"), "info": "Winning score, round time, coins, surprises, item odds."})
			_items.append({"text": "Items", "on_accept": func(): _show("party_items"), "info": "Which items show up, and how often."})
			if not Net.is_online():
				_items.append({"text": "Map editor", "on_accept": func(): get_tree().root.get_node("Transition").change_scene("res://editor/map_editor.tscn"),
					"info": "Draw your own arenas (mouse). Saved maps show up under Arena."})
			_items.append({"text": "Back", "on_accept": func(): _back()})
		"party_rules":
			var r: Dictionary = Party.rules
			var onoff := func(k: String): return "< %s >" % ("On" if r[k] else "Off")
			var flip := func(k: String): r[k] = not r[k]; Party.save_weights(); _refresh_info()
			var step := func(k: String, d: int, lo: int, hi: int): r[k] = clampi(int(r[k]) + d, lo, hi); Party.save_weights(); _refresh_info()
			_items.append({"text": "Mode", "info": "How the party is played.\n" + str(Party.modes().get(r.mode, {}).get("description", "")),
				"value": func(): return "< %s >" % str(Party.modes().get(r.mode, {"name": "Classic"}).name).left(14),
				"on_left": func(): _cycle_mode(-1), "on_right": func(): _cycle_mode(1), "on_accept": func(): _cycle_mode(1)})
			_items.append({"text": "First to", "info": "Points needed to win the party.",
				"value": func(): return "< %d >" % r.target,
				"on_left": func(): step.call("target", -10, 10, 300), "on_right": func(): step.call("target", 10, 10, 300),
				"on_accept": func(): step.call("target", 10, 10, 300)})
			_items.append({"text": "Round time", "info": "Seconds to reach the flag. Arena: each arena's own time.",
				"value": func(): return "< %s >" % ("Arena" if r.round_time == 0 else "%d s" % r.round_time),
				"on_left": func(): step.call("round_time", -10, 0, 180), "on_right": func(): step.call("round_time", 10, 0, 180),
				"on_accept": func(): step.call("round_time", 10, 0, 180)})
			_items.append({"text": "Coins", "info": "A coin to grab on the way: bonus points if you reach the flag with it.",
				"value": func(): return onoff.call("coins"), "on_left": func(): flip.call("coins"), "on_right": func(): flip.call("coins"), "on_accept": func(): flip.call("coins")})
			_items.append({"text": "Surprises", "info": "Some rounds get a surprise rule (low gravity, speedy...).",
				"value": func(): return onoff.call("surprises"), "on_left": func(): flip.call("surprises"), "on_right": func(): flip.call("surprises"), "on_accept": func(): flip.call("surprises")})
			_items.append({"text": "Specials", "info": "Special crates in the box: each gives a special item (big ferris wheel, bear trap, black hole...). Party > Items lists them.",
				"value": func(): return "< %s >" % Party.SPECIAL_NAMES[clampi(int(r.specials), 0, 2)],
				"on_left": func(): step.call("specials", -1, 0, 2), "on_right": func(): step.call("specials", 1, 0, 2),
				"on_accept": func(): r.specials = (int(r.specials) + 1) % 3; Party.save_weights(); _refresh_info()})
			_items.append({"text": "Equal odds", "info": "Every item that's on is as likely as the others (ignores Party > Items odds).",
				"value": func(): return onoff.call("equal_odds"), "on_left": func(): flip.call("equal_odds"), "on_right": func(): flip.call("equal_odds"), "on_accept": func(): flip.call("equal_odds")})
			_items.append({"text": "Reset", "info": "Back to the usual rules.", "on_accept": func():
				Party.rules = Party.RULE_DEFAULTS.duplicate(); Party.save_weights(); _show("party_rules", true)})
			_items.append({"text": "Back", "on_accept": func(): _back()})
		"party_items":
			# The usual items first, then the special ones (from Special crates).
			var ids: Array = Party.listed_items().filter(func(k): return not Party.is_special(k)) \
				+ Party.listed_items().filter(func(k): return Party.is_special(k))
			for id in ids:
				var def: Dictionary = Party.ITEMS[id]
				var info := "Left / right: how often\nJump: on / off"
				if Party.is_special(id):
					info = "Special: comes out of Special crates (Party > Rules > Specials).\n" + info
				_items.append({"text": def.name, "icon": Party.icon(id), "size": 34, "info": info,
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
					"info": "Not listed: friends join with your address (UDP port %d)." % Net.host_port},
				{"text": "Server list", "on_accept": func(): _listing = true; _servers.clear(); _show("servers"); Net.list_servers(),
					"info": "Games hosted by others." if Net.lobby_url != "" else "Set the server list address first."},
				{"text": "Join by address", "on_accept": func(): _start(func(): _edit_text("Host address (ip or ip:port)", _last_address,
					func(t): _last_address = t; _hint.text = "Connecting..."; Net.join_address(t))), "info": "Type the host's address."},
				{"text": "Port: %d" % Net.host_port, "on_accept": func(): _edit_text("UDP port to host on (1024-65535)", str(Net.host_port), func(t):
					if t.strip_edges().is_valid_int():
						Net.host_port = clampi(int(t), 1024, 65535)
						Net.save_config()
					_show("online", true)), "size": 34, "info": "The port your game uses when you host. Friends joining by address add it: ip:port."},
				{"text": "Name: " + Net.player_name, "on_accept": func(): _edit_text("Your name", Net.player_name, _set_name),
					"size": 34, "info": "Shown to the others."},
				{"text": "List: " + (Net.lobby_url if Net.lobby_url != "" else "not set"), "on_accept": func(): _edit_text("Server list address (empty: the game's default)", Net.lobby_url, _set_lobby_url),
					"size": 34, "info": "Address of the server list (server/lobby_server.py)."},
				{"text": "Back", "on_accept": func(): _back()},
			]
		"servers":
			if _servers.is_empty():
				_items.append({"text": "Searching..." if _listing else "No games found", "enabled": false})
			# Each hosted game is a room of its own: the ones waiting for players
			# first, then the ones already playing.
			for group in [["Waiting for players", func(m): return m == "lobby" or m == ""],
					["Playing", func(m): return m != "lobby" and m != ""]]:
				var rooms := _servers.filter(func(r): return group[1].call(str(r.get("mode", ""))))
				if rooms.is_empty():
					continue
				_items.append({"text": "%s (%d)" % [group[0], rooms.size()], "enabled": false, "size": 26})
				for e in rooms:
					var entry: Dictionary = e
					var full: bool = int(entry.players) >= int(entry.max)
					var mode := str(entry.get("mode", ""))
					var doing: String = {"party": "Playing party mode", "campaign": "Playing the campaign"}.get(mode, "In the lobby")
					_items.append({"text": "%s  %d/%d" % [str(entry.name).left(18), int(entry.players), int(entry.max)], "size": 34,
						"enabled": not full,
						"info": "%s\n%d of %d players%s%s" % [doing, int(entry.players), int(entry.max), "  (full)" if full else "",
							"\n(relay available)" if entry.get("relay", false) else ""],
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
				{"text": "Distant players", "key": "distant_players", "on_left": func(): _toggle("distant_players"), "on_right": func(): _toggle("distant_players"), "on_accept": func(): _toggle("distant_players"),
					"info": "A robot off the screen gets a bubble at the edge with a small view of it."},
				{"text": "Bubble view", "key": "bubble_view", "on_left": func(): _bump("bubble_view", -0.1), "on_right": func(): _bump("bubble_view", 0.1), "on_accept": func(): _bump("bubble_view", 0.1, true),
					"info": "How much of the level a distant player's bubble shows. More bars: zoomed further out."},
				{"text": "Bubble size", "key": "bubble_size", "on_left": func(): _bump("bubble_size", -0.1), "on_right": func(): _bump("bubble_size", 0.1), "on_accept": func(): _bump("bubble_size", 0.1, true),
					"info": "How big a distant player's bubble is on the screen."},
				{"text": "Screen shake", "key": "screen_shake", "on_left": func(): _toggle("screen_shake"), "on_right": func(): _toggle("screen_shake"), "on_accept": func(): _toggle("screen_shake"),
					"info": "Explosions (bombs, nukes, black holes) shake the screen."},
				{"text": "Controls", "on_accept": func(): _show("controls"), "info": "Change the keys of each player."},
				{"text": "Mods", "on_accept": func(): _show("mods"), "info": "Items, maps and textures made by players.",
					"enabled": not Net.is_online()},
				{"text": "Back", "on_accept": func(): _back()},
			]
		"controls":
			_items.append({"text": "Player", "info": "Left / right: whose keys to change.",
				"value": func(): return "< P%d >" % _controls_slot,
				"on_left": func(): _controls_slot = posmod(_controls_slot - 2, 5) + 1; _show("controls", true),
				"on_right": func(): _controls_slot = posmod(_controls_slot, 5) + 1; _show("controls", true)})
			for a in PlayerKeys.ACTIONS:
				var act: String = a
				_items.append({"text": PlayerKeys.ACTION_NAMES[act], "size": 36,
					"value": func(): return "Press a key..." if _capture == act else PlayerKeys.key_name(PlayerKeys.key_of(_controls_slot, act)),
					"on_accept": func(): _capture = act; _hint.text = "Press the new key for P%d %s   (Esc: cancel)" % [_controls_slot, PlayerKeys.ACTION_NAMES[act]],
					"info": "Jump: change this key.\nKeys dropping out with several players on one keyboard? Keep each player's keys far apart."})
			_items.append({"text": "Reset all", "info": "Every player back to the usual keys.", "on_accept": func():
				PlayerKeys.reset(); _hint.text = "Keys reset"; _show("controls", true)})
			_items.append({"text": "Back", "on_accept": func(): _back()})
		"mods":
			Mods.scan()
			for m in Mods.mods:
				var mod: Dictionary = m
				_items.append({"text": mod.name.left(16), "size": 34,
					"value": func(): return "On" if mod.enabled else "Off",
					"on_accept": func(): _toggle_mod(mod), "on_left": func(): _toggle_mod(mod), "on_right": func(): _toggle_mod(mod),
					"info": _mod_info(mod)})
			_items.append({"text": "Open mods folder", "on_accept": func(): Mods.open_folder(),
				"info": "Put mod packs (.pck) or mod folders here:\n%s\nThen come back to this screen." % ProjectSettings.globalize_path(Mods.DIR)})
			_items.append({"text": "Back", "on_accept": func(): _back()})
	_heading.text = {"main": "", "campaign": _campaign_heading(), "party": "Party", "party_items": "Party items", "party_rules": "Party rules", "players": "Players",
		"settings": "Settings", "controls": "Controls", "mods": "Mods", "online": "Online", "servers": "Server list", "online_lobby": _online_heading()}[screen]
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
	_lobby.mouse_filter = Control.MOUSE_FILTER_STOP if screen == "players" else Control.MOUSE_FILTER_IGNORE
	if screen == "players" and not Net.is_online():
		_hint.text = "Jump: join / leave    Arrows: choose a slot    Delete: remove    +: add a bot / how good"
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
	_refresh_preview()


## Settings: while a bubble setting is selected, a live bubble replaces the
## machine picture, so the change can be seen as it's made.
func _refresh_preview() -> void:
	var key: String = _items[_index].get("key", "") if not _items.is_empty() else ""
	var want: bool = _screen == "settings" and key in PREVIEW_KEYS and GameState.settings.get("distant_players", true)
	if want and _preview == null:
		_preview = DistantPlayers.Preview.new()
		_preview.anchor_left = 1.0
		_preview.anchor_right = 1.0
		_preview.offset_left = -560
		_preview.offset_right = -60
		_preview.offset_top = 140
		_preview.offset_bottom = 400
		add_child(_preview)
	elif not want and _preview != null:
		_preview.queue_free()
		_preview = null
	if not _lobby.visible:
		_machine.visible = not want
	_info.offset_top = 420 if want else 330
	_refresh_arena_preview()


var _arena_preview: ArenaPreview


## Party > Arena: a picture of the arena that's chosen (not for Random).
func _refresh_arena_preview() -> void:
	var on_arena: bool = _screen == "party" and not _items.is_empty() and _items[_index].get("text", "") == "Arena"
	var want := on_arena and Party.arena_choice != "random"
	if want and _arena_preview == null:
		ArenaPreview.clear_cache()  # maps may have changed in the editor
		_arena_preview = ArenaPreview.new()
		_arena_preview.anchor_left = 1.0
		_arena_preview.anchor_right = 1.0
		_arena_preview.offset_left = -470
		_arena_preview.offset_right = -60
		_arena_preview.offset_top = 150
		_arena_preview.offset_bottom = 380
		_arena_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_arena_preview)
	elif not want and _arena_preview != null:
		_arena_preview.queue_free()
		_arena_preview = null
	if _arena_preview:
		_arena_preview.set_choice(Party.arena_choice)
		_machine.visible = false
		_info.offset_top = 420


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
	Net.lobby_url = t.strip_edges() if t.strip_edges() != "" else Net.default_lobby_url  # empty: back to the default
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
	if _preview != null:  # the cable runs from the bubble preview instead
		return _preview.cable_point() - global_position
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

func _toggle_mod(mod: Dictionary) -> void:
	var count: int = Mods.mods.size()
	Mods.set_enabled(mod.id, not mod.enabled)
	if Mods.get_mod(mod.id) != mod or Mods.mods.size() != count:
		_show("mods", true)  # a mod pack was loaded: the list was read again
		return
	_items[_index].info = _mod_info(mod)
	_refresh_info()


func _mod_info(mod: Dictionary) -> String:
	var lines := []
	if mod.description != "":
		lines.append(mod.description.left(120))
	var kind: String = {"pack": "Mod pack", "project": "In the game project"}.get(mod.get("kind", ""), "Folder")
	lines.append("v%s%s  (%s)" % [mod.version, (" by " + mod.author) if mod.author != "" else "", kind])
	var adds := []
	if not mod.items.is_empty():
		adds.append("%d item%s" % [mod.items.size(), "s" if mod.items.size() > 1 else ""])
	if not mod.get("modes", {}).is_empty():
		adds.append("%d mode%s" % [mod.modes.size(), "s" if mod.modes.size() > 1 else ""])
	if mod.maps != "":
		adds.append("maps")
	if not mod.textures.is_empty():
		adds.append("%d texture%s (restart to see changes)" % [mod.textures.size(), "s" if mod.textures.size() > 1 else ""])
	if not adds.is_empty():
		lines.append("Adds " + ", ".join(adds))
	for p in mod.problems.slice(0, 2):
		lines.append("! " + p)
	return "\n".join(lines)


func _cycle_mode(step: int) -> void:
	var ids := Party.modes().keys()
	var i := maxi(0, ids.find(Party.rules.mode))
	Party.rules.mode = ids[posmod(i + step, ids.size())]
	Party.save_weights()
	_show("party_rules", true)


## Players screen: removes whoever is in `slot` (a person or a bot), even when
## that person's keys or gamepad aren't there any more.
func lobby_remove(slot: int) -> void:
	if Party.bot_list.has(slot):
		Party.remove_bot(slot)
	elif GameState.is_joined(slot) and not Net.is_online():
		GameState.leave(slot)
	_lobby.queue_redraw()


## Players screen: a free slot gets a bot; a bot's slot changes how good it is.
func lobby_bot(slot: int) -> void:
	if Net.is_online():
		return
	if Party.bot_list.has(slot):
		Party.set_bot_skill(slot, Party.bot_list[slot] + 1)
	elif not GameState.is_joined(slot):
		if Party.add_bot(PartyBot.Skill.NORMAL, slot) != 0:
			_lobby.joined_now(slot)
	_lobby.queue_redraw()


func _cycle_arena(step: int) -> void:
	var options := Party.arena_options()
	var i := 0
	for k in options.size():
		if options[k].id == Party.arena_choice:
			i = k
	Party.arena_choice = options[posmod(i + step, options.size())].id
	Party.save_weights()
	_refresh_info()


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
	if _screen in ["party_items", "party_rules", "mods", "controls"]:
		var text: String = {"party_items": "Items", "party_rules": "Rules", "mods": "Mods", "controls": "Controls"}[_screen]
		_show({"party_items": "party", "party_rules": "party", "mods": "settings", "controls": "settings"}[_screen])
		for i in _items.size():
			if _items[i].text == text:
				_select(i)
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
	if _capture != "":
		# Settings > Controls: the next key pressed becomes the key.
		if event is InputEventKey and event.pressed and not event.echo:
			var k: Key = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			if k == KEY_ESCAPE:
				_hint.text = ""
			else:
				var note := PlayerKeys.rebind(_controls_slot, _capture, k)
				_hint.text = note if note != "" else "P%d %s: %s" % [_controls_slot, PlayerKeys.ACTION_NAMES[_capture], PlayerKeys.key_name(k)]
			_capture = ""
			_show("controls", true)
		get_viewport().set_input_as_handled()
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
		# Choose a slot (arrows, sticks, anyone's move keys), then remove it or
		# add a bot there (Delete / Insert or +; any player: turn / flip key).
		var move := Vector2i.ZERO
		if event.is_action_pressed("ui_left", true) or _player_action(event, "move_left"):
			move = Vector2i(-1, 0)
		elif event.is_action_pressed("ui_right", true) or _player_action(event, "move_right"):
			move = Vector2i(1, 0)
		elif event.is_action_pressed("ui_up", true) or _player_action(event, "move_up"):
			move = Vector2i(0, -1)
		elif event.is_action_pressed("ui_down", true) or _player_action(event, "move_down"):
			move = Vector2i(0, 1)
		if move != Vector2i.ZERO:
			_lobby.move_selection(move)
			_handled(stick); return
		var key: Key = event.physical_keycode if event is InputEventKey and event.pressed and not event.echo else KEY_NONE
		if key in [KEY_DELETE, KEY_BACKSPACE] or _player_action(event, "action_2"):
			lobby_remove(_lobby.selected)
			_handled(stick); return
		if key in [KEY_INSERT, KEY_EQUAL, KEY_PLUS] or _player_action(event, "action_3"):
			lobby_bot(_lobby.selected)
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
		if index >= menu._items.size():
			return Vector2.ZERO
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
		if index >= menu._items.size():
			return  # a row of the screen we just left, about to go
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
		elif item.has("value") and item.value.call() is String:
			draw_string(UiTheme.FONT_MEDIUM, Vector2(VALUE_X, 46), item.value.call(), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UiTheme.INK)
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
## Offline, one slot is selected (arrows or the mouse): it can be emptied (Remove)
## or given a bot, whose difficulty can then be changed.
class _Lobby extends Control:
	var menu
	var selected := 1
	var _joined_at := {}
	var _buttons := []  # [Rect2, Callable] of the selected slot's buttons

	func joined_now(slot: int) -> void:
		_joined_at[slot] = Time.get_ticks_msec()

	func move_selection(d: Vector2i) -> void:
		var i := selected - 1
		var col := posmod(i % 4 + d.x, 4)
		var row := posmod(i / 4 + d.y, 2)
		selected = row * 4 + col + 1
		queue_redraw()

	func _process(_d: float) -> void:
		if visible:
			queue_redraw()

	func _cell_center(i: int) -> Vector2:
		var cell := Vector2(size.x / 4, 210)
		return Vector2((i % 4 + 0.5) * cell.x, (i / 4) * cell.y + 110)

	func _gui_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
			return
		for b in _buttons:
			if b[0].has_point(event.position):
				b[1].call()
				accept_event()
				return
		for i in GameState.MAX_PLAYERS:
			if Rect2(_cell_center(i) - Vector2(size.x / 8, 100), Vector2(size.x / 4, 210)).has_point(event.position):
				selected = i + 1
				accept_event()
				return

	func _button(r: Rect2, text: String, fn: Callable) -> void:
		draw_rect(r, Color("f0fff4"))
		draw_rect(r, UiTheme.INK, false, 3.0)
		draw_string(UiTheme.FONT_BOLD, r.position + Vector2(0, r.size.y - 7), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 16, UiTheme.INK)
		_buttons.append([r, fn])

	func _draw() -> void:
		_buttons.clear()
		var offline := not Net.is_online()
		for i in GameState.MAX_PLAYERS:
			var slot := i + 1
			var bot: bool = offline and Party.bot_list.has(slot)
			var joined := GameState.is_joined(slot) or bot
			var color: Color = PlayerSpawner.COLORS[i % 8]
			var c := _cell_center(i)
			if offline and slot == selected and menu and menu._screen == "players":
				var r := Rect2(c + Vector2(-78, -96), Vector2(156, 200))
				draw_rect(r, Color(UiTheme.LIVE, 0.18))
				draw_rect(r, UiTheme.INK, false, 4.0)
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
			var label := _bot_label(slot) if bot else ("P%d" % slot)
			draw_string(UiTheme.FONT_BOLD, c + Vector2(-60, 44), label, HORIZONTAL_ALIGNMENT_CENTER, 120, 26,
				UiTheme.INK if joined else Color("8a8796"))
			var sub := "" if joined else UiTheme.jump_key_text(slot)
			if bot:
				sub = PartyBot.SKILL_NAMES[Party.bot_list[slot]] + " bot"
			if Net.is_online():
				sub = Net.name_of(slot) if joined else ""
			draw_string(UiTheme.FONT_REGULAR, c + Vector2(-80, 68), sub, HORIZONTAL_ALIGNMENT_CENTER, 160, 18,
				UiTheme.ACCENT if joined else UiTheme.MUTED)
			# The selected slot's buttons (for the mouse; keys do the same).
			if offline and slot == selected and menu and menu._screen == "players":
				var row := Rect2(c + Vector2(-72, 76), Vector2(144, 24))
				if bot:
					_button(Rect2(row.position, Vector2(70, 24)), "Remove", func(): menu.lobby_remove(slot))
					_button(Rect2(row.position + Vector2(74, 0), Vector2(70, 24)), "Change",
						func(): menu.lobby_bot(slot))
				elif joined:
					_button(row, "Remove", func(): menu.lobby_remove(slot))
				else:
					_button(row, "Add bot", func(): menu.lobby_bot(slot))

	## B1, B2... for the bots set up for the next party.
	func _bot_label(slot: int) -> String:
		var list := Party.bot_slots()
		return "B%d" % (list.find(slot) + 1)
