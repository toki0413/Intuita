# ca_mode_test.gd
# Godot 原生 CA 模式集成测试，不依赖外部 PyAutoGUI
# 覆盖 3D Bays' 规则引擎、渲染器、守恒矩阵耦合与关卡目标

class_name CAModeTest
extends GdUnitTestSuite

const CellularAutomatonEngine = preload("res://scripts/simulation/cellular_automaton_engine.gd")
const CAGridRenderer = preload("res://scripts/construction/ca_grid_renderer.gd")

var _lm: Node = null


func before() -> void:
	_lm = Engine.get_main_loop().root.get_node_or_null("/root/LevelManager")


func after() -> void:
	if _lm != null:
		_lm.reset_level()


func test_ca_engine_rules_and_step() -> void:
	var engine := CellularAutomatonEngine.new(6, 6, 6)
	engine.set_rule_by_name("bays_4555")

	assert_bool(engine.birth_rules == [5]).is_true()
	assert_bool(engine.survival_rules == [4, 5]).is_true()

	engine.load_pattern("center_seed")
	assert_int(engine.get_alive_count()).is_greater(0)

	var before := engine.get_step_count()
	engine.step()
	assert_int(engine.get_step_count()).is_equal(before + 1)
	assert_int(engine.get_alive_count()).is_greater_equal(0)


func test_ca_engine_conservation_perturbation_bounded() -> void:
	var engine := CellularAutomatonEngine.new(8, 8, 8)
	engine.load_pattern("random_medium")
	engine.step()

	var pert := engine.get_conservation_perturbation()
	assert_bool(pert.has("mass")).is_true()
	assert_bool(pert.has("momentum")).is_true()
	assert_bool(pert.has("energy")).is_true()
	assert_float(pert["mass"]).is_between(-0.2, 0.2)
	assert_float(pert["momentum"]).is_between(-0.2, 0.2)
	assert_float(pert["energy"]).is_between(-0.2, 0.2)


func test_ca_level_data_loads() -> void:
	if _lm == null:
		return
	_lm.reset_level()
	_lm.load_level(5, 2)

	assert_dict(_lm.current_level_data).is_not_empty()
	assert_str(_lm.current_level_data.get("construction_mode", "")).is_equal("cellular_automaton")
	assert_int(_lm.goals.size()).is_greater(0)


func test_ca_mode_initializes_in_game_scene() -> void:
	if _lm != null:
		_lm.reset_level()

	var scene := load("res://scenes/game.tscn") as PackedScene
	assert_object(scene).is_not_null()

	var instance := scene.instantiate()
	assert_object(instance).is_not_null()
	add_child(instance)

	if _lm != null:
		_lm.load_level(5, 2)

	# 等待 construction_canvas 的 call_deferred + create_timer(0.0) + tutorial_overlay deferred 完成
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout

	var canvas: Node3D = instance.get_node_or_null("ConstructionCanvas")
	assert_object(canvas).is_not_null()
	assert_str(canvas._current_construction_mode).is_equal("cellular_automaton")

	var ca_container := canvas.get_node_or_null("CAContainer")
	assert_object(ca_container).is_not_null()

	var renderer: Node = ca_container.get_node_or_null("CAGridRenderer")
	assert_object(renderer).is_not_null()
	assert_object(renderer.engine).is_not_null()

	instance.queue_free()


func test_ca_renderer_step_and_auto_evolve() -> void:
	if _lm != null:
		_lm.reset_level()

	var scene := load("res://scenes/game.tscn") as PackedScene
	var instance := scene.instantiate()
	add_child(instance)

	if _lm != null:
		_lm.load_level(5, 2)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout

	var canvas: Node3D = instance.get_node_or_null("ConstructionCanvas")
	assert_object(canvas).is_not_null()
	var renderer: CAGridRenderer = canvas._ca_renderer
	assert_object(renderer).is_not_null()

	var step_before := renderer.engine.get_step_count()
	renderer.evolve_step()
	assert_int(renderer.engine.get_step_count()).is_equal(step_before + 1)

	# 自动演化应在 process 中持续推进
	renderer.toggle_auto_evolve()
	await get_tree().create_timer(0.4).timeout
	renderer.toggle_auto_evolve()
	assert_int(renderer.engine.get_step_count()).is_greater(step_before + 1)

	instance.queue_free()


func test_ca_goals_progress_via_level_manager() -> void:
	if _lm == null:
		return
	_lm.reset_level()
	_lm.load_level(5, 2)

	var goals: Array = _lm.goals
	var has_pattern := false
	var goal_index := -1
	for i in range(goals.size()):
		if goals[i].get("type") == "ca_pattern_reach":
			has_pattern = true
			goal_index = i
			break
	assert_bool(has_pattern).is_true()

	for i in range(15):
		_lm.register_ca_step({
			"step": i,
			"alive": 12,
			"density": 0.12,
			"phase": "stable" if i >= 10 else "chaotic",
		})

	# ca_pattern_reach 是非验证类目标，应自动完成
	assert_int(_lm.goal_states[goal_index]).is_equal(_lm.GoalState.COMPLETED)
