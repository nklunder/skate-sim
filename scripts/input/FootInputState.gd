class_name FootInputState
extends Node

enum Stance { REGULAR, GOOFY }
enum PopState { NONE, LOADING_OLLIE, LOADING_NOLLIE, POPPED }
## Which physical foot. Was a String tested with begins_with("Left") in ~24 places, which is the same
## failure shape as the trick-name strings removed from this project: a typo compiles cleanly and
## fails silently. Strings now exist only at the HUD boundary, via foot_name().
enum Foot { LEFT, RIGHT }
## Which end of the deck a foot is over.
enum DeckEnd { NOSE, TAIL }

@export var stance: Stance = Stance.REGULAR
@export var board_config: SkateBoardConfig

@export_category("Shove-it Scoop Thresholds")
@export var shuv_180_threshold_deg: float = 40.0 # Standard scoop buffer window (40° to 94°)
@export var shuv_360_threshold_deg: float = 95.0 # Deep scoop buffer window (>= 95°)

@export_category("Flick Tilt & Styling")
## Maximum angle above horizontal (in degrees) allowed for upward/boned flip flicks. Capping this preserves the vertical Ollie forgiveness zone.
@export_range(30.0, 75.0) var max_flick_up_angle_deg: float = 60.0
## Maximum angle below horizontal (in degrees) allowed for downward/rocketed flip flicks.
@export_range(15.0, 60.0) var max_flick_down_angle_deg: float = 45.0
## Maximum downward nose pitch (in degrees) when flicking high toward the nose (-Y thumbstick).
@export_range(-45.0, 0.0) var max_boned_tilt_deg: float = -18.0
## Maximum upward nose pitch (in degrees) when flicking low/backward (+Y thumbstick).
@export_range(0.0, 45.0) var max_rocketed_tilt_deg: float = 18.0

# Live Input Values
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
## Which side of the skater the chase camera sits on: +1 right, -1 left. Absolute, not a toggle -
## d-pad right always picks the right-hand view - so what you get never depends on where you were.
##
## Named by SIDE rather than frontside/backside deliberately: which of the two shows the rider's
## front depends on stance, so the stance-relative names would mean opposite things for a regular
## and a goofy rider while the camera did exactly the same thing.
var camera_side: int = 1

# Push Detection & Stroke Classification
var push_left_triggered: bool = false
var push_right_triggered: bool = false
var last_push_type: String = "None"

## Reads the physical devices. The only thing in this file that knows a gamepad exists - everything
## below works from the Sample it returns, which is also why the regression suites can drive the
## controller by writing stick vectors directly instead of simulating a joypad.
var _poller := StickPoller.new()

# Trick & Combo State Tracking
var current_pop_state: PopState = PopState.NONE
var trick_status_string: String = "Grounded"
var pop_impulse_triggered: bool = false
var pop_impulse_scale: float = 1.0
var pop_lateral_impulse_ratio: float = 0.0
var last_pop_type: String = "None" # Display only. Logic reads current_trick.pop.
var last_pop: TrickSignature.Pop = TrickSignature.Pop.OLLIE
## Measurement of the trick in progress. Populated at pop with pop/flip/shuv; SkaterController
## fills in body_deg at touchdown, once the body rotation has actually happened.
var current_trick: TrickSignature = TrickSignature.new()
## The flip the current pop is classified as. An enum for the same reason `Foot` is: this value is
## LOGIC, not display - it is mirrored for nollie/fakie below and copied straight onto the signature -
## and as a String a typo compiled cleanly and silently produced no flip at all.
var active_flip: TrickSignature.Flip = TrickSignature.Flip.NONE
var last_scoop_sign: float = -1.0
var max_swept_angle: float = 0.0
var accumulated_scoop_deg: float = 0.0
var _last_frame_scoop_angle: float = 0.0
var last_combo_string: String = "None"
## Readout of the last landed trick's measured signature, shown on the HUD so table rows can be
## authored by observation rather than by reasoning about rotation conventions.
var last_trick_signature: String = "-"

# Live Facts
var leading_foot: Foot = Foot.LEFT
var trailing_foot: Foot = Foot.RIGHT
var left_foot_over: DeckEnd = DeckEnd.NOSE
var right_foot_over: DeckEnd = DeckEnd.TAIL

## Display helpers. These are the ONLY place foot/deck identity becomes a string - logic compares
## enum values, never text.
static func foot_name(f: Foot) -> String:
	return "Left Foot" if f == Foot.LEFT else "Right Foot"

