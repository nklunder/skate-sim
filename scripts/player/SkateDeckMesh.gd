class_name SkateDeckMesh
extends Node3D

@export_category("Model & Scale Calibration")
@export var blend_model: PackedScene = preload("res://skateboard.blend")
@export var use_low_poly: bool = true # 8,328 tris vs 646,208 on the high tier; visually indistinguishable at gameplay range
@export var model_scale: float = 0.1722 # Calibrated so total deck length equals 0.80 m (31.5 inches)
@export var model_offset: Vector3 = Vector3(-0.32387, -0.35848, 0.11687) # Aligns the deck on X/Z and puts its UNDERSIDE at y=0, i.e. the rig origin

@export_category("Material Styling")
@export var apply_custom_materials: bool = true

@export_category("Deck Two-Tone")
@export var deck_shader: Shader = preload("res://resources/deck_two_tone.gdshader")
@export var grip_color: Color = Color(0.12, 0.12, 0.14, 1.0) # Matte black griptape on the standing side
@export var deck_bottom_color: Color = Color(0.95, 0.30, 0.02, 1.0) # High-visibility orange so rotation reads mid-air
@export_range(1.0, 64.0) var facing_sharpness: float = 14.0 # Crossover band width around the rails
@export_range(0.0, 1.0) var bottom_emission: float = 0.30 # Keeps the underside readable when it faces away from the sun
@export_range(0.0, 1.0) var grip_grain_strength: float = 0.55 # Set to 0.0 for a flat, untextured top
@export_range(0.0, 1.0) var grip_grain_bump: float = 0.45 # Micro-shadowing; does the heavy lifting on the grit read
@export_range(1.0, 4096.0) var grip_grain_scale: float = 720.0

func _ready() -> void:
	_setup_skateboard_model()

func _build_deck_material() -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = deck_shader
	mat.set_shader_parameter("grip_color", grip_color)
	mat.set_shader_parameter("bottom_color", deck_bottom_color)
	mat.set_shader_parameter("grip_roughness", 0.95)
	mat.set_shader_parameter("bottom_roughness", 0.70)
	mat.set_shader_parameter("bottom_emission", bottom_emission)
	mat.set_shader_parameter("facing_sharpness", facing_sharpness)
	mat.set_shader_parameter("grain_strength", grip_grain_strength)
	mat.set_shader_parameter("grain_bump", grip_grain_bump)
	mat.set_shader_parameter("grain_scale", grip_grain_scale)
	return mat

func _setup_skateboard_model() -> void:
	if not is_instance_valid(blend_model):
		return
		
	var model_instance: Node3D = blend_model.instantiate() as Node3D
	if not model_instance:
		return
		
	model_instance.name = "SkateboardModel"
	model_instance.scale = Vector3(model_scale, model_scale, model_scale)
	model_instance.position = model_offset
	add_child(model_instance)
	
	if not apply_custom_materials:
		# Just handle high/low poly deduplication without modifying surfaces
		for child in model_instance.get_children():
			var is_low: bool = child.name.to_lower().ends_with("_low")
			child.visible = is_low if use_low_poly else (not is_low)
		return
	
	# Create authentic, high-contrast materials for rich presentation
	var mat_deck: ShaderMaterial = _build_deck_material()

	var mat_truck: StandardMaterial3D = StandardMaterial3D.new()
	mat_truck.albedo_color = Color(0.84, 0.86, 0.89, 1.0) # Silver brushed aluminum
	mat_truck.metallic = 0.85
	mat_truck.roughness = 0.30
	
	var mat_wheel: StandardMaterial3D = StandardMaterial3D.new()
	mat_wheel.albedo_color = Color(0.96, 0.95, 0.90, 1.0) # Cream polyurethane
	mat_wheel.roughness = 0.45
	
	var mat_chrome: StandardMaterial3D = StandardMaterial3D.new()
	mat_chrome.albedo_color = Color(0.75, 0.77, 0.80, 1.0) # Chrome hardware and bearing shields
	mat_chrome.metallic = 0.95
	mat_chrome.roughness = 0.15
	
	var mat_bushing: StandardMaterial3D = StandardMaterial3D.new()
	mat_bushing.albedo_color = Color(0.96, 0.40, 0.10, 1.0) # Vibrant orange polyurethane bushings
	mat_bushing.roughness = 0.60
	
	# Prevent Z-fighting and assign materials
	for child in model_instance.get_children():
		var child_name: String = child.name.to_lower()
		var is_low: bool = child_name.ends_with("_low")
		
		# Display only the selected LOD tier to prevent overlapping geometry
		child.visible = is_low if use_low_poly else (not is_low)
		
		if child is MeshInstance3D and child.mesh:
			var surf_count: int = child.mesh.get_surface_count()
			if child_name.contains("wheel"):
				for s in range(surf_count):
					child.set_surface_override_material(s, mat_wheel)
			elif child_name.contains("truck") or child_name.contains("base") or child_name.contains("riser"):
				for s in range(surf_count):
					child.set_surface_override_material(s, mat_truck)
			elif child_name.contains("bolt") or child_name.contains("bearing") or child_name.contains("steel"):
				for s in range(surf_count):
					child.set_surface_override_material(s, mat_chrome)
			elif child_name.contains("rubber"):
				for s in range(surf_count):
					child.set_surface_override_material(s, mat_bushing)
			elif child_name.contains("board"):
				# Surface 0 carries the whole deck shell (top, bottom and rails alike);
				# surfaces 1-2 are hairline slivers on the underside left over from stray
				# material indices in the .blend. All of them take the two-tone shader, which
				# splits grip from bottom by facing direction rather than by surface.
				for s in range(surf_count):
					child.set_surface_override_material(s, mat_deck)
