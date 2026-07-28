extends Node

## Regression suite for FootRig, and the first coverage it has ever had (CLEANUP #5).
##
## Written now because the feet finally MOVE FOR A REASON. Until the rider had legs, every airborne
## foot curve was authored, and there was nothing to assert that would not simply restate the curve
## back to itself. The invariants below are about the rider's legs driving the shoes, which is a
## property worth pinning:
##
##   THE OLLIE RULE.     A plain ollie - no flip, no scoop - keeps the feet ON the deck for the whole
##                       jump. In a real ollie the board is dragged up BY the front foot, so tucking
##                       the knees raises the rider's HIPS while the feet stay planted and the board
##                       rises with them. Feet release only to let the deck turn over underneath.
##                       Asserted at two pop strengths, because release is a question of whether the
##                       deck is rotating and never of how hard the rider popped.
##   ENOUGH TO CLEAR.    When the deck IS turning, the feet must be clear of it before it gets
##                       edge-on - the tuck is sized against the rotation, not against airtime.
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
	# THE OLLIE RULE. A plain ollie - no flip, no scoop - must keep the feet on the deck for the whole
	# jump. The board is dragged up BY the front foot in a real ollie, so tucking the knees raises the
	# rider's hips while the feet stay planted and the board rises with them. Feet release only to let
	# the deck turn over. Asserted at both loads, because the release is a question of whether the
	# deck is rotating and never of how hard the pop was.
	{"label": "ollie, full pop", "flip": false, "load": 1.0, "min_lift": 0.0, "max_lift": 0.002},
	{"label": "ollie, gentle pop", "flip": false, "load": 0.45, "min_lift": 0.0, "max_lift": 0.002},
	{"label": "kickflip, full pop", "flip": true, "load": 1.0, "min_lift": 0.12, "max_lift": 0.25},
	# A HELD rotation outlasts the leg's tuck, and from that point the deck's clearance demand is the
	# only thing holding the feet up. It must HOLD, not track the deck's silhouette - that oscillates
	# twice per revolution, and the feet pumped between 0.001 m and 0.089 m in time with the board.
	# `max_step` is the assertion: once tucked, no frame may move a foot more than the initial ramp.
	{"label": "held double kickflip", "flip": true, "load": 1.0, "hold_flick": 40, "jump": 16.0,
		"speed": 0.0, "min_lift": 0.12, "max_lift": 0.25, "max_step_after_tuck": 0.004},
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
var _max_step_after_tuck: float = 0.0
var _prev_lift: float = 0.0

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
	_skater.velocity = Vector3(0.0, 0.0, float(CASES[_case].get("speed", 7.0)) * st["dir"])
	_skater.rider.stance = st["stance"]
	# Silence the device poller so written sticks survive the tick; TrickState still ticks, so the
	# real gesture recogniser runs and the pop goes through _release_pop() rather than being injected.
	if CASES[_case].has("jump"):
		_skater.jump_impulse = float(CASES[_case]["jump"])
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
	_max_step_after_tuck = 0.0
	_prev_lift = 0.0

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
		if _frame - _pop_frame < int(c.get("hold_flick", 0)):
			rider.left_stick_raw = Vector2(-0.7, 0.0)
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
		# Only while the DECK IS STILL TURNING, and only after the tuck has peaked and settled. The
		# initial ramp and the release descent are both real motion the rider asked for; what must not
		# move is the hold in between.
		if _frame - _pop_frame > 20 and _skater.is_flip_in_progress:
			_max_step_after_tuck = maxf(_max_step_after_tuck, absf(l_lift - _prev_lift))
		_prev_lift = l_lift
		if _land_frame < 0 and _skater.is_grounded and _frame > _pop_frame + 3:
			_land_frame = _frame
			_lift_at_land = maxf(absf(l_lift), absf(r_lift))
			_finish_case()
	elif _frame > 150:
		_fail("never popped")
		_finish_case()
	if _frame > 400 and not _reported:
		# Never hang. A case that cannot finish must say so - a suite that stops producing output is
		# far harder to diagnose than one that fails (AGENTS.md rule 6).
		_fail("case never completed within 400 frames")
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
		problems.append("peak lift %.3f below %.3f - not clear of a deck that is turning" % [_peak_lift, c["min_lift"]])
	if _peak_lift > float(c["max_lift"]):
		var why: String = "the feet left a deck that was not turning" if float(c["max_lift"]) < 0.01 \
			else "tucked further than the rotation calls for"
		problems.append("peak lift %.3f above %.3f - %s" % [_peak_lift, c["max_lift"], why])
	if _lift_at_land > 0.004:
		problems.append("feet %.4f m off the deck at touchdown - settle_now() is covering for them" % _lift_at_land)
	if _grounded_lift > 0.001:
		problems.append("feet lifted %.4f m while grounded before the pop" % _grounded_lift)
	if c.has("max_step_after_tuck") and _max_step_after_tuck > float(c["max_step_after_tuck"]):
		problems.append("feet moved %.4f m in one frame while the deck was turning - the clearance is tracking the board, not held" % _max_step_after_tuck)
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