static func deck_end_name(e: DeckEnd) -> String:
	return "Nose" if e == DeckEnd.NOSE else "Tail"

## The stick belonging to the leading / trailing foot. Five call sites across two files used to
## re-derive this inline, each independently responsible for getting stance handedness right.
func front_stick() -> Vector2:
	return left_stick_raw if leading_foot == Foot.LEFT else right_stick_raw

func back_stick() -> Vector2:
	return right_stick_raw if leading_foot == Foot.LEFT else left_stick_raw

func _physics_process(delta: float) -> void:
	_poll_inputs(delta)
	_update_polar_decomposition()
	_classify_push_strokes()
	_detect_pop_load_and_flick()

## Applies one frame of device state onto the live input values. Everything the hardware knows
## enters the input system through this function and no other.
func _poll_inputs(delta: float) -> void:
	var s: StickPoller.Sample = _poller.poll(delta)
	left_stick_raw = s.left
	right_stick_raw = s.right
	left_stick_speed = s.left_speed
	right_stick_speed = s.right_speed
	lean = s.lean
	# Only on an actual selection, so the sticky side survives frames where the d-pad is idle - and
	# so anything that sets camera_side from outside the device layer is not clobbered next tick.
	if s.camera_side_select != 0:
		camera_side = s.camera_side_select

	# Latch push triggers so button presses aren't dropped before SkaterController evaluation
	if s.push_left_edge:
		push_left_triggered = true
	if s.push_right_edge:
		push_right_triggered = true

	# Spacebar fallback for keyboard jumping with Z (Kickflip) / X (Heelflip) / C (Shove-it)
	if s.pop_edge and current_pop_state != PopState.POPPED:
		pop_impulse_triggered = true
		pop_lateral_impulse_ratio = 0.0
		current_pop_state = PopState.POPPED
		_set_pop(TrickSignature.Pop.OLLIE)
		_build_trick_signature()

func _detect_pop_load_and_flick() -> void:
	if current_pop_state == PopState.POPPED:
		return # Wait for SkaterController touchdown to reset state
		
	var left_is_front: bool = leading_foot == Foot.LEFT
	var front: Vector2 = front_stick()
	var back: Vector2 = back_stick()
	
	# Ollie / Switch Ollie Load (Trailing back foot pulled down in lower hemisphere)
	if current_pop_state == PopState.NONE:
		if back.length() >= 0.20 and back.y >= 0.20:
			current_pop_state = PopState.LOADING_OLLIE
			trick_status_string = "Loading Ollie (Tail)" if back.length() >= 0.70 else "Manual / Ledge Prep"
			_last_frame_scoop_angle = rad_to_deg(back.angle())
			accumulated_scoop_deg = 0.0
			max_swept_angle = 0.0
		# Nollie / Switch Nollie Load (Leading front foot pushed up in upper hemisphere)
		elif front.length() >= 0.20 and front.y <= -0.20:
			current_pop_state = PopState.LOADING_NOLLIE
			trick_status_string = "Loading Nollie (Nose)" if front.length() >= 0.70 else "Manual / Ledge Prep"
			_last_frame_scoop_angle = rad_to_deg(front.angle())
			accumulated_scoop_deg = 0.0
			max_swept_angle = 0.0
			
	# Measure total angular sweep (arc span) and true rotational direction via frame delta accumulation to prevent circle-wrap bugs
	if current_pop_state != PopState.NONE:
		var active_scoop: Vector2 = back if current_pop_state == PopState.LOADING_OLLIE else front
		if active_scoop.length() >= 0.30:
			var curr_deg: float = rad_to_deg(active_scoop.angle())
			var frame_delta: float = rad_to_deg(angle_difference(deg_to_rad(_last_frame_scoop_angle), deg_to_rad(curr_deg)))
			_last_frame_scoop_angle = curr_deg
			accumulated_scoop_deg += frame_delta
			var swept: float = absf(accumulated_scoop_deg)
			if swept > max_swept_angle:
				max_swept_angle = swept
				if swept >= 15.0:
					last_scoop_sign = -1.0 if accumulated_scoop_deg > 0.0 else 1.0
	
	# Execute Flick Pop from loaded states
	if current_pop_state == PopState.LOADING_OLLIE and front.length() >= 0.35 and front.y <= 0.20:
		pop_impulse_triggered = true
		pop_impulse_scale = _calculate_pop_impulse_scale(back.length())
		pop_lateral_impulse_ratio = _calculate_lateral_pop_ratio(back.x)
		current_pop_state = PopState.POPPED
		# Differentiate Switch vs Regular Ollie based on profile stance vs live orientation
		if (stance == Stance.REGULAR and not left_is_front) or (stance == Stance.GOOFY and left_is_front):
			_set_pop(TrickSignature.Pop.SWITCH_OLLIE)
		else:
			_set_pop(TrickSignature.Pop.OLLIE)
		_build_trick_signature()
	elif current_pop_state == PopState.LOADING_NOLLIE and back.length() >= 0.35 and back.y >= -0.20:
		pop_impulse_triggered = true
		pop_impulse_scale = _calculate_pop_impulse_scale(front.length())
		pop_lateral_impulse_ratio = _calculate_lateral_pop_ratio(front.x)
		current_pop_state = PopState.POPPED
		if (stance == Stance.REGULAR and not left_is_front) or (stance == Stance.GOOFY and left_is_front):
			_set_pop(TrickSignature.Pop.FAKIE_OLLIE)
		else:
			_set_pop(TrickSignature.Pop.NOLLIE)
		_build_trick_signature()
	
	# Reset to None if sticks return to neutral without flicking
	if right_stick_raw.length() < 0.20 and left_stick_raw.length() < 0.20 and current_pop_state != PopState.NONE:
		current_pop_state = PopState.NONE
		pop_impulse_scale = 1.0
		max_swept_angle = 0.0
		trick_status_string = "Grounded & Rolling"

