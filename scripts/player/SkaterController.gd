class_name SkaterController
extends Node3D

@export_category("Surface Collision")
# Rig origin to wheel contact, measured from the model: the lowest wheel vertex sits 0.078 below
# the rig origin. The old hardcoded 0.25 was never this distance - it was just the height the rig
# happened to be placed at, while the Ground body's top surface is at y=0, so the board floated
# 17 cm and its shadow read as detached.
@export var ride_height: float = 0.078
@export var probe_reach: float = 1.2 # How far below the trucks to look for a surface.
@export var ground_snap_distance: float = 0.06 # Surface gap within which the skater counts as grounded.
@export var surface_align_speed: float = 12.0 # Lerp rate for pitching/rolling onto a new surface.
@export var max_surface_angle_deg: float = 50.0 # Steeper than this is a wall, not a ridable surface.
# Measured from the model: axle CENTRES sit at z = +/-0.2250 (0.45 m wheelbase) with 48 mm wheels.
# Do not derive these from the wheels' bounding extents - that gives 0.2489, which is the axle plus
# the wheel radius, and pivoting there lifts the board off the ground instead of seating it.
@export var manual_axle_z: float = 0.225
@export var wheel_radius: float = 0.024
@export var truck_half_width: float = 0.09 # Lateral spacing of the ground probes.
@export var wall_probe_distance: float = 0.35 # Forward reach of the wall block probe.
@export_range(0.0, 1.0) var wall_stop_damping: float = 0.0 # Speed retained on wall contact.
var _probe: SurfaceProbe = null
var surface_hit: SurfaceProbe.Hit = SurfaceProbe.Hit.new()

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
@export var flip_speed_deg: float = 608.0
@export var spin_speed_deg: float = 432.0
@export var body_spin_speed_deg: float = 554.0
var target_board_roll: float = 0.0
var target_board_yaw: float = 0.0
var current_aerial_spin_rate: float = 0.0
var is_flip_in_progress: bool = false
## Raw world body yaw accumulated between pop and touchdown. Rider-normalised only when it is
## folded into the trick signature, so this stays comparable with board_pivot.rotation_degrees.y.
var airborne_body_yaw_deg: float = 0.0
## Whether the rider was riding reversed (switch / fakie) at the moment of the pop. Sampled from
## the pivot's real yaw rather than inferred, and captured at pop because the yaw changes in flight.
var pop_riding_reversed: bool = false

@onready var input_state: FootInputState = $FootInputState
## Carries ONLY surface pitch/roll. Deliberately a separate node from BoardPivot: that one's X is
## trick pitch (written by the manual/pop systems and read back by landing checks), so sharing the
## channel would corrupt manuals, wheel-bite detection and pops. CameraPivot stays on SkaterRoot so
## the chase camera does not roll with the ramp.
@onready var surface_align: Node3D = $SurfaceAlign
@onready var board_pivot: Node3D = $SurfaceAlign/BoardPivot
@onready var board_mesh: Node3D = $SurfaceAlign/BoardPivot/BoardMesh
@onready var left_foot: MeshInstance3D = $SurfaceAlign/BoardPivot/LeftFoot
@onready var right_foot: MeshInstance3D = $SurfaceAlign/BoardPivot/RightFoot
@onready var left_peg_pivot: Node3D = $SurfaceAlign/BoardPivot/LeftFoot/PegPivot
@onready var right_peg_pivot: Node3D = $SurfaceAlign/BoardPivot/RightFoot/PegPivot

@export_category("Motion & Push Physics")
@export var max_push_speed: float = 7.0
@export var push_impulse: float = 2.0
@export var rolling_friction: float = 1.0
@export var peg_tilt_deg: float = 35.0 # Max ankle peg lean at full stick deflection
var velocity: Vector3 = Vector3.ZERO
var current_speed: float = 0.0

