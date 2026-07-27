class_name FootRig
extends Node

## The rider's feet: shoe boxes and ankle pegs, and every animation that moves them.
##
## PRESENTATION ONLY. Nothing here feeds back into physics - no probe, landing check or velocity
## term reads a foot position. The one thing physics DOES read is where the feet are relative to the
## deck, and that goes through FootInputState.update_stance_facts(), which is handed `left_foot` and
## `right_foot` directly. So the rule is: this node may move the feet however it likes, but it must
## never be the thing that decides anything.
##
## Sits under BoardPivot so the feet it drives are its siblings, and so foot poses stay expressed in
## the deck's own frame - a foot at rest is at a fixed local offset whatever the board is doing.
##
## Driven by explicit calls from SkaterController's frame pipeline, never by its own
## _physics_process, for the same reason ChaseCamera is: the push stroke and the flip hover both
## write foot positions, and step 8 of the pipeline overwrites them again on the ground. Which of
## those wins has to be decided by call order that is visible in the pipeline, not by node order in
## SkaterRig.tscn.

## Max ankle peg lean at full stick deflection.
@export var peg_tilt_deg: float = 35.0
## Duration of one push stroke, in seconds.
@export var push_anim_duration: float = 0.25
## Height the shoe boxes lift to while the deck spins underneath them, in metres. Clears the
## rotating deck so the board does not visibly pass through the rider's feet mid-flip.
@export var flip_hover_height: float = 0.18
## Rate the feet lerp toward whichever pose is being asked for.
@export var foot_follow_speed: float = 16.0

@onready var left_foot: Node3D = $"../LeftFoot"
@onready var right_foot: Node3D = $"../RightFoot"
@onready var left_peg_pivot: Node3D = $"../LeftFoot/PegPivot"
@onready var right_peg_pivot: Node3D = $"../RightFoot/PegPivot"

# Rest poses are captured from SkaterRig.tscn in _ready() so foot placement has exactly one
# source of truth; hardcoding them here silently reverted any offset set in the scene as soon
# as a push stroke finished.
var left_foot_rest: Vector3 = Vector3(-0.025, 0.055, -0.25)
var right_foot_rest: Vector3 = Vector3(-0.025, 0.055, 0.25)

## Which foot is mid-stroke, and whether a stroke is running at all. Two fields rather than one
## because they are two facts: `Foot` has no "neither" member, and giving it one would weaken the
## leading/trailing pair that uses it, where "neither" is meaningless. The String this replaced was
## compared against "left" / "right" in three places - the exact silent-typo shape the `Foot` enum
## was introduced to remove (see FootInputState).
var is_pushing: bool = false
var active_push_foot: FootInputState.Foot = FootInputState.Foot.LEFT
var push_anim_time: float = 0.0

func _ready() -> void:
	left_foot_rest = left_foot.position
	right_foot_rest = right_foot.position

## Snaps both feet onto their rest poses immediately. Used at touchdown, where the rider's weight
## lands on the deck and there is nothing gradual about it.
func settle() -> void:
	left_foot.position = left_foot_rest
	right_foot.position = right_foot_rest

## Lifts the shoe boxes clear of a deck that is currently spinning underneath them.
func hover(delta: float) -> void:
	var t: float = foot_follow_speed * delta
	left_foot.position.y = lerpf(left_foot.position.y, flip_hover_height, t)
	right_foot.position.y = lerpf(right_foot.position.y, flip_hover_height, t)

## Returns the shoe boxes to riding height once the deck is caught or was never flipping.
func lower(delta: float) -> void:
	var t: float = foot_follow_speed * delta
	left_foot.position.y = lerpf(left_foot.position.y, left_foot_rest.y, t)
	right_foot.position.y = lerpf(right_foot.position.y, right_foot_rest.y, t)

func start_push(foot: FootInputState.Foot) -> void:
	is_pushing = true
	active_push_foot = foot
	push_anim_time = 0.0

