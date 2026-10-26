extends Node
## Autoload "Net": online play.
##
## The host runs the real game. Each client sends the inputs of its own players
## (several people can play on one computer); the host feeds them into its input
## map as if they were local keyboards, so every gameplay script works unchanged.
## The host sends back snapshots of everything that moves or changes (nodes in the
## "net_sync" group implement net_state() / net_apply()), and clients only display.
##
## Ways to connect:
##  - direct: ENet to the host's IP (the host needs UDP port GAME_PORT open)
##  - server list: the host registers on a lobby server (server/lobby_server.py on a
##    VPS); clients pick it from the list and connect directly, or through the
##    lobby server's relay when a direct connection doesn't work.

signal roster_changed
signal status(text: String)
signal connected                    ## client: joined the host
signal failed(reason: String)       ## client: couldn't join / lost the host
signal servers_listed(list: Array)  ## server list arrived (or [] on error)
signal chat_received(who: String, text: String)  ## who = "" for the game's own messages
signal mods_offered(list: Array)    ## client: the host can send the mods we lack ([{id, name, version, size}])
signal mods_progress(done: int, total: int)  ## client: bytes of mods received so far

enum Mode { OFFLINE, HOST, CLIENT }

const GAME_PORT := 7777
const MAX_CLIENTS := 7
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "action_1", "action_2", "action_3"]
## Snapshots every N physics frames (2 = 30 per second), everything resent every FULL_EVERY (1 s).
const SNAPSHOT_EVERY := 2
const FULL_EVERY := 60
const DIRECT_TIMEOUT := 3.0
const CONFIG_PATH := "user://online.cfg"

var mode := Mode.OFFLINE
## Everyone in the game: [{slot, peer, local, name}]. slot = global player number
## (P1..P8), peer = network id (1 = host), local = that computer's own key set.
var roster: Array = []
var bots: Dictionary = {}       # host's bots online: slot -> skill (0-2); everyone knows them
var bot_places: Dictionary = {} # slot -> its place (1-8) in the host's box
var computers: Dictionary = {}  # peer id -> name: every computer in the game (players or not)
var typing := false             # typing in the chat: our players stand still
var banned: Array = []          # host: [{name, ip}] who can't join again while it hosts
## Who you are, and where the server list lives (saved in user://online.cfg).
var player_name := "Player"
## UDP port to host on (Online > Port, or --port on the command line).
var host_port := GAME_PORT
## The game's own server list (project.godot: [bot_party] online/server_list).
var default_lobby_url: String = ProjectSettings.get_setting("bot_party/online/server_list", "")
## The server list in use: the player's own (Online > List), or the default.
var lobby_url := default_lobby_url
var server_name := ""

var _peer: ENetMultiplayerPeer
var _relay_host: RelayHost
var _relay_client: RelayClient
var _lobby: LobbyApi
var _offline_joined: Array[int] = []
var _erased_events := {}        # action -> Array[InputEvent] (host: keys of remote slots)
var _sent := {}                 # host: key -> last state sent
var _frame := 0
var _last_input := {}           # client: slot -> PackedFloat32Array
var _applying := false          # applying something that came from the host
var _connect_timer: SceneTreeTimer
var _pending_relay := {}        # client: listing to fall back to if direct fails
var _hosting_public := false
var _quitting := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Run after the level's physics, so snapshots carry this frame's positions.
	process_physics_priority = 1000
	_load_config()
	_lobby = LobbyApi.new()
	add_child(_lobby)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)


# --- State ---------------------------------------------------------------------

func is_online() -> bool:
	return mode != Mode.OFFLINE


func is_host() -> bool:
	return mode == Mode.HOST


## A client only shows what the host sends; gameplay decisions are the host's.
func is_client() -> bool:
	return mode == Mode.CLIENT


## True while a client applies something the host sent (lets guarded code run).
func applying() -> bool:
	return _applying


func my_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


## Global slots played on this computer -> this computer's key set (local slot).
func my_slots() -> Dictionary:
	var out := {}
	for r in roster:
		if int(r.peer) == my_id():
			out[int(r.slot)] = int(r.local)
	return out


## The key set that controls global slot `slot` on this computer (0 = not ours).
func local_keys_for(slot: int) -> int:
	if not is_online():
		return slot
	return my_slots().get(slot, 0)


# --- Looks (cosmetics from mods) -------------------------------------------------

## The cosmetic the robot in game slot `slot` wears: online, what its player
## chose (in the roster); offline, the key set's choice; bots get one too.
func look_for(slot: int) -> String:
	var mods := _mods()
	var all: Dictionary = mods.cosmetics() if mods else {}
	if all.is_empty():
		return ""
	if is_online():
		for r in roster:
			if int(r.slot) == slot:
				return str(r.get("look", ""))
		if not bots.has(slot):
			return ""
	elif not get_node("/root/Party").bots().has(slot) or not _in_party():
		var mine := GameState.look_of(slot)
		return mine if all.has(mine) else ""
	# Bots: one each, from what's there (the same on every computer).
	var ids := all.keys()
	ids.sort()
	var k := (slot * 7) % (ids.size() + 1)  # (0: none)
	return "" if k == 0 else ids[k - 1]


func _in_party() -> bool:
	var s := get_tree().current_scene
	return s != null and s.has_node("PartyController")


func _my_looks() -> Dictionary:
	var out := {}
	for l in GameState.joined:
		out[str(l)] = GameState.look_of(l)
	return out


## Robots already in the level put on what the roster says.
func _refresh_looks() -> void:
	var scene := get_tree().current_scene if get_tree() else null
	if scene == null:
		return
	for p in get_tree().get_nodes_in_group("players"):
		if scene.is_ancestor_of(p) and p.has_method("set_look"):
			p.set_look(look_for(p.get_meta("player_index", 0) + 1))


