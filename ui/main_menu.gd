extends Control
## Title screen. The menu is one of the game's machines: every option sits on a
## pressure button, and a live cable runs from the machine to the selected one.
##   Up/Down (arrows or any player's keys) move, Enter / Space / any jump key
##   chooses, Left/Right change a setting, Esc goes back.
## "Players" is the lobby: each player presses their own jump key to join.

const TITLE := "Bot Party"
const VERSION := "v0.33"
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


func _exit_tree() -> void:
	var chat := get_node_or_null("/root/Chat")
	if chat:
		chat.dock(null)  # back to its corner in the levels


func _ready() -> void:
	theme = UiTheme.make()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_layout()
	GameState.joined_changed.connect(func(): _refresh_footer(); if _screen == "players": _lobby.queue_redraw())
	Net.status.connect(func(t): _hint.text = t)
	Net.connected.connect(func(): if _screen in ["online", "servers"]: _show("online_lobby"))
	Net.roster_changed.connect(func(): if is_inside_tree() and _screen == "mods_offer" and Net.computers.has(Net.my_id()): _show("online_lobby"))
	Net.failed.connect(func(reason):
		if is_inside_tree() and _screen in ["online", "servers", "online_lobby"]:
			_show("online")
			_hint.text = reason)
	Net.roster_changed.connect(func():
		if not is_inside_tree():
			return  # (leaving the menu)
		if _screen == "online_lobby":
			_show("online_lobby", true)
		elif _screen == "kick" and not Net.computers.has(_kick_peer):
			_show("online_lobby" if Net.is_online() else "online"))
	Net.servers_listed.connect(_on_servers)
	Net.mods_offered.connect(func(list):
		if is_inside_tree():
			_mods_offer = list
			_show("mods_offer"))
	Net.mods_progress.connect(func(done, total):
		if is_inside_tree():
			_hint.text = "Downloading the mods: %d %%" % roundi(100.0 * done / maxf(1.0, total)))
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
				{"text": "Mods", "on_accept": func(): _show("mods"), "info": "Items, maps, game modes, hats and textures made by players.",
					"enabled": not Net.is_online()},
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
			if Party.has_save() and not Net.is_online():
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
			_items.append({"text": "Equal odds", "info": "Every item that's on is as likely as the others (ignores Party > Items odds).",
				"value": func(): return onoff.call("equal_odds"), "on_left": func(): flip.call("equal_odds"), "on_right": func(): flip.call("equal_odds"), "on_accept": func(): flip.call("equal_odds")})
			_items.append({"text": "Reset", "info": "Back to the usual rules.", "on_accept": func():
				Party.rules = Party.RULE_DEFAULTS.duplicate(); Party.save_weights(); _show("party_rules", true)})
			_items.append({"text": "Back", "on_accept": func(): _back()})
		"party_items":
			# Two groups: the usual items (the % is their share of the box), then the
			# special ones (their share of what Special crates give).
			for group in [false, true]:
				var ids: Array = Party.listed_items().filter(func(k): return Party.is_special(k) == group)
				if ids.is_empty():
					continue
				_items.append({"text": "Special items" if group else "Items", "enabled": false, "size": 26, "heading": true})
				for id in ids:
					_items.append(_item_row(id))
				if not group:
					_items.append(_special_crate_row())
			_items.append({"text": "Reset", "on_accept": func():
				Party.reset_weights()
				Party.rules.specials = Party.RULE_DEFAULTS.specials
				Party.save_weights()
				_refresh_info(), "info": "Back to the default odds."})
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
			# Each hosted game is a room of its own, drawn as its own card with its
			# own players: the ones waiting for players first, then the ones playing.
			var rooms := _servers.duplicate()
			rooms.sort_custom(func(a, b): return _room_waiting(a) and not _room_waiting(b))
			for e in rooms:
				var entry: Dictionary = e
				var full: bool = int(entry.players) >= int(entry.max)
				var mode := str(entry.get("mode", ""))
				var doing: String = {"party": "Playing party mode", "campaign": "Playing the campaign"}.get(mode, "Waiting for players")
				var names: Array = entry.get("names", [])
				_items.append({"text": str(entry.name).left(18), "room": entry, "enabled": not full,
					"info": "%s\n%d of %d players%s%s%s" % [doing, int(entry.players), int(entry.max), "  (full)" if full else "",
						("\nIn this room: " + ", ".join(names)) if not names.is_empty() else "",
						"\n(relay available)" if entry.get("relay", false) else ""],
					"on_accept": func(): _start(func(): _hint.text = "Connecting..."; Net.join_listed(entry, entry.you))})
			_items.append({"text": "Refresh", "on_accept": func(): _listing = true; _servers.clear(); _show("servers", true); Net.list_servers()})
			_items.append({"text": "Back", "on_accept": func(): _back()})
		"online_lobby":
			if Net.is_host():
				_items = [
					{"text": "Campaign", "on_accept": func(): _show("campaign")},
					{"text": "Party", "on_accept": func(): _show("party"),
						"info": "Start a party, and set it up first if you like (arena, rules, items): like playing at home."},
				]
				# The others' computers: kick or ban them.
				for peer in Net.computers:
					if int(peer) == 1:
						continue
					var id := int(peer)
					var who := str(Net.computers[peer])
					_items.append({"text": "Kick %s..." % who.left(12), "size": 34,
						"info": "%s's computer. Jump: send them out of the game, or ban them." % who,
						"peer": id, "on_accept": func(): _kick_peer = id; _show("kick")})
				_items.append({"text": "Chat", "on_accept": func(): get_node("/root/Chat").open(), "info": "Talk to the others (C or / anywhere while online)."})
				_items.append(_name_item())
				_items.append({"text": "Close game", "on_accept": func(): Net.leave(); _show("online")})
			else:
				_items = [{"text": "Chat", "on_accept": func(): get_node("/root/Chat").open(), "info": "Talk to the others (C or / anywhere while online)."},
					_name_item(),
					{"text": "Leave", "on_accept": func(): Net.leave(); _show("online")}]
		"mods_offer":
			# The host can send the mods its game needs: they run code, so ask.
			var lines := []
			var total := 0
			for o in _mods_offer:
				lines.append("- %s %s (%s)" % [o.name, o.version, _size_text(int(o.size))])
				total += int(o.size)
			var info := "This game needs:\n%s\n\nMods run code on your computer: say yes only if you trust the host. They're on for this game only." % "\n".join(lines)
			_items = [
				{"text": "Download and join", "info": info, "on_accept": func(): _hint.text = "Downloading the mods..."; Net.accept_mods(true)},
				{"text": "Don't join", "info": info, "on_accept": func(): Net.accept_mods(false); _show("online")},
			]
		"kick":
			var who := str(Net.computers.get(_kick_peer, "?"))
			_items = [
				{"text": "Kick", "on_accept": func(): Net.kick(_kick_peer); _show("online_lobby"),
					"info": "%s and their players leave the game. They can join again." % who},
				{"text": "Ban", "on_accept": func(): Net.kick(_kick_peer, true); _show("online_lobby"),
					"info": "%s and their players leave the game and can't come back while you host (same name or address)." % who},
				{"text": "Back", "on_accept": func(): _show("online_lobby")},
			]
		"settings":
			_items = [
				{"text": "Music", "key": "music_volume", "on_left": func(): _bump("music_volume", -0.1), "on_right": func(): _bump("music_volume", 0.1), "on_accept": func(): _bump("music_volume", 0.1, true), },
				{"text": "Fullscreen", "key": "fullscreen", "on_left": func(): _toggle("fullscreen"), "on_right": func(): _toggle("fullscreen"), "on_accept": func(): _toggle("fullscreen")},
				{"text": "Distant players", "key": "distant_players", "on_left": func(): _toggle("distant_players"), "on_right": func(): _toggle("distant_players"), "on_accept": func(): _toggle("distant_players"),
					"info": "A robot off the screen gets a bubble at the edge with a small view of it."},
				{"text": "Bubble view", "key": "bubble_view", "on_left": func(): _bump("bubble_view", -0.1), "on_right": func(): _bump("bubble_view", 0.1), "on_accept": func(): _bump("bubble_view", 0.1, true),
					"info": "How much of the level a distant player's bubble shows. More bars: zoomed further out."},
				{"text": "Bubble size", "key": "bubble_size", "on_left": func(): _bump("bubble_size", -0.1), "on_right": func(): _bump("bubble_size", 0.1), "on_accept": func(): _bump("bubble_size", 0.1, true),
					"info": "How big a distant player's bubble is on the screen."},
				{"text": "Screen shake", "key": "screen_shake", "on_left": func(): _toggle("screen_shake"), "on_right": func(): _toggle("screen_shake"), "on_accept": func(): _toggle("screen_shake"),
					"info": "Explosions (bombs, nukes, black holes) shake the screen."},
				{"text": "Controls", "on_accept": func(): _show("controls"), "info": "Change the keys of each player." if not Net.is_online() else "Change the keys before going online.",
					"enabled": not Net.is_online()},
				{"text": "Data folder", "on_accept": func(): _open_folder(OS.get_user_data_dir()),
					"info": "Your saves, settings, maps and mods:\n%s" % OS.get_user_data_dir()},
				{"text": "Game folder", "on_accept": func(): _open_folder(_game_folder()),
					"info": "Where the game itself is:\n%s" % _game_folder()},
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
			_items.append({"text": "Explore", "on_accept": func(): _explore(),
				"info": "Mods shared on GitHub (repositories tagged \"%s\"): pick one to install it." % Mods.TOPIC})
			_items.append({"text": "Browse...", "on_accept": func(): _browse_pack(),
				"info": "Install a mod pack (.pck) from your computer."})
			_items.append({"text": "Looks", "on_accept": func(): _show("looks"),
				"info": "Hats and other cosmetics from mods: who wears what."})
			if not Mods.mods.is_empty():
				_items.append({"text": "Installed", "enabled": false, "size": 26, "heading": true})
			for m in Mods.mods:
				var mod: Dictionary = m
				_items.append({"text": mod.name.left(16), "size": 34,
					"value": func(): return "On" if mod.enabled else "Off",
					"on_accept": func(): _toggle_mod(mod), "on_left": func(): _toggle_mod(mod), "on_right": func(): _toggle_mod(mod),
					"info": _mod_info(mod)})
			_items.append({"text": "Open mods folder", "on_accept": func(): Mods.open_folder(),
				"info": "Put mod packs (.pck) or mod folders here:\n%s\nThen come back to this screen." % ProjectSettings.globalize_path(Mods.DIR)})
			_items.append({"text": "Back", "on_accept": func(): _back()})
		"mods_explore":
			_items.append({"text": "Search: " + (_explore_search.left(14) if _explore_search != "" else "all"), "size": 34,
				"info": "Words to look for in the mods' names and descriptions.\nJump: type them (empty: all).",
				"on_accept": func(): _edit_text("Search mods", _explore_search, func(t): _explore_search = t.strip_edges(); _explore())})
			var cycle_sort := func(d: int):
				var sorts: Array = Mods.EXPLORE_SORTS
				_explore_sort = sorts[posmod(sorts.find(_explore_sort) + d, sorts.size())]
				_explore()
			_items.append({"text": "Sort: " + _explore_sort, "size": 34,
				"info": "Left / right: by stars, date (last update), name or downloads.",
				"on_left": func(): cycle_sort.call(-1), "on_right": func(): cycle_sort.call(1), "on_accept": func(): cycle_sort.call(1)})
			if _explore_list.is_empty():
				_items.append({"text": "Looking..." if _exploring else "No mods found", "enabled": false})
			for r in _explore_list:
				var repo: Dictionary = r
				var installed := not Mods.get_mod(ArenaMap.slug(repo.name)).is_empty()
				_items.append({"text": repo.name.left(18), "size": 34,
					"info": "%s\nby %s  ·  %d star%s%s  ·  %s%s\n\nJump: install it (its latest release).\nOnly install mods you trust: they run their own code." % [
						repo.description.left(160), repo.author, repo.stars, "" if repo.stars == 1 else "s",
						("  ·  %d downloads" % repo.downloads) if int(repo.get("downloads", -1)) >= 0 else "",
						repo.get("updated", ""), "\n(installed)" if installed else ""],
					"on_accept": func(): _install_repo(repo)})
			_items.append({"text": "Refresh", "on_accept": func(): _explore()})
			_items.append({"text": "Back", "on_accept": func(): _back()})
		"looks":
			var all: Dictionary = Mods.cosmetics()
			var ids := all.keys()
			ids.sort()
			ids.push_front("")
			if all.is_empty():
				_items.append({"text": "No cosmetics", "enabled": false, "info": "Switch on a mod that has some (like Hats) in Mods."})
			else:
				for slot in range(1, GameState.MAX_PLAYERS + 1):
					var s := slot
					var cycle := func(d: int):
						var at := ids.find(GameState.look_of(s))
						var looks: Dictionary = GameState.settings.get("looks", {})
						looks[str(s)] = ids[posmod(at + d, ids.size())]
						GameState.settings.looks = looks
						GameState.save_settings()
						_show("looks", true)
					var cur := GameState.look_of(s)
					var item := {"text": "P%d" % s, "size": 34,
						"value": func(): return "< %s >" % (str(all[cur].name).left(14) if all.has(cur) else "None"),
						"on_left": func(): cycle.call(-1), "on_right": func(): cycle.call(1), "on_accept": func(): cycle.call(1),
						"info": "What P%d's robot wears (the key set %d, online too).\nLeft / right: change." % [s, s]}
					if all.has(cur):
						item.icon = Mods.look_texture(cur)
					_items.append(item)
			_items.append({"text": "Back", "on_accept": func(): _back()})
	_heading.text = {"main": "", "campaign": _campaign_heading(), "party": "Party", "party_items": "Party items", "party_rules": "Party rules", "players": "Players",
		"settings": "Settings", "controls": "Controls", "mods": "Mods", "mods_explore": "Explore mods", "looks": "Looks", "online": "Online", "servers": "Server list", "online_lobby": _online_heading(),
		"kick": "Kick or ban %s" % str(Net.computers.get(_kick_peer, "?")), "mods_offer": "Mods for this game"}[screen]
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
	_lobby.mouse_filter = Control.MOUSE_FILTER_STOP if screen == "players" or screen == "online_lobby" else Control.MOUSE_FILTER_IGNORE
	# Online lobby: the chat goes under the computers' boxes.
	var chat := get_node_or_null("/root/Chat")
	if screen == "online_lobby":
		_lobby.offset_bottom = 490
		if chat:
			chat.dock(Rect2(get_viewport_rect().size.x - 700, 492, 640, 160))
	else:
		_lobby.offset_bottom = 580
		if chat:
			chat.dock(null)
	_lobby.clip_contents = screen == "online_lobby"
	_lobby._scroll_focus = -1
	if screen == "players" and not Net.is_online():
		_hint.text = "Jump: join / leave    Arrows: choose a slot    Delete: remove    +: add a bot / how good"
	if screen == "online_lobby":
		if not keep_index:
			_set_lobby_focus("players" if Net.my_slots().is_empty() else "menu")
		else:
			_set_lobby_focus(_lobby_focus)
	else:
		_list.modulate.a = 1.0
		_cable.visible = true
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
		row.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				if _screen == "online_lobby":
					_set_lobby_focus("menu")
				_select(i)
				_accept())
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


