class_name Effects
## Small one-shot visual effects (puffs, confetti, rings, floating text).


## Burst of square particles.
static func burst(pos: Vector2, color: Color, amount := 18, speed := 260.0, colors: Array = []) -> Node2D:
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = 0.7
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, 700)
	p.scale_amount_min = 5.0
	p.scale_amount_max = 9.0
	p.color = color
	if not colors.is_empty():
		var g := Gradient.new()
		g.offsets = PackedFloat32Array()
		g.colors = PackedColorArray()
		for i in colors.size():
			g.add_point(float(i) / maxf(1, colors.size() - 1), colors[i])
		p.color_initial_ramp = g
	p.z_index = 60
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


## Expanding ring (explosions).
static func ring(pos: Vector2, radius: float, color: Color) -> Node2D:
	var r := _Ring.new()
	r.position = pos
	r.radius = radius
	r.color = color
	return r


## "+2" style text that floats up and fades.
static func popup(pos: Vector2, text: String, color: Color) -> Node2D:
	var n := Node2D.new()
	n.position = pos
	n.z_index = 70
	var l := Label.new()
	l.text = text
	l.position = Vector2(-60, -20)
	l.size = Vector2(120, 40)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UiTheme.FONT_BOLD)
	l.add_theme_font_size_override("font_size", 40)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 10)
	n.add_child(l)
	n.ready.connect(func():
		var tw := n.create_tween().set_parallel()
		tw.tween_property(n, "position:y", pos.y - 90, 1.0).set_ease(Tween.EASE_OUT)
		tw.tween_property(n, "modulate:a", 0.0, 1.0).set_delay(0.4)
		tw.chain().tween_callback(n.queue_free))
	return n


class _Ring extends Node2D:
	var radius := 120.0
	var color := Color.ORANGE
	var t := 0.0
	func _process(delta: float) -> void:
		t += delta
		queue_redraw()
		if t > 0.5:
			queue_free()
	func _draw() -> void:
		var k := t / 0.5
		draw_circle(Vector2.ZERO, radius * k, Color(color.r, color.g, color.b, 0.45 * (1.0 - k)))
		draw_arc(Vector2.ZERO, radius * k, 0, TAU, 48, Color(1, 0.95, 0.6, 1.0 - k), 6.0)
