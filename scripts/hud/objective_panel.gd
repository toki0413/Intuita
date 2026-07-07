# objective_panel.gd
# 关卡目标面板 - Foldit/Besiege 风格
# 显示当前关卡任务、进度、约束、提示，让玩家知道"该干什么"
# 包含"测试结构"按钮，玩家需主动验证才能完成验证类目标

extends PanelContainer

const HudUtils = preload("res://scripts/hud/hud_utils.gd")

var _i18n = null
signal hint_requested
signal test_requested

var _title_label: Label = null
var _desc_label: Label = null
var _goals_container: VBoxContainer = null
var _hint_label: Label = null
var _collapse_btn: Button = null
var _content: Control = null
var _collapsed: bool = false
var _move_label: Label = null
var _constraint_label: Label = null
var _test_btn: Button = null
var _test_result_label: Label = null

var _goal_widgets: Array = []  # [{label, progress_bar, status_icon}]

var _blink_time: float = 0.0
var _should_blink: bool = false


func _ready() -> void:
	_i18n = Engine.get_main_loop().root.get_node_or_null("/root/I18nManager")
	if _i18n != null and _i18n.has_signal("language_changed"):
		_i18n.language_changed.connect(_on_language_changed)
	_build_ui()

	# 让非交互子节点不拦截鼠标
	HudUtils.set_passthrough(self)

	_refresh_text()
	LevelManager.level_loaded.connect(_on_level_loaded)
	LevelManager.goal_updated.connect(_on_goal_updated)
	LevelManager.constraint_updated.connect(_on_constraint_updated)
	LevelManager.structure_tested.connect(_on_structure_tested)
	# 如果关卡已加载，立即更新
	if LevelManager.current_level_data.size() > 0:
		_on_level_loaded(LevelManager.current_level_data)
func _exit_tree() -> void:
	if _i18n != null and _i18n.is_connected("language_changed", _on_language_changed):
		_i18n.language_changed.disconnect(_on_language_changed)
	if LevelManager != null:
		if LevelManager.level_loaded.is_connected(_on_level_loaded):
			LevelManager.level_loaded.disconnect(_on_level_loaded)
		if LevelManager.goal_updated.is_connected(_on_goal_updated):
			LevelManager.goal_updated.disconnect(_on_goal_updated)
		if LevelManager.constraint_updated.is_connected(_on_constraint_updated):
			LevelManager.constraint_updated.disconnect(_on_constraint_updated)
		if LevelManager.structure_tested.is_connected(_on_structure_tested):
			LevelManager.structure_tested.disconnect(_on_structure_tested)



