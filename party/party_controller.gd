extends Node
## Party mode round loop:
##   PICK      - everyone picks one item from the box (left/right + jump)
##   PLACE     - everyone moves their item's ghost (all 4 directions) and places it (jump)
##   COUNTDOWN - 3, 2, 1...
##   RUN       - race to the flag; spikes, saws and pits eliminate you
##   SCORE     - points, then next round (or a winner)
## Placed obstacles are kept (and saved) for the whole party.

enum Phase { PICK, PLACE, COUNTDOWN, RUN, SCORE, OVER }

## No building inside these (start area, goal area).
@export var start_zone := Rect2(-60, 360, 430, 190)
@export var goal_zone := Rect2(1830, 120, 440, 230)
## Ghosts can't leave this rectangle.
@export var build_area := Rect2(-40, -300, 2280, 1000)
@export var spawn_origin := Vector2(40, 450)
@export var round_time := 40.0
@export var ghost_speed := 650.0
## Big arenas: the camera follows the players (and the items being placed).
@export var follow_camera := false

var phase: Phase = Phase.PICK
var slots: Array[int] = []
var box: Array[String] = []
var cursors := {}      # slot -> index in box
var picks := {}        # slot -> index in box
var ghosts := {}       # slot -> Node2D
var turns := {}        # slot -> quarter turns (0-3) of the item being placed
var mirrors := {}      # slot -> mirrored?
var players := {}      # slot -> player
var finished: Array[int] = []
var trap_kills := {}   # owner slot -> kills this round
var run_time := 0.0
var modifier := ""
## Console: the rule for the next round.
var forced_modifier := ""
var _coin: Node2D
var _preview: _Preview
## Placed item record uid -> item node (to find hosts for attached items).
var _by_uid := {}
## While placing: where each player's cursor really is (the ghost may be snapped
## to an attachment point near it), and the point it's snapped to.
var cursor := {}       # slot -> Vector2
var snapped := {}      # slot -> ItemMount
## How close the cursor must be to an attachment point to snap to it.
const SNAP_DISTANCE := 60.0

var _rng := RandomNumberGenerator.new()
var _ui: CanvasLayer
var _banner: Label
var _sub: Label
var _box_row: HBoxContainer
var _scoreboard: VBoxContainer
var _timer_label: Label
var _mod_label: Label

@onready var _items: Node2D = $"../Items"
@onready var _spawner: PlayerSpawner = $"../PlayerSpawner"
@onready var _goal: Area2D = $"../Goal"


func _ready() -> void:
	add_to_group("party_controller")
	add_to_group("net_sync")
	_rng.randomize()
	if NetCheck.client(self):
		_ready_client()
		return
	if Party.session.is_empty() and not Party.load_save():
		Party.new_session(GameState.joined)  # arena started directly from the editor
	slots = Party.players()
	for rec in Party.session.items.duplicate():
		if not rec.has("uid"):
			rec.uid = _new_uid()  # saves from before attachments
		if _spawn_item(rec.id, Vector2(rec.x, rec.y), int(rec.owner), rec) == null:
			Party.session.items.erase(rec)  # its host is gone
	_goal.collision_layer = 0
	_goal.collision_mask = Layers.PLAYERS
	_goal.body_entered.connect(_on_goal)
	_build_ui()
	_preview = _Preview.new()
	_preview.ctl = self
	_preview.z_index = 60
	get_parent().add_child.call_deferred(_preview)
	_start_pick()


# --- Console helpers ---------------------------------------------------------------

## Gives `slot` this item: replaces what they're placing, or what their cursor is on.
func give_item(slot: int, id: String) -> String:
	if phase == Phase.PLACE and ghosts.get(slot) != null:
		var pos: Vector2 = ghosts[slot].global_position
		ghosts[slot].queue_free()
		var g := _make_ghost(id, slot)
		_items.add_child(g)
		g.global_position = pos
		ghosts[slot] = g
		snapped.erase(slot)
		return "P%d is now placing: %s" % [slot, id]
	if phase == Phase.PICK and cursors.has(slot) and not picks.has(slot):
		box[cursors[slot]] = id
		_update_box()
		return "P%d's box slot is now: %s" % [slot, id]
	return "Only while picking or placing"


## Places an item right away (saved with the party).
func spawn_now(id: String, pos: Vector2) -> Node2D:
	var rec := {"id": id, "x": pos.x, "y": pos.y, "owner": 0, "rot": 0, "mirror": false, "uid": _new_uid()}
	Party.session.items.append(rec)
	var item := _spawn_item(id, pos, 0, rec)
	Party.save()
	return item


func clear_items() -> int:
	var n := 0
	for item in placed_items():
		item.queue_free()
		n += 1
	Party.session.items.clear()
	_by_uid.clear()
	Party.save()
	return n


## Online client: the host runs the party; we build the UI and show its state.
func _ready_client() -> void:
	Party.session = {"round": 1, "scores": {}, "players": [], "items": [], "arena": scene_file()}
	_goal.collision_layer = 0
	_goal.collision_mask = 0
	_build_ui()
	_preview = _Preview.new()
	_preview.ctl = self
	_preview.z_index = 60
	get_parent().add_child.call_deferred(_preview)


func scene_file() -> String:
	return get_parent().scene_file_path


# --- Online ---------------------------------------------------------------------

var _last_scoreboard := []


