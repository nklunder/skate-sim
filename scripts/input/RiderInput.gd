class_name RiderInput
extends Node

## What the rider is physically doing with the controller, and where their feet are on the board.
##
## Deliberately knows NOTHING about tricks. It reports stick vectors, magnitudes, latched buttons and
## stance; deciding that a particular gesture is a nollie heelflip belongs to TrickState, which hangs
## off this node as a child so it ticks immediately after (Godot runs _physics_process in tree order,
## parents first). That ordering is the whole reason for the parent/child relationship rather than
## two siblings - the gesture recogniser must never read a half-updated stick.
##
## This half was split out of the old FootInputState, which had grown into three things at once: an
## input reader, a trick state machine, and a scratchpad SkaterController wrote back into from six
## places. Splitting it means the foot-animation work can add crouch and flick state to TrickState
## without enlarging the thing that answers "where is the left stick".

enum Stance { REGULAR, GOOFY }
## Which physical foot. Was a String tested with begins_with("Left") in ~24 places, which is the same
## failure shape as the trick-name strings removed from this project: a typo compiles cleanly and
## fails silently. Strings now exist only at the HUD boundary, via foot_name().
enum Foot { LEFT, RIGHT }
## Which end of the deck a foot is over. An attribute of the BOARD - see update_stance_facts().
enum DeckEnd { NOSE, TAIL }

@export var stance: Stance = Stance.REGULAR
@export var board_config: SkateBoardConfig

# --- Live device state -------------------------------------------------------
var left_stick_raw: Vector2 = Vector2.ZERO
var right_stick_raw: Vector2 = Vector2.ZERO
var left_mag: float = 0.0
var left_angle: float = 0.0 # Radians via atan2(x, -y)
var right_mag: float = 0.0
var right_angle: float = 0.0
## How fast each stick is moving, in deflection units per second. Sampled onto the trick signature
## at the moment a flick registers - see TrickSignature.flick_speed.
var left_stick_speed: float = 0.0
var right_stick_speed: float = 0.0
var lean: float = 0.0 # RT - LT
## Rising edge of the keyboard pop this frame. Published rather than acted on, because what a pop
## MEANS is TrickState's business.
var pop_edge: bool = false
## Which side of the skater the chase camera sits on: +1 right, -1 left. Absolute, not a toggle -
## d-pad right always picks the right-hand view - so what you get never depends on where you were.
##
## Named by SIDE rather than frontside/backside deliberately: which of the two shows the rider's
## front depends on stance, so the stance-relative names would mean opposite things for a regular
## and a goofy rider while the camera did exactly the same thing.
var camera_side: int = 1

# --- Push detection ----------------------------------------------------------
## Latched until SkaterController consumes them, so a fast tap is never dropped between frames.
var push_left_triggered: bool = false
var push_right_triggered: bool = false
var last_push_type: String = "None" # Display only.

# --- Stance facts ------------------------------------------------------------
var leading_foot: Foot = Foot.LEFT
var trailing_foot: Foot = Foot.RIGHT
var left_foot_over: DeckEnd = DeckEnd.NOSE
var right_foot_over: DeckEnd = DeckEnd.TAIL

## Reads the physical devices. The only thing in this project that knows a gamepad exists -
## everything downstream works from the Sample it returns, which is also why the regression suites
## can drive the controller by writing stick vectors directly instead of simulating a joypad.
var _poller := StickPoller.new()

## Display helpers. These are the ONLY place foot/deck identity becomes a string - logic compares
## enum values, never text.
static func foot_name(f: Foot) -> String:
	return "Left Foot" if f == Foot.LEFT else "Right Foot"

static func deck_end_name(e: DeckEnd) -> String:
	return "Nose" if e == DeckEnd.NOSE else "Tail"

## The stick belonging to the leading / trailing foot. Always call these rather than re-deriving
## stance handedness inline - five call sites across two files used to do that, each independently
## responsible for getting it right.
func front_stick() -> Vector2:
	return left_stick_raw if leading_foot == Foot.LEFT else right_stick_raw

func back_stick() -> Vector2:
	return right_stick_raw if leading_foot == Foot.LEFT else left_stick_raw

func _physics_process(delta: float) -> void:
	_poll_inputs(delta)
	_update_polar_decomposition()
	_classify_push_strokes()

## Applies one frame of device state onto the live values. Everything the hardware knows enters the
## input system through this function and no other.
func _poll_inputs(delta: float) -> void:
	var s: StickPoller.Sample = _poller.poll(delta)
	left_stick_raw = s.left
	right_stick_raw = s.right
	left_stick_speed = s.left_speed
	right_stick_speed = s.right_speed
	lean = s.lean
	pop_edge = s.pop_edge
	# Only on an actual selection, so the sticky side survives frames where the d-pad is idle - and
	# so anything that sets camera_side from outside the device layer is not clobbered next tick.
	if s.camera_side_select != 0:
		camera_side = s.camera_side_select

	# Latch push triggers so button presses aren't dropped before SkaterController evaluation.
	if s.push_left_edge:
		push_left_triggered = true
	if s.push_right_edge:
		push_right_triggered = true

