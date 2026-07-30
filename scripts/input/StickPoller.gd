class_name StickPoller
extends RefCounted

## Reads the physical devices and nothing else.
##
## The one place in the project that knows a gamepad exists. Everything downstream - gesture
## recognition, trick classification, the HUD - works from a Sample, so none of it has to care
## whether the input came from a thumbstick, the WASD/IJKL fallback, or a test writing values in
## directly. That last case is why this split earns its keep: the regression suites drive the
## controller by writing stick vectors, and they must not have to simulate a joypad to do it.
##
## Owns only the state polling genuinely needs: edge detection for the latched buttons, and the
## sticky camera-side selection. All derived facts (magnitudes, angles, stance, gestures) belong to
## FootInputState, which is why they are not here.

## One frame of device state. Everything the rest of the input system is allowed to know about
## the hardware.
class Sample extends RefCounted:
	var left: Vector2 = Vector2.ZERO
	var right: Vector2 = Vector2.ZERO
	var lean: float = 0.0
	## Which camera side the player SELECTED this frame: -1 left, +1 right, 0 for "no selection
	## made". Deliberately not the current side - the selection is sticky, and the sticky value is
	## FootInputState's to own. Reporting the live side here instead would mean the poller
	## overwrote that value every single frame, which silently clobbers any side set from outside
	## the device layer (the regression suite sets it directly, and it stopped taking effect).
	var camera_side_select: int = 0
	## Rising edges, latched by the caller rather than consumed here: a press must survive until the
	## physics tick that acts on it, or fast taps are silently dropped between frames.
	var push_left_edge: bool = false
	var push_right_edge: bool = false
	var pop_edge: bool = false
	## How fast each stick is being MOVED, in deflection units per second - a flat-out sweep from
	## centre to rim in a tenth of a second reads about 10.
	##
	## Device state rather than a derived fact, which is why it lives here: it needs last frame's raw
	## sample, and that is the same kind of thing as the button edges above. What it is FOR is the
	## difference between a lazy flip and an explosive one. Both end at the same stick position, so
	## no reading of position alone can tell them apart; only the speed of the motion can.
	var left_speed: float = 0.0
	var right_speed: float = 0.0

var _prev_push_left: bool = false
var _prev_push_right: bool = false
var _prev_space: bool = false
var _prev_left: Vector2 = Vector2.ZERO
var _prev_right: Vector2 = Vector2.ZERO

func poll(delta: float) -> Sample:
	var s := Sample.new()

	# Joypad input + keyboard fallback (WASD for Left Foot, IJKL for Right Foot)
	var lx: float = Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var ly: float = Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	if abs(lx) < 0.1 and abs(ly) < 0.1:
		lx = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		ly = float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
		if abs(lx) < 0.1 and abs(ly) < 0.1:
			lx = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left") if not Input.is_physical_key_pressed(KEY_L) and not Input.is_physical_key_pressed(KEY_J) else 0.0
			ly = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up") if not Input.is_physical_key_pressed(KEY_K) and not Input.is_physical_key_pressed(KEY_I) else 0.0
	s.left = _deadzone(Vector2(lx, ly))

	var rx: float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ry: float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if abs(rx) < 0.1 and abs(ry) < 0.1:
		rx = float(Input.is_physical_key_pressed(KEY_L)) - float(Input.is_physical_key_pressed(KEY_J))
		ry = float(Input.is_physical_key_pressed(KEY_K)) - float(Input.is_physical_key_pressed(KEY_I))
	s.right = _deadzone(Vector2(rx, ry))

	var lt: float = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	var rt: float = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)
	if lt < 0.05 and rt < 0.05:
		lt = float(Input.is_physical_key_pressed(KEY_Q))
		rt = float(Input.is_physical_key_pressed(KEY_E))
	# Reported LINEAR, and deliberately so. `lean` is a physical request - a truck steer angle on the
	# ground, a muscular torque in the air - and this layer's job is to say what the hardware read, not
	# to shape how it feels. A perceptual curve here is charged to EVERY consumer, including the ones
	# that never asked for it.
	#
	# It was an exponent of 2.2, added for mid-air spin styling, and carving paid for it. A carve is
	# omega = v / R with R = carve_radius_m / lean, so the curve is a curve on CURVATURE: a
	# half-pulled trigger drew a 13.8 m arc where the model says 6 m, and it took ~0.85 of travel to
	# reach a 4 m one. That is the "board does nothing, then suddenly bites" band, and it survived 07a
	# untouched because 07a fixed the model and this is upstream of it.
	#
	# `carve_and_push` pins "half lean must DOUBLE the radius" - lean maps to a steer angle and
	# curvature is what is linear in that angle - but it writes `rider.lean` directly, so the suite has
	# been asserting the linear law while this line quietly broke it for the player. That is the whole
	# hazard of shaping a physical quantity at the device boundary: nothing downstream can see it.
	#
	# If mid-air spin genuinely wants desensitising, it belongs on the single line in
	# RiderBody.advance_spin() that consumes it, where it costs the ground nothing.
	s.lean = rt - lt

	# Chase camera side select on the d-pad. Reports only what was pressed THIS frame; holding
	# nothing reports 0 and leaves the current side alone.
	if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_LEFT) or Input.is_physical_key_pressed(KEY_BRACKETLEFT):
		s.camera_side_select = -1
	elif Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_RIGHT) or Input.is_physical_key_pressed(KEY_BRACKETRIGHT):
		s.camera_side_select = 1

	# Push Button polling (Joypad Y/Triangle for Left Foot, B/Circle for Right Foot; V / B for keyboard)
	var curr_push_left: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_Y) or Input.is_physical_key_pressed(KEY_V)
	var curr_push_right: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_B) or Input.is_physical_key_pressed(KEY_B)
	s.push_left_edge = curr_push_left and not _prev_push_left
	s.push_right_edge = curr_push_right and not _prev_push_right
	_prev_push_left = curr_push_left
	_prev_push_right = curr_push_right

	# Spacebar fallback for keyboard jumping.
	var curr_space: bool = Input.is_physical_key_pressed(KEY_SPACE)
	s.pop_edge = curr_space and not _prev_space
	_prev_space = curr_space

	# Stick speed, measured after the deadzone so a stick resting on the rim does not report motion
	# from sensor noise. Guarded on delta because the first tick and a paused frame both give zero.
	if delta > 0.0:
		s.left_speed = (s.left - _prev_left).length() / delta
		s.right_speed = (s.right - _prev_right).length() / delta
	_prev_left = s.left
	_prev_right = s.right

	return s

## Clamps to the unit circle and snaps the outer rim, so sensor fluctuation at full deflection does
## not read as the stick moving.
func _deadzone(v: Vector2) -> Vector2:
	var out: Vector2 = v.limit_length(1.0)
	return out.normalized() if out.length() > 0.95 else out
