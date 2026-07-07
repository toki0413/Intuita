# quantum_tunneling_test.gd
# 量子隧穿系统单元测试
# 覆盖 WKB 概率计算、放置风险预测以及关卡重置等核心逻辑

extends GdUnitTestSuite


var _QuantumTunnelingScript = null
var _sys: RefCounted = null
var _mock_canvas: Node3D = null


# 只实现 get_atoms 的简易原子管理器 mock, predict 系列要用到
class _MockAtomMgr:
	extends RefCounted
	var _atoms: Array = []
	func set_atoms(atoms: Array) -> void:
		_atoms = atoms
	func get_atoms() -> Array:
		return _atoms


func before_test() -> void:
	_mock_canvas = Node3D.new()
	_mock_canvas.name = "QuantumTunnelingTestCanvas"
	Engine.get_main_loop().root.add_child(_mock_canvas)
	_QuantumTunnelingScript = load("res://scripts/gameplay/quantum_tunneling_system.gd")
	# atom_mgr / float_text 默认传 null, 系统内部都有空值保护
	_sys = _QuantumTunnelingScript.new(_mock_canvas, null, null)
	await Engine.get_main_loop().process_frame


func after_test() -> void:
	if _sys != null:
		_sys.on_level_reset()
		_sys = null
	if _mock_canvas != null and is_instance_valid(_mock_canvas):
		_mock_canvas.queue_free()
		await Engine.get_main_loop().process_frame


# 造一个测试用原子, 默认氢
func _make_atom(pos: Vector3, element: String = "H") -> MeshInstance3D:
	var atom: MeshInstance3D = MeshInstance3D.new()
	atom.set("element_symbol", element)
	atom.position = pos
	_mock_canvas.add_child(atom)
	return atom


# 用指定 atom_mgr 另起一个系统实例 (predict 系列需要真实的原子列表)
func _new_system(atom_mgr) -> RefCounted:
	return _QuantumTunnelingScript.new(_mock_canvas, atom_mgr, null)


# 测试1: 全新系统不应有任何隧穿记录
func test_empty_history() -> void:
	assert_int(_sys.get_tunneling_count()).is_equal(0)


# 测试2: 距离超过阈值(1.2)时隧穿概率必须为 0
func test_tunneling_probability_zero_far() -> void:
	var a := _make_atom(Vector3(0, 0, 0))
	var b := _make_atom(Vector3(3.0, 0, 0))  # 远超阈值
	var p: float = _sys.compute_tunneling_probability(a, b)
	assert_float(p).is_equal(0.0)


# 测试3: 原子靠得很近时应当有非零的隧穿概率
func test_tunneling_probability_positive_close() -> void:
	var a := _make_atom(Vector3(0, 0, 0))
	var b := _make_atom(Vector3(0.3, 0, 0))  # 0.3, 很近
	var p: float = _sys.compute_tunneling_probability(a, b)
	assert_float(p).is_greater(0.0)


# 测试4: 距离越近, 隧穿概率越高
func test_tunneling_probability_increases_closer() -> void:
	var anchor := _make_atom(Vector3(0, 0, 0))
	var far_atom := _make_atom(Vector3(1.1, 0, 0))   # 较远但仍小于阈值
	var near_atom := _make_atom(Vector3(0.2, 0, 0))  # 非常近
	var p_far: float = _sys.compute_tunneling_probability(anchor, far_atom)
	var p_near: float = _sys.compute_tunneling_probability(anchor, near_atom)
	assert_float(p_near).is_greater(p_far)


# 测试5: 预测点远离所有原子时风险等级为 none
func test_predict_tunneling_none() -> void:
	var mgr := _MockAtomMgr.new()
	mgr.set_atoms([_make_atom(Vector3(0, 0, 0))])
	var sys: RefCounted = _new_system(mgr)
	var result: Dictionary = sys.predict_tunneling_at(Vector3(5.0, 0, 0), "H")
	assert_str(result["risk"]).is_equal("none")


# 测试6: 预测点紧贴已有原子时风险至少为 medium
func test_predict_tunneling_high() -> void:
	var mgr := _MockAtomMgr.new()
	mgr.set_atoms([_make_atom(Vector3(0, 0, 0))])
	var sys: RefCounted = _new_system(mgr)
	# 距离 0.1, 概率会被推到 high 区间
	var result: Dictionary = sys.predict_tunneling_at(Vector3(0.1, 0, 0), "H")
	var risk: String = result["risk"]
	assert_bool(risk == "high" or risk == "medium").is_true()


# 测试7: 关卡重置后历史记录清空
func test_level_reset() -> void:
	# 真实触发隧穿依赖 GameState 和 RNG, 这里直接往历史里塞记录来隔离测 reset
	var history: Array = _sys.get("_tunneling_history")
	history.append({"formula": "H•H", "probability": 0.5, "bonus": 8})
	history.append({"formula": "He@C60", "probability": 0.3, "bonus": 15})
	assert_int(_sys.get_tunneling_count()).is_equal(2)
	_sys.on_level_reset()
	assert_int(_sys.get_tunneling_count()).is_equal(0)


# 测试8: 放置时附近没有邻居则不触发隧穿
func test_check_no_neighbors() -> void:
	var atom := _make_atom(Vector3(0, 0, 0))
	var result: Dictionary = _sys.check_tunneling_on_placement(atom, [])
	assert_bool(result["triggered"]).is_false()
