# conservation_engine_test.gd
# gdUnit4 单元测试：守恒矩阵引擎

extends GdUnitTestSuite


const __source = "res://scripts/autoload/07_conservation_engine.gd"

var _engine: Node = null


func before() -> void:
	_engine = Engine.get_singleton("ConservationEngine") if Engine.has_singleton("ConservationEngine") else null
	if _engine == null:
		_engine = Engine.get_main_loop().root.get_node_or_null("/root/ConservationEngine")


func test_engine_autoload_exists() -> void:
	assert_object(_engine).is_not_null()


func test_get_deviation_summary_returns_dict() -> void:
	if _engine == null:
		return

	var summary: Dictionary = _engine.get_deviation_summary()
	assert_dict(summary).is_not_null()
	assert_int(summary.size()).is_equal(4)
	for key in ["mass", "charge", "momentum", "energy"]:
		assert_bool(summary.has(key)).is_true()


func test_matrix_set_and_read() -> void:
	if _engine == null:
		return

	_engine.reset()

	for i in range(4):
		assert_float(_engine.get_entry(i, i)).is_equal_approx(1.0, 0.001)

	for i in range(4):
		for j in range(4):
			if i != j:
				assert_float(_engine.get_entry(i, j)).is_equal_approx(0.0, 0.001)

	_engine.set_entry(0, 1, 0.5)
	assert_float(_engine.get_entry(0, 1)).is_equal_approx(0.5, 0.001)

	_engine.reset()


func test_diagonal_near_1_gives_healthy() -> void:
	if _engine == null:
		return

	_engine.reset()
	var state: int = _engine.get_state()
	assert_int(state).is_equal(0)


func test_large_off_diagonal_gives_warning_or_worse() -> void:
	if _engine == null:
		return

	# Rust 后端按特征值接近 0/负数划分状态；GDScript 回退按偏离 1.0 划分。
	# 单次对称扰动 v 会产生特征值 1±v，选取能同时触发两种后端阈值的值。
	_engine.reset()
	_engine.apply_perturbation(0, 1, 1.0, "test_warning_perturb")
	var state_after: int = _engine.get_state()
	assert_int(state_after).is_greater_equal(1)

	_engine.reset()
	_engine.apply_perturbation(0, 1, 1.05, "test_critical_perturb")
	var state_big: int = _engine.get_state()
	assert_int(state_big).is_greater_equal(2)

	_engine.reset()
