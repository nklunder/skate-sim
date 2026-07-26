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
@onready var leading_lbl: RichTextLabel = $Panel/VBoxContainer/LeadingLabel
@onready var trailing_lbl: RichTextLabel = $Panel/VBoxContainer/TrailingLabel
@onready var mesh_lbl: Label = $Panel/VBoxContainer/MeshUnderFootLabel
@onready var surface_lbl: Label = $Panel/VBoxContainer/SurfaceLabel
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
	# Height above the surface the skater is actually over, not raw world Y - the two only agreed
	# back when the world was a single flat plane.
	var air_gap: float = skater_controller.global_position.y - skater_controller.ride_height
	if skater_controller.surface_hit != null and skater_controller.surface_hit.valid:
		air_gap = skater_controller.global_position.y - skater_controller.surface_hit.position.y - skater_controller.ride_height
	alt_lbl.text = "Height: %s m | V-Speed: %s m/s" % [_fmt(air_gap), _fmt(skater_controller.vertical_velocity)]
	
	speed_lbl.text = "Speed: %.2f m/s (Max: %.1f)" % [skater_controller.current_speed, skater_controller.max_push_speed]
	push_lbl.text = "Last Push: %s" % state.last_push_type
	
	var deck_roll: float = fmod(skater_controller.board_mesh.rotation_degrees.z, 360.0) if is_instance_valid(skater_controller.board_mesh) else 0.0
	pitch_lbl.text = "Deck | Pitch: %3.1f° | Roll: %3.0f° (%s)" % [skater_controller.board_pivot.rotation_degrees.x, deck_roll, "AIR" if not skater_controller.is_grounded else "GND"]
	
	left_stick_lbl.text = "Left Stick   | Mag: %.2f | Ang: %3.0f°" % [state.left_mag, rad_to_deg(state.left_angle)]
	right_stick_lbl.text = "Right Stick | Mag: %.2f | Ang: %3.0f°" % [state.right_mag, rad_to_deg(state.right_angle)]
	lean_lbl.text = "Trigger Spin (RT-LT): %.2f" % state.lean
	stance_lbl.text = "Static Config Stance: %s" % ("REGULAR" if state.stance == state.Stance.REGULAR else "GOOFY")
	# The HUD is the only place foot identity becomes text; logic elsewhere compares enum values.
	var lead_color: String = "#3399e6" if state.leading_foot == FootInputState.Foot.LEFT else "#e64d4d"
	var trail_color: String = "#3399e6" if state.trailing_foot == FootInputState.Foot.LEFT else "#e64d4d"
	leading_lbl.text = "Live Leading Foot: [color=%s]%s[/color]" % [lead_color, FootInputState.foot_name(state.leading_foot)]
	trailing_lbl.text = "Live Trailing Foot: [color=%s]%s[/color]" % [trail_color, FootInputState.foot_name(state.trailing_foot)]
	mesh_lbl.text = "Mesh Under Foot: L->[%s] | R->[%s]" % [
		FootInputState.deck_end_name(state.left_foot_over), FootInputState.deck_end_name(state.right_foot_over)]
	# Surface probe readout: what the collision layer currently sees underneath the trucks.
	var hit: SurfaceProbe.Hit = skater_controller.surface_hit
	if hit != null and hit.valid:
		var slope: float = rad_to_deg(hit.normal.angle_to(Vector3.UP))
		surface_lbl.text = "Surface: y=%s | slope %s° | tilt %s°" % [
			_fmt(hit.position.y), _fmt0(slope), _fmt0(rad_to_deg(skater_controller.surface_align.rotation.x))]
	else:
		surface_lbl.text = "Surface: none (airborne)"

	# Paste these values straight into TrickNames.TABLE to name the trick you just landed.
	sig_lbl.text = "Signature: %s" % state.last_trick_signature

## Formats a float without the "-0.00" flicker. Raycast results carry ~1e-8 of float noise, and
## "%.2f" faithfully renders its sign, so a perfectly stable surface reads as jittering between
## "0.00" and "-0.00". Snapping and adding 0.0 collapses IEEE negative zero to positive zero.
func _fmt(v: float) -> String:
	return "%.2f" % (snappedf(v, 0.01) + 0.0)

func _fmt0(v: float) -> String:
	return "%.0f" % (snappedf(v, 1.0) + 0.0)
