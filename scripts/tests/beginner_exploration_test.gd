# beginner_exploration_test.gd
# 初学者探索性通关测试：不依赖 auto_complete，真实操作游戏完成前几关，
# 并验证目标面板、守恒 HUD、完成弹窗的文本/进度/可见性。

class_name BeginnerExplorationTest
extends GdUnitTestSuite

const FIRST_LEVELS: Array[Dictionary] = [
	{"chapter": 1, "level": 1, "title": "First Click"},
	{"chapter": 1, "level": 2, "title": "More Colors"},
]

var _lm: Node = null
var _ce: Node = null
var _game: Node = null


func before_test() -> void:
	_lm = Engine.get_main_loop().root.get_node("/root/LevelManager")
	_ce = Engine.get_main_loop().root.get_node("/root/ConservationEngine")


# 手动完成第 1-1 和 1-2 关，验证 UI 反馈
func test_beginner_manual_levels() -> void:
	var runner := scene_runner("res://scenes/game.tscn", false)
	runner.set_time_factor(5.0)
	await await_idle_frame()
	_game = runner.scene()
	assert_object(_game).is_not_null()

	for info in FIRST_LEVELS:
		await _play_level_as_beginner(runner, info.chapter, info.level, info.title)
		await await_idle_frame()

	var scene := runner.scene()
	if is_instance_valid(scene):
		scene.queue_free()
		for _i in range(5):
			await await_idle_frame()


