extends Node

## Regression suite for FootRig, and the first coverage it has ever had (CLEANUP #5).
##
## Written now because the feet finally MOVE FOR A REASON. Until the rider had legs, every airborne
## foot curve was authored, and there was nothing to assert that would not simply restate the curve
## back to itself. The invariants below are about the rider's legs driving the shoes, which is a
## property worth pinning:
##
##   TUCK ON EVERY POP.  This hole has now been dug twice, in two different mechanisms, and both
##                       times it went unnoticed because nothing was watching. The apex catch-stomp
##                       could not move a foot that had never left the deck, and the parabola that
##                       replaced it was parameterised on FLIP progress - so a straight ollie, which
##                       has no flip to be a progress of, lifted the feet by exactly zero for the
##                       whole jump. A tuck now hangs off the POP, and this asserts it.
##   EFFORT SCALES.      A gentle ledge-drop pop must not tuck like a full one.
##   FEET COME HOME.     The shoes must reach the deck by touchdown under their own dynamics, not be
##                       rescued by settle_now(). An animation still travelling at touchdown is one
##                       the landing is covering for.
##   MIRRORS HOLD.       BUG_ARCHIVE #4 records that switch/fakie mirror errors are this project's
##                       recurring bug class, found by play and never by tests because they fail as
##                       a silent mirror image. Every case here runs all four of
##                       {regular, goofy} x {forward, switch}.
##
## Run: godot --headless --path . res://tests/foot_rig.tscn

const TEST_WORLD := preload("res://scenes/TestWorld.tscn")

# load: how hard the pop stick is held, which sets pop_impulse_scale and so the tuck effort.
# min_lift / max_lift: bounds on peak foot lift in metres, the assertion that effort scales.
const CASES := [
	{"label": "ollie, full pop", "flip": false, "load": 1.0, "min_lift": 0.12, "max_lift": 0.25},
	{"label": "kickflip, full pop", "flip": true, "load": 1.0, "min_lift": 0.12, "max_lift": 0.25},
	{"label": "gentle pop (ledge drop)", "flip": false, "load": 0.45, "min_lift": 0.0, "max_lift": 0.06},
]

const STANCES := [
	{"label": "regular fwd", "stance": RiderInput.Stance.REGULAR, "dir": -1.0},
	{"label": "regular sw", "stance": RiderInput.Stance.REGULAR, "dir": 1.0},
	{"label": "goofy fwd", "stance": RiderInput.Stance.GOOFY, "dir": -1.0},
	{"label": "goofy sw", "stance": RiderInput.Stance.GOOFY, "dir": 1.0},
]

var _world: Node3D = null
var _skater: SkaterController = null
var _frame: int = 0
var _case: int = 0
var _stance: int = 0
var _failures: int = 0
var _reported: bool = false

var _pop_frame: int = -1
var _land_frame: int = -1
var _peak_lift: float = 0.0
var _lift_at_land: float = 0.0
var _grounded_lift: float = 0.0
var _max_foot_gap: float = 0.0
var _nan_seen: bool = false
var _lead_start: RiderInput.Foot = RiderInput.Foot.LEFT
var _stance_stable: bool = true

func _ready() -> void:
	_start_case()

func _start_case() -> void:
	if _world != null:
		_world.queue_free()
	_world = TEST_WORLD.instantiate()
	add_child(_world)
	_skater = _world.get_node("SkaterRig") as SkaterController
	var st: Dictionary = STANCES[_stance]
	_skater.global_position = Vector3(20.0, _skater.ride_height, 20.0)
	# Travel direction is what makes a stance switch rather than forward: the rider is unchanged and
	# only the way they are going reverses. Setting the velocity is therefore the whole of it.
	_skater.velocity = Vector3(0.0, 0.0, 7.0 * st["dir"])
	_skater.rider.stance = st["stance"]
	# Silence the device poller so written sticks survive the tick; TrickState still ticks, so the
	# real gesture recogniser runs and the pop goes through _release_pop() rather than being injected.
	_skater.rider.set_physics_process(false)
	_frame = 0
	_pop_frame = -1
	_land_frame = -1
	_peak_lift = 0.0
	_lift_at_land = 0.0
	_grounded_lift = 0.0
	_max_foot_gap = 0.0
	_nan_seen = false
	_stance_stable = true

