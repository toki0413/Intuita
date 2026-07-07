# catalyst_network_test.gd
# 催化剂网络系统的单元测试
# 主要覆盖催化剂注册、Arrhenius反应速率、反应评估、网络信息以及关卡重置

extends GdUnitTestSuite

# 原子节点用一个内嵌类包一层，主要是为了挂上 element_symbol 属性
# 裸 MeshInstance3D 没法存自定义属性，get("element_symbol") 会拿不到
class _MockAtom extends MeshInstance3D:
	var element_symbol: String


var _CatalystNetwork = load("res://scripts/gameplay/catalyst_network_system.gd")
var _mock_canvas: Node3D = null
var _system: RefCounted = null


func before_test() -> void:
	_mock_canvas = Node3D.new()
	_mock_canvas.name = "CatalystTestCanvas"
	Engine.get_main_loop().root.add_child(_mock_canvas)
	# atom_mgr 和 float_text 这里都用不到，直接传 null
	_system = _CatalystNetwork.new(_mock_canvas, null, null)
	await Engine.get_main_loop().process_frame


func after_test() -> void:
	if _system != null:
		_system.on_level_reset()
		_system = null
	if _mock_canvas != null and is_instance_valid(_mock_canvas):
		_mock_canvas.queue_free()
		await Engine.get_main_loop().process_frame


# 搭一个模拟原子：给元素符号、给坐标，挂到画布上
func _make_atom(element: String, pos: Vector3) -> MeshInstance3D:
	var atom: MeshInstance3D = _MockAtom.new()
	atom.set("element_symbol", element)
	atom.position = pos
	_mock_canvas.add_child(atom)
	return atom


# 测试1: 刚建好的系统里不应该有任何催化剂
func test_empty_system() -> void:
	assert_int(_system.get_catalyst_count()).is_equal(0)


# 测试2: 放一个Pt原子并注册，催化剂数量应变成1
func test_register_catalyst() -> void:
	var atom := _make_atom("Pt", Vector3.ZERO)
	var result: Dictionary = _system.register_catalyst(atom)
	assert_bool(result["success"]).is_true()
	assert_int(_system.get_catalyst_count()).is_equal(1)


# 测试3: 非催化剂元素要被拒绝
# 注意 Fe 本身在 CATALYST_TYPES 里，所以这里故意用 H
func test_non_catalyst_rejected() -> void:
	var atom := _make_atom("H", Vector3.ZERO)
	var result: Dictionary = _system.register_catalyst(atom)
	assert_bool(result["success"]).is_false()
	assert_int(_system.get_catalyst_count()).is_equal(0)


# 测试4: 合理的活化能和温度下，Arrhenius速率应是个正数
func test_reaction_rate_arrhenius() -> void:
	var rate: float = _system.compute_reaction_rate(150.0, 300.0)
	assert_float(rate).is_greater(0.0)


# 测试5: 只要活化能降低量大于0，加速倍率就该大于1
func test_rate_boost_positive() -> void:
	var boost: float = _system._compute_rate_boost(40.0)
	assert_float(boost).is_greater(1.0)


# 测试6: 没有催化剂时，反应评估应判定为不可催化
func test_evaluate_reaction_no_catalyst() -> void:
	var result: Dictionary = _system.evaluate_reaction(Vector3.ZERO, "H")
	assert_bool(result["catalyzed"]).is_false()


# 测试7: 注册一个Pt催化剂后，在它影响半径内评估反应应被催化
func test_evaluate_reaction_with_catalyst() -> void:
	var atom := _make_atom("Pt", Vector3.ZERO)
	_system.register_catalyst(atom)
	# NETWORK_RADIUS是3.5，取1个单位远的点肯定在范围内
	var result: Dictionary = _system.evaluate_reaction(Vector3(1.0, 0.0, 0.0), "H")
	assert_bool(result["catalyzed"]).is_true()


# 测试8: 催化位点建议接口应返回一个数组
func test_catalyst_positions_suggestions() -> void:
	var atom := _make_atom("H", Vector3.ZERO)
	var suggestions: Array = _system.get_optimal_catalyst_positions([atom])
	assert_bool(suggestions is Array).is_true()


# 测试9: 网络信息字典里应包含 total_catalysts 这个键
func test_network_info() -> void:
	var info: Dictionary = _system.get_network_info()
	assert_dict(info).contains_keys("total_catalysts")


# 测试10: 调用关卡重置后，催化剂应被清空
func test_level_reset() -> void:
	var atom := _make_atom("Pt", Vector3.ZERO)
	_system.register_catalyst(atom)
	assert_int(_system.get_catalyst_count()).is_equal(1)
	_system.on_level_reset()
	assert_int(_system.get_catalyst_count()).is_equal(0)
