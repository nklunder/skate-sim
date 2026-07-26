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

@export_category("Deck Catch Physics")
## Shoe-rubber-on-griptape friction coefficient. A rider can stamp an off-axis deck flat while its
## tilt stays inside the friction cone atan(mu); past that the foot slides down the rail rather than
## flattening it, and the board shoots out. mu = 1.0 is a 45 deg cone.
##
## This is what decides whether a flip is landable - NOT whether a fixed-duration flip animation
## happened to finish. Judging on duration made trick success depend on hang time, so raising a ledge
## by 5 cm could make a kickflip mathematically impossible to land (see AGENTS.md known bugs).
@export var grip_friction: float = 1.0
## Measured from the loaded deck in _ready(), never authored. Half-width and underside height give
## the roll angle at which a RAIL reaches the ground before the wheels do; rolling past it would
## drag the deck through the floor, so it caps the catch cone no matter how grippy the shoes are.
var deck_half_width: float = 0.0
var deck_underside_y: float = 0.0
## min(friction cone, rail-strike angle). Resolved once, from geometry, at _ready().
var catch_cone_deg: float = 45.0
## How far off its resting orientation the deck was at the last touchdown. 0 is a dead-flat catch,
## catch_cone_deg is the sketchiest one still rideable. Recorded at the instant of contact because
## the settle starts erasing it on the very next frame.
var last_catch_error_deg: float = 0.0

@export_category("Landing Absorption")
## Visual suspension travel. Until this existed the skater hit the ground at several m/s and stopped
## in one frame with no give anywhere in the system.
##
## NOT the fix for harsh-feeling landings, and worth remembering why: a straight ollie has exactly
## the same dead stop as a badly-rotated one, and straight ollies read as fine. Impact was never the
## complaint - the travel-direction jerk was (see landing_turn_rate_deg). This is separate polish,
## and setting landing_dip_max to 0.0 disables it cleanly.
##
## Applied to SurfaceAlign.position, which nothing else writes, so the deck and rider compress toward
## the ground while the rig ORIGIN stays put. That matters: every ground probe and the ride-height
## snap work off global_position, so a dip here cannot disturb them. The camera hangs off SkaterRoot
## and so does not dip, which is what makes the compression readable rather than just a screen shake.
@export var landing_dip_max: float = 0.04 # Metres of compression at or above the reference impact.
@export var landing_dip_ref_speed: float = 6.0 # Impact speed producing full compression.
@export var landing_dip_recover: float = 9.0 # Rate the suspension extends back out.
var _landing_dip: float = 0.0

@export_category("Camera")
## How quickly the chase camera's yaw catches up to the rig's.
##
## CameraPivot is a rigid child of SkaterRoot, so until this existed every instantaneous change to
## rig yaw was inherited whole. That was harmless while landings snapped to a perfect 0/180 - rig yaw
## simply never jumped. It stopped being harmless the moment landings began transferring their
## heading residual straight into rotation.y: a 5 deg imperfect landing snapped the view 5 deg, and a
## sideways wash-out snapped it by the full residual.
##
## This governs CONTINUOUS tracking only - steering, essentially. Trail during a turn is roughly
## turn_rate / this at sustained full lean, so ~7 deg at the default 3.0 rad/s. Raise for a tighter,
## more rigid feel; lower for a looser one. Very high values reproduce rigid parenting exactly.
##
## Deliberately NOT the rate that absorbs landing jumps - see camera_recenter_speed. A single rate
## could not serve both: fast enough to stop ground turns feeling boaty was far too fast for a
## landing swing, and slow enough to soften the landing made every turn feel like steering a barge.
@export var camera_follow_speed: float = 25.0
## Stiffness of the critically damped spring that returns an absorbed landing jump to zero. Settles
## in roughly 4 / this seconds, so 12.0 is about a third of a second.
##
## Critically damped rather than a constant slew or a lerp, because the two failure modes sit at
## opposite ends: a lerp moves fastest at the instant the error appears (the whip that read as "too
## snappy"), while a constant slew starts and stops angular velocity abruptly at both ends. A spring
## starts from rest, swells, and decelerates into place, and never overshoots.
@export var camera_recenter_speed: float = 12.0
## How hard the camera's follow position is corrected toward the skater.
##
## Velocity is fed forward before this is applied, so riding at a constant speed produces NO lag at
## all and the framing is exactly as authored. Only CHANGES in motion - landings, wall stops - let
## the camera fall behind and catch up, which is where the sense of weight comes from. This is also
## the seam to hang per-trick camera work off later (grinds, manuals): offset the follow position and
## everything downstream keeps working.
@export var camera_position_damp: float = 12.0
@onready var camera_pivot: Node3D = $CameraPivot
## Smoothed world yaw of the camera, tracked separately from the rig's so the two can diverge.
var _camera_yaw: float = 0.0
## Yaw the camera is deliberately still holding onto after a landing jump, plus its spring velocity.
## Keeping this separate from _camera_yaw is what lets steering stay tight while a landing swing
## stays gentle - one rate could not do both.
var _camera_jump_offset: float = 0.0
var _camera_jump_vel: float = 0.0
## Damped world position the camera orbits around. NOT simply the skater's position: see
## camera_position_damp.
var _camera_pos: Vector3 = Vector3.ZERO

