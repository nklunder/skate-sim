extends Node

## Regression suite for steering: carving, pushing, and the interaction between them.
##
## Written to chase a reported feel bug - "the board ends up at a weird angle like I'm pushing it
## sideways and skidding along the wrong wheel axis", and "kicking while turning feels like drifting
## in a car game". Three plausible mechanisms were proposed and all three were DISPROVEN here, which
## is why the cases stay: each one now pins the behaviour that was suspected.
##
##   1. `_realigning` latching grip weak forever. It capped grip at speed * landing_turn_rate_deg
##      (~7 m/s^2 against wheel_side_grip's 40) and clears only under 0.02 m/s of lateral - so a
##      sustained carve looked able to regenerate lateral faster than the capped grip removed it and
##      keep itself armed. Measured: clears within ~6 frames. Not it.
##   2. The kickturn branch teleporting the rig. Below kickturn_max_speed steering anchors on the
##      trailing axle and translates global_position by the pre/post-rotation delta, with no matching
##      change to velocity - and it picks the axle from `leading_foot`, which can flip mid-turn.
##      Measured: 3 mm of unexplained motion per frame. Not it.
##   3. Carving drifting off its own axis at speed. Measured: a steady 2.9 deg, which is just the
##      one-frame lag between grip scrubbing in pipeline step 3 and steering rotating in step 4.
##
## What is left is not a bug at all: `landing_turn_rate_deg = 60` deliberately paces post-landing
## realignment, so a 20 deg residual spends a third of a second sliding sideways - and a push during
## that window drives along the BOARD, i.e. 20 deg off actual travel. Hence push_turn_damping.
##
## Run: godot --headless --path . res://tests/carve_and_push.tscn

const TEST_WORLD := preload("res://scenes/TestWorld.tscn")

var _world: Node3D = null
var _skater: SkaterController = null
var _case: int = 0
var _frame: int = 0
var _failures: int = 0
var _reported: bool = false
var _max_off_axis: float = 0.0
var _max_speed: float = 0.0
var _max_pos_jump: float = 0.0
var _realigning_frames: int = 0
var _prev_pos: Vector3 = Vector3.ZERO
var _start_heading: float = 0.0
## Total heading swept, accumulated per frame. A carve passes 360 deg in a couple of seconds, so a
## plain (now - start) difference folds back on itself and reports a fraction of the real turn.
var _turned: float = 0.0
var _prev_heading: float = 0.0
## World positions of the two axles at the moment the kickturn begins. Whichever one is on the
## GROUND must stay put while the other swings around it.
var _lead_axle_start: Vector3 = Vector3.ZERO
var _trail_axle_start: Vector3 = Vector3.ZERO
var _lead_axle_drift: float = 0.0
var _trail_axle_drift: float = 0.0
var _landed: bool = false
var _air_frames: int = 0
## Worst off-axis angle seen AFTER the landing residual has had time to work off. The residual
## itself is a legitimate transient - a 15 deg landing IS 15 deg off-axis on the touchdown frame -
## so judging on the peak would fail a correct implementation. What must not happen is the board
## still sliding once the residual is spent.
var _settled_off_axis: float = 0.0
const SETTLE_FRAMES: int = 60

