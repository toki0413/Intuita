extends PanelContainer
var _i18n = null
# 教程覆盖层 - 底部面板显示教程文字，高亮对应UI区域

const HIGHLIGHT_COLOR := Color(UiAnimator.CYAN, 0.6)
const PANEL_BG := Color(UiAnimator.COLOR_BG_PANEL, 0.88)

var _step_label: Label = null
var _text_label: RichTextLabel = null
var _next_btn: Button = null
var _skip_btn: Button = null
var _highlight_rect: ColorRect = null
var _step_complete_indicator: Label = null

var _tween: Tween = null


func _ready() -> void:
	_i18n = Engine.get_main_loop().root.get_node_or_null("/root/I18nManager")
	if _i18n != null and _i18n.has_signal("language_changed"):
		_i18n.language_changed.connect(_on_language_changed)
	# 注册到管理器
	TutorialManager.set_overlay(self)
	TutorialManager.tutorial_step_changed.connect(_on_step_changed)
	TutorialManager.tutorial_completed.connect(_on_tutorial_done)
	TutorialManager.tutorial_skipped.connect(_on_tutorial_done)

	visible = false
	if get_child_count() > 0:
		_assign_scene_nodes()
	else:
		_build_ui()
	_setup_visuals()


func _exit_tree() -> void:
	if _i18n != null and _i18n.is_connected("language_changed", _on_language_changed):
		_i18n.language_changed.disconnect(_on_language_changed)
	TutorialManager.clear_overlay()
	if TutorialManager.tutorial_step_changed.is_connected(_on_step_changed):
		TutorialManager.tutorial_step_changed.disconnect(_on_step_changed)
	if TutorialManager.tutorial_completed.is_connected(_on_tutorial_done):
		TutorialManager.tutorial_completed.disconnect(_on_tutorial_done)
	if TutorialManager.tutorial_skipped.is_connected(_on_tutorial_done):
		TutorialManager.tutorial_skipped.disconnect(_on_tutorial_done)


func _assign_scene_nodes() -> void:
	var vbox = get_node_or_null("MarginContainer/VBox")
	_step_label = vbox.get_node("StepTitle")
	_text_label = vbox.get_node("TutorialText")
	var bottom_hbox = vbox.get_node("BottomHBox")
	_step_complete_indicator = bottom_hbox.get_node("StepCompleteHint")
	_skip_btn = bottom_hbox.get_node("SkipBtn")
	_skip_btn.pressed.connect(_on_skip)
	_next_btn = bottom_hbox.get_node("NextBtn")
	_next_btn.pressed.connect(_on_next)
	# highlight rect goes on parent CanvasLayer
	_highlight_rect = ColorRect.new()
	_highlight_rect.name = "HighlightRect"
	_highlight_rect.color = Color(0, 0, 0, 0)
	_highlight_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_highlight_rect.z_index = -1
	var canvas_layer := get_parent()
	if canvas_layer and canvas_layer is CanvasLayer:
		canvas_layer.call_deferred("add_child", _highlight_rect)
		canvas_layer.call_deferred("move_child", _highlight_rect, 0)


func _setup_visuals() -> void:
	UiAnimator.style_panel(self)
	UiAnimator.style_all_buttons(self, ["NextBtn"])
	UiAnimator.attach_button_helpers(self)


func _build_ui() -> void:
	# 半透明背景
	self_modulate = Color(1, 1, 1, 0)

	# 锚定到底部
	anchors_preset = Control.PRESET_BOTTOM_WIDE
	offset_top = -160
	offset_bottom = 0

	# 主容器
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# 步骤标题
	_step_label = Label.new()
	_step_label.name = "StepTitle"
	_step_label.add_theme_font_override("font", UiAnimator.make_ui_font(26, true))
	_step_label.add_theme_font_size_override("font_size", 26)
	_step_label.add_theme_color_override("font_color", UiAnimator.CYAN)
	vbox.add_child(_step_label)

	# 教程正文
	_text_label = RichTextLabel.new()
	_text_label.name = "TutorialText"
	_text_label.bbcode_enabled = true
	_text_label.fit_content = true
	_text_label.custom_minimum_size = Vector2(0, 50)
	_text_label.add_theme_font_override("normal_font", UiAnimator.make_ui_font(22, false))
	_text_label.add_theme_font_size_override("normal_font_size", 22)
	_text_label.add_theme_color_override("default_color", UiAnimator.PAPER)
	vbox.add_child(_text_label)

	# 底部按钮行
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_END
	hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(hbox)

	# 步骤完成提示
	_step_complete_indicator = Label.new()
	_step_complete_indicator.name = "StepCompleteHint"
	_step_complete_indicator.add_theme_font_override("font", UiAnimator.make_ui_font(20, false))
	_step_complete_indicator.add_theme_font_size_override("font_size", 20)
	_step_complete_indicator.add_theme_color_override("font_color", UiAnimator.GREEN)
	_step_complete_indicator.text = ""
	_step_complete_indicator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_step_complete_indicator)

	_skip_btn = Button.new()
	_skip_btn.name = "SkipBtn"
	_skip_btn.text = "跳过教程"
	_skip_btn.add_theme_font_override("font", UiAnimator.make_ui_font(20, true))
	_skip_btn.add_theme_font_size_override("font_size", 20)
	_skip_btn.pressed.connect(_on_skip)
	hbox.add_child(_skip_btn)

	_next_btn = Button.new()
	_next_btn.name = "NextBtn"
	_next_btn.text = "下一步"
	_next_btn.add_theme_font_override("font", UiAnimator.make_ui_font(22, true))
	_next_btn.add_theme_font_size_override("font_size", 22)
	_next_btn.pressed.connect(_on_next)
	hbox.add_child(_next_btn)

	# 高亮矩形（全屏覆盖层里）
	_highlight_rect = ColorRect.new()
	_highlight_rect.name = "HighlightRect"
	_highlight_rect.color = Color(0, 0, 0, 0)
	_highlight_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_highlight_rect.z_index = -1
	# 挂到CanvasLayer上而不是自身
	var canvas_layer := get_parent()
	if canvas_layer and canvas_layer is CanvasLayer:
		canvas_layer.call_deferred("add_child", _highlight_rect)
		canvas_layer.call_deferred("move_child", _highlight_rect, 0)


