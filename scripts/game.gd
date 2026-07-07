# game.gd
# 游戏主控制器 - 协调各个子系统
#
# Responsibilities:
#   - 连接全局信号
#   - 关卡完成/失败弹窗管理
#   - 证明树和迷雾叠加层切换
#   - 场景切换
#
# Signals:
#   无（监听Autoload信号）
#
# Dependencies:
#   - Autoload: ConservationEngine, GameState, LevelManager, SoundManager
#   - Scenes: main_menu.tscn

extends Node

const HudUtils = preload("res://scripts/hud/hud_utils.gd")

var _construction_canvas: Node3D = null
var _conservation_hud: PanelContainer = null
var _proof_panel: PanelContainer = null
var _tool_panel: PanelContainer = null

# 关卡完成弹窗
var _level_complete_popup: PanelContainer = null
var _level_failed_popup: PanelContainer = null

# 章节过渡
var _chapter_transition: Control = null

# 迷雾叠加层可见性
var _fog_overlay_visible: bool = true
# 调试自动完成模式（命令行 --auto-complete 启用）
var _auto_complete_mode: bool = false


var _i18n = null


func _ready() -> void:
	_i18n = Engine.get_main_loop().root.get_node_or_null("/root/I18nManager")
	if _i18n != null and _i18n.has_signal("language_changed"):
		_i18n.language_changed.connect(_on_language_changed)

	# 检测调试自动完成模式
	for arg in OS.get_cmdline_args():
		if arg == "--auto-complete":
			_auto_complete_mode = true
			GameLogger.info("game", "自动完成模式已启用")

	# 连接全局信号
	ConservationEngine.state_changed.connect(_on_conservation_state_changed)
	GameState.cores_changed.connect(_on_cores_changed)
	LevelManager.level_completed.connect(_on_level_completed)
	LevelManager.level_failed.connect(_on_level_failed)
	LevelManager.goal_updated.connect(_on_goal_updated)
	LevelManager.level_loaded.connect(_on_level_loaded)

	# 自动完成模式：关卡加载后延迟自动完成
	if _auto_complete_mode:
		LevelManager.level_loaded.connect(_on_auto_complete_level)
		# --ca-test 在 main_menu 中先 load_level 再切场景，信号已发出，
		# 这里补一次直接调用，避免错过自动完成
		if LevelManager.current_level_data.size() > 0 and not LevelManager._level_completed:
			_on_auto_complete_level(LevelManager.current_level_data)

	# 缓存子节点引用
	_construction_canvas = get_node_or_null("ConstructionCanvas")
	_conservation_hud = get_node_or_null("HUD/ConservationHUD")
	_proof_panel = get_node_or_null("HUD/ProofPanel")
	_tool_panel = get_node_or_null("HUD/ToolPanel")

	# 连接工具面板信号到构造画布
	if _tool_panel.has_signal("tool_selected") and _construction_canvas.has_method("set_tool"):
		_tool_panel.tool_selected.connect(_construction_canvas.set_tool)
	else:
		push_warning("[游戏] 工具面板或构造画布缺少必要接口")

	# 创建关卡完成/失败弹窗
	_setup_level_popups()

	# 底部操作提示条
	_setup_hint_bar()

	# 加载章节过渡场景
	_chapter_transition = load("res://scenes/hud/chapter_transition.tscn").instantiate()
	call_deferred("add_child", _chapter_transition)
	_chapter_transition.transition_finished.connect(_on_transition_finished)


func _on_language_changed(_locale: String) -> void:
	_setup_level_popups()
	_setup_hint_bar()


var _hint_bar: PanelContainer = null

