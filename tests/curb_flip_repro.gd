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
## Last airborne frame on which each axis actually moved. Sampling "has it reached its target" from
## outside cannot work: the catch clears the flags and fmods the angles during the controller's own
## tick, so the finishing frame is never visible here. When each axis STOPPED turning is observable,
## and is also the exact thing the eye notices - a board that quits spinning while still flipping.
var _last_roll_move: int = -1
var _last_yaw_move: int = -1
var _status: String = ""
var _speed: float = 0.0
var _catch_err: float = 0.0
var _case: int = 0
var _failures: int = 0
var _reported: bool = false

# Curb1 top is y=0.30 spanning x[0.02, 8.02], z[-6.58, 0.00]. `ledge` spawns a bespoke slab at an
# arbitrary top height in clear space at x=20, which is how the large-catch-error cases are staged:
# they need a landing height between the curb and the platform that the level does not contain.
# `hold_manual` parks the trailing stick in the manual zone for the whole flight.
const CASES := [
	{"label": "kickflip -> curb, manual", "pos": Vector3(4.0, 0.078, 2.0),
		"flip": true, "shuv": 0, "expect": "Landed directly into Manual!", "hold_manual": true},
	{"label": "kickflip -> curb", "pos": Vector3(4.0, 0.078, 2.0),
		"flip": true, "shuv": 0, "expect": "Landed Kickflip!"},
	{"label": "kickflip -> flat", "pos": Vector3(4.0, 0.078, 14.0),
		"flip": true, "shuv": 0, "expect": "Landed Kickflip!"},
	{"label": "kickflip, curb -> flat", "pos": Vector3(4.0, 0.378, -1.0),
		"flip": true, "shuv": 0, "expect": "Landed Kickflip!"},
	{"label": "ollie -> curb, manual", "pos": Vector3(4.0, 0.078, 2.0),
		"flip": false, "shuv": 0, "expect": "Landed directly into Manual!", "hold_manual": true},
	# Sketchy but rideable: deck is ~36 deg short, inside the cone, so the settle runs several
	# frames. This is the case that actually exercises the no-teleport guarantee.
	{"label": "kickflip -> 0.43m ledge", "pos": Vector3(20.0, 0.078, 6.0), "ledge": 0.43,
		"flip": true, "shuv": 0, "expect": "Landed Kickflip!"},
	{"label": "kickflip -> 0.43m, manual", "pos": Vector3(20.0, 0.078, 6.0), "ledge": 0.43,
		"flip": true, "shuv": 0, "expect": "Landed directly into Manual!", "hold_manual": true},
	# Past the cone: deck arrives ~56 deg over, foot would slide off the rail. Must still bail.
	{"label": "kickflip -> 0.55m ledge", "pos": Vector3(20.0, 0.078, 6.0), "ledge": 0.55,
		"flip": true, "shuv": 0, "expect": "BAIL! (Primo Crash / Incomplete Flip)"},
	# Deck arrives ~213 deg round - genuinely upside down. Must still bail.
	{"label": "kickflip -> 0.8m platform", "pos": Vector3(-10.0, 0.078, -10.0),
		"flip": true, "shuv": 0, "expect": "BAIL! (Primo Crash / Incomplete Flip)"},
	# Combined-axis tricks: the sync assertion. Both axes must stop turning on the same frame.
	# No exact name is asserted - these inject a signature directly, so the resolved name is
	# TrickNames' business and would make this suite fail for unrelated naming changes. Landing at
	# all is the assertion; finishing together is the point.
	{"label": "360 flip (tre) -> flat", "pos": Vector3(4.0, 0.078, 14.0),
		"flip": true, "shuv": 360, "sync": true},
	{"label": "varial flip -> flat", "pos": Vector3(4.0, 0.078, 14.0),
		"flip": true, "shuv": 180, "sync": true},
	# Single-axis: nothing to synchronise, but its timing must not have been disturbed by the change.
	{"label": "360 shuv -> flat", "pos": Vector3(4.0, 0.078, 14.0),
		"flip": false, "shuv": 360},
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
	# Set the vector directly: current_speed is read-only, precisely so nothing can assign a speed
	# and have a direction silently inferred for it.
	_skater.velocity = -_skater.global_transform.basis.z * 7.0
	_frame = 0
	_popped = false
	_landed_frame = -1
	_max_roll_step = 0.0
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

	if _frame == 5:
		var st: TrickState = _skater.trick
		var sig := TrickSignature.new()
		sig.pop = TrickSignature.Pop.OLLIE
		sig.flip = TrickSignature.Flip.KICK if CASES[_case]["flip"] else TrickSignature.Flip.NONE
		sig.shuv_deg = CASES[_case]["shuv"]
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
	if _landed_frame < 0:
		if d_roll > 0.001:
			_last_roll_move = _frame
		if d_yaw > 0.001:
			_last_yaw_move = _frame

	if _skater.is_grounded and _landed_frame < 0:
		_landed_frame = _frame
		_status = _skater.trick.trick_status_string
		_speed = _skater.current_speed
		_catch_err = _skater.last_catch_error_deg

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
	# Axis sync: both rotations must stop turning on the same frame.
	if c.get("sync", false):
		if _last_roll_move < 0 or _last_yaw_move < 0:
			problems.append("an axis never turned at all")
		elif _last_roll_move != _last_yaw_move:
			problems.append("roll stopped f%d but yaw stopped f%d (%d frames apart)" % [
				_last_roll_move, _last_yaw_move, absi(_last_roll_move - _last_yaw_move)])
	# The deck must come to rest griptape-up, not a few degrees off.
	if not _skater.is_flip_settling and not _skater.is_flip_in_progress:
		var resting: float = absf(_skater.board_mesh.rotation_degrees.z \
			- SkaterController._nearest_multiple(_skater.board_mesh.rotation_degrees.z, 360.0))
		if resting > 0.01:
			problems.append("settled %.2f deg off resting orientation" % resting)

	if not problems.is_empty():
		_failures += 1
	print("%-28s %s air %2d | err %4.1f | step %5.2f | spd %.2f | %s" % [
		c["label"], "PASS" if problems.is_empty() else "FAIL", _landed_frame - _pop_frame,
		_catch_err, _max_roll_step, _speed, _status])
	for p in problems:
		print("     -> %s" % p)

	_case += 1
	if _case >= CASES.size():
		_reported = true
		print("\n%d/%d passed" % [CASES.size() - _failures, CASES.size()])
		get_tree().quit(1 if _failures > 0 else 0)
	else:
		_start_case()
