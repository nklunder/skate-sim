class_name FootRig
extends Node

## The rider's feet: shoe boxes and ankle pegs, and every animation that moves them.
##
## PRESENTATION ONLY, and now provably so. Stance classification moved onto the REST offsets (see
## FootInputState.update_stance_facts), so no live foot position is read by anything outside this
## file any more. That is what frees the animations below to put a shoe anywhere at all - out over
## the nose, off the back of the tail, past the rails - without a hand-maintained "the leading foot
## must never cross Z = 0" invariant standing behind them. Move the feet however you like; nothing
## downstream can notice.
##
## Sits under BoardPivot so poses stay expressed in the deck's own frame: a foot at rest is at a
## fixed local offset whatever the board is doing, and Switch/Fakie's 180 deg yaw is INHERITED
## rather than compensated for. Every flick vector authored here mirrors correctly for free.
##
## HOW IT WORKS - two layers, deliberately separated:
##
##   1. Each foot is in a STATE, and each state solves a TARGET POSE for the frame. States are
##      per-foot, not global: a tre flip needs the trailing foot scooping the tail while the
##      leading foot flicks through the nose pocket, and one shared state cannot say that.
##   2. A critically-damped SPRING carries each shoe toward its target. Weight, overshoot and
##      settling emerge from the integration instead of being authored into curves, and an
##      animation interrupted half way is safe by construction - the target changes, the shoe's
##      existing velocity carries through it, and nothing snaps.
##
## Driven by ONE explicit solve() call from SkaterController's frame pipeline, never by its own
## _physics_process. Posing used to be spread across three points in that pipeline (an animate() at
## the top, hover/lower inside the flight block, settle inside the grounded block), so answering
## "which animation wins?" meant reading three call sites and knowing their order. The state machine
## answers it in one place now.

## What a foot is currently doing. Held PER FOOT - the two channels are independent.
##
## Planned additions, in the order 01_FOOT_ANIMATIONS.md builds them: LOADING (pre-pop crouch),
## FLICKING (the two-stage flip arc), SCOOPING (lateral tail sweep), STOMPING (mid-air catch), and
## eventually GRINDING. Each is a new branch in _solve_target() plus a transition in
## _advance_states(); nothing else has to change.
enum FootState {
	RIDING, ## Standing on the deck at the rest pose.
	PUSHING, ## Mid push stroke - the one grounded animation that takes a foot off its rest.
	HOVERING, ## Lifted clear of a deck spinning underneath.
}

@export_category("Spring")
## How hard each shoe is pulled toward its target pose. Sets the RESPONSE TIME, not the distance:
## a linear spring settles in the same time whether it is travelling a centimetre or ten, which is
## why one value serves both the position and rotation channels despite their different units.
##
## Roughly, the shoe arrives in 4 / sqrt(stiffness) seconds. 400 is about 0.2 s - matched to the
## lerp rate the feet used before springs, so the standing and push poses read as they always did.
@export var foot_stiffness: float = 400.0
## 1.0 is critical damping: the fastest arrival that does not overshoot. Below 1.0 the shoe rings
## past its target and comes back, which is what a hard flick should do; above it, the motion goes
## sluggish. Exported per rig rather than per state for now - split it out when an animation
## genuinely wants a different feel from the rest.
@export_range(0.0, 2.0) var foot_damping_ratio: float = 1.0

@export_category("Poses")
## Max ankle peg lean at full stick deflection.
@export var peg_tilt_deg: float = 35.0
## Rate the ankle pegs lerp toward their tilt. The pegs hang off their own PegPivot node and are a
## direct readout of stick position rather than a weighted limb, so they stay on a plain lerp - a
## spring here would add lag to what is essentially an instrument needle.
@export var peg_follow_speed: float = 16.0
## Duration of one push stroke, in seconds.
@export var push_anim_duration: float = 0.25
## How far the pushing foot drops toward the ground at the middle of its stroke, in metres.
@export var push_dip: float = 0.055
## How far the pushing foot reaches out to the side of the deck, in metres.
@export var push_reach: float = 0.22
## How far the pushing foot travels fore-and-aft across the stroke, in metres. Reaches forward at
## the start and thrusts back at the finish.
@export var push_sweep: float = 0.15
## Height the shoe boxes lift to while the deck spins underneath them, in metres. Clears the
## rotating deck so the board does not visibly pass through the rider's feet mid-flip.
@export var flip_hover_height: float = 0.18

## Longest step the spring is integrated over. A semi-implicit Euler spring goes unstable once the
## step approaches its period, and a frame hitch would otherwise fire the shoes off the board.
## Clamping means a long frame animates in slow motion for one tick, which nobody will ever see.
const MAX_STEP: float = 1.0 / 30.0

@onready var left_foot: Node3D = $"../LeftFoot"
@onready var right_foot: Node3D = $"../RightFoot"
@onready var left_peg_pivot: Node3D = $"../LeftFoot/PegPivot"
@onready var right_peg_pivot: Node3D = $"../RightFoot/PegPivot"