## Party > Items: one item's row.
func _item_row(id: String) -> Dictionary:
	var def: Dictionary = Party.ITEMS[id]
	var info := "Left / right: how often\nJump: on / off"
	if Party.is_special(id):
		info = "Only comes out of Special crates.\nThe % is its share of them.\n" + info
	else:
		info = "The % is its share of the box.\n" + info
	return {"text": def.name, "icon": Party.icon(id), "size": 34, "info": info,
		"value": func(): return _item_value(id),
		"on_left": func(): _set_item_weight(id, Party.weight(id) - 1),
		"on_right": func(): _set_item_weight(id, Party.weight(id) + 1),
		"on_accept": func(): _set_item_weight(id, 0 if Party.weight(id) > 0 else int(def.get("weight", 10)))}


## Settings > Data folder / Game folder.
func _open_folder(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)
	OS.shell_open(path)
	_hint.text = "Opened " + path


## The installed game's folder (or the project's, when run from Godot).
func _game_folder() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://")
	return OS.get_executable_path().get_base_dir()


## Party > Items row value: chance in % (or Off) plus a bar for the weight.
# --- Online -----------------------------------------------------------------------

var _servers: Array = []
var _kick_peer := 0  # host: whose computer the Kick / ban screen is about
var _mods_offer: Array = []  # client: the mods the host can send