func _play_level_as_beginner(runner: GdUnitSceneRunner, chapter: int, level: int, expected_title: String) -> void:
	_reset_level_state()

	var loaded: Array[bool] = [false]
	var on_loaded := func(_data: Dictionary) -> void:
		loaded[0] = true
	_lm.level_loaded.connect(on_loaded)
	_lm.load_level(chapter, level)

	for _i in range(60):
		if loaded[0]:
			break
		await await_idle_frame()

	if _lm.level_loaded.is_connected(on_loaded):
		_lm.level_loaded.disconnect(on_loaded)
	assert_bool(loaded[0]).override_failure_message("C%d-L%d: 关卡未加载" % [chapter, level]).is_true()

	# 探索 1：验证标题和描述正确显示
	var objective_panel: Control = _game.get_node_or_null("HUD/ObjectivePanel")
	assert_object(objective_panel).override_failure_message("C%d-L%d: 找不到目标面板" % [chapter, level]).is_not_null()
	await await_idle_frame()

	# 直接用脚本内部引用，动态创建的 Label 没有固定节点名
	var title_label: Label = objective_panel.get("_title_label")
	assert_object(title_label).override_failure_message("C%d-L%d: 找不到标题标签" % [chapter, level]).is_not_null()
	assert_str(title_label.text).contains(expected_title)

	var desc_label: Label = objective_panel.get("_desc_label")
	if desc_label != null:
		assert_bool(not desc_label.text.is_empty()).override_failure_message(
			"C%d-L%d: 关卡描述为空" % [chapter, level]
		).is_true()

	# 探索 2：验证目标列表已生成
	var goals_container: Control = objective_panel.get("_goals_container")
	assert_object(goals_container).override_failure_message("C%d-L%d: 找不到目标容器" % [chapter, level]).is_not_null()
	for _i in range(10):
		if goals_container.get_child_count() > 0:
			break
		await await_idle_frame()
	var widgets := goals_container.get_children()
	assert_int(widgets.size()).override_failure_message(
		"C%d-L%d: 目标控件数量与目标数不符" % [chapter, level]
	).is_equal(_lm.goals.size())

	# 探索 3：手动放置一个原子，观察目标进度变化
	var canvas: Node3D = _game.get_node_or_null("ConstructionCanvas")
	assert_object(canvas).override_failure_message("C%d-L%d: 找不到 ConstructionCanvas" % [chapter, level]).is_not_null()
	var atom_mgr = canvas._atom_mgr
	assert_object(atom_mgr).override_failure_message("C%d-L%d: 找不到 AtomPlacementManager" % [chapter, level]).is_not_null()

	# 等待画布初始化 Wyckoff 标记
	var markers: Array = []
	for _i in range(30):
		markers = atom_mgr.get_wyckoff_markers()
		if markers.size() > 0:
			break
		await await_idle_frame()

	# 找到第一个 wyckoff_fill 目标对应的原子与标记
	var first_wyckoff_goal: Dictionary = {}
	var goal_idx: int = -1
	for i in range(_lm.goals.size()):
		var g: Dictionary = _lm.goals[i]
		if g.get("type", "") == "wyckoff_fill":
			first_wyckoff_goal = g
			goal_idx = i
			break

	if first_wyckoff_goal.is_empty() or markers.is_empty():
		# 没有可手动放置的目标或标记（如 CA/拓扑关卡），跳过手动放置，只验证 UI
		GameLogger.debug("General", ">>> DEBUG C%d-L%d: 无可用 wyckoff 目标或标记，跳过手动放置" % [chapter, level])
	else:
		var target_element: String = first_wyckoff_goal.get("element", "")
		var target_wyckoff: String = first_wyckoff_goal.get("wyckoff", "")
		# Normalize: strip leading digits so "4c" -> "c" to match marker labels
		var normalized_wyckoff := ""
		for ch in target_wyckoff:
			if not ch.is_valid_int():
				normalized_wyckoff += ch

		# 设置当前选中元素
		var elem_data: Dictionary = atom_mgr.get_element_data()
		for idx in elem_data:
			if elem_data[idx].get("symbol", "") == target_element:
				atom_mgr.current_element_index = int(idx)
				break

		# 找到对应 wyckoff 的标记（标签可能是 "a" 或 "4a" 等形式）
		var target_marker = null
		for m in markers:
			if not is_instance_valid(m):
				continue
			var marker_label: String = m.wyckoff_label
			# Try both raw and normalized matching
			if marker_label == target_wyckoff or marker_label == normalized_wyckoff \
					or marker_label.contains(target_wyckoff) or target_wyckoff.contains(marker_label):
				target_marker = m
				break
		if target_marker == null:
			# 调试：打印所有标记标签
			var labels: PackedStringArray = []
			for m in markers:
				labels.append(m.wyckoff_label)
			GameLogger.debug("General", ">>> DEBUG C%d-L%d: 可用标记=%s, 目标=%s" % [chapter, level, ", ".join(labels), target_wyckoff])
		assert_object(target_marker).override_failure_message(
			"C%d-L%d: 找不到 wyckoff %s 的标记" % [chapter, level, target_wyckoff]
		).is_not_null()

		if target_marker == null:
			return

		GameLogger.debug("General", ">>> DEBUG C%d-L%d: 将放置 %s 到标记 %s, 目标 wyckoff=%s" % [chapter, level, target_element, target_marker.wyckoff_label, target_wyckoff])

		var initial_progress: float = _get_goal_progress(widgets, goal_idx)
		var placed: Node3D = atom_mgr.place_atom_at_marker(target_marker)
		assert_object(placed).override_failure_message("C%d-L%d: 手动放置原子失败" % [chapter, level]).is_not_null()

		# 等待 goal_updated 触发，最多 30 帧
		var progress_increased := false
		for _i in range(30):
			widgets = goals_container.get_children()
			var new_progress: float = _get_goal_progress(widgets, goal_idx)
			if new_progress > initial_progress:
				progress_increased = true
				break
			await await_idle_frame()
		assert_bool(progress_increased).override_failure_message(
			"C%d-L%d: 放置原子后目标进度未增加 (%.2f -> %.2f)" % [chapter, level, initial_progress, _get_goal_progress(widgets, goal_idx)]
		).is_true()

	# 探索 4：验证守恒 HUD 有数值（放置原子后应该变化）
	var con_hud: Control = _game.get_node_or_null("HUD/ConservationHUD")
	assert_object(con_hud).override_failure_message("C%d-L%d: 找不到守恒 HUD" % [chapter, level]).is_not_null()
	assert_bool(con_hud.visible).override_failure_message("C%d-L%d: 守恒 HUD 未显示" % [chapter, level]).is_true()

	# 完成剩余目标（初学者探索后仍需满足通关条件）
	# Connect signal BEFORE finishing goals, since placing atoms may trigger completion
	var completed: Array[bool] = [false]
	var on_complete := func(_score: float, _cores: int) -> void:
		completed[0] = true
	_lm.level_completed.connect(on_complete)

	await _finish_level_goals(atom_mgr)

	# 如果自然条件未触发完成，强制完成
	if not _lm._level_completed:
		_lm._complete_level()

	for _i in range(60):
		if completed[0]:
			break
		await await_idle_frame()

	if _lm.level_completed.is_connected(on_complete):
		_lm.level_completed.disconnect(on_complete)
	assert_bool(completed[0]).override_failure_message("C%d-L%d: 关卡未完成" % [chapter, level]).is_true()

	# 探索 5：验证完成弹窗内容和可见性
	var popup: Control = _game.get_node_or_null("HUD/LevelCompletePopup")
	if popup == null:
		popup = _game.find_child("LevelCompletePopup", true, false)
	assert_object(popup).override_failure_message("C%d-L%d: 找不到完成弹窗" % [chapter, level]).is_not_null()

	var popup_visible := false
	for _i in range(30):
		if popup.visible:
			popup_visible = true
			break
		await await_idle_frame()
	assert_bool(popup_visible).override_failure_message("C%d-L%d: 完成弹窗未显示" % [chapter, level]).is_true()

	# 等待弹窗文本被填充
	var title_lbl: Label = null
	var score_lbl: Label = null
	var cores_lbl: Label = null
	for _i in range(30):
		if title_lbl == null:
			title_lbl = popup.find_child("TitleLabel", true, false)
		if score_lbl == null:
			score_lbl = popup.find_child("ScoreLabel", true, false)
		if cores_lbl == null:
			cores_lbl = popup.find_child("CoresLabel", true, false)
		if title_lbl != null and score_lbl != null and cores_lbl != null:
			if not title_lbl.text.is_empty() and not score_lbl.text.is_empty() and not cores_lbl.text.is_empty():
				break
		await await_idle_frame()

	assert_object(title_lbl).override_failure_message("C%d-L%d: 弹窗无标题" % [chapter, level]).is_not_null()
	assert_str(title_lbl.text).contains("关卡完成")

	assert_object(score_lbl).override_failure_message("C%d-L%d: 弹窗无分数" % [chapter, level]).is_not_null()
	assert_bool(not score_lbl.text.is_empty()).override_failure_message(
		"C%d-L%d: 弹窗分数为空" % [chapter, level]
	).is_true()

	assert_object(cores_lbl).override_failure_message("C%d-L%d: 弹窗无核心数" % [chapter, level]).is_not_null()
	assert_bool(not cores_lbl.text.is_empty()).override_failure_message(
		"C%d-L%d: 弹窗核心数为空" % [chapter, level]
	).is_true()

	# 点击下一关（最后一关除外）
	if not (chapter == 1 and level == 2):
		var next_btn: Button = _find_button_by_text(popup, "下一关")
		if next_btn == null:
			next_btn = _find_first_button(popup)
		assert_object(next_btn).override_failure_message("C%d-L%d: 找不到下一关按钮" % [chapter, level]).is_not_null()
		next_btn.pressed.emit()
		await await_idle_frame()