# Foot Push Animation State (Elevated to Y = 0.055 to prevent board collisions).
# Rest poses are captured from SkaterRig.tscn in _ready() so foot placement has exactly one
# source of truth; hardcoding them here silently reverted any offset set in the scene as soon
# as a push stroke finished.
var left_foot_rest: Vector3 = Vector3(-0.025, 0.055, -0.25)
var right_foot_rest: Vector3 = Vector3(-0.025, 0.055, 0.25)
var active_push_foot: String = ""
var push_anim_time: float = 0.0
var push_anim_duration: float = 0.25

func _ready() -> void:
	left_foot_rest = left_foot.position
	right_foot_rest = right_foot.position
	var exclude: Array[RID] = []
	_probe = SurfaceProbe.new(get_world_3d().direct_space_state, exclude)

## Truck corners in world space, derived from SkaterRoot's YAW ONLY. Deliberately not taken from the
## board nodes: those pitch 22 deg on every pop and roll during flips, which would swing the probe
## origins around exactly when landing accuracy matters most.
func _truck_points() -> PackedVector3Array:
	var yaw_basis := Basis(Vector3.UP, rotation.y)
	var origin := global_position
	var pts := PackedVector3Array()
	# Footprint comes from the SAME measured axle position the manual pivot uses. It previously
	# carried the deleted RayCast nodes' z = +/-0.28, which disagreed with the real axle at 0.225.
	for sx in [-truck_half_width, truck_half_width]:
		for sz in [-manual_axle_z, manual_axle_z]:
			pts.append(origin + yaw_basis * Vector3(sx, 0.0, sz))
	return pts

## Probes for the surface under the trucks. Starts slightly above the rig so the ray cannot begin
## already inside a ledge the skater is standing on.
func _probe_surface() -> SurfaceProbe.Hit:
	if _probe == null:
		return SurfaceProbe.Hit.new()
	var pts := PackedVector3Array()
	for p in _truck_points():
		pts.append(p + Vector3.UP * 0.1)
	var hit: SurfaceProbe.Hit = _probe.highest_below(pts, probe_reach + 0.1)
	# Anything steeper than max_surface_angle_deg is a wall face, not something to stand on.
	if hit.valid and rad_to_deg(hit.normal.angle_to(Vector3.UP)) > max_surface_angle_deg:
		return SurfaceProbe.Hit.new()
	return hit

## Height the rig should sit at to rest on the probed surface.
func _surface_ride_y() -> float:
	return surface_hit.position.y + ride_height

## Tilts SurfaceAlign onto the probed surface normal. Ramps come out of this for free; so does
## flattening back out in the air.
func _apply_surface_alignment(delta: float) -> void:
	var target := Vector3.ZERO
	if is_grounded and surface_hit.valid:
		# Express the normal in the rig's yaw frame so pitch/roll read as board-local tilt.
		var local_n: Vector3 = Basis(Vector3.UP, -rotation.y) * surface_hit.normal
		# Solve for the rotation that carries the board's local +Y onto the surface normal:
		# rotating about X by t maps +Y to (0, cos t, sin t), and about Z by t maps it to
		# (-sin t, cos t, 0). Getting either negation backwards tilts the board AWAY from the slope
		# by the slope angle instead of onto it - a 2x error that reads as "pitches forward going
		# uphill". Asserted by align_test: board up axis must equal the surface normal.
		target.x = atan2(local_n.z, local_n.y)
		target.z = atan2(-local_n.x, local_n.y)
	surface_align.rotation.x = lerp_angle(surface_align.rotation.x, target.x, surface_align_speed * delta)
	surface_align.rotation.z = lerp_angle(surface_align.rotation.z, target.z, surface_align_speed * delta)