func _calculate_pop_impulse_scale(stick_mag: float) -> float:
	# Gentle manual holds between 0.20 and 0.55 generate 0% to 25% impulse for ledge drops and low-pop flips!
	if stick_mag < 0.55:
		return clampf((stick_mag - 0.20) / (0.55 - 0.20) * 0.25, 0.0, 0.25)
	# Deflections above 0.55 smoothly scale up to 100% full impulse at 0.70 and beyond!
	return clampf(0.25 + (stick_mag - 0.55) / (0.70 - 0.55) * 0.75, 0.25, 1.0)

## Returns true if the active stick is pulled down past the heavy pop load threshold (>= 0.70).
func is_preparing_pop() -> bool:
	if current_pop_state == PopState.LOADING_OLLIE:
		return back_stick().length() >= 0.70
	elif current_pop_state == PopState.LOADING_NOLLIE:
		return front_stick().length() >= 0.70
	return false

func _calculate_lateral_pop_ratio(stick_x: float) -> float:
	# Disable directional pop if scooping a Pop Shove-it or Tre Flip (arc sweep >= 40 deg)
	if max_swept_angle >= 40.0:
		return 0.0
	var abs_x: float = absf(stick_x)
	if abs_x < 0.15:
		return 0.0
	# Smoothly scale deflection from 0.15 -> 0.70 into magnitude 0.0 -> 1.0
	var ratio: float = clampf((abs_x - 0.15) / (0.70 - 0.15), 0.0, 1.0)
	return -ratio if stick_x < 0.0 else ratio

func _set_pop(p: TrickSignature.Pop) -> void:
	last_pop = p
	last_pop_type = ["Ollie", "Nollie", "Switch Ollie", "Fakie Ollie"][p]