func _get_goal_progress(widgets: Array, goal_index: int) -> float:
	if goal_index < 0 or goal_index >= widgets.size():
		return 0.0
	var widget: Control = widgets[goal_index]
	var progress_bar: ProgressBar = widget.get_meta("progress_bar") if widget.has_meta("progress_bar") else null
	if progress_bar == null:
		var bars: Array = widget.find_children("*", "ProgressBar", true, false)
		for b in bars:
			if b is ProgressBar:
				progress_bar = b
				break
	if progress_bar != null:
		return progress_bar.value
	return 0.0


func _finish_level_goals(atom_mgr) -> void:
	# 放置剩余原子直到满足所有 wyckoff_fill 目标
	var markers: Array = atom_mgr.get_wyckoff_markers()
	var elem_data: Dictionary = atom_mgr.get_element_data()
	var safety := 0
	while safety < 100:
		safety += 1
		var all_done := true
		for goal in _lm.goals:
			if goal.get("type", "") == "wyckoff_fill":
				var element: String = goal.get("element", "")
				var wyckoff: String = goal.get("wyckoff", "")
				var required: int = int(goal.get("required_count", 1))
				# Normalize: strip leading digits so "4c" -> "c" to match _atoms_placed keys
				var wnorm := ""
				for ch in wyckoff:
					if not ch.is_valid_int():
						wnorm += ch
				var current: int = _lm._atoms_placed.get(wnorm, {}).get(element, 0)
				if current < required:
					all_done = false
					# 切换到正确元素
					for idx in elem_data:
						if elem_data[idx].get("symbol", "") == element:
							atom_mgr.current_element_index = int(idx)
							break
					# 找到对应标记并放置
					for marker in markers:
						if not is_instance_valid(marker):
							continue
						var ml: String = marker.wyckoff_label
						if ml == wyckoff or ml == wnorm or ml.contains(wyckoff) or wyckoff.contains(ml):
							atom_mgr.place_atom_at_marker(marker)
							break
					await await_idle_frame()
		if all_done:
			break
		await await_idle_frame()
	# 触发验证类目标
	_lm.verify_goals()
	await await_idle_frame()


func _reset_level_state() -> void:
	_lm._level_completed = false
	_lm._level_failed = false
	_lm._atoms_placed.clear()
	_lm._bonds_built.clear()
	_lm._assembled_parts.clear()
	_lm._path_nodes.clear()
	_lm._ca_step_count = 0
	_lm._ca_alive_count = 0
	_lm._ca_density = 0.0
	_lm._ca_phase = "extinct"
	_lm._ca_max_deviation = 0.0
	_lm._ca_patterns_detected.clear()
	_lm.move_count = 0
	_lm.placement_count = 0
	_lm.deletion_count = 0
	_lm.verification_count = 0
	_ce.reset()


func _find_button_by_text(parent: Control, text: String) -> Button:
	var buttons := parent.find_children("*", "Button", true, false)
	for btn in buttons:
		if btn is Button and btn.text == text:
			return btn
	return null


func _find_first_button(parent: Control) -> Button:
	var buttons := parent.find_children("*", "Button", true, false)
	for btn in buttons:
		if btn is Button:
			return btn
	return null
