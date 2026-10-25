extends Node
## Gamepads (Xbox, PlayStation, Nintendo Switch Pro and Joy-Cons, ...), as many
## as there are players. A pad belongs to nobody until one of its buttons is
## pressed: then it takes a free player (P6, P7, P8 first, then P5, P4...) and
## keeps it until the game closes, even if it's unplugged for a while. Its
## buttons are added to that player's actions next to the keyboard keys.
##
## Buttons go by place, not by what's printed on them: "action_1" (jump) is the
## bottom button on every pad (A on Xbox, B on Nintendo, Cross on PlayStation).

## The pad buttons of each action (stick directions are added for moves).
const BUTTONS := {
	"move_left": JOY_BUTTON_DPAD_LEFT, "move_right": JOY_BUTTON_DPAD_RIGHT,
	"move_up": JOY_BUTTON_DPAD_UP, "move_down": JOY_BUTTON_DPAD_DOWN,
	"action_1": JOY_BUTTON_A, "action_2": JOY_BUTTON_X, "action_3": JOY_BUTTON_Y,
}
const STICK := {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
	"move_up": [JOY_AXIS_LEFT_Y, -1.0], "move_down": [JOY_AXIS_LEFT_Y, 1.0]}
## Which players a new pad takes, best first.
const ORDER := [6, 7, 8, 5, 4, 3, 2, 1]
const NINTENDO_VENDOR := 0x057e
const SONY_VENDOR := 0x054c

signal changed

var _slot_of := {}   # device -> player slot (1-8)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_connection)
	apply()


## The player a pad plays, or 0.
func slot_of(device: int) -> int:
	return int(_slot_of.get(device, 0))


## The pad that plays `slot`, or -1.
func device_of(slot: int) -> int:
	for d in _slot_of:
		if _slot_of[d] == slot:
			return d
	return -1


## Gives `device` to player `slot` (0: nobody). Whoever had that player before
## gets nothing.
func assign(device: int, slot: int) -> void:
	for d in _slot_of.keys():
		if _slot_of[d] == slot or d == device:
			_slot_of.erase(d)
	if slot >= 1 and slot <= 8:
		_slot_of[device] = slot
	apply()
	changed.emit()


## Every pad belongs to nobody again.
func reset() -> void:
	_slot_of.clear()
	apply()
	changed.emit()


func _input(event: InputEvent) -> void:
	# A pad's first press takes a player, and counts for it right away: the
	# Players screen (which looks at this same press) joins them.
	if event is InputEventJoypadButton and event.pressed and not _slot_of.has(event.device):
		var slot := _free_slot()
		if slot != 0:
			assign(event.device, slot)


## A player nobody plays yet and no pad has.
func _free_slot() -> int:
	var net := get_node_or_null("/root/Net")
	var gs := get_node_or_null("/root/GameState")
	var party := get_node_or_null("/root/Party")
	var online: bool = net != null and net.is_online()
	for slot in ORDER:
		if device_of(slot) != -1:
			continue
		if online:
			if slot in net.my_slots().values():
				continue  # that key set plays already
		elif (gs and gs.is_joined(slot)) or (party and party.bot_list.has(slot)):
			continue
		return slot
	return 0


func _on_connection(device: int, connected: bool) -> void:
	var chat := get_node_or_null("/root/Chat")
	var slot := slot_of(device)
	var text := ""
	if connected:
		text = "%s connected%s" % [pad_name(device), (": P%d" % slot) if slot else ", press a button to play"]
	elif slot:
		text = "P%d's pad disconnected" % slot
	if text != "" and chat:
		chat.add("", text)  # a small line at the bottom left
	changed.emit()


## Puts the pads' buttons on the players' actions (p1_.. and, online, k1_..).
func apply() -> void:
	var net := get_node_or_null("/root/Net")
	for slot in range(1, 9):
		var device := device_of(slot)
		for a in BUTTONS:
			var events: Array[InputEvent] = []
			if device >= 0:
				var b := InputEventJoypadButton.new()
				b.device = device
				b.button_index = BUTTONS[a]
				events.append(b)
				if STICK.has(a):
					var m := InputEventJoypadMotion.new()
					m.device = device
					m.axis = STICK[a][0]
					m.axis_value = STICK[a][1]
					events.append(m)
			for action in ["p%d_%s" % [slot, a], "k%d_%s" % [slot, a]]:
				if not InputMap.has_action(action):
					continue
				if net and net._erased_events.has(action):
					# Online the game slots' own actions are kept aside (net.gd):
					# change what comes back after the game.
					var kept: Array = net._erased_events[action].filter(func(e): return not _is_pad(e))
					kept.append_array(events)
					net._erased_events[action] = kept
					continue
				for e in InputMap.action_get_events(action):
					if _is_pad(e):
						InputMap.action_erase_event(action, e)
				for e in events:
					InputMap.action_add_event(action, e)


func _is_pad(e: InputEvent) -> bool:
	return e is InputEventJoypadButton or e is InputEventJoypadMotion


enum Kind { XBOX, NINTENDO, PLAYSTATION }

func kind(device: int) -> Kind:
	var name := Input.get_joy_name(device).to_lower()
	var vendor := int(Input.get_joy_info(device).get("vendor_id", 0))
	if vendor == NINTENDO_VENDOR or name.contains("nintendo") or name.contains("joy-con") \
			or name.contains("switch") or name.contains("pro controller"):
		return Kind.NINTENDO
	if vendor == SONY_VENDOR or name.contains("playstation") or name.contains("dualsense") \
			or name.contains("dualshock") or name.begins_with("ps") or name.contains("sony"):
		return Kind.PLAYSTATION
	return Kind.XBOX


## What's printed on a pad's button ("B" on a Switch pad's bottom button).
func button_text(device: int, button: int) -> String:
	var names: Array = {
		Kind.XBOX: ["A", "B", "X", "Y"],
		Kind.NINTENDO: ["B", "A", "Y", "X"],
		Kind.PLAYSTATION: ["Cross", "Circle", "Square", "Triangle"],
	}[kind(device)]
	if button >= 0 and button < names.size():
		return names[button]
	match button:
		JOY_BUTTON_DPAD_LEFT: return "Left"
		JOY_BUTTON_DPAD_RIGHT: return "Right"
		JOY_BUTTON_DPAD_UP: return "Up"
		JOY_BUTTON_DPAD_DOWN: return "Down"
	return "Button %d" % button


## A short name for a pad ("Pro Controller", "Joy-Con (L)", "Pad 2").
func pad_name(device: int) -> String:
	var name := Input.get_joy_name(device).strip_edges()
	return name.left(24) if name != "" else "Pad %d" % (device + 1)


## The pads plugged in, with their players: [[device, name, slot], ...].
func connected() -> Array:
	var out := []
	for d in Input.get_connected_joypads():
		out.append([d, pad_name(d), slot_of(d)])
	return out
