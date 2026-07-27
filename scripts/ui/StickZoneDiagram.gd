class_name StickZoneDiagram
extends Control

@export var is_flick_stick: bool = false

var title_lbl: Label
var status_lbl: Label
var active_vector: Vector2 = Vector2.ZERO
var flick_is_left_foot: bool = true
var is_nollie_or_fakie_pop: bool = false

func _ready() -> void:
	title_lbl = Label.new()
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	title_lbl.add_theme_font_size_override("font_size", 11)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4, 1.0) if not is_flick_stick else Color(0.4, 0.95, 0.6, 1.0))
	title_lbl.text = "POP & SCOOP ZONE" if not is_flick_stick else "FLICK & FLIP ZONE"
	add_child(title_lbl)
	
	status_lbl = Label.new()
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	status_lbl.add_theme_font_size_override("font_size", 11)
	status_lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 1.0))
	status_lbl.text = "Pop (Trailing Foot)" if not is_flick_stick else "Flick (Leading Foot)"
	add_child(status_lbl)
	
	_update_label_positions()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_instance_valid(title_lbl):
		_update_label_positions()

func _update_label_positions() -> void:
	if is_instance_valid(title_lbl):
		title_lbl.size = Vector2(size.x, 18)
		title_lbl.position = Vector2(0, 0)
	if is_instance_valid(status_lbl):
		status_lbl.size = Vector2(size.x, 18)
		status_lbl.position = Vector2(0, size.y - 18)

func update_telemetry(rider: RiderInput, trick: TrickState) -> void:
	if rider == null or trick == null:
		return
	var left_is_front: bool = rider.leading_foot == RiderInput.Foot.LEFT
	is_nollie_or_fakie_pop = trick.last_pop == TrickSignature.Pop.NOLLIE or trick.last_pop == TrickSignature.Pop.FAKIE_OLLIE
	
	if is_flick_stick:
		# In Nollie/Fakie Ollie, trailing foot flicks; otherwise leading foot flicks
		if is_nollie_or_fakie_pop:
			active_vector = rider.back_stick()
			flick_is_left_foot = not left_is_front
			status_lbl.text = "Flick (%s)" % RiderInput.foot_name(rider.trailing_foot)
		else:
			active_vector = rider.front_stick()
			flick_is_left_foot = left_is_front
			status_lbl.text = "Flick (%s)" % RiderInput.foot_name(rider.leading_foot)
	else:
		# Pop stick is trailing foot during normal pop, or leading foot during Nollie pop
		if trick.current_pop_state == TrickState.PopState.LOADING_NOLLIE or is_nollie_or_fakie_pop:
			active_vector = rider.front_stick()
			status_lbl.text = "Pop (%s)" % RiderInput.foot_name(rider.leading_foot)
		else:
			active_vector = rider.back_stick()
			status_lbl.text = "Pop (%s)" % RiderInput.foot_name(rider.trailing_foot)
			
	queue_redraw()

func _draw() -> void:
	var center: Vector2 = Vector2(size.x * 0.5, size.y * 0.5)
	var radius: float = minf(size.x - 10.0, size.y - 34.0) * 0.5
	
	# Draw dark background gauge disk
	draw_circle(center, radius + 4.0, Color(0.04, 0.07, 0.1, 0.85))
	draw_arc(center, radius + 4.0, 0.0, PI * 2.0, 32, Color(0.3, 0.5, 0.7, 0.5), 1.5, true)
	
	if not is_flick_stick:
		_draw_pop_zones(center, radius)
	else:
		_draw_flick_zones(center, radius)
		
	# Draw crosshair axes
	draw_line(center - Vector2(radius, 0), center + Vector2(radius, 0), Color(1, 1, 1, 0.15), 1.0)
	draw_line(center - Vector2(0, radius), center + Vector2(0, radius), Color(1, 1, 1, 0.15), 1.0)
	
	# Draw live thumbstick indicator dot and vector line
	var thumb_pos: Vector2 = center + active_vector * radius
	if active_vector.length() > 0.05:
		var line_col: Color = Color(1.0, 0.85, 0.3, 0.8) if not is_flick_stick else Color(0.3, 0.95, 0.6, 0.8)
		draw_line(center, thumb_pos, line_col, 2.0, true)
		draw_circle(thumb_pos, 7.0, line_col)
	draw_circle(thumb_pos, 4.0, Color.WHITE)

