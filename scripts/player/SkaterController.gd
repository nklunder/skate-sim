class_name SkaterController
extends Node3D

@export_category("Manual & Pitch Tolerances")
@export var manual_entry_delay: float = 0.08
@export var max_landing_tolerance_deg: float = 15.0
var manual_timer: float = 0.0
var is_grounded: bool = true

@export_category("Aerial & Jump Physics")
@export var jump_impulse: float = 5.2
@export var gravity_accel: float = 16.0
var vertical_velocity: float = 0.0

@export_category("Flip & Spin Physics (3-Layer Hierarchy)")
@export var flip_speed_deg: float = 760.0
@export var spin_speed_deg: float = 540.0
@export var body_spin_speed_deg: float = 554.0
var target_board_roll: float = 0.0
var target_board_yaw: float = 0.0
var current_aerial_spin_rate: float = 0.0
var is_flip_in_progress: bool = false

@onready var input_state: FootInputState = $FootInputState
@onready var board_pivot: Node3D = $BoardPivot
@onready var board_mesh: Node3D = $BoardPivot/BoardMesh
@onready var left_foot: MeshInstance3D = $BoardPivot/LeftFoot
@onready var right_foot: MeshInstance3D = $BoardPivot/RightFoot
@onready var left_peg_pivot: Node3D = $BoardPivot/LeftFoot/PegPivot
@onready var right_peg_pivot: Node3D = $BoardPivot/RightFoot/PegPivot

# Truck contact raycasts
@onready var ray_fl: RayCast3D = $BoardPivot/RayCastFL
@onready var ray_fr: RayCast3D = $BoardPivot/RayCastFR
@onready var ray_bl: RayCast3D = $BoardPivot/RayCastBL
@onready var ray_br: RayCast3D = $BoardPivot/RayCastBR

# Motion & Push Physics
var velocity: Vector3 = Vector3.ZERO
var current_speed: float = 0.0
var max_push_speed: float = 7.0
var push_impulse: float = 2.5
var rolling_friction: float = 1.25

# Foot Push Animation State (Elevated to Y = 0.055 to prevent board collisions)
var left_foot_rest: Vector3 = Vector3(0, 0.055, -0.25)
var right_foot_rest: Vector3 = Vector3(0, 0.055, 0.25)
var active_push_foot: String = ""
var push_anim_time: float = 0.0
var push_anim_duration: float = 0.25