## Makes the board pitch about the CONTACT AXLE rather than the rig origin.
##
## BoardPivot sits at the rig origin - board centre, ride_height above the ground - so rotating it
## drove the dipping end straight through the floor (8.7 cm under at full 24 deg manual). A real
## manual pivots about the wheels that are still touching.
##
## Rotating a child about a point P instead of its origin is a pure offset: the board point at local
## P must stay where it sat before the pitch was applied. With basis = Ry * Rx that solves to
## position = Ry * (P - Rx * P), so the yaw (body spin) carries the offset around correctly.
##
## Only applied while grounded - airborne, the deck should spin about its centre or flips look wrong.
func _apply_manual_pivot() -> void:
	var offset := Vector3.ZERO
	if is_grounded:
		var pitch: float = board_pivot.rotation.x
		if absf(pitch) > 0.0001:
			# Pivot on the AXLE CENTRE, not the contact patch: the wheel is round, so rotating about
			# its centre keeps it tangent to the ground as it rolls. Using the contact point instead
			# lifts the board a few mm at full tilt.
			var p := Vector3(0.0, -(ride_height - wheel_radius), manual_axle_z * signf(pitch))
			offset = Basis(Vector3.UP, board_pivot.rotation.y) * (p - Basis(Vector3.RIGHT, pitch) * p)
	board_pivot.position = offset

## Stops horizontal motion against vertical faces. Probes from truck height in the travel direction.
func _blocked_by_wall(travel: Vector3) -> bool:
	if _probe == null or travel.length_squared() < 0.0001:
		return false
	var dir: Vector3 = travel.normalized()
	var origin: Vector3 = global_position + Vector3.UP * 0.02
	var hit: SurfaceProbe.Hit = _probe.cast_horizontal(origin, dir, wall_probe_distance)
	if not hit.valid:
		return false
	# Only near-vertical faces block; ramps and curb tops are handled by the ground probe.
	return rad_to_deg(hit.normal.angle_to(Vector3.UP)) > max_surface_angle_deg

