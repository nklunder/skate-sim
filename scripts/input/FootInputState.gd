class_name FootInputState
extends Node

enum Stance { REGULAR, GOOFY }
enum PopState { NONE, LOADING_OLLIE, LOADING_NOLLIE, POPPED }

@export var stance: Stance = Stance.REGULAR
@export var board_config: SkateBoardConfig

# Live Input Values
var left_stick_raw: Vector2 = Vector2.ZERO
var right_stick_raw: Vector2 = Vector2.ZERO
var left_mag: float = 0.0
var left_angle: float = 0.0 # Radians via atan2(x, -y)
var right_mag: float = 0.0
var right_angle: float = 0.0
var lean: float = 0.0 # RT - LT

# Push Detection & Stroke Classification
var push_left_triggered: bool = false
var push_right_triggered: bool = false
var _prev_push_left: bool = false
var _prev_push_right: bool = false
var last_push_type: String = "None"

# Trick & Combo State Tracking
var current_pop_state: PopState = PopState.NONE
var trick_status_string: String = "Grounded"
var pop_impulse_triggered: bool = false
var last_pop_type: String = "None"
var active_flip_type: String = "None"
var active_spin_type: String = "None"
var last_combo_string: String = "None"
var _prev_space_pressed: bool = false

# Live Facts
var leading_foot: String = "Left Foot"
var trailing_foot: String = "Right Foot"
var left_foot_over: String = "Nose"
var right_foot_over: String = "Tail"
var current_velocity: Vector3 = Vector3.ZERO

func _process(_delta: float) -> void:
	_poll_inputs()
	_update_polar_decomposition()
	_classify_push_strokes()
	_detect_pop_load_and_flick()

func _poll_inputs() -> void:
	# Joypad input + keyboard fallback (WASD for Left Foot, IJKL for Right Foot)
	var lx: float = Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var ly: float = Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	if abs(lx) < 0.1 and abs(ly) < 0.1:
		lx = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		ly = float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
		if abs(lx) < 0.1 and abs(ly) < 0.1:
			lx = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left") if not Input.is_physical_key_pressed(KEY_L) and not Input.is_physical_key_pressed(KEY_J) else 0.0
			ly = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up") if not Input.is_physical_key_pressed(KEY_K) and not Input.is_physical_key_pressed(KEY_I) else 0.0
	
	# Apply outer-rim deadzone clamping to eliminate sensor fluctuations at full deflection
	left_stick_raw = Vector2(lx, ly).limit_length(1.0)
	if left_stick_raw.length() > 0.95:
		left_stick_raw = left_stick_raw.normalized()
	
	var rx: float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ry: float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if abs(rx) < 0.1 and abs(ry) < 0.1:
		rx = float(Input.is_physical_key_pressed(KEY_L)) - float(Input.is_physical_key_pressed(KEY_J))
		ry = float(Input.is_physical_key_pressed(KEY_K)) - float(Input.is_physical_key_pressed(KEY_I))
		
	right_stick_raw = Vector2(rx, ry).limit_length(1.0)
	if right_stick_raw.length() > 0.95:
		right_stick_raw = right_stick_raw.normalized()
	
	var lt: float = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	var rt: float = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)
	if lt < 0.05 and rt < 0.05:
		lt = float(Input.is_physical_key_pressed(KEY_Q))
		rt = float(Input.is_physical_key_pressed(KEY_E))
	lean = rt - lt
	
	# Push Button polling (Joypad X/Square for Left Foot, A/Cross for Right Foot; V / B for keyboard)
	var curr_push_left: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_X) or Input.is_physical_key_pressed(KEY_V)
	var curr_push_right: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_A) or Input.is_physical_key_pressed(KEY_B)
	
	push_left_triggered = curr_push_left and not _prev_push_left
	push_right_triggered = curr_push_right and not _prev_push_right
	_prev_push_left = curr_push_left
	_prev_push_right = curr_push_right
	
	# Spacebar fallback for keyboard jumping with Z (Kickflip) / X (Heelflip) / C (Shove-it)
	var curr_space: bool = Input.is_physical_key_pressed(KEY_SPACE)
	if curr_space and not _prev_space_pressed and current_pop_state != PopState.POPPED:
		pop_impulse_triggered = true
		current_pop_state = PopState.POPPED
		last_pop_type = "Ollie"
		_evaluate_flip_combo()
	_prev_space_pressed = curr_space

