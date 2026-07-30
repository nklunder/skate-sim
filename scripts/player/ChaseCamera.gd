class_name ChaseCamera
extends Node3D

## Chase camera: a spring arm orbiting the skater.
##
## Lives on the CameraPivot node, a child of SkaterRoot but deliberately NOT of BoardPivot or
## SurfaceAlign, so the view never rolls with a ramp or spins with a trick.
##
## THE INVARIANT: position and aim must come from the SAME smoothed yaw, or the subject leaves the
## frame. The boom therefore lives on Camera3D and this node orbits the rig origin, so rotating it
## walks the camera AROUND the skater while it keeps facing them. Put the boom offset back on this
## node and rotating it spins the camera on the spot instead - which reads as "the pan is too slow",
## not as a framing bug, so it is worth knowing where to look.
##
## The camera chases the DIRECTION OF TRAVEL, not the board's heading. Roll up a bank and back down
## and gravity reverses your travel without touching rig yaw, so a board-following camera just sits
## there watching you come at it. Travel-following gets fakie right for free too: land a 180 and your
## travel is unchanged, so the shot correctly does not move even though the board reversed. It is
## also why no jump-absorbing machinery is needed here - board heading jumps at touchdown, travel
## does not.
##
## Driven by an explicit follow() call from SkaterController's frame pipeline, never its own
## _physics_process: the camera MUST run after position integration, and self-driving would make that
## ordering a property of node order in SkaterRig.tscn rather than something visible in the code.

## How tightly the chase camera converges on the yaw it is heading for.
##
## Governs CONTINUOUS tracking only - steering, essentially. Trail during a turn is roughly
## turn_rate / this at sustained full lean, so ~7 deg at the default 3.0 rad/s. Raise for a tighter,
## more rigid feel; lower for a looser one. Very high values reproduce rigid parenting exactly.
##
## Paired with camera_max_swing_deg, which paces the GOAL. A single rate could not serve both: fast
## enough that ground turns do not feel boaty was far too fast for a half-turn reversal, and slow
## enough to pace the reversal made every turn feel like steering a barge.
@export var camera_follow_speed: float = 25.0
## Fastest the camera may swing around the skater, in degrees per second. Set comfortably above the
## ~172 deg/s the board can yaw under full lean, so ordinary steering passes through untouched and
## only genuine REORIENTATIONS are paced - chiefly reversing down a bank, which asks for most of a
## half-turn at once.
@export var camera_max_swing_deg: float = 220.0
## ORBIT component of the side view: how far around the skater the camera swings, in degrees.
##
## Kept small on purpose. Orbiting rotates the camera's AIM, so travel stops pointing at the centre
## of the screen and the world streams diagonally - on a wide FOV that asymmetric stretch reads as
## distortion. The visible part of the side view is camera_side_offset_m, which shifts the viewpoint
## without turning it.
##
## MUST NOT BE ZERO: it is the entire tie-break for a travel reversal. Anchored to the rig's lateral
## axis, so the rider's sides do not move when gravity turns them round; the camera must cross to the
## other side RELATIVE TO TRAVEL, making the swing 180 - 2x one way against 180 + 2x the other, and
## shortest-path smoothing then picks a direction on its own. At 0 a dead-straight reversal is a
## coin-flip needing a stored swing sign. Even a few degrees is a decisive margin.
@export var camera_side_offset_deg: float = 2.5
## POSITIONAL component: how far the camera slides sideways, in metres. This is the part you see.
##
## Shifts the viewpoint while the aim stays along travel, so the vanishing point stays centred and
## the skater sits off-centre instead - an over-the-shoulder framing rather than a lean. Contributes
## nothing to the reversal tie-break, which is why the orbit term above survives at all.
@export var camera_side_offset_m: float = 0.26
## How quickly the view slides across when the d-pad selects the other side. Low is a deliberate
## sweep; high snaps. Smooths the SELECTION rather than the two offsets separately, so the orbit and
## the slide always move together and cannot disagree part-way through a switch.
@export var camera_side_switch_speed: float = 3.5
## How hard the camera's follow position is corrected toward the skater.
##
## Velocity is fed forward before this is applied, so riding at a constant speed produces NO lag at
## all and the framing is exactly as authored. Only CHANGES in motion - landings, wall stops - let
## the camera fall behind and catch up, which is where the sense of weight comes from. This is also
## the seam to hang per-trick camera work off later (grinds, manuals): offset the follow position and
## everything downstream keeps working.
@export var camera_position_damp: float = 12.0

