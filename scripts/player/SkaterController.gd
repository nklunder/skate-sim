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
## Rider-relative pitch past which a touchdown counts as landing INTO a manual rather than flat.
@export var manual_catch_min_pitch_deg: float = 5.0
## Deck pitch at full manual extension, and the ceiling airborne stick pitch works against.
@export var max_pitch_deg: float = 24.0
## Maximum pop kicktail pitch angle reached during a full-impulse ollie or vertical pop.
@export var pop_pitch_deg: float = 50.0
## Exponent applied to vertical velocity ratio during pop ascent; higher values rapidly level initial tilt into a horizontal float.
@export var pop_leveling_exponent: float = 2.5
## Stick deflection below which airborne pitch input is ignored.
@export var pitch_stick_deadzone: float = 0.15
## Lerp rates the deck pitches toward its target at, airborne and grounded.
@export var airborne_pitch_follow: float = 14.0
@export var grounded_pitch_follow: float = 16.0
## Speed threshold (in m/s) below which trigger turns lift front trucks for a stationary kickturn instead of carving.
@export var kickturn_max_speed: float = 0.5
## Automatic board pitch angle (in degrees) when initiating a slow-speed kickturn to lift the front wheels.
@export var kickturn_pitch_deg: float = 10.0
var manual_timer: float = 0.0
var is_grounded: bool = true
var _is_carve_latched: bool = false

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
## The chase camera. Everything about HOW it frames the skater lives on ChaseCamera.gd; the rig only
## decides WHEN it advances, by calling follow() at the end of the frame pipeline.
@onready var camera_pivot: ChaseCamera = $CameraPivot
## Below this ground speed the direction of travel is treated as unreadable and the last known
## heading is held instead.
##
## The heading of a near-zero velocity is noise, and that is precisely the state at the top of a
## bank in the instant before a reversal. Lives here rather than on the camera because travel is a
## physics quantity: both the camera's heading and the rolling-direction sign below ask this same
## question, and they must not be able to disagree about the answer.
@export var travel_min_speed: float = 0.6
## Persistent travel direction sign along the board's rolling axis (+1.0 for forward, -1.0 for backward).
## Updated above travel_min_speed so when stalling to a stop, pushing and stance checks preserve
## rolling direction instead of resetting to static rig forward.
var _travel_axis_sign: float = 1.0

@export_category("Aerial & Jump Physics")
@export var jump_impulse: float = 5.2
## Maximum sideways jump velocity (in m/s) imparted when aiming the pop thumbstick off-center.
@export var max_lateral_pop_impulse: float = 1.5
## Slight natural board yaw offset (in degrees) imparted during directed lateral jumps.
@export var lateral_pop_yaw_deg: float = 5.0
## Also sets which gradients hold the skater, via rolling_friction - see that field.
@export var gravity_accel: float = 16.0
# vertical_velocity now lives with `velocity` under Motion & Push Physics: it is velocity.y, not a
# variable of its own. Two velocity representations was the split this rewrite removed.

@export_category("Flip & Spin Physics (3-Layer Hierarchy)")
@export var flip_speed_deg: float = 1020.0
@export var spin_speed_deg: float = 540.0
## Gyroscopic coupling factor: adds rotational inertia to multi-axis tricks (e.g. 360 flips) so they complete later.
@export var rotational_complexity_coupling: float = 0.15

@export_group("Flick Intensity")
## Flick speed, in stick-deflection units per second, that produces the REFERENCE rotation rate -
## i.e. the rate the deck turned at before flick speed was consumed at all.
##
## Measured throws at 60 Hz, from a 0.7 deflection: 1 frame = 42, 2 = 21, 3 = 14, 5 = 8.4, 12 = 3.5.
## 14 is a brisk three-frame throw, so an ordinary flick lands on 1.0x and the tuning below only
## has to describe the deviation.
@export var flick_reference_speed: float = 14.0
## How much rotation rate follows flick speed. 0 ignores it entirely and restores a fixed rate.
@export_range(0.0, 2.0) var flick_rate_sensitivity: float = 0.5
## Bounds on the multiplier. The FLOOR is the important one: a soft flick should turn the deck
## lazily and risk an incomplete trick, not guarantee a primo - the rider should be able to see it
## failing and still catch it.
@export var flick_rate_min: float = 0.6
@export var flick_rate_max: float = 1.6
## Where each axis is heading. DERIVED from the turn counts below, never fixed at the pop - see
## _refresh_rotation_targets().
var target_board_roll: float = 0.0
var target_board_yaw: float = 0.0
## Rest-periods each axis has been asked to turn through, and the orientation and direction it
## started from. Roll rests every 360 deg (griptape up again); yaw rests every 180 (a deck half a
## turn round is the same deck).
##
## THE TURN COUNT IS THE IRREDUCIBLE STATE, and it is the reason held rotation is a one-line
## extension rather than a rewrite. Geometry alone cannot say when a trick is over: a 360 scoop
## passes THROUGH a resting orientation at 180, and stopping there would be wrong. How many turns
## were asked for is rider intent, not something the deck's angle can be asked about. Expressing the
## target as `rest + period * turns * direction` keeps that intent in one growable number, while the
## RATE stays constant and independent of it - so asking for another turn costs nothing and
## re-derives nothing. Fixing an absolute target at the pop is what made "keep spinning while held"
## impossible without moving a goalpost that four other systems were keyed to.
var flip_roll_turns: int = 0
var flip_yaw_turns: int = 0
var _roll_rest_at_pop: float = 0.0
var _yaw_rest_at_pop: float = 0.0
var _roll_turn_dir: float = 0.0
var _yaw_turn_dir: float = 0.0
## Signed deg/s imparted to the deck at the pop, then held constant - airborne there is no torque on
## the board, so constant angular velocity is the physically correct integration.
##
## Both axes are scaled to share ONE trick duration. Driving them at independent fixed rates meant a
## 360 flip's yaw finished at 0.42 s while its roll was only 253 deg round, so the board visibly
## stopped spinning and kept flipping, then halted - see AGENTS.md.
var flip_roll_rate: float = 0.0
var flip_yaw_rate: float = 0.0
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
var _takeoff_vertical_velocity: float = 0.0
var _initial_pop_pitch_deg: float = 0.0
## Raw world body yaw accumulated between pop and touchdown. Rider-normalised only when it is
## folded into the trick signature, so this stays comparable with board_pivot.rotation_degrees.y.
var airborne_body_yaw_deg: float = 0.0
## Whether the rider was riding reversed (switch / fakie) at the moment of the pop. Sampled from
## the pivot's real yaw rather than inferred, and captured at pop because the yaw changes in flight.
var pop_riding_reversed: bool = false