func net_state() -> Dictionary:
	var gh := []
	for slot in ghosts:
		var g = ghosts[slot]
		if g == null or not is_instance_valid(g):
			continue
		var m = snapped.get(slot)
		var mount_path := ""
		if m != null and is_instance_valid(m):
			mount_path = str(get_parent().get_path_to(m))
		gh.append([slot, g.get_meta("item_id"), g.global_position.round(), turns.get(slot, 0),
			mirrors.get(slot, false), mount_path, cursor.get(slot, g.global_position).round()])
	var sess := Party.session
	return {
		"ph": int(phase),
		"sess": [sess.get("round", 1), sess.get("scores", {}), sess.get("players", [])],
		"items": sess.get("items", []),
		"box": [box, picks, cursors],
		"ghosts": gh,
		"ui": [_banner.text, _sub.text, _timer_label.text, get_parent().get_meta("title", ""), _mod_label.text],
		"sb": _last_scoreboard,
		"coin": [is_instance_valid(_coin)],
	}


func net_apply(d: Dictionary) -> void:
	if d.has("sess"):
		Party.session.round = d.sess[0]
		Party.session.scores = d.sess[1]
		Party.session.players = d.sess[2]
		slots.clear()
		for x in d.sess[2]:
			slots.append(int(x))
	if d.has("items"):
		_sync_items(d["items"])
	if d.has("ph") and d.ph != phase:
		phase = d.ph
		_box_row.visible = phase == Phase.PICK
		if phase != Phase.SCORE and phase != Phase.OVER:
			_scoreboard.hide()
		if phase == Phase.PICK:
			_overview()
	if d.has("box"):
		box.assign(d.box[0])
		picks = d.box[1]
		cursors = d.box[2]
		if phase == Phase.PICK:
			_update_box()
	if d.has("ghosts"):
		_sync_ghosts(d.ghosts)
	if d.has("ui"):
		_banner.text = d.ui[0]
		_sub.text = d.ui[1]
		_timer_label.text = d.ui[2]
		_set_title(d.ui[3])
		_mod_label.text = d.ui[4]
	if d.has("coin") and not d.coin[0]:
		var c := get_parent().get_node_or_null("Coin")
		if c:
			c.name = "OldCoin"
			c.queue_free()
	if d.has("sb") and d.sb != _last_scoreboard:
		_last_scoreboard = d.sb
		if not d.sb.is_empty():
			_show_scoreboard(d.sb[0], d.sb[1])


## Client: same placed items as the host (by uid).
func _sync_items(records: Array) -> void:
	var want := {}
	for r in records:
		want[int(r.uid)] = r
	for uid in _by_uid.keys():
		if not want.has(uid):
			if is_instance_valid(_by_uid[uid]):
				_by_uid[uid].queue_free()
			_by_uid.erase(uid)
	for r in records:
		if not _by_uid.has(int(r.uid)):
			_spawn_item(r.id, Vector2(r.x, r.y), int(r.owner), r)
	Party.session.items = records


## Client: the items being placed, where the host has them.
func _sync_ghosts(list: Array) -> void:
	var seen := {}
	for e in list:
		var slot: int = e[0]
		seen[slot] = true
		var g = ghosts.get(slot)
		if g == null or not is_instance_valid(g) or g.get_meta("item_id") != e[1]:
			if g != null and is_instance_valid(g):
				g.queue_free()
			g = _make_ghost(e[1], slot)
			_items.add_child(g)
			ghosts[slot] = g
			if follow_camera:
				g.add_to_group("camera_follow")
		g.global_position = e[2]
		turns[slot] = e[3]
		mirrors[slot] = e[4]
		orient(g, e[3], e[4])
		var m = get_parent().get_node_or_null(e[5]) if e[5] != "" else null
		if m:
			snapped[slot] = m
		else:
			snapped.erase(slot)
		cursor[slot] = e[6]
		var ok := can_place(e[1], g.global_position, e[3])
		g.modulate = Color(1, 1, 1, 0.85) if ok else Color(1, 0.35, 0.35, 0.6)
	for slot in ghosts.keys():
		if not seen.has(slot):
			if ghosts[slot] != null and is_instance_valid(ghosts[slot]):
				ghosts[slot].queue_free()
			ghosts.erase(slot)


# --- Items --------------------------------------------------------------------

func _new_uid() -> int:
	var uid := int(Party.session.get("next_uid", 1))
	Party.session.next_uid = uid + 1
	return uid


## Items that other items can be attached to (ferris wheel, pendulum).
static func is_host(item: Node) -> bool:
	return item.has_method("mounts")


## Can this item hang from an attachment point? (Not bombs, not other hosts.)
static func can_attach(id: String) -> bool:
	var def: Dictionary = Party.ITEMS[id]
	return not def.get("bomb", false) and not def.get("host", false)


func _spawn_item(id: String, pos: Vector2, owner_slot: int, record: Dictionary) -> Node2D:
	var def: Dictionary = Party.ITEMS[id]
	var parent: Node2D = _items
	if record.has("host"):
		var host = _by_uid.get(int(record.host))
		var point := int(record.get("point", 0))
		if host == null or not is_instance_valid(host) or point >= host.mounts().size():
			return null
		parent = host.mounts()[point]
		pos = Vector2.ZERO
	var item: Node2D = load(def.scene).instantiate()
	for k in def.get("props", {}):
		item.set(k, def.props[k])
	item.position = pos
	orient(item, int(record.get("rot", 0)), bool(record.get("mirror", false)))
	item.set_meta("record", record)
	if record.has("uid"):
		_by_uid[int(record.uid)] = item
		item.name = "Item%d" % int(record.uid)  # same path on every computer (online)
	parent.add_child(item)
	item.set_meta("owner_slot", owner_slot)
	for h in item.find_children("*", "Area2D", true, false):
		if h is Hazard:
			h.owner_slot = owner_slot
	return item


