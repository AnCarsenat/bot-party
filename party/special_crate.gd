extends Node2D
## Special item: a crate that turns into a different special item every round
## (any special that fits in its spot). Which one comes from its id and the round
## number, so it's the same on every computer online.

const TEX := preload("res://party/art/special_crate.webp")
## Specials it can become: small enough, not bombs, nothing that others hang from.
## (Not the Party > Items odds: those are each player's own, and online every
## computer must pick the same.)
const MAX_SIZE := Vector2(200, 200)

var current := ""
var _round := -1
var _inside: Node2D


func _ready() -> void:
	set_process(has_meta("record"))  # a ghost (being placed) stays a crate


static func choices(party: Node) -> Array:
	var out := []
	for id in party.ITEMS:
		var d: Dictionary = party.ITEMS[id]
		if d.get("special", false) and id != "special_crate" and not d.get("bomb", false) and not d.get("host", false) \
				and d.has("scene") and d.size.x <= MAX_SIZE.x and d.size.y <= MAX_SIZE.y:
			out.append(id)
	out.sort()
	return out


func _process(_d: float) -> void:
	var party := get_node("/root/Party")
	var r := int(party.session.get("round", 1))
	if r == _round:
		return
	_round = r
	var ids := choices(party)
	if ids.is_empty():
		return
	var h := hash([int(get_meta("record").get("uid", 0)), r])
	_become(ids[posmod(h, ids.size())])


func _become(id: String) -> void:
	if id == current and is_instance_valid(_inside):
		return
	if is_instance_valid(_inside):
		remove_child(_inside)  # now: the new one must get the same name (online, paths must match)
		_inside.queue_free()
	current = id
	var def: Dictionary = get_node("/root/Party").ITEMS[id]
	_inside = load(def.scene).instantiate()
	for k in def.get("props", {}):
		_inside.set(k, def.props[k])
	_inside.name = "Inside"
	add_child(_inside)
	_add_mod_script(_inside, def)
	# Its traps count for whoever placed the crate.
	for h in _inside.find_children("*", "Area2D", true, false):
		if h is Hazard:
			h.owner_slot = get_meta("owner_slot", 0)
	queue_redraw()


## A mod item's own script (like PartyController._add_mod_script).
static func _add_mod_script(item: Node, def: Dictionary) -> void:
	if def.has("script"):
		var behaviour := Node.new()
		behaviour.name = "ModScript"
		behaviour.set_script(load(def.script))
		item.add_child(behaviour)


func reset_round() -> void:
	if is_instance_valid(_inside) and _inside.has_method("reset_round"):
		_inside.reset_round()


func _draw() -> void:
	if not is_instance_valid(_inside):
		draw_texture_rect(TEX, Rect2(-32, -32, 64, 64), false)
		return
	# A little "?" tag: it'll be something else next round.
	draw_rect(Rect2(-40, -48, 20, 20), Color.BLACK)
	draw_rect(Rect2(-38, -46, 16, 16), Color("e8b270"))
	draw_string(UiTheme.FONT_BOLD, Vector2(-36, -32), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