## What the rider is doing with the controller, and where their feet are on the deck.
@onready var rider: RiderInput = $RiderInput
## What that adds up to as an attempted trick. A child of RiderInput so it ticks straight after it.
@onready var trick: TrickState = $RiderInput/TrickState
## Carries ONLY surface pitch/roll. Deliberately a separate node from BoardPivot: that one's X is
## trick pitch (written by the manual/pop systems and read back by landing checks), so sharing the
## channel would corrupt manuals, wheel-bite detection and pops. CameraPivot stays on SkaterRoot so
## the chase camera does not roll with the ramp.
@onready var surface_align: Node3D = $SurfaceAlign
@onready var rider_body: RiderBody = $SurfaceAlign/RiderTorso
@onready var board_pivot: Node3D = $SurfaceAlign/BoardPivot
@onready var board_mesh: Node3D = $SurfaceAlign/BoardPivot/BoardMesh
## The rider's feet and every animation that moves them. Presentation only - see FootRig.gd, and
## note that this is now structural rather than a convention: the stance test below consumes the
## shoes' REST offsets, so no live foot position feeds any decision at all.
@onready var foot_rig: FootRig = $SurfaceAlign/BoardPivot/FootRig
## Reused each frame rather than allocated, since it is pure parameter passing. Everything FootRig
## is allowed to know about the frame it is posing for goes through here - it holds no reference
## back to this controller.
var _foot_frame := FootRig.Frame.new()

@export_category("Motion & Push Physics")
@export var max_push_speed: float = 7.0 # Ceiling on PUSHING only - gravity may exceed it downhill.
@export var push_impulse: float = 2.0
## How long a push stroke occupies the rider, in seconds. Nominally the same as FootRig's
## push_anim_duration, but kept here and separate on purpose: this is the PHYSICAL duration, and no
## gameplay term may be gated on how long an animation happens to run.
@export var push_stroke_time: float = 0.25
## Steering authority retained while loading a pop, when the rider's weight has shifted onto the
## tail ready to snap it down. Registered as a contributor in _lean_authority().
@export_range(0.0, 1.0) var pop_load_turn_damping: float = 0.2
## Steering authority retained at the START of a push stroke, easing back to full as it finishes.
##
## On a real board you cannot carve while pushing, and the reason is anatomical rather than
## frictional: carving is done by leaning the deck on its bushings, which needs the rider's weight
## over both trucks. During a push one foot is on the ground and the weight is centred over the
## front truck, so there is nothing left to lean WITH.
##
## Ramped rather than switched. Steering authority returns as the foot comes back to the deck, which
## is both what actually happens and smoother than a step change - a hard restore at the end of the
## stroke reads as the board suddenly grabbing.
@export_range(0.0, 1.0) var push_turn_damping: float = 0.15
## Seconds since the last push impulse. Also the natural home for a physical push cooldown, if
## kicking should ever be rate-limited: gate _apply_push_impulse() on this rather than on whether
## FootRig happens to be mid-stroke.
var _since_push: float = 1000.0
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
## Largest heading error the paced realignment above will cover, in degrees. Beyond it, the excess
## is scrubbed by wheel_side_grip at full strength instead.
##
## This is the DOMAIN of that pacing, not a tuning knob for its feel. The budget works by the
## small-angle relation v_lat ~= speed * angle, which needs an along-axis component to rotate travel
## toward. Land with no forward speed at all - a standing directional pop, which leaps purely
## sideways - and the angle is 90 deg, the approximation is meaningless, and draining at
## speed * angular_rate rotates nothing. It just decays the speed linearly over ~1 s while grip,
## which would have stopped it in 28 ms, never engages at all because lateral never exceeds the
## budget. The board slid sideways across the ground like ice.
##
## Expressed as an ANGLE rather than a speed so it scales with how fast the rider arrived: the
## question "is this a heading to be swung into line, or a skid the wheels should fight?" is about
## the direction of travel, not its magnitude. 45 deg is the diagonal - past it, more of the motion
## is across the wheels than along them, which is a skid by any reading.
@export var max_realign_angle_deg: float = 45.0
## Sideways speed still owed from the last landing, in m/s. A BUDGET that only ever shrinks - never
## a state flag inferred from live lateral speed.
##
## That distinction is the whole fix for the landing skid. The old version was a boolean latch that
## capped grip and cleared itself once live lateral fell under 0.02 m/s. But steering GENERATES
## lateral speed, and at full lean it generates it faster than the capped grip removes it - so
## holding a trigger through a touchdown meant the clear condition never arrived, the cap never
## lifted, and the board slid sideways for as long as the trigger was held. Weak grip kept lateral
## high, and high lateral kept grip weak: a positive feedback loop the rider drove directly.
##
## The flaw underneath was that one number could not tell two things apart - sideways speed LEFT
## OVER from the landing, which should be worked off smoothly at a paced rate, and sideways speed
## the rider is CREATING right now by carving, which the wheels should fight at full strength.
## Recording the residual explicitly at touchdown separates them: it decays on its own schedule and
## nothing the rider does can top it back up.
var _landing_residual: float = 0.0
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

## Horizontal rolling speed. READ ONLY, and deliberately so.
##
## It was briefly settable, rescaling the horizontal velocity in place to spare the call sites. That
## is a magnitude abstraction sitting on a vector, and it silently means "change my speed but keep my
## current direction" - correct for a crash, wrong for a push, with nothing to mark the difference.
## It produced exactly one bug and would have produced more: pushing while drifting even slightly
## sideways scaled the sideways component up along with the forward one, so a kick could accelerate
## the skater along a crooked line instead of straightening it out.
##
## Anything that changes motion now states what it physically does to the VECTOR - see
## _apply_push_impulse() for a directed drive and _kill_momentum() for a crash.
var current_speed: float:
	get:
		return Vector2(velocity.x, velocity.z).length()

## LIVE sideways speed across the wheels' rolling axis - the quantity grip is actively scrubbing off
## right now. Computed, never stored, for the same reason `current_speed` is: `velocity` plus the rig
## yaw already determine it completely, and a cached copy could disagree with them.
##
## Distinct from `last_landing_slide`, which is a LATCHED sample of this taken at touchdown and held
## until the next one. Conflating the two is what made a stale HUD reading look like a physics leak:
## the snapshot is meant to persist, and the live value decays to zero within about half a second.
var lateral_speed: float:
	get:
		var flat := Vector3(velocity.x, 0.0, velocity.z)
		var axis: Vector3 = _board_axis()
		return (flat - axis * flat.dot(axis)).length()

## Vertical component of `velocity`, under the name the airborne path and the HUD already used.
## A bridge, not a second variable: two independent velocity representations is exactly the kind of
## split that produced this system's earlier bugs.
var vertical_velocity: float:
	get: return velocity.y
	set(value): velocity.y = value

func _ready() -> void:
	var exclude: Array[RID] = []
	_probe = SurfaceProbe.new(get_world_3d().direct_space_state, exclude)
	_measure_catch_cone()

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

## A push drives the board along its ROLLING AXIS, in whichever direction it is already rolling.
##
## Emphatically not along the current travel vector: drifting even slightly sideways, that would
## scale the sideways component up with the forward one and accelerate the skater along a crooked
## line. Adding only along the axis leaves the lateral component alone for grip to scrub off, so a
## push actively straightens a crooked roll instead of entrenching it.
##
## Riding fakie is not a special case - the axis is a LINE, and the sign comes from which way the
## skater is already travelling along it. Stationary, it defaults to the board's forward.
func _apply_push_impulse() -> void:
	var axis: Vector3 = _board_axis()
	var dir: Vector3 = axis if _travel_axis_sign >= 0.0 else -axis
	# The ceiling is on SPEED, so it is measured against total ground speed rather than against the
	# along-axis component. Clamping the component instead let a push top that component up to the
	# full 7 m/s while a sideways drift sat on top of it, so pushing out of a crooked landing reached
	# 8.3 m/s - over a ceiling the rest of the game treats as absolute.
	#
	# The impulse is still applied purely along the rolling axis: that is what lets grip scrub the
	# lateral component away and straighten a crooked roll, rather than entrenching it.
	#
	# maxf guards the downhill case: gravity can legitimately carry the skater past max_push_speed,
	# and a push must never become a brake.
	var speed: float = current_speed
	var add: float = maxf(0.0, minf(speed + push_impulse, max_push_speed) - speed)
	velocity.x += dir.x * add
	velocity.z += dir.z * add

