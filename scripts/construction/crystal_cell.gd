# crystal_cell.gd
# 晶胞 - 表示一个单位晶格
# 包含晶格参数、空间群、Wyckoff位置
# 可视化: 线框盒子 + Wyckoff位置小点
#
# Responsibilities:
#   - 晶格参数管理（a/b/c/alpha/beta/gamma）
#   - 空间群设置和Wyckoff位置计算
#   - 分数坐标与笛卡尔坐标互转
#   - 晶胞线框和Wyckoff小点可视化
#
# Signals:
#   cell_modified() - 晶胞参数被修改
#
# Dependencies:
#   - Resources: SpaceGroupData

extends Node3D

@export var lattice_a: float = 5.0
@export var lattice_b: float = 5.0
@export var lattice_c: float = 5.0
@export var lattice_alpha: float = 90.0  # 度
@export var lattice_beta: float = 90.0
@export var lattice_gamma: float = 90.0
@export var space_group_number: int = 1

var _space_group_data: Resource = null
var _cell_mesh_instance: MeshInstance3D = null
var _wyckoff_multimesh: MultiMeshInstance3D = null

signal cell_modified()


func _ready() -> void:
	_load_space_group_data()
	_build_cell_wireframe()
	_build_wyckoff_dots()


func _load_space_group_data() -> void:
	_space_group_data = SpaceGroupData.new()


func set_lattice_params(a: float, b: float, c: float, alpha: float, beta: float, gamma: float) -> void:
	lattice_a = a
	lattice_b = b
	lattice_c = c
	lattice_alpha = alpha
	lattice_beta = beta
	lattice_gamma = gamma
	_rebuild_visuals()
	cell_modified.emit()


func set_space_group(num: int) -> void:
	space_group_number = num
	_rebuild_visuals()
	cell_modified.emit()


func _rebuild_visuals() -> void:
	# 清除旧的
	if _cell_mesh_instance:
		_cell_mesh_instance.queue_free()
		_cell_mesh_instance = null
	if _wyckoff_multimesh:
		_wyckoff_multimesh.queue_free()
		_wyckoff_multimesh = null

	_build_cell_wireframe()
	_build_wyckoff_dots()


func get_wyckoff_positions() -> Array:
	# 返回当前空间群的所有Wyckoff位置
	var sg = _space_group_data.get_by_number(space_group_number)
	if sg == null:
		return []
	return sg.wyckoff_positions


func fractional_to_cartesian(frac: Vector3) -> Vector3:
	# 标准晶体学坐标变换
	# frac = (x, y, z) 分数坐标
	# 返回笛卡尔坐标 (Å)
	var alpha_rad := deg_to_rad(lattice_alpha)
	var beta_rad := deg_to_rad(lattice_beta)
	var gamma_rad := deg_to_rad(lattice_gamma)

	var cos_a := cos(alpha_rad)
	var cos_b := cos(beta_rad)
	var cos_g := cos(gamma_rad)
	var sin_g := sin(gamma_rad)

	# 变换矩阵 (Busing & Levy convention)
	# a轴沿x, b轴在xy平面
	var a_x := lattice_a
	var a_y := 0.0
	var a_z := 0.0

	var b_x := lattice_b * cos_g
	var b_y := lattice_b * sin_g
	var b_z := 0.0

	var c_x := lattice_c * cos_b
	var c_y := lattice_c * (cos_a - cos_b * cos_g) / maxf(abs(sin_g), 1e-6)
	var c_z_sq := lattice_c * lattice_c - c_x * c_x - c_y * c_y
	var c_z := sqrt(maxf(c_z_sq, 0.0))

	var cart := Vector3(
		frac.x * a_x + frac.y * b_x + frac.z * c_x,
		frac.x * a_y + frac.y * b_y + frac.z * c_y,
		frac.x * a_z + frac.y * b_z + frac.z * c_z
	)
	return cart


