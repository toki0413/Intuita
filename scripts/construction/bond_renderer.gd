# bond_renderer.gd
# 键渲染器 - 两个原子之间的化学键
# 支持单键/双键/离子键，可断开（带动画）
# 守恒应力可视化：偏离时键变色+振动+拉伸
#
# Responsibilities:
#   - 化学键3D渲染（圆柱体对齐两原子）
#   - 单键/双键/离子键类型区分
#   - 键断开动画（拉伸+淡出）
#   - 实时跟踪原子位置更新变换
#   - 守恒偏离时应力可视化（变色/振动/拉伸）
#
# Signals:
#   bond_broken(bond_renderer) - 键断开
#
# Dependencies:
#   - ConservationEngine (守恒偏离度)

extends MeshInstance3D

enum BondType { SINGLE, DOUBLE, IONIC }

var atom_a: Node3D = null  # atom_node引用
var atom_b: Node3D = null  # atom_node引用
var bond_type: BondType = BondType.SINGLE
var _is_broken: bool = false
var _break_progress: float = 0.0
var _bond_radius: float = 0.05

# 双键用的第二条线
var _second_cylinder: MeshInstance3D = null

# 守恒应力状态
var _stress_deviation: float = 0.0
var _stress_vibration_offset: Vector3 = Vector3.ZERO
var _stress_time: float = 0.0
var _base_bond_color: Color = Color(0.3, 0.5, 0.9)

signal bond_broken(bond_renderer: Node)


func _ready() -> void:
	_setup_cylinder()
	if bond_type == BondType.DOUBLE:
		_setup_second_cylinder()
	_update_color()
	set_process(true)


func _setup_cylinder() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = _bond_radius
	cyl.bottom_radius = _bond_radius
	cyl.radial_segments = 8
	cyl.rings = 1
	cyl.height = 1.0  # 固定高度1.0，通过scale.y调整实际长度
	mesh = cyl

	var mat := StandardMaterial3D.new()
	mat.metallic = 0.1
	mat.roughness = 0.5
	set_surface_override_material(0, mat)


func _setup_second_cylinder() -> void:
	_second_cylinder = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = _bond_radius * 0.8
	cyl.bottom_radius = _bond_radius * 0.8
	cyl.radial_segments = 8
	cyl.rings = 1
	cyl.height = 1.0  # 固定高度1.0，通过scale.y调整
	_second_cylinder.mesh = cyl

	var mat := StandardMaterial3D.new()
	mat.metallic = 0.1
	mat.roughness = 0.5
	_second_cylinder.set_surface_override_material(0, mat)
	add_child(_second_cylinder)


func _update_color() -> void:
	match bond_type:
		BondType.SINGLE:
			_base_bond_color = Color(0.3, 0.5, 0.9)  # 蓝色
		BondType.DOUBLE:
			_base_bond_color = Color(0.2, 0.8, 0.9)  # 青色
		BondType.IONIC:
			_base_bond_color = Color(0.9, 0.85, 0.2)  # 黄色
	_apply_stress_color()


func _apply_stress_color() -> void:
	# 守恒偏离时键颜色渐变：原色 → 黄色(警告) → 红色(危险)
	var color := _base_bond_color
	if _stress_deviation > 0.1:
		# 偏离0.1~0.6: 原色→黄色
		var t := clampf((_stress_deviation - 0.1) / 0.5, 0.0, 1.0)
		var warning_color := Color(1.0, 0.85, 0.15)
		color = _base_bond_color.lerp(warning_color, t)
	if _stress_deviation > 0.6:
		# 偏离0.6~1.0: 黄色→红色
		var t := clampf((_stress_deviation - 0.6) / 0.4, 0.0, 1.0)
		var critical_color := Color(0.95, 0.2, 0.1)
		color = color.lerp(critical_color, t)

	var mat: StandardMaterial3D = null
	if get_surface_override_material_count() > 0:
		mat = get_surface_override_material(0) as StandardMaterial3D
	if mat:
		mat.albedo_color = color
		# 偏离时增加emission让键"发光发热"
		if _stress_deviation > 0.3:
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = clampf(_stress_deviation - 0.3, 0.0, 0.8)
		else:
			mat.emission_enabled = false

	if _second_cylinder:
		var mat2: StandardMaterial3D = null
		if _second_cylinder.get_surface_override_material_count() > 0:
			mat2 = _second_cylinder.get_surface_override_material(0) as StandardMaterial3D
		if mat2:
			mat2.albedo_color = color
			if _stress_deviation > 0.3:
				mat2.emission_enabled = true
				mat2.emission = color
				mat2.emission_energy_multiplier = clampf(_stress_deviation - 0.3, 0.0, 0.8)
			else:
				mat2.emission_enabled = false