## Stops the skater dead. Horizontal only: vertical is owned by the airborne path and the ride-height
## snap, and zeroing it here would swallow a fall in progress.
func _kill_momentum() -> void:
	velocity.x = 0.0
	velocity.z = 0.0

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

# =================================================================================================
# RIG FRAMES - every orientation conversion in the project, and nowhere else.
#
# THE recurring bug class here (BUG_ARCHIVE #4, #6) is a quantity measured in one frame being used
# in another. The rig has four. SkaterRoot carries the world heading, and TWO SIBLING CHAINS hang
# beneath it - the rider and the board - because they are two bodies, not one:
#
#   frame        adds                                   consumed by
#   ----------   ------------------------------------   ----------------------------------------
#   SkaterRoot   world heading + landing residuals       _board_axis, steering, camera, position
#   RiderTorso   the RIDER's yaw - shoulders, spin       pivot_reversed, i.e. switch/fakie
#   BoardPivot   the BOARD's yaw + manual pitch          trick pitch, manuals, feet, stance facts
#   BoardMesh    the deck's own flip roll + scoop yaw     roll targets, nose/tail identity
#
# RiderTorso and BoardPivot are SIBLINGS, deliberately. The feet stay under BoardPivot - that is
# what makes switch/fakie mirroring inherited rather than compensated for - and only the torso
# separates, which is also the anatomy: feet on the board, shoulders free, twist in between.
#
# BoardPivot's yaw used to carry the rider's 0/180 switch flip AND their accumulated body spin, with
# no way to tell them apart. A boardslide needs the deck 90 deg across the direction of travel while
# the rider still faces near-forward, and that is not expressible while the rider IS the board.
# While the coupling is rigid the two frames move together and every previous figure is reproduced
# exactly; softening the torsion between them is what lets a slide happen.
#
# TrickSignature.gd does exactly this for the two rotation-NAMING frames, and its conversions are
# the only sign logic in this project that has never regressed. This is the same medicine applied
# to the rig itself. Before it existed the seven call sites below each re-derived their own sign,
# independently, and one of them had it backwards for every switch-stance kickturn ever taken.
#
# THE DISTINCTION THAT MATTERS, and the one that caused that bug - these are NOT interchangeable:
#
#   leading_axle_z()   WHERE THE RIDER IS GOING. Which end of the deck travel points toward.
#                      Flips when you roll backwards down a bank, with the board never moving.
#   pivot_reversed()   HOW TWO FRAMES RELATE. Whether BoardPivot is half a turn out of phase with
#                      the rig. Flips when you land a 180, with your travel never changing.
#
# Deriving an axle from the first and then applying it in the rig's frame - without the second -
# is precisely what made every kickturn in switch pivot on the airborne truck.
# =================================================================================================

## BoardPivot-local Z of the axle at the LEADING end - the end travel points toward.
##
## Read off the leading foot's REST offset rather than its live position, so it states which end the
## rider is mounted facing and no animation can perturb it.
func leading_axle_z() -> float:
	var rest: Vector3 = foot_rig.left_rest if rider.leading_foot == RiderInput.Foot.LEFT \
		else foot_rig.right_rest
	return manual_axle_z if rest.z >= 0.0 else -manual_axle_z

## BoardPivot-local Z of the axle at the TRAILING end - the one a pop kicks off, a manual balances
## on, and a kickturn pivots around.
func trailing_axle_z() -> float:
	return -leading_axle_z()

## Maps a rider-relative pitch intent onto BoardPivot's local X axis.
##
## A positive local X pitch drops the +Z end (see _apply_manual_pivot). An OLLIE kicks the TRAILING
## end down, so it wants signf(pitch) == signf(trailing_axle_z()) - which is exactly this value.
## Multiply any "positive means tail down" angle by it before assigning to board_pivot.rotation.x.
func stance_sign() -> float:
	return -1.0 if leading_axle_z() >= 0.0 else 1.0

## The deck's current pitch, read back RIDER-relative: positive is trailing-end-down (a tail
## manual), negative is leading-end-down (a nose manual), whichever way round the rider stands.
## The inverse of stance_sign()'s job, and the reason landing checks do not need their own copy.
func rider_pitch_deg() -> float:
	return board_pivot.rotation_degrees.x * stance_sign()

## True while the RIDER sits half a turn out of phase with the rig: all of switch and fakie, plus
## anything after a landed body 180 (_evaluate_touchdown_landing parks the nearest multiple of 180
## on both frames and hands only the remainder to the rig).
##
## A statement about FRAMES, not about where the rider is going - see the block comment above.
##
## Reads the RIDER's frame, not the board's. Being switch is a fact about the person: it means their
## body faces the opposite way down the line they are travelling. It was previously read off
## BoardPivot only because the rider had no frame of their own to read - the board carried the
## rider's 0/180 flip along with its own yaw, and the two were indistinguishable. They coincide
## while the coupling is rigid, so this is the same answer today; it stops being the same answer the
## moment a slide turns the deck across the rider, which is exactly the case this split exists for.
func pivot_reversed() -> bool:
	return cos(rider_body.rotation.y) < 0.0

## Carries a BoardPivot-local Z into the rig's frame.
##
## Anything that derives a position from BoardPivot-relative facts and then applies it through
## SkaterRoot - rotate_y(), to_global(), global_position - MUST pass through here.
func pivot_z_to_rig(z: float) -> float:
	return -z if pivot_reversed() else z

## True while the DECK ITSELF is turned 180 deg from rest, i.e. after a landed shove-it.
##
## Deliberately distinct from pivot_reversed(): this is the board's own yaw, on BoardMesh, and it
## turns without the rider turning. Nose and tail are attributes of the board, so this - never
## pivot_reversed() - is what decides which physical end a foot is standing over.
func deck_reversed() -> bool:
	return cos(deg_to_rad(board_mesh.rotation_degrees.y)) < 0.0

## Direction a kickflip rolls, compensated for a deck already sitting 180 deg round after a
## shove-it. Note this takes NO stance term: nollie/fakie flip mirroring is applied once, in
## TrickState._build_trick_signature(), and applying it twice cancels it out.
func flip_roll_sign() -> float:
	return -1.0 if deck_reversed() else 1.0

