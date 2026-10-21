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

const HELLO_HOST := 0x01
const HELLO_CLIENT := 0x02
const JOIN := 0x03
const LEFT := 0x04
const ACK := 0x05
const TO_CLIENT := 0x10
const TO_HOST := 0x11
const KEEPALIVE := 2.0

var _relay := PacketPeerUDP.new()
var _hello := PackedByteArray()
var _game_port := 0
var _clients := {}   # cid -> PacketPeerUDP (to our ENet server)
var _next_hello := 0.0


func _init(relay_ip: String, relay_port: int, server_id: String, token: String, game_port: int) -> void:
	_game_port = game_port
	_relay.bind(0)
	_relay.set_dest_address(relay_ip, relay_port)
	_hello.append(HELLO_HOST)
	_hello.append_array(server_id.to_ascii_buffer())
	_hello.append_array(token.to_ascii_buffer())


func poll() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now >= _next_hello:
		_next_hello = now + KEEPALIVE
		_relay.put_packet(_hello)
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