## A player online: its computer's name, plus its number there when that
## computer plays several ("Zoe", "Zoe 2"); bots: B1, B2...
func player_label(slot: int) -> String:
	if bots.has(slot):
		var order := bots.keys()
		order.sort()
		return "B%d" % (order.find(slot) + 1)
	for r in roster:
		if int(r.slot) == slot:
			var same := roster.filter(func(o): return int(o.peer) == int(r.peer)).size()
			return str(r.name) if same == 1 else "%s %d" % [r.name, int(r.local)]
	return "P%d" % slot


func name_of(slot: int) -> String:
	for r in roster:
		if int(r.slot) == slot:
			return r.name
	return ""


## Joined slots to save to disk (the offline ones while online).
func offline_joined() -> Array[int]:
	return _offline_joined if is_online() else GameState.joined


# --- Host ----------------------------------------------------------------------

## Starts hosting with the players who already joined on this computer.
## public: listed on the server list (and reachable through its relay).
func host(public: bool) -> Error:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err := ERR_CANT_CREATE
	var port := host_port
	for k in 10:
		# A quiet look first: ENet prints an error for every port it can't open
		# (another game on this computer already uses it).
		var probe := PacketPeerUDP.new()
		var free := probe.bind(host_port + k, "*") == OK
		probe.close()
		if not free:
			continue
		err = _peer.create_server(host_port + k, MAX_CLIENTS)
		if err == OK:
			_peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
			port = host_port + k
			break
	if err != OK:
		status.emit("Can't open port %d" % host_port)
		return err
	multiplayer.multiplayer_peer = _peer
	mode = Mode.HOST
	_take_keys()
	_offline_joined = GameState.joined.duplicate()
	roster.clear()
	computers = {1: player_name.left(16)}
	banned.clear()
	for s in GameState.joined:
		roster.append({"slot": s, "peer": 1, "local": s, "name": player_name})
	server_name = "%s's game" % player_name
	_hosting_public = public
	if public:
		_register(port)
	status.emit("Hosting on port %d" % port)
	roster_changed.emit()
	return OK


func _register(port: int) -> void:
	if lobby_url == "":
		status.emit("Hosting (not listed: no server list address set)")
		return
	var info := {"name": server_name, "port": port, "max": GameState.MAX_PLAYERS,
		"players": roster.size(), "mode": _mode_text(), "lan_ip": _lan_ip(), "names": room_names()}
	_lobby.register(lobby_url, info, func(ok: bool, data: Dictionary):
		if ok and not is_host():
			_lobby.close()  # closed the game before the list answered: unlist it
			return
		if not ok or not is_host():
			status.emit("Server list unreachable: only direct connections")
			return
		status.emit("Listed as \"%s\"" % server_name)
		var relay_ip := IP.resolve_hostname(LobbyApi.host_of(lobby_url), IP.TYPE_IPV4)
		if relay_ip != "" and data.has("relay_port"):
			_relay_host = RelayHost.new(relay_ip, int(data.relay_port), data.id, data.token, port)
	)


func _mode_text() -> String:
	var s := get_tree().current_scene if get_tree() else null
	if s and s.has_node("PartyController"):
		return "party"
	if s and s.has_node("Game"):
		return "campaign"
	return "lobby"


func _lan_ip() -> String:
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			return a
	return ""


func _on_peer_connected(id: int) -> void:
	_short_timeout(id)  # then waits for _hello


func _on_peer_disconnected(id: int) -> void:
	if not is_host():
		return
	if computers.has(id):
		_announce("%s left" % str(computers[id]))
	computers.erase(id)
	var gone := []
	for r in roster.duplicate():
		if int(r.peer) == id:
			roster.erase(r)
			gone.append(int(r.slot))
	for s in gone:
		_release_slot(s)
		var scene := get_tree().current_scene
		var p := scene.get_node_or_null("Player%d" % s) if scene else null
		if p:
			p.queue_free()
	_roster_updated()


## A client says hello with its name and the key sets of its players.
@rpc("any_peer", "call_remote", "reliable")
func _hello(who: String, local_slots: Array, their_mods := [], looks := {}) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if is_banned(who, _address_of(id)):
		_refused.rpc_id(id, "You can't join this game: the host banned you")
		get_tree().create_timer(0.5).timeout.connect(func(): if _peer: _peer.disconnect_peer(id))
		return
	var missing := _missing_mods(their_mods)
	if missing != "":
		# Offer to send them (the player says yes or no: mods run code).
		var offer := []
		for r in _mods().required():
			if not r in their_mods:
				var mid: String = r.split("@")[0]
				var file: String = _mods().pack_for(mid)
				if file == "":
					offer.clear()
					break
				var m: Dictionary = _mods().get_mod(mid)
				offer.append({"id": mid, "name": str(m.get("name", mid)), "version": str(m.get("version", "1")),
					"size": FileAccess.get_file_as_bytes(file).size(), "file": file})
		if offer.is_empty():
			_refused.rpc_id(id, "You need these mods to join: " + missing)
			return
		_offers[id] = offer
		_offer_mods.rpc_id(id, offer.map(func(o): return {"id": o.id, "name": o.name, "version": o.version, "size": o.size}))
		return
	computers[id] = who.left(16)
	_announce("%s joined" % who.left(16))
	for l in local_slots:
		_add_player(id, int(l), who, str(looks.get(str(l), looks.get(int(l), ""))))
	_roster_updated()
	# Bring the newcomer to where we are.
	var scene := get_tree().current_scene
	if scene and scene.scene_file_path != "":
		_load_scene.rpc_id(id, scene.scene_file_path, "", 0.0, _scene_token, _scene_extra(scene.scene_file_path))
		_welcome.call_deferred(id)


# --- Sending mods (host -> a joining player) ------------------------------------

const MOD_CHUNK := 32 * 1024
const CHUNKS_PER_FRAME := 8
var _offers := {}     # host: peer -> what we offered it
var _sending := []    # host: [peer, id, bytes, next chunk]
var _receiving := {}  # client: id -> PackedByteArray so far
var _expect := {}     # client: id -> size


