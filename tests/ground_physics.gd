extends Node

## Regression suite for ground dynamics: slope gravity, wheel grip and momentum-based landings.
##
## These behaviours are all consequences of ONE change - velocity became an authoritative world
## vector instead of `-basis.z * current_speed` - so they are asserted together. Each case below
## used to be impossible to express:
##
##   SLOPES.   Gravity did not act on a grounded skater at all; speed only ever decreased. Holding
##             on gentle gradients, rolling down steep ones and reversing when stalled are not three
##             features, they are friction compared against the fall line in one place.
##   LANDINGS. Touchdown snapped board yaw to a perfect 0/180 and bailed on a fixed 45-135 deg
##             window with no speed term. Now the residual heading is kept and the bail is decided
##             by lateral momentum, so tolerance scales with speed on its own.
##
## Run: godot --headless --path . res://tests/ground_physics.tscn

const TEST_WORLD := preload("res://scenes/TestWorld.tscn")
const G := 16.0 # Mirrors SkaterController.gravity_accel; only used to document expectations here.

var _world: Node3D = null
var _skater: SkaterController = null
var _frame: int = 0
var _case: int = 0
var _failures: int = 0
var _reported: bool = false
var _start_heading: float = 0.0
var _popped: bool = false
var _landed: bool = false
var _land_status: String = ""
var _land_speed: float = 0.0
var _land_slide: float = 0.0
var _peak_speed: float = 0.0
var _min_speed: float = 1e9
var _reversed: bool = false
var _settle: int = 0
var _pushes: int = 0
## Sideways speed across the board axis. The discriminator for the push-skid regression: a directed
## push leaves this alone for grip to remove, while one that merely rescaled the velocity vector
## scaled it UP along with the forward component.
var _max_lateral: float = 0.0
var _initial_lateral: float = 0.0
## Largest single-frame change in the camera's WORLD yaw, and the residual the landing handed the
## rig. The camera is a rigid child of SkaterRoot, so a landing that jumps rig yaw would jump the
## view by the whole residual at once unless it is eased.
var _max_cam_step: float = 0.0
var _prev_cam_yaw: float = 0.0
var _residual: float = 0.0
## Board world yaw across the touchdown frame. The heading residual is transferred from board_pivot
## to the rig, which must leave the board's WORLD orientation untouched - the rig gains exactly what
## the pivot gives up. Asserted because "it just feels abrupt" could not distinguish a camera swing
## from the board itself jerking, and this rules the board out for good.
var _board_jump: float = 0.0
var _prev_board_yaw: float = 0.0
## Largest single-frame rotation of the TRAVEL direction. Grip used to be at full strength on the
## first grounded frame, so an imperfect landing swung the direction of motion by the whole residual
## in one tick while the camera eased over eight - a smooth view over a world that jerked.
var _max_dir_step: float = 0.0
var _prev_dir: float = 0.0
## Worst framing error seen after touchdown: the angle between where the camera looks and where the
## skater actually is. THE camera invariant - position and aim must derive from the same smoothed
## yaw, or the subject leaves the frame. When this broke, a 70 deg landing put the skater 60.8 deg
## off-axis for 1.2 s, and it did not present as a framing bug at all: it read as "the pan is slow".
var _max_off_centre: float = 0.0
var _rest_off_centre: float = 0.0

