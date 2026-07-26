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

# Live Input Values
var left_stick_raw: Vector2 = Vector2.ZERO
var right_stick_raw: Vector2 = Vector2.ZERO
var left_mag: float = 0.0
var left_angle: float = 0.0 # Radians via atan2(x, -y)
var right_mag: float = 0.0
var right_angle: float = 0.0
var lean: float = 0.0 # RT - LT
## Which side of the skater the chase camera sits on: +1 right, -1 left. Absolute, not a toggle -
## d-pad right always picks the right-hand view - so what you get never depends on where you were.
##
## Named by SIDE rather than frontside/backside deliberately: which of the two shows the rider's
## front depends on stance, so the stance-relative names would mean opposite things for a regular
## and a goofy rider while the camera did exactly the same thing.
var camera_side: int = 1
var current_button_string: String = "None"

# Push Detection & Stroke Classification
var push_left_triggered: bool = false
var push_right_triggered: bool = false
var _prev_push_left: bool = false
var _prev_push_right: bool = false
var last_push_type: String = "None"

# Trick & Combo State Tracking
var current_pop_state: PopState = PopState.NONE
var trick_status_string: String = "Grounded"
var pop_impulse_triggered: bool = false
var last_pop_type: String = "None" # Display only. Logic reads current_trick.pop.
var last_pop: TrickSignature.Pop = TrickSignature.Pop.OLLIE
## Measurement of the trick in progress. Populated at pop with pop/flip/shuv; SkaterController
## fills in body_deg at touchdown, once the body rotation has actually happened.
var current_trick: TrickSignature = TrickSignature.new()
var active_flip_type: String = "None"
var last_scoop_sign: float = -1.0
var max_swept_angle: float = 0.0
var accumulated_scoop_deg: float = 0.0
var _last_frame_scoop_angle: float = 0.0
var last_combo_string: String = "None"
## Readout of the last landed trick's measured signature, shown on the HUD so table rows can be
## authored by observation rather than by reasoning about rotation conventions.
var last_trick_signature: String = "-"
var _prev_space_pressed: bool = false

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

func _physics_process(_delta: float) -> void:
	_poll_inputs()
	_update_polar_decomposition()
	_classify_push_strokes()
	_detect_pop_load_and_flick()

func _poll_inputs() -> void:
	# Joypad input + keyboard fallback (WASD for Left Foot, IJKL for Right Foot)
	var lx: float = Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var ly: float = Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	if abs(lx) < 0.1 and abs(ly) < 0.1:
		lx = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		ly = float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
		if abs(lx) < 0.1 and abs(ly) < 0.1:
			lx = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left") if not Input.is_physical_key_pressed(KEY_L) and not Input.is_physical_key_pressed(KEY_J) else 0.0
			ly = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up") if not Input.is_physical_key_pressed(KEY_K) and not Input.is_physical_key_pressed(KEY_I) else 0.0
	
	# Apply outer-rim deadzone clamping to eliminate sensor fluctuations at full deflection
	left_stick_raw = Vector2(lx, ly).limit_length(1.0)
	if left_stick_raw.length() > 0.95:
		left_stick_raw = left_stick_raw.normalized()
	
	var rx: float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ry: float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if abs(rx) < 0.1 and abs(ry) < 0.1:
		rx = float(Input.is_physical_key_pressed(KEY_L)) - float(Input.is_physical_key_pressed(KEY_J))
		ry = float(Input.is_physical_key_pressed(KEY_K)) - float(Input.is_physical_key_pressed(KEY_I))
		
	right_stick_raw = Vector2(rx, ry).limit_length(1.0)
	if right_stick_raw.length() > 0.95:
		right_stick_raw = right_stick_raw.normalized()
	
	var lt: float = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	var rt: float = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)
	if lt < 0.05 and rt < 0.05:
		lt = float(Input.is_physical_key_pressed(KEY_Q))
		rt = float(Input.is_physical_key_pressed(KEY_E))
	var raw_lean: float = rt - lt
	# Apply audio-log power curve (exponent 2.2) to desensitize light-to-mid trigger pulls while preserving full speed at 1.0
	lean = signf(raw_lean) * pow(absf(raw_lean), 2.2)
	
	# Chase camera side select on the d-pad. Absolute rather than a toggle: pressing the same side
	# twice is a no-op, so the view you get is never a function of the view you had.
	if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_LEFT) or Input.is_physical_key_pressed(KEY_BRACKETLEFT):
		camera_side = -1
	elif Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_RIGHT) or Input.is_physical_key_pressed(KEY_BRACKETRIGHT):
		camera_side = 1

	# Push Button polling (Joypad X/Square for Left Foot, A/Cross for Right Foot; V / B for keyboard)
	var curr_push_left: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_X) or Input.is_physical_key_pressed(KEY_V)
	var curr_push_right: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_A) or Input.is_physical_key_pressed(KEY_B)
	
	# Latch push triggers so button presses aren't dropped before SkaterController evaluation
	if curr_push_left and not _prev_push_left:
		push_left_triggered = true
	if curr_push_right and not _prev_push_right:
		push_right_triggered = true
	_prev_push_left = curr_push_left
	_prev_push_right = curr_push_right
	
	# Spacebar fallback for keyboard jumping with Z (Kickflip) / X (Heelflip) / C (Shove-it)
	var curr_space: bool = Input.is_physical_key_pressed(KEY_SPACE)
	if curr_space and not _prev_space_pressed and current_pop_state != PopState.POPPED:
		pop_impulse_triggered = true
		current_pop_state = PopState.POPPED
		_set_pop(TrickSignature.Pop.OLLIE)
		_build_trick_signature()
	_prev_space_pressed = curr_space
	
	# Poll all controller buttons to aid telemetry and button remapping
	var pressed_btns: Array[String] = []
	for btn_idx in 64:
		if Input.is_joy_button_pressed(0, btn_idx):
			pressed_btns.append(_get_joy_button_name(btn_idx))
	current_button_string = "None" if pressed_btns.is_empty() else ", ".join(pressed_btns)