## How much of the rider's weight is available to lean the deck with, from 0 (none) to 1 (all).
##
## Carving works by leaning the deck onto its bushings, which needs weight over both trucks. Every
## body state that takes weight off one of them reduces it, so rather than each such state bolting
## another multiplier onto the steering rate, they are listed here as contributors.
##
## The most restrictive contributor governs rather than the product, because these are ALTERNATIVE
## body positions, not stacking ones - a rider mid-push is not also loading the tail, and
## multiplying two near-zero factors would only produce an authority no state actually calls for.
##
## Grinds and manuals hang off here when they arrive.
func _lean_authority() -> float:
	var authority: float = 1.0
	# Loading a pop shifts the weight back onto the tail, ready to snap it down.
	if trick.is_preparing_pop():
		authority = minf(authority, pop_load_turn_damping)
	# Pushing puts a foot on the ground, leaving nothing over the back truck to lean with. Recovers
	# as the stroke completes rather than snapping back, which is both what happens physically and
	# smoother than a step change.
	if _since_push < push_stroke_time:
		authority = minf(authority, lerpf(push_turn_damping, 1.0, _since_push / push_stroke_time))
	return authority

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
	var axis: Vector3 = _board_axis()
	var lateral: Vector3 = flat - axis * flat.dot(axis)

	# The landing residual melts at a paced rate rather than being scrubbed off by grip. Lateral
	# speed relates to heading as v_lat ~= speed * angle, so draining the budget at
	# speed * angular_rate turns travel at exactly landing_turn_rate_deg, at any speed - which is
	# what makes a crooked landing swing into line smoothly instead of snapping.
	_landing_residual = maxf(0.0,
		_landing_residual - flat.length() * deg_to_rad(landing_turn_rate_deg) * delta)

	# Grip then removes everything ABOVE that budget at full strength. Two consequences, and they
	# are the entire point:
	#   - At touchdown lateral equals the budget, so limit_length() is a no-op and the residual
	#     works off at the paced rate. The landing feels exactly as it did.
	#   - Lateral the rider adds by STEERING sits above the budget, so it meets full grip and is
	#     scrubbed immediately. Carving stays tight, and a held trigger can no longer prop the
	#     board sideways, because nothing the rider does can raise the budget.
	# Once the budget reaches zero this is a plain move_toward(ZERO), i.e. ordinary wheel grip.
	flat += lateral.move_toward(lateral.limit_length(_landing_residual), wheel_side_grip * delta) - lateral

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

## THE FRAME PIPELINE. Order is the design here, not an implementation detail.
##
## Each step is a named method so this reads as the sequence it is, but the sequence is the part
## that matters: several steps write state a later one reads back, three of them write board_pivot's
## pitch, and the comments at the call sites below record which orderings are load-bearing and why.
## Reordering these lines is a behaviour change even though none of the methods themselves change.
##
## The two extracted nodes - foot_rig and camera_pivot - are advanced by explicit calls from here
## rather than by their own _physics_process, precisely so they take part in this ordering instead
## of being sequenced by node order in SkaterRig.tscn.
func _physics_process(delta: float) -> void:
	# 1. Where the skater is, and which way they are rolling.
	_update_grounded_state()
	_update_travel_axis_sign()
	_since_push += delta

	_apply_surface_alignment(delta)
	_update_stance_facts()

	# 2. Push acceleration impulses from the face buttons.
	_apply_push_inputs()

	# 3. Ground dynamics: slope gravity, wheel grip and rolling friction in one pass.
	if is_grounded:
		_apply_ground_forces(delta)

	# 4. Steering and stationary rotation, via trigger lean.
	_apply_steering(delta)

	# 5. Vertical pop impulse, and setup of the 3-layer trick rotations it starts.
	_execute_pop()

	# 5b. Carry a late-caught deck the last few degrees onto its resting orientation.
	#
	# Deliberately BEFORE the flight block, not after it. Touchdown is resolved inside step 6, so a
	# settle called afterwards would advance on the very frame the flip integrator already advanced,
	# rotating the deck twice in one tick. Running first means the settle only ever picks up on the
	# frame after the catch, and the deck turns at exactly one rate at all times.
	_advance_flip_settle(delta)

	# 6. Custom gravity, aerial pitch control, 3-layer flight physics and touchdown.
	if not is_grounded:
		_integrate_flight(delta)

	# 7. Position integration, blocked by vertical faces.
	_integrate_position(delta)

	# 8. Grounded board rotations and middle-zone manuals (only when on pavement).
	if is_grounded:
		_apply_grounded_board_pitch(delta)

	# 8c. Let the suspension extend back out, pose the feet, then advance the camera.
	#
	# The feet are solved HERE, once, rather than at the three points through the frame they used to
	# be spread across (an animate() before step 2, hover/lower inside the flight block, a settle()
	# in the grounded block). Every fact a foot pose depends on is final by now, so gathering them
	# into one call is what lets FootRig arbitrate between competing animations inside its own state
	# machine instead of leaving "which one wins" to be reconstructed from three call sites and
	# their order. It runs BEFORE the camera so the ankle pegs resolve against the same camera yaw
	# they always did - they work in the angle between the camera and the board, and the camera has
	# not moved yet this frame.
	#
	# The camera MUST run here, after step 7 has integrated position: it feeds velocity forward and
	# damps toward global_position, so advancing it earlier would frame where the skater was rather
	# than where they now are.
	# The rider's legs advance BEFORE the feet are posed, because the feet are the end of the legs.
	# Grounded clamps them out to standing, so a landing arriving early simply meets the feet.
	rider_body.solve_legs(delta, is_grounded)
	_recover_landing_dip(delta)
	_foot_frame.is_grounded = is_grounded
	_foot_frame.deck_is_spinning = is_flip_in_progress
	_foot_frame.foot_lift = rider_body.foot_lift()
	# The deck's own silhouette: how far it reaches above its long axis as it turns over. The feet
	# are held clear of THIS, so a rolling deck can never pass through a shoe no matter how the
	# rider's legs happen to be behaving.
	_foot_frame.deck_reach = deck_half_width * absf(sin(board_mesh.rotation.z))
	foot_rig.solve(delta, _foot_frame, rider, camera_pivot.rotation.y, board_pivot.rotation.y)
	camera_pivot.follow(delta)

	# 9. Re-seat the board onto its contact axle. Runs last, after every writer of board_pivot pitch
	# (the pop in step 5, airborne pitch in step 6, grounded manuals just above).
	_apply_manual_pivot()

## Step 1. Grounded vs airborne, measured against real geometry rather than a fixed plane.
##
## Proximity may only KEEP the skater grounded, never make them grounded. The airborne -> grounded
## transition belongs exclusively to the touchdown path in step 6, which is what zeroes
## vertical_velocity and runs _evaluate_touchdown_landing() (landing tolerances, bail checks,
## trick naming). Letting this block flip the flag on proximity skipped all of that whenever the
## skater entered the snap band gently - rolling off a low curb left v_speed stuck negative
## forever and never resolved the trick name.
##
## The old first clause here was `if vertical_velocity > 0.05: is_grounded = false`. It had to go
## once slopes went live: velocity is no longer purely horizontal in intent, and any test of world
## Y against zero misreads a skater rolling uphill as one leaving the ground. It was only ever a
## belt-and-braces guard - the pop in step 5 sets is_grounded = false explicitly, and nothing else
## can lift the skater off a surface - so removing it costs nothing.
func _update_grounded_state() -> void:
	surface_hit = _probe_surface()
	if not surface_hit.valid:
		is_grounded = false # Nothing underneath - rolled off a ledge, no special case needed.
	elif is_grounded:
		is_grounded = global_position.y - _surface_ride_y() <= ground_snap_distance

