class_name TrickState
extends Node

## Recognises what the rider is ATTEMPTING, from the raw gestures RiderInput publishes.
##
## The gesture state machine: pop loading, scoop arc measurement, flick classification, and the
## resulting TrickSignature. Split out of the old FootInputState, which was simultaneously an input
## reader, this state machine, and a scratchpad SkaterController wrote back into.
##
## Sits as a CHILD of RiderInput so it ticks immediately after it - Godot runs _physics_process in
## tree order, parents before children - which guarantees the gestures below are read from a fully
## updated stick rather than a half-updated one. That ordering is the reason for the parent/child
## relationship instead of two siblings.
##
## Builds NO display names. It measures the physical action into `current_trick`; TrickNames.gd
## decides what to call it, at touchdown, once body rotation has actually happened.

enum PopState { NONE, LOADING_OLLIE, LOADING_NOLLIE, POPPED }

@export_category("Deflection Zones")
## Minimum stick deflection that registers as a load at all - the floor of the manual balance band.
@export_range(0.05, 0.5) var manual_zone_min: float = 0.20
## Deflection at and above which the rider is committed to a heavy pop rather than balancing a
## manual. Drives is_preparing_pop(), which gates steering damping and the pre-pop crouch.
@export_range(0.3, 1.0) var pop_load_threshold: float = 0.70
## Where the impulse curve changes slope: below this a load reads as a gentle manual hold, above it
## as genuine compression.
@export_range(0.2, 1.0) var low_pop_knee: float = 0.55
## Jump impulse a load at low_pop_knee produces, as a fraction of full. The un-popped ledge drop.
@export_range(0.0, 1.0) var low_pop_max_ratio: float = 0.25
## How far the OPPOSITE stick must be thrown to release the pop.
@export_range(0.1, 1.0) var flick_min_deflection: float = 0.35
## How far the stick must STILL be deflected for the flick to count as held, sustaining the rotation
## into a double or triple. DELIBERATELY HIGHER than flick_min_deflection: reuse that threshold and
## any stick position that could have thrown the flick also counts as still asking for more, so a
## thumb following through gets the rider a double they never asked for.
##
## Same shape as the two-stage balance law on holds_*_balance() - entering a state and sustaining it
## are different requests and should not share a number. Here the sustain is the STRICTER of the two,
## because the failure guarded is an accidental hold rather than an accidental drop.
##
## Raise it if doubles still fire unintentionally; lower it if holding one feels like a fight. Below
## flick_min_deflection it stops doing anything, since the flick could not have fired.
@export_range(0.1, 1.0) var flick_hold_min_deflection: float = 0.60
## How closely the stick must still point along the direction it was flicked for the flick to count
## as HELD, as a dot product. 1.0 demands the exact direction; 0.6 allows about 53 degrees either way.
##
## Alignment rather than mere deflection, because a stick on its way back through the rim is
## deflected too - and sustaining a rotation because the rider is releasing would be the opposite of
## what they asked for.
@export_range(0.0, 1.0) var flick_hold_alignment: float = 0.6

## Vertical band the releasing stick must be inside, so a flick reads as a flick and not as the
## opposite end being loaded instead.
@export_range(0.0, 0.5) var flick_release_band: float = 0.20
## Upper bound on deflection for ENTERING a manual from four wheels. Full compression past this is
## an Ollie load, not a balance request - see the two-stage law on holds_*_balance() below.
@export_range(0.5, 1.0) var manual_entry_max: float = 0.90
## Sweep below which no scoop is considered active, for the manual-entry test.
@export var scoop_idle_deg: float = 10.0