static func _size_text(bytes: int) -> String:
	if bytes >= 1024 * 1024:
		return "%.1f MB" % (bytes / 1048576.0)
	return "%d KB" % maxi(1, bytes / 1024)
var _online_bot_skill := 1  # host: how good the bots added online are
var _lobby_focus := "menu"  # online lobby: "menu" (the options) or "players" (your box)


func _set_lobby_focus(f: String) -> void:
	_lobby_focus = f
	_list.modulate.a = 0.45 if f == "players" else 1.0
	_cable.visible = f == "menu"
	if _screen == "online_lobby":
		_hint.text = (("Jump: join   Arrows: a place   +: bot / level   Del: remove" if Net.is_host()
				else "Jump: join / leave    Left: menu    C: chat") if f == "players"
			else "Right: your players    C: chat") + ("    Waiting for the host to start." if Net.is_client() else "")
var _listing := false
var _last_address := ""
var _editor: PanelContainer


func _host(public: bool) -> void:
	if Net.host(public) == OK:
		_show("online_lobby")


func _set_name(t: String) -> void:
	Net.rename(t if t.strip_edges() != "" else "Player")  # online: everyone sees it
	_show("online_lobby" if Net.is_online() else "online", true)


## "Name: Elian" in the online lobby: rename yourself, everyone sees it.
func _name_item() -> Dictionary:
	return {"text": "Name: " + Net.player_name.left(12), "size": 34,
		"on_accept": func(): _edit_text("Your name", Net.player_name, _set_name),
		"info": "What the others see you as (your box, your robots, the chat)."}


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