# speed: initial roll along the board's own -Z.
# lean: trigger deflection held for the whole run.
# push_every: kick every N frames.
# turned_min / turned_max: bounds on total heading change, in degrees. The pair is the point of the
#   push cases - a push must not stop the carve dead, but must visibly cost turning authority.
const CASES := [
	{"label": "carve @7, no push", "speed": 7.0, "lean": 1.0, "run": 120,
		"turned_min": 300.0, "max_off_axis": 5.0},
	{"label": "carve @7 + push every 12f", "speed": 7.0, "lean": 1.0, "run": 120, "push_every": 12,
		"turned_max": 200.0, "max_off_axis": 5.0},
	{"label": "carve @1.5 + push every 12f", "speed": 1.5, "lean": 1.0, "run": 120, "push_every": 12,
		"turned_max": 200.0, "max_off_axis": 5.0},
	# Below kickturn_max_speed steering anchors on the trailing axle and moves global_position
	# directly. Nothing else in the suites exercises that branch.
	{"label": "kickturn @0.3", "speed": 0.3, "lean": 1.0, "run": 200, "max_pos_jump": 0.02},
	{"label": "kickturn @0.45", "speed": 0.45, "lean": 1.0, "run": 200, "max_pos_jump": 0.02},
	{"label": "kickturn + push from rest", "speed": 0.2, "lean": 1.0, "run": 300, "push_every": 45,
		"max_pos_jump": 0.02},
	# A kickturn must pivot on the axle that is ON THE GROUND. _apply_grounded_board_pitch() lifts the
	# LEADING trucks during a slow turn, so anchoring the leading axle makes the airborne truck the
	# pivot and swings the grounded one around it.
	#
	# pivot_yaw = 180 is SWITCH AND FAKIE, and equally the state a landed body-180 leaves behind:
	# _evaluate_touchdown_landing() rounds board_pivot's yaw to the nearest multiple of 180 and keeps
	# it there, transferring only the remainder to the rig. So the pivot sits half a turn out of phase
	# with SkaterRoot - while the kickturn does its rotation in SkaterRoot's frame. Reported as
	# "in switch stance the front lifted truck is the pivot point", which is exactly this.
	{"label": "kickturn, forward", "speed": 0.3, "lean": 1.0, "run": 150, "check_anchor": true},
	{"label": "kickturn switch / after 180", "speed": 0.3, "lean": 1.0, "run": 150,
		"pivot_yaw": 180.0, "check_anchor": true},
	# THE SKID. Reported as "on landing, hold a trigger and you start skidding in that direction."
	#
	# Touchdown caps wheel grip while the wheels drag travel back onto the board axis, and clears
	# that cap only once lateral speed falls under 0.02 m/s. Steering GENERATES lateral speed, and at
	# full lean it generates it faster than the capped grip removes it - so holding a trigger through
	# a landing stops the cap ever clearing, and the board keeps sliding for as long as you hold it.
	#
	# Both lean signs, because the residual has a direction: steering INTO it shrinks lateral and
	# hides the bug, steering AWAY from it feeds the loop. An earlier version of this suite tested
	# only the first and wrongly concluded the mechanism was innocent.
	{"label": "land 15 deg, then hold lean +", "speed": 7.0, "lean": 1.0, "run": 150,
		"land_yaw": 15.0, "max_settled_off_axis": 4.0, "max_realign_frames": 40},
	{"label": "land 15 deg, then hold lean -", "speed": 7.0, "lean": -1.0, "run": 150,
		"land_yaw": 15.0, "max_settled_off_axis": 4.0, "max_realign_frames": 40},
	{"label": "land -15 deg, then hold lean +", "speed": 7.0, "lean": 1.0, "run": 150,
		"land_yaw": -15.0, "max_settled_off_axis": 4.0, "max_realign_frames": 40},
]

func _ready() -> void:
	_start_case()

func _start_case() -> void:
	if _world != null:
		remove_child(_world)
		_world.queue_free()
	_world = TEST_WORLD.instantiate()
	add_child(_world)
	_skater = _world.get_node("SkaterRig") as SkaterController
	_skater.global_position = Vector3(20.0, _skater.ride_height, 20.0)
	_skater.velocity = Vector3(0.0, 0.0, -float(CASES[_case]["speed"]))
	_frame = 0
	_max_off_axis = 0.0
	_max_speed = 0.0
	_max_pos_jump = 0.0
	_settled_off_axis = 0.0
	_realigning_frames = 0
	_prev_pos = _skater.global_position
	_start_heading = _skater.rotation_degrees.y
	_turned = 0.0
	_prev_heading = _skater.rotation_degrees.y
	if CASES[_case].has("pivot_yaw"):
		# A landed body-180 turns the RIDER and the board together, so both frames carry it. Setting
		# only the board would describe a deck spun 180 underneath a rider who never moved - which is
		# a boardslide, not switch stance, and would leave pivot_reversed() reading the rider's frame
		# a half-turn out from the board's.
		_skater.board_pivot.rotation_degrees.y = float(CASES[_case]["pivot_yaw"])
		_skater.rider_body.rotation_degrees.y = float(CASES[_case]["pivot_yaw"])
	_lead_axle_start = _axle_world(-1.0)
	_trail_axle_start = _axle_world(1.0)
	_lead_axle_drift = 0.0
	_trail_axle_drift = 0.0
	_landed = not CASES[_case].has("land_yaw")
	_air_frames = 0

func _physics_process(delta: float) -> void:
	if _reported or _skater == null:
		return
	var c: Dictionary = CASES[_case]

	# Landing cases pop first and hold a board yaw through the flight, so touchdown deposits a real
	# heading residual and arms the grip cap. Measurement starts on the first GROUNDED frame.
	if c.has("land_yaw") and not _landed:
		_air_frames += 1
		if _air_frames == 5:
			var st: TrickState = _skater.trick
			var sig := TrickSignature.new()
			sig.pop = TrickSignature.Pop.OLLIE
			st.current_trick = sig
			st.current_pop_state = TrickState.PopState.POPPED
			st.pop_impulse_triggered = true
			return
		if _air_frames > 5 and not _skater.is_grounded:
			_skater.board_pivot.rotation_degrees.y = c["land_yaw"]
			_skater.rider_body.rotation_degrees.y = c["land_yaw"]
			return
		if _air_frames > 5 and _skater.is_grounded:
			_landed = true
			_prev_pos = _skater.global_position
			_prev_heading = _skater.rotation_degrees.y
			_lead_axle_start = _axle_world(-1.0)
			_trail_axle_start = _axle_world(1.0)
		else:
			return
	_frame += 1

	# Rewritten every tick: _poll_inputs() zeroes lean with no device attached.
	_skater.rider.lean = float(c["lean"])
	if c.has("push_every") and _frame % int(c["push_every"]) == 0:
		_skater.rider.push_right_triggered = true

	var heading: float = _skater.rotation_degrees.y
	_turned += rad_to_deg(angle_difference(deg_to_rad(_prev_heading), deg_to_rad(heading)))
	_prev_heading = heading
	if _skater._landing_residual > 0.0:
		_realigning_frames += 1
	_max_off_axis = maxf(_max_off_axis, _travel_vs_board())
	if _frame > SETTLE_FRAMES:
		_settled_off_axis = maxf(_settled_off_axis, _travel_vs_board())
	_max_speed = maxf(_max_speed, _skater.current_speed)
	# Motion this frame that velocity does not account for. Ordinary integration leaves this at zero;
	# the kickturn's axle anchoring shows up here, and an anchor flipping axles would show up big.
	# Skipped on frame 1, where there is no previous frame to difference against.
	if _frame > 1:
		var expected: Vector3 = Vector3(_skater.velocity.x, 0.0, _skater.velocity.z) * delta
		var actual: Vector3 = _skater.global_position - _prev_pos
		actual.y = 0.0
		_max_pos_jump = maxf(_max_pos_jump, (actual - expected).length())
	_prev_pos = _skater.global_position
	# Travel starts along the board's own -Z, so in the RIG's frame the leading axle is at -0.225 and
	# the trailing one at +0.225 - regardless of how BoardPivot happens to be yawed.
	_lead_axle_drift = maxf(_lead_axle_drift, _axle_world(-1.0).distance_to(_lead_axle_start))
	_trail_axle_drift = maxf(_trail_axle_drift, _axle_world(1.0).distance_to(_trail_axle_start))

	if _frame >= int(c["run"]):
		_finish_case()

