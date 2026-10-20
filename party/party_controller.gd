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
@export var bomb_radius := 130.0

var phase: Phase = Phase.PICK
var slots: Array[int] = []
var box: Array[String] = []
var cursors := {}      # slot -> index in box
var picks := {}        # slot -> index in box
var ghosts := {}       # slot -> Node2D
var players := {}      # slot -> player
var finished: Array[int] = []
var trap_kills := {}   # owner slot -> kills this round
var run_time := 0.0

var _rng := RandomNumberGenerator.new()
var _ui: CanvasLayer
var _banner: Label
var _sub: Label
var _box_row: HBoxContainer
var _scoreboard: VBoxContainer
var _timer_label: Label

@onready var _items: Node2D = $"../Items"
@onready var _spawner: PlayerSpawner = $"../PlayerSpawner"
@onready var _goal: Area2D = $"../Goal"


func _ready() -> void:
	add_to_group("party_controller")
	_rng.randomize()
	if Party.session.is_empty() and not Party.load_save():
		Party.new_session(GameState.joined)  # arena started directly from the editor
	slots = Party.players()
	for rec in Party.session.items:
		_spawn_item(rec.id, Vector2(rec.x, rec.y), int(rec.owner), rec)
	_goal.collision_layer = 0
	_goal.collision_mask = Layers.PLAYERS
	_goal.body_entered.connect(_on_goal)
	_build_ui()
	_start_pick()


# --- Items --------------------------------------------------------------------

func _spawn_item(id: String, pos: Vector2, owner_slot: int, record: Dictionary) -> Node2D:
	var def: Dictionary = Party.ITEMS[id]
	var item: Node2D = load(def.scene).instantiate()
	for k in def.get("props", {}):
		item.set(k, def.props[k])
	item.position = pos
	item.set_meta("record", record)
	_items.add_child(item)
	for h in item.find_children("*", "Area2D", true, false):
		if h is Hazard:
			h.owner_slot = owner_slot
	return item


func _footprint(id: String, pos: Vector2) -> Rect2:
	var def: Dictionary = Party.ITEMS[id]
	var size: Vector2 = def.size
	return Rect2(pos + def.get("offset", Vector2.ZERO) - size / 2.0, size)


func can_place(id: String, pos: Vector2) -> bool:
	if Party.ITEMS[id].get("bomb", false):
		return true
	var r := _footprint(id, pos)
	return not r.intersects(start_zone) and not r.intersects(goal_zone)


func _explode(pos: Vector2) -> void:
	for item in _items.get_children():
		if not item.has_meta("record"):
			continue  # ghosts still being placed, effects
		if item.global_position.distance_to(pos) <= bomb_radius:
			Party.session.items.erase(item.get_meta("record"))
			item.queue_free()
	var boom := _Boom.new()
	boom.position = pos
	boom.radius = bomb_radius
	_items.add_child(boom)


# --- Phases --------------------------------------------------------------------

func _start_pick() -> void:
	phase = Phase.PICK
	_clear_players()
	_set_title("Party, round %d" % Party.session.round)
	_banner.text = "Round %d" % Party.session.round
	_sub.text = "Pick something with left and right, then jump"
	var ids := Party.ITEMS.keys()
	box.clear()
	var count := slots.size() + 2
	var bombs := 0
	while box.size() < count:
		var id: String = ids[_rng.randi_range(0, ids.size() - 1)]
		if id == "bomb" and (bombs >= 1 or Party.session.items.is_empty()):
			continue
		if id == "bomb":
			bombs += 1
		box.append(id)
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
	_sub.text = "Move it with your keys and jump to put it down"
	_banner.text = ""
	ghosts.clear()
	for i in slots.size():
		var slot := slots[i]
		var id := box[picks[slot]]
		var g := _make_ghost(id, slot)
		g.position = build_area.get_center() + Vector2((i - slots.size() / 2.0) * 120.0, -150)
		_items.add_child(g)
		ghosts[slot] = g


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
	var tag := Label.new()
	tag.text = "P%d" % slot
	tag.position = Vector2(-20, -70)
	tag.add_theme_font_size_override("font_size", 28)
	tag.add_theme_color_override("font_color", PlayerSpawner.COLORS[(slot - 1) % 8])
	tag.add_theme_color_override("font_outline_color", Color.BLACK)
	tag.add_theme_constant_override("outline_size", 8)
	g.add_child(tag)
	return g