static func _room_waiting(entry: Dictionary) -> bool:
	return str(entry.get("mode", "")) in ["", "lobby"]


func _online_heading() -> String:
	if Net.is_host():
		return "Your game: %d / %d players" % [Net.taken_places(), GameState.MAX_PLAYERS]
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
	Net.typing = true  # online: typing doesn't move your robots
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
	Net.typing = false


func _campaign_heading() -> String:
	var c: Dictionary = GameState.campaign()
	return "Campaign: %s" % c.name


## Party > Items: how often a card in the box is a Special crate (off, rare,
## often): the "specials" rule.
func _special_crate_row() -> Dictionary:
	var r: Dictionary = Party.rules
	var set_to := func(v: int):
		r.specials = clampi(v, 0, 2)
		Party.save_weights()
		_refresh_info()
	return {"text": "Special card", "icon": Party.icon("special"), "size": 34,
		"info": "How often a card in the box is a Special crate (it gives one of the special items below): off, rare or often.\nLeft / right: how often\nJump: on / off",
		"value": func():
			var v := clampi(int(r.specials), 0, 2)
			return {"text": "Off" if v == 0 else "%d%%" % roundi(Party.SPECIAL_ODDS[v] * 100.0), "bar": v / 2.0},
		"on_left": func(): set_to.call(int(r.specials) - 1),
		"on_right": func(): set_to.call(int(r.specials) + 1),
		"on_accept": func(): set_to.call(0 if int(r.specials) > 0 else 1)}


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

