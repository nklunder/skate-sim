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

## Signed deg/s the shoulders are currently turning at.
var spin_rate_deg: float = 0.0

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

## Stops the shoulders dead. For touchdown, where the rider's weight lands and the spin is resolved
## into the rig's heading by _evaluate_touchdown_landing().
func halt_spin() -> void:
	spin_rate_deg = 0.0
