class_name RiderBody
extends Node3D

## The RIDER, as distinct from the board they are standing on.
##
## Until this node existed the physics simulated exactly one body - the deck - and the skater was a
## drawing hung off it. That is the root of a whole class of problems rather than one bug:
##
##   1. The feet had no physical source of motion. Anything they did relative to the deck had to be
##      authored, so every airborne foot curve was a hand-drawn imitation of physics, needing a
##      special case per situation (pop strength did not scale it, an early landing snapped it mid
##      arc, and a straight ollie got no motion at all).
##   2. `BoardPivot.rotation.y` carried TWO unrelated quantities at once: the rider's body spin and
##      the board's 0/180 switch-stance relationship. A boardslide puts the deck 90 deg across the
##      direction of travel while the rider still faces near-forward - inexpressible while the body
##      and the board are the same object.
##
## THE SPLIT: the feet stay in the deck's frame (which is what makes switch/fakie mirroring
## inherited rather than compensated for - see FootRig's header), and only the TORSO separates. That
## is also the anatomy: your feet are on the board, your shoulders are free, and the twist lives
## between them.
##
## Driven by an explicit call from SkaterController's frame pipeline, never by its own
## _physics_process - the same rule ChaseCamera and FootRig follow, and for the same reason: the
## ordering has to be visible in the pipeline rather than being a property of node order in
## SkaterRig.tscn.

## Full-lean spin rate in the air, in degrees per second.
##
## Moved here from SkaterController unchanged. Spinning is something the RIDER does - the deck comes
## round because it is attached to them, not the other way about - and that is exactly the
## distinction this node exists to make.
@export var body_spin_speed_deg: float = 554.0
## How quickly the shoulders converge on the rate the triggers are asking for. This is the rider's
## own rotational inertia: they cannot start or stop turning instantly.
@export var spin_response: float = 20.0

@export_category("Torsion")
## Comfortable twist between the feet and the shoulders, in degrees, and ASYMMETRIC on purpose.
##
## Hips externally rotate far further than they internally rotate. That single anatomical fact is
## what makes a frontside noseslide leave the body short of the board while a backside boardslide
## lets it come all the way round - the rider runs out of comfortable range one way and not the
## other. It is also where the 20-35 deg offsets of crooked and Smith grinds come from, for free,
## rather than from a table of per-trick angles.
##
## **If frontside and backside slides come out the wrong way round in play, swap these two.** The
## magnitudes are anatomy and can be trusted; which one is "external" depends on a sign convention
## that cannot be settled until there is a ledge to slide on.
@export var twist_external_deg: float = 45.0
@export var twist_internal_deg: float = 25.0
## How hard the board is pulled back into line with the shoulders, per second.
##
## STARTS EFFECTIVELY RIGID, which is what makes introducing this a provable no-op: the board closes
## the whole twist every frame, exactly as a board welded to the rider did. Lower it to let the deck
## lag the shoulders. A plain relaxation rate rather than a spring, deliberately - a spring stiff
## enough to be rigid at 60 Hz sits right on the edge of going unstable, and there is no feel to be
## had from the rigid end of the range anyway.
@export var twist_follow: float = 1000.0

@export_category("Legs")
## Standing leg length, in metres: hip to sole with the rider stood normally on the deck.
##
## The feet sit ON the deck at this length by definition, so it is the ZERO of foot lift rather than
## a number the feet are ever compared against. Its absolute value only starts to matter when a
## torso mesh hangs off it.
@export var stand_height: float = 0.90
## Shortest the legs can be pulled up, in metres. A knee tuck has an anatomical limit; without one,
## a hard enough pop would fold the rider through their own hips.
@export var leg_min: float = 0.55
## How hard the legs pull back toward standing once tucked. Sets the RECOVERY TIME, and it is sized
## against THE DECK'S ROTATION rather than against airtime. Two things have to be true at once: the
## tuck must outlast the rotation, or the board comes round into feet that have already returned;
## and it must be spent BY the time the rotation ends, because that is the moment the feet take the
## deck back (see FootRig's composition). A tuck still standing at that instant would be a step
## change in foot height - a snap - which is the "levitate, then stomp" failure in a new costume.
@export var leg_stiffness: float = 80.0
## Well under 1.0, which is what makes the tuck a broad hump that HOLDS the feet clear rather than a
## spike that peaks and decays. Overshoot past standing is invisible, since foot_lift() floors at
## zero - a ringing leg cannot push a foot through the deck.
@export_range(0.0, 2.0) var leg_damping_ratio: float = 0.3
## Retraction speed given to the legs at the pop, in metres per second, at FULL pop impulse.
##
## This is the one muscular command in the whole arrangement, and it is deliberately an IMPULSE
## rather than a path. A knee tuck is not gravity - nothing emerges it - so something has to ask for
## it; the honest place to draw the line is authoring the effort and letting integration produce the
## motion. Everything downstream then follows for free: it scales with how hard the pop was, an
## early landing simply meets the feet on the way, and a straight ollie tucks without a special case
## because this hangs off the POP rather than off a flip that may not exist.
@export var tuck_impulse: float = 2.15

