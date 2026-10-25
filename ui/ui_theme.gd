class_name UiTheme
## The game's UI look, taken from the sprites: black outlines, pastel fills,
## marble backgrounds, pixel type (Jersey 10 and 15, OFL - see ui/fonts).

const INK := Color("000000")        # outlines and text, like the sprites
const MARBLE := Color("ece9ee")     # paper / panels (from tile.webp)
const MINT := Color("b0e2bc")       # machine bodies
const LIVE := Color("70e890")       # live cable
const LIME := Color("d7ffac")       # selection
const RED := Color("e64f3e")        # button cap
const CRATE := Color("e9cd96")
const SKY := Color("78c8f0")
const MUTED := Color("5c5a68")      # secondary text on marble
const TEXT := INK
const ACCENT := Color("2f7a43")     # dark green, readable on marble

const FONT_REGULAR := preload("res://ui/fonts/Jersey15.ttf")
const FONT_MEDIUM := preload("res://ui/fonts/Jersey15.ttf")
const FONT_BOLD := preload("res://ui/fonts/Jersey10.ttf")


static func frame(name: String) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = load("res://ui/frames/%s.png" % name)
	s.set_texture_margin_all(9)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 12
	s.content_margin_bottom = 14
	return s


static func make() -> Theme:
	var t := Theme.new()
	t.default_font = FONT_REGULAR
	t.default_font_size = 22
	t.set_color("font_color", "Label", INK)
	t.set_constant("outline_size", "Label", 0)
	t.set_stylebox("panel", "PanelContainer", frame("marble"))
	t.set_stylebox("normal", "Button", frame("marble"))
	t.set_stylebox("hover", "Button", frame("lime"))
	t.set_stylebox("focus", "Button", frame("lime"))
	t.set_stylebox("pressed", "Button", frame("mint"))
	t.set_stylebox("disabled", "Button", frame("marble"))
	t.set_font("font", "Button", FONT_MEDIUM)
	t.set_font_size("font_size", "Button", 26)
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", INK)
	t.set_color("font_disabled_color", "Button", MUTED)
	return t


## Big pixel heading, black with a thin marble outline so it reads over any tile.
static func title(text: String, size := 64) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", FONT_BOLD)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", MARBLE)
	l.add_theme_constant_override("outline_size", maxi(4, size / 8))
	return l


static func button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 0)
	b.pressed.connect(on_pressed)
	return b


## Small label for a player: "P2" in a box filled with the player's colour.
## "P3", or "B1" for a bot in the party being played.
static func slot_label(slot: int) -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var party = tree.root.get_node_or_null("Party")
	var net = tree.root.get_node_or_null("Net")
	if net and net.is_online():
		return net.player_label(slot)
	var scene := tree.current_scene
	if party and scene and scene.has_node("PartyController"):
		return party.label(slot)
	return "P%d" % slot


static func player_chip(slot: int, faded := false) -> PanelContainer:
	var p := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = PlayerSpawner.COLORS[(slot - 1) % 8]
	box.border_color = INK
	box.set_border_width_all(3)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 0
	box.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", box)
	var l := Label.new()
	l.text = slot_label(slot)
	l.add_theme_font_override("font", FONT_BOLD)
	l.add_theme_font_size_override("font_size", 18)
	p.add_child(l)
	if faded:
		p.modulate = Color(1, 1, 1, 0.35)
	return p


## Action prefix of key set n: online the keys live in k1_..k8_ (net.gd).
static func _keys_of(n: int) -> String:
	var online := InputMap.has_action("k%d_action_1" % n) and InputMap.action_get_events("p%d_action_1" % n).is_empty()
	return ("k%d_" if online else "p%d_") % n


## The key a player jumps with, as text ("Space", "N", "Pad 1 A").
static func jump_key_text(n: int) -> String:
	return action_key_text(n, 1)


## The key for a player's action 1, 2 or 3 ("Space", "E", "Pad 1 X").
static func action_key_text(n: int, action: int) -> String:
	var name: String = _keys_of(n) + "action_%d" % action
	if not InputMap.has_action(name):
		return "-"
	for ev in InputMap.action_get_events(name):
		if ev is InputEventJoypadButton:
			return "Pad %d %s" % [ev.device + 1, ["A", "B", "X", "Y"][clampi(ev.button_index, 0, 3)]]
		return _event_text(ev)
	return "-"


## Readable controls for player n (1-based), from the Input Map.
static func controls_text(n: int) -> String:
	var parts := []
	for action in ["move_left", "move_right", "action_1"]:
		var name: String = _keys_of(n) + action
		if not InputMap.has_action(name):
			continue
		for ev in InputMap.action_get_events(name):
			parts.append(_event_text(ev))
			break
	if parts.is_empty():
		return "-"
	if parts[0].begins_with("Pad"):
		return parts[0] + " stick or D-pad, A to jump"
	return "%s %s to move, %s to jump" % parts


static func _event_text(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var code: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
		var local := code
		if ev.physical_keycode != 0 and DisplayServer.get_name() != "headless":
			local = DisplayServer.keyboard_get_keycode_from_physical(code)  # shows AZERTY etc. correctly
		return OS.get_keycode_string(local)
	if ev is InputEventJoypadMotion or ev is InputEventJoypadButton:
		return "Pad %d" % (ev.device + 1)
	return ev.as_text()