func _get_joy_button_name(btn: int) -> String:
	match btn:
		JOY_BUTTON_A: return "0 (A / Cross)"
		JOY_BUTTON_B: return "1 (B / Circle)"
		JOY_BUTTON_X: return "2 (X / Square)"
		JOY_BUTTON_Y: return "3 (Y / Triangle)"
		JOY_BUTTON_BACK: return "4 (Back / Select / Share)"
		JOY_BUTTON_GUIDE: return "5 (Guide / PS / Home)"
		JOY_BUTTON_START: return "6 (Start / Options)"
		JOY_BUTTON_LEFT_STICK: return "7 (L3 / Left Stick)"
		JOY_BUTTON_RIGHT_STICK: return "8 (R3 / Right Stick)"
		JOY_BUTTON_LEFT_SHOULDER: return "9 (L1 / Left Bumper)"
		JOY_BUTTON_RIGHT_SHOULDER: return "10 (R1 / Right Bumper)"
		JOY_BUTTON_DPAD_UP: return "11 (D-Pad Up)"
		JOY_BUTTON_DPAD_DOWN: return "12 (D-Pad Down)"
		JOY_BUTTON_DPAD_LEFT: return "13 (D-Pad Left)"
		JOY_BUTTON_DPAD_RIGHT: return "14 (D-Pad Right)"
		JOY_BUTTON_MISC1: return "15 (Misc 1 / Share / Mic)"
		JOY_BUTTON_PADDLE1: return "16 (Paddle 1 / Upper Right)"
		JOY_BUTTON_PADDLE2: return "17 (Paddle 2 / Upper Left)"
		JOY_BUTTON_PADDLE3: return "18 (Paddle 3 / Lower Right)"
		JOY_BUTTON_PADDLE4: return "19 (Paddle 4 / Lower Left)"
		JOY_BUTTON_TOUCHPAD: return "20 (Touchpad Click)"
		_: return "%d (Raw Button)" % btn

func _detect_pop_load_and_flick() -> void:
	if current_pop_state == PopState.POPPED:
		return # Wait for SkaterController touchdown to reset state
		
	var left_is_front: bool = leading_foot == Foot.LEFT
	var front: Vector2 = front_stick()
	var back: Vector2 = back_stick()
	
	# Ollie / Switch Ollie Load (Trailing back foot pulled down in lower hemisphere)
	if current_pop_state == PopState.NONE:
		if back.length() >= 0.70 and back.y >= 0.50:
			current_pop_state = PopState.LOADING_OLLIE
			trick_status_string = "Loading Ollie (Tail)"
			_last_frame_scoop_angle = rad_to_deg(back.angle())
			accumulated_scoop_deg = 0.0
			max_swept_angle = 0.0
		# Nollie / Switch Nollie Load (Leading front foot pushed up in upper hemisphere)
		elif front.length() >= 0.70 and front.y <= -0.50:
			current_pop_state = PopState.LOADING_NOLLIE
			trick_status_string = "Loading Nollie (Nose)"
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
		current_pop_state = PopState.POPPED
		# Differentiate Switch vs Regular Ollie based on profile stance vs live orientation
		if (stance == Stance.REGULAR and not left_is_front) or (stance == Stance.GOOFY and left_is_front):
			_set_pop(TrickSignature.Pop.SWITCH_OLLIE)
		else:
			_set_pop(TrickSignature.Pop.OLLIE)
		_build_trick_signature()
	elif current_pop_state == PopState.LOADING_NOLLIE and back.length() >= 0.35 and back.y >= -0.20:
		pop_impulse_triggered = true
		current_pop_state = PopState.POPPED
		if (stance == Stance.REGULAR and not left_is_front) or (stance == Stance.GOOFY and left_is_front):
			_set_pop(TrickSignature.Pop.FAKIE_OLLIE)
		else:
			_set_pop(TrickSignature.Pop.NOLLIE)
		_build_trick_signature()
	
	# Reset to None if sticks return to neutral without flicking
	if right_stick_raw.length() < 0.20 and left_stick_raw.length() < 0.20 and current_pop_state != PopState.NONE:
		current_pop_state = PopState.NONE
		max_swept_angle = 0.0
		trick_status_string = "Grounded & Rolling"

