extends Node
## Autoload "DebugView": global switch for debug drawings (one-way arrows, logic wires...).
## On at start when Debug > "Visible Collision Shapes" is ticked. F3 toggles it in game.

signal changed(enabled: bool)

var enabled: bool = false:
	set(value):
		if value == enabled:
			return
		enabled = value
		changed.emit(enabled)


func _ready() -> void:
	enabled = get_tree().debug_collisions_hint


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		enabled = not enabled
