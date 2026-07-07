extends PanelContainer
var _i18n = null
# AI助手面板 - 右侧滑入，显示提示和守恒诊断

const SLIDE_WIDTH := 360.0
const SLIDE_DURATION := 0.35

var _title_label: Label = null
var _hint_label: RichTextLabel = null
var _status_label: Label = null
var _cost_label: Label = null
var _close_btn: Button = null
var _hint_btn: Button = null

var _typewriter_tween: Tween = null
var _slide_tween: Tween = null
var _full_hint_text: String = ""


func _ready() -> void:
	_i18n = Engine.get_main_loop().root.get_node_or_null("/root/I18nManager")
	if _i18n != null and _i18n.has_signal("language_changed"):
		_i18n.language_changed.connect(_on_language_changed)
	AIAssistant.set_panel(self)
	visible = false
	if get_child_count() > 0:
		_assign_scene_nodes()
	else:
		_build_ui()
	_setup_visuals()

	_refresh_text()
	AIAssistant.hint_delivered.connect(_on_hint_delivered)
	AIAssistant.assistant_unlocked.connect(_on_unlocked)


func _assign_scene_nodes() -> void:
	anchors_preset = Control.PRESET_RIGHT_WIDE
	offset_left = -SLIDE_WIDTH
	offset_right = 0
	custom_minimum_size.x = SLIDE_WIDTH
	var vbox = get_node_or_null("MarginContainer/VBox")
	if vbox == null:
		push_warning("[AI面板] MarginContainer/VBox 节点缺失，回退到 _build_ui")
		_build_ui()
		return
	var title_hbox = vbox.get_node_or_null("TitleHBox")
	if title_hbox == null:
		push_warning("[AI面板] TitleHBox 节点缺失")
		return
	_title_label = title_hbox.get_node_or_null("TitleLabel")
	_close_btn = title_hbox.get_node_or_null("CloseBtn")
	if _close_btn:
		_close_btn.pressed.connect(_on_close)
	_status_label = vbox.get_node_or_null("StatusLabel")
	_hint_label = vbox.get_node_or_null("HintText")
	var bottom_vbox = vbox.get_node_or_null("BottomVBox")
	if bottom_vbox == null:
		push_warning("[AI面板] BottomVBox 节点缺失")
		return
	_cost_label = bottom_vbox.get_node_or_null("CostLabel")
	_hint_btn = bottom_vbox.get_node_or_null("HintBtn")
	if _hint_btn:
		_hint_btn.pressed.connect(_on_request_hint)


func _setup_visuals() -> void:
	UiAnimator.style_panel(self)
	UiAnimator.style_all_buttons(self, ["HintBtn"])
	UiAnimator.attach_button_helpers(self)


func _build_ui() -> void:
	# 锚定到右侧
	anchors_preset = Control.PRESET_RIGHT_WIDE
	offset_left = -SLIDE_WIDTH
	offset_right = 0
	custom_minimum_size.x = SLIDE_WIDTH

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# 标题行
	var title_hbox := HBoxContainer.new()
	vbox.add_child(title_hbox)

	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.text = _i18n.translate("hud.ai.title") if _i18n != null else "AI Assistant"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_font := UiAnimator.make_ui_font(24, true)
	_title_label.add_theme_font_override("font", title_font)
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", UiAnimator.CYAN)
	title_hbox.add_child(_title_label)

	_close_btn = Button.new()
	_close_btn.name = "CloseBtn"
	_close_btn.text = "✕"
	_close_btn.flat = true
	var close_font := UiAnimator.make_ui_font(22, true)
	_close_btn.add_theme_font_override("font", close_font)
	_close_btn.add_theme_font_size_override("font_size", 22)
	_close_btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_close_btn.pressed.connect(_on_close)
	title_hbox.add_child(_close_btn)

	# 目标状态区
	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.text = _i18n.translate("hud.ai.loading") if _i18n != null else "Loading..."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var status_font := UiAnimator.make_ui_font(20, false)
	_status_label.add_theme_font_override("font", status_font)
	_status_label.add_theme_font_size_override("font_size", 20)
	_status_label.add_theme_color_override("font_color", UiAnimator.MUTED)
	vbox.add_child(_status_label)

	# 分隔线
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# 提示文本区
	_hint_label = RichTextLabel.new()
	_hint_label.name = "HintText"
	_hint_label.bbcode_enabled = true
	_hint_label.fit_content = true
	_hint_label.custom_minimum_size = Vector2(0, 80)
	_hint_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var hint_font := UiAnimator.make_ui_font(22, false)
	_hint_label.add_theme_font_override("normal_font", hint_font)
	_hint_label.add_theme_font_size_override("normal_font_size", 22)
	_hint_label.add_theme_color_override("default_color", UiAnimator.PAPER)
	vbox.add_child(_hint_label)

	# 底部操作区
	var bottom_vbox := VBoxContainer.new()
	bottom_vbox.add_theme_constant_override("separation", 8)
	vbox.add_child(bottom_vbox)

	_cost_label = Label.new()
	_cost_label.name = "CostLabel"
	var cost_font := _make_code_font(20, false)
	_cost_label.add_theme_font_override("font", cost_font)
	_cost_label.add_theme_font_size_override("font_size", 20)
	_cost_label.add_theme_color_override("font_color", UiAnimator.MUTED)
	bottom_vbox.add_child(_cost_label)

	_hint_btn = Button.new()
	_hint_btn.name = "HintBtn"
	_hint_btn.text = _i18n.translate("hud.ai.get_hint") if _i18n != null else "Get Hint"
	var btn_font := UiAnimator.make_ui_font(22, true)
	_hint_btn.add_theme_font_override("font", btn_font)
	_hint_btn.add_theme_font_size_override("font_size", 22)
	_hint_btn.pressed.connect(_on_request_hint)
	bottom_vbox.add_child(_hint_btn)