@export_category("Shove-it Scoop Thresholds")
@export var scoop_180_threshold_deg: float = 40.0 # Standard scoop buffer window (40° to 94°)
@export var scoop_360_threshold_deg: float = 95.0 # Deep scoop buffer window (>= 95°)
## Deflection below which stick motion is too near the centre for its angle to be meaningful.
@export_range(0.1, 1.0) var scoop_min_deflection: float = 0.30
## Sweep that must accumulate before the scoop's DIRECTION is trusted. Below this the sign is noise.
@export var scoop_direction_min_deg: float = 15.0
## How fast a remembered flick speed bleeds away, in deflection-units per second per second.
##
## PEAK-HELD per stick, never a single-frame sample: a throw is several frames long and its speed is
## not constant across them, so one sample taken on whichever frame crossed flick_min_deflection is
## noise. The peak bleeds so it measures THIS flick rather than one from two seconds ago.
@export var flick_speed_decay: float = 60.0

## How fast a loaded tail springs back once the thumb starts coming home, in stick units per second.
##
## THE COMPRESSION IS PHYSICAL STATE, not a live readout of the thumb. A rider pops by flicking the
## OPPOSITE stick, so both thumbs move at once and the loading one is often already on its way back
## when the flick lands. Read live at that instant, pop height becomes a function of thumb
## SYNCHRONISATION rather than of how hard the rider loaded:
##
##     load stick at flick   1.00   0.70   0.40   0.10   0.00
##     jump height (m)       0.80   0.80   0.19   0.01   0.00  <- board never leaves the ground
##
## Two frames of timing separate a full ollie from nothing, and the trick still REGISTERS - the deck
## flips, the name resolves - it simply has no height. That is "sometimes it just doesn't pop".
##
## Physically the tail is already compressed by the time the flick happens, and letting go of the
## stick does not uncompress it instantly. At 2.5 a full load stays worth a full pop for ~7 frames
## and survives as a load at all for ~19.
@export var load_release_rate: float = 2.5

@export_category("Directional Pop")
## Horizontal deflection inside which a pop goes dead straight, for gap consistency.
@export_range(0.0, 0.5) var lateral_pop_deadzone: float = 0.15
## Horizontal deflection producing a full-strength lateral leap.
@export_range(0.2, 1.0) var lateral_pop_full: float = 0.70

@export_category("Flick Tilt & Styling")
## Maximum angle above horizontal (in degrees) allowed for upward/boned flip flicks. Capping this preserves the vertical Ollie forgiveness zone.
@export_range(30.0, 75.0) var max_flick_up_angle_deg: float = 60.0
## Maximum angle below horizontal (in degrees) allowed for downward/rocketed flip flicks.
@export_range(15.0, 60.0) var max_flick_down_angle_deg: float = 45.0
## Maximum downward nose pitch (in degrees) when flicking high toward the nose (-Y thumbstick).
@export_range(-45.0, 0.0) var max_boned_tilt_deg: float = -18.0
## Maximum upward nose pitch (in degrees) when flicking low/backward (+Y thumbstick).
@export_range(0.0, 45.0) var max_rocketed_tilt_deg: float = 18.0