func _on_step_changed(step_index: int) -> void:
	# 教程激活时隐藏底部提示条，避免重叠
	_hide_hint_bar(true)

	# 优先检查域教程
	if TutorialManager.is_domain_active():
		var step_data := TutorialManager.get_domain_step_data()
		if step_data.is_empty():
			return
		visible = true
		_step_label.text = step_data.get("text", "")
		_text_label.text = step_data.get("description", "")
		_step_complete_indicator.text = ""
		_next_btn.text = _i18n.translate("tutorial.next")

		var steps: Array = TutorialManager.DOMAIN_TUTORIALS.get(TutorialManager.get_domain_mode(), [])
		if step_index >= steps.size() - 1:
			_next_btn.text = "开始！"

		_animate_in()
		_update_highlight(step_data.get("highlight", ""))
		return

	# Ch1基础教程
	var step_data := TutorialManager.get_current_step_data()
	if step_data.is_empty():
		return

	visible = true
	_step_label.text = step_data.get("title", "")
	_text_label.text = step_data.get("text", "")
	_step_complete_indicator.text = ""
	_next_btn.text = "下一步"

	# 最后一步改按钮文字
	if step_index >= TutorialManager.STEPS.size() - 1:
		_next_btn.text = "开始游戏！"

	# 滑入动画
	_animate_in()

	# 高亮对应UI
	_update_highlight(step_data.get("highlight", ""))


func _on_tutorial_done() -> void:
	_animate_out()
	# 教程结束后恢复底部提示条
	_hide_hint_bar(false)


# 教程激活时隐藏/恢复底部提示条，避免重叠
func _hide_hint_bar(hide: bool) -> void:
	var game := get_tree().root.get_node_or_null("Game")
	if game == null:
		game = get_tree().root.find_child("Game", true, false)
	if game and game.has_node("HUD/HintBar"):
		var hint_bar: Control = game.get_node("HUD/HintBar")
		if is_instance_valid(hint_bar):
			hint_bar.visible = not hide


func _on_next() -> void:
	if TutorialManager.is_domain_active():
		TutorialManager.advance_domain()
	else:
		TutorialManager.advance()


func _on_skip() -> void:
	if TutorialManager.is_domain_active():
		TutorialManager.skip_domain()
	else:
		TutorialManager.skip()


func mark_step_complete() -> void:
	_step_complete_indicator.text = _i18n.translate("tutorial.step_complete")
	_next_btn.text = _i18n.translate("tutorial.continue")


func _animate_in() -> void:
	UiAnimator.animate_in(self)


func _animate_out() -> void:
	UiAnimator.animate_out(self, func(): visible = false)


func _update_highlight(target_name: String) -> void:
	if not _highlight_rect:
		return

	if target_name.is_empty():
		_highlight_rect.color = Color(0, 0, 0, 0)
		return

	# 在场景树里找目标节点
	var target: Control = _find_hud_node(target_name)
	if not target:
		_highlight_rect.color = Color(0, 0, 0, 0)
		return

	# 计算高亮区域（带边距的发光边框效果）
	var rect := target.get_global_rect()
	rect = rect.grow_individual(-4, -4, 4, 4)
	_highlight_rect.position = rect.position
	_highlight_rect.size = rect.size
	_highlight_rect.color = HIGHLIGHT_COLOR

	# 呼吸动画
	if _tween:
		_tween.kill()
	_tween = create_tween().set_loops()
	_tween.tween_property(_highlight_rect, "color:a", 0.3, 1.0)
	_tween.tween_property(_highlight_rect, "color:a", 0.7, 1.0)


func _find_hud_node(name_hint: String) -> Control:
	# 在场景树中搜索HUD相关节点
	var tree := get_tree()
	if not tree:
		return null

	var nodes := tree.get_nodes_in_group("hud_panels")
	for node in nodes:
		if node.name == name_hint and node is Control:
			return node

	# 回退: 按名称搜索
	var candidates := tree.get_nodes_in_group(name_hint)
	if candidates.size() > 0 and candidates[0] is Control:
		return candidates[0]

	return null

func _on_language_changed(_locale: String) -> void:
	_refresh_text()

func _refresh_text() -> void:
	if _i18n == null:
		return
	if _skip_btn:
		_skip_btn.text = _i18n.translate("tutorial.skip")
	if _next_btn:
		_next_btn.text = _i18n.translate("tutorial.next")
