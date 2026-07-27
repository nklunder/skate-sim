class_name JoyButtonNames
extends RefCounted

## Human-readable names for joypad buttons, for the debug HUD's button readout.
##
## Purely a display concern, and it lives with the HUD for that reason. It used to run inside
## FootInputState._poll_inputs(), which meant sixty-four Input queries and a string join every
## physics tick to build a label - work the input system did not need and could not use, on the one
## path where per-frame cost actually matters. Nothing in the input or physics systems has ever read
## it; only DebugHUD did.
##
## Kept as a full table rather than generated from the enum because the whole point is the mapping
## between Godot's index and the labels printed on real controllers - which is exactly what you are
## looking up when remapping a button.

static func name_for(btn: int) -> String:
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

## Every button currently held on `device`, as one label. "None" when nothing is pressed.
static func pressed_summary(device: int = 0) -> String:
	var pressed: Array[String] = []
	for btn_idx in 64:
		if Input.is_joy_button_pressed(device, btn_idx):
			pressed.append(name_for(btn_idx))
	return "None" if pressed.is_empty() else ", ".join(pressed)