func _set_pop(p: TrickSignature.Pop) -> void:
	last_pop = p
	last_pop_type = ["Ollie", "Nollie", "Switch Ollie", "Fakie Ollie"][p]

## Measures what the player just did into `current_trick`. Body rotation is NOT known yet - it
## happens during flight - so SkaterController fills body_deg in at touchdown and resolves the name
## there. Nothing here builds a display string; naming lives entirely in TrickNames.gd.
func _build_trick_signature() -> void:
	active_flip_type = "None"

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
	
	# Universal Flick Rule: Flicking outward (-X for Left, +X for Right = behind body) = Kickflip; Inward (+X for Left, -X for Right = in front of body) = Heelflip
	if flick_stick.length() >= 0.25 and abs(flick_stick.y) <= abs(flick_stick.x):
		if flick_is_left_foot:
			active_flip_type = "Kickflip" if flick_stick.x < 0.0 else "Heelflip"
		else:
			active_flip_type = "Kickflip" if flick_stick.x > 0.0 else "Heelflip"
	elif Input.is_physical_key_pressed(KEY_Z) or Input.is_physical_key_pressed(KEY_F):
		active_flip_type = "Kickflip"
	elif Input.is_physical_key_pressed(KEY_X) or Input.is_physical_key_pressed(KEY_G):
		active_flip_type = "Heelflip"
		
	# In Fakie and Nollie stance the flicking foot swaps ends, so the physical flick maps to the opposite deck
	# roll. Mirror the classification to keep both HUD trick terminology and control-to-rotation behaviour accurate.
	if (last_pop == TrickSignature.Pop.FAKIE_OLLIE or last_pop == TrickSignature.Pop.NOLLIE) and active_flip_type != "None":
		active_flip_type = "Heelflip" if active_flip_type == "Kickflip" else "Kickflip"

	match active_flip_type:
		"Kickflip": sig.flip = TrickSignature.Flip.KICK
		"Heelflip": sig.flip = TrickSignature.Flip.HEEL
		_: sig.flip = TrickSignature.Flip.NONE

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

## `root` is the yaw-carrying SkaterRoot. It is passed explicitly rather than reached via
## pivot.get_parent(), which now resolves to the surface-tilted SurfaceAlign node and would skew the
## stationary forward vector on any ramp.
func update_stance_facts(pivot: Node3D, left_foot: Node3D, right_foot: Node3D, vel: Vector3, root: Node3D = null) -> void:
	var nose_pos: Vector3 = pivot.to_global(Vector3(0, 0, -0.35))
	
	# Live Mesh-Under-Foot check via distance to Nose
	if left_foot.global_position.distance_squared_to(nose_pos) < right_foot.global_position.distance_squared_to(nose_pos):
		left_foot_over = DeckEnd.NOSE
		right_foot_over = DeckEnd.TAIL
	else:
		left_foot_over = DeckEnd.TAIL
		right_foot_over = DeckEnd.NOSE
	
	# Live Trailing / Leading Foot check via velocity or static forward alignment
	var forward_source: Node3D = root if root != null else pivot.get_parent()
	var travel_dir: Vector3 = vel.normalized() if vel.length_squared() > 0.05 else -forward_source.global_transform.basis.z
	var left_dot: float = (left_foot.global_position - pivot.global_position).dot(travel_dir)
	var right_dot: float = (right_foot.global_position - pivot.global_position).dot(travel_dir)
	if left_dot > right_dot:
		leading_foot = Foot.LEFT
		trailing_foot = Foot.RIGHT
	else:
		leading_foot = Foot.RIGHT
		trailing_foot = Foot.LEFT