func _setup_hint_bar() -> void:
	# 切换语言会重建提示条，先把旧的释放掉避免叠在 HUD 下面
	if _hint_bar != null and is_instance_valid(_hint_bar):
		_hint_bar.queue_free()
	_hint_bar = PanelContainer.new()
	_hint_bar.name = "HintBar"
	_hint_bar.anchors_preset = Control.PRESET_CENTER_BOTTOM
	_hint_bar.anchor_left = 0.5
	_hint_bar.anchor_right = 0.5
	_hint_bar.offset_top = -38
	_hint_bar.offset_bottom = -10
	_hint_bar.offset_left = -320
	_hint_bar.offset_right = 320
	_hint_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 应用统一面板样式
	UiAnimator.style_panel(_hint_bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 8)

	var label := Label.new()
	label.name = "HintLabel"
	label.text = _i18n.translate("hud.controls_hint") if _i18n != null else "LMB: Place/Operate | RMB drag: Rotate | Scroll: Zoom | 1-9: Element | P/S/D: Tool | F: Fog | H: Help | ESC: Pause"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", UiAnimator.MUTED)
	margin.add_child(label)
	_hint_bar.add_child(margin)

	# HintBar不拦截鼠标，让点击穿透到3D场景
	HudUtils.set_passthrough(_hint_bar)

	var hud := get_node_or_null("HUD")
	if hud:
		hud.call_deferred("add_child", _hint_bar)
	else:
		call_deferred("add_child", _hint_bar)


func _on_conservation_state_changed(old_state: int, new_state: int) -> void:
	var state_names := []
	if _i18n != null:
		var raw = _i18n.translate("hud.conservation.states")
		state_names = raw.split(",")
	else:
		state_names = ["HEALTHY", "WARNING", "CRITICAL", "DISINTEGRATED"]
	if new_state >= 0 and new_state < state_names.size() and old_state >= 0 and old_state < state_names.size():
		GameLogger.info("ConservationEngine", "[守恒] 状态变化: %s -> %s" % [state_names[old_state], state_names[new_state]])

	# Breach警示音分层递进
	# old=HEALTHY(0), new=WARNING(1) -> LAYER_1
	if old_state == 0 and new_state == 1:
		SoundManager.play_breach_warning(1)
	# old=WARNING(1), new=CRITICAL(2) -> LAYER_2
	elif old_state == 1 and new_state == 2:
		SoundManager.play_breach_warning(2)
	# old=CRITICAL(2), new=DISINTEGRATED(3) -> LAYER_3
	elif old_state == 2 and new_state == 3:
		SoundManager.play_breach_warning(3)


func _on_cores_changed(new_count: int) -> void:
	pass  # HUD会自行更新


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_proof_tree"):
		if _proof_panel:
			_proof_panel.visible = not _proof_panel.visible
	if event.is_action_pressed("toggle_fog"):
		_toggle_fog_overlay()
	# H键重新查看教程
	if event is InputEventKey and event.pressed and event.keycode == KEY_H and not event.ctrl_pressed:
		if not TutorialManager._is_active:
			TutorialManager.replay_tutorial()
	# Enter键: 通关弹窗显示时进入下一关
	if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		if _level_complete_popup and _level_complete_popup.visible:
			_on_next_level_pressed()
			get_viewport().set_input_as_handled()


# 自动完成模式回调：关卡加载后延迟触发完成
func _on_auto_complete_level(_data: Dictionary) -> void:
	# 延迟1秒让关卡场景稳定，再强制完成
	get_tree().create_timer(1.0).timeout.connect(
		func() -> void:
			if is_instance_valid(self) and not LevelManager._level_completed:
				# CA 关卡的目标(如 ca_pattern_reach)依赖实际演化步数，
				# 自动完成模式下没有真实演化，这里强制标记所有目标为完成
				for i in range(LevelManager.goals.size()):
					if LevelManager.goal_states[i] != LevelManager.GoalState.COMPLETED:
						LevelManager.goal_states[i] = LevelManager.GoalState.COMPLETED
						LevelManager.goal_updated.emit(i, LevelManager.GoalState.COMPLETED, 1.0)
				# 验证类目标走正常流程，其余已被强制完成
				LevelManager.verify_goals()
				# 如果验证后还没完成，强制完成
				if not LevelManager._level_completed:
					LevelManager._complete_level()
	)


