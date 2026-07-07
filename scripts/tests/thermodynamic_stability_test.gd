# thermodynamic_stability_test.gd
# 热力学稳定性引擎单元测试

extends GdUnitTestSuite


var _thermo_sys: RefCounted = null
var _mock_canvas: Node3D = null


func before_test() -> void:
	_mock_canvas = Node3D.new()
	_mock_canvas.name = "ThermoTestCanvas"
	Engine.get_main_loop().root.add_child(_mock_canvas)
	var script = load("res://scripts/gameplay/thermodynamic_stability.gd")
	_thermo_sys = script.new(_mock_canvas, null, null)
	await Engine.get_main_loop().process_frame


func after_test() -> void:
	if _thermo_sys != null:
		_thermo_sys.on_level_reset()
		_thermo_sys = null
	if _mock_canvas != null and is_instance_valid(_mock_canvas):
		_mock_canvas.queue_free()
		await Engine.get_main_loop().process_frame


# 测试1: 初始状态应为稳定
func test_initial_stability() -> void:
	var label: String = _thermo_sys.get_stability_label()
	assert_str(label).is_equal("稳定")


# 测试2: 零原子零键时Gibbs自由能为0
func test_empty_system_zero_gibbs() -> void:
	_thermo_sys.recalculate(0, 0, 0, {})
	var g: float = _thermo_sys.get_gibbs_energy()
	assert_float(g).is_equal_approx(0.0, 0.001)


# 测试3: 有键时焓为负（稳定）
func test_bond_lowers_enthalpy() -> void:
	_thermo_sys.recalculate(2, 1, 0, {})
	var h: float = _thermo_sys.get_enthalpy()
	assert_bool(h < 0.0).is_true()


# 测试4: 缺陷提高焓（不稳定）
func test_defect_raises_enthalpy() -> void:
	_thermo_sys.recalculate(2, 0, 0, {})
	var h_clean: float = _thermo_sys.get_enthalpy()
	
	_thermo_sys.on_level_reset()
	_thermo_sys.recalculate(2, 0, 1, {})
	var h_defect: float = _thermo_sys.get_enthalpy()
	
	assert_bool(h_defect > h_clean).is_true()


# 测试5: 应变提高焓
func test_strain_raises_enthalpy() -> void:
	_thermo_sys.recalculate(2, 0, 0, {})
	var h_no_strain: float = _thermo_sys.get_enthalpy()
	
	_thermo_sys.on_level_reset()
	_thermo_sys.recalculate(2, 0, 0, {"avg_strain": 0.5})
	var h_strain: float = _thermo_sys.get_enthalpy()
	
	assert_bool(h_strain > h_no_strain).is_true()


# 测试6: 高温下Gibbs自由能更低（熵贡献 -TS 更显著）
func test_high_temp_lowers_gibbs() -> void:
	# G = H - T*S, S > 0 时高温使 G 更小
	_thermo_sys.on_temperature_changed(100.0)
	_thermo_sys.recalculate(4, 4, 0, {})
	var g_cold: float = _thermo_sys.get_gibbs_energy()
	
	_thermo_sys.on_level_reset()
	_thermo_sys.on_temperature_changed(5000.0)
	_thermo_sys.recalculate(4, 4, 0, {})
	var g_hot: float = _thermo_sys.get_gibbs_energy()
	
	# 高温下 -TS 项更大，G 应更低
	assert_bool(g_hot < g_cold).is_true()


# 测试7: 验证折扣范围合理
func test_verification_discount_range() -> void:
	# 基态折扣最大
	_thermo_sys.recalculate(10, 10, 0, {})
	var discount: float = _thermo_sys.get_verification_discount()
	assert_bool(discount >= 0.5 and discount <= 1.5).is_true()


# 测试8: 核心倍率范围合理
func test_core_multiplier_range() -> void:
	_thermo_sys.recalculate(10, 10, 0, {})
	var mult: float = _thermo_sys.get_core_multiplier()
	assert_bool(mult >= 0.7 and mult <= 1.5).is_true()


# 测试9: 瓦解阈值修正范围合理
func test_disintegration_threshold_range() -> void:
	_thermo_sys.recalculate(10, 10, 0, {})
	var mod: float = _thermo_sys.get_disintegration_threshold_modifier()
	assert_bool(mod >= -0.2 and mod <= 0.3).is_true()


# 测试10: 关卡重置恢复初始状态
func test_level_reset() -> void:
	_thermo_sys.recalculate(5, 3, 2, {"avg_strain": 0.8})
	_thermo_sys.on_level_reset()
	
	assert_float(_thermo_sys.get_gibbs_energy()).is_equal_approx(0.0, 0.001)
	assert_float(_thermo_sys.get_enthalpy()).is_equal_approx(0.0, 0.001)
	assert_str(_thermo_sys.get_stability_label()).is_equal("稳定")


# 测试11: info字典包含所有必需字段
func test_info_contains_all_fields() -> void:
	_thermo_sys.recalculate(4, 2, 1, {"avg_strain": 0.3})
	var info: Dictionary = _thermo_sys.get_info()
	
	assert_bool(info.has("stability")).is_true()
	assert_bool(info.has("gibbs")).is_true()
	assert_bool(info.has("enthalpy")).is_true()
	assert_bool(info.has("entropy")).is_true()
	assert_bool(info.has("temperature")).is_true()
	assert_bool(info.has("verification_discount")).is_true()
	assert_bool(info.has("core_multiplier")).is_true()
	assert_bool(info.has("disintegration_modifier")).is_true()
