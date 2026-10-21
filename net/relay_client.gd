class_name RelayClient
extends RefCounted
## UDP tunnel through the lobby server's relay, client side.
## Our ENet client connects to a socket on 127.0.0.1 (local_port); everything it
## sends goes to the relay, tagged for the server we want, and back.
##
##   client -> relay  0x02 HELLO_CLIENT id(8)   (every 2 s until the game ends)
##   client <-> relay 0x10 payload             (game traffic)

const KEEPALIVE := 2.0

var local_port := 0
var _local := PacketPeerUDP.new()     # our ENet client <-> us
var _relay := PacketPeerUDP.new()     # us <-> relay
var _hello := PackedByteArray()
var _enet_ip := ""
var _enet_port := 0
var _next_hello := 0.0


func _init(relay_ip: String, relay_port: int, server_id: String) -> void:
	_local.bind(0, "127.0.0.1")
	local_port = _local.get_local_port()
	_relay.bind(0)
	_relay.set_dest_address(relay_ip, relay_port)
	_hello.append(RelayHost.HELLO_CLIENT)
	_hello.append_array(server_id.to_ascii_buffer())


func poll() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now >= _next_hello:
		_next_hello = now + KEEPALIVE
		_relay.put_packet(_hello)
	while _local.get_available_packet_count() > 0:
		var payload := _local.get_packet()
		_enet_ip = _local.get_packet_ip()
		_enet_port = _local.get_packet_port()
		var out := PackedByteArray([RelayHost.TO_CLIENT])
		out.append_array(payload)
		_relay.put_packet(out)
	while _relay.get_available_packet_count() > 0:
		var p := _relay.get_packet()
		if p.size() > 1 and p[0] == RelayHost.TO_CLIENT and _enet_port != 0:
			_local.set_dest_address(_enet_ip, _enet_port)
			_local.put_packet(p.slice(1))


func close() -> void:
	_local.close()
	_relay.close()
