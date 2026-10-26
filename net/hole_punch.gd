class_name HolePunch
extends RefCounted
## Client side of hole punching: lets us connect straight to a host behind a
## home router, with nobody configuring anything.
##
## From a UDP port of ours we ask the lobby server's relay where the host's game
## port is (as the internet sees it). The relay tells the host where we are, and
## the host sends us a few tiny packets: that opens its router to us. We send it
## a few too (opens ours), then our ENet client connects from that same port.
## Works with most home routers; for the others, the relay carries the game.
##
##   client -> relay  0x07 PUNCH_CLIENT id(8) local_port(2) our_ipv6
##   relay -> client  0x08 PUNCH_INFO {ok, ip, port, ip6, port6}

const PUNCH_CLIENT := 0x07
const PUNCH_INFO := 0x08
const ASK_EVERY := 0.3
const GIVE_UP := 2.0

var local_port := 0
## When done: {ok, ip, port, ip6, port6} ({} if the relay never answered).
var info := {}
var done := false

var _sock := PacketPeerUDP.new()
var _ask := PackedByteArray()
var _started := 0.0
var _next_ask := 0.0


func _init(relay_ip: String, relay_port: int, server_id: String, my_ipv6: String) -> void:
	_sock.bind(0, "*")
	local_port = _sock.get_local_port()
	_sock.set_dest_address(relay_ip, relay_port)
	_ask.append(PUNCH_CLIENT)
	_ask.append_array(server_id.to_ascii_buffer())
	var port := PackedByteArray([0, 0])
	port.encode_u16(0, local_port)
	port.reverse()  # big-endian, like the relay reads it
	_ask.append_array(port)
	_ask.append_array(my_ipv6.to_ascii_buffer())
	_started = _now()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Call every frame until `done`.
func poll() -> void:
	if done:
		return
	var now := _now()
	if now >= _next_ask:
		_next_ask = now + ASK_EVERY
		_sock.put_packet(_ask)
	while _sock.get_available_packet_count() > 0:
		var p := _sock.get_packet()
		if p.size() > 1 and p[0] == PUNCH_INFO:
			var d = JSON.parse_string(p.slice(1).get_string_from_utf8())
			if d is Dictionary:
				info = d
				_knock()
				_finish()
				return
	if now - _started > GIVE_UP:
		_finish()


## A few packets to the host from our port: our router now lets its answers in.
func _knock() -> void:
	if not info.get("ok", false):
		return
	for target in [[str(info.get("ip6", "")), int(info.get("port6", 0))], [str(info.get("ip", "")), int(info.get("port", 0))]]:
		if target[0].is_valid_ip_address() and target[1] > 0:
			_sock.set_dest_address(target[0], target[1])
			for k in 3:
				_sock.put_packet(PackedByteArray([0]))


func _finish() -> void:
	done = true
	_sock.close()  # the ENet client takes this port over


func close() -> void:
	done = true
	_sock.close()
