@tool
class_name LogicGate
extends LogicNode
## Combines its inputs:
##   AND  - on when ALL inputs are on
##   OR   - on when ANY input is on
##   NOT  - on when NO input is on (use it with one input to invert it)
##   NAND - opposite of AND
##   NOR  - opposite of OR (same as NOT)
##   XOR  - on when an ODD number of inputs are on (for 2 inputs: exactly one)
##   XNOR - opposite of XOR

enum Type { AND, OR, NOT, NAND, NOR, XOR, XNOR }

@export var type: Type = Type.AND:
	set(value):
		type = value
		queue_redraw()
		if is_node_ready() and not Engine.is_editor_hint():
			_on_inputs_changed()


func _on_inputs_changed() -> void:
	var on := count_on(inputs)
	var total := count_valid(inputs)
	var all_on := total > 0 and on == total
	var result: bool
	match type:
		Type.AND: result = all_on
		Type.OR: result = on > 0
		Type.NOT, Type.NOR: result = on == 0
		Type.NAND: result = not all_on
		Type.XOR: result = on % 2 == 1
		Type.XNOR: result = on % 2 == 0
	set_output(result)


func _default_texture() -> Texture2D:
	return preload("res://logic/gate.webp")


## The gate type is gameplay information, so it is always printed on the sprite.
func _always_label() -> String:
	return Type.keys()[type]


func _label() -> PackedStringArray:
	return PackedStringArray(["GATE", "%d inputs" % inputs.size()])