## Persistent rolling direction along the board's axis, held above the travel_min_speed deadband so
## a skater stalling to a stop keeps the direction they were rolling rather than snapping to the
## rig's static forward.
func _update_travel_axis_sign() -> void:
	# Measured ALONG THE WHEELS, not on total speed. Gating on total speed and then reading a tiny
	# along-axis component let motion that was almost entirely SIDEWAYS set which way the rider is
	# travelling: a standing directional pop leaps perpendicular to the deck at over 1 m/s, clearing
	# any speed gate, while the along-axis component is near zero and its sign is noise. That fed
	# leading_foot, which fed the kickturn axle, and the board pivoted on the wrong truck after
	# landing. Same mistake the chase camera made with its heading, in a second consumer.
	var axis: Vector3 = _board_axis()
	var along: float = Vector3(velocity.x, 0.0, velocity.z).dot(axis)
	if absf(along) > travel_min_speed:
		_travel_axis_sign = 1.0 if along >= 0.0 else -1.0

## Hands FootInputState the geometry it needs to work out which foot is leading, and which end of
## the DECK each shoe is standing on.
##
## Passes the shoes' REST offsets, not their live nodes: foot placement is a property of how the
## rider stands on the board, not of what an animation is doing this instant. See
## update_stance_facts() for why that distinction is load-bearing.
##
## Passes SkaterRoot, not board_pivot: update_stance_facts() reads pivot.get_parent() for the
## stationary forward vector, and that parent is now the surface-tilted SurfaceAlign node.
## Horizontal velocity only. `velocity` now carries the ballistic vertical speed too, and during a
## pop that term dominates - passing it whole would point the travel vector nearly straight up and
## scramble the leading/trailing foot test for the whole flight.
##
## The last argument is whether the DECK is turned 180 deg from rest. Nose and tail are fixed
## attributes of the board, so a landed shove-it puts the tail at the leading end without moving the
## rider at all - read the deck's real orientation rather than inferring it from the rider's stance.
func _update_stance_facts() -> void:
	rider.update_stance_facts(board_pivot, foot_rig.left_rest, foot_rig.right_rest,
		self, _travel_axis_sign, deck_reversed())

## Step 2. Push impulses from the face buttons (latched inputs ensure zero missed taps).
func _apply_push_inputs() -> void:
	if not (rider.push_left_triggered or rider.push_right_triggered):
		return
	if is_grounded:
		_apply_push_impulse()
		_since_push = 0.0
		# The animation may REFUSE - both shoes never leave the deck at once, so a press arriving
		# mid-stroke is dropped. The physical impulse above is applied either way: whether pushing
		# should also be rate-limited in the physics is a gameplay question, and answering it
		# silently here by gating on an animation would be exactly the animation-decides-an-outcome
		# coupling this project has removed everywhere else.
		if rider.push_left_triggered:
			foot_rig.start_push(RiderInput.Foot.LEFT)
		else:
			foot_rig.start_push(RiderInput.Foot.RIGHT)
		rider.push_left_triggered = false
		rider.push_right_triggered = false
	elif vertical_velocity > 0.5 or (surface_hit.valid and global_position.y - _surface_ride_y() > 0.35):
		# Clear stale latched presses if high in the air to prevent unintended touchdown bursts
		rider.push_left_triggered = false
		rider.push_right_triggered = false

## Step 4. Steering and stationary rotation via trigger lean (RT - LT), on pavement only.
func _apply_steering(delta: float) -> void:
	# Steering rate is lean input times the board's turn speed times however much of the rider's
	# weight is actually available to lean with - see _lean_authority(), which is where pop loading,
	# pushing, and later grinds and manuals all register their cost. Damps STEERING only, never the
	# push impulse: gating a gameplay term on a body state is fine, gating it on an ANIMATION is not.
	var turn_rate: float = rider.lean * (rider.board_config.turn_speed if is_instance_valid(rider.board_config) else 3.0) * _lean_authority()
	if not is_grounded or abs(rider.lean) <= 0.05:
		_is_carve_latched = false
		return
		
	var speed: float = Vector3(velocity.x, 0.0, velocity.z).length()
	# Latch continuous carving if initiated above kickturn threshold, remaining in carve mode down to near-stall (< 0.05 m/s)
	if speed >= kickturn_max_speed:
		_is_carve_latched = true
	elif speed < 0.05:
		_is_carve_latched = false
		
	if not _is_carve_latched:
		# Stationary Kickturn: anchor the rotation on the axle that is ON THE GROUND, so the back
		# tyres stay locked to the pavement while the nose swings round.
		#
		# The trailing axle is a BoardPivot-relative fact and the rotation below happens in the RIG's
		# frame, so it has to be carried across - which is the whole reason pivot_z_to_rig() exists.
		# Deriving the axle without it anchored the LEADING truck in switch, and since a kickturn
		# lifts the leading trucks, that made the airborne one the pivot (BUG_ARCHIVE #6).
		var axle_local_pos := Vector3(0.0, -(ride_height - wheel_radius),
			pivot_z_to_rig(trailing_axle_z()))
		var axle_world_before: Vector3 = to_global(axle_local_pos)
		rotate_y(-turn_rate * delta)
		var axle_world_after: Vector3 = to_global(axle_local_pos)
		global_position += (axle_world_before - axle_world_after)
	else:
		rotate_y(-turn_rate * delta)