func _place(slot: int) -> void:
	var g: Node2D = ghosts[slot]
	var id: String = g.get_meta("item_id")
	var pos := g.position
	g.queue_free()
	ghosts[slot] = null
	if Party.ITEMS[id].get("bomb", false):
		_explode(pos)
	else:
		var rec := {"id": id, "x": pos.x, "y": pos.y, "owner": slot}
		Party.session.items.append(rec)
		_spawn_item(id, pos, slot, rec)
	Party.save()


func _start_countdown() -> void:
	phase = Phase.COUNTDOWN
	_sub.text = ""
	finished.clear()
	trap_kills.clear()
	for i in slots.size():
		var pos := spawn_origin + Vector2((i % 4) * 80.0, -(i / 4) * 100.0)
		var p := _spawner.spawn(slots[i], pos, slots.size() > 1)
		p.set_physics_process(false)
		players[slots[i]] = p
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
		_sub.text = "Everyone made it, so nobody scores"
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
	var old := {}
	for s in slots:
		old[s] = Party.score(s)
		Party.session.scores[str(s)] = Party.score(s) + gains[s]
	Party.session.round += 1
	Party.save()
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
		g.position += dir * ghost_speed * delta
		g.position = g.position.clamp(build_area.position, build_area.end)
		var id: String = g.get_meta("item_id")
		var ok := can_place(id, g.position)
		var c: Color = PlayerSpawner.COLORS[(slot - 1) % 8]
		g.modulate = Color(c.r, c.g, c.b, 0.75) if ok else Color(1, 0.3, 0.3, 0.6)
		if ok and _pressed(slot, "action_1"):
			_place(slot)
	if all_done:
		_start_countdown()


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
	body.remove_from_group("camera_follow")
	create_tween().tween_property(body, "modulate:a", 0.0, 0.3)  # our tween: the body gets disabled
	body.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
	_sub.text = "P%d made it!" % slot


func on_trap_kill(owner_slot: int, victim: Node) -> void:
	var victim_slot: int = victim.get_meta("player_index", 0) + 1
	if phase == Phase.RUN and owner_slot != 0 and owner_slot != victim_slot:
		trap_kills[owner_slot] = trap_kills.get(owner_slot, 0) + 1


func _clear_players() -> void:
	for p in players.values():
		if is_instance_valid(p):
			p.queue_free()
	players.clear()


# --- UI -------------------------------------------------------------------------

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


func _update_box() -> void:
	for c in _box_row.get_children():
		c.queue_free()
	for i in box.size():
		var def: Dictionary = Party.ITEMS[box[i]]
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(140, 160)
		card.add_theme_stylebox_override("panel", UiTheme.frame("crate"))
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		card.add_child(v)
		var icon := TextureRect.new()
		icon.texture = load(def.icon)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.custom_minimum_size = Vector2(80, 64)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		v.add_child(icon)
		var name := Label.new()
		name.text = def.name
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.add_theme_font_override("font", UiTheme.FONT_MEDIUM)
		name.add_theme_font_size_override("font_size", 22)
		v.add_child(name)
		var who := HBoxContainer.new()
		who.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(who)
		var owner := 0
		for s in picks:
			if picks[s] == i:
				owner = s
		if owner:
			card.modulate = Color(1, 1, 1, 0.45)
			who.add_child(UiTheme.player_chip(owner))
		else:
			for s in cursors:
				if not picks.has(s) and cursors[s] == i:
					who.add_child(UiTheme.player_chip(s))
			if who.get_child_count() > 0:
				card.add_theme_stylebox_override("panel", UiTheme.frame("lime"))
		_box_row.add_child(card)


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


## Expanding ring for the bomb.
class _Boom extends Node2D:
	var radius := 120.0
	var t := 0.0
	func _process(delta: float) -> void:
		t += delta
		queue_redraw()
		if t > 0.5:
			queue_free()
	func _draw() -> void:
		var k := t / 0.5
		draw_circle(Vector2.ZERO, radius * k, Color(1, 0.6, 0.2, 0.5 * (1.0 - k)))
		draw_arc(Vector2.ZERO, radius * k, 0, TAU, 48, Color(1, 0.9, 0.5, 1.0 - k), 6.0)
