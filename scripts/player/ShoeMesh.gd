class_name ShoeMesh
extends Node3D

@export_category("Model & Calibration")
@export var shoe_scene: PackedScene = preload("res://assets/models/shoes/shoes_dc_tonik_right.glb")
@export var is_left_shoe: bool = false
@export var model_scale: float = 1.0 # Easily tunable multiplier
@export var model_offset: Vector3 = Vector3.ZERO
@export var model_rotation_deg: Vector3 = Vector3(0, 90, 0)

@export_category("Test Colorization")
@export var apply_test_colors: bool = true
## Diagnostic test colors: default Blue for left foot, Red for right foot
@export var tint_color: Color = Color(1.0, 1.0, 1.0, 1.0)

var _model_instance: Node3D = null

func _ready() -> void:
	_setup_shoe_model()

func _setup_shoe_model() -> void:
	if shoe_scene == null:
		return
		
	var instance: Node3D = shoe_scene.instantiate() as Node3D
	if not instance:
		return
		
	instance.name = "ShoeModel"
	
	# Handle X-axis scale mirroring for opposite foot
	var sx: float = -model_scale if is_left_shoe else model_scale
	instance.scale = Vector3(sx, model_scale, model_scale)
	instance.position = model_offset
	instance.rotation_degrees = model_rotation_deg
	add_child(instance)
	_model_instance = instance
	
	if apply_test_colors:
		_apply_color_tint(instance)

func _apply_color_tint(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		var count: int = node.mesh.get_surface_count()
		for s in range(count):
			var mat: Material = node.get_active_material(s)
			if mat is StandardMaterial3D:
				var dup: StandardMaterial3D = mat.duplicate() as StandardMaterial3D
				dup.albedo_color = dup.albedo_color * tint_color
				node.set_surface_override_material(s, dup)
				
	for child in node.get_children():
		_apply_color_tint(child)