## Degrees of extra field of view at full speed, on top of whatever the camera was authored with.
## Speed is felt largely through how fast texture streams past the edges of the frame, and a fixed
## lens gives 2 m/s and 7 m/s the same peripheral flow.
##
## Kept DELIBERATELY SUBTLE - speed-scaled FOV is a racing-game convention, and the reference this
## sim chases sells speed through sound, a low camera and pavement texture instead. Wide enough to
## read as a swell at full speed, not as the world bending.
##
## Set to 0.0 to disable entirely: nothing else reads it, so the lens simply never moves. Worth
## knowing for motion sensitivity, which a swelling FOV can provoke.
@export var fov_gain_deg: float = 4.0
## Speed at which the full gain is reached, in m/s. Defaults to the rig's own max_push_speed, so the
## lens is wide open exactly when the rider is going as fast as pushing can carry them.
@export var fov_speed_ref: float = 7.0
## How quickly the lens chases the speed it is being shown, per second.
##
## Deliberately slow - about a quarter-second constant at 4.0. FOV that tracks speed instantly reads
## as the lens breathing on every push stroke and every landing; lagging it turns the same change
## into a swell that arrives after the acceleration is felt, which is what sells it.
@export var fov_response: float = 4.0

@onready var camera_boom: Camera3D = $Camera3D
## The rig this camera orbits. Resolved from the parent rather than exported: CameraPivot is only
## ever a child of SkaterRoot, and an exported reference would be one more thing to wire up per scene
## and one more way for a duplicated rig to end up filming the wrong skater.
@onready var skater: SkaterController = get_parent() as SkaterController

## Authored camera offset, captured in _ready() so the lateral slide has a fixed origin to work from
## rather than accumulating onto whatever it left behind last frame.
var _camera_boom_rest: Vector3 = Vector3.ZERO
var _camera_lateral: float = 0.0
## Selected side, smoothed to a continuous -1..+1. Passing through zero mid-switch sweeps the camera
## through dead centre, which is what makes the change read as a move rather than a cut.
var _camera_side_smooth: float = 1.0
## Smoothed world yaw of the camera, tracked separately from the rig's so the two can diverge.
var _camera_yaw: float = 0.0
## Rate-limited yaw the camera is heading for. Separate from _camera_yaw so the limiter paces the
## GOAL while the lerp softens the start and stop of the move - a bare rate limit would begin and end
## the swing with a step change in angular velocity.
var _camera_target_yaw: float = 0.0
## Last heading of travel worth trusting. Updated only above the rig's travel_min_speed, so a skater
## hanging at the top of a bank keeps the heading they arrived with instead of reading noise.
var _travel_heading: float = 0.0
## Damped world position the camera orbits around. NOT simply the skater's position: see
## camera_position_damp.
var _camera_pos: Vector3 = Vector3.ZERO
## Field of view the camera was authored with, captured in _ready() so the speed gain has a fixed
## origin. Read from the scene rather than hardcoded, like _camera_boom_rest: duplicating the
## authored value here would let the two disagree the moment anyone adjusts the lens in the editor.
var _fov_rest: float = 75.0

func _ready() -> void:
	if skater == null:
		push_warning("ChaseCamera: parent is not a SkaterController; the camera will not follow.")
		return
	_camera_yaw = skater.rotation.y
	_camera_target_yaw = skater.rotation.y
	_travel_heading = skater.rotation.y
	_camera_pos = skater.global_position
	_camera_boom_rest = camera_boom.position
	_fov_rest = camera_boom.fov