func _update_polar_decomposition() -> void:
	left_mag = left_stick_raw.length()
	left_angle = atan2(left_stick_raw.x, -left_stick_raw.y) if left_mag > 0.05 else 0.0
	right_mag = right_stick_raw.length()
	right_angle = atan2(right_stick_raw.x, -right_stick_raw.y) if right_mag > 0.05 else 0.0

func _classify_push_strokes() -> void:
	if push_left_triggered:
		last_push_type = "Mongo Push (Leading)" if leading_foot == Foot.LEFT else "Standard Push (Trailing)"
	elif push_right_triggered:
		last_push_type = "Mongo Push (Leading)" if leading_foot == Foot.RIGHT else "Standard Push (Trailing)"

## Resolves the two facts that depend on where the rider's feet sit relative to the deck.
##
## Both are derived from the shoes' REST OFFSETS, never from their live positions. Foot placement is
## a property of how the rider stands on the board, not of what an animation is doing this instant,
## and reading the live nodes coupled the single most load-bearing fact in the input system
## (`leading_foot` drives pop classification, every pitch sign, front_stick()/back_stick(), push type
## and the kickturn axle) to a node documented as presentation-only. It also forced FootRig to honour
## a hand-maintained "the leading foot must never cross Z = 0" invariant on every animation ever
## written. Rests are constants captured from SkaterRig.tscn, so that whole class of coupling is gone.
##
## `root` is the yaw-carrying SkaterRoot. It is passed explicitly rather than reached via
## pivot.get_parent(), which now resolves to the surface-tilted SurfaceAlign node and would skew the
## stationary forward vector on any ramp.
##
## `deck_reversed` is whether the DECK ITSELF is currently turned 180 deg from its resting
## orientation - see the nose/tail note below.
func update_stance_facts(pivot: Node3D, left_rest: Vector3, right_rest: Vector3,
		root: Node3D = null, travel_axis_sign: float = 1.0, deck_reversed: bool = false) -> void:
	# NOSE and TAIL are fixed attributes of the BOARD, and are not the same question as leading and
	# trailing. Land a shove-it and the deck has turned 180 deg underneath a rider who has not moved:
	# the tail is now at the leading end and the nose at the trailing one, while `leading_foot` below
	# is completely unchanged. The two facts must therefore be derived from different things.
	#
	# Which END of the deck a shoe is mounted over is fixed (rest offsets, deck-local -Z is the nose
	# at rest); whether that end is currently the nose or the tail flips with the deck's own yaw. So
	# it is an XOR of the two, and the reason it is tracked at all is that real decks are not
	# symmetric - nose and tail differ in length and kick, and anything drawing or measuring against
	# that geometry has to know which one it is standing on.
	var left_at_deck_front: bool = left_rest.z < right_rest.z
	if left_at_deck_front != deck_reversed:
		left_foot_over = DeckEnd.NOSE
		right_foot_over = DeckEnd.TAIL
	else:
		left_foot_over = DeckEnd.TAIL
		right_foot_over = DeckEnd.NOSE

	# LEADING and TRAILING are about the rider and the direction of travel, so the deck's own yaw is
	# irrelevant here - a board rolls equally well either way round. Rest offsets are rotated into
	# world space by the pivot's basis, which is exactly what (foot.global_position -
	# pivot.global_position) evaluated to back when the live nodes were read.
	#
	# Taken from `travel_axis_sign` - which way along the ROLLING AXIS the rider is going - and never
	# from the raw velocity vector. The feet are mounted fore and aft, so a travel direction with a
	# large sideways component dots to nearly zero against both of them and the comparison below is
	# decided by noise. A standing directional pop is exactly that: over 1 m/s straight sideways.
	# leading_foot would flip mid-flight, and since it picks the kickturn axle the board came down
	# pivoting on the wrong truck. The sign already holds through low speed, so it is also the right
	# answer when stopped.
	var forward_source: Node3D = root if root != null else pivot.get_parent()
	var travel_dir: Vector3 = -forward_source.global_transform.basis.z * travel_axis_sign
	var basis: Basis = pivot.global_transform.basis
	if (basis * left_rest).dot(travel_dir) > (basis * right_rest).dot(travel_dir):
		leading_foot = Foot.LEFT
		trailing_foot = Foot.RIGHT
	else:
		leading_foot = Foot.RIGHT
		trailing_foot = Foot.LEFT
