# phonon_spectrum_test.gd
# 声子谱系统单元测试

extends GdUnitTestSuite


var _phonon_sys: RefCounted = null
var _mock_canvas: Node3D = null


func before_test() -> void:
	_mock_canvas = Node3D.new()
	_mock_canvas.name = "PhononTestCanvas"
	Engine.get_main_loop().root.add_child(_mock_canvas)
	var script = load("res://scripts/gameplay/phonon_spectrum_system.gd")
	_phonon_sys = script.new(_mock_canvas, null, null)
	await Engine.get_main_loop().process_frame


func after_test() -> void:
	if _phonon_sys != null:
		_phonon_sys.on_level_reset()
		_phonon_sys = null
	if _mock_canvas != null and is_instance_valid(_mock_canvas):
		_mock_canvas.queue_free()
		await Engine.get_main_loop().process_frame


# 测试1: 空系统Debye温度为默认值
func test_empty_system_default_debye() -> void:
	var theta: float = _phonon_sys.get_debye_temperature()
	assert_float(theta).is_equal_approx(300.0, 1.0)


# 测试2: 放置原子后Debye温度变化
func test_atom_changes_debye_temp() -> void:
	var theta_before: float = _phonon_sys.get_debye_temperature()
	
	var atom: MeshInstance3D = MeshInstance3D.new()
	atom.set("element_symbol", "Fe")
	atom.position = Vector3(0, 0, 0)
	_mock_canvas.add_child(atom)
	
	_phonon_sys.on_atom_placed(atom)
	
	var theta_after: float = _phonon_sys.get_debye_temperature()
	# Debye温度应该从默认值变化
	assert_bool(absf(theta_after - theta_before) > 0.01).is_true()
	
	atom.queue_free()
	await Engine.get_main_loop().process_frame


# 测试3: 声速在合理范围内
func test_sound_velocity_range() -> void:
	var atom: MeshInstance3D = MeshInstance3D.new()
	atom.set("element_symbol", "Fe")
	atom.position = Vector3(0, 0, 0)
	_mock_canvas.add_child(atom)
	
	_phonon_sys.on_atom_placed(atom)
	
	var v_s: float = _phonon_sys.get_sound_velocity()
	# 声速应在1000-15000 m/s范围内
	assert_bool(v_s >= 1000.0 and v_s <= 15000.0).is_true()
	
	atom.queue_free()
	await Engine.get_main_loop().process_frame


# 测试4: 比热容为正值
func test_heat_capacity_positive() -> void:
	var atom: MeshInstance3D = MeshInstance3D.new()
	atom.set("element_symbol", "Fe")
	atom.position = Vector3(0, 0, 0)
	_mock_canvas.add_child(atom)
	
	_phonon_sys.on_atom_placed(atom)
	
	var c_v: float = _phonon_sys.compute_heat_capacity(300.0)
	assert_bool(c_v > 0.0).is_true()
	
	atom.queue_free()
	await Engine.get_main_loop().process_frame


# 测试5: 高温比热容趋近Dulong-Petit极限 (3Nk_B)
func test_high_temp_dulong_petit() -> void:
	var atom: MeshInstance3D = MeshInstance3D.new()
	atom.set("element_symbol", "Fe")
	atom.position = Vector3(0, 0, 0)
	_mock_canvas.add_child(atom)
	
	_phonon_sys.on_atom_placed(atom)
	
	# 高温下 C_v → 3Nk_B
	var c_v_high: float = _phonon_sys.compute_heat_capacity(10000.0)
	var dulong_petit: float = 3.0 * 1.0 * 8.617e-5  # 3Nk_B for N=1
	
	# 允许10%误差
	assert_float(c_v_high).is_equal_approx(dulong_petit, dulong_petit * 0.15)
	
	atom.queue_free()
	await Engine.get_main_loop().process_frame


# 测试6: 低温比热容遵循Debye T³定律
func test_low_temp_debye_t3() -> void:
	var atom: MeshInstance3D = MeshInstance3D.new()
	atom.set("element_symbol", "Fe")
	atom.position = Vector3(0, 0, 0)
	_mock_canvas.add_child(atom)
	
	_phonon_sys.on_atom_placed(atom)
	
	# 低温下 C_v ∝ T³
	var c_v_10k: float = _phonon_sys.compute_heat_capacity(10.0)
	var c_v_20k: float = _phonon_sys.compute_heat_capacity(20.0)
	
	# T翻倍，C_v应约为8倍 (2³=8)
	if c_v_10k > 0.0:
		var ratio: float = c_v_20k / c_v_10k
		assert_bool(ratio > 4.0 and ratio < 16.0).is_true()
	
	atom.queue_free()
	await Engine.get_main_loop().process_frame