## Step 5. The pop: vertical impulse, kicktail pitch, and the deck rotation targets for the trick.
func _execute_pop() -> void:
	if not (is_grounded and trick.pop_impulse_triggered):
		return
	vertical_velocity = jump_impulse * trick.pop_impulse_scale
	is_grounded = false
	trick.pop_impulse_triggered = false
	# The knees come up as hard as the pop was. Nothing emerges a tuck - it is a muscle - so this is
	# the one place effort is authored, and it is an impulse rather than a path.
	rider_body.tuck(trick.pop_impulse_scale)

	if absf(trick.pop_lateral_impulse_ratio) > 0.0:
		var lateral_axis: Vector3 = global_transform.basis.x * _travel_axis_sign
		lateral_axis.y = 0.0
		velocity += lateral_axis.normalized() * (trick.pop_lateral_impulse_ratio * max_lateral_pop_impulse)
		# The deck kicking out under a directional pop is a twist between rider and board, so it winds
		# the torsion rather than being written straight onto the board's yaw. Written the old way it
		# would be a yaw the coupling never agreed to, and the torsion would quietly undo it.
		#
		# MIND THE SIGN. wind_twist() records how far the board is AHEAD of the rider, and relaxing
		# that twist is what turns the deck - so the board ends up moving by MINUS the wound amount.
		# Winding by -ratio (the direction the deck should end up going) therefore kicked it the wrong
		# way, and no suite caught it because none of them pops laterally.
		rider_body.wind_twist(trick.pop_lateral_impulse_ratio * lateral_pop_yaw_deg)
		trick.pop_lateral_impulse_ratio = 0.0

	airborne_body_yaw_deg = 0.0
	# Read the orientation rather than inferring it from the pop type - the rider may have arrived
	# at this heading any number of ways.
	pop_riding_reversed = pivot_reversed()
	var sig: TrickSignature = trick.current_trick
	_takeoff_vertical_velocity = maxf(0.0, vertical_velocity)
	var velocity_ratio: float = clampf(_takeoff_vertical_velocity / jump_impulse, 0.0, 1.0)
	var dynamic_pitch: float = pop_pitch_deg * velocity_ratio
	if sig.scoop_deg != 0 and sig.flip == TrickSignature.Flip.NONE:
		dynamic_pitch = minf(dynamic_pitch, 15.0)
	_initial_pop_pitch_deg = dynamic_pitch

	# Kick the deck's end down: the trailing one for an Ollie, the leading one for a Nollie. Written
	# rider-relative and mapped onto the pivot's local X by stance_sign(), so switch and goofy need
	# no separate case.
	if sig.pop == TrickSignature.Pop.NOLLIE or sig.pop == TrickSignature.Pop.FAKIE_OLLIE:
		board_pivot.rotation_degrees.x = -dynamic_pitch * stance_sign()
	else:
		board_pivot.rotation_degrees.x = dynamic_pitch * stance_sign()

	# Where the deck actually was when the trick started, so touchdown can measure what it turned
	# through rather than assuming it turned through whatever was requested here.
	_pop_board_roll = board_mesh.rotation_degrees.z
	_pop_board_yaw = board_mesh.rotation_degrees.y

	# Configure BoardMesh flip & spin targets (Layer 3). Only the deck's own 180 deg yaw reversal
	# after a Shove-it needs compensating here - Nollie/Fakie flip mirroring is already applied
	# in TrickState._build_trick_signature(), so there is no stance term.
	#
	# Targets are built off the nearest RESTING orientation, not off the raw current angle: popping
	# again mid-settle would otherwise bake the few unsettled degrees in permanently, and every
	# later trick would inherit the error. When the deck is already at rest - the normal case -
	# rounding is a no-op and the target is unchanged.
	_roll_rest_at_pop = _nearest_multiple(board_mesh.rotation_degrees.z, 360.0)
	_yaw_rest_at_pop = _nearest_multiple(board_mesh.rotation_degrees.y, 180.0)
	if sig.flip == TrickSignature.Flip.KICK:
		_roll_turn_dir = flip_roll_sign()
		flip_roll_turns = 1
		is_flip_in_progress = true
	elif sig.flip == TrickSignature.Flip.HEEL:
		_roll_turn_dir = -flip_roll_sign()
		flip_roll_turns = 1
		is_flip_in_progress = true
	else:
		_roll_turn_dir = 0.0
		flip_roll_turns = 0

	# Spin magnitude comes from the measured signature, never from the display name. Counted in
	# HALF-turns, because that is what the deck actually rests at: a 360 scoop is two of them.
	if sig.scoop_deg != 0:
		_yaw_turn_dir = trick.last_scoop_sign
		flip_yaw_turns = 2 if absi(sig.scoop_deg) == 360 else 1
		is_flip_in_progress = true
	else:
		_yaw_turn_dir = 0.0
		flip_yaw_turns = 0
	_refresh_rotation_targets()

	# The flip loop now owns BoardMesh; any settle still running is superseded by it.
	if is_flip_in_progress:
		is_flip_settling = false
	_impart_deck_rotation(sig)

## Step 6. Flight: gravity, the three rotation layers, and the touchdown that ends it.
func _integrate_flight(delta: float) -> void:
	vertical_velocity -= gravity_accel * delta
	global_position.y += vertical_velocity * delta

	# Layer 1: Aerial Body Spin (FS/BS 180s/360s via triggers, with the rider's own rotational inertia)
	#
	# The RIDER turns and the board is carried round with them, rather than the deck being spun and
	# the rider inferred from it. That is the physically true direction, and it is what lets the two
	# come apart later: a boardslide puts the deck across the direction of travel while the rider
	# still faces near-forward, which is not expressible while one of them IS the other.
	#
	# The board follows through the TORSION, not by taking the shoulders' delta outright. Turning the
	# shoulders winds the twist up; relaxing it is what turns the deck. At the default twist_follow
	# the whole wind-up closes within the same frame, so the deck still tracks the rider exactly and
	# every previous figure is reproduced - softening it is a separate, deliberate change.
	var turned: float = rider_body.advance_spin(rider.lean, delta)
	if turned != 0.0:
		rider_body.wind_twist(-turned) # the shoulders moved; the deck has not caught up yet
		airborne_body_yaw_deg += turned
	board_pivot.rotation_degrees.y += rider_body.solve_twist(delta,
		rider.stance == RiderInput.Stance.GOOFY)

	# Layer 2: Mid-Air Pitch Control (0.20 to 1.00 thumbsticks to angle nose/tail in air)
	_apply_airborne_board_pitch(delta)

	# Layer 3: Deck Flip & Spin Authority on BoardMesh with Shoe Hover Catching.
	# Rates were fixed at the pop and are simply integrated here; both axes were scaled to the
	# same trick duration, so they arrive together on the same frame however they are combined.
	# The feet are NOT posed here any more. is_flip_in_progress is handed to FootRig as
	# `deck_is_spinning` in step 8c, and its state machine decides whether that means hovering clear
	# of the deck or returning to the rest pose - which is the same choice the hover()/lower() pair
	# used to make from inside this block, but made in one place alongside every other foot state.
	if is_flip_in_progress:
		board_mesh.rotation_degrees.z = move_toward(board_mesh.rotation_degrees.z, target_board_roll, absf(flip_roll_rate) * delta)
		board_mesh.rotation_degrees.y = move_toward(board_mesh.rotation_degrees.y, target_board_yaw, absf(flip_yaw_rate) * delta)

		# Catch trick cleanly when deck revolution completes (grip tape facing up). This is the frame
		# a mid-air catch stomp will be fired from - see 01_FOOT_ANIMATIONS.md section 4.
		if is_equal_approx(board_mesh.rotation_degrees.z, target_board_roll) and is_equal_approx(board_mesh.rotation_degrees.y, target_board_yaw):
			is_flip_in_progress = false
			board_mesh.rotation_degrees.z = fmod(board_mesh.rotation_degrees.z, 360.0)
			board_mesh.rotation_degrees.y = fmod(board_mesh.rotation_degrees.y, 360.0)
			trick.trick_status_string = "Caught in mid-air!"

	# Touchdown onto whatever surface the probe found - ground, curb top, ramp face.
	if surface_hit.valid and global_position.y <= _surface_ride_y() and vertical_velocity <= 0.0:
		# Sample the impact BEFORE it is zeroed - it is the only measure of how hard this landing
		# was, and one line later it is gone.
		var impact: float = absf(vertical_velocity)
		global_position.y = _surface_ride_y()
		vertical_velocity = 0.0
		is_grounded = true
		if landing_dip_ref_speed > 0.0:
			_landing_dip = minf(impact / landing_dip_ref_speed, 1.0) * landing_dip_max
		rider_body.halt_spin()
		trick.current_pop_state = TrickState.PopState.NONE
		_evaluate_touchdown_landing()