var _left: Channel = null
var _right: Channel = null

## One foot: the node it drives, the pose it rests at, what it is doing, and the spring state
## carrying it there.
class Channel extends RefCounted:
	var node: Node3D
	## Captured from SkaterRig.tscn, never authored here - the scene is the single source of truth
	## for where the shoes are mounted. Rotation is captured alongside position so an animation that
	## angles an ankle has something to return to.
	var rest_position: Vector3 = Vector3.ZERO
	var rest_rotation: Vector3 = Vector3.ZERO
	var state: FootRig.FootState = FootRig.FootState.RIDING
	## Seconds since this foot entered its current state. The only clock any animation needs.
	var phase_time: float = 0.0
	var target_position: Vector3 = Vector3.ZERO
	var target_rotation: Vector3 = Vector3.ZERO
	var _vel_position: Vector3 = Vector3.ZERO
	var _vel_rotation: Vector3 = Vector3.ZERO

	func _init(foot: Node3D) -> void:
		node = foot
		rest_position = foot.position
		rest_rotation = foot.rotation
		target_position = rest_position
		target_rotation = rest_rotation

	func enter(new_state: FootRig.FootState) -> void:
		if state == new_state:
			return
		state = new_state
		phase_time = 0.0

	## Advances the shoe one step toward its target under a damped spring.
	##
	## c = 2 * zeta * sqrt(k) is the standard critical-damping relation, so zeta = 1.0 arrives in the
	## shortest time without overshooting and anything below rings. Velocity is integrated before
	## position (semi-implicit Euler) because the explicit form gains energy and slowly shakes the
	## shoes apart at these stiffnesses.
	func integrate(stiffness: float, damping_ratio: float, delta: float) -> void:
		var damping: float = 2.0 * damping_ratio * sqrt(maxf(stiffness, 0.0))
		_vel_position += ((target_position - node.position) * stiffness - _vel_position * damping) * delta
		node.position += _vel_position * delta
		_vel_rotation += ((target_rotation - node.rotation) * stiffness - _vel_rotation * damping) * delta
		node.rotation += _vel_rotation * delta

	## Puts the shoe on its target immediately and kills the spring. For touchdown, where the
	## rider's weight lands on the deck and there is nothing gradual about it.
	func snap() -> void:
		node.position = target_position
		node.rotation = target_rotation
		_vel_position = Vector3.ZERO
		_vel_rotation = Vector3.ZERO

## What the rig needs to know about the frame it is posing for.
##
## Passed in rather than reached back for: FootRig must not hold a reference to SkaterController,
## or the presentation-only rule becomes a matter of discipline instead of one of structure. One
## instance is reused by the controller, so this costs no allocation per frame.
class Frame extends RefCounted:
	var is_grounded: bool = true
	## True while the deck is rotating under the rider - the feet must be clear of it.
	var deck_is_spinning: bool = false

func _ready() -> void:
	_left = Channel.new(left_foot)
	_right = Channel.new(right_foot)

## Rest offsets in BoardPivot-local metres. Read by SkaterController for the stance test, which is
## the one physics decision the feet take part in - and it consumes these CONSTANTS rather than the
## live positions, so no animation can disturb it.
var left_rest: Vector3:
	get: return _left.rest_position if _left != null else Vector3.ZERO

var right_rest: Vector3:
	get: return _right.rest_position if _right != null else Vector3.ZERO

## Begins a push stroke, or refuses.
##
## Returns false when either foot is already off its rest pose. Both shoes may never leave the deck
## at once, and a press arriving mid-stroke is DROPPED rather than queued: a rider with one foot in
## the air cannot start a second kick, and a queue would let button spam bank strokes that fire
## after the fact. The caller is free to ignore the result - the physical push impulse is the
## controller's business, not the animation's.
func start_push(foot: FootInputState.Foot) -> bool:
	if _left.state != FootState.RIDING or _right.state != FootState.RIDING:
		return false
	var channel: Channel = _left if foot == FootInputState.Foot.LEFT else _right
	channel.enter(FootState.PUSHING)
	return true

## Drops both feet onto their rest poses instantly, cancelling whatever they were doing. Touchdown
## only: the rider's weight arrives on the deck in one frame, and easing that reads as floating.
func settle_now() -> void:
	for ch in [_left, _right]:
		ch.state = FootState.RIDING
		ch.phase_time = 0.0
		ch.target_position = ch.rest_position
		ch.target_rotation = ch.rest_rotation
		ch.snap()

## Poses both feet for this frame. The single entry point, called from SkaterController's pipeline.
##
## `camera_yaw` and `board_yaw` are the local yaws of CameraPivot and BoardPivot; see
## _drive_ankle_peg() for why both are needed.
func solve(delta: float, frame: Frame, input_state: FootInputState, camera_yaw: float,
		board_yaw: float) -> void:
	var step: float = minf(delta, MAX_STEP)
	_advance_states(step, frame)
	_solve_target(_left, true, input_state)
	_solve_target(_right, false, input_state)
	_left.integrate(foot_stiffness, foot_damping_ratio, step)
	_right.integrate(foot_stiffness, foot_damping_ratio, step)
	_drive_ankle_pegs(step, input_state, camera_yaw, board_yaw)