func _toggle_fog_overlay() -> void:
	# 切换所有迷雾体积的可见性
	_fog_overlay_visible = not _fog_overlay_visible
	if _construction_canvas:
		var effect_mgr = _construction_canvas.get_effect_manager()
		if effect_mgr:
			for fog_vol in effect_mgr.get_fog_volumes():
				if is_instance_valid(fog_vol):
					fog_vol.visible = _fog_overlay_visible
			# 同时切换容器本身的可见性，确保新建迷雾也遵循当前状态
			var container = effect_mgr.fog_container
			if container:
				container.visible = _fog_overlay_visible
	if GameLogger:
		GameLogger.info("game", "迷雾叠加层: %s" % ("显示" if _fog_overlay_visible else "隐藏"))


# ============ 关卡完成/失败弹窗 ============

func _setup_level_popups() -> void:
	# 关卡完成弹窗
	_level_complete_popup = PanelContainer.new()
	_level_complete_popup.name = "LevelCompletePopup"
	_level_complete_popup.anchors_preset = Control.PRESET_CENTER
	_level_complete_popup.offset_left = -200
	_level_complete_popup.offset_top = -120
	_level_complete_popup.offset_right = 200
	_level_complete_popup.offset_bottom = 120
	_level_complete_popup.visible = false
	_level_complete_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiAnimator.style_panel(_level_complete_popup)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)

	var title_label := Label.new()
	title_label.name = "TitleLabel"
	title_label.text = _i18n.translate("level.complete.title") if _i18n != null else "Level Complete!"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 28)
	title_label.add_theme_color_override("font_color", ConservationEngine.get_state_color(0))
	vbox.add_child(title_label)

	var score_label := Label.new()
	score_label.name = "ScoreLabel"
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.add_theme_color_override("font_color", UiAnimator.PAPER)
	vbox.add_child(score_label)

	var cores_label := Label.new()
	cores_label.name = "CoresLabel"
	cores_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cores_label.add_theme_color_override("font_color", UiAnimator.CYAN)
	vbox.add_child(cores_label)

	# 优雅度评分标签（多解创造模式）
	var elegance_label := Label.new()
	elegance_label.name = "EleganceLabel"
	elegance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	elegance_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))  # 金色
	elegance_label.add_theme_font_size_override("font_size", 22)
	elegance_label.visible = false
	vbox.add_child(elegance_label)

	var next_btn := Button.new()
	next_btn.name = "NextLevelButton"
	next_btn.text = _i18n.translate("level.complete.next") if _i18n != null else "Next Level"
	next_btn.set_script(load("res://scripts/hud/button_helper.gd"))
	next_btn.pressed.connect(_on_next_level_pressed)
	vbox.add_child(next_btn)

	var menu_btn := Button.new()
	menu_btn.text = _i18n.translate("level.complete.menu") if _i18n != null else "Return to Menu"
	menu_btn.set_script(load("res://scripts/hud/button_helper.gd"))
	menu_btn.pressed.connect(_on_back_to_menu)
	vbox.add_child(menu_btn)

	_level_complete_popup.add_child(vbox)
	UiAnimator.style_button(next_btn, true)
	UiAnimator.style_button(menu_btn)

	# 关卡失败弹窗
	_level_failed_popup = PanelContainer.new()
	_level_failed_popup.name = "LevelFailedPopup"
	_level_failed_popup.anchors_preset = Control.PRESET_CENTER
	_level_failed_popup.offset_left = -200
	_level_failed_popup.offset_top = -100
	_level_failed_popup.offset_right = 200
	_level_failed_popup.offset_bottom = 100
	_level_failed_popup.visible = false
	_level_failed_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiAnimator.style_panel(_level_failed_popup)

	var vbox2 := VBoxContainer.new()
	vbox2.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox2.add_theme_constant_override("separation", 16)

	var fail_label := Label.new()
	fail_label.name = "FailLabel"
	fail_label.text = _i18n.translate("level.failed.title") if _i18n != null else "Level Failed"
	fail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fail_label.add_theme_font_size_override("font_size", 28)
	fail_label.add_theme_color_override("font_color", ConservationEngine.get_state_color(2))
	vbox2.add_child(fail_label)

	var reason_label := Label.new()
	reason_label.name = "ReasonLabel"
	reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reason_label.add_theme_color_override("font_color", UiAnimator.MUTED)
	vbox2.add_child(reason_label)

	var retry_btn := Button.new()
	retry_btn.text = _i18n.translate("level.failed.retry") if _i18n != null else "Retry"
	retry_btn.set_script(load("res://scripts/hud/button_helper.gd"))
	retry_btn.pressed.connect(_on_retry_pressed)
	vbox2.add_child(retry_btn)

	var menu_btn2 := Button.new()
	menu_btn2.text = _i18n.translate("level.failed.menu") if _i18n != null else "Return to Menu"
	menu_btn2.set_script(load("res://scripts/hud/button_helper.gd"))
	menu_btn2.pressed.connect(_on_back_to_menu)
	vbox2.add_child(menu_btn2)

	_level_failed_popup.add_child(vbox2)
	UiAnimator.style_button(retry_btn, true)
	UiAnimator.style_button(menu_btn2)

	# 挂到HUD下, 延迟添加避免父节点 busy setting up children
	var hud := get_node_or_null("HUD")
	if hud:
		hud.call_deferred("add_child", _level_complete_popup)
		hud.call_deferred("add_child", _level_failed_popup)
	else:
		call_deferred("add_child", _level_complete_popup)
		call_deferred("add_child", _level_failed_popup)


