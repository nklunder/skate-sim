extends Node

## Regression suite for the POP GESTURE - the load-then-flick sequence, driven through the real
## input chain rather than injected.
##
## Written because a reported bug ("sometimes the input sequence feels like it should result in a
## completed trick, but the board never leaves the ground") was invisible to every existing suite.
## `curb_flip_repro` sets `pop_impulse_triggered` directly, so it never runs `_release_pop()` at all;
## the other three never pop from a gesture. The entire recogniser was untested.
##
## THE BUG, for the record. A rider pops by flicking the OPPOSITE stick, so both thumbs move at
## once and the loading one is usually already on its way home when the flick lands. Impulse was
## read LIVE from the load stick at that instant, which made pop height a function of thumb
## synchronisation rather than of how hard the rider loaded:
##
##     load stick at flick   1.00   0.70   0.40   0.10   0.00
##     jump height (m)       0.80   0.80   0.19   0.01   0.00   <- never leaves the ground
##
## Roughly two frames of timing separated a full ollie from nothing, and the trick still REGISTERED -
## the deck flipped, the name resolved - it simply had no height. A second, rarer failure had the
## same face: on a slow flick throw the loading thumb crossed the deadzone before the flicking one
## reached it, both sticks were briefly under `manual_zone_min` on the same frame, and the reset
## clause dropped the load mid-gesture so no pop happened at all.
##
## Both are fixed by treating the tail's compression as PHYSICAL STATE with a spring-back rate
## rather than as a live readout of the thumb. The cases below pin that from both sides: the
## forgiveness must be real, and it must not swallow the graded low-pop response it sits on top of.
##
## Run: godot --headless --path . res://tests/pop_gesture.tscn

const TEST_WORLD := preload("res://scenes/TestWorld.tscn")

# hold        steady deflection the rider settles at before flicking
# pre         optional harder load held for the first 10 frames, then eased to `hold`
# wait        frames spent at `hold` before the flick is thrown
# flick_over  frames the flick takes to travel out (a slow throw is the second failure mode)
# min_h/max_h bounds on jump height, as a FRACTION of a full-scale pop.
#
# Fractions rather than metres, because every one of these cases is really asserting a pop SCALE -
# "the rider loaded fully, so they must get a full pop", "a sloppy throw keeps most of it", "a light
# hold barely leaves the ground". Written in metres they were sized against one particular
# jump_impulse and re-baselined wholesale the moment the pop was tuned, which taught nothing: the
# recogniser was never what changed. _full_pop_height() derives the reference from the physics, so
# these now track jump_impulse and gravity_accel on their own.
#
# The upper bounds sit just over 1.0 on purpose. A full pop IS the ceiling, and the slack is for the
# apex being sampled per frame rather than solved for.
const CASES := [
	# The reported failure. The thumb is already home when the flick lands; the rider loaded fully,
	# so they must get a full pop.
	{"label": "full load, thumb home at flick", "pre": 1.0, "hold": 0.0, "wait": 0,
		"flick_over": 2.0, "min_h": 0.83, "max_h": 1.07},
	# The second failure. A slow throw used to drop the load mid-gesture and pop not at all.
	#
	# The bound is deliberately NOT full height. Releasing the load outright and then taking 12
	# frames to throw the flick is a sloppy input, and the tail has been springing back for all of
	# it - losing some pop is the honest answer and the whole point of a release RATE rather than a
	# latch. What is pinned here is that the gesture survives and produces a real pop: no cliff, and
	# never zero. Timing is forgiven, not made free.
	{"label": "full load, slow flick throw", "pre": 1.0, "hold": 0.0, "wait": 0,
		"flick_over": 12.0, "min_h": 0.35, "max_h": 1.07},
	# Forgiveness must not swallow the graded response underneath it.
	{"label": "steady gentle hold", "hold": 0.45, "wait": 0, "flick_over": 2.0,
		"min_h": 0.006, "max_h": 0.12},
	{"label": "steady light hold (ledge drop)", "hold": 0.25, "wait": 0, "flick_over": 2.0,
		"min_h": 0.0, "max_h": 0.012},
	# THE DIRECTIONAL POP. Popping from a standstill with the foot in a side pocket leaps the rider
	# over a metre per second STRAIGHT SIDEWAYS. That is nearly perpendicular to the deck, so anything
	# deriving a heading from raw velocity gets noise - leading_foot flipped mid-flight, and since it
	# picks the kickturn axle the board came down pivoting on the wrong truck. Invisible to every
	# suite until now, and the third time this class of bug has bitten (chase camera heading, travel
	# axis sign, and this). Also pins the direction the deck kicks, which a sign inversion in the
	# torsion routing reversed with nothing to catch it.
	{"label": "left pocket pop, stationary", "hold": 1.0, "wait": 0, "flick_over": 2.0,
		"speed": 0.0, "pocket_x": -0.56, "expect_yaw_sign": 1.0, "min_h": 0.71, "max_h": 1.07},
	{"label": "right pocket pop, stationary", "hold": 1.0, "wait": 0, "flick_over": 2.0,
		"speed": 0.0, "pocket_x": 0.56, "expect_yaw_sign": -1.0, "min_h": 0.71, "max_h": 1.07},
	# The same pop with the deck's kick-out yaw DISABLED, which is the case that actually pins the
	# stance derivation. With the kick present, travel is a hair off perpendicular and the fore/aft
	# dot-product comparison breaks in the deck's favour by luck; at zero it is a true tie and a
	# stance read from raw velocity is a coin flip. Deriving it from the along-axis sign instead is
	# what makes it deterministic, and this is the case that fails without it.
	{"label": "lateral pop, no deck kick", "hold": 1.0, "wait": 0, "flick_over": 2.0,
		"speed": 0.0, "pocket_x": -0.56, "lateral_yaw": 0.0, "min_h": 0.71, "max_h": 1.07},
	# The compression must SPRING BACK, not latch. A rider who loads hard, eases off and then sits
	# there has let the tail up; flicking later is a gentle pop, not a stored full one.
	{"label": "full load, eased off, flicked late", "pre": 1.0, "hold": 0.30, "wait": 30,
		"flick_over": 2.0, "min_h": 0.0, "max_h": 0.072},
]