func _detect_pop_load_and_flick() -> void:
	if current_pop_state == PopState.POPPED:
		return # Wait for SkaterController touchdown to reset state
		
	if stance == Stance.REGULAR:
		# Ollie Load (Back foot / Right stick fully pulled down > 0.90 to match expanded manual zone)
		if right_stick_raw.y > 0.90:
			current_pop_state = PopState.LOADING_OLLIE
			trick_status_string = "Loading Ollie (Tail)"
		# Nollie Load (Front foot / Left stick pushed fully forward < -0.90)
		elif left_stick_raw.y < -0.90:
			current_pop_state = PopState.LOADING_NOLLIE
			trick_status_string = "Loading Nollie (Nose)"
		
		# Execute Flick Pop from loaded states (allows vertical up or sideways -90°/+90° flicks)
		if current_pop_state == PopState.LOADING_OLLIE and left_stick_raw.length() >= 0.35 and left_stick_raw.y <= 0.20:
			pop_impulse_triggered = true
			current_pop_state = PopState.POPPED
			last_pop_type = "Ollie"
			_evaluate_flip_combo()
		elif current_pop_state == PopState.LOADING_NOLLIE and right_stick_raw.length() >= 0.35 and right_stick_raw.y >= -0.20:
			pop_impulse_triggered = true
			current_pop_state = PopState.POPPED
			last_pop_type = "Nollie"
			_evaluate_flip_combo()
		
		# Reset to None if sticks return to neutral without flicking
		if right_stick_raw.length() < 0.20 and left_stick_raw.length() < 0.20 and current_pop_state != PopState.NONE:
			current_pop_state = PopState.NONE
			trick_status_string = "Grounded & Rolling"
	else: # GOOFY stance
		if left_stick_raw.y > 0.90:
			current_pop_state = PopState.LOADING_OLLIE
			trick_status_string = "Loading Ollie (Tail)"
		elif right_stick_raw.y < -0.90:
			current_pop_state = PopState.LOADING_NOLLIE
			trick_status_string = "Loading Nollie (Nose)"
			
		if current_pop_state == PopState.LOADING_OLLIE and right_stick_raw.length() >= 0.35 and right_stick_raw.y <= 0.20:
			pop_impulse_triggered = true
			current_pop_state = PopState.POPPED
			last_pop_type = "Ollie"
			_evaluate_flip_combo()
		elif current_pop_state == PopState.LOADING_NOLLIE and left_stick_raw.length() >= 0.35 and left_stick_raw.y >= -0.20:
			pop_impulse_triggered = true
			current_pop_state = PopState.POPPED
			last_pop_type = "Nollie"
			_evaluate_flip_combo()
			
		if right_stick_raw.length() < 0.20 and left_stick_raw.length() < 0.20 and current_pop_state != PopState.NONE:
			current_pop_state = PopState.NONE
			trick_status_string = "Grounded & Rolling"

func _evaluate_flip_combo() -> void:
	active_flip_type = "None"
	active_spin_type = "None"
	
	# Evaluate 90-degree side flick quadrant (45° above and below horizontal axis: abs(y) <= abs(x))
	var flick_vec: Vector2 = left_stick_raw if stance == Stance.REGULAR else right_stick_raw
	var sweep_vec: Vector2 = right_stick_raw if stance == Stance.REGULAR else left_stick_raw
	
	if flick_vec.length() >= 0.25 and abs(flick_vec.y) <= abs(flick_vec.x):
		if flick_vec.x < 0.0:
			active_flip_type = "Kickflip"
		else:
			active_flip_type = "Heelflip"
	elif Input.is_physical_key_pressed(KEY_Z) or Input.is_physical_key_pressed(KEY_F):
		active_flip_type = "Kickflip"
	elif Input.is_physical_key_pressed(KEY_X) or Input.is_physical_key_pressed(KEY_G):
		active_flip_type = "Heelflip"
		
	if (sweep_vec.length() >= 0.25 and abs(sweep_vec.y) <= abs(sweep_vec.x)) or Input.is_physical_key_pressed(KEY_C) or Input.is_physical_key_pressed(KEY_H):
		active_spin_type = "Pop Shove-it"
		
	# Construct combo trick description
	if active_spin_type != "None" and active_flip_type != "None":
		last_combo_string = "Varial " + active_flip_type
	elif active_flip_type != "None":
		last_combo_string = (last_pop_type + " " + active_flip_type).strip_edges() if last_pop_type != "Ollie" else active_flip_type
	elif active_spin_type != "None":
		last_combo_string = (last_pop_type + " " + active_spin_type).strip_edges() if last_pop_type != "Ollie" else active_spin_type
	else:
		last_combo_string = last_pop_type
		
	trick_status_string = "Airborne: %s!" % last_combo_string

func _update_polar_decomposition() -> void:
	left_mag = left_stick_raw.length()
	if left_mag > 0.05:
		left_angle = atan2(left_stick_raw.x, -left_stick_raw.y)
	else:
		left_angle = 0.0
	
	right_mag = right_stick_raw.length()
	if right_mag > 0.05:
		right_angle = atan2(right_stick_raw.x, -right_stick_raw.y)
	else:
		right_angle = 0.0

func _classify_push_strokes() -> void:
	if push_left_triggered:
		if leading_foot.begins_with("Left"):
			last_push_type = "Mongo Push (Leading)"
		else:
			last_push_type = "Standard Push (Trailing)"
	elif push_right_triggered:
		if leading_foot.begins_with("Right"):
			last_push_type = "Mongo Push (Leading)"
		else:
			last_push_type = "Standard Push (Trailing)"

func update_stance_facts(pivot: Node3D, left_foot: Node3D, right_foot: Node3D, vel: Vector3) -> void:
	current_velocity = vel
	var nose_pos: Vector3 = pivot.to_global(Vector3(0, 0, -0.35))
	
	# Live Mesh-Under-Foot check via distance to Nose
	if left_foot.global_position.distance_squared_to(nose_pos) < right_foot.global_position.distance_squared_to(nose_pos):
		left_foot_over = "Nose"
		right_foot_over = "Tail"
	else:
		left_foot_over = "Tail"
		right_foot_over = "Nose"
	
	# Live Trailing / Leading Foot check via velocity dot product
	if vel.length_squared() > 0.05:
		var travel_dir: Vector3 = vel.normalized()
		var left_dot: float = (left_foot.global_position - pivot.global_position).dot(travel_dir)
		var right_dot: float = (right_foot.global_position - pivot.global_position).dot(travel_dir)
		if left_dot > right_dot:
			leading_foot = "Left Foot"
			trailing_foot = "Right Foot"
		else:
			leading_foot = "Right Foot"
			trailing_foot = "Left Foot"
	else:
		if stance == Stance.REGULAR:
			leading_foot = "Left Foot"
			trailing_foot = "Right Foot"
		else:
			leading_foot = "Right Foot"
			trailing_foot = "Left Foot"