func _on_level_loaded(data: Dictionary) -> void:
	var chapter: int = data.get("chapter", 0)
	var level: int = data.get("level", 0)
	var domain: String = data.get("domain", "")

	# 根据关卡域启动对应音乐和氛围音
	match domain:
		"crystal":
			SoundManager.play_music(SoundManager.MusicStyle.CRYSTAL)
			SoundManager.play_ambience("crystal")
		"fluid":
			SoundManager.play_music(SoundManager.MusicStyle.FLUID)
			SoundManager.play_ambience("fluid")
		"fog":
			SoundManager.play_music(SoundManager.MusicStyle.FOG)
			SoundManager.play_ambience("fog")
		_:
			# 默认启动晶体风格
			SoundManager.play_music(SoundManager.MusicStyle.CRYSTAL)
			SoundManager.play_ambience("crystal")

	# 第一章第一关: 启动新手教程（如果尚未完成）
	if chapter == 1 and level == 1 and not TutorialManager.is_completed() and not _auto_complete_mode:
		# 延迟启动让场景完全加载
		get_tree().create_timer(0.5).timeout.connect(func():
			if is_instance_valid(self):
				TutorialManager.start_tutorial()
		)
	# 更新底部提示条
	var hint: String = data.get("hint", "")
	if hint != "" and _hint_bar:
		var hint_label: Label = _hint_bar.find_child("HintLabel", false, false)
		if hint_label:
			hint_label.text = hint

	# Boss关·盲建：隐藏守恒矩阵HUD，考验直觉
	var constraints: Dictionary = data.get("constraints", {})
	var hide_hud: bool = bool(constraints.get("hide_conservation_hud", false))
	if _conservation_hud:
		_conservation_hud.visible = not hide_hud
	if hide_hud:
		GameLogger.info("game", "[Boss·盲建] 守恒HUD已隐藏")