# --- Mods > Explore / Browse ---------------------------------------------------------

var _explore_list: Array = []
var _exploring := false
var _explore_search := ""
var _explore_sort := "Stars"


func _explore() -> void:
	_exploring = true
	_explore_list = []
	_show("mods_explore", _screen == "mods_explore")
	Mods.explore(func(list: Array, err: String):
		_exploring = false
		_explore_list = list
		if is_inside_tree() and _screen == "mods_explore":
			_show("mods_explore", true)
			if err != "":
				_hint.text = err, _explore_search, _explore_sort)


func _install_repo(repo: Dictionary) -> void:
	_hint.text = "Downloading %s..." % repo.name
	Mods.install_from_repo(repo.full_name, func(err: String):
		if not is_inside_tree():
			return
		_hint.text = err if err != "" else "%s is installed and on" % repo.name
		if _screen == "mods_explore":
			_show("mods_explore", true))


## Mods > Browse: pick a mod pack on this computer.
func _browse_pack() -> void:
	var done := func(path: String):
		var err: String = Mods.install_pack(path)
		_hint.text = err if err != "" else "%s is installed and on" % path.get_file()
		_show("mods", true)
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		DisplayServer.file_dialog_show("Install a mod pack", OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS), "", false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, PackedStringArray(["*.pck, *.zip ; Mod packs"]),
			func(ok: bool, paths: PackedStringArray, _filter: int):
				if ok and not paths.is_empty():
					done.call(paths[0]))
		return
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.pck, *.zip ; Mod packs"])
	dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	dialog.title = "Install a mod pack"
	dialog.file_selected.connect(func(p): done.call(p); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.7)


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
	if not mod.get("cosmetics", {}).is_empty():
		adds.append("%d cosmetic%s" % [mod.cosmetics.size(), "s" if mod.cosmetics.size() > 1 else ""])
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
		if Net.is_online():
			_show("online_lobby")
			_hint.text = "Nobody has joined yet: Jump in your box"
		else:
			_show("players")
		return
	action.call()


