class_name PlayerKeys
## Keyboard keys for each player's controls (Settings > Controls). Changes are
## saved in user://controls.cfg and put back at every start. Gamepads keep their
## buttons: only keyboard keys are changed here.
##
## When several people share one keyboard, some keyboards can't see more than a
## few keys held at once ("ghosting": a key press just doesn't arrive). Moving
## players' keys apart (one on the arrows, one on the numpad...) helps.

const PATH := "user://controls.cfg"
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "action_1", "action_2", "action_3"]
const ACTION_NAMES := {"move_left": "Left", "move_right": "Right", "move_up": "Up", "move_down": "Down",
	"action_1": "Jump", "action_2": "Turn", "action_3": "Flip"}
## Players that use the keyboard by default.
const KEYBOARD_SLOTS := [1, 2, 3, 4, 5]


static func action(slot: int, a: String) -> String:
	return "p%d_%s" % [slot, a]


## The physical key (keycode) of an action, or 0.
static func key_of(slot: int, a: String) -> Key:
	for e in InputMap.action_get_events(action(slot, a)):
		if e is InputEventKey:
			return e.physical_keycode if e.physical_keycode != 0 else e.keycode
	return KEY_NONE


static func key_name(k: Key) -> String:
	if k == KEY_NONE:
		return "-"
	return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(k)) if DisplayServer.get_name() != "headless" else OS.get_keycode_string(k)


## The game's own keys for an action (project settings).
static func default_key(slot: int, a: String) -> Key:
	var setting = ProjectSettings.get_setting("input/" + action(slot, a))
	if setting is Dictionary:
		for e in setting.get("events", []):
			if e is InputEventKey:
				return e.physical_keycode if e.physical_keycode != 0 else e.keycode
	return KEY_NONE


static func _set_key(slot: int, a: String, k: Key) -> void:
	var act := action(slot, a)
	for e in InputMap.action_get_events(act):
		if e is InputEventKey:
			InputMap.action_erase_event(act, e)
	if k != KEY_NONE:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(act, e)


## Gives `slot`'s action this key. If someone else had it, they get our old key
## (a swap, so no key does two things). Returns "" or what was swapped.
static func rebind(slot: int, a: String, k: Key) -> String:
	var old := key_of(slot, a)
	var note := ""
	for s in range(1, 9):
		for other in ACTIONS:
			if (s != slot or other != a) and key_of(s, other) == k:
				_set_key(s, other, old)
				note = "Swapped with P%d %s" % [s, ACTION_NAMES[other]]
	_set_key(slot, a, k)
	save()
	return note


static func reset() -> void:
	for s in range(1, 9):
		for a in ACTIONS:
			if default_key(s, a) != KEY_NONE or key_of(s, a) != KEY_NONE:
				_set_key(s, a, default_key(s, a))
	DirAccess.remove_absolute(PATH)


static func save() -> void:
	var cfg := ConfigFile.new()
	for s in range(1, 9):
		for a in ACTIONS:
			var k := key_of(s, a)
			if k != default_key(s, a):
				cfg.set_value("p%d" % s, a, int(k))
	cfg.save(PATH)


## Puts the saved keys back (at startup).
static func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for sec in cfg.get_sections():
		var slot := int(sec.trim_prefix("p"))
		for a in cfg.get_section_keys(sec):
			if a in ACTIONS and InputMap.has_action(action(slot, a)):
				_set_key(slot, a, int(cfg.get_value(sec, a)) as Key)
