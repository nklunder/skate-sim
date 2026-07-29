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

## Path radius, sampled per frame as v / omega. THIS is the invariant carving now has to hold: lean
## sets a turn RADIUS, and the angular rate is whatever v / R makes it. Swept degrees were only ever
## a proxy for "the board turns", and they are a bad one under this model - they change with speed by
## design, so a bound on them measures the test's starting speed as much as the physics.
##
## Sampled only above _RADIUS_MIN_SPEED. Below that the kickturn owns steering, which is a flat rate
## and deliberately has no constant radius; including it would average two different mechanisms.
var _radius_sum: float = 0.0
var _radius_samples: int = 0
var _rate_sum: float = 0.0
const _RADIUS_MIN_SPEED: float = 1.0

# speed: initial roll along the board's own -Z.
# lean: trigger deflection held for the whole run.
# push_every: kick every N frames.
# turned_min / turned_max: bounds on total heading change, in degrees. The pair is the point of the
#   push cases - a push must not stop the carve dead, but must visibly cost turning authority.
const CASES := [
	# THE CARVE MODEL. Lean sets a turn radius and omega = v / R follows, so the SAME lean draws the
	# same arc at every speed while the angular rate scales with it. Three speeds because one point
	# cannot tell a correct radius from a flat rate that happens to agree there - which is exactly how
	# the old model passed: it was calibrated at riding speed and ~4x too fast at walking pace.
	#
	# Rates are the run MEAN, and speed decays under rolling friction over the 60 frames, so each sits
	# a little under the v/R figure for its starting speed (7 m/s -> 134 deg/s, 4 -> 76, 2 -> 38).
	{"label": "carve radius @7", "speed": 7.0, "lean": 1.0, "run": 60,
		"radius_m": 3.0, "rate_deg_s": 128.0, "max_off_axis": 5.0},
	{"label": "carve radius @4", "speed": 4.0, "lean": 1.0, "run": 60,
		"radius_m": 3.0, "rate_deg_s": 72.0, "max_off_axis": 5.0},
	{"label": "carve radius @2", "speed": 2.0, "lean": 1.0, "run": 60,
		"radius_m": 3.0, "rate_deg_s": 34.0, "max_off_axis": 5.0},
	# Half lean must DOUBLE the radius, not halve it. Lean maps to a truck steer angle, and curvature
	# is what is linear in that angle - so this is the case that would catch lean being applied to R.
	{"label": "carve radius @4, half lean", "speed": 4.0, "lean": 0.5, "run": 60,
		"radius_m": 6.0, "radius_tol": 0.5, "max_off_axis": 5.0},
	# RE-BASELINED by 07a, from turned_min 300. A full-lean carve at 7 m/s is now a 3 m circle, which
	# is 360 deg in ~2.7 s rather than the ~2.1 s the flat 172 deg/s gave - so 120 frames no longer
	# completes a lap, and asserting that it does would be asserting the OLD model. The bound stays a
	# coarse "the carve is not being killed" guard; the radius cases above are what pin the physics.
	{"label": "carve @7, no push", "speed": 7.0, "lean": 1.0, "run": 120,
		"turned_min": 190.0, "max_off_axis": 5.0},
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
	# A MANUAL MUST STILL STEER. is_preparing_pop() fires at pop_load_threshold, so a manual held
	# deeper than that used to be charged the POP's 80% damping - full authority below 0.70 and a
	# fifth of it above, a cliff in the middle of a trick the rider is actively balancing. Both
	# depths are tested because only the deep one was ever broken, and a single shallow case would
	# have reported the mechanism healthy.
	#
	# RE-BASELINED by 07a, from min_turned 100. At 4 m/s a full-lean carve is 76 deg/s, and
	# manual_turn_damping keeps 80% of it - so ~61 deg/s, or ~55 deg over the 60-frame run once
	# friction is counted, where the flat model gave ~135. The bound still catches the bug it exists
	# for by a wide margin: charging the manual the POP's 0.2 damping instead would turn ~14 deg.
	{"label": "steer in a shallow manual", "speed": 4.0, "lean": 1.0, "run": 60,
		"manual_hold": 0.50, "min_turned": 45.0},
	{"label": "steer in a DEEP manual", "speed": 4.0, "lean": 1.0, "run": 60,
		"manual_hold": 0.85, "min_turned": 45.0},
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
	_radius_sum = 0.0
	_radius_samples = 0
	_rate_sum = 0.0

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
	if c.has("manual_hold"):
		# Trailing stick held down: the balance input that puts the deck up on one truck.
		# The poller must be silenced or TrickState never sees it - it is a CHILD of RiderInput and
		# ticks after the poll that zeroes the sticks, so current_pop_state would stay NONE and
		# is_preparing_pop() could never fire. Without this the case cannot reproduce the very cliff
		# it exists to pin, and passes whether the bug is present or not.
		_skater.rider.set_physics_process(false)
		_skater.rider.right_stick_raw = Vector2(0.0, float(c["manual_hold"]))
		_skater.rider.right_mag = _skater.rider.right_stick_raw.length()
	if c.has("push_every") and _frame % int(c["push_every"]) == 0:
		_skater.rider.push_right_triggered = true

	var heading: float = _skater.rotation_degrees.y
	var swept: float = rad_to_deg(angle_difference(deg_to_rad(_prev_heading), deg_to_rad(heading)))
	_turned += swept
	_prev_heading = heading

	# R = v / omega, per frame. Constant radius across a decaying speed is the whole claim.
	var planar_speed: float = Vector3(_skater.velocity.x, 0.0, _skater.velocity.z).length()
	var rate: float = absf(swept) / delta
	if planar_speed >= _RADIUS_MIN_SPEED and rate > 0.01 and _skater.is_grounded:
		_radius_sum += planar_speed / deg_to_rad(rate)
		_rate_sum += rate
		_radius_samples += 1
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
	if c.has("min_turned"):
		if not _skater.is_manualing():
			problems.append("never entered a manual - the case is not testing what it claims")
		elif turned < float(c["min_turned"]):
			problems.append("turned only %.1f deg in a manual, expected at least %.1f - steering authority is being cut" % [
				turned, float(c["min_turned"])])
	var mean_radius: float = (_radius_sum / _radius_samples) if _radius_samples > 0 else 0.0
	var mean_rate: float = (_rate_sum / _radius_samples) if _radius_samples > 0 else 0.0
	var detail: String = "turned %5.1f deg | offAxis %4.1f (settled %4.1f) | peak %4.2f m/s | posJump %.4f m | paced %d/%d" % [
		turned, _max_off_axis, _settled_off_axis, _max_speed, _max_pos_jump, _realigning_frames, _frame]

	# The carve model itself: lean sets the radius, speed sets the rate.
	if c.has("radius_m"):
		detail += " | R %.2f m @ %5.1f deg/s" % [mean_radius, mean_rate]
		if _radius_samples < int(c["run"]) / 2:
			problems.append("only %d radius samples in %d frames - the carve never sustained" % [
				_radius_samples, _frame])
		elif absf(mean_radius - float(c["radius_m"])) > float(c.get("radius_tol", 0.25)):
			problems.append("carved a %.2f m radius, expected %.2f +/- %.2f - lean is not setting a RADIUS" % [
				mean_radius, float(c["radius_m"]), float(c.get("radius_tol", 0.25))])
	# The rate must SCALE with speed, which is what the old flat-rate model got wrong. Asserted per
	# case so the three probe speeds together pin the slope, not just one point on it.
	if c.has("rate_deg_s") and absf(mean_rate - float(c["rate_deg_s"])) > float(c.get("rate_tol", 12.0)):
		problems.append("turned at %.1f deg/s, expected ~%.1f - the rate is not tracking speed" % [
			mean_rate, float(c["rate_deg_s"])])

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