# slope: gradient in degrees for a bespoke slab spawned at x=20, z=20, downhill toward +Z.
#   Fall-line acceleration is G*sin(t)*cos(t), so friction (1.0) holds anything under ~3.6 deg.
# land_yaw: board_pivot yaw forced through the whole flight, i.e. the heading the rider lands at.
# speed: initial rolling speed. +Z on a slope case is downhill, -Z is uphill.
const CASES := [
	{"label": "flat: coasts to a stop", "speed": 3.0, "settle": 240, "expect_stopped": true},
	{"label": "2 deg slope: holds at rest", "slope": 2.0, "speed": 0.0, "settle": 180,
		"expect_stopped": true},
	{"label": "15 deg slope: rolls downhill", "slope": 15.0, "speed": 0.0, "settle": 120,
		"expect_rolling": true},
	# expect_swing_sign pins which SIDE of travel the camera settles on, not just how far off it is.
	# Without it both cases assert only a magnitude, so a bug that ignored camera_side entirely left
	# the left-view case silently reproducing the right-view result and still passing. That happened:
	# extracting device polling made the poller overwrite camera_side every frame from its own
	# default, which clobbered the value this harness sets.
	{"label": "bank reversal, right view", "slope": 15.0, "speed": -2.0, "settle": 180,
		"expect_reversal": true, "camera_side": 1, "expect_swing_sign": -1},
	{"label": "bank reversal, left view", "slope": 15.0, "speed": -2.0, "settle": 180,
		"expect_reversal": true, "camera_side": -1, "expect_swing_sign": 1},
	{"label": "land 185 deg @ 7 m/s", "speed": 7.0, "land_yaw": 185.0,
		"expect_landed": true, "expect_drift": 5.0},
	{"label": "land 175 deg @ 7 m/s", "speed": 7.0, "land_yaw": 175.0,
		"expect_landed": true, "expect_drift": -5.0},
	{"label": "land 100 deg @ 7 m/s", "speed": 7.0, "land_yaw": 100.0, "expect_bail": true},
	{"label": "land 100 deg @ 1.5 m/s", "speed": 1.5, "land_yaw": 100.0, "expect_landed": true},
	# Pushing while drifting sideways must STRAIGHTEN the roll, not entrench it. Regression for a
	# skid introduced by the velocity rewrite: current_speed was settable, and assigning it rescaled
	# the horizontal velocity while preserving direction - so a kick scaled the sideways component
	# up along with the forward one and drove the skater along a crooked line.
	# Pushes start immediately, while the drift is still there to be amplified: grip scrubs a 40 deg
	# drift away in about five frames, so a test that waits even a moment measures nothing.
	{"label": "push while drifting sideways", "speed": -5.0, "settle": 90, "drift_deg": 40.0,
		"push_every": 1, "expect_straighten": true},
	# Carving now pays the same lateral-scrub toll as a crooked landing, because it is the same
	# mechanism: turning the rig puts velocity off the rolling axis and grip drags it back. It must
	# cost SOME speed (that is the weight the rewrite adds) without bleeding the skater dry.
	{"label": "carve: turns, keeps speed", "speed": -7.0, "settle": 60, "lean": 1.0,
		"expect_carve": true},
	# Preserved direction: coasting backward (+Z) to a stop on flat ground must preserve backward travel,
	# so pushing from zero speed accelerates backward instead of flipping forward (-Z).
	{"label": "rollback stop preserves push", "speed": 3.0, "settle": 240,
		"push_at_stop": true, "expect_preserved_push": true},
]

func _ready() -> void:
	_start_case()

## Slab tilted about X so downhill runs toward +Z. Placed clear of every TestWorld obstacle.
## Surface height directly above the body centre works out to centre.y + halfheight/cos(t).
func _spawn_slope(deg: float) -> float:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12.0, 0.4, 24.0)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(20.0, 1.0, 20.0)
	body.rotation.x = deg_to_rad(deg)
	_world.add_child(body)
	return 1.0 + 0.2 / cos(deg_to_rad(deg))

func _start_case() -> void:
	if _world != null:
		remove_child(_world)
		_world.queue_free()
	_world = TEST_WORLD.instantiate()
	add_child(_world)
	_skater = _world.get_node("SkaterRig") as SkaterController
	var c: Dictionary = CASES[_case]
	if c.has("slope"):
		var surf: float = _spawn_slope(c["slope"])
		_skater.global_position = Vector3(20.0, surf + _skater.ride_height, 20.0)
	else:
		_skater.global_position = Vector3(20.0, _skater.ride_height, 20.0)
	# Set velocity directly rather than via current_speed: the setter has no direction to preserve at
	# rest and would fall back to the board axis, which is -Z. These cases need a signed Z.
	# Slope cases need a signed Z (+Z is downhill). Landing cases roll forward, i.e. along the board's
	# own -Z axis, so travel starts aligned with the deck and the residual is the only thing off.
	var vz: float = -c["speed"] if c.has("land_yaw") else c["speed"]
	_skater.velocity = Vector3(0.0, 0.0, vz)
	if c.has("drift_deg"):
		_skater.velocity = _skater.velocity.rotated(Vector3.UP, deg_to_rad(c["drift_deg"]))
	if c.has("camera_side"):
		_skater.rider.camera_side = c["camera_side"]
	_frame = 0
	_popped = false
	_landed = false
	_peak_speed = 0.0
	_min_speed = 1e9
	_reversed = false
	_settle = 0
	_pushes = 0
	_max_lateral = 0.0
	_initial_lateral = _lateral_speed()
	_max_cam_step = 0.0
	_residual = 0.0
	_board_jump = 0.0
	_max_dir_step = 0.0
	_max_off_centre = 0.0
	_rest_off_centre = 0.0
	_prev_dir = _travel_dir()
	_prev_cam_yaw = _cam_yaw()
	_prev_board_yaw = _board_yaw()
	_start_heading = _skater.rotation_degrees.y

