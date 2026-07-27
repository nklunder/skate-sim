class_name TrickSignature
extends RefCounted

## A measurement of what physically happened during one trick.
##
## Deliberately encodes NO skateboarding naming conventions. It does not decide what counts as
## frontside, whether fakie reverses labels, or whether nollie keeps them. It records the action;
## TrickNames.gd maps the recording to whatever you decided to call it.

enum Pop { OLLIE, NOLLIE, SWITCH_OLLIE, FAKIE_OLLIE }
enum Flip { NONE, KICK, HEEL }

# --- Measured, rider-relative (see rider_sign) -------------------------------
var pop: Pop = Pop.OLLIE
var flip: Flip = Flip.NONE
var shuv_deg: int = 0 # Board rotation RELATIVE TO THE BODY. 0, +/-180, +/-360.
var body_deg: int = 0 # Body rotation. 0, +/-180, +/-360, +/-540 ...
var flick_tilt_deg: float = 0.0 # Pitch tilt imparted by flick angle (- = boned, + = rocketed)
## How fast the flicking stick was MOVING when the flick registered, in deflection units per second.
##
## The one measurement that separates a lazy flip from an explosive one: both end with the stick in
## the same place, so no reading of stick POSITION can tell them apart.
##
## Measured but not yet consumed - nothing reads it today. It is recorded here rather than computed
## where it is used because two separate systems are meant to scale off it, and off the SAME number:
## how fast the shoe whips through its flick arc, and (later) how fast the deck rotates. Sharing one
## measurement is what keeps the shoe clearing the deck at every intensity, instead of needing a
## separately calibrated floor speed on each.
var flick_speed: float = 0.0

# --- Derived -----------------------------------------------------------------

## The board's net turn in the world: body and shuv combine, so they can cancel.
## Zero while body_deg is non-zero is the "board stayed put but I turned" family.
var board_world_deg: int:
	get: return body_deg + shuv_deg

## True when body and board turned the same way (as opposed to against each other).
var body_with_shuv: bool:
	get: return body_deg != 0 and shuv_deg != 0 and signi(body_deg) == signi(shuv_deg)

## An odd number of half-turns leaves you riding the other way round.
var lands_switch: bool:
	get: return (absi(body_deg) / 180) % 2 == 1

# --- Frame conversion -------------------------------------------------------
#
# EVERY sign bug in this system has had the same cause: a rotation measured in one frame being
# stored as if it were in another. The two measured rotations do NOT come from the same frame, so
# they do NOT take the same correction. Both conversions live here so there is one place to look.
#
#   quantity   measured in            already rider-relative?   correction needed
#   --------   --------------------   ----------------------   --------------------------------
#   shuv_deg   thumbstick sweep       yes, for facing          which FOOT scoops (swaps by pop)
#   body_deg   world yaw of pivot     no                       goofy mirror + riding reversed
#
# Getting either wrong does not crash or look obviously broken - the trick simply resolves to its
# mirror image (a switch 360 flip reads as a switch hardflip). Only the tests catch it.

## Mirrors goofy onto regular so an identical physical motion yields identical numbers.
## This is the FACING-INDEPENDENT part, shared by both quantities.
static func rider_sign(is_goofy: bool) -> int:
	return -1 if is_goofy else 1

## World yaw -> rider-relative, for body rotation.
##
## Body rotation is read off board_pivot in world space, so unlike the shuv it is NOT already
## body-relative: when the rider is riding reversed (switch or fakie) their frontside is the other
## way round in the world, and the sign must flip to match. `riding_reversed` is sampled from the
## pivot's actual yaw at pop time rather than inferred from the pop type, so it stays honest no
## matter how the rider arrived at that orientation.
static func body_sign(is_goofy: bool, riding_reversed: bool) -> int:
	var s: int = rider_sign(is_goofy)
	return -s if riding_reversed else s

## Thumbstick sweep -> rider-relative, for board (shuv) rotation.
##
## The sweep direction is already relative to the rider's body because the sticks map anatomically
## to feet. What it is NOT invariant to is WHICH foot does the scooping: the right stick scoops for
## an Ollie / Fakie Ollie but the left stick for a Switch Ollie / Nollie, so an identical sweep
## means the opposite board direction. Positive result == frontside, in every stance.
static func shuv_sign(is_goofy: bool, left_foot_scoops: bool) -> int:
	var s: int = rider_sign(is_goofy)
	return -s if left_foot_scoops else s

## One-line readout printed by the HUD after every landing. This is the authoring tool: perform a
## trick, read this off the screen, paste the values into TrickNames.TABLE with a name.
func describe() -> String:
	return "pop=%s flip=%s shuv=%+d body=%+d world=%+d with_shuv=%s" % [
		Pop.keys()[pop], Flip.keys()[flip], shuv_deg, body_deg, board_world_deg, body_with_shuv,
	]