## Turns an item by quarter turns and mirrors it. Items with a direction
## (crossbow, conveyor) implement set_mirrored(); symmetric items just turn.
static func orient(item: Node2D, rot: int, mirror: bool) -> void:
	item.rotation = (rot % 4) * PI / 2.0
	if item.has_method("set_mirrored"):
		item.set_mirrored(mirror)
	elif not item is CollisionObject2D:
		item.scale.x = -1.0 if mirror else 1.0


func _footprint(id: String, pos: Vector2, rot := 0) -> Rect2:
	var def: Dictionary = Party.ITEMS[id]
	var size: Vector2 = def.size
	var offset: Vector2 = def.get("offset", Vector2.ZERO)
	if rot % 2 == 1:
		size = Vector2(size.y, size.x)
	offset = offset.rotated((rot % 4) * PI / 2.0)
	return Rect2(pos + offset - size / 2.0, size)


func can_place(id: String, pos: Vector2, rot := 0) -> bool:
	if Party.ITEMS[id].get("bomb", false):
		return true
	var r := _footprint(id, pos, rot)
	return not r.intersects(start_zone) and not r.intersects(goal_zone)


## Every placed item, including the ones hanging from attachment points.
func placed_items() -> Array:
	var out := []
	for item in _items.find_children("*", "Node2D", true, false):
		if item.has_meta("record") and not item.is_queued_for_deletion():
			out.append(item)
	return out


## Free attachment points of placed hosts.
func free_mounts() -> Array:
	var out := []
	for item in placed_items():
		if is_host(item):
			for m in item.mounts():
				if not m.occupied():
					out.append(m)
	return out


## Placed items a bomb of `radius` at `pos` would destroy
## (what hangs from a destroyed host goes with it).
func items_in_blast(pos: Vector2, radius: float) -> Array:
	var out := []
	for item in placed_items():
		if item.global_position.distance_to(pos) <= radius:
			out.append(item)
	for item in out.duplicate():
		if is_host(item):
			for m in item.mounts():
				for child in m.get_children():
					if child.has_meta("record") and not child in out:
						out.append(child)
	return out


func _explode(pos: Vector2, radius: float) -> void:
	for item in items_in_blast(pos, radius):
		Party.session.items.erase(item.get_meta("record"))
		item.queue_free()
	_explode_fx(pos, radius)
	NetCheck.event(self, "_explode_fx", [pos, radius])


func _explode_fx(pos: Vector2, radius: float) -> void:
	_items.add_child(Effects.ring(pos, radius, Color(1, 0.6, 0.2)))
	if radius > 200.0:
		_items.add_child(Effects.ring(pos, radius * 0.6, Color(1, 0.9, 0.5)))


# --- Phases --------------------------------------------------------------------

func _start_pick() -> void:
	phase = Phase.PICK
	_last_scoreboard = []
	_clear_players()
	_set_title("Party, round %d" % Party.session.round)
	_banner.text = "Round %d" % Party.session.round
	_sub.text = "Pick"
	box.clear()
	var count := slots.size() + 2
	var bomb_ids := []
	for k in Party.ITEMS:
		if Party.ITEMS[k].get("bomb", false):
			bomb_ids.append(k)
	# At most one bomb (or nuke) per box, and none while there's nothing to blow up.
	var no_bombs: bool = Party.session.items.is_empty()
	while box.size() < count:
		var id: String = Party.pick_item(_rng, bomb_ids if no_bombs else [])
		if id in bomb_ids:
			no_bombs = true
		box.append(id)
	_overview()
	cursors.clear()
	picks.clear()
	for i in slots.size():
		cursors[slots[i]] = i % box.size()
	_box_row.show()
	_scoreboard.hide()
	_update_box()


func _start_place() -> void:
	phase = Phase.PLACE
	_box_row.hide()
	_sub.text = "Place"
	_banner.text = ""
	ghosts.clear()
	turns.clear()
	mirrors.clear()
	for i in slots.size():
		var slot := slots[i]
		var id := box[picks[slot]]
		turns[slot] = 0
		mirrors[slot] = false
		var g := _make_ghost(id, slot)
		g.position = _ghost_start(i)
		cursor[slot] = g.position
		snapped.erase(slot)
		_items.add_child(g)
		ghosts[slot] = g
		if follow_camera:
			g.add_to_group("camera_follow")


func _ghost_start(i: int) -> Vector2:
	var centre := build_area.get_center() + Vector2(0, -150)
	if follow_camera:
		var cam := _camera()
		if cam:
			centre = cam.get_screen_center_position()
	return (centre + Vector2((i - slots.size() / 2.0) * 120.0, 0)).clamp(build_area.position, build_area.end)


func _camera() -> Camera2D:
	return get_parent().get_node_or_null("Camera2D") as Camera2D


## Big arenas: show the whole course between rounds.
func _overview() -> void:
	var cam := _camera()
	if cam == null or not follow_camera:
		return
	var view := get_viewport().get_visible_rect().size
	var z := minf(view.x / build_area.size.x, view.y / build_area.size.y) * 1.05
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	tw.tween_property(cam, "global_position", build_area.get_center(), 0.6)
	tw.tween_property(cam, "zoom", Vector2(z, z), 0.6)