## Measures what the player just did into `current_trick`. Body rotation is NOT known yet - it
## happens during flight - so SkaterController fills body_deg in at touchdown and resolves the name
## there. Nothing here builds a display string; naming lives entirely in TrickNames.gd.
func _build_trick_signature() -> void:
	active_flip = TrickSignature.Flip.NONE

	var sig := TrickSignature.new()
	sig.pop = last_pop

	var left_is_front: bool = leading_foot == Foot.LEFT
	var flick_stick: Vector2
	var flick_is_left_foot: bool

	if last_pop == TrickSignature.Pop.NOLLIE or last_pop == TrickSignature.Pop.FAKIE_OLLIE:
		# In a Nollie or Fakie Ollie pop, the TRAILING foot is the flicking foot
		flick_stick = back_stick()
		flick_is_left_foot = not left_is_front
	else:
		# In an Ollie pop, the LEADING foot is the flicking foot
		flick_stick = front_stick()
		flick_is_left_foot = left_is_front

	# How hard the rider flicked, taken from the flicking stick at the instant the trick is measured.
	sig.flick_speed = left_stick_speed if flick_is_left_foot else right_stick_speed

	# Universal Flick Rule: Flicking outward (-X for Left, +X for Right = behind body) = Kickflip; Inward (+X for Left, -X for Right = in front of body) = Heelflip
	var max_slope: float = tan(deg_to_rad(max_flick_up_angle_deg if flick_stick.y <= 0.0 else max_flick_down_angle_deg))
	if flick_stick.length() >= 0.25 and absf(flick_stick.y) <= absf(flick_stick.x) * max_slope:
		if flick_is_left_foot:
			active_flip = TrickSignature.Flip.KICK if flick_stick.x < 0.0 else TrickSignature.Flip.HEEL
		else:
			active_flip = TrickSignature.Flip.KICK if flick_stick.x > 0.0 else TrickSignature.Flip.HEEL
		
		var tilt_ratio: float = clampf((flick_stick.y / absf(flick_stick.x)) / max_slope, -1.0, 1.0)
		if tilt_ratio < 0.0:
			sig.flick_tilt_deg = absf(tilt_ratio) * max_boned_tilt_deg
		else:
			sig.flick_tilt_deg = tilt_ratio * max_rocketed_tilt_deg
	elif Input.is_physical_key_pressed(KEY_Z) or Input.is_physical_key_pressed(KEY_F):
		active_flip = TrickSignature.Flip.KICK
	elif Input.is_physical_key_pressed(KEY_X) or Input.is_physical_key_pressed(KEY_G):
		active_flip = TrickSignature.Flip.HEEL

	# In Fakie and Nollie stance the flicking foot swaps ends, so the physical flick maps to the opposite deck
	# roll. Mirror the classification to keep both HUD trick terminology and control-to-rotation behaviour accurate.
	if (last_pop == TrickSignature.Pop.FAKIE_OLLIE or last_pop == TrickSignature.Pop.NOLLIE) \
			and active_flip != TrickSignature.Flip.NONE:
		active_flip = TrickSignature.Flip.HEEL if active_flip == TrickSignature.Flip.KICK \
			else TrickSignature.Flip.KICK

	sig.flip = active_flip

	var is_360_shuv: bool = (max_swept_angle >= shuv_360_threshold_deg or Input.is_physical_key_pressed(KEY_H))
	if is_360_shuv or (max_swept_angle >= shuv_180_threshold_deg or Input.is_physical_key_pressed(KEY_C)):
		if Input.is_physical_key_pressed(KEY_C) or Input.is_physical_key_pressed(KEY_H):
			last_scoop_sign = -1.0
		# `last_scoop_sign` is the RAW thumbstick sweep direction, and stays raw for the physical
		# rotation SkaterController applies. Converting it to the rider's frame for naming is
		# TrickSignature.shuv_sign()'s job - see the frame table there.
		var magnitude: int = 360 if is_360_shuv else 180
		sig.shuv_deg = int(magnitude * last_scoop_sign) \
			* TrickSignature.shuv_sign(stance == Stance.GOOFY, not flick_is_left_foot)

	current_trick = sig
	# Name is resolved at touchdown, once the body rotation has actually happened.
	trick_status_string = "Airborne"


func _update_polar_decomposition() -> void:
	left_mag = left_stick_raw.length()
	if left_mag > 0.05:
		left_angle = atan2(left_stick_raw.x, -left_stick_raw.y)
	else:
		left_angle = 0.0
	
	right_mag = right_stick_raw.length()
	if right_mag > 0.05:
		right_angle = atan2(right_stick_raw.x, -right_stick_raw.y)
	else:
		right_angle = 0.0

func _classify_push_strokes() -> void:
	if push_left_triggered:
		if leading_foot == Foot.LEFT:
			last_push_type = "Mongo Push (Leading)"
		else:
			last_push_type = "Standard Push (Trailing)"
	elif push_right_triggered:
		if leading_foot == Foot.RIGHT:
			last_push_type = "Mongo Push (Leading)"
		else:
			last_push_type = "Standard Push (Trailing)"

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
func update_stance_facts(pivot: Node3D, left_rest: Vector3, right_rest: Vector3, vel: Vector3,
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
	var forward_source: Node3D = root if root != null else pivot.get_parent()
	var travel_dir: Vector3 = vel.normalized() if vel.length_squared() > 0.05 else -forward_source.global_transform.basis.z * travel_axis_sign
	var basis: Basis = pivot.global_transform.basis
	var left_dot: float = (basis * left_rest).dot(travel_dir)
	var right_dot: float = (basis * right_rest).dot(travel_dir)
	if left_dot > right_dot:
		leading_foot = Foot.LEFT
		trailing_foot = Foot.RIGHT
	else:
		leading_foot = Foot.RIGHT
		trailing_foot = Foot.LEFT