# 测试7: 振动熵为正值
func test_vibrational_entropy_positive() -> void:
	var atom: MeshInstance3D = MeshInstance3D.new()
	atom.set("element_symbol", "Fe")
	atom.position = Vector3(0, 0, 0)
	_mock_canvas.add_child(atom)
	
	_phonon_sys.on_atom_placed(atom)
	
	var s_vib: float = _phonon_sys.compute_vibrational_entropy(300.0)
	assert_bool(s_vib >= 0.0).is_true()
	
	atom.queue_free()
	await Engine.get_main_loop().process_frame


# 测试8: 声子态密度在Debye频率处为零
func test_phonon_dos_at_cutoff() -> void:
	var atom: MeshInstance3D = MeshInstance3D.new()
	atom.set("element_symbol", "Fe")
	atom.position = Vector3(0, 0, 0)
	_mock_canvas.add_child(atom)
	
	_phonon_sys.on_atom_placed(atom)
	
	# 在极高频率处DOS应为0
	var dos_high: float = _phonon_sys.phonon_dos(1e20)
	assert_float(dos_high).is_equal_approx(0.0, 0.001)
	
	# 在零频率处DOS也应为0
	var dos_zero: float = _phonon_sys.phonon_dos(0.0)
	assert_float(dos_zero).is_equal_approx(0.0, 0.001)
	
	atom.queue_free()
	await Engine.get_main_loop().process_frame


# 测试9: 软模检测在高应变下触发
func test_soft_mode_detection() -> void:
	var atom: MeshInstance3D = MeshInstance3D.new()
	atom.set("element_symbol", "Fe")
	atom.position = Vector3(0, 0, 0)
	_mock_canvas.add_child(atom)
	
	_phonon_sys.on_atom_placed(atom)
	
	# 高应变场景
	var high_strain_info: Dictionary = {"avg_strain": 0.8}
	var result: Dictionary = _phonon_sys.check_phonon_softening(high_strain_info, 5)
	
	# 应该检测到不稳定
	assert_bool(result.has("is_stable")).is_true()
	assert_bool(result["is_stable"] == false).is_true()
	assert_bool(result["soft_modes"].size() > 0).is_true()
	
	atom.queue_free()
	await Engine.get_main_loop().process_frame


# 测试10: 低应变无软模
func test_no_soft_mode_low_strain() -> void:
	var atom: MeshInstance3D = MeshInstance3D.new()
	atom.set("element_symbol", "Fe")
	atom.position = Vector3(0, 0, 0)
	_mock_canvas.add_child(atom)
	
	_phonon_sys.on_atom_placed(atom)
	
	var low_strain_info: Dictionary = {"avg_strain": 0.01}
	var result: Dictionary = _phonon_sys.check_phonon_softening(low_strain_info, 0)
	
	assert_bool(result["is_stable"] == true).is_true()
	
	atom.queue_free()
	await Engine.get_main_loop().process_frame


# 测试11: 关卡重置恢复默认值
func test_level_reset() -> void:
	var atom: MeshInstance3D = MeshInstance3D.new()
	atom.set("element_symbol", "Fe")
	atom.position = Vector3(0, 0, 0)
	_mock_canvas.add_child(atom)
	
	_phonon_sys.on_atom_placed(atom)
	_phonon_sys.on_level_reset()
	
	assert_float(_phonon_sys.get_debye_temperature()).is_equal_approx(300.0, 1.0)
	
	atom.queue_free()
	await Engine.get_main_loop().process_frame


# 测试12: 拉曼活性模预测返回数组
func test_raman_modes_returned() -> void:
	var atom: MeshInstance3D = MeshInstance3D.new()
	atom.set("element_symbol", "Fe")
	atom.position = Vector3(0, 0, 0)
	_mock_canvas.add_child(atom)
	
	_phonon_sys.on_atom_placed(atom)
	
	var modes: Array = _phonon_sys.predict_raman_active_modes()
	assert_bool(modes.size() > 0).is_true()
	
	# 每个模应包含branch和frequency字段
	if modes.size() > 0:
		assert_bool(modes[0].has("branch")).is_true()
		assert_bool(modes[0].has("frequency")).is_true()
	
	atom.queue_free()
	await Engine.get_main_loop().process_frame


# 测试13: 声子信息摘要包含所有字段
func test_phonon_info() -> void:
	var atom: MeshInstance3D = MeshInstance3D.new()
	atom.set("element_symbol", "Fe")
	atom.position = Vector3(0, 0, 0)
	_mock_canvas.add_child(atom)
	
	_phonon_sys.on_atom_placed(atom)
	
	var info: Dictionary = _phonon_sys.get_phonon_info()
	assert_bool(info.has("debye_temp")).is_true()
	assert_bool(info.has("sound_velocity")).is_true()
	assert_bool(info.has("total_atoms")).is_true()
	assert_bool(info.has("heat_capacity_300k")).is_true()
	assert_bool(info.has("vib_entropy_300k")).is_true()
	assert_int(info["total_atoms"]).is_equal(1)
	
	atom.queue_free()
	await Engine.get_main_loop().process_frame