func _physics_process(_delta: float) -> void:
	if _reported or _skater == null:
		return
	_frame += 1
	var c: Dictionary = CASES[_case]

	var cam: float = _cam_yaw()
	_max_cam_step = maxf(_max_cam_step, absf(rad_to_deg(angle_difference(
		deg_to_rad(_prev_cam_yaw), deg_to_rad(cam)))))
	_prev_cam_yaw = cam

	if c.has("land_yaw"):
		_run_landing_case(c)
	else:
		_run_slope_case(c)

func _run_slope_case(c: Dictionary) -> void:
	_max_lateral = maxf(_max_lateral, _lateral_speed())
	if c.has("push_every") and _frame % int(c["push_every"]) == 0:
		_skater.rider.push_right_triggered = true
		_pushes += 1
	if c.has("push_at_stop") and _skater.current_speed < 0.01 and _pushes == 0:
		_skater.rider.push_right_triggered = true
		_pushes += 1
	if c.has("lean"):
		_skater.rider.lean = c["lean"] # Zeroed by _poll_inputs each tick with no device attached.
	var speed: float = _skater.current_speed
	_peak_speed = maxf(_peak_speed, speed)
	_min_speed = minf(_min_speed, speed)
	if _skater.velocity.z > 0.05 and c["speed"] < 0.0:
		_reversed = true # Launched uphill (-Z), now travelling downhill (+Z).
	if _frame >= int(c["settle"]):
		_finish_case()

func _run_landing_case(c: Dictionary) -> void:
	# Pop a plain ollie, hold the landing heading through the flight, then judge the touchdown.
	if _frame == 5 and not _popped:
		var st: TrickState = _skater.trick
		var sig := TrickSignature.new()
		sig.pop = TrickSignature.Pop.OLLIE
		sig.flip = TrickSignature.Flip.NONE
		st.current_trick = sig
		st.current_pop_state = TrickState.PopState.POPPED
		st.pop_impulse_triggered = true
		_popped = true
		return
	if not _popped:
		return
	# Sampled before the harness writes land_yaw below, so this compares the last airborne frame
	# against the first grounded one - exactly the transfer.
	# Only meaningful while actually rolling; a wash-out drops to zero speed and the heading of a
	# zero vector is not a direction.
	if _landed:
		_max_off_centre = maxf(_max_off_centre, _off_centre())
	else:
		# Last airborne reading is the settled baseline: the camera has had the whole flight to
		# reach its resting framing, including the lateral slide.
		_rest_off_centre = _off_centre()
	var dir: float = _travel_dir()
	if _skater.current_speed > 0.5:
		_max_dir_step = maxf(_max_dir_step, absf(rad_to_deg(angle_difference(
			deg_to_rad(_prev_dir), deg_to_rad(dir)))))
	_prev_dir = dir
	var bw: float = _board_yaw()
	if _skater.is_grounded and not _landed:
		_board_jump = absf(rad_to_deg(angle_difference(deg_to_rad(_prev_board_yaw), deg_to_rad(bw))))
	_prev_board_yaw = bw
	if not _skater.is_grounded:
		_skater.board_pivot.rotation_degrees.y = c["land_yaw"]
		return
	if not _landed:
		_landed = true
		_land_status = _skater.trick.trick_status_string
		_land_speed = _skater.current_speed
		_land_slide = _skater.last_landing_slide
		_residual = absf(rad_to_deg(angle_difference(
			deg_to_rad(_start_heading), deg_to_rad(_skater.rotation_degrees.y))))
		return
	# Dedicated counter. Reusing _frame here re-tripped the `_frame == 5` pop above, so every landing
	# case silently flew twice and applied its heading residual twice.
	_settle += 1
	# Long enough for both the camera AND travel to give back a full wash-out residual at 60 deg/s:
	# 80 deg is 1.33 s, i.e. 80 frames. Slow landings realign slower still, so allow headroom.
	if _settle >= 150:
		_finish_case()

## Angle between the camera's view direction and the direction to the skater. Constant while the
## framing holds; a spike means the subject has drifted out of shot.
func _off_centre() -> float:
	var cam: Camera3D = _skater.get_node("CameraPivot/Camera3D") as Camera3D
	var to_skater: Vector3 = _skater.global_position - cam.global_position
	if to_skater.length_squared() < 0.0001:
		return 0.0
	return rad_to_deg((-cam.global_transform.basis.z).angle_to(to_skater.normalized()))