func _make_ghost(id: String, slot: int) -> Node2D:
	var def: Dictionary = Party.ITEMS[id]
	var g: Node2D
	if def.get("bomb", false):
		var s := Sprite2D.new()
		s.texture = load(def.icon)
		s.scale = Vector2(2, 2)
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		g = s
	else:
		g = load(def.scene).instantiate()
		for k in def.get("props", {}):
			g.set(k, def.props[k])
		g.process_mode = Node.PROCESS_MODE_DISABLED  # no collision, no movement while it's a ghost
	g.set_meta("item_id", id)
	g.set_meta("slot", slot)
	g.z_index = 50
	return g


func _place(slot: int) -> void:
	var g: Node2D = ghosts[slot]
	var id: String = g.get_meta("item_id")
	var pos := g.global_position
	g.queue_free()
	ghosts[slot] = null
	if Party.ITEMS[id].get("bomb", false):
		_explode(pos, float(Party.ITEMS[id].radius))
	else:
		var rec := {"id": id, "x": pos.x, "y": pos.y, "owner": slot, "rot": turns.get(slot, 0),
			"mirror": mirrors.get(slot, false), "uid": _new_uid()}
		var m = snapped.get(slot)
		if m != null and is_instance_valid(m) and not m.occupied():
			var host: Node = m.get_parent()
			rec.host = int(host.get_meta("record").uid)
			rec.point = host.mounts().find(m)
		Party.session.items.append(rec)
		_spawn_item(id, pos, slot, rec)
	snapped.erase(slot)
	Party.save()


func _start_countdown() -> void:
	phase = Phase.COUNTDOWN
	_sub.text = ""
	finished.clear()
	trap_kills.clear()
	for item in placed_items():
		if item.has_method("reset_round"):
			item.reset_round()
	for bolt in get_tree().get_nodes_in_group("bolts"):
		bolt.queue_free()  # still flying from before the round
	_spawn_coin()
	# Some rounds get a surprise rule.
	modifier = ""
	if forced_modifier != "":
		modifier = forced_modifier  # console
		forced_modifier = ""
	elif Party.session.round > 1 and _rng.randf() < 0.3:
		var names := Party.MODIFIERS.keys()
		modifier = names[_rng.randi_range(0, names.size() - 1)]
	for i in slots.size():
		var pos := spawn_origin + Vector2((i % 4) * 80.0, -(i / 4) * 100.0)
		var p := _spawner.spawn(slots[i], pos, slots.size() > 1)
		p.set_ghostly(true)  # party: run through each other, no standing on heads
		p.set_physics_process(false)
		players[slots[i]] = p
		if modifier != "":
			for k in Party.MODIFIERS[modifier]:
				p.set(k, p.get(k) * Party.MODIFIERS[modifier][k])
	_mod_label.text = ("This round: " + modifier) if modifier != "" else ""
	if modifier != "":
		_banner.text = modifier + "!"
		await get_tree().create_timer(1.2).timeout
	for n in ["3", "2", "1"]:
		_banner.text = n
		await get_tree().create_timer(0.6).timeout
	_banner.text = "Go!"
	for p in players.values():
		if is_instance_valid(p):
			p.set_physics_process(true)
	phase = Phase.RUN
	run_time = 0.0
	await get_tree().create_timer(0.7).timeout
	if _banner.text == "Go!":
		_banner.text = ""


func _start_score() -> void:
	phase = Phase.SCORE
	_timer_label.text = ""
	modifier = ""  # surprise rules last one round
	_mod_label.text = ""
	var n := slots.size()
	var gains := {}
	for s in slots:
		gains[s] = 0
	if n == 1:
		_banner.text = "Made it!" if finished.size() == 1 else "Try again"
		if finished.size() == 1:
			gains[slots[0]] += Party.POINTS_FINISH
	elif finished.size() == n:
		_banner.text = "Too easy!"
		_sub.text = "No points"
	elif finished.is_empty():
		_banner.text = "Nobody made it"
		_sub.text = "No points this round"
	else:
		_banner.text = "P%d takes the round" % finished[0] if finished.size() == 1 else "Round over"
		for s in finished:
			gains[s] += Party.POINTS_FINISH
		if finished.size() > 1:
			gains[finished[0]] += Party.POINTS_FIRST
	if n > 1:
		for owner in trap_kills:
			if gains.has(owner):
				gains[owner] += Party.POINTS_TRAP * trap_kills[owner]
	# Coin: bonus for reaching the flag with it.
	for s in finished:
		var p = players.get(s)
		if is_instance_valid(p) and p.get_meta("coin", false):
			gains[s] += Party.POINTS_COIN
	if is_instance_valid(_coin):
		_coin.queue_free()
	var old := {}
	for s in slots:
		old[s] = Party.score(s)
		Party.session.scores[str(s)] = Party.score(s) + gains[s]
	Party.session.round += 1
	Party.save()
	_last_scoreboard = [old, gains]
	_show_scoreboard(old, gains)
	await get_tree().create_timer(3.5).timeout

	var best := -1
	var winner := 0
	for s in slots:
		if Party.score(s) >= Party.TARGET_SCORE and Party.score(s) > best:
			best = Party.score(s)
			winner = s
	if winner != 0:
		phase = Phase.OVER
		_banner.text = "P%d wins the party!" % winner
		_sub.text = ""
		await get_tree().create_timer(3.0).timeout
		Party.end_game("P%d wins the party!" % winner)
	else:
		_sub.text = ""
		_start_pick()


# --- Per-frame ------------------------------------------------------------------

