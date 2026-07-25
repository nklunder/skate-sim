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
@export var body_spin_speed_deg: float = 240.0
var target_board_roll: float = 0.0
var target_board_yaw: float = 0.0
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
	
	# 2. Push Acceleration Impulses via Face Buttons (only on ground)
	if is_grounded and (input_state.push_left_triggered or input_state.push_right_triggered):
		current_speed = minf(current_speed + push_impulse, max_push_speed)
		if input_state.push_left_triggered:
			_start_foot_push("left")
		else:
			_start_foot_push("right")
	
	# 3. Rolling Resistance / Deceleration when rolling on pavement
	if is_grounded:
		current_speed = maxf(0.0, current_speed - rolling_friction * delta)
	
	# 4. Steering & Stationary Rotation via Trigger Lean (RT - LT) on pavement
	var turn_rate: float = input_state.lean * (input_state.board_config.turn_speed if is_instance_valid(input_state.board_config) else 3.0)
	if is_grounded and abs(input_state.lean) > 0.05:
		rotate_y(-turn_rate * delta)
	
	# 5. Execute Vertical Pop Impulse & Setup 3-Layer Trick Rotations
	if is_grounded and input_state.pop_impulse_triggered:
		vertical_velocity = jump_impulse
		is_grounded = false
		input_state.pop_impulse_triggered = false
		
		# Initial kicktail pitch angle upon popping
		if input_state.last_pop_type.begins_with("Ollie"):
			board_pivot.rotation_degrees.x = 22.0
		else:
			board_pivot.rotation_degrees.x = -22.0
			
		# Configure BoardMesh flip & spin targets (Layer 3)
		if input_state.active_flip_type == "Kickflip":
			target_board_roll = board_mesh.rotation_degrees.z + 360.0
			is_flip_in_progress = true
		elif input_state.active_flip_type == "Heelflip":
			target_board_roll = board_mesh.rotation_degrees.z - 360.0
			is_flip_in_progress = true
		else:
			target_board_roll = board_mesh.rotation_degrees.z
			
		if input_state.active_spin_type != "None":
			target_board_yaw = board_mesh.rotation_degrees.y + 180.0
			is_flip_in_progress = true
		else:
			target_board_yaw = board_mesh.rotation_degrees.y
	
	# 6. Apply Custom Gravity, Aerial Pitch Control, 3-Layer Flight Physics & Touchdown
	if not is_grounded:
		vertical_velocity -= gravity_accel * delta
		global_position.y += vertical_velocity * delta
		
		# Layer 1: Aerial Body & Deck Spin Authority (FS/BS 180s/360s via triggers)
		# Applied to board_pivot.y so rolling travel vector and chase camera stay fixed behind the skater!
		if abs(input_state.lean) > 0.05:
			board_pivot.rotation_degrees.y -= input_state.lean * body_spin_speed_deg * delta
		
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
	# In mid-air, full deflection range (0.20 to 1.0) directly tilts the board for catching manuals or leveling out
	if input_state.stance == FootInputState.Stance.REGULAR:
		if input_state.right_stick_raw.y > 0.15:
			target_pitch_deg = input_state.right_stick_raw.y * 24.0 # Tail dip
		elif input_state.left_stick_raw.y < -0.15:
			target_pitch_deg = input_state.left_stick_raw.y * 24.0 # Nose dip
	else:
		if input_state.left_stick_raw.y > 0.15:
			target_pitch_deg = input_state.left_stick_raw.y * 24.0
		elif input_state.right_stick_raw.y < -0.15:
			target_pitch_deg = input_state.right_stick_raw.y * 24.0
	
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
		
	# Snap touchdown yaw to nearest 180 orientation (Regular Forward vs Fakie/Switch)
	var curr_yaw: float = fmod(board_pivot.rotation_degrees.y, 360.0)
	if curr_yaw < 0.0:
		curr_yaw += 360.0
	if curr_yaw >= 90.0 and curr_yaw <= 270.0:
		board_pivot.rotation_degrees.y = 180.0 # Riding Switch / Fakie!
	else:
		board_pivot.rotation_degrees.y = 0.0 # Riding Regular Forward!

	var pitch: float = board_pivot.rotation_degrees.x
	var in_manual_zone: bool = false
	
	# Check if stick is cleanly held within the expanded Manual Zone (0.20 to 0.90) upon touchdown
	if input_state.stance == FootInputState.Stance.REGULAR:
		if pitch > 5.0 and input_state.right_stick_raw.y >= 0.20 and input_state.right_stick_raw.y <= 0.90:
			in_manual_zone = true
		elif pitch < -5.0 and input_state.left_stick_raw.y <= -0.20 and input_state.left_stick_raw.y >= -0.90:
			in_manual_zone = true
	else:
		if pitch > 5.0 and input_state.left_stick_raw.y >= 0.20 and input_state.left_stick_raw.y <= 0.90:
			in_manual_zone = true
		elif pitch < -5.0 and input_state.right_stick_raw.y <= -0.20 and input_state.right_stick_raw.y >= -0.90:
			in_manual_zone = true
	
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
	# Manuals trigger in the expanded middle zone between 0.20 and 0.90.
	# Full stick extension (> 0.90) is reserved for Trick/Pop Setup and holds the deck level on pavement!
	if input_state.stance == FootInputState.Stance.REGULAR:
		if input_state.right_stick_raw.y > 0.20 and input_state.right_stick_raw.y <= 0.90:
			target_pitch_deg = input_state.right_stick_raw.y * 24.0
		elif input_state.left_stick_raw.y < -0.20 and input_state.left_stick_raw.y >= -0.90:
			target_pitch_deg = input_state.left_stick_raw.y * 24.0
	else: # GOOFY stance (Left foot is over Tail)
		if input_state.left_stick_raw.y > 0.20 and input_state.left_stick_raw.y <= 0.90:
			target_pitch_deg = input_state.left_stick_raw.y * 24.0
		elif input_state.right_stick_raw.y < -0.20 and input_state.right_stick_raw.y >= -0.90:
			target_pitch_deg = input_state.right_stick_raw.y * 24.0
	
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
			# Sinusoidal stroke curve sweeping foot out and down against pavement
			var stroke_offset: float = sin(progress * PI)
			if active_push_foot == "left":
				left_foot.position = left_foot_rest + Vector3(-0.2 * stroke_offset, -0.05 * stroke_offset, 0.0)
			else:
				right_foot.position = right_foot_rest + Vector3(0.2 * stroke_offset, -0.05 * stroke_offset, 0.0)

func _animate_ankle_pegs(delta: float) -> void:
	if input_state.left_mag > 0.05:
		var target_y: float = -input_state.left_angle
		var target_x: float = -input_state.left_mag * 0.35
		left_peg_pivot.rotation.y = lerp_angle(left_peg_pivot.rotation.y, target_y, 16.0 * delta)
		left_peg_pivot.rotation.x = lerpf(left_peg_pivot.rotation.x, target_x, 16.0 * delta)
	else:
		left_peg_pivot.rotation = left_peg_pivot.rotation.lerp(Vector3.ZERO, 16.0 * delta)
		
	if input_state.right_mag > 0.05:
		var target_y: float = -input_state.right_angle
		var target_x: float = -input_state.right_mag * 0.35
		right_peg_pivot.rotation.y = lerp_angle(right_peg_pivot.rotation.y, target_y, 16.0 * delta)
		right_peg_pivot.rotation.x = lerpf(right_peg_pivot.rotation.x, target_x, 16.0 * delta)
	else:
		right_peg_pivot.rotation = right_peg_pivot.rotation.lerp(Vector3.ZERO, 16.0 * delta)