@export_category("Aerial & Jump Physics")
@export var jump_impulse: float = 5.2
## Also sets which gradients hold the skater, via rolling_friction - see that field.
@export var gravity_accel: float = 16.0
# vertical_velocity now lives with `velocity` under Motion & Push Physics: it is velocity.y, not a
# variable of its own. Two velocity representations was the split this rewrite removed.

@export_category("Flip & Spin Physics (3-Layer Hierarchy)")
@export var flip_speed_deg: float = 608.0
@export var spin_speed_deg: float = 432.0
@export var body_spin_speed_deg: float = 554.0
var target_board_roll: float = 0.0
var target_board_yaw: float = 0.0
## Signed deg/s imparted to the deck at the pop, then held constant - airborne there is no torque on
## the board, so constant angular velocity is the physically correct integration.
##
## Both axes are scaled to share ONE trick duration. Driving them at independent fixed rates meant a
## 360 flip's yaw finished at 0.42 s while its roll was only 253 deg round, so the board visibly
## stopped spinning and kept flipping, then halted - see AGENTS.md.
var flip_roll_rate: float = 0.0
var flip_yaw_rate: float = 0.0
var current_aerial_spin_rate: float = 0.0
var is_flip_in_progress: bool = false
## True while the deck is rotating the last few degrees onto its resting orientation after a late
## catch. Landing must never teleport the deck flat - an instant snap of up to a full catch cone is
## precisely the visual pop this phase exists to avoid - so the remaining sweep is integrated at the
## flip's own angular rate instead.
var is_flip_settling: bool = false
## Deck roll / yaw at the instant of the pop, so the rotation the deck ACTUALLY achieved can be
## measured at touchdown and credited, rather than trusting what was asked for at pop time.
var _pop_board_roll: float = 0.0
var _pop_board_yaw: float = 0.0
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
@export var max_push_speed: float = 7.0 # Ceiling on PUSHING only - gravity may exceed it downhill.
@export var push_impulse: float = 2.0
## Deceleration opposing travel. Roughly 5-10x real rolling resistance: a real board coasts for over
## a minute, which is not fun. Since slopes went live this number does a SECOND job - it sets which
## gradients you can rest on. Friction holds you wherever the fall line is weaker than it, i.e. up to
## asin(rolling_friction / gravity_accel) ~= 3.6 deg at present. Nothing in TestWorld is that gentle,
## so every ramp here rolls you. Raise this if you want parkable banks.
@export var rolling_friction: float = 1.0
## Lateral grip: the deceleration the wheels apply ACROSS their rolling axis. Wheels roll freely
## along their axis and resist sideways, and that single asymmetry is what produces imperfect-landing
## drift, the speed cost of carving, and sideways-landing scrub. High values snap a crooked landing
## straight almost at once; low values let the board slide and drift.
@export var wheel_side_grip: float = 40.0
## Sideways speed at touchdown above which the wheels wash out and the rider is thrown.
##
## Replaced a fixed 45-135 deg angle window that had NO speed term, so landing at 100 deg while
## creeping at 0.2 m/s bailed exactly as hard as at 7 m/s. Because the test is on momentum, tolerance
## now scales with speed on its own: at 7 m/s you get +/-21 deg, at 3 m/s +/-56 deg, and at or below
## this value any angle is survivable - including a full 90 deg.
@export var max_landing_slide: float = 2.5
## Fastest the DIRECTION OF TRAVEL may swing while realigning after a landing, in degrees per second.
##
## Full grip on the first grounded frame turned travel by the whole residual in a single tick while
## the camera eased over eight - a smooth view over a world that jerked, which reads as a harsh
## landing without looking like a snap. Note this is the fix for that; landing_dip_max is NOT. A
## straight ollie has the same dead-stop impact as a badly-rotated one and reads as fine, so impact
## was never the complaint.
##
## Caps the ANGULAR rate rather than the lateral force, because the angle is what the eye tracks. A
## force cap gets the shape backwards: scrubbing removes a fixed slice of lateral speed per frame, so
## as the remainder shrinks the same slice becomes an ever LARGER angle, and the worst jerk lands on
## the final frame of the settle. Capping the angle gives a constant, even swing.
##
## Independent of the camera. The two once had to match, back when the camera's aim was smoothed
## while its position was not: the subject left the frame, so any disagreement between how fast the
## world turned and how fast the view turned was glaring. Now that the camera orbits and keeps the
## skater centred throughout, this is purely a question of how quickly the wheels drag travel into
## line, and can be tuned on its own merits.
##
## Applies only while realigning from a touchdown. Carving is a STEADY STATE and needs full grip: at
## full lean the board yaws ~172 deg/s, so a permanent cap here would make every hard turn drift.
## Same transient-versus-steady-state split the camera needed two rates for.
@export var landing_turn_rate_deg: float = 60.0
## Seconds since the last touchdown. Not currently read, but kept as the natural home for anything
## else that needs to know how fresh a landing is.
var _since_touchdown: float = 1000.0
## True while the wheels are still pulling travel back onto the board axis after a landing. A state
## flag rather than a fixed window deliberately: how long realignment takes depends on the residual
## AND the speed, so any fixed duration would expire mid-swing on slow, badly-rotated landings and
## reintroduce the jerk it was added to remove.
var _realigning: bool = false
@export var peg_tilt_deg: float = 35.0 # Max ankle peg lean at full stick deflection
## THE authoritative motion state, in world space. Deliberately not rebuilt from orientation each
## frame: `velocity = -basis.z * current_speed` made travel and facing the same quantity, so the
## skater could only ever move exactly where the board pointed. That is what forced landings to snap
## to a perfect 0/180, made slope gravity impossible to express, and left the sideways-landing test
## with nothing but an angle to go on.
##
## While GROUNDED, y is held at zero and height belongs entirely to the surface snap in step 7, so
## only the horizontal components are integrated. While AIRBORNE, y is the ballistic vertical speed.
var velocity: Vector3 = Vector3.ZERO
## Sideways speed at the last touchdown. On the HUD so max_landing_slide can be tuned against real
## landings rather than guessed at.
var last_landing_slide: float = 0.0