# --- Live trick state --------------------------------------------------------
var current_pop_state: PopState = PopState.NONE
var trick_status_string: String = "Grounded"
var pop_impulse_triggered: bool = false
var pop_impulse_scale: float = 1.0
var pop_lateral_impulse_ratio: float = 0.0
## True while the stick that FIRED the pop has not yet returned to neutral.
##
## A rider pops by flicking the OPPOSITE stick, so the loading stick is still buried at takeoff. Read
## as a live pitch request that holds the deck ~24 deg nose-up for the whole flight and lands the
## rider in a manual they never asked for. Consuming the load at the pop means the stick must be
## RELEASED and re-applied before it steers pitch again - which is what the rider's foot does anyway.
##
## Airborne only, so holding through a landing still enters a manual under the two-stage balance law.
var pop_load_spent: bool = false
var last_pop: TrickSignature.Pop = TrickSignature.Pop.OLLIE
## Measurement of the trick in progress. Populated at pop with pop/flip/scoop; SkaterController
## fills in body_deg at touchdown, once the body rotation has actually happened.
var current_trick: TrickSignature = TrickSignature.new()
var last_scoop_sign: float = -1.0
var max_swept_angle: float = 0.0
## The tail's live compression, as a stick vector. Magnitude is REMEMBERED and bleeds back at
## load_release_rate; direction tracks the thumb, so gliding the foot across the tail's pockets
## still aims the pop in real time. This, not `rider.back_stick()`, is what a pop is measured from.
var _load: Vector2 = Vector2.ZERO
## True while the rider is STILL HOLDING the flick they threw, in the direction they threw it.
##
## THE ONE HOLD INPUT FOR THE WHOLE TRICK. A scoop is initiated by the popping foot's arc sweep but
## sustained by holding the FLICK, so flipping, scooping and both are all extended by the same
## gesture. That is the same statement flip/scoop sync makes - that a trick is one coherent rotation
## rather than two things happening near each other - and it is why there is no second hold to
## disagree with this one. It also means nothing here reads the popping stick, so `pop_load_spent`
## is not involved.
var flick_held: bool = false
## The direction the flick was thrown, and which stick threw it. Remembered at the pop so "still
## held" can be judged against what the rider actually did rather than against a fixed axis.
var _flick_dir: Vector2 = Vector2.ZERO
var _flick_is_left: bool = false
## Recent peak speed of each stick. See flick_speed_decay.
var _left_flick_peak: float = 0.0
var _right_flick_peak: float = 0.0
var _accumulated_scoop_deg: float = 0.0
var _last_frame_scoop_angle: float = 0.0
var last_combo_string: String = "None"
## Readout of the last landed trick's measured signature, shown on the HUD so table rows can be
## authored by observation rather than by reasoning about rotation conventions.
var last_trick_signature: String = "-"

## The gestures this reads. Resolved from the parent rather than exported: TrickState is only ever a
## child of RiderInput, and an exported reference would be one more thing to wire up per scene.
@onready var rider: RiderInput = get_parent() as RiderInput

func _ready() -> void:
	if rider == null:
		push_warning("TrickState: parent is not a RiderInput; no trick will ever be recognised.")

func _physics_process(delta: float) -> void:
	if rider == null:
		return
	_track_flick_speed(delta)
	_track_flick_hold(delta)
	_release_spent_pop_stick()
	_handle_keyboard_pop()
	_detect_pop_load_and_flick(delta)

## Spacebar fallback for keyboard jumping, with Z (Kickflip) / X (Heelflip) / C (Shove-it).
func _handle_keyboard_pop() -> void:
	if not (rider.pop_edge and current_pop_state != PopState.POPPED):
		return
	pop_impulse_triggered = true
	# Explicitly a full-strength pop. Without this the keyboard path inherited whatever scale the
	# last STICK pop left behind - and since touchdown resets current_pop_state but not the scale,
	# a spacebar ollie after a 25% ledge drop popped at 25% and looked broken.
	pop_impulse_scale = 1.0
	pop_lateral_impulse_ratio = 0.0
	pop_load_spent = false
	current_pop_state = PopState.POPPED
	last_pop = TrickSignature.Pop.OLLIE
	_build_trick_signature()

