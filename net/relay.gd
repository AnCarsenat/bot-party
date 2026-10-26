class_name RelayHost
extends RefCounted
## UDP tunnel through the lobby server's relay, host side.
## The relay can't open connections to us, so we keep a UDP "line" open to it.
## Each remote client gets a local UDP socket that talks to our own ENet server on
## 127.0.0.1, so to ENet the client looks like someone on this computer.
##
## Packets (first byte = type):
##   host -> relay  0x01 HELLO_HOST id(8) token(16)    (every 2 s, keeps the line open)
##   relay -> host  0x03 JOIN cid(2) / 0x04 LEFT cid(2) / 0x05 ACK
##   relay <-> host 0x11 cid(2) payload                 (game traffic of client cid)
##
## Hole punching (so most players connect straight to us, not through the relay):
##   game socket -> relay  0x06 PUNCH_HOST id(8) token(16)  (every 2 s: where our
##                         game port is, as the internet sees it)
##   relay -> host  0x09 PUNCH_TO {ip, port, ip6, port6}     (a client wants in: we
##                         send it a few tiny packets from the game socket, which
##                         opens our router to it)

const HELLO_HOST := 0x01
const HELLO_CLIENT := 0x02
const JOIN := 0x03
const LEFT := 0x04
const ACK := 0x05
const TO_CLIENT := 0x10
const TO_HOST := 0x11
const KEEPALIVE := 2.0
const PUNCH_HOST := 0x06
const PUNCH_TO := 0x09
const PUNCH_FOR := 8.0      # seconds we keep knocking for a client
const PUNCH_EVERY := 0.25

## Sends from our game (ENet) socket: func(ip, port, bytes). Set by net.gd.
var game_send: Callable
var _relay_ip := ""
var _relay_port := 0
var _punch_hello := PackedByteArray()
var _punches: Array = []    # [ip, port, until, next]

var _relay := PacketPeerUDP.new()
var _hello := PackedByteArray()
var _game_port := 0
var _clients := {}   # cid -> PacketPeerUDP (to our ENet server)
var _next_hello := 0.0


func _init(relay_ip: String, relay_port: int, server_id: String, token: String, game_port: int) -> void:
	_game_port = game_port
	_relay_ip = relay_ip
	_relay_port = relay_port
	_relay.bind(0)
	_relay.set_dest_address(relay_ip, relay_port)
	_hello.append(HELLO_HOST)
	_hello.append_array(server_id.to_ascii_buffer())
	_hello.append_array(token.to_ascii_buffer())
	_punch_hello = _hello.duplicate()
	_punch_hello[0] = PUNCH_HOST


func poll() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now >= _next_hello:
		_next_hello = now + KEEPALIVE
		_relay.put_packet(_hello)
		if game_send.is_valid():
			game_send.call(_relay_ip, _relay_port, _punch_hello)
	for p in _punches:
		if now >= p[3] and game_send.is_valid():
			p[3] = now + PUNCH_EVERY
			game_send.call(p[0], p[1], PackedByteArray([0]))
	_punches = _punches.filter(func(p): return now < p[2])
	while _relay.get_available_packet_count() > 0:
		var p := _relay.get_packet()
		if p.size() < 1:
			continue
		match p[0]:
			JOIN:
				_client(p.decode_u16(1))
			LEFT:
				var cid := p.decode_u16(1)
				if _clients.has(cid):
					_clients[cid].close()
					_clients.erase(cid)
			TO_HOST:
				if p.size() > 3:
					_client(p.decode_u16(1)).put_packet(p.slice(3))
			PUNCH_TO:
				var d = JSON.parse_string(p.slice(1).get_string_from_utf8())
				if d is Dictionary and _punches.size() < 32:
					if str(d.get("ip", "")).is_valid_ip_address():
						_punches.append([str(d.ip), int(d.get("port", 0)), now + PUNCH_FOR, now])
					if str(d.get("ip6", "")).is_valid_ip_address():
						_punches.append([str(d.ip6), int(d.get("port6", 0)), now + PUNCH_FOR, now])
	for cid in _clients:
		var s: PacketPeerUDP = _clients[cid]
		while s.get_available_packet_count() > 0:
			var payload := s.get_packet()
			var out := PackedByteArray([TO_HOST, 0, 0])
			out.encode_u16(1, cid)
			out.append_array(payload)
			_relay.put_packet(out)


func _client(cid: int) -> PacketPeerUDP:
	if not _clients.has(cid):
		var s := PacketPeerUDP.new()
		s.bind(0, "127.0.0.1")
		s.set_dest_address("127.0.0.1", _game_port)
		_clients[cid] = s
	return _clients[cid]


func close() -> void:
	for s in _clients.values():
		s.close()
	_clients.clear()
	_relay.close()