@rpc("authority", "call_remote", "reliable")
func _offer_mods(list: Array) -> void:
	if not is_client():
		return
	_expect.clear()
	for o in list:
		_expect[str(o.id)] = int(o.size)
	mods_offered.emit(list)


## Client: yes, send them (or no: we leave).
func accept_mods(yes: bool) -> void:
	if not is_client():
		return
	if not yes:
		leave()
		failed.emit("Not joined: that game needs mods")
		return
	_receiving.clear()
	status.emit("Downloading the mods...")
	_want_mods.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _want_mods() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not is_host() or not _offers.has(peer):
		return
	for o in _offers[peer]:
		_sending.append([peer, o.id, FileAccess.get_file_as_bytes(o.file), 0])
	_offers.erase(peer)


## Host: a few pieces each frame (so the game doesn't stall).
func _send_mod_chunks() -> void:
	var budget := CHUNKS_PER_FRAME
	while budget > 0 and not _sending.is_empty():
		var s: Array = _sending[0]
		if not s[0] in multiplayer.get_peers():
			_sending.pop_front()
			continue
		var bytes: PackedByteArray = s[2]
		var count := maxi(1, ceili(bytes.size() / float(MOD_CHUNK)))
		var i: int = s[3]
		_mod_chunk.rpc_id(s[0], s[1], i, count, bytes.slice(i * MOD_CHUNK, (i + 1) * MOD_CHUNK))
		s[3] = i + 1
		if s[3] >= count:
			_sending.pop_front()
		budget -= 1


@rpc("authority", "call_remote", "reliable")
func _mod_chunk(id: String, index: int, count: int, data: PackedByteArray) -> void:
	if not is_client() or not _expect.has(id):
		return
	if index == 0:
		_receiving[id] = PackedByteArray()
	_receiving[id].append_array(data)
	var done := 0
	var total := 0
	for k in _expect:
		total += int(_expect[k])
		done += _receiving.get(k, PackedByteArray()).size()
	mods_progress.emit(done, total)
	if index < count - 1:
		return
	# This one's here: save it and load it.
	DirAccess.make_dir_recursive_absolute(_mods().NET_DIR)
	var file: String = _mods().NET_DIR.path_join(ArenaMap.slug(id) + ".pck")
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f == null:
		leave()
		failed.emit("Couldn't save the mod " + id)
		return
	f.store_buffer(_receiving[id])
	f.close()
	if not _mods().mount_net(file):
		leave()
		failed.emit("Couldn't load the mod " + id)
		return
	_expect.erase(id)
	if _expect.is_empty():
		# Everything's here: say hello again, with them.
		status.emit("Mods loaded, joining...")
		_hello.rpc_id(1, player_name, Array(GameState.joined), _mods().required(), _my_looks())


## Host: which of our item mods the client lacks ("" = none).
func _missing_mods(theirs: Array) -> String:
	var out := []
	for r in _mods().required():
		if not r in theirs:
			out.append(r.split("@")[0])
	return ", ".join(out)


func was_online_for_mods() -> bool:
	return _mods() != null and _mods()._net_on


func _mods() -> Node:
	return get_node("/root/Mods")


## Host -> client: you can't join (mods missing).
@rpc("authority", "call_remote", "reliable")
func _refused(reason: String) -> void:
	leave()
	failed.emit(reason)


## A client's player joins (from their lobby) or leaves.
@rpc("any_peer", "call_remote", "reliable")
func _request_join(local_slot: int, look := "") -> void:
	if not is_host():
		return
	_add_player(multiplayer.get_remote_sender_id(), local_slot, _name_of_peer(multiplayer.get_remote_sender_id()), look)
	_roster_updated()


@rpc("any_peer", "call_remote", "reliable")
func _request_leave(local_slot: int) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	for r in roster.duplicate():
		if int(r.peer) == id and int(r.local) == local_slot:
			roster.erase(r)
			_release_slot(int(r.slot))
	_roster_updated()


func _name_of_peer(id: int) -> String:
	if computers.has(id):
		return str(computers[id])
	for r in roster:
		if int(r.peer) == id:
			return r.name
	return "Player"


func _add_player(peer: int, local_slot: int, who: String, look := "") -> int:
	if local_slot < 1 or local_slot > GameState.MAX_PLAYERS:
		return 0
	who = who.left(16)
	for r in roster:
		if int(r.peer) == peer and int(r.local) == local_slot:
			return int(r.slot)
	var used := bots.keys().map(func(s): return int(s))
	for r in roster:
		used.append(int(r.slot))
	if used.size() >= GameState.MAX_PLAYERS:
		return 0
	var slot := local_slot if not local_slot in used else 0
	if slot == 0:
		for s in range(1, GameState.MAX_PLAYERS + 1):
			if not s in used:
				slot = s
				break
	roster.append({"slot": slot, "peer": peer, "local": local_slot, "name": who,
		"look": look if look == "" or _mods().cosmetics().has(look) else ""})
	# Joining in the middle of a level: drop in (party mode: from the next party).
	var scene := get_tree().current_scene
	var spawner := scene.get_node_or_null("PlayerSpawner") if scene else null
	if spawner and spawner.allow_drop_in and not scene.has_node("Player%d" % slot):
		spawner._drop_in.call_deferred(slot)
	return slot


## Host's own players joining / leaving in the online lobby (by key set: the
## game slot is whichever is free).
func host_local_join(local_slot: int) -> void:
	if bot_at(local_slot) != 0:
		remove_bot_at(local_slot)  # a player takes the bot's place
	if _add_player(1, local_slot, player_name, GameState.look_of(local_slot)) != 0:
		_roster_updated()


func host_local_leave(local_slot: int) -> void:
	for r in roster.duplicate():
		if int(r.local) == local_slot and int(r.peer) == 1:
			roster.erase(r)
			_release_slot(int(r.slot))
	_roster_updated()


func _roster_updated() -> void:
	roster.sort_custom(func(a, b): return int(a.slot) < int(b.slot))
	_apply_joined()
	_refresh_looks()
	if is_host():
		_set_roster.rpc(roster)
		_set_computers.rpc(computers, bots, bot_places)
		if _lobby.registered():
			_lobby.heartbeat(taken_places(), _mode_text(), room_names())
	roster_changed.emit()