func _build_ui() -> void:
	# 面板定位: 顶部居中，宽度按屏幕比例缩放（15%-72%），避免与右侧守恒矩阵重叠
	# 使用锚点而非固定像素，适配不同分辨率
	anchor_left = 0.15
	anchor_right = 0.72
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = 10.0
	offset_top = 20.0
	offset_right = -10.0
	offset_bottom = 20.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	custom_minimum_size = Vector2(0, 120)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.047, 0.055, 0.078, 0.88)
	sb.border_color = Color(0, 0.831, 1, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(0, 0.831, 1, 0.12)
	sb.shadow_size = 8
	add_theme_stylebox_override("panel", sb)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 6)
	margin.add_child(outer_vbox)

	# 标题行 + 折叠按钮
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	outer_vbox.add_child(title_row)

	_title_label = Label.new()
	_title_label.text = _i18n.translate("hud.objectives.title")
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.add_theme_color_override("font_color", Color(0, 0.831, 1, 1))
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_title_label)

	_collapse_btn = Button.new()
	_collapse_btn.text = "▼"
	_collapse_btn.custom_minimum_size = Vector2(32, 32)
	_collapse_btn.tooltip_text = "折叠/展开目标面板"
	_collapse_btn.pressed.connect(_toggle_collapse)
	title_row.add_child(_collapse_btn)

	# 可折叠内容区
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 6)
	outer_vbox.add_child(_content)

	# 关卡描述
	_desc_label = Label.new()
	_desc_label.text = ""
	_desc_label.add_theme_font_size_override("font_size", 13)
	_desc_label.add_theme_color_override("font_color", Color(0.8, 0.82, 0.85, 1))
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.custom_minimum_size = Vector2(380, 0)
	_content.add_child(_desc_label)

	# 约束显示区 (时间/步数/部件)
	_constraint_label = Label.new()
	_constraint_label.text = ""
	_constraint_label.add_theme_font_size_override("font_size", 13)
	_constraint_label.add_theme_color_override("font_color", Color(1, 0.6, 0.3, 1))
	_constraint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_constraint_label.custom_minimum_size = Vector2(380, 0)
	_constraint_label.tooltip_text = _i18n.translate("hud.objectives.constraint_tooltip") if _i18n != null else ""
	_content.add_child(_constraint_label)

	# 分隔线
	var sep := HSeparator.new()
	_content.add_child(sep)

	# 目标列表标题
	var goals_title := Label.new()
	goals_title.text = _i18n.translate("hud.goals.legend")
	goals_title.add_theme_font_size_override("font_size", 14)
	goals_title.add_theme_color_override("font_color", Color(1, 0.843, 0, 1))
	_content.add_child(goals_title)

	# 目标列表容器
	_goals_container = VBoxContainer.new()
	_goals_container.add_theme_constant_override("separation", 4)
	_content.add_child(_goals_container)

	# 提示区
	var hint_sep := HSeparator.new()
	_content.add_child(hint_sep)

	_hint_label = Label.new()
	_hint_label.text = ""
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7, 1))
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(380, 0)
	_content.add_child(_hint_label)

	# 测试结构按钮 (Besiege风格: 主动测试)
	_test_btn = Button.new()
	_test_btn.text = _i18n.translate("hud.test_structure")
	_test_btn.add_theme_font_size_override("font_size", 15)
	_test_btn.custom_minimum_size = Vector2(0, 40)
	_test_btn.tooltip_text = _i18n.translate("hud.test_structure.tooltip") if _i18n != null else ""
	_test_btn.pressed.connect(_on_test_pressed)
	_content.add_child(_test_btn)

	# 测试结果显示
	_test_result_label = Label.new()
	_test_result_label.text = ""
	_test_result_label.add_theme_font_size_override("font_size", 12)
	_test_result_label.add_theme_color_override("font_color", Color(0.8, 0.82, 0.85, 1))
	_test_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_test_result_label.custom_minimum_size = Vector2(380, 0)
	_content.add_child(_test_result_label)

	# 移动计数器
	_move_label = Label.new()
	_move_label.text = _i18n.translate("hud.moves")
	_move_label.add_theme_font_size_override("font_size", 12)
	_move_label.add_theme_color_override("font_color", Color(1, 0.843, 0, 0.8))
	_move_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_content.add_child(_move_label)


var _obj_update_timer: float = 0.0
const OBJ_UPDATE_INTERVAL := 0.5  # 每0.5秒更新一次


func _process(_delta: float) -> void:
	if not LevelManager or not is_instance_valid(LevelManager):
		return
	_obj_update_timer += _delta
	if _obj_update_timer >= OBJ_UPDATE_INTERVAL:
		_obj_update_timer = 0.0
		_update_move_counter()
		_update_constraint_display()
	# 测试按钮闪烁提醒
	if _should_blink and _test_btn != null:
		_blink_time += _delta * 5.0
		var alpha: float = (sin(_blink_time) + 1.0) * 0.5
		_test_btn.modulate = Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.8, 0.2), alpha)
	elif _test_btn != null:
		_test_btn.modulate = Color.WHITE


func _on_level_loaded(data: Dictionary) -> void:
	var title: String = data.get("title", "")
	var chapter: int = data.get("chapter", 0)
	var level: int = data.get("level", 0)
	var desc: String = data.get("description", "")
	var hint: String = data.get("hint", "")

	_title_label.text = _i18n.translate("level.title_format", {"chapter": chapter, "level": level, "title": title})
	_desc_label.text = desc
	_hint_label.text = _i18n.translate("hud.hint_prefix", {"hint": hint}) if not hint.is_empty() else ""
	_test_result_label.text = ""

	# 更新约束显示
	_update_constraint_display()
	_update_move_counter()
	_rebuild_goals()


