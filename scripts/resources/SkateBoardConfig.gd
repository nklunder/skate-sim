class_name SkateBoardConfig
extends Resource

## ⚠️ Only `carve_radius_m` is currently read by the game (SkaterController step 4). Every other field
## below is a roadmap placeholder that nothing consumes yet - tuning them in the inspector is
## silently a no-op. Wire a field up before relying on it, and drop this note once they are live.

@export_category("Pop Forces")
@export var ollie_pop_force: float = 6.0 # unused
@export var nollie_pop_force: float = 6.0 # unused
@export var scoop_force: float = 4.0 # unused

@export_category("Steering Sensitivity")
## LIVE - the turn RADIUS in metres at full lean, which is what a truck actually sets.
##
## Bushings deflect by an amount set by how hard the rider leans; that deflection is a steering
## angle, and the steering angle with the wheelbase gives a radius. The angular rate then falls out
## as omega = v / R, so the same lean carves the same arc at any speed. This replaced a flat
## `turn_speed` in rad/s, which turned at ~172 deg/s whether the skater was doing 7 m/s or 1 - about
## right when fast and 4x too quick at walking pace, which is what made slow riding read as darty.
##
## Real boards vary enormously with truck tightness, so this is the natural knob for the hardware
## customisation work. Smaller is tighter. Lean scales CURVATURE, not radius: half lean is a 6 m arc.
@export var carve_radius_m: float = 3.0
@export var lean_sensitivity: float = 2.0 # unused
@export var powerslide_threshold: float = 0.7 # unused

@export_category("Landing Tolerances")
@export var max_pitch_angle: float = 35.0 # unused
@export var max_roll_angle: float = 30.0 # unused
@export var imperfect_landing_drag: float = 1.5 # unused
