# strain_field_test.gd
# 应变张量场系统单元测试

extends GdUnitTestSuite


var _strain_field: RefCounted = null
var _mock_canvas: Node3D = null


func before_test() -> void:
	_mock_canvas = Node3D.new()
	_mock_canvas.name = "StrainTestCanvas"
	Engine.get_main_loop().root.add_child(_mock_canvas)
	var script = load("res://scripts/gameplay/strain_field_system.gd")
	_strain_field = script.new(_mock_canvas, null, null)
	await Engine.get_main_loop().process_frame


func after_test() -> void:
	if _strain_field != null:
		_strain_field.on_level_reset()
		_strain_field = null
	if _mock_canvas != null and is_instance_valid(_mock_canvas):
		_mock_canvas.queue_free()
		await Engine.get_main_loop().process_frame


# 测试1: 空系统应返回零应变
func test_empty_system_zero_strain() -> void:
	var mag: float = _strain_field.get_strain_magnitude(Vector3(0, 0, 0))
	assert_float(mag).is_equal_approx(0.0, 0.001)
	
	var vol: float = _strain_field.get_volumetric_strain(Vector3(1, 1, 1))
	assert_float(vol).is_equal_approx(0.0, 0.001)


# 测试2: 单个原子产生非零应变场
func test_single_atom_produces_strain() -> void:
	var atom: MeshInstance3D = MeshInstance3D.new()
	atom.set("element_symbol", "Fe")
	atom.position = Vector3(0, 0, 0)
	_mock_canvas.add_child(atom)
	
	_strain_field.on_atom_placed(atom)
	
	# 在原子附近应有显著应变
	var mag_near: float = _strain_field.get_strain_magnitude(Vector3(0.5, 0, 0))
	assert_bool(mag_near > 0.0).is_true()
	
	# 远离原子的位置应变应较小
	var mag_far: float = _strain_field.get_strain_magnitude(Vector3(10, 10, 10))
	assert_bool(mag_far < mag_near).is_true()
	
	atom.queue_free()
	await Engine.get_main_loop().process_frame


# 测试3: 应变张量是对称的
func test_strain_tensor_symmetry() -> void:
	var atom: MeshInstance3D = MeshInstance3D.new()
	atom.set("element_symbol", "Cu")
	atom.position = Vector3(0, 0, 0)
	_mock_canvas.add_child(atom)
	
	_strain_field.on_atom_placed(atom)
	
	var tensor: Array = _strain_field.compute_strain_tensor(Vector3(0.5, 0.3, 0.2))
	
	# ε_xy == ε_yx, ε_xz == ε_zx, ε_yz == ε_zy
	assert_float(tensor[1]).is_equal_approx(tensor[3], 0.0001)
	assert_float(tensor[2]).is_equal_approx(tensor[6], 0.0001)
	assert_float(tensor[5]).is_equal_approx(tensor[7], 0.0001)
	
	atom.queue_free()
	await Engine.get_main_loop().process_frame


# 测试4: 多个原子应变叠加
func test_strain_superposition() -> void:
	var atom1: MeshInstance3D = MeshInstance3D.new()
	atom1.set("element_symbol", "Fe")
	atom1.position = Vector3(-1, 0, 0)
	_mock_canvas.add_child(atom1)
	
	_strain_field.on_atom_placed(atom1)
	var strain_one: float = _strain_field.get_strain_magnitude(Vector3(0, 0, 0))
	
	var atom2: MeshInstance3D = MeshInstance3D.new()
	atom2.set("element_symbol", "Fe")
	atom2.position = Vector3(1, 0, 0)
	_mock_canvas.add_child(atom2)
	
	_strain_field.on_atom_placed(atom2)
	var strain_two: float = _strain_field.get_strain_magnitude(Vector3(0, 0, 0))
	
	# 两个原子的叠加应变应大于单个原子
	assert_bool(strain_two > strain_one).is_true()
	
	atom1.queue_free()
	atom2.queue_free()
	await Engine.get_main_loop().process_frame


# 测试5: 原子移除后应变消失
func test_strain_removed_with_atom() -> void:
	var atom: MeshInstance3D = MeshInstance3D.new()
	atom.set("element_symbol", "Na")
	atom.position = Vector3(0, 0, 0)
	_mock_canvas.add_child(atom)
	
	_strain_field.on_atom_placed(atom)
	var strain_before: float = _strain_field.get_strain_magnitude(Vector3(0.5, 0, 0))
	assert_bool(strain_before > 0.0).is_true()
	
	_strain_field.on_atom_removed(atom)
	atom.queue_free()
	await Engine.get_main_loop().process_frame
	
	var strain_after: float = _strain_field.get_strain_magnitude(Vector3(0.5, 0, 0))
	assert_float(strain_after).is_equal_approx(0.0, 0.001)


# 测试6: 应变信息摘要正确
func test_strain_info() -> void:
	var atom: MeshInstance3D = MeshInstance3D.new()
	atom.set("element_symbol", "Fe")
	atom.position = Vector3(0, 0, 0)
	_mock_canvas.add_child(atom)
	
	_strain_field.on_atom_placed(atom)
	
	var info: Dictionary = _strain_field.get_strain_info()
	assert_bool(info.has("avg_strain")).is_true()
	assert_bool(info.has("max_strain")).is_true()
	assert_bool(info.has("total_atoms")).is_true()
	assert_int(info["total_atoms"]).is_equal(1)
	
	atom.queue_free()
	await Engine.get_main_loop().process_frame


# 测试7: 偏应变非负
func test_deviatoric_strain_nonnegative() -> void:
	var atom: MeshInstance3D = MeshInstance3D.new()
	atom.set("element_symbol", "Fe")
	atom.position = Vector3(0, 0, 0)
	_mock_canvas.add_child(atom)
	
	_strain_field.on_atom_placed(atom)
	
	# 偏应变（形状变化部分）应该 >= 0
	var dev: float = _strain_field.get_deviatoric_strain(Vector3(0.3, 0.4, 0.5))
	assert_bool(dev >= 0.0).is_true()
	
	atom.queue_free()
	await Engine.get_main_loop().process_frame


# 测试8: 关卡重置后应变场清空
func test_level_reset_clears_strain() -> void:
	var atom: MeshInstance3D = MeshInstance3D.new()
	atom.set("element_symbol", "Fe")
	atom.position = Vector3(0, 0, 0)
	_mock_canvas.add_child(atom)
	
	_strain_field.on_atom_placed(atom)
	assert_bool(_strain_field.get_strain_magnitude(Vector3(0.5, 0, 0)) > 0.0).is_true()
	
	_strain_field.on_level_reset()
	
	var mag: float = _strain_field.get_strain_magnitude(Vector3(0.5, 0, 0))
	assert_float(mag).is_equal_approx(0.0, 0.001)
	
	atom.queue_free()
	await Engine.get_main_loop().process_frame
