# resonance_cascade_test.gd
# 共振级联系统单元测试

extends GdUnitTestSuite


var _cascade_sys: RefCounted = null
var _mock_canvas: Node3D = null


func before_test() -> void:
	_mock_canvas = Node3D.new()
	_mock_canvas.name = "ResonanceTestCanvas"
	Engine.get_main_loop().root.add_child(_mock_canvas)
	var script = load("res://scripts/gameplay/resonance_cascade_system.gd")
	# atom_mgr / float_text 传 null, 系统内部都有空值保护
	_cascade_sys = script.new(_mock_canvas, null, null)
	await Engine.get_main_loop().process_frame


func after_test() -> void:
	if _cascade_sys != null:
		_cascade_sys.on_level_reset()
		_cascade_sys = null
	if _mock_canvas != null and is_instance_valid(_mock_canvas):
		_mock_canvas.queue_free()
		await Engine.get_main_loop().process_frame


# 测试1: 初始频率应为正值
func test_default_frequency() -> void:
	var freq: float = _cascade_sys.get_current_frequency()
	assert_bool(freq > 0.0).is_true()


# 测试2: tune_frequency 返回带 resonance 字段的字典
func test_tune_frequency() -> void:
	# 5e12 是默认频率, 远离所有默认模, 不会触发共振副作用
	var result: Dictionary = _cascade_sys.tune_frequency(5e12)
	assert_bool(result is Dictionary).is_true()
	assert_bool(result.has("resonance")).is_true()


# 测试3: tune_by_delta 改变频率并返回字典
func test_tune_by_delta() -> void:
	var freq_before: float = _cascade_sys.get_current_frequency()
	var result: Dictionary = _cascade_sys.tune_by_delta(0.5)
	var freq_after: float = _cascade_sys.get_current_frequency()
	assert_bool(result is Dictionary).is_true()
	assert_bool(freq_after != freq_before).is_true()


# 测试4: 默认共振模列表非空 (无声子系统时也有默认模)
func test_get_resonance_modes() -> void:
	var modes: Array = _cascade_sys.get_resonance_modes()
	assert_bool(modes.size() > 0).is_true()


# 测试5: 级联信息字典包含关键字段
func test_cascade_info() -> void:
	var info: Dictionary = _cascade_sys.get_cascade_info()
	assert_bool(info.has("cascade_count")).is_true()
	assert_bool(info.has("current_frequency")).is_true()


# 测试6: 频率匹配模时预测会共振 (默认 LA声学模 = 3e12)
func test_predict_resonance() -> void:
	var result: Dictionary = _cascade_sys.predict_resonance(3e12)
	assert_bool(result.has("will_resonate")).is_true()
	assert_bool(result["will_resonate"]).is_true()


# 测试7: 频率远离所有模时预测不共振 (1e13 偏离全部默认模)
func test_predict_no_resonance() -> void:
	var result: Dictionary = _cascade_sys.predict_resonance(1e13)
	assert_bool(result.has("will_resonate")).is_true()
	assert_bool(result["will_resonate"]).is_false()


# 测试8: 关卡重置后级联计数归零、频率恢复默认
func test_level_reset() -> void:
	# 先调到共振频率让 cascade_count 递增
	_cascade_sys.tune_frequency(3e12)
	_cascade_sys.on_level_reset()
	var info: Dictionary = _cascade_sys.get_cascade_info()
	assert_int(info["cascade_count"]).is_equal(0)
	assert_float(_cascade_sys.get_current_frequency()).is_equal_approx(5e12, 1e11)
