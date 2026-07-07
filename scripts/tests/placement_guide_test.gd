# placement_guide_test.gd
# 智能放置引导系统的单元测试

extends GdUnitTestSuite


var _guide = null
var _mock_canvas: Node3D = null


func before_test() -> void:
	_mock_canvas = Node3D.new()
	_mock_canvas.name = "PlacementGuideTestCanvas"
	Engine.get_main_loop().root.add_child(_mock_canvas)
	var script = load("res://scripts/gameplay/placement_guide_system.gd")
	# atom_mgr 和 float_text 都传 null，走空数据分支
	_guide = script.new(_mock_canvas, null, null)
	await Engine.get_main_loop().process_frame


func after_test() -> void:
	if _guide != null:
		_guide.on_level_reset()
		_guide = null
	if _mock_canvas != null and is_instance_valid(_mock_canvas):
		_mock_canvas.queue_free()
		await Engine.get_main_loop().process_frame


# 测试1: 新建的引导系统不应有任何建议
func test_empty_suggestions() -> void:
	var suggestions: Array = _guide.get_suggestions()
	assert_array(suggestions).is_empty()


# 测试2: evaluate_placement 必须返回带 total_score 的字典
func test_evaluate_placement_returns_dict() -> void:
	var result: Dictionary = _guide.evaluate_placement(Vector3(0, 0, 0), "H")
	assert_bool(result.has("total_score")).is_true()


# 测试3: 总评分应落在 [0, 1] 区间内
func test_evaluate_placement_score_range() -> void:
	var result: Dictionary = _guide.evaluate_placement(Vector3(0, 0, 0), "H")
	var score: float = result["total_score"]
	assert_bool(score >= 0.0).is_true()
	assert_bool(score <= 1.0).is_true()


# 测试4: 没有建议时摘要文本应给出提示
func test_get_guide_summary_empty() -> void:
	var summary: String = _guide.get_guide_summary()
	assert_str(summary).is_equal("暂无放置建议")


# 测试5: 调过 evaluate_placement 之后摘要仍应是合法字符串
func test_guide_summary_after_eval() -> void:
	_guide.evaluate_placement(Vector3(0, 0, 0), "H")
	var summary: String = _guide.get_guide_summary()
	# 只要求返回一个非空字符串即可
	assert_str(summary).is_not_empty()


# 测试6: 切换到 Wyckoff 模式不能崩
func test_set_mode() -> void:
	# GuideMode.WYCKOFF 对应枚举值 0
	_guide.set_mode(0)
	# 能走到这里就说明没崩
	assert_bool(true).is_true()


# 测试7: 连续开关引导不应抛错
func test_set_active() -> void:
	_guide.set_active(false)
	_guide.set_active(true)
	assert_bool(true).is_true()


# 测试8: 关卡重置后建议列表应清空
func test_level_reset() -> void:
	_guide.on_level_reset()
	assert_array(_guide.get_suggestions()).is_empty()


# 测试9: 没有建议时 get_best_suggestion 返回空字典
func test_get_best_suggestion_empty() -> void:
	var best: Dictionary = _guide.get_best_suggestion()
	assert_bool(best.is_empty()).is_true()


# 测试10: evaluate_placement 的结果里要带 reasons 数组
func test_evaluate_placement_has_reasons() -> void:
	var result: Dictionary = _guide.evaluate_placement(Vector3(0, 0, 0), "H")
	assert_bool(result.has("reasons")).is_true()
	assert_bool(result["reasons"] is Array).is_true()