func _on_level_completed(score: float, cores_earned: int) -> void:
	SoundManager.play(SoundManager.SoundType.PROOF_COMPLETE)

	# 判断是否是最终关卡（Chapter 4 Level 10 Boss），若是则切换到菜单音乐
	var chapter: int = LevelManager.current_level_data.get("chapter", 1)
	var level: int = LevelManager.current_level_data.get("level", 1)
	if chapter == 4 and level == 10:
		SoundManager.crossfade_music(SoundManager.MusicStyle.MENU, 3.0)
	else:
		# 保持当前风格但降低音量作为胜利余韵
		SoundManager.lower_music_volume(-20.0, 2.0)
	SoundManager.stop_ambience()

	if _level_complete_popup:
		_level_complete_popup.visible = true
		_level_complete_popup.mouse_filter = Control.MOUSE_FILTER_STOP
		# ScoreLabel/CoresLabel 是 VBox 的子孙节点，需要递归查找
		var score_label: Label = _level_complete_popup.find_child("ScoreLabel", true, false)
		var cores_label: Label = _level_complete_popup.find_child("CoresLabel", true, false)
		var elegance_label: Label = _level_complete_popup.find_child("EleganceLabel", true, false)
		var next_btn: Button = _level_complete_popup.find_child("NextLevelButton", true, false)
		if score_label:
			score_label.text = _i18n.translate("level.complete.score", {"score": score}) if _i18n != null else "Score: %.1f" % score
		if cores_label:
			cores_label.text = _i18n.translate("level.complete.cores", {"n": cores_earned}) if _i18n != null else "Cores: %d" % cores_earned
		# 优雅度评分显示
		var elegance: float = LevelManager.current_level_data.get("_elegance_score", 0.0)
		var breakdown: Dictionary = LevelManager.current_level_data.get("_elegance_breakdown", {})
		if elegance_label:
			if elegance > 0.0:
				elegance_label.text = "Elegance: %.0f/100" % elegance
				elegance_label.visible = true
			else:
				elegance_label.visible = false
		# 先隐藏下一关按钮，2秒后显示，让玩家欣赏完成画面
		if next_btn:
			next_btn.visible = false
			get_tree().create_timer(2.0).timeout.connect(func():
				if is_instance_valid(next_btn):
					next_btn.visible = true
					UiAnimator.pulse_scale(next_btn, 1.1)
			)
		# 入场动画 + 成功闪光反馈
		UiAnimator.animate_in(_level_complete_popup)
		UiAnimator.flash_success(_level_complete_popup)

	# 显示手记条目
	var journal: String = LevelManager.current_level_data.get("journal_entry", "")
	if journal != "" and _chapter_transition:
		_chapter_transition.play_journal_entry(journal)


func _on_level_failed(reason: String) -> void:
	if LevelManager != null and LevelManager.has_method("set_metric"):
		LevelManager.set_metric("fail_reason", reason)
	# 先播放完全崩解音效，然后停止音乐和氛围音
	SoundManager.play(SoundManager.SoundType.DISINTEGRATE_FULL)
	SoundManager.stop_music(2.0)
	SoundManager.stop_ambience()

	# G2: 使用法医分析报告代替简单弹窗
	var failure_info: Dictionary = ConservationEngine.get_failure_info()
	var failed_row: int = failure_info.get("row", -1)
	var deviation: float = failure_info.get("deviation", 0.0)
	var operation: String = failure_info.get("operation", reason)

	if _construction_canvas and _construction_canvas.has_method("get_effect_manager"):
		var effect_mgr = _construction_canvas.get_effect_manager()
		if effect_mgr:
			effect_mgr.show_forensics_report(failed_row, deviation, operation)
			return

	# 回退: 如果无法获取effect_manager，使用旧弹窗
	SoundManager.play(SoundManager.SoundType.VERIFICATION_FAIL)
	if _level_failed_popup:
		_level_failed_popup.visible = true
		_level_failed_popup.mouse_filter = Control.MOUSE_FILTER_STOP
		var reason_label: Label = _level_failed_popup.find_child("ReasonLabel", false, false)
		if reason_label:
			reason_label.text = reason
		# 入场动画 + 失败抖动反馈
		UiAnimator.animate_in(_level_failed_popup)
		UiAnimator.shake(_level_failed_popup)


func _on_goal_updated(goal_index: int, state: int, progress: float) -> void:
	# 目标状态变化时更新工具面板的目标进度显示
	if _tool_panel and _tool_panel.has_method("update_goal_progress"):
		_tool_panel.update_goal_progress(goal_index, state, progress)


