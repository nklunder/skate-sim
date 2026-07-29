extends Node

## Regression suite for deck rotation: the late-catch landing rule, and axis synchronisation.
##
## Originally the reproduction for "kickflip into a manual on the curb stalls every time". Both bugs
## it now guards share one cause - deck rotation was a set of independent fixed-duration animations
## rather than one trick - so they are asserted together:
##
##   1. CATCH. Landability is judged on deck ORIENTATION against a cone derived from deck geometry
##      and shoe friction, never on whether an animation finished. Hang time must not decide it.
##   2. SYNC. Roll and yaw finish on the SAME frame however they are combined, so a 360 flip cannot
##      stop spinning while it is still flipping.
##   3. SMOOTH. The deck is never teleported to its resting orientation; per-frame rotation stays
##      within the angular velocity the trick actually carried.
##
## Drives the REAL SkaterController by writing the state RiderInput would have written.
## Run: godot --headless --path . res://tests/curb_flip_repro.tscn

const TEST_WORLD := preload("res://scenes/TestWorld.tscn")

var _world: Node3D = null
var _skater: SkaterController = null
var _frame: int = 0
var _pop_frame: int = 0
var _popped: bool = false
var _landed_frame: int = -1
var _prev_roll: float = 0.0
var _prev_yaw: float = 0.0
var _max_roll_step: float = 0.0
## Per-frame roll steps for the ramp assertions - see the profile block. `_last_full_roll_step` is
## the step BEFORE the final one, and the distinction is load-bearing: the final step is a partial,
## clamped by move_toward as it lands exactly on the target, so its size is set by where the target
## happens to fall on the frame grid rather than by the deck's rate. Asserting on it passed a deck
## with no catch ramp at all.
var _first_roll_step: float = 0.0
var _last_roll_step: float = 0.0
var _last_full_roll_step: float = 0.0
## Precession wobble on BoardMesh's THIRD axis (07b). Peak in flight, and whatever is left at
## touchdown. The second is the one that matters: the wobble is airborne-only and nothing advances it
## once grounded, so anything surviving the landing is a permanent tilt on the deck.
var _peak_wobble: float = 0.0
var _wobble_at_land: float = 0.0
## Last airborne frame on which each axis actually moved. Sampling "has it reached its target" from
## outside cannot work: the catch clears the flags and fmods the angles during the controller's own
## tick, so the finishing frame is never visible here. When each axis STOPPED turning is observable,
## and is also the exact thing the eye notices - a board that quits spinning while still flipping.
var _last_roll_move: int = -1
var _last_yaw_move: int = -1
var _status: String = ""
var _speed: float = 0.0
var _catch_err: float = 0.0
var _turns: int = 0
var _rolled: float = 0.0
var _peak_rolled: float = 0.0
var _prev_roll_signed: float = 0.0
var _reversed: float = 0.0
var _case: int = 0
var _failures: int = 0
var _reported: bool = false

