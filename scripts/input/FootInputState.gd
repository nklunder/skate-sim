class_name FootInputState
extends Node

enum Stance { REGULAR, GOOFY }
enum PopState { NONE, LOADING_OLLIE, LOADING_NOLLIE, POPPED }

@export var stance: Stance = Stance.REGULAR
@export var board_config: SkateBoardConfig

@export_category("Shove-it Scoop Thresholds")
@export var shuv_180_threshold_deg: float = 40.0 # Standard scoop buffer window (40° to 94°)
@export var shuv_360_threshold_deg: float = 95.0 # Deep scoop buffer window (>= 95°)

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
var last_scoop_sign: float = -1.0
var initial_scoop_angle: float = 0.0
var max_swept_angle: float = 0.0
var accumulated_scoop_deg: float = 0.0
var _last_frame_scoop_angle: float = 0.0
var last_combo_string: String = "None"
var _prev_space_pressed: bool = false

# Live Facts
var leading_foot: String = "Left Foot"
var trailing_foot: String = "Right Foot"
var left_foot_over: String = "Nose"
var right_foot_over: String = "Tail"
var current_velocity: Vector3 = Vector3.ZERO

func _physics_process(_delta: float) -> void:
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
	var raw_lean: float = rt - lt
	# Apply audio-log power curve (exponent 2.2) to desensitize light-to-mid trigger pulls while preserving full speed at 1.0
	lean = signf(raw_lean) * pow(absf(raw_lean), 2.2)
	
	# Push Button polling (Joypad X/Square for Left Foot, A/Cross for Right Foot; V / B for keyboard)
	var curr_push_left: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_X) or Input.is_physical_key_pressed(KEY_V)
	var curr_push_right: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_A) or Input.is_physical_key_pressed(KEY_B)
	
	# Latch push triggers so button presses aren't dropped before SkaterController evaluation
	if curr_push_left and not _prev_push_left:
		push_left_triggered = true
	if curr_push_right and not _prev_push_right:
		push_right_triggered = true
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
		
	# Determine leading (front) and trailing (back) sticks dynamically based on live travel stance
	var left_is_front: bool = leading_foot.begins_with("Left")
	var front_stick: Vector2 = left_stick_raw if left_is_front else right_stick_raw
	var back_stick: Vector2 = right_stick_raw if left_is_front else left_stick_raw
	
	# Ollie / Switch Ollie Load (Trailing back foot pulled down in lower hemisphere)
	if current_pop_state == PopState.NONE:
		if back_stick.length() >= 0.70 and back_stick.y >= 0.50:
			current_pop_state = PopState.LOADING_OLLIE
			trick_status_string = "Loading Ollie (Tail)"
			initial_scoop_angle = rad_to_deg(back_stick.angle())
			_last_frame_scoop_angle = initial_scoop_angle
			accumulated_scoop_deg = 0.0
			max_swept_angle = 0.0
		# Nollie / Switch Nollie Load (Leading front foot pushed up in upper hemisphere)
		elif front_stick.length() >= 0.70 and front_stick.y <= -0.50:
			current_pop_state = PopState.LOADING_NOLLIE
			trick_status_string = "Loading Nollie (Nose)"
			initial_scoop_angle = rad_to_deg(front_stick.angle())
			_last_frame_scoop_angle = initial_scoop_angle
			accumulated_scoop_deg = 0.0
			max_swept_angle = 0.0
			
	# Measure total angular sweep (arc span) and true rotational direction via frame delta accumulation to prevent circle-wrap bugs
	if current_pop_state != PopState.NONE:
		var active_scoop: Vector2 = back_stick if current_pop_state == PopState.LOADING_OLLIE else front_stick
		if active_scoop.length() >= 0.30:
			var curr_deg: float = rad_to_deg(active_scoop.angle())
			var frame_delta: float = rad_to_deg(angle_difference(deg_to_rad(_last_frame_scoop_angle), deg_to_rad(curr_deg)))
			_last_frame_scoop_angle = curr_deg
			accumulated_scoop_deg += frame_delta
			var swept: float = absf(accumulated_scoop_deg)
			if swept > max_swept_angle:
				max_swept_angle = swept
				if swept >= 15.0:
					last_scoop_sign = -1.0 if accumulated_scoop_deg > 0.0 else 1.0
	
	# Execute Flick Pop from loaded states
	if current_pop_state == PopState.LOADING_OLLIE and front_stick.length() >= 0.35 and front_stick.y <= 0.20:
		pop_impulse_triggered = true
		current_pop_state = PopState.POPPED
		# Differentiate Switch vs Regular Ollie based on profile stance vs live orientation
		if (stance == Stance.REGULAR and not left_is_front) or (stance == Stance.GOOFY and left_is_front):
			last_pop_type = "Switch Ollie"
		else:
			last_pop_type = "Ollie"
		_evaluate_flip_combo()
	elif current_pop_state == PopState.LOADING_NOLLIE and back_stick.length() >= 0.35 and back_stick.y >= -0.20:
		pop_impulse_triggered = true
		current_pop_state = PopState.POPPED
		if (stance == Stance.REGULAR and not left_is_front) or (stance == Stance.GOOFY and left_is_front):
			last_pop_type = "Fakie Ollie"
		else:
			last_pop_type = "Nollie"
		_evaluate_flip_combo()
	
	# Reset to None if sticks return to neutral without flicking
	if right_stick_raw.length() < 0.20 and left_stick_raw.length() < 0.20 and current_pop_state != PopState.NONE:
		current_pop_state = PopState.NONE
		max_swept_angle = 0.0
		trick_status_string = "Grounded & Rolling"