func _process(delta: float) -> void:
	_update_ghost_tags()
	if NetCheck.client(self):
		return  # online: the host runs the rounds
	match phase:
		Phase.PICK: _process_pick()
		Phase.PLACE: _process_place(delta)
		Phase.RUN: _process_run(delta)


func _pressed(slot: int, what: String) -> bool:
	return Input.is_action_just_pressed("p%d_%s" % [slot, what])


func _process_pick() -> void:
	var changed := false
	for slot in slots:
		if picks.has(slot):
			continue
		if _pressed(slot, "move_left"):
			cursors[slot] = _free_index(cursors[slot], -1); changed = true
		elif _pressed(slot, "move_right"):
			cursors[slot] = _free_index(cursors[slot], 1); changed = true
		elif _pressed(slot, "action_1") and not _taken(cursors[slot]):
			picks[slot] = cursors[slot]; changed = true
			# Others standing on the taken item move off it.
			for other in slots:
				if not picks.has(other) and cursors[other] == picks[slot]:
					cursors[other] = _free_index(cursors[other], 1)
	if changed:
		_update_box()
	if picks.size() == slots.size():
		_start_place()


func _taken(i: int) -> bool:
	return i in picks.values()


func _free_index(from: int, dir: int) -> int:
	var i := from
	for k in box.size():
		i = (i + dir + box.size()) % box.size()
		if not _taken(i):
			return i
	return from


func _process_place(delta: float) -> void:
	var all_done := true
	for slot in slots:
		var g = ghosts.get(slot)
		if g == null:
			continue
		all_done = false
		var p := "p%d_" % slot
		var dir := Vector2(Input.get_axis(p + "move_left", p + "move_right"), Input.get_axis(p + "move_up", p + "move_down"))
		cursor[slot] = (cursor[slot] + dir * ghost_speed * delta).clamp(build_area.position, build_area.end)
		_snap(slot, g)
		if _pressed(slot, "action_2"):
			turns[slot] = (turns[slot] + 1) % 4
		if _pressed(slot, "action_3"):
			mirrors[slot] = not mirrors[slot]
		orient(g, turns[slot], mirrors[slot])
		var id: String = g.get_meta("item_id")
		var ok := can_place(id, g.global_position, turns[slot])
		g.modulate = Color(1, 1, 1, 0.85) if ok else Color(1, 0.35, 0.35, 0.6)
		if ok and _pressed(slot, "action_1"):
			_place(slot)
	if all_done:
		_start_countdown()


## Puts the ghost on the nearest free attachment point close to the cursor
## (it then moves with that point), or on the cursor.
func _snap(slot: int, g: Node2D) -> void:
	var best: ItemMount = null
	if can_attach(g.get_meta("item_id")):
		var best_d := SNAP_DISTANCE
		var taken := []
		for other in snapped:
			if other != slot:
				taken.append(snapped[other])
		for m in free_mounts():
			var d: float = m.global_position.distance_to(cursor[slot])
			if d < best_d and not m in taken:
				best_d = d
				best = m
	if best:
		snapped[slot] = best
		g.global_position = best.global_position
	else:
		snapped.erase(slot)
		g.global_position = cursor[slot]


func _process_run(delta: float) -> void:
	run_time += delta
	var left := maxf(0.0, round_time - run_time)
	_timer_label.text = "%d" % ceili(left)
	var active := 0
	for s in slots:
		var p = players.get(s)
		if is_instance_valid(p) and not p.get_meta("eliminated", false) and not p.get_meta("finished", false):
			active += 1
	if active == 0:
		_start_score()
	elif left <= 0.0:
		var game := get_parent().get_node("Game")
		for p in players.values():
			if is_instance_valid(p) and not p.get_meta("finished", false):
				game.eliminate_player(p)
		_start_score()


func _on_goal(body: Node) -> void:
	if phase != Phase.RUN or not body.is_in_group("players") or body.get_meta("finished", false) or body.get_meta("eliminated", false):
		return
	var slot: int = body.get_meta("player_index", 0) + 1
	finished.append(slot)
	body.set_meta("finished", true)
	_goal_fx()
	NetCheck.event(self, "_goal_fx")
	if body.get_meta("coin", false) and is_instance_valid(_coin):
		_coin.hide()
	body.remove_from_group("camera_follow")
	create_tween().tween_property(body, "modulate:a", 0.0, 0.3)  # our tween: the body gets disabled
	body.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
	_sub.text = "P%d made it!" % slot


func _goal_fx() -> void:
	get_parent().add_child(Effects.burst(_goal.global_position + Vector2(0, -40), Color.WHITE, 40, 420.0,
		[Color("e64f3e"), Color("ffd65a"), Color("70e890"), Color("78c8f0"), Color("d7ffac")]))


func _popup_fx(pos: Vector2, text: String, slot: int) -> void:
	get_parent().add_child(Effects.popup(pos, text, PlayerSpawner.COLORS[(slot - 1) % 8]))


func on_trap_kill(owner_slot: int, victim: Node) -> void:
	var victim_slot: int = victim.get_meta("player_index", 0) + 1
	if phase == Phase.RUN and owner_slot != 0 and owner_slot != victim_slot:
		trap_kills[owner_slot] = trap_kills.get(owner_slot, 0) + 1
		if slots.size() > 1:
			_popup_fx(victim.global_position, "+%d" % Party.POINTS_TRAP, owner_slot)
			NetCheck.event(self, "_popup_fx", [victim.global_position, "+%d" % Party.POINTS_TRAP, owner_slot])