# Curb1 top is y=0.30 spanning x[0.02, 8.02], z[-6.58, 0.00]. `ledge` spawns a bespoke slab at an
# arbitrary top height in clear space at x=20, which is how the large-catch-error cases are staged:
# they need a landing height between the curb and the platform that the level does not contain.
# `hold_manual` parks the trailing stick in the manual zone for the whole flight.
const CASES := [
	{"label": "kickflip -> curb, manual", "pos": Vector3(4.0, 0.078, 2.0),
		"flip": true, "scoop": 0, "expect": "Landed directly into Manual!", "hold_manual": true},
	{"label": "kickflip -> curb", "pos": Vector3(4.0, 0.078, 2.0),
		"flip": true, "scoop": 0, "expect": "Landed Kickflip!"},
	{"label": "kickflip -> flat", "pos": Vector3(4.0, 0.078, 14.0),
		"flip": true, "scoop": 0, "expect": "Landed Kickflip!"},
	{"label": "kickflip, curb -> flat", "pos": Vector3(4.0, 0.378, -1.0),
		"flip": true, "scoop": 0, "expect": "Landed Kickflip!"},
	{"label": "ollie -> curb, manual", "pos": Vector3(4.0, 0.078, 2.0),
		"flip": false, "scoop": 0, "expect": "Landed directly into Manual!", "hold_manual": true},
	# THE CONE, in three regimes. What each case pins is the deck ERROR at touchdown and which side
	# of catch_cone_deg it lands, NOT any particular ledge height - the ledge is only how airtime is
	# shortened. So when the pop was raised (jump_impulse 5.2 -> 6.0) and all three gained ~8 frames
	# of hang time, the fix was to slow the deck rather than to raise the obstacles: flip_speed is
	# already a per-case knob, while the 0.8 m platform is fixed world geometry. 608 -> 486 restores
	# ~36 / ~52 / ~85 deg of error, which is where these sat before.
	#
	# Then 07b's spin-up ramp cost every one of them a further 8.1 deg - a CONSTANT angular deficit
	# rather than a proportional one, which is why all three moved by the same amount: ramping 1/3,
	# 2/3, 1 over three frames loses exactly one frame of rotation, and 486/60 = 8.1. 486 -> 498 pays
	# it back. If the ramp durations are retuned, this is the figure that moves with them.
	#
	# Sketchy but rideable: deck is ~36 deg short, inside the cone, so the settle runs several
	# frames. This is the case that actually exercises the no-teleport guarantee.
	{"label": "kickflip -> 0.43m ledge", "pos": Vector3(20.0, 0.078, 6.0), "ledge": 0.43,
		"flip": true, "scoop": 0, "expect": "Landed Kickflip!", "flip_speed": 498.0},
	{"label": "kickflip -> 0.43m, manual", "pos": Vector3(20.0, 0.078, 6.0), "ledge": 0.43,
		"flip": true, "scoop": 0, "expect": "Landed directly into Manual!", "hold_manual": true, "flip_speed": 498.0},
	# Past the cone: deck arrives ~56 deg over, foot would slide off the rail. Must still bail.
	{"label": "kickflip -> 0.55m ledge", "pos": Vector3(20.0, 0.078, 6.0), "ledge": 0.55,
		"flip": true, "scoop": 0, "expect": "BAIL! (Primo Crash / Incomplete Flip)", "flip_speed": 498.0},
	# Deck arrives ~213 deg round - genuinely upside down. Must still bail.
	{"label": "kickflip -> 0.8m platform", "pos": Vector3(-10.0, 0.078, -10.0),
		"flip": true, "scoop": 0, "expect": "BAIL! (Primo Crash / Incomplete Flip)", "flip_speed": 498.0},
	# THE RATE PROFILE (07b). Ramp up, hold, ramp down - see the ramp assertion in _finish_case().
	# A tre flip is included because the ramps scale BOTH axes by one shared factor: sync is a
	# rate-RATIO lock, so ramping the axes independently would pull the trick apart mid-ramp and put
	# it back together afterwards. Its "sync" flag is what catches that, and it is the reason the
	# ramp is a single scalar rather than a per-axis envelope.
	{"label": "kickflip, rate profile", "pos": Vector3(4.0, 0.078, 14.0),
		"flip": true, "scoop": 0, "ramps": true},
	{"label": "tre flip, ramped in sync", "pos": Vector3(4.0, 0.078, 14.0),
		"flip": true, "scoop": 360, "ramps": true, "sync": true},
	# Combined-axis tricks: the sync assertion. Both axes must stop turning on the same frame.
	# No exact name is asserted - these inject a signature directly, so the resolved name is
	# TrickNames' business and would make this suite fail for unrelated naming changes. Landing at
	# all is the assertion; finishing together is the point.
	{"label": "360 flip (tre) -> flat", "pos": Vector3(4.0, 0.078, 14.0),
		"flip": true, "scoop": 360, "sync": true},
	{"label": "varial flip -> flat", "pos": Vector3(4.0, 0.078, 14.0),
		"flip": true, "scoop": 180, "sync": true},
	# Single-axis: nothing to synchronise, but its timing must not have been disturbed by the change.
	{"label": "360 scoop -> flat", "pos": Vector3(4.0, 0.078, 14.0),
		"flip": false, "scoop": 360},
	# FLICK INTENSITY. How hard the stick was thrown scales the rotation rate, so the same trick
	# finishes sooner or later. Measured throws at 60 Hz from a 0.7 deflection: 1 frame = 42 units/s,
	# 3 = 14 (the reference), 12 = 3.5. Bounds below are on the frame the roll stops.
	#
	# A signature with NO flick measurement means "unmeasured", not "flicked infinitely slowly" - the
	# keyboard pop sets none, and every other case here injects one. Those must take the reference
	# rate, which is what keeps this whole feature a no-op for the rest of the suite.
	# RE-BASELINED by 07b, from 24. The spin-up ramp delays every completion by about a frame, and a
	# hard flick has the least room to absorb it because it finishes soonest. What the pair still
	# pins is the GAP between a hard and a lazy flick, which is untouched at 4+ frames.
	{"label": "kickflip, hard flick", "pos": Vector3(4.0, 0.078, 14.0),
		"flip": true, "scoop": 0, "flick_speed": 42.0, "roll_stops_before": 26},
	{"label": "kickflip, lazy flick", "pos": Vector3(4.0, 0.078, 14.0),
		"flip": true, "scoop": 0, "flick_speed": 3.5, "roll_stops_after": 30},
	# HELD ROTATION. The deck free-spins for as long as the flick is held and settles to the NEAREST
	# resting orientation on release - so how far it gets is simply how long the rider held, and
	# nothing is quantised or committed to up front. `jump` buys the airtime.
	#
	# expect_turns is measured on the rotation ACHIEVED, not on any target, because there is no
	# longer a target while free-spinning. The roll-step cap above still applies: the rate must not
	# change when free-spin begins, since that transition is meant to be invisible.
	{"label": "double kickflip (held)", "pos": Vector3(4.0, 0.078, 14.0),
		"flip": true, "scoop": 0, "hold_flick": 46, "jump": 16.0, "expect_turns": 2,
		"max_reversed": 50.0},
	# Released just past a completion, which is the case that used to unwind furthest. A board with
	# angular momentum does not spin backwards in mid-air, so the correction must stay inside
	# flip_unwind_max_deg - beyond that the momentum wins and it carries on round instead.
	{"label": "release mid-turn", "pos": Vector3(4.0, 0.078, 14.0),
		"flip": true, "scoop": 0, "hold_flick": 36, "jump": 16.0, "max_reversed": 50.0},
	{"label": "triple kickflip (held)", "pos": Vector3(4.0, 0.078, 14.0),
		"flip": true, "scoop": 0, "hold_flick": 72, "jump": 16.0, "expect_turns": 3},
	{"label": "double tre flip (held)", "pos": Vector3(4.0, 0.078, 14.0),
		"flip": true, "scoop": 360, "hold_flick": 58, "jump": 16.0, "expect_turns": 2, "sync": true},
	# A stick that is still DEFLECTED but no longer pointing where it was flicked must stop
	# sustaining. The rider flicks left and then pushes down - reaching for a manual on the way in -
	# and that must not read as "keep flipping". Deflection alone cannot tell the two apart; only
	# alignment can, which is what flick_hold_alignment is for.
	{"label": "flick then steer away", "pos": Vector3(4.0, 0.078, 14.0),
		"flip": true, "scoop": 0, "hold_flick": 46, "after_flick": Vector2(0.0, 0.7),
		"max_reversed": 50.0,
		"jump": 16.0, "expect_turns": 2},
]