## Horizontal rolling speed. Derived from `velocity`, never stored alongside it - a scalar speed plus
## a separate direction is precisely the representation this rewrite removed. Assigning rescales the
## horizontal velocity in place, so every existing `current_speed = 0.0` and `current_speed *= x`
## call site keeps working and keeps meaning what it did.
var current_speed: float:
	get:
		return Vector2(velocity.x, velocity.z).length()
	set(value):
		var flat := Vector2(velocity.x, velocity.z)
		var dir: Vector2
		if flat.length_squared() > 0.00000001:
			dir = flat.normalized()
		else:
			# Stopped, so there is no travel direction to preserve: accelerate along the board.
			var axis := _board_axis()
			dir = Vector2(axis.x, axis.z)
		velocity.x = dir.x * value
		velocity.z = dir.y * value

## Vertical component of `velocity`, under the name the airborne path and the HUD already used.
## A bridge, not a second variable: two independent velocity representations is exactly the kind of
## split that produced this system's earlier bugs.
var vertical_velocity: float:
	get: return velocity.y
	set(value): velocity.y = value

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
	_measure_catch_cone()
	_camera_yaw = rotation.y
	_camera_pos = global_position

## Resolves how far off-axis the deck may be at touchdown and still be caught. Two independent
## physical limits, whichever binds first:
##
##   1. FRICTION. The rider stamps the deck flat with the sole of a shoe. The contact normal tilts
##      with the deck, so the flattening force only wins while tan(tilt) <= mu; past that the foot
##      slides down the rail instead and the board squirts out sideways.
##   2. GEOMETRY. Roll far enough and the downhill RAIL reaches the ground before the wheels do.
##      Settling from beyond that angle would visibly drag the deck through the floor.
##
## Both are properties of the board and the shoes, not of the world, so nothing here refers to
## airtime, ledge height, gravity or frame rate - which is the entire point.
func _measure_catch_cone() -> void:
	var friction_cone: float = rad_to_deg(atan(maxf(grip_friction, 0.01)))
	var deck: SkateDeckMesh = board_mesh as SkateDeckMesh
	var box: AABB = deck.deck_extents() if deck != null else AABB()
	deck_half_width = maxf(absf(box.position.x), absf(box.end.x))
	deck_underside_y = box.position.y
	if deck_half_width <= 0.0001:
		push_warning("SkaterController: deck shell not measurable (no visible mesh matching \"board\"); "
			+ "catch cone falls back to the friction cone alone, with no rail-strike clamp.")
		catch_cone_deg = friction_cone
		return
	# Low rail height while rolled by t, in rig-local metres:
	#     y(t) = deck_underside_y * cos(t) - deck_half_width * sin(t)  ==  R * cos(t + phase)
	# with R the rail's distance from the roll axis. It touches down when y(t) == -ride_height.
	# R <= ride_height means the rail can never reach the ground, so only friction binds.
	var radius: float = sqrt(deck_underside_y * deck_underside_y + deck_half_width * deck_half_width)
	if radius <= ride_height:
		catch_cone_deg = friction_cone
		return
	var phase: float = atan2(deck_half_width, deck_underside_y)
	var rail_strike: float = rad_to_deg(acos(clampf(-ride_height / radius, -1.0, 1.0)) - phase)
	catch_cone_deg = minf(friction_cone, maxf(rail_strike, 0.0))

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