func _on_next_level_pressed() -> void:
	if _level_complete_popup:
		_level_complete_popup.visible = false
		_level_complete_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 加载下一关，自动处理章节过渡
	var chapter: int = LevelManager.current_level_data.get("chapter", 1)
	var level: int = LevelManager.current_level_data.get("level", 1)
	var next_chapter: int = chapter
	var next_level: int = level + 1

	# Chapter 1有14关(含Boss), Chapter 2有13关(含Boss), Chapter 3有12关(含Boss), Chapter 4有10关(含Boss)
	var max_levels := {1: 14, 2: 13, 3: 12, 4: 10}
	if next_level > max_levels.get(chapter, 10):
		next_chapter = chapter + 1
		next_level = 1

	# 章节过渡动画
	if next_chapter > chapter and next_chapter <= 4:
		# 先设置 pending 值，防止 play_transition 同步发射 transition_finished 时 pending 还没赋值
		_pending_next_chapter = next_chapter
		_pending_next_level = next_level
		if _chapter_transition:
			_chapter_transition.play_transition(chapter, next_chapter)
		else:
			_on_transition_finished()
		return
	elif next_chapter > 4:
		# Ch4完成 — 特殊结局
		_pending_next_chapter = -1
		_pending_next_level = -1
		if _chapter_transition:
			_chapter_transition.play_transition(4, -1)
		else:
			_on_transition_finished()
		return

	LevelManager.load_level(next_chapter, next_level)


var _pending_next_chapter: int = -1
var _pending_next_level: int = -1
func _exit_tree() -> void:
	if ConservationEngine != null and ConservationEngine.state_changed.is_connected(_on_conservation_state_changed):
		ConservationEngine.state_changed.disconnect(_on_conservation_state_changed)
	if GameState != null and GameState.cores_changed.is_connected(_on_cores_changed):
		GameState.cores_changed.disconnect(_on_cores_changed)
	if LevelManager != null:
		if LevelManager.level_completed.is_connected(_on_level_completed):
			LevelManager.level_completed.disconnect(_on_level_completed)
		if LevelManager.level_failed.is_connected(_on_level_failed):
			LevelManager.level_failed.disconnect(_on_level_failed)
		if LevelManager.goal_updated.is_connected(_on_goal_updated):
			LevelManager.goal_updated.disconnect(_on_goal_updated)
		if LevelManager.level_loaded.is_connected(_on_level_loaded):
			LevelManager.level_loaded.disconnect(_on_level_loaded)
		if LevelManager.level_loaded.is_connected(_on_auto_complete_level):
			LevelManager.level_loaded.disconnect(_on_auto_complete_level)
	if _chapter_transition != null and _chapter_transition.transition_finished.is_connected(_on_transition_finished):
		_chapter_transition.transition_finished.disconnect(_on_transition_finished)



func _on_transition_finished() -> void:
	if _pending_next_chapter == -1 and _pending_next_level == -1:
		# Ch4完成结局后返回菜单
		UiAnimator.fade_change_scene("res://scenes/main_menu.tscn")
		return
	if _pending_next_chapter > 0 and _pending_next_level > 0:
		LevelManager.load_level(_pending_next_chapter, _pending_next_level)
		_pending_next_chapter = -1
		_pending_next_level = -1


func _on_retry_pressed() -> void:
	if _level_failed_popup:
		_level_failed_popup.visible = false
		_level_failed_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var chapter: int = LevelManager.current_level_data.get("chapter", 1)
	var level: int = LevelManager.current_level_data.get("level", 1)
	if LevelManager != null and LevelManager.has_method("increment_metric"):
		LevelManager.increment_metric("retry_count")
	LevelManager.load_level(chapter, level)


func _on_back_to_menu() -> void:
	if _level_complete_popup:
		_level_complete_popup.visible = false
		_level_complete_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _level_failed_popup:
		_level_failed_popup.visible = false
		_level_failed_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiAnimator.fade_change_scene("res://scenes/main_menu.tscn")