func _physics_process(delta: float) -> void:
	# 1. Grounded vs Airborne evaluation, measured against real geometry rather than a fixed plane.
	#
	# Proximity may only KEEP the skater grounded, never make them grounded. The airborne -> grounded
	# transition belongs exclusively to the touchdown path in section 6, which is what zeroes
	# vertical_velocity and runs _evaluate_touchdown_landing() (landing tolerances, bail checks,
	# trick naming). Letting this block flip the flag on proximity skipped all of that whenever the
	# skater entered the snap band gently - rolling off a low curb left v_speed stuck negative
	# forever and never resolved the trick name.
	surface_hit = _probe_surface()
	if vertical_velocity > 0.05:
		is_grounded = false
	elif not surface_hit.valid:
		is_grounded = false # Nothing underneath - rolled off a ledge, no special case needed.
	elif is_grounded:
		is_grounded = global_position.y - _surface_ride_y() <= ground_snap_distance

	# Synchronize all kinematic animations and stance updates to physics tick
	_animate_ankle_pegs(delta)
	_animate_foot_push_stroke(delta)
	_apply_surface_alignment(delta)
	# Pass SkaterRoot, not board_pivot: update_stance_facts() reads pivot.get_parent() for the
	# stationary forward vector, and that parent is now the surface-tilted SurfaceAlign node.
	input_state.update_stance_facts(board_pivot, left_foot, right_foot, velocity, self)
	
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
		elif vertical_velocity > 0.5 or (surface_hit.valid and global_position.y - _surface_ride_y() > 0.35):
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
		
		airborne_body_yaw_deg = 0.0
		# Same idiom as deck_reversed below: read the orientation instead of inferring it.
		pop_riding_reversed = cos(deg_to_rad(board_pivot.rotation_degrees.y)) < 0.0
		var sig: TrickSignature = input_state.current_trick

		# Initial kicktail pitch angle and flip roll sign upon popping (inverted in Switch/Fakie where Y == 180!)
		var stance_sign: float = 1.0 if input_state.leading_foot == FootInputState.Foot.LEFT else -1.0
		if sig.pop == TrickSignature.Pop.NOLLIE or sig.pop == TrickSignature.Pop.FAKIE_OLLIE:
			board_pivot.rotation_degrees.x = -22.0 * stance_sign # Leading nose pop
		else:
			board_pivot.rotation_degrees.x = 22.0 * stance_sign # Trailing tail pop

		# Configure BoardMesh flip & spin targets (Layer 3). Only the deck's own 180 deg yaw reversal
		# after a Shove-it needs compensating here - Nollie/Fakie flip mirroring is already applied
		# in FootInputState._build_trick_signature(), so there is no stance term.
		var deck_reversed: bool = cos(deg_to_rad(board_mesh.rotation_degrees.y)) < 0.0
		var roll_sign: float = -1.0 if deck_reversed else 1.0
		if sig.flip == TrickSignature.Flip.KICK:
			target_board_roll = board_mesh.rotation_degrees.z + (360.0 * roll_sign)
			is_flip_in_progress = true
		elif sig.flip == TrickSignature.Flip.HEEL:
			target_board_roll = board_mesh.rotation_degrees.z - (360.0 * roll_sign)
			is_flip_in_progress = true
		else:
			target_board_roll = board_mesh.rotation_degrees.z

		# Spin magnitude comes from the measured signature, never from the display name.
		if sig.shuv_deg != 0:
			var spin_deg: float = 360.0 if absi(sig.shuv_deg) == 360 else 180.0
			target_board_yaw = board_mesh.rotation_degrees.y + (spin_deg * input_state.last_scoop_sign)
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
			airborne_body_yaw_deg -= current_aerial_spin_rate * delta
		
		# Layer 2: Mid-Air Pitch Control (0.20 to 1.00 thumbsticks to angle nose/tail in air)
		_apply_airborne_board_pitch(delta)
		
		# Layer 3: Deck Flip & Spin Authority on BoardMesh with Shoe Hover Catching
		if is_flip_in_progress:
			var is_360_spin: bool = absi(input_state.current_trick.shuv_deg) == 360
			var active_spin_vel: float = spin_speed_deg * 2.0 if absf(target_board_yaw - board_mesh.rotation_degrees.y) > 185.0 or is_360_spin else spin_speed_deg
			board_mesh.rotation_degrees.z = move_toward(board_mesh.rotation_degrees.z, target_board_roll, flip_speed_deg * delta)
			board_mesh.rotation_degrees.y = move_toward(board_mesh.rotation_degrees.y, target_board_yaw, active_spin_vel * delta)
			
			# Elevate shoe boxes slightly above spinning deck (Y = 0.18m)
			left_foot.position.y = lerpf(left_foot.position.y, 0.18, 16.0 * delta)
			right_foot.position.y = lerpf(right_foot.position.y, 0.18, 16.0 * delta)
			
			# Catch trick cleanly when deck revolution completes (grip tape facing up)
			if is_equal_approx(board_mesh.rotation_degrees.z, target_board_roll) and is_equal_approx(board_mesh.rotation_degrees.y, target_board_yaw):
				is_flip_in_progress = false
				board_mesh.rotation_degrees.z = fmod(board_mesh.rotation_degrees.z, 360.0)
				board_mesh.rotation_degrees.y = fmod(board_mesh.rotation_degrees.y, 360.0)
				input_state.trick_status_string = "Caught in mid-air!"
		else:
			# Return shoe boxes to ride rest height when trick is caught or no flip active
			left_foot.position.y = lerpf(left_foot.position.y, left_foot_rest.y, 16.0 * delta)
			right_foot.position.y = lerpf(right_foot.position.y, right_foot_rest.y, 16.0 * delta)
		
		# Touchdown onto whatever surface the probe found - ground, curb top, ramp face.
		if surface_hit.valid and global_position.y <= _surface_ride_y() and vertical_velocity <= 0.0:
			global_position.y = _surface_ride_y()
			vertical_velocity = 0.0
			is_grounded = true
			current_aerial_spin_rate = 0.0
			input_state.current_pop_state = FootInputState.PopState.NONE
			_evaluate_touchdown_landing()
	
	# 7. Horizontal Kinematic Motion Execution, blocked by vertical faces.
	velocity = -global_transform.basis.z * current_speed
	var travel: Vector3 = velocity * delta
	if _blocked_by_wall(travel):
		current_speed *= wall_stop_damping
		velocity = Vector3.ZERO
	else:
		global_position += travel

	# Ride the surface while grounded so curb tops and ramps are followed rather than fallen through.
	if is_grounded and surface_hit.valid:
		global_position.y = _surface_ride_y()
	
	# 8. Grounded Board Rotations & Middle-Zone Manuals (only when on pavement)
	if is_grounded:
		_apply_grounded_board_pitch(delta)
		if active_push_foot == "":
			left_foot.position = left_foot_rest
			right_foot.position = right_foot_rest

	# 9. Re-seat the board onto its contact axle. Runs last, after every writer of board_pivot pitch
	# (the pop in step 5, airborne pitch in step 6, grounded manuals just above).
	_apply_manual_pivot()