func _ready() -> void:
	_start_case()

func _spawn_ledge(top: float) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 4.0, 30.0)
	shape.shape = box
	body.add_child(shape)
	# Front face at z = +4, well clear of the pop, so the wall probe never sees it from the ground.
	body.position = Vector3(20.0, top - 2.0, -11.0)
	_world.add_child(body)

func _start_case() -> void:
	if _world != null:
		remove_child(_world)
		_world.queue_free()
	_world = TEST_WORLD.instantiate()
	add_child(_world)
	if CASES[_case].has("ledge"):
		_spawn_ledge(CASES[_case]["ledge"])
	_skater = _world.get_node("SkaterRig") as SkaterController
	_skater.global_position = CASES[_case]["pos"]
	if CASES[_case].has("flip_speed"):
		_skater.flip_speed_deg = CASES[_case]["flip_speed"]
	if CASES[_case].has("jump"):
		_skater.jump_impulse = float(CASES[_case]["jump"])
	if CASES[_case].has("hold_flick"):
		# `flick_held` is computed by TrickState, which is a CHILD of RiderInput and so ticks after
		# its poll - unlike the hold_manual trick above, whose consumer runs earlier and beats the
		# zeroing. A held stick therefore has to survive the tick, so the poller is silenced. Only
		# for these cases, so nothing else in the suite changes.
		_skater.rider.set_physics_process(false)
	# Set the vector directly: current_speed is read-only, precisely so nothing can assign a speed
	# and have a direction silently inferred for it.
	_skater.velocity = -_skater.global_transform.basis.z * 7.0
	_frame = 0
	_popped = false
	_landed_frame = -1
	_max_roll_step = 0.0
	_first_roll_step = 0.0
	_last_roll_step = 0.0
	_last_full_roll_step = 0.0
	_peak_wobble = 0.0
	_wobble_at_land = 0.0
	_rolled = 0.0
	_peak_rolled = 0.0
	_prev_roll_signed = _skater.board_mesh.rotation_degrees.z
	_reversed = 0.0
	_last_roll_move = -1
	_last_yaw_move = -1
	if _case == 0:
		print("deck half-width %.4f m | underside y %+.4f m | catch cone %.1f deg\n" % [
			_skater.deck_half_width, _skater.deck_underside_y, _skater.catch_cone_deg])