## One coin per round, somewhere in the middle of the course.
func _spawn_coin() -> void:
	if is_instance_valid(_coin):
		_coin.queue_free()
	var area := Rect2(goal_zone.position.x * 0.25, build_area.position.y + 250, goal_zone.position.x * 0.6, build_area.size.y * 0.45)
	var pos := Vector2(_rng.randf_range(area.position.x, area.end.x), _rng.randf_range(area.position.y, area.end.y))
	_coin = preload("res://party/coin.tscn").instantiate()
	_coin.position = pos
	_coin.name = "Coin"
	get_parent().add_child(_coin)
	NetCheck.event(self, "_client_coin", [pos])


## Online client: the round's coin (the host moves it).
func _client_coin(pos: Vector2) -> void:
	var old := get_parent().get_node_or_null("Coin")
	if old:
		old.name = "OldCoin"
		old.queue_free()
	_coin = preload("res://party/coin.tscn").instantiate()
	_coin.position = pos
	_coin.name = "Coin"
	get_parent().add_child(_coin)


func _clear_players() -> void:
	for p in players.values():
		if is_instance_valid(p):
			p.queue_free()
	players.clear()


# --- UI -------------------------------------------------------------------------

var _ghost_tags := {}  # slot -> Control


## "P1" chip + the player's turn / flip keys, following each ghost on screen.
func _update_ghost_tags() -> void:
	for slot in _ghost_tags.keys():
		if phase != Phase.PLACE or ghosts.get(slot) == null:
			_ghost_tags[slot].queue_free()
			_ghost_tags.erase(slot)
	if phase != Phase.PLACE:
		return
	var xf := get_viewport().get_canvas_transform()
	for slot in slots:
		var g = ghosts.get(slot)
		if g == null:
			continue
		if not _ghost_tags.has(slot):
			var tag := VBoxContainer.new()
			tag.alignment = BoxContainer.ALIGNMENT_CENTER
			var chip := UiTheme.player_chip(slot)
			chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			tag.add_child(chip)
			var keys := Label.new()
			var k := Net.local_keys_for(slot)
			if k != 0:
				keys.text = "%s turn  %s flip" % [UiTheme.action_key_text(k, 2), UiTheme.action_key_text(k, 3)]
			keys.add_theme_font_size_override("font_size", 14)
			keys.add_theme_color_override("font_outline_color", UiTheme.MARBLE)
			keys.add_theme_constant_override("outline_size", 5)
			tag.add_child(keys)
			_ui.get_child(0).add_child(tag)
			_ghost_tags[slot] = tag
		var t: Control = _ghost_tags[slot]
		t.position = xf * g.global_position + Vector2(-t.size.x / 2.0, -70)

func _set_title(text: String) -> void:
	get_parent().set_meta("title", text)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 40
	add_child(_ui)
	var root := Control.new()
	root.theme = UiTheme.make()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_TOP)
	col.offset_top = 60
	col.offset_left = -500
	col.offset_right = 500
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)
	_banner = UiTheme.title("", 56)
	col.add_child(_banner)
	_sub = Label.new()
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_font_override("font", UiTheme.FONT_MEDIUM)
	_sub.add_theme_font_size_override("font_size", 26)
	_sub.add_theme_color_override("font_outline_color", UiTheme.MARBLE)
	_sub.add_theme_constant_override("outline_size", 6)
	col.add_child(_sub)

	_box_row = HBoxContainer.new()
	_box_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_box_row.add_theme_constant_override("separation", 14)
	_box_row.set_anchors_preset(Control.PRESET_CENTER)
	_box_row.offset_left = -560
	_box_row.offset_right = 560
	_box_row.offset_top = -40
	root.add_child(_box_row)

	_scoreboard = VBoxContainer.new()
	_scoreboard.set_anchors_preset(Control.PRESET_CENTER)
	_scoreboard.offset_left = -330
	_scoreboard.offset_right = 330
	_scoreboard.offset_top = -40
	_scoreboard.add_theme_constant_override("separation", 8)
	root.add_child(_scoreboard)

	_timer_label = Label.new()
	_timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_timer_label.offset_left = -60
	_timer_label.offset_right = 60
	_timer_label.offset_top = 10
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_override("font", UiTheme.FONT_BOLD)
	_timer_label.add_theme_font_size_override("font_size", 40)
	_timer_label.add_theme_color_override("font_outline_color", UiTheme.MARBLE)
	_timer_label.add_theme_constant_override("outline_size", 6)
	root.add_child(_timer_label)

	# This round's surprise rule, shown under the timer for the round only.
	_mod_label = Label.new()
	_mod_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_mod_label.offset_left = -200
	_mod_label.offset_right = 200
	_mod_label.offset_top = 58
	_mod_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mod_label.add_theme_font_override("font", UiTheme.FONT_MEDIUM)
	_mod_label.add_theme_font_size_override("font_size", 22)
	_mod_label.add_theme_color_override("font_color", UiTheme.RED)
	_mod_label.add_theme_color_override("font_outline_color", UiTheme.MARBLE)
	_mod_label.add_theme_constant_override("outline_size", 6)
	root.add_child(_mod_label)


func _update_box() -> void:
	for c in _box_row.get_children():
		c.queue_free()
	for i in box.size():
		var card := _Card.new()
		card.item = box[i]
		for s in picks:
			if picks[s] == i:
				card.taker = s
		if card.taker == 0:
			for s in slots:
				if cursors.get(s, -1) == i and not picks.has(s):
					card.hovering.append(s)
		_box_row.add_child(card)