## Component of travel across the board's rolling axis.
func _lateral_speed() -> float:
	var v := Vector3(_skater.velocity.x, 0.0, _skater.velocity.z)
	var axis: Vector3 = -_skater.global_transform.basis.z
	axis.y = 0.0
	if axis.length_squared() < 0.0001:
		return 0.0
	axis = axis.normalized()
	return (v - axis * v.dot(axis)).length()

## Heading of travel in world degrees. Undefined at a standstill, so callers must gate on speed.
func _travel_dir() -> float:
	var v := Vector2(_skater.velocity.x, _skater.velocity.z)
	return rad_to_deg(v.angle()) if v.length_squared() > 0.0001 else _prev_dir

## Signed angle between where the camera faces and the direction of travel. At rest this should sit
## at +/- camera_side_offset_deg, its sign telling you which side the camera has chosen.
func _cam_vs_travel() -> float:
	var v := Vector2(_skater.velocity.x, _skater.velocity.z)
	if v.length() < _skater.travel_min_speed:
		return 0.0
	return rad_to_deg(angle_difference(atan2(-v.x, -v.y), deg_to_rad(_cam_yaw())))

## Board yaw in world terms: the rig's heading plus the deck's own switch-stance/spin yaw.
func _board_yaw() -> float:
	return _skater.rotation_degrees.y + _skater.board_pivot.rotation_degrees.y

## Camera yaw in world terms: CameraPivot is a child of the rig, so its world yaw is the sum.
func _cam_yaw() -> float:
	return _skater.rotation_degrees.y + _skater.camera_pivot.rotation_degrees.y

## Angle between travel and the wheels' rolling axis. Zero once grip has pulled them into line;
## a board rolling fakie counts as aligned, since a board rolls equally well either way round.
func _travel_vs_board() -> float:
	var v := Vector3(_skater.velocity.x, 0.0, _skater.velocity.z)
	if v.length_squared() < 0.0001:
		return 0.0
	var axis: Vector3 = -_skater.global_transform.basis.z
	axis.y = 0.0
	var a: float = rad_to_deg(v.normalized().angle_to(axis.normalized()))
	return minf(a, 180.0 - a)