func _back() -> void:
	if _screen == "campaign" and Net.is_online():
		_show("online_lobby")
		return
	if _screen == "online_lobby":
		return  # leave with the Leave / Close option
	if _screen == "kick":
		_show("online_lobby")
		return
	if _screen == "mods_offer":
		Net.accept_mods(false)
		_show("online")
		return
	if _screen == "servers":
		_show("online")
		_select(2)
		return
	if _screen in ["party_items", "party_rules", "controls", "mods_explore", "looks"]:
		var text: String = {"party_items": "Items", "party_rules": "Rules", "controls": "Controls", "mods_explore": "Explore", "looks": "Looks"}[_screen]
		_show({"party_items": "party", "party_rules": "party", "controls": "settings", "mods_explore": "mods", "looks": "mods"}[_screen])
		for i in _items.size():
			if _items[i].text == text:
				_select(i)
		return
	if _screen == "party" and Net.is_online():
		_show("online_lobby")
		for i in _items.size():
			if _items[i].text == "Party":
				_select(i)
		return
	var back_to := {"campaign": 0, "party": 1, "online": 2, "players": 3, "mods": 4, "settings": 5}
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
		# Online, each computer's own key sets (the game slots' keys are taken).
		var a := ("k%d_%s" if Net.is_online() else "p%d_%s") % [slot, suffix]
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
	if _screen == "online_lobby" and _lobby_focus == "players":
		# Your box has the focus: each key set's jump adds or takes away its
		# player; left (or back) goes to the menu.
		var who := _player_action(event, "action_1")
		if who:
			if who in Net.my_slots().values():
				Net.request_leave(who)
			else:
				Net.request_join(who)
			_handled(stick)
			return
		var key: Key = event.physical_keycode if event is InputEventKey and event.pressed and not event.echo else KEY_NONE
		if Net.is_host():
			# The host picks a place of its box: + adds a bot there (again: its
			# level changes), Delete takes it away. Like the Players screen.
			if key in [KEY_INSERT, KEY_EQUAL, KEY_PLUS, KEY_KP_ADD] or _player_action(event, "action_3"):
				var at := Net.bot_at(_lobby.online_pick)
				Net.set_bot(_lobby.online_pick, (int(Net.bots[at]) + 1) % 3 if at != 0 else _online_bot_skill)
				if at == 0 and Net.bot_at(_lobby.online_pick) == 0:
					_hint.text = "That place is taken (or the game is full)"
				_handled(stick); return
			if key in [KEY_DELETE, KEY_BACKSPACE] or _player_action(event, "action_2"):
				Net.remove_bot_at(_lobby.online_pick)
				_handled(stick); return
			var per_row: int = _lobby.layout_row
			var col := (_lobby.online_pick - 1) % per_row
			var move := 0
			if event.is_action_pressed("ui_left", true) or _player_action(event, "move_left"):
				if col == 0:
					_set_lobby_focus("menu")
					_handled(stick); return
				move = -1
			elif event.is_action_pressed("ui_right", true) or _player_action(event, "move_right"):
				move = 1 if col < per_row - 1 else 0
			elif event.is_action_pressed("ui_up", true) or _player_action(event, "move_up"):
				move = -per_row
			elif event.is_action_pressed("ui_down", true) or _player_action(event, "move_down"):
				move = per_row
			if move != 0 or event.is_action_pressed("ui_up", true) or event.is_action_pressed("ui_down", true) or event.is_action_pressed("ui_right", true) \
					or _player_action(event, "move_up") or _player_action(event, "move_down") or _player_action(event, "move_right"):
				var to: int = _lobby.online_pick + move
				if to >= 1 and to <= GameState.MAX_PLAYERS:
					_lobby.online_pick = to
				_handled(stick); return
			if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
				_set_lobby_focus("menu")
				_handled(stick)
			return
		if event.is_action_pressed("ui_left", true) or _player_action(event, "move_left") \
				or event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause") or _player_action(event, "action_2"):
			_set_lobby_focus("menu")
			_handled(stick)
			return
		if event.is_action_pressed("ui_up", true) or event.is_action_pressed("ui_down", true) or event.is_action_pressed("ui_right", true) \
				or _player_action(event, "move_up") or _player_action(event, "move_down") or _player_action(event, "move_right"):
			_handled(stick)  # nothing to move to there
		return
	if _screen == "online_lobby" and (event.is_action_pressed("ui_right", true) or _player_action(event, "move_right")) \
			and not _items[_index].has("on_right"):
		_set_lobby_focus("players")
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
		if _items[_index].has("on_left"):
			_items[_index].on_left.call()
		elif not _screen in ["main", "online_lobby"]:
			_back()  # left with nothing to change: back
		_handled(stick)
	elif event.is_action_pressed("ui_right", true) or _player_action(event, "move_right"):
		if _items[_index].has("on_right"): _items[_index].on_right.call()
		_handled(stick)
	elif event.is_action_pressed("ui_accept") or _player_action(event, "action_1"):
		_accept(); _handled(stick)
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause") or _player_action(event, "action_2"):
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
		if item.has("room"):
			return Vector2(4 + 8 + 560 + 4, 31)  # the card's right edge
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
		if item.has("room"):
			_draw_room(item)
			return
		if item.get("heading", false):
			# A section title (Party > Items): no button, a line under it.
			draw_string(UiTheme.FONT_BOLD, Vector2(4, 44), item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UiTheme.ACCENT)
			draw_line(Vector2(4, 54), Vector2(size.x - 20, 54), UiTheme.ACCENT, 3.0)
			return
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


	## A hosted game in the server list: a card of its own (name, who's in it,
	## waiting or playing, how full).
	func _draw_room(item: Dictionary) -> void:
		var room: Dictionary = item.room
		var selected: bool = index == menu._index
		var enabled: bool = item.get("enabled", true)
		var waiting: bool = menu._room_waiting(room)
		var card := Rect2(Vector2(4 + (8.0 if selected else 0.0), 2), Vector2(560, 58))
		draw_rect(card, UiTheme.LIME if selected else Color.WHITE)
		draw_rect(card, UiTheme.ACCENT if selected else UiTheme.INK, false, 4.0 if selected else 3.0)
		# Waiting / playing tag on the left edge.
		var tag := Rect2(card.position + Vector2(8, 10), Vector2(96, 38))
		draw_rect(tag, UiTheme.LIVE if waiting else UiTheme.CRATE)
		draw_rect(tag, UiTheme.INK, false, 2.0)
		draw_string(UiTheme.FONT_MEDIUM, tag.position + Vector2(0, 28), "Open" if waiting else "Playing",
			HORIZONTAL_ALIGNMENT_CENTER, tag.size.x, 24, UiTheme.INK)
		var color: Color = UiTheme.INK if enabled else Color("9a97a6")
		var x := tag.end.x + 14.0
		draw_string(UiTheme.FONT_BOLD, Vector2(x, 30), item.text, HORIZONTAL_ALIGNMENT_LEFT, 300, 30, color)
		var names: Array = room.get("names", [])
		var who := ", ".join(names) if not names.is_empty() else "%d player%s" % [int(room.players), "" if int(room.players) == 1 else "s"]
		draw_string(UiTheme.FONT_MEDIUM, Vector2(x, 52), who, HORIZONTAL_ALIGNMENT_LEFT, 300, 20, UiTheme.MUTED)
		draw_string(UiTheme.FONT_BOLD, Vector2(card.end.x - 90, 42), "%d/%d" % [int(room.players), int(room.max)],
			HORIZONTAL_ALIGNMENT_RIGHT, 78, 30, color)


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
	var _scroll := 0.0       # online: how far the computers' boxes are scrolled
	var _scroll_to := 0.0
	var _scroll_focus := -1
	var online_pick := 1    # host: the place of its box that + / Delete act on
	var layout_row := 4     # how the 8 places are laid out (4 x 2, or 8 in a row)
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
		if Net.is_online() and event is InputEventMouseButton and event.pressed:
			var row := (size.y - 36 - 12) / 2.0 + 12.0
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_scroll_to = (roundf(_scroll_to / row) + 1.0) * row
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_scroll_to = maxf(0.0, (roundf(_scroll_to / row) - 1.0) * row)
			elif event.button_index == MOUSE_BUTTON_LEFT and menu:
				menu._set_lobby_focus("players")
			return
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
		if not offline:
			_draw_online()
			return
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

	## Online: one box per computer (the host first; this computer's marked
	## "you"), each with its own 8 places like the Players screen, smaller: its
	## players on their buttons, the free places with the key that joins there.
	## When the game is full, every free place is greyed out.
	func _draw_online() -> void:
		var order: Array = [1]
		for peer in Net.computers:
			if not int(peer) in order:
				order.append(int(peer))
		for r in Net.roster:
			if not int(r.peer) in order:
				order.append(int(r.peer))
		if not Net.my_id() in order:
			order.append(Net.my_id())
		var free := GameState.MAX_PLAYERS - Net.taken_places()
		var full := free <= 0
		var n := order.size()
		# One or two columns of boxes, the 8 places in 4 x 2 or in a row of 8:
		# whichever shows the places biggest (a place is 160 x 185 at full size).
		var gap := 12.0
		var area := Vector2(size.x - 14, size.y - 36)
		var cols := 1
		var per_row := 4
		var zoom := 0.0
		for c in [2, 1]:
			if c > n:
				continue
			# At most 2 rows on screen; more computers than that: it scrolls.
			var rws: int = mini(ceili(n / float(c)), 2)
			var w: float = (area.x - gap * (c - 1)) / c
			var h: float = (area.y - gap * (rws - 1)) / rws
			for pr in [4, 8]:
				var z: float = clampf(minf((w - 16) / (pr * 160.0), (h - 40) / ((8 / pr) * 185.0)), 0.15, 0.6)
				if z > zoom + 0.01:
					zoom = z
					cols = c
					per_row = pr
		var box := Vector2(minf((area.x - gap * (cols - 1)) / cols, 16 + per_row * 160.0 * zoom), 40 + (8 / per_row) * 185.0 * zoom)
		layout_row = per_row
		var all_rows := ceili(n / float(cols))
		if all_rows > 2:
			box.y = (area.y - gap) / 2.0  # two rows a screen, scrolled a row at a time
		# Scrolling (like the settings list): to the box of the computer chosen
		# in the menu (host: Kick...), else to ours; the mouse wheel too.
		var content := ceili(n / float(cols)) * (box.y + gap) - gap
		var focus: int = menu._items[menu._index].get("peer", Net.my_id()) if menu and not menu._items.is_empty() else Net.my_id()
		var fk := maxi(0, order.find(focus))
		if focus != _scroll_focus:
			_scroll_focus = focus
			var top := (fk / cols) * (box.y + gap)
			if top < _scroll_to or top + box.y > _scroll_to + area.y:
				_scroll_to = top + box.y - area.y if top > _scroll_to else top
		_scroll_to = clampf(_scroll_to, 0.0, maxf(0.0, content - area.y))
		_scroll = lerpf(_scroll, _scroll_to, 0.25)
		if content > area.y:
			# A little bar on the right: where we are in the list.
			var bar_h := area.y * area.y / content
			draw_rect(Rect2(area.x + 6, _scroll / content * area.y, 6, bar_h), UiTheme.MUTED)
		for k in n:
			var peer: int = order[k]
			var r := Rect2(Vector2((k % cols) * (box.x + gap), (k / cols) * (box.y + gap) - _scroll), box)
			if r.position.y < -2.0 or r.end.y > area.y + 2.0:
				continue  # only whole boxes (it's scrolling)
			var mine := peer == Net.my_id()
			var focused: bool = mine and menu and menu._lobby_focus == "players"
			draw_rect(r, UiTheme.LIME if mine else Color.WHITE)
			if focused:
				draw_rect(r.grow(4), UiTheme.LIVE, false, 4.0)  # where your keys go now
			draw_rect(r, UiTheme.ACCENT if mine else UiTheme.INK, false, 5.0 if focused else (4.0 if mine else 3.0))
			var title := str(Net.computers.get(peer, Net.player_name if mine else Net._name_of_peer(peer)))
			var tags := []
			if peer == 1:
				tags.append("host")
			if mine:
				tags.append("you")
			if not tags.is_empty():
				title += "  (" + ", ".join(tags) + ")"
			draw_string(UiTheme.FONT_BOLD, r.position + Vector2(12, 28), title, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 24, 24, UiTheme.INK)
			# Its 8 places: its key sets 1-8.
			var by_local := {}
			for e in Net.roster:
				if int(e.peer) == peer:
					by_local[int(e.local)] = int(e.slot)
			# The host's bots are in its box too (each its own level).
			var bot_here := {}
			if peer == 1:
				for b in Net.bot_places:
					bot_here[int(Net.bot_places[b])] = int(b)
			var picking: bool = focused and Net.is_host()
			for i in GameState.MAX_PLAYERS:
				var local := i + 1
				var c := r.position + Vector2(8 + ((i % per_row) + 0.5) * 160.0 * zoom, 36 + (95.0 + (i / per_row) * 185.0) * zoom)
				if picking and local == online_pick:
					# The place the host's +, Delete act on.
					draw_rect(Rect2(c + Vector2(-78, -96) * zoom, Vector2(156, 200) * zoom), Color(UiTheme.LIVE, 0.25))
					draw_rect(Rect2(c + Vector2(-78, -96) * zoom, Vector2(156, 200) * zoom), UiTheme.INK, false, 3.0)
				draw_set_transform(c, 0.0, Vector2(zoom, zoom))
				if by_local.has(local):
					_draw_cell(by_local[local], true, "P%d" % local, "")  # its own number on its computer
				elif bot_here.has(local):
					_draw_cell(bot_here[local], true, Net.player_label(bot_here[local]), PartyBot.SKILL_NAMES[int(Net.bots.get(bot_here[local], 1))] + " bot")
				elif full:
					_draw_cell(0, false, "", "", true)
				else:
					_draw_cell(0, false, "", UiTheme.jump_key_text(local) if mine else "")
				draw_set_transform(Vector2.ZERO)
		draw_string(UiTheme.FONT_MEDIUM, Vector2(0, size.y - 6), "Full" if full else "%d free place%s" % [free, "" if free == 1 else "s"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UiTheme.RED if full else UiTheme.MUTED)

	## One place drawn round (0, 0) like on the Players screen: a robot standing
	## on its button (or an empty button), a label and a line under it.
	func _draw_cell(slot: int, joined: bool, label: String, sub: String, greyed := false) -> void:
		var color: Color = PlayerSpawner.COLORS[(slot - 1) % 8] if slot > 0 else Color("c9c6d2")
		var sink := 6.0 if joined else 0.0
		var off := Color("8f8c99") if greyed else Color("c9c6d2")
		draw_texture_rect(TEX_CAP, Rect2(Vector2(-48, -60 + sink), Vector2(96, 96)), false, color if joined else off)
		draw_texture_rect(TEX_BASE, Rect2(Vector2(-48, -60), Vector2(96, 96)), false, Color(0.7, 0.7, 0.75) if greyed else Color.WHITE)
		if joined:
			var t := clampf((Time.get_ticks_msec() - _joined_at.get(slot, 0)) / 250.0, 0.0, 1.0)
			var drop := (1.0 - t) * (1.0 - t) * -70.0
			var r := Rect2(Vector2(-40, -86 + sink + drop), Vector2(80, 80))
			var frame := 0 if t >= 1.0 else 7
			draw_texture_rect_region(TEX_PLAYER_BODY, r, Rect2(frame * 32, 0, 32, 32), color)
			draw_texture_rect_region(TEX_PLAYER_FACE, r, Rect2(frame * 32, 0, 32, 32))
		draw_string(UiTheme.FONT_BOLD, Vector2(-60, 62), label, HORIZONTAL_ALIGNMENT_CENTER, 120, 30,
			UiTheme.INK if joined else Color("8a8796"))
		draw_string(UiTheme.FONT_REGULAR, Vector2(-80, 86), sub, HORIZONTAL_ALIGNMENT_CENTER, 160, 24,
			UiTheme.ACCENT if joined else UiTheme.MUTED)

	## B1, B2... for the bots set up for the next party.
	func _bot_label(slot: int) -> String:
		var list := Party.bot_slots()
		return "B%d" % (list.find(slot) + 1)