func _physics_process(delta: float) -> void:
	# 1. Grounded vs Airborne evaluation
	if vertical_velocity > 0.05 or global_position.y > 0.27:
		is_grounded = false
	else:
		var ray_colliding: bool = ray_fl.is_colliding() or ray_fr.is_colliding() or ray_bl.is_colliding() or ray_br.is_colliding()
		is_grounded = ray_colliding or (global_position.y <= 0.45)
	
	# Synchronize all kinematic animations and stance updates to physics tick
	_animate_ankle_pegs(delta)
	_animate_foot_push_stroke(delta)
	input_state.update_stance_facts(board_pivot, left_foot, right_foot, velocity)
	
	# 2. Push Acceleration Impulses via Face Buttons (latched inputs ensure zero missed taps)
	if input_state.push_left_triggered or input_state.push_right_triggered:
		if is_grounded:
			current_speed = minf(current_speed + push_impulse, max_push_speed)
			if input_state.push_left_triggered:
				_start_foot_push("left")
			else:
				_start_foot_push("right")
			input_state.push_left_triggered = false
			input_state.push_right_triggered = false
		elif vertical_velocity > 0.5 or global_position.y > 0.60:
			# Clear stale latched presses if high in the air to prevent unintended touchdown bursts
			input_state.push_left_triggered = false
			input_state.push_right_triggered = false
	
	# 3. Rolling Resistance / Deceleration when rolling on pavement
	if is_grounded:
		current_speed = maxf(0.0, current_speed - rolling_friction * delta)
	
	# 4. Steering & Stationary Rotation via Trigger Lean (RT - LT) on pavement
	# Dampen steering by 80% while preparing pop to safely pre-wind aerial spin without swerving off line!
	var turn_mult: float = 0.2 if input_state.current_pop_state != FootInputState.PopState.NONE else 1.0
	var turn_rate: float = input_state.lean * (input_state.board_config.turn_speed if is_instance_valid(input_state.board_config) else 3.0) * turn_mult
	if is_grounded and abs(input_state.lean) > 0.05:
		rotate_y(-turn_rate * delta)
	
	# 5. Execute Vertical Pop Impulse & Setup 3-Layer Trick Rotations
	if is_grounded and input_state.pop_impulse_triggered:
		vertical_velocity = jump_impulse
		is_grounded = false
		input_state.pop_impulse_triggered = false
		
		# Initial kicktail pitch angle upon popping
		if input_state.last_pop_type.contains("Nollie") or input_state.last_pop_type.contains("Fakie"):
			board_pivot.rotation_degrees.x = -22.0 # Leading nose pop
		else:
			board_pivot.rotation_degrees.x = 22.0 # Trailing tail pop
			
		# Configure BoardMesh flip & spin targets (Layer 3) with reverse roll direction for Nollie/Fakie flips!
		var roll_sign: float = -1.0 if (input_state.last_pop_type.contains("Nollie") or input_state.last_pop_type.contains("Fakie")) else 1.0
		if input_state.active_flip_type == "Kickflip":
			target_board_roll = board_mesh.rotation_degrees.z + (360.0 * roll_sign)
			is_flip_in_progress = true
		elif input_state.active_flip_type == "Heelflip":
			target_board_roll = board_mesh.rotation_degrees.z - (360.0 * roll_sign)
			is_flip_in_progress = true
		else:
			target_board_roll = board_mesh.rotation_degrees.z
			
		if input_state.active_spin_type != "None":
			var spin_sign: float = -input_state.last_scoop_sign if (input_state.last_pop_type.contains("Nollie") or input_state.last_pop_type.contains("Fakie")) else input_state.last_scoop_sign
			target_board_yaw = board_mesh.rotation_degrees.y + (180.0 * spin_sign)
			is_flip_in_progress = true
		else:
			target_board_yaw = board_mesh.rotation_degrees.y
	
	# 6. Apply Custom Gravity, Aerial Pitch Control, 3-Layer Flight Physics & Touchdown
	if not is_grounded:
		vertical_velocity -= gravity_accel * delta
		global_position.y += vertical_velocity * delta
		
		# Layer 1: Aerial Body & Deck Spin Authority (FS/BS 180s/360s via triggers with fluid momentum smoothing)
		# Applied to board_pivot.y so rolling travel vector and chase camera stay fixed behind the skater!
		var target_spin: float = input_state.lean * body_spin_speed_deg
		current_aerial_spin_rate = lerpf(current_aerial_spin_rate, target_spin, 20.0 * delta)
		if abs(current_aerial_spin_rate) > 0.1:
			board_pivot.rotation_degrees.y -= current_aerial_spin_rate * delta
		
		# Layer 2: Mid-Air Pitch Control (0.20 to 1.00 thumbsticks to angle nose/tail in air)
		_apply_airborne_board_pitch(delta)
		
		# Layer 3: Deck Flip & Spin Authority on BoardMesh with Shoe Hover Catching
		if is_flip_in_progress:
			board_mesh.rotation_degrees.z = move_toward(board_mesh.rotation_degrees.z, target_board_roll, flip_speed_deg * delta)
			board_mesh.rotation_degrees.y = move_toward(board_mesh.rotation_degrees.y, target_board_yaw, spin_speed_deg * delta)
			
			# Elevate shoe boxes slightly above spinning deck (Y = 0.18m)
			left_foot.position.y = lerpf(left_foot.position.y, 0.18, 16.0 * delta)
			right_foot.position.y = lerpf(right_foot.position.y, 0.18, 16.0 * delta)
			
			# Catch trick cleanly when deck revolution completes (grip tape facing up)
			if is_equal_approx(board_mesh.rotation_degrees.z, target_board_roll) and is_equal_approx(board_mesh.rotation_degrees.y, target_board_yaw):
				is_flip_in_progress = false
				board_mesh.rotation_degrees.z = fmod(board_mesh.rotation_degrees.z, 360.0)
				board_mesh.rotation_degrees.y = fmod(board_mesh.rotation_degrees.y, 360.0)
				input_state.trick_status_string = "Caught %s in mid-air!" % input_state.last_combo_string
		else:
			# Return shoe boxes to ride rest height when trick is caught or no flip active
			left_foot.position.y = lerpf(left_foot.position.y, left_foot_rest.y, 16.0 * delta)
			right_foot.position.y = lerpf(right_foot.position.y, right_foot_rest.y, 16.0 * delta)
		
		# Touchdown landing contact on ground layer (Y <= 0.25)
		if global_position.y <= 0.25 and vertical_velocity <= 0.0:
			global_position.y = 0.25
			vertical_velocity = 0.0
			is_grounded = true
			current_aerial_spin_rate = 0.0
			input_state.current_pop_state = FootInputState.PopState.NONE
			_evaluate_touchdown_landing()
	
	# 7. Horizontal Kinematic Motion Execution
	velocity = -global_transform.basis.z * current_speed
	global_position += velocity * delta
	
	# 8. Grounded Board Rotations & Middle-Zone Manuals (only when on pavement)
	if is_grounded:
		_apply_grounded_board_pitch(delta)