## Signed deg/s the shoulders are currently turning at.
var spin_rate_deg: float = 0.0
## Live leg length. The rider and the board are BOTH projectiles and gravity cancels exactly in the
## difference between two projectiles, so their separation is not governed by gravity at all - it is
## governed entirely by the legs. That is why there is no second ballistic integrator here to
## subtract from the board's: it would be redundant, and two integrations of the same g would drift
## apart in the last decimal for no gain.
var _leg: float = 0.0
var _leg_vel: float = 0.0
## The board's yaw offset from the rider, in degrees - the wind-up between feet and shoulders.
##
## Held as its own state rather than derived from the two frames' yaws, and that is load-bearing.
## The deck kicking out under a directional pop (lateral_pop_yaw_deg) IS a twist, and a coupling
## that re-derived the twist from the yaws every frame would relax it the instant it was applied.
## Anything that turns the board relative to the rider therefore winds THIS, and the board's yaw is
## the consequence.
var twist_deg: float = 0.0

## Advances the shoulders one frame under trigger lean, and reports HOW FAR THEY TURNED, in degrees.
##
## Returns the delta rather than the resulting absolute yaw, deliberately. While the coupling is
## rigid the board is carried round by this same delta; once the torsion spring softens it will be
## carried by some fraction of it. A caller handed the absolute yaw would have to know how the two
## frames relate in order to use it at all - which is precisely the knowledge this split exists to
## keep in one place.
##
## Below the rate threshold nothing is written, so a rider who is not asking to spin accumulates no
## drift from the lerp's asymptotic tail.
func advance_spin(lean: float, delta: float) -> float:
	var target: float = lean * body_spin_speed_deg
	spin_rate_deg = lerpf(spin_rate_deg, target, spin_response * delta)
	if absf(spin_rate_deg) <= 0.1:
		return 0.0
	var turned: float = -spin_rate_deg * delta
	rotation_degrees.y += turned
	return turned

## How far the feet are lifted off the deck, in metres. Zero while stood normally.
##
## The whole of the airborne foot motion is this one number. It replaced a parabola authored against
## flip progress, which could not answer three ordinary questions: a weak pop tucked exactly as hard
## as a full one, an early landing was snapped flat mid-arc, and a straight ollie - having no flip to
## be a progress OF - lifted the feet by literally nothing for the entire jump.
func foot_lift() -> float:
	return maxf(0.0, stand_height - _leg)

## Tucks the knees, at `scale` of full effort. Called at the pop with the same impulse scale the
## jump itself is given, so the tuck is as strong as the pop that caused it.
func tuck(scale: float) -> void:
	_leg_vel -= tuck_impulse * clampf(scale, 0.0, 1.0)

## Advances the legs one frame. `grounded` clamps them out to standing: a foot cannot sink through
## the deck it is standing on, and that clamp IS the contact - it is what makes a landing arriving
## early simply meet the feet rather than needing the animation cut short.
func solve_legs(delta: float, grounded: bool) -> void:
	var damping: float = 2.0 * leg_damping_ratio * sqrt(maxf(leg_stiffness, 0.0))
	_leg_vel += ((stand_height - _leg) * leg_stiffness - _leg_vel * damping) * delta
	_leg += _leg_vel * delta
	if grounded and _leg < stand_height:
		_leg = stand_height
		_leg_vel = 0.0
	elif _leg < leg_min:
		_leg = leg_min
		_leg_vel = 0.0

## Winds the torsion by `deg` - something turned the board relative to the rider. The deck kicking
## out under a directional pop today; a ledge dragging it round once slides exist.
func wind_twist(deg: float) -> void:
	twist_deg += deg

## Relaxes the torsion one frame and returns HOW FAR THE BOARD TURNS, in degrees.
##
## `goofy` mirrors the anatomy: a goofy rider is a regular rider reflected, so the comfortable range
## swaps sides with them.
func solve_twist(delta: float, goofy: bool) -> float:
	# Past the comfortable range the joint simply stops. A hard limit rather than a stiffer spring is
	# the honest shape for something made of bone and ligament rather than muscle, and it means a
	# ledge dragging the board round can never wind the rider past what a body can actually do.
	var limit: float = comfort_limit(twist_deg >= 0.0, goofy)
	var held: float = signf(twist_deg) * minf(absf(twist_deg), limit)
	# Excess the joint cannot hold. It is NOT discarded: a joint at its limit is rigid, so anything
	# past the limit drags the board round bodily. Dropping it instead let the tracked twist and the
	# board's real offset from the rider walk apart - measured 41 deg of twist against 171 deg of
	# actual lag, i.e. the two frames silently disagreeing about where the board was.
	var over: float = twist_deg - held
	twist_deg = held
	var closed: float = -twist_deg * minf(twist_follow * delta, 1.0)
	twist_deg += closed
	return closed - over

## The comfortable limit in one direction, in degrees. Goofy is a regular rider reflected, so the
## two sides swap with them - which is why this takes the stance rather than assuming it.
func comfort_limit(positive: bool, goofy: bool) -> float:
	return twist_external_deg if positive != goofy else twist_internal_deg

## Stops the shoulders dead. For touchdown, where the rider's weight lands and the spin is resolved
## into the rig's heading by _evaluate_touchdown_landing().
func halt_spin() -> void:
	spin_rate_deg = 0.0

func _ready() -> void:
	_leg = stand_height