func _update_constraint_display() -> void:
	if not _constraint_label:
		return
	if not LevelManager or not is_instance_valid(LevelManager) or not LevelManager.has_method("get_constraint_status"):
		return
	var cs: Dictionary = LevelManager.get_constraint_status()
	var lines: Array[String] = []

	# 时间约束
	var time_limit: float = cs.get("time_limit", 0)
	var time_elapsed: float = cs.get("time_elapsed", 0)
	if time_limit > 0:
		var remaining: float = maxf(time_limit - time_elapsed, 0)
		var time_str: String = _i18n.translate("hud.constraint.time", {"elapsed": time_elapsed, "limit": time_limit}) if _i18n != null else ""
		if remaining < 10:
			time_str += _i18n.translate("hud.constraint.time_warning") if _i18n != null else ""
		lines.append(time_str)

	# 操作约束
	var move_limit: int = cs.get("move_limit", 0)
	var move_count: int = cs.get("move_count", 0)
	if move_limit > 0:
		var move_str: String = _i18n.translate("hud.constraint.moves", {"count": move_count, "limit": move_limit}) if _i18n != null else ""
		if move_count >= move_limit * 0.8:
			move_str += _i18n.translate("hud.constraint.moves_warning") if _i18n != null else ""
		lines.append(move_str)

	# 部件约束
	var part_limit: int = cs.get("part_limit", 0)
	var part_count: int = cs.get("part_count", 0)
	if part_limit > 0:
		var part_str: String = _i18n.translate("hud.constraint.parts", {"count": part_count, "limit": part_limit}) if _i18n != null else ""
		if part_count >= part_limit * 0.8:
			part_str += _i18n.translate("hud.constraint.parts_warning") if _i18n != null else ""
		lines.append(part_str)

	# 守恒洁癖
	if cs.get("no_warning", false):
		lines.append(_i18n.translate("hud.constraint.no_warning") if _i18n != null else "")

	# 不稳定性
	var instability: float = cs.get("instability", 0)
	var max_instability: float = cs.get("max_instability", 3.0)
	if instability > 0.1:
		var pct := instability / max_instability * 100
		var inst_str: String = _i18n.translate("hud.constraint.instability", {"pct": pct}) if _i18n != null else ""
		if pct > 70:
			inst_str += _i18n.translate("hud.constraint.collapse_warning") if _i18n != null else ""
		lines.append(inst_str)

	_constraint_label.text = "\n".join(lines)

	# 根据约束状态调整颜色
	if lines.size() > 0:
		var has_warning := false
		for line in lines:
			if line.find("⚠") >= 0 or line.find("即将") >= 0:
				has_warning = true
				break
		if has_warning:
			_constraint_label.add_theme_color_override("font_color", ConservationEngine.get_state_color(2))
		else:
			_constraint_label.add_theme_color_override("font_color", ConservationEngine.get_state_color(1))


func _update_move_counter() -> void:
	if _move_label and LevelManager and is_instance_valid(LevelManager):
		var moves: int = LevelManager.move_count
		var par: int = maxi(LevelManager.goals.size() * 2, 4)
		# match keys in zh_CN.json / en.json
		var efficiency_key = "perfect" if moves <= par else ("good" if moves <= par * 2 else "poor")
		var efficiency: String = _i18n.translate("hud.moves." + efficiency_key) if _i18n != null else efficiency_key
		_move_label.text = _i18n.translate("hud.moves_detail", {"moves": moves, "par": par, "efficiency": efficiency}) if _i18n != null else ""
		_move_label.tooltip_text = _i18n.translate("hud.moves.tooltip") if _i18n != null else ""


func _rebuild_goals() -> void:
	# 清除旧目标
	for child in _goals_container.get_children():
		child.queue_free()
	_goal_widgets.clear()

	# 为每个目标创建进度条
	for i in range(LevelManager.goals.size()):
		var goal: Dictionary = LevelManager.goals[i]
		var widget := _create_goal_widget(goal, i)
		_goals_container.add_child(widget)
		_goal_widgets.append(widget)


func _create_goal_widget(goal: Dictionary, index: int) -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)

	# 状态图标
	var status_icon := Label.new()
	status_icon.text = "○"
	status_icon.add_theme_font_size_override("font_size", 16)
	status_icon.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7, 1))
	status_icon.custom_minimum_size = Vector2(24, 24)
	hbox.add_child(status_icon)

	# 目标描述
	var label := Label.new()
	var desc := _format_goal_description(goal)
	# 验证类目标添加标记
	if _is_verification_goal(goal):
		desc = "🔍 " + desc
	label.text = desc
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.85, 0.87, 0.9, 1))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.tooltip_text = _format_goal_tooltip(goal)
	hbox.add_child(label)

	# 进度条
	var progress := ProgressBar.new()
	progress.min_value = 0.0
	progress.max_value = 1.0
	progress.value = 0.0
	progress.custom_minimum_size = Vector2(80, 20)
	progress.show_percentage = false
	progress.tooltip_text = "完成进度"
	hbox.add_child(progress)

	# 百分比数字
	var pct_label := Label.new()
	pct_label.text = "0%"
	pct_label.add_theme_font_size_override("font_size", 12)
	pct_label.add_theme_color_override("font_color", Color(0.8, 0.82, 0.85, 1))
	pct_label.custom_minimum_size = Vector2(36, 20)
	pct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(pct_label)

	# 存储引用用于更新
	hbox.set_meta("status_icon", status_icon)
	hbox.set_meta("progress_bar", progress)
	hbox.set_meta("label", label)
	hbox.set_meta("pct_label", pct_label)

	return hbox


