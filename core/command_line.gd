extends Node
## Autoload "CommandLine": start the game straight into something. Options go after
## "--" (Godot's own options, like --headless, go before it):
##
##   godot --path . -- --host --party
##   godot --headless --path . -- --host --public --port=7800 --players=0 --wait=2 --party
##   ./BotParty.x86_64 -- --join=192.168.1.20:7777
##
## --help                 this list
## --host                 host an online game        --public   list it on the server list
## --port=N               UDP port to host on        --name=X   your name
## --list=URL             server list address
## --join=ADDRESS         join a game (ip or ip:port)
## --players=N            local players (0: a host with nobody playing on it)
## --wait=N               host: wait until N players are in before starting
## --party                start a party              --campaign[=LEVEL]  start the campaign
## --arena=NAME|FILE      party arena: random, steps, pillar, windy, meteor, or a map file
## --bots=N               computer players           --bot-skill=easy|normal|hard
## --state=NAME           load a save state (console "savestate NAME")
## --editor               open the map editor

const HELP := """Bot Party command line (options go after "--"):
  --help                  this list
  --host [--public]       host an online game (--public: on the server list)
  --port=N --name=X       hosting port, your name
  --list=URL              server list address
  --join=ADDRESS          join a game (ip or ip:port)
  --players=N             local players (0: nobody plays on this computer)
  --wait=N                host: wait until N players are in before starting
  --party | --campaign[=LEVEL]
  --arena=NAME|FILE       random, steps, pillar, windy, meteor, or a map file
  --bots=N --bot-skill=easy|normal|hard
  --state=NAME            load a save state
  --editor                open the map editor"""

var options := {}


func _ready() -> void:
	options = parse(OS.get_cmdline_user_args())
	if not options.is_empty():
		_run.call_deferred()


## "--a=1 --b" -> {"a": "1", "b": ""}
static func parse(args: PackedStringArray) -> Dictionary:
	var out := {}
	for a in args:
		if not a.begins_with("--"):
			continue
		var kv := a.trim_prefix("--").split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else ""
	return out


func _run() -> void:
	var o := options
	if o.has("help"):
		print(HELP)
		get_tree().quit()
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var gs := get_node("/root/GameState")
	var net := get_node("/root/Net")
	var party := get_node("/root/Party")
	if o.has("name"):
		net.player_name = o.name
	if o.has("list"):
		net.lobby_url = o.list
	if o.has("port") and o.port.is_valid_int():
		net.host_port = clampi(int(o.port), 1024, 65535)
	if o.has("players") and o.players.is_valid_int():
		var n := clampi(int(o.players), 0, gs.MAX_PLAYERS)
		gs.joined.clear()
		for s in n:
			gs.joined.append(s + 1)
	if o.has("bots") and o.bots.is_valid_int():
		var skill := maxi(0, ["easy", "normal", "hard"].find(str(o.get("bot-skill", "normal")).to_lower()))
		party.set_bots(int(o.bots), skill)
	if o.has("arena"):
		party.arena_choice = _arena(o.arena)
	if o.has("state"):
		print(SaveStates.load_state(get_tree(), o.state))
		return
	if o.has("editor"):
		get_node("/root/Transition").change_scene("res://editor/map_editor.tscn")
		return
	if o.has("join"):
		net.join_address(o.join)
		print("Joining ", o.join)
		return
	if o.has("host"):
		var err: Error = net.host(o.has("public"))
		if err != OK:
			printerr("Can't host on port %d" % net.host_port)
			return
		print("Hosting on port %d%s" % [net.host_port, " (listed)" if o.has("public") else ""])
		var wait := int(o.get("wait", "0")) if o.get("wait", "").is_valid_int() else 0
		while net.roster.size() < wait:
			await get_tree().create_timer(0.5).timeout
	if o.has("party"):
		print("Starting a party with %d player(s)" % maxi(gs.joined.size(), net.roster.size()))
		party.new_game()
	elif o.has("campaign"):
		print("Starting the campaign")
		var level := int(o.campaign) - 1 if o.campaign.is_valid_int() else 0
		gs.start_level(clampi(level, 0, gs.levels.size() - 1))


func _arena(name: String) -> String:
	var party := get_node("/root/Party")
	var short := {"steps": 0, "pillar": 1, "windy": 2, "meteor": 3}
	if short.has(name.to_lower()):
		return party.ARENAS[short[name.to_lower()]]
	if name.ends_with(".json") or name.ends_with(".tscn"):
		return "map:" + name
	return "random"