func _draw_pop_zones(center: Vector2, r: float) -> void:
	# Ollie Pop Zone (bottom 80 deg arc around 90° / 6 o'clock)
	_draw_pie_sector(center, 0.0, r, deg_to_rad(50.0), deg_to_rad(130.0), Color(1.0, 0.8, 0.2, 0.35), Color(1.0, 0.8, 0.2, 0.9))
	# Nollie Pop Zone (top 80 deg arc around 270° / 12 o'clock)
	_draw_pie_sector(center, 0.0, r, deg_to_rad(230.0), deg_to_rad(310.0), Color(1.0, 0.8, 0.2, 0.35), Color(1.0, 0.8, 0.2, 0.9))
	
	# 180° Shuv Scoop Arcs (Standard scoop window: 40° to 94° from pop axis)
	# Bottom Right / Right side
	_draw_pie_sector(center, 0.0, r, deg_to_rad(4.0), deg_to_rad(50.0), Color(0.2, 0.8, 1.0, 0.35), Color(0.2, 0.8, 1.0, 0.9))
	# Bottom Left / Left side
	_draw_pie_sector(center, 0.0, r, deg_to_rad(130.0), deg_to_rad(176.0), Color(0.2, 0.8, 1.0, 0.35), Color(0.2, 0.8, 1.0, 0.9))
	
	# 360° Shuv Deep Scoop Arcs (Deep scoop >= 95° from pop axis, upper side hemispheres)
	_draw_pie_sector(center, 0.0, r, deg_to_rad(176.0), deg_to_rad(230.0), Color(0.8, 0.3, 0.9, 0.35), Color(0.8, 0.3, 0.9, 0.9))
	_draw_pie_sector(center, 0.0, r, deg_to_rad(310.0), deg_to_rad(364.0), Color(0.8, 0.3, 0.9, 0.35), Color(0.8, 0.3, 0.9, 0.9))

func _draw_flick_zones(center: Vector2, r: float) -> void:
	# Kickflip = outward (-X for Left foot, +X for Right foot); Heelflip = inward (+X for Left, -X for Right)
	var kick_col: Color = Color(0.2, 0.9, 0.4, 0.35) # Neon Green
	var kick_line: Color = Color(0.2, 0.9, 0.4, 0.9)
	var heel_col: Color = Color(1.0, 0.5, 0.2, 0.35) # Neon Orange
	var heel_line: Color = Color(1.0, 0.5, 0.2, 0.9)
	
	var left_side_is_kick: bool = flick_is_left_foot
	var left_col: Color = kick_col if left_side_is_kick else heel_col
	var left_line: Color = kick_line if left_side_is_kick else heel_line
	var right_col: Color = heel_col if left_side_is_kick else kick_col
	var right_line: Color = heel_line if left_side_is_kick else kick_line
	
	# Left Side Wedge (-X): from 135° (45° down) to 240° (60° up)
	_draw_pie_sector(center, 0.0, r, deg_to_rad(135.0), deg_to_rad(240.0), left_col, left_line)
	# Right Side Wedge (+X): from -60° (300°, 60° up) to +45° (45° down)
	_draw_pie_sector(center, 0.0, r, deg_to_rad(-60.0), deg_to_rad(45.0), right_col, right_line)
	
	# Ollie / Level Forgiveness Wedge (Top 60° around 12 o'clock, between 240° and 300°)
	_draw_pie_sector(center, 0.0, r, deg_to_rad(240.0), deg_to_rad(300.0), Color(0.3, 0.6, 0.9, 0.35), Color(0.3, 0.6, 0.9, 0.9))
	# Scoop Buffer / Deadzone Wedge (Bottom 90° around 6 o'clock, between 45° and 135°)
	_draw_pie_sector(center, 0.0, r, deg_to_rad(45.0), deg_to_rad(135.0), Color(0.25, 0.25, 0.3, 0.25), Color(0.4, 0.4, 0.5, 0.4))

func _draw_pie_sector(center: Vector2, inner_r: float, outer_r: float, start_a: float, end_a: float, fill_col: Color, border_col: Color, segments: int = 16) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	var step: float = (end_a - start_a) / float(segments)
	
	for i in range(segments + 1):
		var angle: float = start_a + step * float(i)
		pts.append(center + Vector2(cos(angle), sin(angle)) * outer_r)
		
	if inner_r > 0.0:
		for i in range(segments, -1, -1):
			var angle: float = start_a + step * float(i)
			pts.append(center + Vector2(cos(angle), sin(angle)) * inner_r)
	else:
		pts.append(center)
		
	if pts.size() >= 3:
		draw_polygon(pts, [fill_col])
		
	if border_col.a > 0.0 and outer_r > 0.0:
		draw_arc(center, outer_r, start_a, end_a, segments, border_col, 2.0, true)