func _apply_airborne_board_pitch(delta: float) -> void:
	var target_pitch_deg: float = 0.0
	var left_is_front: bool = input_state.leading_foot == FootInputState.Foot.LEFT
	var front: Vector2 = input_state.front_stick()
	var back: Vector2 = input_state.back_stick()

	if back.y > 0.15:
		target_pitch_deg = back.y * 24.0 # Tail dip (trailing edge)
	elif front.y < -0.15:
		target_pitch_deg = front.y * 24.0 # Nose dip (leading edge)
		
	if not left_is_front:
		target_pitch_deg = -target_pitch_deg # Invert local X rotation when board is at Y=180
	
	board_pivot.rotation_degrees.x = lerpf(board_pivot.rotation_degrees.x, target_pitch_deg, 14.0 * delta)

## Folds the body rotation that just happened into the trick signature and resolves its name.
## Called only on successful landings - a bail leaves the previous landed trick on display.
func _finalise_trick_name() -> void:
	var sig: TrickSignature = input_state.current_trick
	var half_turns: int = int(round(airborne_body_yaw_deg / 180.0))
	sig.body_deg = half_turns * 180 * TrickSignature.body_sign(
		input_state.stance == FootInputState.Stance.GOOFY, pop_riding_reversed)
	input_state.last_combo_string = TrickNames.resolve(sig)
	input_state.last_trick_signature = sig.describe()

func _evaluate_touchdown_landing() -> void:
	# Firmly seat shoes onto deck rest coordinates immediately upon ground contact
	left_foot.position = left_foot_rest
	right_foot.position = right_foot_rest
	
	# Primo / Incomplete Flip Check
	if is_flip_in_progress:
		input_state.trick_status_string = "BAIL! (Primo Crash / Incomplete Flip)"
		current_speed = 0.0
		board_mesh.rotation_degrees.z = 0.0
		board_mesh.rotation_degrees.y = 0.0
		is_flip_in_progress = false
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
	
	var left_is_front: bool = input_state.leading_foot == FootInputState.Foot.LEFT
	var front: Vector2 = input_state.front_stick()
	var back: Vector2 = input_state.back_stick()

	# Check if back or front stick is cleanly held within the expanded Manual Zone (0.20 to 0.90) upon touchdown
	var effective_pitch: float = pitch if left_is_front else -pitch
	if effective_pitch > 5.0 and back.y >= 0.20 and back.y <= 0.90:
		in_manual_zone = true # Touchdown into standard / switch manual!
	elif effective_pitch < -5.0 and front.y <= -0.20 and front.y >= -0.90:
		in_manual_zone = true # Touchdown into nose / switch nose manual!
	
	if in_manual_zone:
		# INSTANT MANUAL CATCH: bypass loading delay and continue rolling smoothly!
		_finalise_trick_name()
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
		_finalise_trick_name()
		input_state.trick_status_string = "Landed %s!" % input_state.last_combo_string
		manual_timer = 0.0