func _detect_pop_load_and_flick(delta: float) -> void:
	if current_pop_state == PopState.POPPED:
		return # Wait for SkaterController touchdown to reset state

	var left_is_front: bool = rider.leading_foot == RiderInput.Foot.LEFT
	var front: Vector2 = rider.front_stick()
	var back: Vector2 = rider.back_stick()

	# Ollie / Switch Ollie Load (Trailing back foot pulled down in lower hemisphere)
	if current_pop_state == PopState.NONE:
		if back.length() >= manual_zone_min and back.y >= manual_zone_min:
			_begin_load(PopState.LOADING_OLLIE, back, "Loading Ollie (Tail)")
		# Nollie / Switch Nollie Load (Leading front foot pushed up in upper hemisphere)
		elif front.length() >= manual_zone_min and front.y <= -manual_zone_min:
			_begin_load(PopState.LOADING_NOLLIE, front, "Loading Nollie (Nose)")

	# Track the tail's compression, which follows the thumb DOWN more slowly than the thumb moves.
	if current_pop_state != PopState.NONE:
		_track_compression(back if current_pop_state == PopState.LOADING_OLLIE else front, delta)

	# Measure total angular sweep (arc span) and true rotational direction via frame delta
	# accumulation, to prevent circle-wrap bugs when a sweep passes 180 deg.
	if current_pop_state != PopState.NONE:
		var active_scoop: Vector2 = back if current_pop_state == PopState.LOADING_OLLIE else front
		if active_scoop.length() >= scoop_min_deflection:
			var curr_deg: float = rad_to_deg(active_scoop.angle())
			var frame_delta: float = rad_to_deg(angle_difference(
				deg_to_rad(_last_frame_scoop_angle), deg_to_rad(curr_deg)))
			_last_frame_scoop_angle = curr_deg
			_accumulated_scoop_deg += frame_delta
			var swept: float = absf(_accumulated_scoop_deg)
			if swept > max_swept_angle:
				max_swept_angle = swept
				if swept >= scoop_direction_min_deg:
					last_scoop_sign = -1.0 if _accumulated_scoop_deg > 0.0 else 1.0

	# Execute Flick Pop from loaded states.
	if current_pop_state == PopState.LOADING_OLLIE \
			and front.length() >= flick_min_deflection and front.y <= flick_release_band:
		_release_pop(_load, left_is_front, TrickSignature.Pop.SWITCH_OLLIE, TrickSignature.Pop.OLLIE)
	elif current_pop_state == PopState.LOADING_NOLLIE \
			and back.length() >= flick_min_deflection and back.y >= -flick_release_band:
		_release_pop(_load, left_is_front, TrickSignature.Pop.FAKIE_OLLIE, TrickSignature.Pop.NOLLIE)

	# Reset to NONE if the sticks return to neutral without ever flicking - AND the tail has actually
	# sprung back. The compression clause is not belt-and-braces: throwing a flick takes a few frames,
	# and on a slower throw the loading thumb crosses the deadzone before the flicking one reaches it.
	# Both sticks are then briefly under manual_zone_min on the same frame, and without this the load
	# was dropped mid-gesture and the pop never happened at all. A rider who is still compressed has
	# not abandoned anything.
	if rider.right_stick_raw.length() < manual_zone_min \
			and rider.left_stick_raw.length() < manual_zone_min \
			and _load.length() < manual_zone_min \
			and current_pop_state != PopState.NONE:
		current_pop_state = PopState.NONE
		pop_impulse_scale = 1.0
		max_swept_angle = 0.0
		_load = Vector2.ZERO
		_flick_dir = Vector2.ZERO
		flick_held = false
		trick_status_string = "Grounded & Rolling"

## Compression follows the thumb up instantly and back down at load_release_rate. Direction stays
## live so the pocket the foot is in still aims the pop, while the magnitude - which is what the
## impulse is measured from - remembers the load the rider actually achieved.
func _track_compression(active: Vector2, delta: float) -> void:
	var live: float = active.length()
	var mag: float = maxf(live, _load.length() - load_release_rate * delta)
	var dir: Vector2 = active.normalized() if live > 0.05 else _load.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.DOWN
	_load = dir * mag

func _begin_load(state: PopState, stick: Vector2, heavy_label: String) -> void:
	current_pop_state = state
	_load = stick
	trick_status_string = heavy_label if stick.length() >= pop_load_threshold else "Manual / Ledge Prep"
	_last_frame_scoop_angle = rad_to_deg(stick.angle())
	_accumulated_scoop_deg = 0.0
	max_swept_angle = 0.0