func cartesian_to_fractional(cart: Vector3) -> Vector3:
	# 逆变换: 笛卡尔 -> 分数坐标
	var alpha_rad := deg_to_rad(lattice_alpha)
	var beta_rad := deg_to_rad(lattice_beta)
	var gamma_rad := deg_to_rad(lattice_gamma)

	var cos_a := cos(alpha_rad)
	var cos_b := cos(beta_rad)
	var cos_g := cos(gamma_rad)
	var sin_g := sin(gamma_rad)

	var a_x := lattice_a
	var b_x := lattice_b * cos_g
	var b_y := lattice_b * sin_g
	var c_x := lattice_c * cos_b
	var c_y := lattice_c * (cos_a - cos_b * cos_g) / maxf(abs(sin_g), 1e-6)
	var c_z_sq := lattice_c * lattice_c - c_x * c_x - c_y * c_y
	var c_z := sqrt(maxf(c_z_sq, 0.0))

	# 变换矩阵
	var m := Basis(
		Vector3(a_x, 0.0, 0.0),
		Vector3(b_x, b_y, 0.0),
		Vector3(c_x, c_y, c_z)
	)
	var inv := m.inverse()
	var frac := inv * cart
	return frac


func find_nearest_wyckoff(pos: Vector3) -> Dictionary:
	# pos可以是分数坐标或笛卡尔坐标，这里统一用分数坐标
	var wyckoff_positions := get_wyckoff_positions()
	var best_label := ""
	var best_position := Vector3.ZERO
	var best_distance := INF

	for wp in wyckoff_positions:
		if not wp is Dictionary or not wp.has("positions"):
			continue
		var label: String = str(wp.get("label", ""))
		for raw_pos in wp["positions"]:
			if raw_pos is Array and raw_pos.size() >= 3:
				var wp_vec := Vector3(float(raw_pos[0]), float(raw_pos[1]), float(raw_pos[2]))
				var dist := pos.distance_to(wp_vec)
				if dist < best_distance:
					best_distance = dist
					best_position = wp_vec
					best_label = label

	return {
		"wyckoff_label": best_label,
		"position": best_position,
		"distance": best_distance
	}


func _build_cell_wireframe() -> void:
	# 用ArrayMesh画线框盒子
	# 8个顶点 (分数坐标0和1的角)
	var verts_frac := [
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0),
		Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1),
	]

	var verts_cart: Array[Vector3] = []
	for v in verts_frac:
		verts_cart.append(fractional_to_cartesian(v))

	# 12条边
	var edges := [
		[0,1],[1,2],[2,3],[3,0],  # 底面
		[4,5],[5,6],[6,7],[7,4],  # 顶面
		[0,4],[1,5],[2,6],[3,7],  # 竖边
	]

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var positions := PackedVector3Array()
	var colors := PackedColorArray()

	var line_color := Color(0.4, 0.6, 0.8, 0.6)
	for edge in edges:
		positions.append(verts_cart[edge[0]])
		positions.append(verts_cart[edge[1]])
		colors.append(line_color)
		colors.append(line_color)

	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_COLOR] = colors

	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)

	_cell_mesh_instance = MeshInstance3D.new()
	_cell_mesh_instance.mesh = arr_mesh

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	arr_mesh.surface_set_material(0, mat)

	add_child(_cell_mesh_instance)


func _build_wyckoff_dots() -> void:
	var wyckoff_positions := get_wyckoff_positions()

	# 收集所有Wyckoff笛卡尔坐标
	var cart_positions: Array[Vector3] = []
	for wp in wyckoff_positions:
		if not wp is Dictionary or not wp.has("positions"):
			continue
		for raw_pos in wp["positions"]:
			if raw_pos is Array and raw_pos.size() >= 3:
				var frac_pos := Vector3(float(raw_pos[0]), float(raw_pos[1]), float(raw_pos[2]))
				cart_positions.append(fractional_to_cartesian(frac_pos))

	if cart_positions.is_empty():
		return

	# 共享球体网格
	var sphere := SphereMesh.new()
	sphere.radius = 0.08
	sphere.height = 0.16
	sphere.radial_segments = 8
	sphere.rings = 6

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.8, 1.0, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.surface_set_material(0, mat)

	# 创建MultiMesh
	var mm := MultiMesh.new()
	mm.mesh = sphere
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = cart_positions.size()

	for i in range(cart_positions.size()):
		mm.set_instance_transform(i, Transform3D(Basis(), cart_positions[i]))

	_wyckoff_multimesh = MultiMeshInstance3D.new()
	_wyckoff_multimesh.multimesh = mm
	_wyckoff_multimesh.name = "WyckoffDots"
	add_child(_wyckoff_multimesh)