## Step 7. Position integration, blocked by vertical faces. `velocity` is authoritative and is NOT
## rebuilt from orientation here - that rebuild was the whole bug. Only the horizontal components
## move the skater; while grounded the surface snap at the end owns height entirely.
func _integrate_position(delta: float) -> void:
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

## Step 8c. Lets the landing suspension extend back out. Applied to SurfaceAlign.position, which
## nothing else writes - see landing_dip_max for why that node and not the rig origin.
func _recover_landing_dip(delta: float) -> void:
	_landing_dip = lerpf(_landing_dip, 0.0, minf(landing_dip_recover * delta, 1.0))
	surface_align.position.y = -_landing_dip

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
	# Reference rate each axis would run at alone. The 360 scoop keeps its historical doubling, which
	# is what makes a tre flip's scoop read as sharper than its flip rather than lazier.
	var yaw_ref: float = spin_speed_deg * (2.0 if absi(sig.scoop_deg) == 360 else 1.0)
	var roll_time: float = absf(roll_sweep) / flip_speed_deg if flip_speed_deg > 0.0 else 0.0
	var yaw_time: float = absf(yaw_sweep) / yaw_ref if yaw_ref > 0.0 else 0.0
	
	# Multi-axis rotational inertia coupling: combining simultaneous rotation axes in 3D distributes
	# angular kinetic energy and extends revolution duration. A 360 flip (360 scoop + flip) carries
	# twice the secondary angular displacement of a varial flip (180 scoop + flip), naturally extending
	# its completion and procedural mid-air catch stomp slightly later past jump apex!
	var primary_time: float = maxf(roll_time, yaw_time)
	var secondary_time: float = minf(roll_time, yaw_time)
	var complexity_drag: float = 0.0
	if roll_time > 0.0 and yaw_time > 0.0:
		var sweep_ratio: float = (absf(roll_sweep) + absf(yaw_sweep)) / 360.0
		complexity_drag = secondary_time * rotational_complexity_coupling * sweep_ratio
	var trick_time: float = primary_time + complexity_drag

	if trick_time <= 0.0:
		flip_roll_rate = 0.0
		flip_yaw_rate = 0.0
		return
	# How hard it was flicked scales BOTH axes by the same factor, which is what keeps flip and scoop
	# synchronised: their ratio is what makes them arrive together, and scaling preserves a ratio.
	var intensity: float = _flick_rate_scale(sig.flick_speed)
	flip_roll_rate = roll_sweep / trick_time * intensity
	flip_yaw_rate = yaw_sweep / trick_time * intensity

## Rotation rate multiplier from how hard the rider flicked, around flick_reference_speed.
##
## A signature with NO flick measurement means "unmeasured", not "flicked infinitely slowly": the
## keyboard pop path sets no speed, and a test injecting a signature directly does not either. Both
## take the reference rate rather than the floor, which is also what keeps this change a no-op for
## every existing suite.
func _flick_rate_scale(flick_speed: float) -> float:
	if flick_speed <= 0.0 or flick_reference_speed <= 0.0:
		return 1.0
	var ratio: float = flick_speed / flick_reference_speed
	return clampf(1.0 + (ratio - 1.0) * flick_rate_sensitivity, flick_rate_min, flick_rate_max)

## Rebuilds both rotation targets from the turn counts.
##
## Targets are a CONSEQUENCE of how many turns the rider has asked for, not a number decided at the
## pop. Raising a turn count and calling this is the whole of "keep spinning" - the rate is untouched,
## so the deck simply takes longer to arrive rather than speeding up to hit a moved goalpost.
##
## Built off the RESTING orientation the trick started from, not the raw angle: popping again
## mid-settle would otherwise bake the few unsettled degrees in permanently and every later trick
## would inherit the error. When the deck is already at rest - the normal case - that rounding is a
## no-op and the target is unchanged.
func _refresh_rotation_targets() -> void:
	target_board_roll = _roll_rest_at_pop + 360.0 * float(flip_roll_turns) * _roll_turn_dir
	target_board_yaw = _yaw_rest_at_pop + 180.0 * float(flip_yaw_turns) * _yaw_turn_dir

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
## sweep achieved since the pop decides what it is CALLED. A 360 scoop that only made it half way is
## credited as the 180 it actually did.
func _credit_achieved_rotation() -> void:
	var sig: TrickSignature = trick.current_trick
	if sig.flip != TrickSignature.Flip.NONE:
		var roll_turns: int = int(roundf((board_mesh.rotation_degrees.z - _pop_board_roll) / 360.0))
		if roll_turns == 0:
			sig.flip = TrickSignature.Flip.NONE
	if sig.scoop_deg != 0:
		var achieved: int = absi(int(roundf((board_mesh.rotation_degrees.y - _pop_board_yaw) / 180.0)))
		var intended: int = int(absi(sig.scoop_deg) / 180.0)
		if achieved < intended:
			sig.scoop_deg = achieved * 180 * signi(sig.scoop_deg)

func _apply_airborne_board_pitch(delta: float) -> void:
	# Solved RIDER-relative throughout - positive is trailing-end-down - then mapped onto the pivot's
	# local X by stance_sign() in the single assignment at the end.
	var target_pitch_deg: float = 0.0
	# The pitch view of the sticks, not the raw ones: the stick that fired the pop is still buried at
	# takeoff and reads as centred until the rider releases it. See TrickState.pop_load_spent.
	var front: Vector2 = trick.airborne_front_stick()
	var back: Vector2 = trick.airborne_back_stick()
	var sig: TrickSignature = trick.current_trick

	if _takeoff_vertical_velocity > 0.01 and vertical_velocity > 0.0:
		var ratio: float = clampf(vertical_velocity / _takeoff_vertical_velocity, 0.0, 1.0)
		target_pitch_deg = _initial_pop_pitch_deg * pow(ratio, pop_leveling_exponent)

	if sig and sig.flip != TrickSignature.Flip.NONE and is_flip_in_progress:
		target_pitch_deg += sig.flick_tilt_deg

	if back.y > pitch_stick_deadzone:
		target_pitch_deg += back.y * max_pitch_deg # Tail dip (trailing edge)
	elif front.y < -pitch_stick_deadzone:
		target_pitch_deg += front.y * max_pitch_deg # Nose dip (leading edge)

	# The three terms above ADD, so a rider re-applying pitch during the ascent stacks their input on
	# top of the pop's own tilt. Bounded by the pop angle itself, which is the steepest the deck is
	# ever meant to sit at. Currently this rarely binds - airborne_pitch_follow is too slow to reach
	# the stacked target before the pop term decays - and that is precisely why it is worth pinning
	# down: raise the follow rate for responsiveness and the deck would whip to 74 deg without it.
	target_pitch_deg = clampf(target_pitch_deg, -pop_pitch_deg, pop_pitch_deg)

	board_pivot.rotation_degrees.x = lerpf(board_pivot.rotation_degrees.x,
		target_pitch_deg * stance_sign(), airborne_pitch_follow * delta)

## Folds the body rotation that just happened into the trick signature and resolves its name.
## Called only on successful landings - a bail leaves the previous landed trick on display.
func _finalise_trick_name() -> void:
	var sig: TrickSignature = trick.current_trick
	var half_turns: int = int(round(airborne_body_yaw_deg / 180.0))
	sig.body_deg = half_turns * 180 * TrickSignature.body_sign(
		rider.stance == RiderInput.Stance.GOOFY, pop_riding_reversed)
	trick.last_combo_string = TrickNames.resolve(sig)
	trick.last_trick_signature = sig.describe()