## Eases the chase camera's yaw toward the rig's, so a landing that jumps the rig's heading does not
## jump the view with it. Deliberately smooths yaw ONLY: the pivot's baked pitch and offset are what
## frame the shot, and it stays on SkaterRoot rather than BoardPivot so the view never rolls with a
## ramp or spins with a trick.
##
## Chase camera: a spring arm orbiting the skater.
##
## THE INVARIANT: position and aim must come from the SAME smoothed yaw. Break it and the subject
## leaves the frame. It was broken here once, and the failure is worth recording because it did not
## look like a framing bug - it read as "the pan is too slow". CameraPivot used to CARRY the boom
## offset, so it sat 2.1 m behind the skater and rotating it spun the camera on the spot, like
## turning your head while standing still. Rig yaw was inherited rigidly, so on an imperfect landing
## the camera's POSITION whipped round instantly while only its AIM was smoothed. Measured on a
## 70 deg landing: the skater sat 60.8 deg off the centre of view - outside the frame entirely - and
## took 1.2 s to come back. The boom now lives on Camera3D and this node orbits the rig origin, so
## rotating it walks the camera AROUND the skater while it keeps facing them.
##
## Two yaw rates, because ground turns and landing swings want opposite things: steering tracks
## tightly via camera_follow_speed, while a landing dumps its residual into a spring-damped offset so
## the view does not jump at the moment of contact.
func _smooth_camera(delta: float) -> void:
	# Critically damped spring on the absorbed jump: accel toward zero, minus velocity damping.
	var accel: float = -camera_recenter_speed * camera_recenter_speed * _camera_jump_offset \
		- 2.0 * camera_recenter_speed * _camera_jump_vel
	_camera_jump_vel += accel * delta
	_camera_jump_offset += _camera_jump_vel * delta

	var target: float = rotation.y + _camera_jump_offset
	_camera_yaw = lerp_angle(_camera_yaw, target, minf(camera_follow_speed * delta, 1.0))
	# CameraPivot is a child of SkaterRoot, so its world yaw is rotation.y plus its own local yaw.
	# Solve for the local angle that lands it on the smoothed world yaw.
	camera_pivot.rotation.y = angle_difference(rotation.y, _camera_yaw)

	# Follow position, velocity fed forward so constant-speed riding has zero lag and the authored
	# framing is untouched. Only changes in motion make the camera fall behind.
	_camera_pos += velocity * delta
	_camera_pos = _camera_pos.lerp(global_position, minf(camera_position_damp * delta, 1.0))
	camera_pivot.global_position = _camera_pos

## The wheels' rolling axis in world space, flattened and normalised.
##
## Read from the RIG yaw, which is where landing residuals are deposited (see the transfer in
## _evaluate_touchdown_landing). board_pivot carries only the 0/180 switch-stance flip, and a 180
## leaves the rolling axis on the same LINE anyway - a board rolls equally well either way round -
## so it cannot contribute here.
func _board_axis() -> Vector3:
	var axis: Vector3 = -global_transform.basis.z
	axis.y = 0.0
	if axis.length_squared() < 0.0001:
		return Vector3.FORWARD
	return axis.normalized()