func _apply_joined() -> void:
	var slots: Array[int] = []
	for r in roster:
		slots.append(int(r.slot))
	GameState.joined = slots


# --- Keys while online --------------------------------------------------------
# Every computer has its own key sets 1-8 (k1_..k8_ actions, copied from the
# p1_..p8_ keys). The game slots' actions (p1_..p8_) only get pressed for the
# players each key set plays: Zoe can play with her P1 keys and Elian with his,
# whatever game slots they got, and nobody's keys move someone else's robot.

func _take_keys() -> void:
	for l in range(1, GameState.MAX_PLAYERS + 1):
		for a in ACTIONS:
			var p := "p%d_%s" % [l, a]
			var k := "k%d_%s" % [l, a]
			if not InputMap.has_action(p):
				continue
			if InputMap.has_action(k):
				InputMap.erase_action(k)
			InputMap.add_action(k, InputMap.action_get_deadzone(p))
			var events: Array = _erased_events.get(p, InputMap.action_get_events(p))
			for ev in events:
				InputMap.action_add_event(k, ev)
		_erase_keys(l)


## This computer's key set `local` as button strengths (ACTIONS order).
func _keyboard(local: int) -> PackedByteArray:
	var v := PackedByteArray()
	if typing:
		v.resize(ACTIONS.size())
		return v
	for a in ACTIONS:
		var action := "k%d_%s" % [local, a]
		v.append(roundi(Input.get_action_strength(action) * 255.0) if InputMap.has_action(action) else 0)
	return v