func _apply_airborne_board_pitch(delta: float) -> void:
	var target_pitch_deg: float = 0.0
	var left_is_front: bool = input_state.leading_foot.begins_with("Left")
	var front_stick: Vector2 = input_state.left_stick_raw if left_is_front else input_state.right_stick_raw
	var back_stick: Vector2 = input_state.right_stick_raw if left_is_front else input_state.left_stick_raw
	
	if back_stick.y > 0.15:
		target_pitch_deg = back_stick.y * 24.0 # Tail dip (trailing edge)
	elif front_stick.y < -0.15:
		target_pitch_deg = front_stick.y * 24.0 # Nose dip (leading edge)
	
	board_pivot.rotation_degrees.x = lerpf(board_pivot.rotation_degrees.x, target_pitch_deg, 14.0 * delta)

func _evaluate_touchdown_landing() -> void:
	# Primo / Incomplete Flip Check
	if is_flip_in_progress:
		input_state.trick_status_string = "BAIL! (Primo Crash / Incomplete Flip)"
		current_speed = 0.0
		board_mesh.rotation_degrees.z = 0.0
		board_mesh.rotation_degrees.y = 0.0
		is_flip_in_progress = false
		left_foot.position.y = left_foot_rest.y
		right_foot.position.y = right_foot_rest.y
		manual_timer = 0.0
		return
		
	# Snap touchdown yaw to nearest 180 orientation with ±45° precision landing window
	var curr_yaw: float = fmod(board_pivot.rotation_degrees.y, 360.0)
	if curr_yaw < 0.0:
		curr_yaw += 360.0
	
	# Sideways Landing Bail (perpendicular to momentum between 45° to 135° or 225° to 315°)
	if (curr_yaw >= 45.0 and curr_yaw <= 135.0) or (curr_yaw >= 225.0 and curr_yaw <= 315.0):
		input_state.trick_status_string = "BAIL! (Sideways Landing / Wheel Skid)"
		current_speed = 0.0 # Speed loss from sideways wheel friction
		board_pivot.rotation_degrees.x = 0.0
		board_pivot.rotation_degrees.y = 0.0 if (curr_yaw < 90.0 or curr_yaw > 270.0) else 180.0
		manual_timer = 0.0
		return
		
	if curr_yaw >= 135.0 and curr_yaw <= 225.0:
		board_pivot.rotation_degrees.y = 180.0 # Riding Switch / Fakie!
	else:
		board_pivot.rotation_degrees.y = 0.0 # Riding Regular Forward!

	var pitch: float = board_pivot.rotation_degrees.x
	var in_manual_zone: bool = false
	
	var left_is_front: bool = input_state.leading_foot.begins_with("Left")
	var front_stick: Vector2 = input_state.left_stick_raw if left_is_front else input_state.right_stick_raw
	var back_stick: Vector2 = input_state.right_stick_raw if left_is_front else input_state.left_stick_raw
	
	# Check if back or front stick is cleanly held within the expanded Manual Zone (0.20 to 0.90) upon touchdown
	if pitch > 5.0 and back_stick.y >= 0.20 and back_stick.y <= 0.90:
		in_manual_zone = true # Touchdown into standard / switch manual!
	elif pitch < -5.0 and front_stick.y <= -0.20 and front_stick.y >= -0.90:
		in_manual_zone = true # Touchdown into nose / switch nose manual!
	
	if in_manual_zone:
		# INSTANT MANUAL CATCH: bypass loading delay and continue rolling smoothly!
		input_state.trick_status_string = "Landed directly into Manual!"
		manual_timer = manual_entry_delay # Instant loading buffer
	elif abs(pitch) > max_landing_tolerance_deg:
		# BAIL / WHEEL BITE: landed too steep outside of manual catching zone!
		input_state.trick_status_string = "BAIL! (Wheel Bite / Over-Pitched)"
		current_speed = 0.0 # Speed penalty for crashing
		board_pivot.rotation_degrees.x = 0.0
		manual_timer = 0.0
	else:
		# CLEAN LANDING: within tolerances
		input_state.trick_status_string = "Clean Touchdown & Rolling"
		manual_timer = 0.0