## Ground dynamics: slope gravity, wheel grip and rolling friction.
##
## These three used to be, respectively: absent entirely, a snap-to-perfect plus a fixed angle bail,
## and a scalar decrement. They are one function now because they are one phenomenon - a contact
## patch that is free along one axis, gripping across it, and pulled downhill by gravity.
##
## Height is NOT integrated here. While grounded the surface snap owns it outright, so this only ever
## needs the horizontal projection of the along-slope acceleration, and y is pinned to zero.
func _apply_ground_forces(delta: float) -> void:
	velocity.y = 0.0
	if not surface_hit.valid:
		return

	# Fall line: gravity with its surface-normal component removed. On flat ground this is exactly
	# zero, so there is no "am I on a slope" branch anywhere - flat is just the degenerate case.
	var g: Vector3 = Vector3.DOWN * gravity_accel
	var fall_line: Vector3 = g - surface_hit.normal * g.dot(surface_hit.normal)
	var flat := Vector3(velocity.x + fall_line.x * delta, 0.0, velocity.z + fall_line.z * delta)

	# Wheel anisotropy. Everything about imperfect landings falls out of this split: the component
	# along the rolling axis survives, the component across it is scrubbed off against grip. That
	# scrub IS the speed penalty - landing 5 deg off costs cos(5 deg), i.e. almost nothing, while
	# landing 60 deg off costs most of your speed. Carving pays the same toll, which is why steering
	# now has weight to it.
	_since_touchdown += delta
	var axis: Vector3 = _board_axis()
	var lateral: Vector3 = flat - axis * flat.dot(axis)
	# While realigning from a landing, cap the lateral force at whatever turns travel no faster than
	# landing_turn_rate_deg. Lateral speed relates to heading as v_lat ~= speed * angle, so bounding
	# the force to speed * angular_rate bounds the angle swing directly, at any speed.
	var grip: float = wheel_side_grip
	if _realigning:
		grip = minf(grip, flat.length() * deg_to_rad(landing_turn_rate_deg))
		if lateral.length() < 0.02:
			_realigning = false
	flat += lateral.move_toward(Vector3.ZERO, grip * delta) - lateral

	# Rolling friction opposes travel and can never reverse it. move_toward lands exactly on zero, so
	# a gradient whose fall line is weaker than friction simply has everything gravity just added
	# taken back off again, and the skater holds still - no jitter, no static-friction special case,
	# and no clamp. Steeper than that and the remainder accelerates them downhill; steep enough while
	# stalled and they roll back down, because nothing here privileges the forward direction.
	flat = flat.move_toward(Vector3.ZERO, rolling_friction * delta)
	velocity.x = flat.x
	velocity.z = flat.z

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
	#
	# The old first clause here was `if vertical_velocity > 0.05: is_grounded = false`. It had to go
	# once slopes went live: velocity is no longer purely horizontal in intent, and any test of world
	# Y against zero misreads a skater rolling uphill as one leaving the ground. It was only ever a
	# belt-and-braces guard - the pop in step 5 sets is_grounded = false explicitly, and nothing else
	# can lift the skater off a surface - so removing it costs nothing.
	surface_hit = _probe_surface()
	if not surface_hit.valid:
		is_grounded = false # Nothing underneath - rolled off a ledge, no special case needed.
	elif is_grounded:
		is_grounded = global_position.y - _surface_ride_y() <= ground_snap_distance

	# Synchronize all kinematic animations and stance updates to physics tick
	_animate_ankle_pegs(delta)
	_animate_foot_push_stroke(delta)
	_apply_surface_alignment(delta)
	# Pass SkaterRoot, not board_pivot: update_stance_facts() reads pivot.get_parent() for the
	# stationary forward vector, and that parent is now the surface-tilted SurfaceAlign node.
	# Horizontal velocity only. `velocity` now carries the ballistic vertical speed too, and during a
	# pop that term dominates - passing it whole would point the travel vector nearly straight up and
	# scramble the leading/trailing foot test for the whole flight.
	input_state.update_stance_facts(board_pivot, left_foot, right_foot,
		Vector3(velocity.x, 0.0, velocity.z), self)
	
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
	
	# 3. Ground dynamics: slope gravity, wheel grip and rolling friction in one pass.
	if is_grounded:
		_apply_ground_forces(delta)
	
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

		# Where the deck actually was when the trick started, so touchdown can measure what it turned
		# through rather than assuming it turned through whatever was requested here.
		_pop_board_roll = board_mesh.rotation_degrees.z
		_pop_board_yaw = board_mesh.rotation_degrees.y

		# Configure BoardMesh flip & spin targets (Layer 3). Only the deck's own 180 deg yaw reversal
		# after a Shove-it needs compensating here - Nollie/Fakie flip mirroring is already applied
		# in FootInputState._build_trick_signature(), so there is no stance term.
		#
		# Targets are built off the nearest RESTING orientation, not off the raw current angle: popping
		# again mid-settle would otherwise bake the few unsettled degrees in permanently, and every
		# later trick would inherit the error. When the deck is already at rest - the normal case -
		# rounding is a no-op and the target is unchanged.
		var roll_rest: float = _nearest_multiple(board_mesh.rotation_degrees.z, 360.0)
		var yaw_rest: float = _nearest_multiple(board_mesh.rotation_degrees.y, 180.0)
		var deck_reversed: bool = cos(deg_to_rad(board_mesh.rotation_degrees.y)) < 0.0
		var roll_sign: float = -1.0 if deck_reversed else 1.0
		if sig.flip == TrickSignature.Flip.KICK:
			target_board_roll = roll_rest + (360.0 * roll_sign)
			is_flip_in_progress = true
		elif sig.flip == TrickSignature.Flip.HEEL:
			target_board_roll = roll_rest - (360.0 * roll_sign)
			is_flip_in_progress = true
		else:
			target_board_roll = roll_rest

		# Spin magnitude comes from the measured signature, never from the display name.
		if sig.shuv_deg != 0:
			var spin_deg: float = 360.0 if absi(sig.shuv_deg) == 360 else 180.0
			target_board_yaw = yaw_rest + (spin_deg * input_state.last_scoop_sign)
			is_flip_in_progress = true
		else:
			target_board_yaw = yaw_rest

		# The flip loop now owns BoardMesh; any settle still running is superseded by it.
		if is_flip_in_progress:
			is_flip_settling = false
		_impart_deck_rotation(sig)
	
	# 5b. Carry a late-caught deck the last few degrees onto its resting orientation.
	#
	# Deliberately BEFORE the flight block, not after it. Touchdown is resolved inside step 6, so a
	# settle called afterwards would advance on the very frame the flip integrator already advanced,
	# rotating the deck twice in one tick. Running first means the settle only ever picks up on the
	# frame after the catch, and the deck turns at exactly one rate at all times.
	_advance_flip_settle(delta)

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
		
		# Layer 3: Deck Flip & Spin Authority on BoardMesh with Shoe Hover Catching.
		# Rates were fixed at the pop and are simply integrated here; both axes were scaled to the
		# same trick duration, so they arrive together on the same frame however they are combined.
		if is_flip_in_progress:
			board_mesh.rotation_degrees.z = move_toward(board_mesh.rotation_degrees.z, target_board_roll, absf(flip_roll_rate) * delta)
			board_mesh.rotation_degrees.y = move_toward(board_mesh.rotation_degrees.y, target_board_yaw, absf(flip_yaw_rate) * delta)

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
			# Sample the impact BEFORE it is zeroed - it is the only measure of how hard this landing
			# was, and one line later it is gone.
			var impact: float = absf(vertical_velocity)
			global_position.y = _surface_ride_y()
			vertical_velocity = 0.0
			is_grounded = true
			_since_touchdown = 0.0
			_realigning = true
			if landing_dip_ref_speed > 0.0:
				_landing_dip = minf(impact / landing_dip_ref_speed, 1.0) * landing_dip_max
			current_aerial_spin_rate = 0.0
			input_state.current_pop_state = FootInputState.PopState.NONE
			_evaluate_touchdown_landing()
	
	# 7. Position integration, blocked by vertical faces. `velocity` is authoritative and is NOT
	# rebuilt from orientation here - that rebuild was the whole bug. Only the horizontal components
	# move the skater; while grounded the surface snap just below owns height entirely.
	var travel: Vector3 = Vector3(velocity.x, 0.0, velocity.z) * delta
	if _blocked_by_wall(travel):
		# Scales rather than zeroing so wall_stop_damping keeps meaning "fraction of speed retained".
		velocity.x *= wall_stop_damping
		velocity.z *= wall_stop_damping
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

	# 8c. Let the suspension extend back out, and ease the camera toward the rig's heading.
	_landing_dip = lerpf(_landing_dip, 0.0, minf(landing_dip_recover * delta, 1.0))
	surface_align.position.y = -_landing_dip
	_smooth_camera(delta)

	# 9. Re-seat the board onto its contact axle. Runs last, after every writer of board_pivot pitch
	# (the pop in step 5, airborne pitch in step 6, grounded manuals just above).
	_apply_manual_pivot()