## World position of an axle, in SkaterRoot's frame. `sign` is +1 for the trailing axle, -1 for the
## leading one, given the cases all start rolling along the board's own -Z.
func _axle_world(sign: float) -> Vector3:
	return _skater.to_global(Vector3(0.0, -(_skater.ride_height - _skater.wheel_radius),
		_skater.manual_axle_z * sign))

## Angle between travel and the wheels' rolling axis. Zero means the board goes where it points;
## large means it is sliding sideways across its own wheels. A board rolling fakie counts as
## aligned, since a board rolls equally well either way round.
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
	var turned: float = absf(_turned)
	var detail: String = "turned %5.1f deg | offAxis %4.1f (settled %4.1f) | peak %4.2f m/s | posJump %.4f m | paced %d/%d" % [
		turned, _max_off_axis, _settled_off_axis, _max_speed, _max_pos_jump, _realigning_frames, _frame]

	if c.has("max_off_axis") and _max_off_axis > float(c["max_off_axis"]):
		problems.append("slid %.1f deg off the rolling axis (limit %.1f) - drifting, not carving" % [
			_max_off_axis, c["max_off_axis"]])
	# For landing cases: the residual is allowed its transient, but once spent the board must track
	# its wheels again however hard the rider is steering.
	if c.has("max_settled_off_axis") and _settled_off_axis > float(c["max_settled_off_axis"]):
		problems.append("still %.1f deg off-axis %d frames after landing (limit %.1f) - the skid never ended" % [
			_settled_off_axis, SETTLE_FRAMES, c["max_settled_off_axis"]])
	# The grip cap is a TRANSIENT for working off a landing residual. Steering must never be able to
	# keep it alive - if it can, the board slides for as long as the trigger is held.
	if c.has("max_realign_frames") and _realigning_frames > int(c["max_realign_frames"]):
		problems.append("grip stayed capped for %d of %d frames - steering is feeding the latch" % [
			_realigning_frames, _frame])
	if c.has("max_pos_jump") and _max_pos_jump > float(c["max_pos_jump"]):
		problems.append("rig moved %.4f m unaccounted for by velocity (limit %.4f)" % [
			_max_pos_jump, c["max_pos_jump"]])
	if c.has("turned_min") and turned < float(c["turned_min"]):
		problems.append("expected a full carve, only turned %.1f deg" % turned)
	# Pushing must COST turning authority without killing the turn outright.
	if c.has("turned_max"):
		if turned > float(c["turned_max"]):
			problems.append("pushing did not damp steering: turned %.1f deg (limit %.1f)" % [
				turned, c["turned_max"]])
		if turned < 20.0:
			problems.append("pushing killed steering entirely: only %.1f deg" % turned)
	if c.get("check_anchor", false):
		detail += " | leadAxle %.3f trailAxle %.3f" % [_lead_axle_drift, _trail_axle_drift]
		# The GROUNDED (trailing) axle is the anchor: it must stay put while the lifted leading one
		# swings around it.
		if _trail_axle_drift > _lead_axle_drift:
			problems.append("pivoted on the LIFTED leading axle - grounded axle swung %.3f m while the airborne one moved %.3f m" % [
				_trail_axle_drift, _lead_axle_drift])
		if _trail_axle_drift > 0.05:
			problems.append("grounded axle drifted %.3f m - it should be anchored" % _trail_axle_drift)
	if _max_speed > _skater.max_push_speed + 0.2:
		problems.append("total speed reached %.2f against a %.2f ceiling" % [
			_max_speed, _skater.max_push_speed])

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