func _apply_grounded_board_pitch(delta: float) -> void:
	var target_pitch_deg: float = 0.0
	var left_is_front: bool = input_state.leading_foot.begins_with("Left")
	var front_stick: Vector2 = input_state.left_stick_raw if left_is_front else input_state.right_stick_raw
	var back_stick: Vector2 = input_state.right_stick_raw if left_is_front else input_state.left_stick_raw
	
	# Manuals trigger in the expanded middle zone between 0.20 and 0.90 on whichever stick corresponds to leading/trailing edge!
	if back_stick.y > 0.20 and back_stick.y <= 0.90:
		target_pitch_deg = back_stick.y * 24.0
	elif front_stick.y < -0.20 and front_stick.y >= -0.90:
		target_pitch_deg = front_stick.y * 24.0
	
	# Tightened Grounded Manual Delay (80ms): ignores brief transition frames when fast-snapping to full extension
	if is_grounded and abs(target_pitch_deg) > 0.5:
		if manual_timer < manual_entry_delay:
			manual_timer += delta
			target_pitch_deg = 0.0
	else:
		manual_timer = 0.0
	
	board_pivot.rotation_degrees.x = lerpf(board_pivot.rotation_degrees.x, target_pitch_deg, 16.0 * delta)

func _start_foot_push(foot: String) -> void:
	active_push_foot = foot
	push_anim_time = 0.0

func _animate_foot_push_stroke(delta: float) -> void:
	if active_push_foot != "":
		push_anim_time += delta
		var progress: float = push_anim_time / push_anim_duration
		if progress >= 1.0:
			left_foot.position = left_foot_rest
			right_foot.position = right_foot_rest
			active_push_foot = ""
		else:
			# Sinusoidal dip to ground zero (Y - 0.055) paired with a forward-to-backward sweeping thrust on Z
			var vertical_dip: float = sin(progress * PI) * -0.055
			var lateral_reach: float = sin(progress * PI) * 0.22
			var longitudinal_sweep: float = cos(progress * PI) * -0.15 # Reaches forward at start, thrusts backward at finish!
			if active_push_foot == "left":
				left_foot.position = left_foot_rest + Vector3(-lateral_reach, vertical_dip, longitudinal_sweep)
			else:
				right_foot.position = right_foot_rest + Vector3(lateral_reach, vertical_dip, longitudinal_sweep)

func _animate_ankle_pegs(delta: float) -> void:
	if input_state.left_mag > 0.05:
		left_peg_pivot.rotation_degrees.x = lerpf(left_peg_pivot.rotation_degrees.x, input_state.left_stick_raw.y * 35.0, 16.0 * delta)
		left_peg_pivot.rotation_degrees.z = lerpf(left_peg_pivot.rotation_degrees.z, -input_state.left_stick_raw.x * 35.0, 16.0 * delta)
	else:
		left_peg_pivot.rotation = left_peg_pivot.rotation.lerp(Vector3.ZERO, 16.0 * delta)
		
	if input_state.right_mag > 0.05:
		right_peg_pivot.rotation_degrees.x = lerpf(right_peg_pivot.rotation_degrees.x, input_state.right_stick_raw.y * 35.0, 16.0 * delta)
		right_peg_pivot.rotation_degrees.z = lerpf(right_peg_pivot.rotation_degrees.z, -input_state.right_stick_raw.x * 35.0, 16.0 * delta)
	else:
		right_peg_pivot.rotation = right_peg_pivot.rotation.lerp(Vector3.ZERO, 16.0 * delta)
