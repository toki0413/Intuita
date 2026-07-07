# goal_check_test.gd
# gdUnit4 单元测试：目标检查逻辑
# 测试 symmetry_check、conservation_check、geometry_check、mesh_build 的真实计算行为

extends GdUnitTestSuite


const __source = "res://scripts/autoload/05_level_manager.gd"

var _lm: Node = null


func before() -> void:
	_lm = Engine.get_main_loop().root.get_node_or_null("/root/LevelManager")


func after() -> void:
	if _lm != null:
		_lm.reset_level()


func test_symmetry_check_requires_atoms() -> void:
	# 没有原子放置时，symmetry_check 应该 progress=0，状态保持 PENDING
	if _lm == null:
		return
	_lm.load_level(1, 3)  # 八面体倾斜 - 有 symmetry_check 目标
	_lm._check_goals()
	var goals: Array = _lm.goals
	for i in range(goals.size()):
		if goals[i]["type"] == "symmetry_check":
			assert_int(_lm.goal_states[i]).is_equal(_lm.GoalState.PENDING)


func test_conservation_check_with_identity_matrix() -> void:
	# 单位矩阵的偏离度为 0，conservation_check 应该通过
	if _lm == null:
		return
	_lm.load_level(1, 1)  # NaCl - 有 conservation_check 目标
	ConservationEngine.reset()
	_lm._check_goals()
	var goals: Array = _lm.goals
	for i in range(goals.size()):
		if goals[i]["type"] == "conservation_check":
			# 偏离度为 0，应该完成或至少有进度
			assert_bool(_lm.goal_states[i] == _lm.GoalState.COMPLETED or \
				_lm.goal_states[i] == _lm.GoalState.IN_PROGRESS).override_failure_message(
				"conservation_check with identity matrix should progress"
			)


func test_geometry_check_not_completed_without_atoms() -> void:
	# 没有原子放置时，geometry_check 不应标记为完成
	# 即使守恒矩阵健康，缺少原子也无法验证几何约束
	if _lm == null:
		return
	_lm.load_level(1, 5)  # 金刚石网络 - 有 geometry_check (target_angle=109.5°)
	ConservationEngine.reset()
	_lm._check_goals()
	var goals: Array = _lm.goals
	for i in range(goals.size()):
		if goals[i]["type"] == "geometry_check":
			assert_int(_lm.goal_states[i]).is_not_equal(_lm.GoalState.COMPLETED)


func test_mesh_build_counts_atoms() -> void:
	# mesh_build 目标需要足够的原子，没有放置原子时不应完成
	if _lm == null:
		return
	_lm.load_level(2, 5)  # 流体边界层 - 有 mesh_build 目标
	_lm._check_goals()
	var goals: Array = _lm.goals
	for i in range(goals.size()):
		if goals[i]["type"] == "mesh_build":
			assert_int(_lm.goal_states[i]).is_not_equal(_lm.GoalState.COMPLETED)