func _is_verification_goal(goal: Dictionary) -> bool:
	var gtype: String = goal.get("type", "")
	match gtype:
		"conservation_check", "geometry_check", "transport_check", \
		"interface_check", "thermal_check", "em_check", "symmetry_check", "verification":
			return true
		_:
			return false


func _format_goal_description(goal: Dictionary) -> String:
	var gtype: String = goal.get("type", "")
	match gtype:
		"wyckoff_fill":
			return "在 %s 位置放置 %s × %d" % [
				goal.get("wyckoff", "?"),
				goal.get("element", "?"),
				int(goal.get("required_count", 1))
			]
		"conservation_check":
			return "守恒量偏差 ≤ %.2f (需测试)" % goal.get("max_deviation", 0.1)
		"verification":
			return "通过结构验证 (需测试)"
		"symmetry_check":
			return "对称性: 空间群 #%d→#%d (需测试)" % [
				goal.get("source_sg", 0),
				goal.get("target_sg", 0)
			]
		"bond_check":
			return "建立 %s-%s 键 × %d" % [
				goal.get("element_a", "?"),
				goal.get("element_b", "?"),
				goal.get("required_count", 1)
			]
		"bond_build":
			return "建立指定化学键 × %d" % goal.get("required_bonds", 1)
		"geometry_check":
			return "几何参数达标 (需测试)"
		"transport_check":
			return "传输路径达标 (需测试)"
		"interface_check":
			return "界面特性达标 (需测试)"
		"reaction_path":
			return "反应路径完成"
		"assembly_check":
			return "组装部件: %s" % goal.get("component", "?")
		"topology_check":
			return "拓扑结构达标"
		"mesh_build":
			return "网格构建完成"
		"path_build":
			return "路径构建完成"
		"thermal_check":
			return "热力学条件达标 (需测试)"
		"diffusion_check":
			return "扩散特性达标"
		"em_check":
			return "电磁特性达标 (需测试)"
		"ca_pattern_reach":
			return "演化至 %s 模式" % goal.get("target_pattern", "稳定")
		"ca_conservation_maintain":
			return "演化中守恒偏离 ≤ %.2f (需测试)" % goal.get("max_deviation", 0.2)
		"ca_phase_transition":
			return "发生 %s 相变" % goal.get("target_phase", "稳定")
		"element_count":
			return "放置 %s × %d" % [goal.get("element", "?"), goal.get("count", 1)]
		"bond_count":
			return "建立 %s 键 × %d" % [goal.get("bond_type", "化学"), goal.get("count", 1)]
		"fog_dispel":
			return "驱散迷雾区域"
		"structure_quality":
			return "结构质量达标 (需测试)"
		"fuzzy_check":
			return "%s %s %s (需测试)" % [goal.get("property", "?"), goal.get("operator", "?"), goal.get("value", "?")]
		"ca_step_count":
			return "演化步数 ≥ %d" % goal.get("value", 1)
		_:
			return goal.get("description", gtype)


func _format_goal_tooltip(goal: Dictionary) -> String:
	var gtype: String = goal.get("type", "")
	match gtype:
		"wyckoff_fill":
			return "在晶格的 Wyckoff 位置放置指定元素\nWyckoff 位置是空间群对称性定义的等效位置\n放置类目标: 放置足够数量自动完成"
		"conservation_check":
			return "守恒矩阵的对角线元素偏离 1.0 不能超过指定值\n验证类目标: 需要点击'测试结构'按钮验证\n查看右上角守恒矩阵了解当前状态"
		"verification":
			return "验证类目标: 需要点击'测试结构'按钮运行验证\n验证管线会检查结构是否符合科学约束"
		"symmetry_check":
			return "构造的结构需要满足对称性降低路径\n验证类目标: 需要点击'测试结构'按钮验证"
		"bond_check":
			return "在两个指定元素之间建立化学键\n使用'成键'工具依次点击两个原子"
		"geometry_check":
			return "验证类目标: 需要点击'测试结构'按钮验证\n检查键长、键角、晶格参数等几何约束"
		"ca_pattern_reach":
			return "元胞自动机目标: 驱动CA演化直到出现目标模式\n需要点击'测试结构'按钮确认模式已稳定"
		"ca_conservation_maintain":
			return "验证类目标: 演化过程中守恒矩阵不能偏离太多\n让CA运行足够步数后点击'测试结构'验证"
		"ca_phase_transition":
			return "元胞自动机目标: 让系统从一种相态演化到目标相态\n需要点击'测试结构'按钮确认"
		_:
			return "完成此目标以通关\n🔍标记的目标需要点击'测试结构'按钮验证"