func _physics_process(_delta: float) -> void:
	if _reported or _skater == null:
		return
	_frame += 1
	var c: Dictionary = CASES[_case]
	var rider: RiderInput = _skater.rider
	var lf: Node3D = _skater.foot_rig.get_node("../LeftFoot") as Node3D
	var rf: Node3D = _skater.foot_rig.get_node("../RightFoot") as Node3D

	if _frame == 3:
		_lead_start = rider.leading_foot
	elif _frame > 3 and rider.leading_foot != _lead_start:
		_stance_stable = false

	# Load the trailing stick, then throw the leading one to release the pop.
	if _frame >= 5 and _pop_frame < 0:
		var back_is_right: bool = rider.leading_foot == RiderInput.Foot.LEFT
		var load := Vector2(0.0, float(c["load"]))
		if back_is_right:
			rider.right_stick_raw = load
		else:
			rider.left_stick_raw = load
		if _frame >= 12:
			var flick := Vector2(-0.7, 0.0) if c["flip"] else Vector2(0.0, -0.5)
			if back_is_right:
				rider.left_stick_raw = flick
			else:
				rider.right_stick_raw = flick
	elif _pop_frame >= 0:
		rider.right_stick_raw = Vector2.ZERO
		rider.left_stick_raw = Vector2.ZERO
	rider.left_mag = rider.left_stick_raw.length()
	rider.right_mag = rider.right_stick_raw.length()

	if _pop_frame < 0 and _skater.trick.current_pop_state == TrickState.PopState.POPPED and _frame >= 12:
		if not c["flip"]:
			_skater.trick.current_trick.flip = TrickSignature.Flip.NONE
		_pop_frame = _frame

	var l_lift: float = lf.position.y - _skater.foot_rig.left_rest.y
	var r_lift: float = rf.position.y - _skater.foot_rig.right_rest.y
	if not (is_finite(l_lift) and is_finite(r_lift) and is_finite(lf.position.x) and is_finite(rf.position.z)):
		_nan_seen = true
	# Both feet ride the same pair of legs, so an airborne divergence between them is a bug. This is
	# the assertion that would have caught the stagger timer that read as robotic.
	_max_foot_gap = maxf(_max_foot_gap, absf(l_lift - r_lift))
	if _skater.is_grounded and _pop_frame < 0:
		_grounded_lift = maxf(_grounded_lift, maxf(l_lift, r_lift))

	if _pop_frame > 0:
		_peak_lift = maxf(_peak_lift, l_lift)
		if _land_frame < 0 and _skater.is_grounded and _frame > _pop_frame + 3:
			_land_frame = _frame
			_lift_at_land = maxf(absf(l_lift), absf(r_lift))
			_finish_case()
	elif _frame > 150:
		_fail("never popped")
		_finish_case()

func _fail(msg: String) -> void:
	_failures += 1
	print("      -> %s" % msg)

func _finish_case() -> void:
	var c: Dictionary = CASES[_case]
	var st: Dictionary = STANCES[_stance]
	var problems: Array[String] = []

	if _nan_seen:
		problems.append("NaN reached a foot transform")
	if not _stance_stable:
		problems.append("leading_foot changed mid-trick")
	if _peak_lift < float(c["min_lift"]):
		problems.append("peak lift %.3f below %.3f - the rider did not tuck" % [_peak_lift, c["min_lift"]])
	if _peak_lift > float(c["max_lift"]):
		problems.append("peak lift %.3f above %.3f - tuck did not scale with pop effort" % [_peak_lift, c["max_lift"]])
	if _lift_at_land > 0.004:
		problems.append("feet %.4f m off the deck at touchdown - settle_now() is covering for them" % _lift_at_land)
	if _grounded_lift > 0.001:
		problems.append("feet lifted %.4f m while grounded before the pop" % _grounded_lift)
	if _max_foot_gap > 0.004:
		problems.append("feet diverged by %.4f m - they share one pair of legs" % _max_foot_gap)

	var ok: bool = problems.is_empty()
	print("%-24s %-12s %s | air %2d f | peak lift %.3f | at land %.4f" % [
		c["label"], st["label"], "PASS" if ok else "FAIL",
		(_land_frame - _pop_frame) if _land_frame > 0 else -1, _peak_lift, _lift_at_land])
	for p in problems:
		_fail(p)

	_stance += 1
	if _stance >= STANCES.size():
		_stance = 0
		_case += 1
	if _case >= CASES.size():
		_reported = true
		var total: int = CASES.size() * STANCES.size()
		print("\n%d/%d passed" % [total - _failures, total])
		get_tree().quit()
		return
	_start_case()