func _evaluate_touchdown_landing() -> void:
	# Firmly seat shoes onto deck rest coordinates immediately upon ground contact. An EVENT, which
	# is why it stays an explicit call here rather than becoming a state the solver infers: the
	# rider's weight arrives on the deck in a single frame and easing it reads as floating.
	foot_rig.settle_now()
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
			trick.trick_status_string = "BAIL! (Primo Crash / Incomplete Flip)"
			_kill_momentum()
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
		# Genuinely a magnitude operation - the stamp that flattens the deck costs speed without
		# redirecting it - so scaling the vector in place is what is meant here.
		velocity.x *= cos(deg_to_rad(catch_err))
		velocity.z *= cos(deg_to_rad(catch_err))
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
	rotate_y(deg_to_rad(board_pivot.rotation_degrees.y - rest_yaw))
	board_pivot.rotation_degrees.y = fmod(rest_yaw, 360.0)
	# The rider's frame is resolved the same way and at the same instant. Only the REMAINDER went to
	# the rig above, so the shoulders keep the half-turn that makes the rider switch - but they must
	# not keep the whole spin, or every trick ever landed accumulates into the torso for good.
	# Rounded independently rather than copied from the board: the two differ by the deck's own
	# lateral pop yaw (up to lateral_pop_yaw_deg), which is the board kicking out, not the rider
	# turning, and it must not leak into the rider's frame.
	rider_body.rotation_degrees.y = fmod(
		_nearest_multiple(rider_body.rotation_degrees.y, 180.0), 360.0)
	# Nothing is handed to the camera here any more. It tracks the direction of TRAVEL, which does
	# not jump at touchdown - only the rig's heading does - so there is no discontinuity to absorb.

	# Sideways landing, judged on MOMENTUM rather than angle. Wheels hold only so much lateral speed
	# before washing out, so the identical 90 deg landing is survivable at walking pace and fatal at
	# full speed - a distinction the old fixed 45-135 deg window could not express at all. Anything
	# under the limit is not "forgiven" either: the lateral component is still scrubbed off against
	# grip by _apply_ground_forces(), so a sketchy landing costs real speed.
	var flat_v := Vector3(velocity.x, 0.0, velocity.z)
	var land_axis: Vector3 = _board_axis()
	var land_along: float = absf(flat_v.dot(land_axis))
	last_landing_slide = (flat_v - land_axis * flat_v.dot(land_axis)).length()
	# Arm the realignment budget with the sideways speed actually arrived with. Set HERE, where that
	# speed is measured, and nowhere else - a second writer is exactly how it would start growing
	# again, which is the failure the budget replaced.
	#
	# Bounded by the heading error the pacing can actually express - see max_realign_angle_deg. The
	# budget only covers lateral that is a heading to be ROTATED into line, which needs an along-axis
	# component to rotate toward; anything beyond that is a skid, and grip fights it at full strength.
	# Landing with no forward speed at all now arms nothing, so a standing directional pop lands and
	# stops instead of sliding.
	_landing_residual = minf(last_landing_slide,
		land_along * tan(deg_to_rad(max_realign_angle_deg)))
	if last_landing_slide > max_landing_slide:
		_landing_residual = 0.0 # Washed out; momentum is killed below, so there is nothing to pace.
		trick.trick_status_string = "BAIL! (Sideways Landing / Wheel Skid)"
		_kill_momentum()
		board_pivot.rotation_degrees.x = 0.0
		manual_timer = 0.0
		return

	var pitch: float = board_pivot.rotation_degrees.x
	var in_manual_zone: bool = false
	
	# Landing INTO a manual: the deck is already pitched that way and the rider is still asking for
	# it. Uses the same balance test as grounded pitch, so a manual cannot be caught on touchdown
	# under rules the very next frame disagrees with.
	var effective_pitch: float = rider_pitch_deg()
	if effective_pitch > manual_catch_min_pitch_deg and trick.holds_tail_balance():
		in_manual_zone = true # Touchdown into standard / switch manual!
	elif effective_pitch < -manual_catch_min_pitch_deg and trick.holds_nose_balance():
		in_manual_zone = true # Touchdown into nose / switch nose manual!
	
	if in_manual_zone:
		# INSTANT MANUAL CATCH: bypass loading delay and continue rolling smoothly!
		_finalise_trick_name()
		trick.trick_status_string = "Landed directly into Manual!"
		manual_timer = manual_entry_delay # Instant loading buffer
	elif abs(pitch) > max_landing_tolerance_deg:
		# BAIL / WHEEL BITE: landed too steep outside of manual catching zone!
		trick.trick_status_string = "BAIL! (Wheel Bite / Over-Pitched)"
		_kill_momentum() # Speed penalty for crashing
		board_pivot.rotation_degrees.x = 0.0
		manual_timer = 0.0
	else:
		# CLEAN LANDING: within tolerances
		_finalise_trick_name()
		trick.trick_status_string = "Landed %s!" % trick.last_combo_string
		manual_timer = 0.0

func _apply_grounded_board_pitch(delta: float) -> void:
	# Solved RIDER-relative throughout - positive is trailing-end-down - then mapped onto the pivot's
	# local X by stance_sign() in the single assignment at the end.
	var target_pitch_deg: float = 0.0
	var front: Vector2 = rider.front_stick()
	var back: Vector2 = rider.back_stick()
	var is_manualing: bool = false

	var was_manualing: bool = manual_timer >= manual_entry_delay or abs(board_pivot.rotation_degrees.x) > 2.0

	# The two-stage balance law - entering a manual from four wheels demands more than holding one
	# already established. Both stages live on TrickState so this and the touchdown check cannot
	# drift apart about what a manual is; see the comment there for why each stage tests what it does.
	var tail_down: bool = trick.holds_tail_balance() if was_manualing else trick.enters_tail_balance()
	var nose_down: bool = trick.holds_nose_balance() if was_manualing else trick.enters_nose_balance()
	if tail_down:
		target_pitch_deg = minf(1.0, back.length()) * max_pitch_deg
		is_manualing = true
	elif nose_down:
		target_pitch_deg = -minf(1.0, front.length()) * max_pitch_deg
		is_manualing = true
		
	# Automatically lift front trucks during Stationary Kickturns ONLY if not already balancing a thumbstick manual!
	if not is_manualing and not _is_carve_latched and abs(rider.lean) > 0.05 and Vector3(velocity.x, 0.0, velocity.z).length() < kickturn_max_speed:
		target_pitch_deg = kickturn_pitch_deg
		manual_timer = manual_entry_delay
		
	# Tightened Grounded Manual Delay (80ms): ignores brief transition frames when fast-snapping to full extension
	if abs(target_pitch_deg) > 0.5:
		if manual_timer < manual_entry_delay:
			manual_timer += delta
			target_pitch_deg = 0.0
	else:
		manual_timer = 0.0

	board_pivot.rotation_degrees.x = lerpf(board_pivot.rotation_degrees.x,
		target_pitch_deg * stance_sign(), grounded_pitch_follow * delta)