func _apply_grounded_board_pitch(delta: float) -> void:
	var target_pitch_deg: float = 0.0
	var left_is_front: bool = input_state.leading_foot == FootInputState.Foot.LEFT
	var front: Vector2 = input_state.front_stick()
	var back: Vector2 = input_state.back_stick()

	# Manuals trigger in the expanded middle zone between 0.20 and 0.90 on whichever stick corresponds to leading/trailing edge!
	if back.y > 0.20 and back.y <= 0.90:
		target_pitch_deg = back.y * 24.0
	elif front.y < -0.20 and front.y >= -0.90:
		target_pitch_deg = front.y * 24.0
		
	if not left_is_front:
		target_pitch_deg = -target_pitch_deg # Invert local X rotation when board is at Y=180
	
	# Tightened Grounded Manual Delay (80ms): ignores brief transition frames when fast-snapping to full extension
	if abs(target_pitch_deg) > 0.5:
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
			# Sinusoidal dip toward the deck surface paired with a forward-to-backward sweeping thrust on Z
			var vertical_dip: float = sin(progress * PI) * -0.055
			var left_is_leading: bool = input_state.leading_foot == FootInputState.Foot.LEFT
			var is_mongo_push: bool = (active_push_foot == "left" and left_is_leading) or (active_push_foot == "right" and not left_is_leading)
			var lateral_dir: float = -1.0 if is_mongo_push else 1.0 # Mongo reaches to heel side (-X), Standard reaches to toe side (+X)
			var lateral_reach: float = sin(progress * PI) * 0.22 * lateral_dir
			var longitudinal_sweep: float = cos(progress * PI) * -0.15 # Reaches forward at start, thrusts backward at finish!
			if active_push_foot == "left":
				left_foot.position = left_foot_rest + Vector3(lateral_reach, vertical_dip, longitudinal_sweep)
			else:
				right_foot.position = right_foot_rest + Vector3(lateral_reach, vertical_dip, longitudinal_sweep)

func _animate_ankle_pegs(delta: float) -> void:
	# Each PegPivot hangs under BoardPivot, which yaws to 180 deg in Switch/Fakie while
	# CameraPivot (parented to SkaterRoot) stays put. Driving the tilt directly in pivot-local
	# degrees therefore mirrored the pegs in switch, so stick-down read as up and left as right.
	# Rotating the stick vector out of screen space and into the pivot's frame keeps the pegs
	# pointing the way the physical stick is actually pushed at ANY yaw, so they stay honest
	# part-way through an aerial spin too, not just at 0 deg and 180 deg.
	var yaw: float = board_pivot.rotation.y
	var yaw_cos: float = cos(yaw)
	var yaw_sin: float = sin(yaw)
	_drive_ankle_peg(left_peg_pivot, input_state.left_stick_raw, input_state.left_mag, yaw_cos, yaw_sin, delta)
	_drive_ankle_peg(right_peg_pivot, input_state.right_stick_raw, input_state.right_mag, yaw_cos, yaw_sin, delta)

func _drive_ankle_peg(pivot: Node3D, stick: Vector2, mag: float, yaw_cos: float, yaw_sin: float, delta: float) -> void:
	if mag <= 0.05:
		pivot.rotation = pivot.rotation.lerp(Vector3.ZERO, 16.0 * delta)
		return
	# Screen-space stick (x = right, y = toward the camera) resolved onto the pivot's local axes.
	var local_x: float = stick.x * yaw_cos - stick.y * yaw_sin
	var local_z: float = stick.x * yaw_sin + stick.y * yaw_cos
	pivot.rotation_degrees.x = lerpf(pivot.rotation_degrees.x, local_z * peg_tilt_deg, 16.0 * delta)
	pivot.rotation_degrees.z = lerpf(pivot.rotation_degrees.z, -local_x * peg_tilt_deg, 16.0 * delta)