## One item in the pick box. Who is on it is shown by shape, not just colour:
## each hovering player gets their own ring (stacked) and their robot standing on
## top with their number; a picked card is greyed out with the picker's robot
## sitting on it and a big tick.
class _Card extends Control:
	const BODY := preload("res://player/player_body.webp")
	const FACE := preload("res://player/player_face.webp")
	var item := ""
	var taker := 0
	var hovering: Array = []
	var _t := 0.0
	# Kept here: a texture loaded inside _draw() would be freed before it's drawn.
	var _icon: Texture2D
	var _frame_lime := UiTheme.frame("lime")
	var _frame_crate := UiTheme.frame("crate")

	func _init() -> void:
		custom_minimum_size = Vector2(150, 236)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _robot(at: Vector2, slot: int, size: float, frame: int) -> void:
		var r := Rect2(at - Vector2(size / 2.0, size), Vector2(size, size))
		var src := Rect2(frame * 32, 0, 32, 32)
		draw_texture_rect_region(BODY, r, src, PlayerSpawner.COLORS[(slot - 1) % 8])
		draw_texture_rect_region(FACE, r, src)

	func _tag(at: Vector2, slot: int) -> void:
		var text := "P%d" % slot
		var w := UiTheme.FONT_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 14
		var r := Rect2(at - Vector2(w / 2.0, 0), Vector2(w, 24))
		draw_rect(r, PlayerSpawner.COLORS[(slot - 1) % 8])
		draw_rect(r, UiTheme.INK, false, 3.0)
		draw_string(UiTheme.FONT_BOLD, r.position + Vector2(7, 18), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiTheme.INK)

	func _draw() -> void:
		var def: Dictionary = Party.ITEMS[item]
		var lift := -10.0 if not hovering.is_empty() else 0.0
		var card := Rect2(Vector2(6, 64 + lift), Vector2(size.x - 12, 160))
		# Rings: one per hovering player, stacked outwards, in their colour.
		for k in hovering.size():
			var grow := 5.0 + k * 7.0
			var r := card.grow(grow)
			draw_rect(r, UiTheme.INK, false, 9.0)
			draw_rect(r, PlayerSpawner.COLORS[(hovering[k] - 1) % 8], false, 5.0)
		draw_style_box(_frame_lime if not hovering.is_empty() else _frame_crate, card)
		# Icon and name.
		if _icon == null:
			_icon = load(def.icon)
		var icon := _icon
		var ir := Rect2(card.position + Vector2((card.size.x - 80) / 2.0, 14), Vector2(80, 80))
		draw_texture_rect(icon, ir, false, Color(1, 1, 1, 0.35) if taker else Color.WHITE)
		var font: Font = UiTheme.FONT_MEDIUM
		var fs := 20 if def.name.length() <= 10 else 16
		draw_string(font, card.position + Vector2(0, 124), def.name, HORIZONTAL_ALIGNMENT_CENTER, card.size.x, fs,
			UiTheme.INK if not taker else Color("8a8796"))
		if taker:
			# Picked: big tick in the picker's colour, their robot sitting on top.
			var c: Color = PlayerSpawner.COLORS[(taker - 1) % 8]
			var mid := card.get_center() + Vector2(0, -16)
			var pts := PackedVector2Array([mid + Vector2(-26, 0), mid + Vector2(-8, 18), mid + Vector2(28, -22)])
			draw_polyline(pts, UiTheme.INK, 16.0)
			draw_polyline(pts, c, 9.0)
			_robot(Vector2(card.get_center().x, card.position.y + 6), taker, 56, 0)
			_tag(Vector2(card.get_center().x, card.end.y + 6), taker)
			return
		# Hovering players' robots stand on the card, side by side, bobbing a little.
		var n := hovering.size()
		for k in n:
			var x := card.get_center().x + (k - (n - 1) / 2.0) * 44.0
			var bob := absf(sin(_t * 6.0 + k)) * -5.0
			_robot(Vector2(x, card.position.y + 6 + bob), hovering[k], 48, 0)
			_tag(Vector2(x, card.end.y + 8), hovering[k])