var _ai_update_timer: float = 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	_ai_update_timer += delta
	if _ai_update_timer >= 1.0:
		_ai_update_timer = 0.0
		_update_status()


func slide_in() -> void:
	if _slide_tween:
		_slide_tween.kill()
	_slide_tween = create_tween()
	position.x = SLIDE_WIDTH
	_slide_tween.tween_property(self, "position:x", 0.0, SLIDE_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
	UiAnimator.animate_in(self)
	_update_status()


func slide_out() -> void:
	if _slide_tween:
		_slide_tween.kill()
	_slide_tween = create_tween()
	_slide_tween.tween_property(self, "position:x", SLIDE_WIDTH, SLIDE_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUART)
	UiAnimator.animate_out(self, func(): visible = false)


func _on_close() -> void:
	slide_out()


func _on_request_hint() -> void:
	if not AIAssistant.is_unlocked():
		return
	var hint := AIAssistant.request_hint()
	if not hint.is_empty():
		_show_typewriter(hint)


func _on_hint_delivered(text: String) -> void:
	_show_typewriter(text)


func _on_unlocked() -> void:
	_update_status()


func _show_typewriter(text: String) -> void:
	_full_hint_text = text
	_hint_label.text = ""

	if _typewriter_tween:
		_typewriter_tween.kill()
	_typewriter_tween = create_tween()

	var char_count := text.length()
	for i in range(char_count):
		var idx := i + 1
		_typewriter_tween.tween_callback(_set_hint_text.bind(text.left(idx)))
		_typewriter_tween.tween_interval(0.02)


func _set_hint_text(text: String) -> void:
	_hint_label.text = text


func _update_status() -> void:
	var remaining := AIAssistant.get_hints_remaining()
	var goals := LevelManager.goals
	var goal_states := LevelManager.goal_states

	var completed := 0
	var total := goals.size()
	for state in goal_states:
		if state == LevelManager.GoalState.COMPLETED:
			completed += 1

	_status_label.text = _i18n.translate("hud.ai.status", {"completed": completed, "total": total, "remaining": remaining, "max": AIAssistant.MAX_HINTS_PER_LEVEL})
	_cost_label.text = _i18n.translate("hud.ai.cost", {"cost": AIAssistant.HINT_CORE_COST})

	if remaining <= 0:
		_hint_btn.disabled = true
		_hint_btn.text = _i18n.translate("hud.ai.no_hints")
	else:
		_hint_btn.disabled = false
		_hint_btn.text = _i18n.translate("hud.ai.get_hint")


func _make_code_font(size: int, bold: bool = false) -> Font:
	var sys_font := SystemFont.new()
	sys_font.font_names = PackedStringArray(["JetBrains Mono", "Cascadia Code", "Consolas", "Menlo", "Courier New"])
	sys_font.font_weight = 700 if bold else 400
	sys_font.font_stretch = 100
	# 同上，用 FontVariation 包一层
	var fv := FontVariation.new()
	fv.base_font = sys_font
	fv.variation_embolden = 0.6 if bold else 0.0
	return fv

func _exit_tree() -> void:
	# 面板销毁时清掉 AIAssistant 里的反向引用，避免悬空指针
	if is_instance_valid(AIAssistant):
		AIAssistant.set_panel(null)
	if _i18n != null and _i18n.is_connected("language_changed", _on_language_changed):
		_i18n.language_changed.disconnect(_on_language_changed)
	if AIAssistant != null and AIAssistant.hint_delivered.is_connected(_on_hint_delivered):
		AIAssistant.hint_delivered.disconnect(_on_hint_delivered)
	if AIAssistant != null and AIAssistant.assistant_unlocked.is_connected(_on_unlocked):
		AIAssistant.assistant_unlocked.disconnect(_on_unlocked)

func _on_language_changed(_locale: String) -> void:
	_refresh_text()

func _refresh_text() -> void:
	if _i18n == null:
		return

