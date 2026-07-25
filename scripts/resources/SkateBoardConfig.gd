class_name SkateBoardConfig
extends Resource

@export_category("Pop Forces")
@export var ollie_pop_force: float = 6.0
@export var nollie_pop_force: float = 6.0
@export var scoop_force: float = 4.0

@export_category("Steering Sensitivity")
@export var turn_speed: float = 3.0
@export var lean_sensitivity: float = 2.0
@export var powerslide_threshold: float = 0.7

@export_category("Landing Tolerances")
@export var max_pitch_angle: float = 35.0
@export var max_roll_angle: float = 30.0
@export var imperfect_landing_drag: float = 1.5