func _evaluate_flip_combo() -> void:
	active_flip_type = "None"
	active_spin_type = "None"
	
	var left_is_front: bool = leading_foot.begins_with("Left")
	var flick_stick: Vector2
	var scoop_stick: Vector2
	var flick_is_left_foot: bool
	
	if last_pop_type.contains("Nollie") or last_pop_type.contains("Fakie"):
		# In a Nollie or Fakie Ollie pop, the TRAILING foot is the flicking foot
		flick_stick = right_stick_raw if left_is_front else left_stick_raw
		scoop_stick = left_stick_raw if left_is_front else right_stick_raw
		flick_is_left_foot = not left_is_front
	else:
		# In an Ollie pop, the LEADING foot is the flicking foot
		flick_stick = left_stick_raw if left_is_front else right_stick_raw
		scoop_stick = right_stick_raw if left_is_front else left_stick_raw
		flick_is_left_foot = left_is_front
	
	# Universal Flick Rule: Flicking outward (-X for Left, +X for Right = behind body) = Kickflip; Inward (+X for Left, -X for Right = in front of body) = Heelflip
	if flick_stick.length() >= 0.25 and abs(flick_stick.y) <= abs(flick_stick.x):
		if flick_is_left_foot:
			active_flip_type = "Kickflip" if flick_stick.x < 0.0 else "Heelflip"
		else:
			active_flip_type = "Kickflip" if flick_stick.x > 0.0 else "Heelflip"
	elif Input.is_physical_key_pressed(KEY_Z) or Input.is_physical_key_pressed(KEY_F):
		active_flip_type = "Kickflip"
	elif Input.is_physical_key_pressed(KEY_X) or Input.is_physical_key_pressed(KEY_G):
		active_flip_type = "Heelflip"
		
	# In Fakie stance, reverse the text label classification while preserving existing physical control-to-rotation behavior
	if last_pop_type.contains("Fakie") and active_flip_type != "None":
		active_flip_type = "Heelflip" if active_flip_type == "Kickflip" else "Kickflip"
		
	var is_360_shuv: bool = (max_swept_angle >= shuv_360_threshold_deg or Input.is_physical_key_pressed(KEY_H))
	if is_360_shuv or (max_swept_angle >= shuv_180_threshold_deg or Input.is_physical_key_pressed(KEY_C)):
		var scoop_is_left_foot: bool = not flick_is_left_foot
		var is_frontside: bool = false
		if not Input.is_physical_key_pressed(KEY_C) and not Input.is_physical_key_pressed(KEY_H):
			if scoop_is_left_foot:
				is_frontside = (last_scoop_sign < 0.0)
			else:
				is_frontside = (last_scoop_sign > 0.0)
		else:
			last_scoop_sign = -1.0
			
		if is_360_shuv:
			active_spin_type = "360 FS Pop Shove-it" if is_frontside else "360 Pop Shove-it"
		else:
			active_spin_type = "FS Pop Shove-it" if is_frontside else "Pop Shove-it"
		
	# Construct combo trick description with authentic 360 Flip / Laser Flip nomenclature
	var combo_prefix: String = "Fakie" if last_pop_type == "Fakie Ollie" else last_pop_type
	var body: String = ""
	if active_spin_type.begins_with("360"):
		var is_fs_360: bool = active_spin_type.contains("FS")
		if active_flip_type == "Kickflip":
			body = "360 FS Flip" if is_fs_360 else "360 Flip"
		elif active_flip_type == "Heelflip":
			body = "Laser Flip" if is_fs_360 else "360 Heelflip"
		else:
			body = active_spin_type
	elif active_spin_type != "None" and active_flip_type != "None":
		var spin_word: String = "FS Varial" if active_spin_type.begins_with("FS") else "Varial"
		body = spin_word + " " + active_flip_type
	elif active_flip_type != "None":
		body = active_flip_type
	elif active_spin_type != "None":
		body = active_spin_type
	else:
		body = ""
		
	if body != "":
		last_combo_string = (combo_prefix + " " + body).strip_edges() if last_pop_type != "Ollie" else body
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
	
	# Live Trailing / Leading Foot check via velocity or static forward alignment
	var travel_dir: Vector3 = vel.normalized() if vel.length_squared() > 0.05 else -pivot.get_parent().global_transform.basis.z
	var left_dot: float = (left_foot.global_position - pivot.global_position).dot(travel_dir)
	var right_dot: float = (right_foot.global_position - pivot.global_position).dot(travel_dir)
	if left_dot > right_dot:
		leading_foot = "Left Foot"
		trailing_foot = "Right Foot"
	else:
		leading_foot = "Right Foot"
		trailing_foot = "Left Foot"