## Advances the push stroke and the ankle pegs. `camera_yaw` and `board_yaw` are the local yaws of
## CameraPivot and BoardPivot; see animate_ankle_pegs() for why both are needed.
func animate(delta: float, input_state: FootInputState, camera_yaw: float, board_yaw: float) -> void:
	_animate_ankle_pegs(delta, input_state, camera_yaw, board_yaw)
	_animate_push_stroke(delta, input_state)

func _animate_push_stroke(delta: float, input_state: FootInputState) -> void:
	if not is_pushing:
		return
	push_anim_time += delta
	var progress: float = push_anim_time / push_anim_duration
	if progress >= 1.0:
		settle()
		is_pushing = false
		return
	# Sinusoidal dip toward the deck surface paired with a forward-to-backward sweeping thrust on Z
	var vertical_dip: float = sin(progress * PI) * -0.055
	var pushing_left: bool = active_push_foot == FootInputState.Foot.LEFT
	var left_is_leading: bool = input_state.leading_foot == FootInputState.Foot.LEFT
	var is_mongo_push: bool = pushing_left == left_is_leading
	var lateral_dir: float = -1.0 if is_mongo_push else 1.0 # Mongo reaches to heel side (-X), Standard reaches to toe side (+X)
	var lateral_reach: float = sin(progress * PI) * 0.22 * lateral_dir
	var longitudinal_sweep: float = cos(progress * PI) * -0.15 # Reaches forward at start, thrusts backward at finish!
	if pushing_left:
		left_foot.position = left_foot_rest + Vector3(lateral_reach, vertical_dip, longitudinal_sweep)
	else:
		right_foot.position = right_foot_rest + Vector3(lateral_reach, vertical_dip, longitudinal_sweep)

func _animate_ankle_pegs(delta: float, input_state: FootInputState, camera_yaw: float,
		board_yaw: float) -> void:
	# Each PegPivot hangs under BoardPivot, which yaws to 180 deg in Switch/Fakie while
	# CameraPivot (parented to SkaterRoot) stays put. Driving the tilt directly in pivot-local
	# degrees therefore mirrored the pegs in switch, so stick-down read as up and left as right.
	# Rotating the stick vector out of screen space and into the pivot's frame keeps the pegs
	# pointing the way the physical stick is actually pushed at ANY yaw, so they stay honest
	# part-way through an aerial spin too, not just at 0 deg and 180 deg.
	#
	# Extended for direction reversals: when gravity reverses rolling direction and the chase camera
	# swings 180 deg around SkaterRoot to track travel, CameraPivot's yaw changes by PI while
	# BoardPivot's remains unaltered. We transform screen-space stick inputs using the relative
	# angle between camera view and board yaw so pegs stay honest regardless of camera reversals.
	var yaw: float = angle_difference(camera_yaw, board_yaw)
	var yaw_cos: float = cos(yaw)
	var yaw_sin: float = sin(yaw)
	_drive_ankle_peg(left_peg_pivot, input_state.left_stick_raw, input_state.left_mag, yaw_cos, yaw_sin, delta)
	_drive_ankle_peg(right_peg_pivot, input_state.right_stick_raw, input_state.right_mag, yaw_cos, yaw_sin, delta)

func _drive_ankle_peg(pivot: Node3D, stick: Vector2, mag: float, yaw_cos: float, yaw_sin: float, delta: float) -> void:
	if mag <= 0.05:
		pivot.rotation = pivot.rotation.lerp(Vector3.ZERO, foot_follow_speed * delta)
		return
	# Screen-space stick (x = right, y = toward the camera) resolved onto the pivot's local axes.
	var local_x: float = stick.x * yaw_cos - stick.y * yaw_sin
	var local_z: float = stick.x * yaw_sin + stick.y * yaw_cos
	pivot.rotation_degrees.x = lerpf(pivot.rotation_degrees.x, local_z * peg_tilt_deg, foot_follow_speed * delta)
	pivot.rotation_degrees.z = lerpf(pivot.rotation_degrees.z, -local_x * peg_tilt_deg, foot_follow_speed * delta)