func _physics_process(_delta: float) -> void:
	if _reported or _skater == null:
		return
	_frame += 1

	# RiderInput._poll_inputs() zeroes the sticks every tick in headless (no device attached).
	# This node sits above SkaterRig in tree order, so writing here lands before the controller reads.
	if _popped and CASES[_case].get("hold_manual", false):
		_skater.rider.right_stick_raw = Vector2(0.0, 0.60) # trailing stick, inside 0.20-0.90
	# Hold the flick out for a while after the pop: each completion reached while it is still held
	# buys another turn.
	if _popped and _frame - _pop_frame < int(CASES[_case].get("hold_flick", 0)):
		_skater.rider.left_stick_raw = Vector2(-0.7, 0.0)
	elif CASES[_case].has("hold_flick"):
		_skater.rider.left_stick_raw = CASES[_case].get("after_flick", Vector2.ZERO)

	if _frame == 5:
		var st: TrickState = _skater.trick
		var sig := TrickSignature.new()
		sig.pop = TrickSignature.Pop.OLLIE
		sig.flip = TrickSignature.Flip.KICK if CASES[_case]["flip"] else TrickSignature.Flip.NONE
		sig.scoop_deg = CASES[_case]["scoop"]
		if CASES[_case].has("flick_speed"):
			sig.flick_speed = float(CASES[_case]["flick_speed"])
		if CASES[_case].has("hold_flick"):
			# The suite injects the pop, so it must also declare the flick that _build_trick_signature()
			# would have recorded - otherwise there is no direction to judge "still held" against.
			st._flick_dir = Vector2(-1.0, 0.0)
			st._flick_is_left = true
		st.current_trick = sig
		st.last_scoop_sign = -1.0
		st.current_pop_state = TrickState.PopState.POPPED
		st.pop_impulse_triggered = true
		_popped = true
		_pop_frame = _frame
		_prev_roll = _skater.board_mesh.rotation_degrees.z
		_prev_yaw = _skater.board_mesh.rotation_degrees.y
		return

	if not _popped:
		return

	# Per-frame movement of each axis, measured as an ANGLE so the fmod wrap closing a rotation does
	# not read as a 360 deg jump. The roll figure doubles as the teleport guard: a deck snapped flat
	# would show up here as an oversized step.
	var roll: float = _skater.board_mesh.rotation_degrees.z
	var yaw: float = _skater.board_mesh.rotation_degrees.y
	var d_roll: float = absf(rad_to_deg(angle_difference(deg_to_rad(_prev_roll), deg_to_rad(roll))))
	var d_yaw: float = absf(rad_to_deg(angle_difference(deg_to_rad(_prev_yaw), deg_to_rad(yaw))))
	_prev_roll = roll
	_prev_yaw = yaw
	_max_roll_step = maxf(_max_roll_step, d_roll)
	if not _skater.is_grounded:
		_peak_wobble = maxf(_peak_wobble, absf(_skater.board_mesh.rotation_degrees.x))
	# THE RATE PROFILE (07b). A real deck does not start or stop rotating instantly, so the per-frame
	# step must ramp up, hold flat, and ramp down. Recorded as the first and last MOVING frames
	# against the peak; a deck with no ramps reports all three equal.
	if d_roll > 0.01:
		if _first_roll_step <= 0.0:
			_first_roll_step = d_roll
		_last_full_roll_step = _last_roll_step
		_last_roll_step = d_roll
	# SIGNED, deliberately: d_roll above is an absolute step, so accumulating it would make an
	# unwinding deck appear to keep turning forwards and the reversal below could never be non-zero.
	_rolled += rad_to_deg(angle_difference(deg_to_rad(_prev_roll_signed), deg_to_rad(roll)))
	_prev_roll_signed = roll
	# A deck in mid-air does not spin backwards, so any UNWINDING is a correction the rider's feet
	# made, and it must stay small enough to read as one.
	_peak_rolled = maxf(_peak_rolled, absf(_rolled))
	_reversed = maxf(_reversed, _peak_rolled - absf(_rolled))
	if _landed_frame < 0:
		if d_roll > 0.001:
			_last_roll_move = _frame
		if d_yaw > 0.001:
			_last_yaw_move = _frame

	if _skater.is_grounded and _landed_frame < 0:
		_landed_frame = _frame
		# Turns ACHIEVED, not asked for. Holding no longer buys turns up front - the deck free-spins
		# and settles to the nearest resting orientation - so the target says nothing about how far
		# it actually got.
		_turns = int(roundf(absf(_rolled) / 360.0))
		_status = _skater.trick.trick_status_string
		_speed = _skater.current_speed
		_catch_err = _skater.last_catch_error_deg
		_wobble_at_land = absf(_skater.board_mesh.rotation_degrees.x)

	if _landed_frame >= 0 and _frame - _landed_frame >= 20:
		_finish_case()