## Fires the pop. `load_stick` is the one that was HELD (it sets impulse strength and direction);
## the opposite stick is the one that was thrown to release it.
func _release_pop(load_stick: Vector2, left_is_front: bool, reversed_pop: TrickSignature.Pop,
		forward_pop: TrickSignature.Pop) -> void:
	pop_impulse_triggered = true
	pop_impulse_scale = _calculate_pop_impulse_scale(load_stick.length())
	pop_lateral_impulse_ratio = _calculate_lateral_pop_ratio(load_stick.x)
	pop_load_spent = true
	_load = Vector2.ZERO
	current_pop_state = PopState.POPPED
	# Switch vs regular is the rider's PROFILE stance against their live orientation, so a goofy
	# rider riding left-foot-forward is in switch exactly as a regular rider riding right-foot-forward.
	var riding_reversed: bool = (rider.stance == RiderInput.Stance.REGULAR) != left_is_front
	last_pop = reversed_pop if riding_reversed else forward_pop
	_build_trick_signature()

## Watches whether the thrown flick is still being held out in the direction it was thrown.
func _track_flick_hold(_delta: float) -> void:
	if current_pop_state != PopState.POPPED or _flick_dir == Vector2.ZERO:
		flick_held = false
		return
	var stick: Vector2 = rider.left_stick_raw if _flick_is_left else rider.right_stick_raw
	flick_held = stick.length() >= flick_hold_min_deflection \
		and stick.normalized().dot(_flick_dir) >= flick_hold_alignment

## Peak-holds each stick's speed so a flick is measured by the whole throw rather than by whichever
## single frame crossed the release threshold.
func _track_flick_speed(delta: float) -> void:
	var bleed: float = flick_speed_decay * delta
	_left_flick_peak = maxf(rider.left_stick_speed, _left_flick_peak - bleed)
	_right_flick_peak = maxf(rider.right_stick_speed, _right_flick_peak - bleed)

## Which stick was HELD to load the pop - the trailing one for an ollie, the leading one for a
## nollie. Read off `last_pop` rather than `current_pop_state`, which is already POPPED by the time
## anything asks.
func _pop_loaded_back_stick() -> bool:
	return last_pop == TrickSignature.Pop.OLLIE or last_pop == TrickSignature.Pop.SWITCH_OLLIE

## Clears the spent flag once the loading stick has genuinely come home. Runs BEFORE the early-out in
## _detect_pop_load_and_flick(), which returns while POPPED - i.e. for the whole flight, which is
## exactly when this needs to be watching.
func _release_spent_pop_stick() -> void:
	if not pop_load_spent:
		return
	var loaded: Vector2 = rider.back_stick() if _pop_loaded_back_stick() else rider.front_stick()
	if loaded.length() < manual_zone_min:
		pop_load_spent = false

## The two sticks as AIRBORNE PITCH should see them: a stick still spent from the pop reads as
## centred. Every other consumer keeps reading RiderInput directly - this is a statement about one
## gesture having already been used up, not about where the stick physically is.
func airborne_back_stick() -> Vector2:
	return Vector2.ZERO if pop_load_spent and _pop_loaded_back_stick() else rider.back_stick()

func airborne_front_stick() -> Vector2:
	return Vector2.ZERO if pop_load_spent and not _pop_loaded_back_stick() else rider.front_stick()

## Vertical impulse as a fraction of full, from how hard the pop stick was loaded.
##
## Two slopes meeting at low_pop_knee: a gentle manual hold yields a zero-to-low pop, which is what
## makes an un-popped kickflip off a ledge possible, and real compression ramps from there to full.
func _calculate_pop_impulse_scale(stick_mag: float) -> float:
	if stick_mag < low_pop_knee:
		var span: float = maxf(low_pop_knee - manual_zone_min, 0.001)
		return clampf((stick_mag - manual_zone_min) / span * low_pop_max_ratio, 0.0, low_pop_max_ratio)
	var upper: float = maxf(pop_load_threshold - low_pop_knee, 0.001)
	return clampf(low_pop_max_ratio + (stick_mag - low_pop_knee) / upper * (1.0 - low_pop_max_ratio),
		low_pop_max_ratio, 1.0)