func _add_tag(parent: Control, slot: int, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", PlayerSpawner.COLORS[(slot - 1) % 8])
	parent.add_child(l)


func _show_scoreboard(old: Dictionary, gains: Dictionary) -> void:
	for c in _scoreboard.get_children():
		c.queue_free()
	_scoreboard.show()
	var panel := PanelContainer.new()
	_scoreboard.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var head := Label.new()
	head.text = "First to %d points wins" % Party.TARGET_SCORE
	head.add_theme_color_override("font_color", UiTheme.MUTED)
	col.add_child(head)
	for s in slots:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var chip := UiTheme.player_chip(s)
		chip.custom_minimum_size = Vector2(52, 0)
		row.add_child(chip)
		var bar_bg := Panel.new()
		var frame := StyleBoxFlat.new()
		frame.bg_color = Color("d8d5de")
		frame.border_color = UiTheme.INK
		frame.set_border_width_all(3)
		bar_bg.add_theme_stylebox_override("panel", frame)
		bar_bg.custom_minimum_size = Vector2(440, 30)
		row.add_child(bar_bg)
		var bar := ColorRect.new()
		bar.color = PlayerSpawner.COLORS[(s - 1) % 8]
		bar.position = Vector2(3, 3)
		bar.size = Vector2(434.0 * minf(1.0, float(old[s]) / Party.TARGET_SCORE), 24)
		bar_bg.add_child(bar)
		var target := 434.0 * minf(1.0, float(Party.score(s)) / Party.TARGET_SCORE)
		bar.create_tween().tween_property(bar, "size:x", target, 0.8).set_delay(0.4)
		var pts := Label.new()
		pts.add_theme_font_override("font", UiTheme.FONT_BOLD)
		pts.text = "%d  %s" % [Party.score(s), ("+%d" % gains[s]) if gains[s] > 0 else ""]
		row.add_child(pts)
		col.add_child(row)


## Placing helpers, drawn in the world on top of everything:
##  - no-build zones (red hatching, brighter when an item is pushed into one)
##  - each ghost's footprint (red when it can't go there)
##  - crossbow bolt paths, mine and bomb blast zones (and what a bomb would destroy)
## Saw rails, pendulum arcs and flame reach are drawn by the items themselves.
class _Preview extends Node2D:
	var ctl
	const RED := Color(0.9, 0.31, 0.24)

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var phase: int = ctl.phase
		if not phase in [ctl.Phase.PICK, ctl.Phase.PLACE, ctl.Phase.COUNTDOWN]:
			return
		var space := get_world_2d().direct_space_state
		# Placed items: faint hints.
		for item in ctl.placed_items():
			if item.has_method("bolt_end"):
				_dotted(item.muzzle(), item.bolt_end(space), Color(RED, 0.55), 6.0)
			if item.get_script() == preload("res://party/mine.gd"):
				_ring(item.global_position, item.radius, Color(RED, 0.25))
		if phase != ctl.Phase.PLACE:
			return
		var blocked_zone := {}
		for slot in ctl.slots:
			var g = ctl.ghosts.get(slot)
			if g == null:
				continue
			var id: String = g.get_meta("item_id")
			var def: Dictionary = Party.ITEMS[id]
			var rot: int = ctl.turns.get(slot, 0)
			var col: Color = PlayerSpawner.COLORS[(slot - 1) % 8]
			if def.get("bomb", false):
				var r: float = def.radius
				draw_circle(g.global_position, r, Color(RED, 0.12))
				_ring(g.global_position, r, RED)
				for victim in ctl.items_in_blast(g.global_position, r):
					var vr: Rect2 = ctl._footprint(victim.get_meta("record").id, victim.global_position, int(victim.get_meta("record").get("rot", 0)))
					_cross(vr, RED)
				continue
			var m = ctl.snapped.get(slot)
			if m != null and is_instance_valid(m):
				# Snapped to an attachment point: ring + link to where the cursor is.
				draw_line(ctl.cursor[slot], m.global_position, Color(col, 0.7), 3.0)
				draw_arc(m.global_position, 16.0, 0.0, TAU, 24, Color.BLACK, 7.0)
				draw_arc(m.global_position, 16.0, 0.0, TAU, 24, col, 4.0)
			var fp: Rect2 = ctl._footprint(id, g.global_position, rot)
			var ok: bool = ctl.can_place(id, g.global_position, rot)
			_dashed_rect(fp, col if ok else RED, 3.0)
			if not ok:
				for zone in [ctl.start_zone, ctl.goal_zone]:
					if fp.intersects(zone):
						blocked_zone[zone] = true
			if g.has_method("bolt_end"):
				_dotted(g.muzzle(), g.bolt_end(space), Color(col, 0.9), 6.0)
			if id == "mine":
				_ring(g.global_position, g.radius, Color(RED, 0.7))
		for zone in [ctl.start_zone, ctl.goal_zone]:
			_hatch(zone, Color(RED, 0.8 if blocked_zone.has(zone) else 0.18), blocked_zone.has(zone))

	func _dotted(a: Vector2, b: Vector2, c: Color, r: float) -> void:
		var d := a.distance_to(b)
		var n := int(d / 22.0)
		for i in n + 1:
			draw_circle(a.lerp(b, float(i) / maxi(n, 1)), r * 0.5, c)
		draw_line(b + Vector2(-8, -8), b + Vector2(8, 8), c, 3.0)
		draw_line(b + Vector2(-8, 8), b + Vector2(8, -8), c, 3.0)

	func _ring(p: Vector2, r: float, c: Color) -> void:
		var n := 40
		for i in n:
			if i % 2 == 0:
				draw_arc(p, r, TAU * i / n, TAU * (i + 1) / n, 4, c, 3.0)

	func _cross(r: Rect2, c: Color) -> void:
		draw_rect(r, Color(c, 0.25))
		draw_line(r.position, r.end, c, 4.0)
		draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), c, 4.0)

	func _dashed_rect(r: Rect2, c: Color, w: float) -> void:
		var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		for k in 4:
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[(k + 1) % 4]
			var n := maxi(1, int(a.distance_to(b) / 14.0))
			for i in n:
				if i % 2 == 0:
					draw_line(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), c, w)

	## No-build zone: outline plus diagonal stripes.
	func _hatch(r: Rect2, c: Color, strong: bool) -> void:
		draw_rect(r, c, false, 4.0 if strong else 2.0)
		if not strong:
			return
		draw_rect(r, Color(c, 0.12))
		var step := 28.0
		var x := r.position.x - r.size.y
		while x < r.end.x:
			var a := Vector2(x, r.end.y)
			var b := Vector2(x + r.size.y, r.position.y)
			# Clip the stripe to the rectangle.
			if a.x < r.position.x:
				a = Vector2(r.position.x, r.end.y - (r.position.x - a.x))
			if b.x > r.end.x:
				b = Vector2(r.end.x, r.position.y + (b.x - r.end.x))
			if a.x <= b.x:
				draw_line(a, b, Color(c, 0.5), 3.0)
			x += step