func _finish_case() -> void:
	var c: Dictionary = CASES[_case]
	var problems: Array[String] = []
	var speed: float = _skater.current_speed
	var detail: String = ""

	if c.get("expect_stopped", false):
		detail = "final %.3f m/s (peak %.2f)" % [speed, _peak_speed]
		if speed > 0.01:
			problems.append("expected to come to rest, still moving at %.3f m/s" % speed)
	elif c.get("expect_rolling", false):
		detail = "final %.2f m/s downhill" % _skater.velocity.z
		if _skater.velocity.z < 1.0:
			problems.append("expected to roll downhill, reached only %.2f m/s" % _skater.velocity.z)
	elif c.get("expect_straighten", false):
		var off: float = _travel_vs_board()
		detail = "%d pushes | %.2f m/s | off %.1f deg | lateral %.2f peak vs %.2f start" % [
			_pushes, speed, off, _max_lateral, _initial_lateral]
		if _pushes < 3:
			problems.append("test did not actually push")
		# A push must never grow the sideways component. This is the assertion that distinguishes a
		# directed drive from a rescale of the whole velocity vector.
		if _max_lateral > _initial_lateral + 0.05:
			problems.append("pushing amplified sideways speed %.2f -> %.2f" % [
				_initial_lateral, _max_lateral])
		if off > 2.0:
			problems.append("still %.1f deg off the board axis - pushes are driving it crooked" % off)
		if speed < 3.0:
			problems.append("pushing failed to build speed: %.2f m/s" % speed)
	elif c.get("expect_carve", false):
		var turned: float = absf(rad_to_deg(angle_difference(
			deg_to_rad(_start_heading), deg_to_rad(_skater.rotation_degrees.y))))
		detail = "turned %.0f deg | %.2f -> %.2f m/s" % [turned, _peak_speed, speed]
		if turned < 20.0:
			problems.append("expected the carve to turn the skater, only %.0f deg" % turned)
		if speed < _peak_speed * 0.5:
			problems.append("carve bled too much speed: %.2f -> %.2f m/s" % [_peak_speed, speed])
		if _land_status.begins_with("BAIL"):
			problems.append("carving should never wash out")
	elif c.get("expect_reversal", false):
		detail = "%.2f m/s downhill | camVsTravel %+.1f | camStep %.2f" % [
			_skater.velocity.z, _cam_vs_travel(), _max_cam_step]
		if not _reversed:
			problems.append("expected to stall and roll back down, never reversed")
		# THE bank-reversal requirement: once genuinely rolling back down, the camera must have
		# swung round to chase, not sat there watching the skater approach.
		if absf(_cam_vs_travel()) > _skater.camera_pivot.camera_side_offset_deg + 3.0:
			problems.append("camera did not swing round to chase: %.1f deg off travel" % _cam_vs_travel())
		# And it must have swung toward the side the offset selects, at a paced rate.
		if c.has("expect_swing_sign") and signf(_cam_vs_travel()) != float(c["expect_swing_sign"]):
			problems.append("camera settled on the wrong side: %+.1f deg" % _cam_vs_travel())
		if _max_cam_step > _skater.camera_pivot.camera_max_swing_deg / 60.0 + 0.3:
			problems.append("camera swung %.2f deg in one frame (limit %.2f)" % [
				_max_cam_step, _skater.camera_pivot.camera_max_swing_deg / 60.0])
	elif c.get("expect_preserved_push", false):
		detail = "final v_z %.2f m/s (%d pushes after stop)" % [_skater.velocity.z, _pushes]
		if _pushes < 1:
			problems.append("never came to a full stop to trigger push")
		if _skater.velocity.z <= 0.5:
			problems.append("push after rollback stop propelled forward (vz=%.2f) instead of preserving backward roll" % _skater.velocity.z)
	else:
		var bailed: bool = _land_status.begins_with("BAIL")
		var drift: float = rad_to_deg(angle_difference(
			deg_to_rad(_start_heading), deg_to_rad(_skater.rotation_degrees.y)))
		detail = "slide %.2f | %.2f m/s | drift %+.1f | boardjump %.2f | cam %.2f/%.1f" % [
			_land_slide, _land_speed, drift, _board_jump, _max_cam_step, _residual]
		detail += " | dir %.2f | offCentre %.1f (rest %.1f)" % [
			_max_dir_step, _max_off_centre, _rest_off_centre]
		# The subject must stay framed THROUGHOUT. A few degrees of drift is the positional damping
		# doing its job; tens of degrees means position and aim have come apart again.
		if _max_off_centre > _rest_off_centre + 8.0:
			problems.append("skater drifted %.1f deg off centre (resting %.1f) - camera lost framing" % [
				_max_off_centre, _rest_off_centre])
		# Travel must turn progressively as grip loads, never in a single frame.
		if _residual > 1.0 and not bailed and _max_dir_step > _residual * 0.4:
			problems.append("travel direction turned %.2f deg of a %.1f deg residual in one frame" % [
				_max_dir_step, _residual])
		if _board_jump > 0.01:
			problems.append("board world orientation jumped %.2f deg at touchdown" % _board_jump)
		# The camera must spread the rig's jump over several frames, never inherit it whole.
		if _residual > 1.0:
			# Rate limited: the camera may never swing faster than camera_max_swing_deg, whatever
			# the provocation. Landings should barely move it at all now, since it tracks travel
			# and travel does not jump at touchdown.
			var cap: float = _skater.camera_pivot.camera_max_swing_deg / 60.0 + 0.3
			if _max_cam_step > cap:
				problems.append("camera moved %.2f deg in one frame (limit %.2f)" % [
					_max_cam_step, cap])
			# The camera settles behind TRAVEL, offset to the chosen side - not behind the rig.
			if absf(_cam_vs_travel()) > _skater.camera_pivot.camera_side_offset_deg + 2.0:
				problems.append("camera settled %.1f deg off travel (expected ~%.0f)" % [
					_cam_vs_travel(), _skater.camera_pivot.camera_side_offset_deg])
		if c.get("expect_bail", false) and not bailed:
			problems.append("expected a wash-out, got \"%s\"" % _land_status)
		if c.get("expect_landed", false):
			if bailed:
				problems.append("expected to ride away, got \"%s\"" % _land_status)
			# Heading must carry the residual instead of snapping to a perfect 0/180.
			if c.has("expect_drift") and absf(drift - c["expect_drift"]) > 0.6:
				problems.append("expected %+.1f deg of drift, measured %+.1f" % [c["expect_drift"], drift])
			# Grip must then pull travel back onto the board's axis.
			if _travel_vs_board() > 1.0:
				problems.append("travel still %.1f deg off the board axis after settling" % _travel_vs_board())

	if not problems.is_empty():
		_failures += 1
	print("%-30s %s | %s" % [c["label"], "PASS" if problems.is_empty() else "FAIL", detail])
	for p in problems:
		print("     -> %s" % p)

	_case += 1
	if _case >= CASES.size():
		_reported = true
		print("\n%d/%d passed" % [CASES.size() - _failures, CASES.size()])
		get_tree().quit(1 if _failures > 0 else 0)
	else:
		_start_case()