func set_atoms(a: Node3D, b: Node3D, type: BondType = BondType.SINGLE) -> void:
	atom_a = a
	atom_b = b
	bond_type = type
	_update_color()


func _process(delta: float) -> void:
	if atom_a == null or atom_b == null:
		if not _is_broken:
			_break_progress += delta * 2.0
			if _break_progress > 1.0:
				queue_free()
		else:
			queue_free()
		return

	if _is_broken:
		_animate_break(delta)
		return

	# 守恒应力振动
	_stress_time += delta
	if _stress_deviation > 0.15:
		# 振动幅度随偏离增大，频率也加快
		var amplitude := _stress_deviation * 0.04
		var freq := 8.0 + _stress_deviation * 20.0
		# 减少闪烁模式下降低振动
		if UiAnimator != null and UiAnimator.is_flashing_reduced():
			amplitude *= 0.3
			freq = minf(freq, 5.0)
		_stress_vibration_offset = Vector3(
			sin(_stress_time * freq) * amplitude,
			cos(_stress_time * freq * 1.3) * amplitude,
			sin(_stress_time * freq * 0.7 + 1.5) * amplitude
		)
	else:
		_stress_vibration_offset = Vector3.ZERO

	# 只在原子位置变化时更新变换（降频到每3帧一次）
	if Engine.get_process_frames() % 3 != 0:
		return
	_update_transform()


func _update_transform() -> void:
	var pos_a := atom_a.global_position
	var pos_b := atom_b.global_position
	var mid := (pos_a + pos_b) * 0.5
	var diff := pos_b - pos_a
	var length := diff.length()

	if length < 0.001:
		visible = false
		return

	visible = true

	# 应力拉伸：偏离时键略微伸长，模拟原子间距离被守恒偏离"撑开"
	var stress_stretch := 1.0 + _stress_deviation * 0.08
	var stretched_length := length * stress_stretch

	# 放到中点 + 振动偏移
	global_position = mid + _stress_vibration_offset

	# 朝向: CylinderMesh默认沿Y轴，需要旋转到对齐a->b方向
	var up := Vector3.UP
	var dir := diff.normalized()
	if absf(dir.dot(up)) > 0.999:
		up = Vector3.RIGHT
	var basis := Basis.looking_at(dir, up)
	global_basis = basis

	# 通过scale.y调整键长，避免每帧重建mesh
	scale = Vector3(1.0, stretched_length, 1.0)

	# 双键第二条线偏移
	if _second_cylinder:
		_second_cylinder.global_basis = basis
		_second_cylinder.scale = Vector3(1.0, stretched_length, 1.0)
		# 垂直于键方向的偏移
		var perp := dir.cross(up).normalized() * _bond_radius * 2.5
		_second_cylinder.global_position = mid + perp + _stress_vibration_offset


func break_bond() -> void:
	if _is_broken:
		return
	_is_broken = true
	_break_progress = 0.0
	bond_broken.emit(self)


func _animate_break(delta: float) -> void:
	_break_progress += delta / 1.0  # 1秒断开动画

	# 拉伸 + 淡出
	var stretch := 1.0 + _break_progress * 2.0
	var alpha := 1.0 - _break_progress

	var mat := get_surface_override_material(0) as StandardMaterial3D
	if mat:
		mat.albedo_color.a = maxf(alpha, 0.0)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	scale = Vector3(1.0 / stretch, stretch, 1.0 / stretch)

	if _second_cylinder:
		var mat2 := _second_cylinder.get_surface_override_material(0) as StandardMaterial3D
		if mat2:
			mat2.albedo_color.a = maxf(alpha, 0.0)
			mat2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	if _break_progress >= 1.0:
		queue_free()


func get_bond_length() -> float:
	if atom_a and atom_b:
		return atom_a.global_position.distance_to(atom_b.global_position)
	return 0.0


func update_stress(deviation: float) -> void:
	# 由 EffectManager 调用，更新键的守恒应力状态
	_stress_deviation = deviation
	_apply_stress_color()
