class_name SkateBoardConfig
extends Resource

## ⚠️ Only `turn_speed` is currently read by the game (SkaterController step 4). Every other field
## below is a roadmap placeholder that nothing consumes yet - tuning them in the inspector is
## silently a no-op. Wire a field up before relying on it, and drop this note once they are live.

@export_category("Pop Forces")
@export var ollie_pop_force: float = 6.0 # unused
@export var nollie_pop_force: float = 6.0 # unused
@export var scoop_force: float = 4.0 # unused

@export_category("Steering Sensitivity")
@export var turn_speed: float = 3.0 # LIVE - steering rate
@export var lean_sensitivity: float = 2.0 # unused
@export var powerslide_threshold: float = 0.7 # unused

@export_category("Landing Tolerances")
@export var max_pitch_angle: float = 35.0 # unused
@export var max_roll_angle: float = 30.0 # unused
@export var imperfect_landing_drag: float = 1.5 # unused
