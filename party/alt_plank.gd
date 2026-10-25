extends Platform
## Special item: a plank that's solid for 2 seconds, then gone for 2 seconds, on a
## loop. It blinks before it goes.

const ON := 2.0
const OFF := 2.0
const WARN := 0.6

var _t := 0.0


func _ready() -> void:
	super._ready()
	if not Engine.is_editor_hint():
		add_to_group("net_sync_slow")  # clients run the clock themselves


## Will it be solid `seconds` from now? (Bots use it to plan their jumps.)
func solid_in(seconds: float) -> bool:
	return fmod(_t + seconds, ON + OFF) < ON


func body_rid() -> RID:
	return _body.get_rid()


func reset_round() -> void:
	_t = 0.0
	_set_solid(true)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if Engine.is_editor_hint():
		return
	_t += delta
	var c := fmod(_t, ON + OFF)
	var want := c < ON
	if want != solid:
		_set_solid(want)
	elif solid:
		_sprite.modulate.a = 0.45 + 0.55 * absf(cos(_t * 12.0)) if c > ON - WARN else 1.0


func net_state() -> Array:
	return super.net_state() + [snappedf(_t, 0.01)]


func net_apply(s: Array) -> void:
	super.net_apply(s)
	if s.size() > 3 and absf(_t - (s[3] + NetCheck.lead(self))) > 0.08:
		_t = s[3] + NetCheck.lead(self)