## Nearest orientation in which the deck is at rest: griptape up for roll (multiples of 360), wheels
## running along the deck's long axis for yaw (multiples of 180, since a board rides either way).
static func _nearest_multiple(value: float, step: float) -> float:
	return roundf(value / step) * step

## Sets the deck's angular velocity for the trick just popped, scaling BOTH axes onto one shared
## duration so they finish together.
##
## A trick is one event: the rider flicks and scoops in a single motion and catches the board once,
## with both rotations complete. Driving roll and yaw at independent fixed rates broke that - a 360
## flip's yaw ran at spin_speed_deg * 2 (0.42 s) while its roll ran at flip_speed_deg (0.59 s), so
## the deck finished spinning a fifth of a second before it finished flipping. On screen the board
## stopped rotating on one axis mid-trick and kept going on the other, then stopped dead.
##
## The duration is the SLOWER of the two axes' natural times, and the faster axis is slowed to match.
## Scaling to the faster one instead would speed rotations up beyond their tuned reference rates and
## shorten every combined trick. Single-axis tricks have nothing to reconcile, so their timing is
## exactly what it always was.
func _impart_deck_rotation(sig: TrickSignature) -> void:
	var roll_sweep: float = target_board_roll - board_mesh.rotation_degrees.z
	var yaw_sweep: float = target_board_yaw - board_mesh.rotation_degrees.y
	# Reference rate each axis would run at alone. The 360 shuv keeps its historical doubling, which
	# is what makes a tre flip's scoop read as sharper than its flip rather than lazier.
	var yaw_ref: float = spin_speed_deg * (2.0 if absi(sig.shuv_deg) == 360 else 1.0)
	var roll_time: float = absf(roll_sweep) / flip_speed_deg if flip_speed_deg > 0.0 else 0.0
	var yaw_time: float = absf(yaw_sweep) / yaw_ref if yaw_ref > 0.0 else 0.0
	var trick_time: float = maxf(roll_time, yaw_time)
	if trick_time <= 0.0:
		flip_roll_rate = 0.0
		flip_yaw_rate = 0.0
		return
	flip_roll_rate = roll_sweep / trick_time
	flip_yaw_rate = yaw_sweep / trick_time