## Online client: the round trip to the host, in ms (0 offline / host).
func round_trip_ms() -> int:
	if not is_client() or _peer == null:
		return 0
	var p := _peer.get_peer(1)
	return int(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if p else 0


## Our own players: their key sets press their game slots' buttons here.
var _mirrored := {}  # slot -> last strengths
func _mirror_keys() -> void:
	var mine := my_slots()
	for slot in mine:
		var v := _keyboard(mine[slot])
		if _mirrored.get(slot) != v:
			_mirrored[slot] = v
			_apply_input(slot, v)
	for slot in _mirrored.keys():
		if not mine.has(slot):
			_mirrored.erase(slot)
			_release_slot(slot)


func _release_slot(slot: int) -> void:
	_remote_last.erase(slot)
	for a in ACTIONS:
		Input.action_release("p%d_%s" % [slot, a])


## The keys of a game slot no longer press it directly (while online).
func _erase_keys(slot: int) -> void:
	for a in ACTIONS:
		var action := "p%d_%s" % [slot, a]
		if InputMap.has_action(action) and not _erased_events.has(action):
			_erased_events[action] = InputMap.action_get_events(action)
			InputMap.action_erase_events(action)
			Input.action_release(action)


func _restore_keys(slot: int) -> void:
	for a in ACTIONS:
		var action := "p%d_%s" % [slot, a]
		Input.action_release(action)
		if _erased_events.has(action):
			for e in _erased_events[action]:
				InputMap.action_add_event(action, e)
			_erased_events.erase(action)


# --- Client --------------------------------------------------------------------

## Connects straight to an address ("1.2.3.4" or "1.2.3.4:7777").
func join_address(address: String) -> void:
	leave()
	var host_ip := address.strip_edges()
	var port := GAME_PORT
	if host_ip.count(":") == 1:
		port = int(host_ip.get_slice(":", 1))
		host_ip = host_ip.get_slice(":", 0)
	if not host_ip.is_valid_ip_address():
		host_ip = IP.resolve_hostname(host_ip, IP.TYPE_IPV4)
	if host_ip == "":
		failed.emit("Unknown address")
		return
	_start_client(host_ip, port, "Connecting to %s..." % address)


## Joins a game from the server list: directly if possible, else through the relay.
func join_listed(entry: Dictionary, my_public_ip: String) -> void:
	leave()
	_pending_relay = entry if entry.get("relay", false) else {}
	var ip: String = entry.get("ip", "")
	if ip == my_public_ip and entry.get("lan_ip", "") != "":
		ip = entry.lan_ip  # same network as the host: use its local address
	if ip == "" or not entry.get("direct", true):
		_join_relay()
		return
	_start_client(ip, int(entry.port), "Connecting to %s..." % entry.name)


func _join_relay() -> void:
	var entry := _pending_relay
	_pending_relay = {}
	if entry.is_empty():
		leave()
		failed.emit("Can't reach the host")
		return
	var relay_ip := IP.resolve_hostname(LobbyApi.host_of(lobby_url), IP.TYPE_IPV4)
	if relay_ip == "":
		leave()
		failed.emit("Can't reach the server list")
		return
	_relay_client = RelayClient.new(relay_ip, int(entry.relay_port), entry.id)
	_start_client("127.0.0.1", _relay_client.local_port, "Connecting through the relay...")


func _start_client(ip: String, port: int, text: String) -> void:
	if _peer:
		_peer.close()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(ip, port)
	if err != OK:
		leave()
		failed.emit("Can't connect (%s)" % error_string(err))
		return
	_peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = _peer
	mode = Mode.CLIENT
	_take_keys()
	status.emit(text)
	var attempt := _peer
	_connect_timer = get_tree().create_timer(DIRECT_TIMEOUT if not _pending_relay.is_empty() else 10.0)
	_connect_timer.timeout.connect(func():
		if _peer == attempt and _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			_on_connection_failed()
	)


func _on_connected() -> void:
	_short_timeout(1)
	_offline_joined = GameState.joined.duplicate()
	_hello.rpc_id(1, player_name, Array(GameState.joined), _mods().required(), _my_looks())
	status.emit("Connected")
	connected.emit()


func _on_connection_failed() -> void:
	if mode != Mode.CLIENT:
		return
	if not _pending_relay.is_empty():
		status.emit("Direct connection failed, trying the relay...")
		_peer.close()
		_join_relay()
		return
	leave()
	failed.emit("Couldn't connect")


func _on_server_gone() -> void:
	var was := is_client()
	leave()
	if was:
		failed.emit("The host left")
		GameState.go_to_menu("The host left")


## Host -> clients: every computer in the game (even without a player yet).
@rpc("authority", "call_remote", "reliable")
func _set_computers(c: Dictionary, b := {}, places := {}) -> void:
	computers = c
	bots = {}
	for k in b:
		bots[int(k)] = int(b[k])
	bot_places = {}
	for k in places:
		bot_places[int(k)] = int(places[k])
	roster_changed.emit()


# --- Bots (host) --------------------------------------------------------------
# The host's computer runs them (party only); they take places like players.

## Places taken (players and bots).
func taken_places() -> int:
	return roster.size() + bots.size()


## The bot at place `place` of the host's box (its game slot), or 0.
func bot_at(place: int) -> int:
	for s in bot_places:
		if int(bot_places[s]) == place:
			return int(s)
	return 0


## Host: a bot at place `place` of its box (or that bot's level changed).
func set_bot(place: int, skill: int) -> bool:
	if not is_host() or place < 1 or place > GameState.MAX_PLAYERS:
		return false
	var at := bot_at(place)
	if at != 0:
		bots[at] = clampi(skill, 0, 2)
		_roster_updated()
		return true
	for r in roster:
		if int(r.peer) == 1 and int(r.local) == place:
			return false  # one of our players is there
	if taken_places() >= GameState.MAX_PLAYERS:
		return false
	var used := bots.keys()
	for r in roster:
		used.append(int(r.slot))
	var slot := place if not place in used else 0
	if slot == 0:
		for s in range(1, GameState.MAX_PLAYERS + 1):
			if not s in used:
				slot = s
				break
	bots[slot] = clampi(skill, 0, 2)
	bot_places[slot] = place
	_announce("A bot joined (%s)" % PartyBot.SKILL_NAMES[bots[slot]])
	_roster_updated()
	return true


func remove_bot_at(place: int) -> void:
	var slot := bot_at(place)
	if not is_host() or slot == 0:
		return
	bots.erase(slot)
	bot_places.erase(slot)
	_release_slot(slot)
	_roster_updated()


# --- Names ---------------------------------------------------------------------

## A new name for this computer (saved); online, everyone sees it right away.
func rename(new_name: String) -> String:
	new_name = new_name.strip_edges().left(16)
	if new_name == "" or new_name == player_name:
		return player_name
	player_name = new_name
	save_config()
	if is_host():
		_set_name(1, new_name)
	elif is_client():
		_rename_up.rpc_id(1, new_name)
	return player_name


@rpc("any_peer", "call_remote", "reliable")
func _rename_up(new_name: String) -> void:
	if is_host():
		_set_name(multiplayer.get_remote_sender_id(), new_name.strip_edges().left(16))


## Host: computer `id` is now called `new_name` (its players too).
func _set_name(id: int, new_name: String) -> void:
	if new_name == "" or not computers.has(id):
		return
	var old := str(computers[id])
	computers[id] = new_name
	for r in roster:
		if int(r.peer) == id:
			r.name = new_name
	if old != new_name:
		_announce("%s is now %s" % [old, new_name])
	if id == 1:
		server_name = "%s's game" % new_name
		_lobby.game_name = server_name
	_roster_updated()


# --- Kick and ban (host) --------------------------------------------------------

## The computers' addresses (as the host sees them): through the relay, every
## one looks like 127.0.0.1, so a ban there goes by name only.
func _address_of(id: int) -> String:
	var p := _peer.get_peer(id) if _peer else null
	var ip := p.get_remote_address() if p else ""
	return "" if ip.begins_with("127.") or ip == "::1" else ip


func is_banned(who: String, ip: String) -> bool:
	for b in banned:
		if b.name == who.left(16) or (ip != "" and b.ip == ip):
			return true
	return false


## Sends a computer (and its players) out of the game; `ban`: it can't come
## back while you host (same name or address).
func kick(id: int, ban := false) -> void:
	if not is_host() or id == 1 or not computers.has(id):
		return
	if ban:
		banned.append({"name": str(computers[id]), "ip": _address_of(id)})
	_announce("%s was %s" % [str(computers[id]), "banned" if ban else "sent out"])
	computers.erase(id)  # (no "left" message when it goes)
	_kicked.rpc_id(id, "The host banned you" if ban else "The host sent you out of the game")
	get_tree().create_timer(0.3).timeout.connect(func():
		if _peer and id in multiplayer.get_peers():
			_peer.disconnect_peer(id))


@rpc("authority", "call_remote", "reliable")
func _kicked(reason: String) -> void:
	var in_level := get_tree().current_scene != null and not get_tree().current_scene.scene_file_path.ends_with("main_menu.tscn")
	leave()
	failed.emit(reason)
	if in_level:
		GameState.go_to_menu(reason)


@rpc("authority", "call_remote", "reliable")
func _set_roster(r: Array) -> void:
	roster = r
	_apply_joined()
	_refresh_looks()
	for slot in _last_input.keys():
		if not my_slots().has(slot):
			_last_input.erase(slot)  # (rejoining: send the keys again)
	roster_changed.emit()


## Client lobby: one of this computer's players joins or leaves.
func request_join(local_slot: int) -> void:
	if is_client():
		_request_join.rpc_id(1, local_slot, GameState.look_of(local_slot))
	elif is_host():
		host_local_join(local_slot)


func request_leave(local_slot: int) -> void:
	if is_client():
		_request_leave.rpc_id(1, local_slot)
	elif is_host():
		host_local_leave(local_slot)


# --- Leaving ----------------------------------------------------------------------

func leave() -> void:
	if mode == Mode.OFFLINE and _peer == null:
		return
	if is_host() and _lobby.registered() and not _quitting:
		_lobby.close()
	for action in _erased_events.keys():
		for e in _erased_events[action]:
			InputMap.action_add_event(action, e)
	_erased_events.clear()
	_mirrored.clear()
	_remote_last.clear()
	_offers.clear()
	_sending.clear()
	_receiving.clear()
	_expect.clear()
	if was_online_for_mods():
		_mods().set_net_on(false)  # the host's mods: off again
	_token_path = ""
	_loaded_scene = null
	_full_next = false
	typing = false
	var chat := get_node_or_null("/root/Chat")
	if chat and not _quitting:
		chat.close()
		chat.clear()
	for s in range(1, GameState.MAX_PLAYERS + 1):
		for a in ACTIONS:
			Input.action_release("p%d_%s" % [s, a])
	if _peer:
		_say_goodbye()
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if _relay_host:
		_relay_host.close()
	if _relay_client:
		_relay_client.close()
	_relay_host = null
	_relay_client = null
	var was_online := mode != Mode.OFFLINE
	mode = Mode.OFFLINE
	roster.clear()
	computers.clear()
	bots.clear()
	bot_places.clear()
	_reset_sync()
	_last_input.clear()
	if was_online and not _offline_joined.is_empty():
		GameState.joined = _offline_joined
	_offline_joined = [] as Array[int]
	roster_changed.emit()


## Tell the others we're leaving right away (through the relay too), so they
## don't wait for a timeout.
func _say_goodbye() -> void:
	if _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	for id in multiplayer.get_peers():
		var p := _peer.get_peer(id)
		if p:
			p.peer_disconnect_now()
	_peer.host.flush()
	for k in 3:
		OS.delay_msec(10)
		if _relay_host:
			_relay_host.poll()
		if _relay_client:
			_relay_client.poll()


func _exit_tree() -> void:
	_quitting = true
	leave()  # game closed while online (the listing expires by itself)


## Notice a vanished host / client within seconds instead of ENet's 30 s default.
func _short_timeout(id: int) -> void:
	var p := _peer.get_peer(id) if _peer else null
	if p:
		p.set_timeout(0, 4000, 8000)


# --- Scene changes -----------------------------------------------------------------

## Each scene the host loads gets a number; snapshots carry it so a client never
## applies state meant for another scene.
var _scene_token := 0


## Called by Transition: the host takes everyone along; a client only changes
## scene when the host says so (or when it leaves the game).
func allow_scene_change(path: String, message: String, message_time: float) -> bool:
	if is_host():
		_scene_token += 1
		_reset_sync()
		_load_scene.rpc(path, message, message_time, _scene_token, _scene_extra(path))
		if _lobby.registered():
			_lobby.heartbeat.call_deferred(taken_places(), _mode_text(), room_names())
		return true
	if is_client():
		return _applying
	return true


@rpc("authority", "call_remote", "reliable")
func _load_scene(path: String, message: String, message_time: float, token: int, extra := {}) -> void:
	_scene_token = token
	_token_path = path
	if extra.has("map"):
		Party.session["map"] = extra.map  # custom arena: build the host's map
	_reset_sync()
	_applying = true
	get_tree().root.get_node("Transition").change_scene(path, message, message_time)
	_applying = false


## What a client needs to load `path` like the host (the map of a custom arena).
func _scene_extra(path: String) -> Dictionary:
	if path == ArenaMap.SCENE:
		return {"map": Party.session.get("map", {})}
	return {}


# --- Per frame ---------------------------------------------------------------------

func _process(_d: float) -> void:
	if not _held_until_seen.is_empty():
		_release_seen_taps()
	if is_online():
		_mirror_keys()
	if _relay_host:
		_relay_host.poll()
	if _relay_client:
		_relay_client.poll()


func _physics_process(_d: float) -> void:
	if _relay_host:
		_relay_host.poll()
	if _relay_client:
		_relay_client.poll()
	if is_client() and _peer and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_send_inputs()
	elif is_host():
		_frame += 1
		if multiplayer.get_peers().size() > 0:
			if _frame % SNAPSHOT_EVERY == 0 or _full_next:
				_send_snapshot(_frame % FULL_EVERY == 0 or _full_next)
				_full_next = false
			else:
				_send_players_fast()
		_reapply_inputs()
		if not _sending.is_empty():
			_send_mod_chunks()


## Client: our players' buttons -> host (only when something changed).
func _send_inputs() -> void:
	for slot in my_slots():
		var local: int = my_slots()[slot]
		var v := _keyboard(local)
		if _last_input.get(slot) != v:
			_last_input[slot] = v
			_remote_input.rpc_id(1, slot, v)


@rpc("any_peer", "call_remote", "reliable")
func _remote_input(slot: int, v: PackedByteArray) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	var owned := false
	for r in roster:
		if int(r.slot) == slot and int(r.peer) == sender:
			owned = true
	if not owned:
		return
	_remote_last[slot] = v
	_apply_input(slot, v)


## Host: the players' positions every frame in between snapshots (the robots
## are what people watch; the rest goes 30 times a second).
func _send_players_fast() -> void:
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path == "":
		return
	var players := PackedInt32Array()
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_inside_tree() and scene.is_ancestor_of(p):
			players.append_array([p.get_meta("player_index", 0) + 1, roundi(p.global_position.x), roundi(p.global_position.y)])
	if not players.is_empty():
		_players_fast.rpc(_scene_token, players)


@rpc("authority", "call_remote", "unreliable_ordered")
func _players_fast(token: int, players: PackedInt32Array) -> void:
	var scene := get_tree().current_scene
	if token != _scene_token or scene == null or (_token_path != "" and scene.scene_file_path != _token_path):
		return
	for i in range(0, players.size() - 2, 3):
		var p := scene.get_node_or_null("Player%d" % players[i])
		if p and p.has_method("net_move"):
			p.net_move(Vector2(players[i + 1], players[i + 2]))


## Host: what each remote slot holds is pressed again now and then (the window
## losing focus lets go of every key, and clients only send changes).
var _remote_last := {}
func _reapply_inputs() -> void:
	if _frame % 15 != 0:
		return
	for slot in _remote_last:
		_apply_input(slot, _remote_last[slot])
	for slot in _mirrored:
		_apply_input(slot, _mirrored[slot])


## Presses a game slot's buttons as `v` says (one strength per ACTIONS entry).
func _apply_input(slot: int, v: PackedByteArray) -> void:
	for i in mini(v.size(), ACTIONS.size()):
		var action := "p%d_%s" % [slot, ACTIONS[i]]
		var strength := v[i] / 255.0
		if strength > 0.05:
			_held_until_seen.erase(action)
			if not Input.is_action_pressed(action) or absf(Input.get_action_strength(action) - strength) > 0.01:
				if not Input.is_action_pressed(action):
					_pressed_at[action] = [Engine.get_process_frames(), Engine.get_physics_frames()]
				Input.action_press(action, strength)
		elif Input.is_action_pressed(action):
			if _pressed_at.has(action) and not _seen(action):
				_held_until_seen[action] = true  # a quick tap: let the game see it first
			else:
				Input.action_release(action)


## A quick tap (press and release in one network batch) must still last one game
## frame (and one physics frame), or "just pressed" would never be seen.
var _pressed_at := {}         # action -> [process frame, physics frame] of the press
var _held_until_seen := {}    # action -> true: release once the game has seen it


func _seen(action: String) -> bool:
	var at: Array = _pressed_at.get(action, [0, 0])
	return Engine.get_process_frames() > at[0] and Engine.get_physics_frames() > at[1]


func _release_seen_taps() -> void:
	for action in _held_until_seen.keys():
		if _seen(action):
			Input.action_release(action)
			_held_until_seen.erase(action)


# --- Snapshots ------------------------------------------------------------------------
# Synced nodes are named by small numbers instead of their paths. The host sends
# the number -> path table reliably when new nodes show up (and to newcomers);
# snapshots then only carry [number, state] pairs for what changed.
# Nodes in "net_sync_slow" (moving items whose clients keep their own clock) are
# only sent with the full snapshot, once a second.

var _ids := {}          # host: key (path or path|part) -> id
var _next_id := 1
var _force := {}        # host: id -> snapshots left where it's sent even unchanged
var _last_players := PackedInt32Array()
var _id_keys := {}      # client: id -> key
var _id_nodes := {}     # client: id -> node (cache)


func _reset_sync() -> void:
	_sent.clear()
	_ids.clear()
	_force.clear()
	_next_id = 1
	_last_players = PackedInt32Array()
	_id_keys.clear()
	_id_nodes.clear()


## Host: everything a newcomer needs (the whole id table, then a full snapshot).
var _token_path := ""        # client: the scene the current token is for
var _loaded_scene: Node = null


## Client -> host: the new scene is up (anything sent while it loaded was dropped).
@rpc("any_peer", "call_remote", "reliable")
func _scene_ready(token: int) -> void:
	if is_host() and token == _scene_token:
		_full_next = true


var _full_next := false


func _welcome(peer: int) -> void:
	var table := {}
	for key in _ids:
		table[_ids[key]] = key
	_id_table.rpc_id(peer, _scene_token, table)
	for id in _ids.values():
		_force[id] = 2


func _id_for(key: String, new_keys: Dictionary) -> int:
	if not _ids.has(key):
		_ids[key] = _next_id
		new_keys[_next_id] = key
		_force[_next_id] = 3  # its state goes out again once the table has arrived
		_next_id += 1
	return _ids[key]


var _synced_scene: Node


func _send_snapshot(full: bool) -> void:
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path == "":
		return
	if scene != _synced_scene:
		# New level loaded: everything goes out once, even what matches the defaults.
		_synced_scene = scene
		_sent.clear()
		full = true
	var players := PackedInt32Array()
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_inside_tree() and scene.is_ancestor_of(p):
			var pos: Vector2 = p.global_position
			players.append_array([p.get_meta("player_index", 0) + 1, roundi(pos.x), roundi(pos.y)])
	var new_keys := {}
	var entries := []
	for n in get_tree().get_nodes_in_group("net_sync"):
		if not full and n.is_in_group("net_sync_slow"):
			continue
		if not scene.is_ancestor_of(n) or not n.has_method("net_state"):
			continue
		var path := str(scene.get_path_to(n))
		var st = n.net_state()
		if st is Dictionary:
			for k in st:
				_add_entry(path + "|" + str(k), st[k], full, entries, new_keys)
		else:
			_add_entry(path, st, full, entries, new_keys)
	if not new_keys.is_empty():
		_id_table.rpc(_scene_token, new_keys)
	var send_players := full or players != _last_players
	if entries.is_empty() and not send_players:
		return  # nothing moved
	_last_players = players
	_snapshot.rpc(_scene_token, players if send_players else PackedInt32Array(), entries)


func _add_entry(key: String, st, full: bool, entries: Array, new_keys: Dictionary) -> void:
	var id := _id_for(key, new_keys)
	var forced: int = _force.get(id, 0)
	if full or forced > 0 or _sent.get(key) != st:
		_sent[key] = st
		entries.append(id)
		entries.append(st)
		if forced > 0:
			_force[id] = forced - 1
			if forced == 1:
				_force.erase(id)


@rpc("authority", "call_remote", "reliable")
func _id_table(token: int, table: Dictionary) -> void:
	if token != _scene_token:
		return
	for id in table:
		_id_keys[int(id)] = table[id]


@rpc("authority", "call_remote", "unreliable_ordered")
func _snapshot(token: int, players: PackedInt32Array, entries: Array) -> void:
	var scene := get_tree().current_scene
	if token != _scene_token or scene == null or not scene.is_node_ready():
		return
	if _token_path != "" and scene.scene_file_path != _token_path:
		return  # still showing the last scene (the new one is fading in)
	if scene != _loaded_scene:
		_loaded_scene = scene
		_scene_ready.rpc_id(1, token)  # host: send everything again, we're there
	_applying = true
	if not players.is_empty():
		_reconcile_players(scene, players)
	# Group per node (party controller parts come as path|part); the node that
	# creates others (the party controller) goes first.
	var per_node := {}
	var first := []
	for i in range(0, entries.size() - 1, 2):
		var key: String = _id_keys.get(int(entries[i]), "")
		if key == "":
			continue  # table not here yet: it'll be sent again
		var path := key.get_slice("|", 0)
		if key.contains("|"):
			if not per_node.has(path):
				per_node[path] = {}
			per_node[path][key.get_slice("|", 1)] = entries[i + 1]
		else:
			per_node[path] = entries[i + 1]
		if path == "PartyController" and not path in first:
			first.append(path)
	for path in first + per_node.keys().filter(func(p): return not p in first):
		var n := _node_at(scene, path)
		if n and n.has_method("net_apply"):
			n.net_apply(per_node[path])
	_applying = false


func _node_at(scene: Node, path: String) -> Node:
	var n = _id_nodes.get(path)
	if n == null or not is_instance_valid(n) or n.is_queued_for_deletion():
		n = scene.get_node_or_null(path)
		if n:
			_id_nodes[path] = n
	return n


## Client: same players as the host (spawned / removed as needed).
func _reconcile_players(scene: Node, list: PackedInt32Array) -> void:
	var want := {}
	for i in range(0, list.size() - 2, 3):
		want[list[i]] = Vector2(list[i + 1], list[i + 2])
	for p in get_tree().get_nodes_in_group("players"):
		if scene.is_ancestor_of(p) and not want.has(p.get_meta("player_index", 0) + 1):
			p.queue_free()
	var spawner := scene.get_node_or_null("PlayerSpawner")
	if spawner == null:
		return
	for slot in want:
		if not scene.has_node("Player%d" % slot):
			var p = spawner.spawn(slot, want[slot], want.size() > 1)
			p.global_position = want[slot]


## Client: a new robot in place of `old` (out or finished last round, back now).
func respawn_player(old: Node, pos: Vector2) -> Node:
	var scene := get_tree().current_scene
	var spawner := scene.get_node_or_null("PlayerSpawner") if scene else null
	if spawner == null or not scene.is_ancestor_of(old):
		return null
	var slot: int = old.get_meta("player_index", 0) + 1
	var others := get_tree().get_nodes_in_group("players").filter(func(p): return p != old and scene.is_ancestor_of(p)).size()
	old.remove_from_group("players")
	old.remove_from_group("camera_follow")
	old.name = "Gone%d" % slot  # the new one gets its name now
	old.queue_free()
	var p = spawner.spawn(slot, pos, others > 0)
	p.global_position = pos
	return p


# --- Chat (console "say") -------------------------------------------------------------

func chat(text: String) -> void:
	text = text.strip_edges().left(200)
	if text == "" or not is_online():
		return
	if is_host():
		_chat_show.rpc(player_name, text)
		_chat_show(player_name, text)
	else:
		_chat_up.rpc_id(1, text)


@rpc("any_peer", "call_remote", "reliable")
func _chat_up(text: String) -> void:
	if is_host():
		var who := _name_of_peer(multiplayer.get_remote_sender_id())
		text = text.strip_edges().left(200)
		_chat_show.rpc(who, text)
		_chat_show(who, text)


@rpc("authority", "call_remote", "reliable")
func _chat_show(who: String, text: String) -> void:
	chat_received.emit(who, text)


## Host: a message from the game itself to everyone (someone joined, left...).
func _announce(text: String) -> void:
	if is_host():
		_chat_show.rpc("", text)
		_chat_show("", text)


## Host: run a method on the same node on every client (one-off effects).
func send_event(node: Node, method: String, args: Array) -> void:
	var scene := get_tree().current_scene
	if scene == null or not scene.is_ancestor_of(node):
		return
	_event.rpc(scene.scene_file_path, str(scene.get_path_to(node)), method, args)


@rpc("authority", "call_remote", "reliable")
func _event(scene_path: String, node_path: String, method: String, args: Array) -> void:
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != scene_path:
		return
	var n := scene.get_node_or_null(node_path)
	if n and n.has_method(method):
		_applying = true
		n.callv(method, args)
		_applying = false


# --- Server list -----------------------------------------------------------------------

func list_servers() -> void:
	if lobby_url == "":
		servers_listed.emit([])
		return
	_lobby.list(lobby_url, func(ok: bool, data: Dictionary):
		if not ok:
			servers_listed.emit([])
			return
		var out := []
		for s in data.get("servers", []):
			s["relay_port"] = data.get("relay_port", 0)
			s["you"] = data.get("you", "")
			out.append(s)
		servers_listed.emit(out)
	)


func lobby_heartbeat() -> void:
	if is_host() and _lobby.registered():
		_lobby.heartbeat(taken_places(), _mode_text(), room_names())


## Who is in this game, one name per computer ("Alice x2" for two players on one keyboard).
func room_names() -> Array:
	return _room_names() + (["%d bot%s" % [bots.size(), "" if bots.size() == 1 else "s"]] if not bots.is_empty() else [])


func _room_names() -> Array:
	var count := {}
	var order := []
	for r in roster:
		var n := str(r.get("name", "?")).left(16)
		if not count.has(n):
			order.append(n)
		count[n] = count.get(n, 0) + 1
	return order.map(func(n): return n if count[n] == 1 else "%s x%d" % [n, count[n]])


# --- Config -----------------------------------------------------------------------------

func save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("online", "name", player_name)
	# Only a list the player typed is saved: if the default changes in a new
	# version of the game, players who never changed it follow.
	cfg.set_value("online", "lobby_url", "" if lobby_url == default_lobby_url else lobby_url)
	cfg.set_value("online", "port", host_port)
	cfg.save(CONFIG_PATH)


func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		player_name = cfg.get_value("online", "name", player_name)
		var own: String = cfg.get_value("online", "lobby_url", "")
		lobby_url = own if own != "" else default_lobby_url
		host_port = clampi(int(cfg.get_value("online", "port", host_port)), 1024, 65535)