## THE TWO-STAGE BALANCE LAW. Both stages live here so the two callers - grounded pitch and touchdown
## classification - cannot drift apart about what a manual is. The expressions are not obvious; they
## are the fix for BUG_ARCHIVE #5, so a second copy is one edit away from them disagreeing.
##
## Stage 1 (ENTER, from four wheels) demands mid-zone precision and no active scoop. Both matter:
## sweeping the stick around the rim for a shove-it drops Cartesian y while the magnitude stays
## high, and full compression past manual_entry_max is an Ollie load, not a request to lift the nose.
##
## Stage 2 (HOLD, already balancing) switches to polar magnitude during a pop load, so a full
## circular scoop or a deep pop deflection out of an established manual does not drop it.
func enters_tail_balance() -> bool:
	var back: Vector2 = rider.back_stick()
	return back.y > manual_zone_min and back.length() <= manual_entry_max and _no_active_scoop()

func enters_nose_balance() -> bool:
	var front: Vector2 = rider.front_stick()
	return front.y < -manual_zone_min and front.length() <= manual_entry_max and _no_active_scoop()

func holds_tail_balance() -> bool:
	var back: Vector2 = rider.back_stick()
	return back.y >= manual_zone_min \
		or (current_pop_state == PopState.LOADING_OLLIE and back.length() >= manual_zone_min)

func holds_nose_balance() -> bool:
	var front: Vector2 = rider.front_stick()
	return front.y <= -manual_zone_min \
		or (current_pop_state == PopState.LOADING_NOLLIE and front.length() >= manual_zone_min)

func _no_active_scoop() -> bool:
	return max_swept_angle < scoop_idle_deg

## True while the active stick is loaded past the heavy pop threshold. Gates steering damping and,
## once the foot animations land, the pre-pop crouch - so a gentle manual hold leaves both alone.
func is_preparing_pop() -> bool:
	if current_pop_state == PopState.LOADING_OLLIE:
		return rider.back_stick().length() >= pop_load_threshold
	elif current_pop_state == PopState.LOADING_NOLLIE:
		return rider.front_stick().length() >= pop_load_threshold
	return false

func _calculate_lateral_pop_ratio(stick_x: float) -> float:
	# A directional leap and a scoop are the same stick motion at different angles, so the moment a
	# sweep is large enough to register as a shove-it the lateral impulse must stand down or every
	# scooped trick launches sideways. Keyed to the scoop threshold itself rather than to a copy of
	# its value, so the two cannot drift apart when it is retuned.
	if max_swept_angle >= scoop_180_threshold_deg:
		return 0.0
	var abs_x: float = absf(stick_x)
	if abs_x < lateral_pop_deadzone:
		return 0.0
	var span: float = maxf(lateral_pop_full - lateral_pop_deadzone, 0.001)
	var ratio: float = clampf((abs_x - lateral_pop_deadzone) / span, 0.0, 1.0)
	return -ratio if stick_x < 0.0 else ratio