func _on_goal_updated(goal_index: int, state: int, progress: float) -> void:
	if goal_index < 0 or goal_index >= _goal_widgets.size():
		return
	var widget: Control = _goal_widgets[goal_index]
	var status_icon: Label = widget.get_meta("status_icon")
	var progress_bar: ProgressBar = widget.get_meta("progress_bar")
	var label: Label = widget.get_meta("label")
	var pct_label: Label = widget.get_meta("pct_label")

	if status_icon:
		match state:
			LevelManager.GoalState.PENDING:
				status_icon.text = "○"
				status_icon.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7, 1))
			LevelManager.GoalState.IN_PROGRESS:
				status_icon.text = "◐"
				status_icon.add_theme_color_override("font_color", ConservationEngine.get_state_color(1))
			LevelManager.GoalState.COMPLETED:
				status_icon.text = "●"
				status_icon.add_theme_color_override("font_color", ConservationEngine.get_state_color(0))
			LevelManager.GoalState.FAILED:
				status_icon.text = "✕"
				status_icon.add_theme_color_override("font_color", ConservationEngine.get_state_color(2))

	if progress_bar:
		progress_bar.value = progress

	if pct_label:
		pct_label.text = "%d%%" % int(round(progress * 100.0))
		if state == LevelManager.GoalState.COMPLETED:
			pct_label.add_theme_color_override("font_color", ConservationEngine.get_state_color(0))
		elif state == LevelManager.GoalState.FAILED:
			pct_label.add_theme_color_override("font_color", ConservationEngine.get_state_color(2))
		else:
			pct_label.add_theme_color_override("font_color", Color(0.8, 0.82, 0.85, 1))

	if label and state == LevelManager.GoalState.COMPLETED:
		label.add_theme_color_override("font_color", Color(ConservationEngine.get_state_color(0), 0.8))
		# 完成时播放一次缩放反馈动画
		UiAnimator.pulse_scale(widget, 1.05)
		# 播放音效
		if SoundManager != null:
			SoundManager.play(SoundManager.SoundType.PROOF_COMPLETE)
	# 更新测试按钮闪烁状态
	_update_test_button_blink()


func _on_constraint_updated(_constraint_type: String, _current: float, _limit: float) -> void:
	_update_constraint_display()


func _on_structure_tested(stable: bool, issues: Array) -> void:
	if stable:
		_test_result_label.text = _i18n.translate("hud.test.success")
		_test_result_label.add_theme_color_override("font_color", ConservationEngine.get_state_color(0))
		_test_btn.add_theme_color_override("font_color", ConservationEngine.get_state_color(0))
	else:
		var issue_text: String = "✕ 结构不稳定:\n"
		for issue in issues:
			issue_text += "  • " + str(issue) + "\n"
		_test_result_label.text = issue_text
		_test_result_label.add_theme_color_override("font_color", ConservationEngine.get_state_color(2))
		_test_btn.add_theme_color_override("font_color", ConservationEngine.get_state_color(2))


func _on_test_pressed() -> void:
	# Besiege风格: 主动测试结构
	_test_result_label.text = _i18n.translate("hud.test.running")
	_test_result_label.add_theme_color_override("font_color", ConservationEngine.get_state_color(1))
	test_requested.emit()
	LevelManager.test_structure()


func _toggle_collapse() -> void:
	_collapsed = not _collapsed
	_content.visible = not _collapsed
	_collapse_btn.text = "▶" if _collapsed else "▼"

	# 折叠时缩小面板
	if _collapsed:
		offset_bottom = offset_top + 60.0
	else:
		offset_bottom = offset_top + 400.0


func _update_test_button_blink() -> void:
	# 检查是否有可测试的验证类目标
	_should_blink = false
	if LevelManager.goals.size() == 0:
		return
	for goal in LevelManager.goals:
		if LevelManager._goal_requires_verification(goal.get("type", "")):
			_should_blink = true
			break


func _on_language_changed(_locale: String) -> void:
	_refresh_text()

func _refresh_text() -> void:
	if _i18n == null:
		return

