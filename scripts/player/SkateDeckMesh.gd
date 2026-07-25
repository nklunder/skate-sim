class_name SkateDeckMesh
extends MeshInstance3D

@export var deck_length: float = 0.80
@export var deck_width: float = 0.22
@export var deck_thickness: float = 0.012
@export var kicktail_angle_deg: float = 18.0
@export var kicktail_start_z: float = 0.24

func _ready() -> void:
	_generate_continuous_deck()

func _generate_continuous_deck() -> void:
	var st_grip: SurfaceTool = SurfaceTool.new()
	var st_wood: SurfaceTool = SurfaceTool.new()
	
	st_grip.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Define profile cross-sections along longitudinal Z-axis (Nose -0.40 to Tail +0.40)
	var z_slices: Array[float] = [-0.40, -0.36, -0.28, -0.18, 0.0, 0.18, 0.28, 0.36, 0.40]
	var half_thickness: float = deck_thickness * 0.5
	var slope_tan: float = tan(deg_to_rad(kicktail_angle_deg))
	
	var rings: Array = []
	for z in z_slices:
		# Width taper for popsicle rounded tips
		var w: float = deck_width * 0.5
		if abs(z) >= 0.38:
			w *= 0.35
		elif abs(z) >= 0.34:
			w *= 0.82
			
		# Elevation calculation along smooth upturned kicktails
		var y_base: float = 0.0
		if z > kicktail_start_z:
			y_base = (z - kicktail_start_z) * slope_tan
		elif z < -kicktail_start_z:
			y_base = (-z - kicktail_start_z) * slope_tan
			
		# Cross section: Left edge (-X), Center (0), Right edge (+X)
		var top_left: Vector3 = Vector3(-w, y_base + half_thickness + 0.002, z)
		var top_center: Vector3 = Vector3(0.0, y_base + half_thickness, z)
		var top_right: Vector3 = Vector3(w, y_base + half_thickness + 0.002, z)
		
		var bot_left: Vector3 = Vector3(-w, y_base - half_thickness + 0.002, z)
		var bot_center: Vector3 = Vector3(0.0, y_base - half_thickness, z)
		var bot_right: Vector3 = Vector3(w, y_base - half_thickness + 0.002, z)
		
		rings.append({"tl": top_left, "tc": top_center, "tr": top_right, "bl": bot_left, "bc": bot_center, "br": bot_right})
	
	# Triangulate adjacent sections into smooth continuous faces
	for i in range(rings.size() - 1):
		var r0: Dictionary = rings[i]
		var r1: Dictionary = rings[i+1]
		
		# Top Griptape Surface (Matte Black - upward normal winding)
		_add_quad_rev(st_grip, r0.tl, r1.tl, r1.tc, r0.tc)
		_add_quad_rev(st_grip, r0.tc, r1.tc, r1.tr, r0.tr)
		
		# Underside Maple Surface (Stained Orange - downward normal winding)
		_add_quad(st_wood, r0.bl, r1.bl, r1.bc, r0.bc)
		_add_quad(st_wood, r0.bc, r1.bc, r1.br, r0.br)
		
		# Side Rim Wood Edges
		_add_quad(st_wood, r0.bl, r1.bl, r1.tl, r0.tl)
		_add_quad_rev(st_wood, r0.br, r1.br, r1.tr, r0.tr)
	
	# Nose & Tail end cap trim
	var first: Dictionary = rings[0]
	var last: Dictionary = rings[rings.size() - 1]
	_add_quad(st_wood, first.bl, first.br, first.tr, first.tl)
	_add_quad_rev(st_wood, last.bl, last.br, last.tr, last.tl)
	
	st_grip.generate_normals()
	st_wood.generate_normals()
	
	var arr_mesh: ArrayMesh = st_grip.commit()
	st_wood.commit(arr_mesh)
	
	# Assign professional high-contrast materials with disabled culling to ensure proper top/bottom orientation
	var mat_grip: StandardMaterial3D = StandardMaterial3D.new()
	mat_grip.albedo_color = Color(0.12, 0.12, 0.14, 1.0)
	mat_grip.roughness = 0.95
	mat_grip.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	var mat_wood: StandardMaterial3D = StandardMaterial3D.new()
	mat_wood.albedo_color = Color(0.92, 0.45, 0.12, 1.0)
	mat_wood.roughness = 0.35
	mat_wood.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	mesh = arr_mesh
	set_surface_override_material(0, mat_grip)
	set_surface_override_material(1, mat_wood)


func _add_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3) -> void:
	st.add_vertex(v0)
	st.add_vertex(v1)
	st.add_vertex(v2)
	st.add_vertex(v0)
	st.add_vertex(v2)
	st.add_vertex(v3)

func _add_quad_rev(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3) -> void:
	st.add_vertex(v0)
	st.add_vertex(v2)
	st.add_vertex(v1)
	st.add_vertex(v0)
	st.add_vertex(v3)
	st.add_vertex(v2)
