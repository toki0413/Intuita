# regression_test.gd
# 回归测试：验证已修复的bug不会复发
# 每个测试case对应一个具体的bug修复

class_name RegressionTest
extends GdUnitTestSuite


var _lm: Node = null
var _ce: Node = null


func before_test() -> void:
	_lm = Engine.get_main_loop().root.get_node("/root/LevelManager")
	_ce = Engine.get_main_loop().root.get_node("/root/ConservationEngine")


# Bug: max_parts 约束把键也计入部件数，导致 Ch2-L11(4原子+3键=7>6) 不可通关
# Fix: max_parts 只计原子数，不计键
func test_max_parts_excludes_bonds() -> void:
	_lm._level_completed = false
	_lm._atoms_placed.clear()
	_lm._bonds_built.clear()
	_lm._part_limit = 6
	# 放置4个原子 + 3个键 = 7 "部件"（旧逻辑会超限）
	for i in range(4):
		_lm.register_atom_placement("Si", "a")
	for i in range(3):
		_lm.register_bond("Si", "O")
	# 验证不会触发失败
	_lm._check_constraints()
	assert_bool(_lm._level_failed).override_failure_message(
		"max_parts不应将键计入部件数：4原子+3键应在max_parts=6下通过"
	).is_false()


# Bug: ca_conservation_maintain 使用历史最大偏离，暂时偏离后永远无法完成
# Fix: 改用当前偏离值
func test_ca_conservation_uses_current_deviation() -> void:
	_lm._level_completed = false
	_lm._atoms_placed.clear()
	_lm._ca_step_count = 15
	_lm._ca_max_deviation = 0.5  # 历史最大偏离（高）
	_ce.reset()  # 当前偏离为0（健康）
	# 设置一个 ca_conservation_maintain 目标
	var typed_goals: Array[Dictionary] = [{"type": "ca_conservation_maintain", "max_deviation": 0.2, "min_steps": 10, "description": "test"}]
	_lm.goals = typed_goals
	var typed_states: Array[int] = [_lm.GoalState.PENDING]
	_lm.goal_states = typed_states
	_lm.verify_goals()
	# 当前偏离为0，应该能完成（即使历史最大偏离很高）
	assert_bool(_lm.goal_states[0] == _lm.GoalState.COMPLETED).override_failure_message(
		"ca_conservation_maintain应检查当前偏离而非历史最大值"
	).is_true()


# Bug: forbidden_tools 定义了 is_tool_forbidden() 但从未调用
# Fix: construction_canvas.set_tool() 中调用检查
func test_forbidden_tools_enforced() -> void:
	var ft: Array[String] = ["bond_tool"]
	_lm._forbidden_tools = ft
	assert_bool(_lm.is_tool_forbidden("bond_tool")).is_true()
	assert_bool(_lm.is_tool_forbidden("element_block")).is_false()
	var empty_ft: Array[String] = []
	_lm._forbidden_tools = empty_ft


# Bug: fuzzy_check 对 <= 操作符 progress 计算反向
# Fix: <= 操作符使用 1.0 - current/threshold
func test_fuzzy_check_progress_le_operator() -> void:
	_lm._level_completed = false
	_lm._atoms_placed.clear()
	_lm._bonds_built.clear()
	_ce.reset()
	# max_deviation metric with <= operator, threshold 0.3
	var typed_goals: Array[Dictionary] = [{
		"type": "fuzzy_check",
		"metric": "max_deviation",
		"operator": "<=",
		"threshold": 0.3,
		"description": "test"
	}]
	_lm.goals = typed_goals
	var ts2: Array[int] = [_lm.GoalState.PENDING]
	_lm.goal_states = ts2
	_lm._check_goals()
	# 守恒引擎已重置，current_val=0，应完成
	assert_bool(_lm.goal_states[0] == _lm.GoalState.COMPLETED).override_failure_message(
		"fuzzy_check对<=操作符在current=0时应完成"
	).is_true()


# Bug: verify_goals() 缺少 ca_conservation_maintain case，目标永远无法完成
# Fix: 添加 case 到 verify_goals()
func test_verify_goals_has_ca_conservation_case() -> void:
	_lm._level_completed = false
	_lm._atoms_placed.clear()
	_lm._ca_step_count = 15
	_ce.reset()
	var typed_goals: Array[Dictionary] = [{"type": "ca_conservation_maintain", "max_deviation": 0.2, "min_steps": 10, "description": "test"}]
	_lm.goals = typed_goals
	var ts3: Array[int] = [_lm.GoalState.PENDING]
	_lm.goal_states = ts3
	_lm.verify_goals()
	assert_bool(_lm.goal_states[0] == _lm.GoalState.COMPLETED).override_failure_message(
		"verify_goals()应能处理ca_conservation_maintain类型目标"
	).is_true()


# Bug: seed_count metric 不存在，Ch4-L9/L10 "保存种子"目标永远为0
# Fix: 新增 seed_count metric + register_ca_seed_save()
func test_seed_count_metric() -> void:
	_lm._level_completed = false
	_lm._atoms_placed.clear()
	_lm._ca_seeds_saved = 0
	_ce.reset()
	var typed_goals: Array[Dictionary] = [{
		"type": "fuzzy_check",
		"metric": "seed_count",
		"operator": ">=",
		"threshold": 2,
		"description": "test"
	}]
	_lm.goals = typed_goals
	var ts4: Array[int] = [_lm.GoalState.PENDING]
	_lm.goal_states = ts4
	# 保存2个种子
	_lm.register_ca_seed_save()
	_lm.register_ca_seed_save()
	_lm._check_goals()
	assert_bool(_lm.goal_states[0] == _lm.GoalState.COMPLETED).override_failure_message(
		"seed_count metric应能正确计数CA种子保存"
	).is_true()


# Bug: symmetry_check 在立方晶格上评分恒为0
# Fix: Ch2-L3 改为四方晶格 + I4/mmm
func test_symmetry_check_tetragonal_achievable() -> void:
	var loader_script: Resource = load("res://scripts/autoload/level_data_loader.gd")
	var loader: Variant = loader_script.new()
	loader._rebuild_registry()
	var ld: Variant = loader.load_level_data(2, 3)
	assert_that(ld).is_not_null()
	var json_data: Dictionary = ld.to_json()
	# 验证晶格不是立方
	var lp = json_data["lattice_parameters"]
	var is_cubic: bool = absf(float(lp["x"]) - float(lp["y"])) < 0.001 and absf(float(lp["y"]) - float(lp["z"])) < 0.001
	assert_bool(is_cubic).override_failure_message(
		"Ch2-L3晶格应为四方（非立方）以使symmetry_check可达"
	).is_false()