## Advances the camera one frame. Called explicitly by SkaterController after position integration -
## see the class comment for why this is not a _physics_process.
func follow(delta: float) -> void:
	if skater == null:
		return
	var velocity: Vector3 = skater.velocity

	# Heading of travel, held below a threshold: the heading of a near-zero vector is noise, and that
	# is exactly the state at the top of a bank just before a reversal.
	#
	# Measured ALONG THE WHEELS, not on total speed. Only motion along the rolling axis carries the
	# rider somewhere they are pointed; sideways motion is a translation of a rider whose heading has
	# not changed. A standing directional pop leaps bodily sideways at up to 1.5 m/s, clearing
	# travel_min_speed outright - read as a heading it swings the camera 90 deg mid-flight and PARKS
	# it there, since travel stops on landing and the last heading is held.
	#
	# Costs the bank reversal nothing, which is the case this guard exists for: gravity reverses
	# travel ALONG the axis, so the component tested here is exactly the one that flips sign.
	var flat := Vector2(velocity.x, velocity.z)
	var roll_axis := Vector2(-skater.global_transform.basis.z.x, -skater.global_transform.basis.z.z)
	if roll_axis.length_squared() > 0.000001 \
			and absf(flat.dot(roll_axis.normalized())) > skater.travel_min_speed:
		_travel_heading = atan2(-flat.x, -flat.y)

	# Where the camera wants to sit: behind travel, orbited toward the rider's chosen side. A node
	# at yaw t looks along (-sin t, -cos t), so "behind" is the opposite.
	var behind := Vector2(sin(_travel_heading), cos(_travel_heading))
	_camera_side_smooth = lerpf(_camera_side_smooth, float(skater.rider.camera_side),
		minf(camera_side_switch_speed * delta, 1.0))
	var side := Vector2(skater.global_transform.basis.x.x, skater.global_transform.basis.x.z)
	var pos_dir := behind
	var perp_dir := Vector2.ZERO
	if side.length_squared() > 0.000001:
		side = side.normalized()
		# Only the part of the side vector lying ACROSS the view line can offset the camera. Taking
		# the perpendicular component keeps this continuous: travelling exactly sideways, the offset
		# fades smoothly to nothing and returns on the other side, where a sign test would flip and
		# make the camera chatter on the boundary.
		var perp: Vector2 = side - behind * side.dot(behind)
		if perp.length() > 0.001:
			perp_dir = perp.normalized()
			# Both offsets scale by the SAME smoothed selection, so a switch eases the orbit and the
			# slide in step and passes cleanly through centre instead of flipping sign.
			pos_dir = (behind + perp_dir * tan(deg_to_rad(camera_side_offset_deg))
				* _camera_side_smooth).normalized()
	var desired: float = atan2(pos_dir.x, pos_dir.y)

	# Rate-limit the goal, then smooth toward it. The limiter is what turns a reversal into a swing
	# rather than a snap; the lerp rounds off the start and stop the limiter would otherwise leave.
	var step: float = deg_to_rad(camera_max_swing_deg) * delta
	_camera_target_yaw += clampf(angle_difference(_camera_target_yaw, desired), -step, step)
	_camera_yaw = lerp_angle(_camera_yaw, _camera_target_yaw, minf(camera_follow_speed * delta, 1.0))
	# This node is a child of SkaterRoot, so its world yaw is the rig's rotation.y plus its own local
	# yaw. Solve for the local angle that lands it on the smoothed world yaw.
	rotation.y = angle_difference(skater.rotation.y, _camera_yaw)

	# Lateral slide, in this pivot's own frame - the visible half of the side view.
	#
	# Projecting the side direction onto the pivot's local X gives a signed factor that is +/-1 in
	# normal riding and eases through zero in the degenerate sideways case - the same continuity trick
	# as the orbit term, avoiding a sign() that would flip on the boundary.
	var pivot_x := Vector2(cos(_camera_yaw), -sin(_camera_yaw))
	var lateral_target: float = camera_side_offset_m * _camera_side_smooth * perp_dir.dot(pivot_x)
	_camera_lateral = lerpf(_camera_lateral, lateral_target, minf(camera_follow_speed * delta, 1.0))
	camera_boom.position.x = _camera_boom_rest.x + _camera_lateral

	# Follow position, velocity fed forward so constant-speed riding has zero lag and the authored
	# framing is untouched. Only changes in motion make the camera fall behind.
	_camera_pos += velocity * delta
	_camera_pos = _camera_pos.lerp(skater.global_position, minf(camera_position_damp * delta, 1.0))
	global_position = _camera_pos

	# Speed-scaled FOV. Touches the LENS ONLY - no yaw, no position, no aim - so it cannot disturb the
	# invariant at the top of this file, structurally rather than by being small.
	#
	# PLANAR speed on purpose. current_speed drops the vertical component, so a pop does not punch the
	# lens open on every ollie and shut again on landing.
	var speed_frac: float = clampf(skater.current_speed / maxf(fov_speed_ref, 0.01), 0.0, 1.0)
	camera_boom.fov = lerpf(camera_boom.fov, _fov_rest + fov_gain_deg * speed_frac,
		minf(fov_response * delta, 1.0))