const STANCES := [
	{"label": "regular", "stance": RiderInput.Stance.REGULAR},
	{"label": "goofy", "stance": RiderInput.Stance.GOOFY},
]

var _world: Node3D = null
var _skater: SkaterController = null
var _frame: int = 0
var _case: int = 0
var _stance: int = 0
var _failures: int = 0
var _reported: bool = false

var _pop_frame: int = -1
var _peak: float = 0.0
var _y0: float = 0.0
var _scale: float = -1.0
var _dropped: bool = false
var _lead_before: RiderInput.Foot = RiderInput.Foot.LEFT
var _axle_before: float = 0.0
## STICKY. A flip that happens mid-flight and recovers on landing is still a flip - the board pivots
## on the wrong truck for as long as it lasts, and sampling only the final state misses it entirely.
var _lead_flipped: bool = false
var _axle_flipped: bool = false
var _peak_yaw: float = 0.0

func _ready() -> void:
	_start_case()

func _start_case() -> void:
	if _world != null:
		_world.queue_free()
	_world = TEST_WORLD.instantiate()
	add_child(_world)
	_skater = _world.get_node("SkaterRig") as SkaterController
	_skater.global_position = Vector3(20.0, _skater.ride_height, 20.0)
	_skater.velocity = Vector3(0.0, 0.0, -float(CASES[_case].get("speed", 7.0)))
	_skater.rider.stance = STANCES[_stance]["stance"]
	if CASES[_case].has("lateral_yaw"):
		_skater.lateral_pop_yaw_deg = float(CASES[_case]["lateral_yaw"])
	# Silence the poller so written sticks survive; TrickState still ticks, so the pop goes through
	# the real recogniser and _release_pop() rather than being injected.
	_skater.rider.set_physics_process(false)
	_frame = 0
	_pop_frame = -1
	_peak = 0.0
	_scale = -1.0
	_dropped = false
	_lead_flipped = false
	_axle_flipped = false
	_peak_yaw = 0.0
	_y0 = _skater.global_position.y

