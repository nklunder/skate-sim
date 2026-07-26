class_name DebugHUD
extends Control

@export var skater_controller: SkaterController

@onready var trick_lbl: Label = $Panel/VBoxContainer/TrickStatusLabel
@onready var pop_lbl: Label = $Panel/VBoxContainer/LastPopLabel
@onready var alt_lbl: Label = $Panel/VBoxContainer/AltitudeLabel
@onready var speed_lbl: Label = $Panel/VBoxContainer/SpeedLabel
@onready var push_lbl: Label = $Panel/VBoxContainer/PushTypeLabel
@onready var pitch_lbl: Label = $Panel/VBoxContainer/PitchLabel
@onready var left_stick_lbl: Label = $Panel/VBoxContainer/LeftStickLabel
@onready var right_stick_lbl: Label = $Panel/VBoxContainer/RightStickLabel
@onready var lean_lbl: Label = $Panel/VBoxContainer/LeanLabel
@onready var stance_lbl: Label = $Panel/VBoxContainer/StanceLabel
@onready var leading_lbl: Label = $Panel/VBoxContainer/LeadingLabel
@onready var trailing_lbl: Label = $Panel/VBoxContainer/TrailingLabel
@onready var mesh_lbl: Label = $Panel/VBoxContainer/MeshUnderFootLabel
@onready var sig_lbl: Label = $Panel/VBoxContainer/SignatureLabel

func _ready() -> void:
	if not skater_controller:
		skater_controller = get_node_or_null("/root/TestWorld/SkaterRig") as SkaterController
		if not skater_controller and is_inside_tree():
			skater_controller = get_tree().get_first_node_in_group("player") as SkaterController

func _process(_delta: float) -> void:
	if not is_instance_valid(skater_controller) or not is_instance_valid(skater_controller.input_state):
		return
	var state: FootInputState = skater_controller.input_state
	
	trick_lbl.text = "Trick Status: %s" % state.trick_status_string
	pop_lbl.text = "Last Combo: %s" % state.last_combo_string
	alt_lbl.text = "Altitude: %.2f m | V-Speed: %.2f m/s" % [skater_controller.global_position.y, skater_controller.vertical_velocity]
	
	speed_lbl.text = "Speed: %.2f m/s (Max: %.1f)" % [skater_controller.current_speed, skater_controller.max_push_speed]
	push_lbl.text = "Last Push: %s" % state.last_push_type
	
	var deck_roll: float = fmod(skater_controller.board_mesh.rotation_degrees.z, 360.0) if is_instance_valid(skater_controller.board_mesh) else 0.0
	pitch_lbl.text = "Deck | Pitch: %3.1f° | Roll: %3.0f° (%s)" % [skater_controller.board_pivot.rotation_degrees.x, deck_roll, "AIR" if not skater_controller.is_grounded else "GND"]
	
	left_stick_lbl.text = "Left Stick   | Mag: %.2f | Ang: %3.0f°" % [state.left_mag, rad_to_deg(state.left_angle)]
	right_stick_lbl.text = "Right Stick | Mag: %.2f | Ang: %3.0f°" % [state.right_mag, rad_to_deg(state.right_angle)]
	lean_lbl.text = "Trigger Spin (RT-LT): %.2f" % state.lean
	stance_lbl.text = "Static Config Stance: %s" % ("REGULAR" if state.stance == state.Stance.REGULAR else "GOOFY")
	leading_lbl.text = "Live Leading Foot: %s" % state.leading_foot
	trailing_lbl.text = "Live Trailing Foot: %s" % state.trailing_foot
	mesh_lbl.text = "Mesh Under Foot: L->[%s] | R->[%s]" % [state.left_foot_over, state.right_foot_over]
	# Paste these values straight into TrickNames.TABLE to name the trick you just landed.
	sig_lbl.text = "Signature: %s" % state.last_trick_signature