## Rotates a late-caught deck onto its resting orientation at the flip's own angular rate.
##
## This is the whole reason a late catch does not look like a glitch. The board is never teleported
## flat; the rotation it already carried keeps integrating for the few frames it takes to arrive, so
## on screen the flip simply finishes under the rider's feet as they land - which is what a real late
## catch looks like. Always rotates the SHORT way to the nearest resting orientation, so a flip that
## barely started settles back the way it came instead of grinding out a full turn it never earned.
func _advance_flip_settle(delta: float) -> void:
	if is_flip_in_progress or not is_flip_settling:
		return
	# Recomputed per frame, but stable: move_toward only ever approaches the target, so the nearest
	# resting orientation cannot change midway.
	var roll_target: float = _nearest_multiple(board_mesh.rotation_degrees.z, 360.0)
	var yaw_target: float = _nearest_multiple(board_mesh.rotation_degrees.y, 180.0)
	# Carry the deck's own angular velocity through the catch rather than switching to a different
	# rate at the moment of contact - a speed change mid-rotation reads as a hitch even when the
	# motion stays continuous. Falls back to the reference rates for an axis that was not turning.
	var roll_rate: float = absf(flip_roll_rate) if absf(flip_roll_rate) > 1.0 else flip_speed_deg
	var yaw_rate: float = absf(flip_yaw_rate) if absf(flip_yaw_rate) > 1.0 else spin_speed_deg
	board_mesh.rotation_degrees.z = move_toward(board_mesh.rotation_degrees.z, roll_target, roll_rate * delta)
	board_mesh.rotation_degrees.y = move_toward(board_mesh.rotation_degrees.y, yaw_target, yaw_rate * delta)
	if is_equal_approx(board_mesh.rotation_degrees.z, roll_target) \
			and is_equal_approx(board_mesh.rotation_degrees.y, yaw_target):
		is_flip_settling = false
		board_mesh.rotation_degrees.z = fmod(roll_target, 360.0)
		board_mesh.rotation_degrees.y = fmod(yaw_target, 360.0)