func _physics_process(_delta: float) -> void:
	if _reported or _skater == null:
		return
	_frame += 1
	var c: Dictionary = CASES[_case]
	var rider: RiderInput = _skater.rider
	var flick_at: int = 12 + int(c["wait"])

	if _pop_frame < 0:
		var held: float = float(c["hold"])
		if c.has("pre") and _frame <= 10:
			held = float(c["pre"])
		var back_is_right: bool = rider.leading_foot == RiderInput.Foot.LEFT
		var load := Vector2(float(c.get("pocket_x", 0.0)), held)
		var flick := Vector2.ZERO
		if _frame >= flick_at:
			var t: float = clampf(float(_frame - flick_at + 1) / float(c["flick_over"]), 0.0, 1.0)
			flick = Vector2(-0.7 * t, 0.0)
		if back_is_right:
			rider.right_stick_raw = load
			rider.left_stick_raw = flick
		else:
			rider.left_stick_raw = load
			rider.right_stick_raw = flick
	else:
		rider.right_stick_raw = Vector2.ZERO
		rider.left_stick_raw = Vector2.ZERO
	rider.left_mag = rider.left_stick_raw.length()
	rider.right_mag = rider.right_stick_raw.length()

	# A load dropped back to NONE after the gesture began is the second failure mode.
	if _frame == 3:
		_lead_before = rider.leading_foot
		_axle_before = _skater.trailing_axle_z()
	if _frame > 12 and _pop_frame < 0 and _skater.trick.current_pop_state == TrickState.PopState.NONE:
		_dropped = true

	if _pop_frame < 0 and _skater.trick.current_pop_state == TrickState.PopState.POPPED:
		_pop_frame = _frame
		_scale = _skater.trick.pop_impulse_scale

	if _pop_frame > 0:
		_peak = maxf(_peak, _skater.global_position.y - _y0)
		if absf(_skater.board_pivot.rotation_degrees.y) > absf(_peak_yaw):
			_peak_yaw = _skater.board_pivot.rotation_degrees.y
		if rider.leading_foot != _lead_before:
			_lead_flipped = true
		if signf(_skater.trailing_axle_z()) != signf(_axle_before):
			_axle_flipped = true
		if _frame > _pop_frame + 45:
			_finish_case()
	elif _frame > 140:
		_finish_case()

## Apex a full-scale pop reaches, from the physics rather than a recorded metre figure: v^2 / 2g.
## Every height bound is a fraction of this, so tuning jump_impulse or gravity_accel cannot silently
## re-baseline a suite whose subject is the GESTURE RECOGNISER and not the ballistics.
func _full_pop_height() -> float:
	if _skater == null or _skater.gravity_accel <= 0.0:
		return 1.0
	return (_skater.jump_impulse * _skater.jump_impulse) / (2.0 * _skater.gravity_accel)

func _finish_case() -> void:
	var c: Dictionary = CASES[_case]
	var st: Dictionary = STANCES[_stance]
	var problems: Array[String] = []

	if _pop_frame < 0:
		problems.append("never popped - the gesture was lost entirely")
	else:
		if _dropped:
			problems.append("load dropped to NONE mid-gesture before the flick landed")
		var frac: float = _peak / _full_pop_height()
		if frac < float(c["min_h"]):
			problems.append("height %.3f m = %.3f of a full pop, below %.3f - loaded but got no pop for it" % [
				_peak, frac, c["min_h"]])
		if frac > float(c["max_h"]):
			problems.append("height %.3f m = %.3f of a full pop, above %.3f - more pop than the rider asked for" % [
				_peak, frac, c["max_h"]])
		if _lead_flipped:
			problems.append("leading_foot flipped during the trick - the kickturn axle swaps with it")
		if _axle_flipped:
			problems.append("trailing axle sign flipped during the trick - board pivots on the wrong truck")
		if c.has("expect_yaw_sign") and signf(_peak_yaw) != float(c["expect_yaw_sign"]):
			problems.append("deck kicked the wrong way: peak board yaw %+.2f, expected sign %+.0f"
				% [_peak_yaw, float(c["expect_yaw_sign"])])

	var ok: bool = problems.is_empty()
	print("%-34s %-8s %s | scale %.2f | height %.3f m (%.2f of full)" % [
		c["label"], st["label"], "PASS" if ok else "FAIL", _scale, _peak, _peak / _full_pop_height()])
	for p in problems:
		_failures += 1
		print("      -> %s" % p)

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
