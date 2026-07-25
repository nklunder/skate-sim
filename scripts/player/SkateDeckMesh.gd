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
			
		# 5-point smooth parabolic cross-section across deck width
		var top_row: Array[Vector3] = []
		var bot_row: Array[Vector3] = []
		var x_ratios: Array[float] = [-1.0, -0.5, 0.0, 0.5, 1.0]
		for ratio in x_ratios:
			var x_pos: float = ratio * w
			var concave_rise: float = pow(abs(ratio), 2.0) * 0.008 # Outer rail curves up by +0.008 (8mm), center sits at 0.0
			top_row.append(Vector3(x_pos, y_base + half_thickness + concave_rise, z))
			bot_row.append(Vector3(x_pos, y_base - half_thickness + concave_rise, z))
			
		rings.append({"top": top_row, "bot": bot_row})
	
	# Triangulate adjacent sections into smooth continuous faces
	for i in range(rings.size() - 1):
		var t0: Array[Vector3] = rings[i]["top"]
		var t1: Array[Vector3] = rings[i+1]["top"]
		var b0: Array[Vector3] = rings[i]["bot"]
		var b1: Array[Vector3] = rings[i+1]["bot"]
		
		for j in range(4):
			# Top Griptape Surface (Concave bowl - upward normal winding)
			_add_quad_rev(st_grip, t0[j], t1[j], t1[j+1], t0[j+1])
			# Underside Maple Surface (Convex belly - downward normal winding)
			_add_quad(st_wood, b0[j], b1[j], b1[j+1], b0[j+1])
			
		# Side Rim Wood Edges (Left rail j=0, Right rail j=4)
		_add_quad(st_wood, b0[0], b1[0], t1[0], t0[0])
		_add_quad_rev(st_wood, b0[4], b1[4], t1[4], t0[4])
	
	# Nose & Tail end cap trim
	var first_t: Array[Vector3] = rings[0]["top"]
	var first_b: Array[Vector3] = rings[0]["bot"]
	var last_t: Array[Vector3] = rings[rings.size() - 1]["top"]
	var last_b: Array[Vector3] = rings[rings.size() - 1]["bot"]
	for j in range(4):
		_add_quad(st_wood, first_b[j], first_b[j+1], first_t[j+1], first_t[j])
		_add_quad_rev(st_wood, last_b[j], last_b[j+1], last_t[j+1], last_t[j])
	
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