## Measures what the player just did into `current_trick`. Body rotation is NOT known yet - it
## happens during flight - so SkaterController fills body_deg in at touchdown and resolves the name
## there. Nothing here builds a display string; naming lives entirely in TrickNames.gd.
func _build_trick_signature() -> void:
	var sig := TrickSignature.new()
	sig.pop = last_pop
	# Local, not a field: nothing outside this function has ever read it, and a shared mutable copy
	# of a value about to be written onto the signature is just a second source of truth.
	var active_flip: TrickSignature.Flip = TrickSignature.Flip.NONE

	var left_is_front: bool = rider.leading_foot == RiderInput.Foot.LEFT
	var flick_stick: Vector2
	var flick_is_left_foot: bool

	if last_pop == TrickSignature.Pop.NOLLIE or last_pop == TrickSignature.Pop.FAKIE_OLLIE:
		# In a Nollie or Fakie Ollie pop, the TRAILING foot is the flicking foot
		flick_stick = rider.back_stick()
		flick_is_left_foot = not left_is_front
	else:
		# In an Ollie pop, the LEADING foot is the flicking foot
		flick_stick = rider.front_stick()
		flick_is_left_foot = left_is_front

	# How hard the rider flicked: the PEAK of the throw, not the instant the trick happened to be
	# measured at. See flick_speed_decay.
	sig.flick_speed = _left_flick_peak if flick_is_left_foot else _right_flick_peak
	# Remembered so _track_flick_hold() can tell "still holding it" from "on the way back".
	_flick_dir = flick_stick.normalized() if flick_stick.length() > 0.001 else Vector2.ZERO
	_flick_is_left = flick_is_left_foot

	# Universal Flick Rule: Flicking outward (-X for Left, +X for Right = behind body) = Kickflip;
	# Inward (+X for Left, -X for Right = in front of body) = Heelflip.
	var max_slope: float = tan(deg_to_rad(
		max_flick_up_angle_deg if flick_stick.y <= 0.0 else max_flick_down_angle_deg))
	if flick_stick.length() >= 0.25 and absf(flick_stick.y) <= absf(flick_stick.x) * max_slope:
		var outward: bool = flick_stick.x < 0.0 if flick_is_left_foot else flick_stick.x > 0.0
		active_flip = TrickSignature.Flip.KICK if outward else TrickSignature.Flip.HEEL

		var tilt_ratio: float = clampf((flick_stick.y / absf(flick_stick.x)) / max_slope, -1.0, 1.0)
		sig.flick_tilt_deg = absf(tilt_ratio) * max_boned_tilt_deg if tilt_ratio < 0.0 \
			else tilt_ratio * max_rocketed_tilt_deg
	elif Input.is_physical_key_pressed(KEY_Z) or Input.is_physical_key_pressed(KEY_F):
		active_flip = TrickSignature.Flip.KICK
	elif Input.is_physical_key_pressed(KEY_X) or Input.is_physical_key_pressed(KEY_G):
		active_flip = TrickSignature.Flip.HEEL

	# In Fakie and Nollie stance the flicking foot swaps ends, so the physical flick maps to the
	# opposite deck roll. Mirror the classification to keep both HUD terminology and control-to-
	# rotation behaviour accurate. Applied ONCE, here - SkaterController's roll target deliberately
	# carries no stance term, because applying this twice cancels it out.
	if (last_pop == TrickSignature.Pop.FAKIE_OLLIE or last_pop == TrickSignature.Pop.NOLLIE) \
			and active_flip != TrickSignature.Flip.NONE:
		active_flip = TrickSignature.Flip.HEEL if active_flip == TrickSignature.Flip.KICK \
			else TrickSignature.Flip.KICK

	sig.flip = active_flip

	var is_360_scoop: bool = max_swept_angle >= scoop_360_threshold_deg \
		or Input.is_physical_key_pressed(KEY_H)
	if is_360_scoop or max_swept_angle >= scoop_180_threshold_deg \
			or Input.is_physical_key_pressed(KEY_C):
		if Input.is_physical_key_pressed(KEY_C) or Input.is_physical_key_pressed(KEY_H):
			last_scoop_sign = -1.0
		# `last_scoop_sign` is the RAW thumbstick sweep direction, and stays raw for the physical
		# rotation SkaterController applies. Converting it to the rider's frame for naming is
		# TrickSignature.scoop_sign()'s job - see the frame table there.
		var magnitude: int = 360 if is_360_scoop else 180
		sig.scoop_deg = int(magnitude * last_scoop_sign) \
			* TrickSignature.scoop_sign(rider.stance == RiderInput.Stance.GOOFY, not flick_is_left_foot)

	current_trick = sig
	# Name is resolved at touchdown, once the body rotation has actually happened.
	trick_status_string = "Airborne"