## The arbitration, in one place and in priority order. Read top to bottom: the first branch that
## applies owns the foot, so "which animation wins" is answered by where it sits in this list.
func _advance_states(delta: float, frame: Frame) -> void:
	for ch in [_left, _right]:
		ch.phase_time += delta
		if not frame.is_grounded and frame.deck_is_spinning:
			# Highest priority: the deck is turning over underneath, so the feet get out of its way
			# whatever else they were doing. A push stroke caught by a pop is simply abandoned - a
			# rider cannot keep kicking at the ground once the board has left it.
			ch.enter(FootState.HOVERING)
		elif ch.state == FootState.HOVERING:
			ch.enter(FootState.RIDING)
		elif ch.state == FootState.PUSHING and ch.phase_time >= push_anim_duration:
			ch.enter(FootState.RIDING)

## Solves one foot's target pose from its state. Every branch starts at the rest pose and displaces
## from it, so nothing an animation writes can leak into the next state - the reason the old
## y-only hover() could not be given an x or z term safely.
func _solve_target(ch: Channel, is_left: bool, input_state: FootInputState) -> void:
	ch.target_position = ch.rest_position
	ch.target_rotation = ch.rest_rotation
	match ch.state:
		FootState.HOVERING:
			ch.target_position.y = flip_hover_height
		FootState.PUSHING:
			ch.target_position += _push_offset(ch.phase_time, is_left, input_state)

## Displacement of a pushing foot at `t` seconds into its stroke: a sinusoidal dip toward the
## pavement paired with a forward-to-backward sweeping thrust along Z.
func _push_offset(t: float, is_left: bool, input_state: FootInputState) -> Vector3:
	var progress: float = clampf(t / push_anim_duration, 0.0, 1.0)
	var arc: float = sin(progress * PI)
	var left_is_leading: bool = input_state.leading_foot == FootInputState.Foot.LEFT
	# Mongo means pushing with the LEADING foot. It reaches across to the heel side (-X) while a
	# standard push steps off the toe side (+X); deriving that from the live stance rather than from
	# which shoe it is keeps goofy riders stepping off the same side of the board as regular ones.
	var is_mongo: bool = is_left == left_is_leading
	return Vector3(
		arc * push_reach * (-1.0 if is_mongo else 1.0),
		-arc * push_dip,
		cos(progress * PI) * -push_sweep)

func _drive_ankle_pegs(delta: float, input_state: FootInputState, camera_yaw: float,
		board_yaw: float) -> void:
	# Each PegPivot hangs under BoardPivot, which yaws to 180 deg in Switch/Fakie while CameraPivot
	# (parented to SkaterRoot) stays put. Driving the tilt directly in pivot-local degrees therefore
	# mirrored the pegs in switch, so stick-down read as up and left as right. Rotating the stick
	# vector out of screen space and into the pivot's frame keeps the pegs pointing the way the
	# physical stick is actually pushed at ANY yaw, so they stay honest part-way through an aerial
	# spin too, not just at 0 deg and 180 deg.
	#
	# Extended for direction reversals: when gravity reverses rolling direction and the chase camera
	# swings 180 deg around SkaterRoot to track travel, CameraPivot's yaw changes by PI while
	# BoardPivot's remains unaltered. Using the relative angle between camera view and board yaw
	# keeps the pegs honest regardless of camera reversals.
	var yaw: float = angle_difference(camera_yaw, board_yaw)
	var yaw_cos: float = cos(yaw)
	var yaw_sin: float = sin(yaw)
	_drive_ankle_peg(left_peg_pivot, input_state.left_stick_raw, input_state.left_mag, yaw_cos, yaw_sin, delta)
	_drive_ankle_peg(right_peg_pivot, input_state.right_stick_raw, input_state.right_mag, yaw_cos, yaw_sin, delta)

func _drive_ankle_peg(pivot: Node3D, stick: Vector2, mag: float, yaw_cos: float, yaw_sin: float,
		delta: float) -> void:
	if mag <= 0.05:
		pivot.rotation = pivot.rotation.lerp(Vector3.ZERO, peg_follow_speed * delta)
		return
	# Screen-space stick (x = right, y = toward the camera) resolved onto the pivot's local axes.
	var local_x: float = stick.x * yaw_cos - stick.y * yaw_sin
	var local_z: float = stick.x * yaw_sin + stick.y * yaw_cos
	pivot.rotation_degrees.x = lerpf(pivot.rotation_degrees.x, local_z * peg_tilt_deg, peg_follow_speed * delta)
	pivot.rotation_degrees.z = lerpf(pivot.rotation_degrees.z, -local_x * peg_tilt_deg, peg_follow_speed * delta)
