class_name LobbyApi
extends Node
## Talks to the server list (server/lobby_server.py) over HTTP + JSON.
##   POST /api/host       register a game      -> {id, token, ip, relay_port}
##   POST /api/heartbeat  keep it listed (every HEARTBEAT seconds)
##   POST /api/close      remove it
##   GET  /api/servers    the list             -> {you, relay_port, servers: [...]}

const HEARTBEAT := 10.0

var base := ""
var id := ""
var token := ""
var _players := 0
var _mode := ""
var _names: Array = []
var game_name := ""  # sent with each heartbeat (the host may rename itself)
var _beat: Timer


func _ready() -> void:
	_beat = Timer.new()
	_beat.wait_time = HEARTBEAT
	_beat.timeout.connect(func(): heartbeat(_players, _mode, _names))
	add_child(_beat)


## "http://example.com:8910" -> "example.com"
static func host_of(url: String) -> String:
	var u := url.strip_edges()
	if u.contains("://"):
		u = u.get_slice("://", 1)
	return u.get_slice("/", 0).get_slice(":", 0)


static func normalize(url: String) -> String:
	var u := url.strip_edges().trim_suffix("/")
	if u != "" and not u.contains("://"):
		u = "http://" + u
	if u != "" and u.count(":") < 2:
		u += ":8910"
	return u


func registered() -> bool:
	return id != ""


func register(url: String, info: Dictionary, done: Callable) -> void:
	base = normalize(url)
	_players = int(info.get("players", 1))
	_mode = info.get("mode", "")
	game_name = str(info.get("name", ""))
	_names = info.get("names", [])
	_request("POST", "/api/host", info, func(ok: bool, data: Dictionary):
		if ok and data.has("id"):
			id = data.id
			token = data.token
			_beat.start()
		done.call(ok and data.has("id"), data)
	)


## `names`: who is in the game (shown in the server list, so each room shows its own players).
func heartbeat(players: int, mode: String, names := []) -> void:
	_players = players
	_mode = mode
	_names = names
	if registered():
		var body := {"id": id, "token": token, "players": players, "mode": mode, "names": names}
		if game_name != "":
			body["name"] = game_name
		_request("POST", "/api/heartbeat", body, func(_ok, _d): pass)


func close() -> void:
	if registered():
		_request("POST", "/api/close", {"id": id, "token": token}, func(_ok, _d): pass)
	id = ""
	token = ""
	_beat.stop()


func list(url: String, done: Callable) -> void:
	var b := normalize(url)
	_request("GET", "/api/servers", {}, done, b)


func _request(method: String, path: String, body: Dictionary, done: Callable, b := "") -> void:
	var req := HTTPRequest.new()
	req.timeout = 5.0
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h, bytes: PackedByteArray):
		req.queue_free()
		var data = JSON.parse_string(bytes.get_string_from_utf8()) if bytes.size() > 0 else null
		var ok := result == HTTPRequest.RESULT_SUCCESS and code == 200 and data is Dictionary
		done.call(ok, data if data is Dictionary else {})
	)
	var url := (b if b != "" else base) + path
	var headers := PackedStringArray(["Content-Type: application/json"])
	var m := HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET
	var err := req.request(url, headers, m, JSON.stringify(body) if method == "POST" else "")
	if err != OK:
		req.queue_free()
		done.call(false, {})