func _finish_case() -> void:
	var c: Dictionary = CASES[_case]
	var problems: Array[String] = []
	var bailed: bool = _status.begins_with("BAIL")
	if c.has("expect"):
		if _status != c["expect"]:
			problems.append("expected \"%s\"" % c["expect"])
	elif bailed:
		problems.append("expected a landing, got a bail")
	# No teleport: the deck may never move further in one frame than the rotation it carried.
	# Exempt from bails, which deliberately slam the deck back to flat as part of the crash.
	if not bailed:
		var cap: float = maxf(absf(_skater.flip_roll_rate), _skater.flip_speed_deg) / 60.0
		if _max_roll_step > cap + 0.5:
			problems.append("roll jumped %.2f deg in one frame (cap %.2f)" % [_max_roll_step, cap])
	# THE RAMPS (07b). The deck used to go 0 -> full rate in one frame at the pop and full -> 0 in one
	# frame at completion. Nothing physical does that, and it was the largest single reason tricks
	# read as machine-driven. A foot applies torque over its contact time, and the feet absorb the
	# catch over a few frames.
	#
	# Asserted as a RATIO to the peak step, so it stays true if the rates or the ramp durations are
	# retuned. Without the ramps all three figures are equal and both bounds fail at once.
	if c.get("ramps", false):
		if _max_roll_step <= 0.0:
			problems.append("the deck never turned - the ramp case is not testing what it claims")
		else:
			var up: float = _first_roll_step / _max_roll_step
			var down: float = _last_full_roll_step / _max_roll_step
			if up > float(c.get("max_first_frac", 0.5)):
				problems.append("first frame was %.2f of peak rate (limit %.2f) - the deck starts spinning instantly" % [
					up, float(c.get("max_first_frac", 0.5))])
			if down > float(c.get("max_last_frac", 0.75)):
				problems.append("last frame was %.2f of peak rate (limit %.2f) - the deck stops dead rather than being caught" % [
					down, float(c.get("max_last_frac", 0.75))])
	# THE WOBBLE (07b). Visual only, on an axis nothing else reads - so what can go wrong is not that
	# it disturbs a landing but that it OUTLIVES one. Nothing advances it while grounded, so a
	# non-zero tilt at touchdown is simply left on the deck forever.
	if c.get("ramps", false) and _peak_wobble < 0.5:
		problems.append("deck never wobbled (peak %.2f deg) - the precession term is not running" % _peak_wobble)
	# Checked on EVERY case, not just the ramp ones. A trick that finishes in the air has its wobble
	# wound down by the decay branch long before touchdown, so those cases cannot see the landing
	# clear at all - it is the deck still turning AS it lands (the ledge cases, and every bail) that
	# actually exercises it.
	if _wobble_at_land > 0.001:
		problems.append("deck landed still tilted %.3f deg on its third axis - the wobble outlived the trick" % _wobble_at_land)
	# Axis sync: both rotations must stop turning on the same frame.
	if c.get("sync", false):
		if _last_roll_move < 0 or _last_yaw_move < 0:
			problems.append("an axis never turned at all")
		elif _last_roll_move != _last_yaw_move:
			problems.append("roll stopped f%d but yaw stopped f%d (%d frames apart)" % [
				_last_roll_move, _last_yaw_move, absi(_last_roll_move - _last_yaw_move)])
	if c.has("max_reversed") and _reversed > float(c["max_reversed"]):
		problems.append("deck unwound %.1f deg, over %.1f - a mid-air reversal that large reads as the physics running backwards" % [
			_reversed, float(c["max_reversed"])])
	# Held rotation: the turn count must have grown by the time the deck came down.
	if c.has("expect_turns") and _turns != int(c["expect_turns"]):
		problems.append("completed %d roll turns, expected %d - holding the flick did not extend it" % [
			_turns, int(c["expect_turns"])])
	# Flick intensity: a harder throw must finish the rotation sooner, a lazy one later.
	if c.has("roll_stops_before") and _last_roll_move >= int(c["roll_stops_before"]):
		problems.append("roll stopped f%d, expected before f%d - a hard flick did not speed it up" % [
			_last_roll_move, int(c["roll_stops_before"])])
	if c.has("roll_stops_after") and _last_roll_move <= int(c["roll_stops_after"]):
		problems.append("roll stopped f%d, expected after f%d - a lazy flick did not slow it down" % [
			_last_roll_move, int(c["roll_stops_after"])])
	# The deck must come to rest griptape-up, not a few degrees off.
	if not _skater.is_flip_settling and not _skater.is_flip_in_progress:
		var resting: float = absf(_skater.board_mesh.rotation_degrees.z \
			- SkaterController._nearest_multiple(_skater.board_mesh.rotation_degrees.z, 360.0))
		if resting > 0.01:
			problems.append("settled %.2f deg off resting orientation" % resting)

	if not problems.is_empty():
		_failures += 1
	var line: String = "%-28s %s air %2d | err %4.1f | step %5.2f | spd %.2f | %s" % [
		c["label"], "PASS" if problems.is_empty() else "FAIL", _landed_frame - _pop_frame,
		_catch_err, _max_roll_step, _speed, _status]
	if c.get("ramps", false) and _max_roll_step > 0.0:
		line += " | ramp %.2f -> 1.00 -> %.2f | wobble %.2f -> %.3f" % [
			_first_roll_step / _max_roll_step, _last_full_roll_step / _max_roll_step,
			_peak_wobble, _wobble_at_land]
	print(line)
	for p in problems:
		print("     -> %s" % p)

	_case += 1
	if _case >= CASES.size():
		_reported = true
		print("\n%d/%d passed" % [CASES.size() - _failures, CASES.size()])
		get_tree().quit(1 if _failures > 0 else 0)
	else:
		_start_case()