## Rewrites the signature to the rotation the deck ACTUALLY completed.
##
## Catching on orientation alone would otherwise credit the full trick however little the deck turned:
## a board that had barely begun to flip is also within a few degrees of griptape-up, so popping onto
## a high ledge would land and be named a kickflip. Orientation decides whether it is RIDEABLE; the
## sweep achieved since the pop decides what it is CALLED. A 360 shuv that only made it half way is
## credited as the 180 it actually did.
func _credit_achieved_rotation() -> void:
	var sig: TrickSignature = input_state.current_trick
	if sig.flip != TrickSignature.Flip.NONE:
		var roll_turns: int = int(roundf((board_mesh.rotation_degrees.z - _pop_board_roll) / 360.0))
		if roll_turns == 0:
			sig.flip = TrickSignature.Flip.NONE
	if sig.shuv_deg != 0:
		var achieved: int = absi(int(roundf((board_mesh.rotation_degrees.y - _pop_board_yaw) / 180.0)))
		var intended: int = absi(sig.shuv_deg) / 180
		if achieved < intended:
			sig.shuv_deg = achieved * 180 * signi(sig.shuv_deg)

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
	last_catch_error_deg = 0.0

	# Primo / Incomplete Flip Check.
	#
	# Judged on where the deck IS, not on whether a fixed-duration animation finished. The old test
	# was `is_flip_in_progress`, which is true until the deck sweeps a full 360 at flip_speed_deg -
	# a constant 0.60 s regardless of hang time. Hang time, meanwhile, shrinks with the height gained
	# from takeoff surface to landing surface, so popping onto a 0.30 m curb gave 0.58 s and every
	# kickflip onto it bailed one frame short, deterministically. Nothing below reads airtime, ledge
	# height, gravity or frame rate; re-tuning any of them can no longer make a trick unlandable.
	if is_flip_in_progress or is_flip_settling:
		var roll_err: float = absf(board_mesh.rotation_degrees.z - _nearest_multiple(board_mesh.rotation_degrees.z, 360.0))
		var yaw_err: float = absf(board_mesh.rotation_degrees.y - _nearest_multiple(board_mesh.rotation_degrees.y, 180.0))
		var catch_err: float = maxf(roll_err, yaw_err)
		last_catch_error_deg = catch_err
		if catch_err > catch_cone_deg:
			input_state.trick_status_string = "BAIL! (Primo Crash / Incomplete Flip)"
			current_speed = 0.0
			board_mesh.rotation_degrees.z = 0.0
			board_mesh.rotation_degrees.y = 0.0
			is_flip_in_progress = false
			is_flip_settling = false
			manual_timer = 0.0
			return
		# Caught. Only the component of momentum still aligned with the roll direction survives the
		# stamp that flattens the deck, so a dead-flat catch keeps everything and one out at the edge
		# of the cone costs ~30%. Execution deliberately falls through from here into the manual and
		# landing checks below: the old early `return` skipped them, which is why an incomplete flip
		# presented as "manuals do not work after a flip trick" rather than as a failed landing.
		is_flip_in_progress = false
		is_flip_settling = true
		current_speed *= cos(deg_to_rad(catch_err))
		_credit_achieved_rotation()

	# Land on the heading actually achieved, instead of snapping to a perfect 0/180.
	#
	# The residual is TRANSFERRED to the rig yaw rather than discarded. board_pivot keeps only the
	# 0/180 switch-stance flip that every `cos(board_pivot.rotation_degrees.y)` test downstream
	# depends on, while the rig - which is what _board_axis() reads, what steering turns and what the
	# camera follows - genuinely points where the rider landed. Land a 180 at 185 deg and you ride
	# away 5 deg off your old line and have to steer out of it; the error does not silently vanish.
	#
	# The trick NAME is unaffected: _finalise_trick_name() already rounds body yaw to half-turns, so
	# 185 deg still reads as a 180. Naming quantises, physics does not.
	#
	# On a tilted surface the rig and pivot yaws are separated by SurfaceAlign's pitch and roll, so
	# this transfer is exact only on flat ground. At plausible landing residuals and ramp angles the
	# error stays well under a degree - not worth carrying a quaternion for.
	var rest_yaw: float = _nearest_multiple(board_pivot.rotation_degrees.y, 180.0)
	var residual: float = deg_to_rad(board_pivot.rotation_degrees.y - rest_yaw)
	rotate_y(residual)
	board_pivot.rotation_degrees.y = fmod(rest_yaw, 360.0)
	# Hand the jump to the camera to absorb rather than inherit. The rig turns instantly - the board
	# really is pointing somewhere new the moment it touches down - but the VIEW should not teleport
	# with it, so the offset cancels the change at this instant and gives it back over the next few
	# frames. Without this the camera whipped by the whole residual in a single frame.
	_camera_jump_offset -= residual
	_camera_jump_vel = 0.0

	# Sideways landing, judged on MOMENTUM rather than angle. Wheels hold only so much lateral speed
	# before washing out, so the identical 90 deg landing is survivable at walking pace and fatal at
	# full speed - a distinction the old fixed 45-135 deg window could not express at all. Anything
	# under the limit is not "forgiven" either: the lateral component is still scrubbed off against
	# grip by _apply_ground_forces(), so a sketchy landing costs real speed.
	var flat_v := Vector3(velocity.x, 0.0, velocity.z)
	var land_axis: Vector3 = _board_axis()
	last_landing_slide = (flat_v - land_axis * flat_v.dot(land_axis)).length()
	if last_landing_slide > max_landing_slide:
		input_state.trick_status_string = "BAIL! (Sideways Landing / Wheel Skid)"
		current_speed = 0.0
		board_pivot.rotation_degrees.x = 0.0
		manual_timer = 0.0
		return

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
