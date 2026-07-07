# chapter_transition.gd
# 章节过渡动画 - 全屏覆盖层，手写风格科学手记
# 深色背景+网格纸纹理，逐字打字机效果
#
# Responsibilities:
#   - 章节过渡动画播放
#   - 打字机效果文本逐行显示
#   - "继续"按钮出现
#   - 关卡完成时显示手记条目
#
# Dependencies:
#   - Autoload: SoundManager

extends Control

var _i18n = null
signal transition_finished()

# 章节过渡文本（双语：中文 + 英文交替）
const CHAPTER_TRANSITIONS: Dictionary = {
	"1_to_2": [
		"第47天。晶体已经稳定了。",
		"Day 47. The crystals are stable now.",
		"每个原子各就其位，每条键都有交代。",
		"Each atom in its place, each bond accounted for.",
		"但晶体不会动。它们不会改变。",
		"But crystals don't move. They don't change.",
		"真正的问题不是\"是什么\"——而是\"什么在流动\"。",
		"The real question isn't 'what IS' — it's 'what FLOWS'.",
		"明天，我打开通道。",
		"Tomorrow, I open the channels.",
	],
	"2_to_3": [
		"第112天。离子流动，边界守恒。",
		"Day 112. The ions flow, the boundaries hold.",
		"但没有目的的流动只是混沌。",
		"But flow without purpose is just chaos.",
		"催化剂选择路径。电池储存意志。",
		"A catalyst chooses its path. A battery stores its will.",
		"最后一个问题：我能否\"创造\"，而不只是\"发现\"？",
		"The final question: can I CREATE, not just discover?",
		"火焰，现在点燃。",
		"The fire starts now.",
	],
	"3_to_4": [
		"第256天。材料已被锻造，规则已被书写。",
		"Day 256. Materials forged, rules written.",
		"但规则的尽头，是涌现的起点。",
		"But at the end of rules lies the beginning of emergence.",
		"一个细胞活着。两个细胞对话。无数细胞——进化。",
		"One cell lives. Two cells converse. Countless cells—evolve.",
		"我不再构造静态的结构。我培育动态的生命。",
		"I no longer build static structures. I breed dynamic life.",
		"让混沌涌动，看秩序自生。",
		"Let chaos churn, and watch order self-arise.",
	],
	"4_ending": [
		"存在即被构造。",
		"To exist is to be constructed.",
		"你建造的不只是一个结构——",
		"What you built was not just a structure—",
		"它是一个证明。一个存在性证明。",
		"it was a proof. An existence proof.",
		"你是创造的主体。",
		"You are the creative subject.",
		"直觉主义不是限制。",
		"Intuitionism is not a limitation.",
		"它是解放。",
		"It is a liberation.",
	],
}

var _char_timer: Timer = null
var _current_lines: Array = []
var _current_line_idx: int = 0
var _current_char_idx: int = 0
var _text_labels: Array[RichTextLabel] = []
var _continue_btn: Button = null
var _is_playing: bool = false
var _char_delay: float = 0.05  # 每字符延迟


func _ready() -> void:
	_i18n = Engine.get_main_loop().root.get_node_or_null("/root/I18nManager")
	if _i18n != null and _i18n.has_signal("language_changed"):
		_i18n.language_changed.connect(_on_language_changed)
	anchors_preset = Control.PRESET_FULL_RECT
	visible = false
	if get_child_count() > 0:
		_assign_scene_nodes()
	else:
		_build_ui()
	_refresh_text()
	_setup_visuals()


func _exit_tree() -> void:
	if _i18n != null and _i18n.is_connected("language_changed", _on_language_changed):
		_i18n.language_changed.disconnect(_on_language_changed)


func _setup_visuals() -> void:
	# 继续按钮添加统一反馈
	if _continue_btn and _continue_btn.get_script() == null:
		_continue_btn.set_script(load("res://scripts/hud/button_helper.gd"))
	UiAnimator.style_button(_continue_btn, true)


func _assign_scene_nodes() -> void:
	var grid_overlay = get_node_or_null("GridOverlay")
	grid_overlay.draw.connect(_draw_grid.bind(grid_overlay))
	var text_vbox = get_node_or_null("TextMargin/TextVBox")
	_text_labels.clear()
	# 双语叙事最多10行，尝试加载12个标签（不足则动态创建补齐）
	for i in range(12):
		var label = text_vbox.get_node_or_null("Line%d" % i)
		if label == null:
			# 场景中没有足够标签，动态创建
			label = RichTextLabel.new()
			label.bbcode_enabled = true
			label.fit_content = true
			label.scroll_active = false
			label.custom_minimum_size = Vector2(0, 36)
			label.add_theme_font_size_override("normal_font_size", 24)
			label.add_theme_color_override("default_color", Color(UiAnimator.PAPER, 0.0))
			label.add_theme_font_override("normal_font", UiAnimator.make_ui_font(24, true))
			text_vbox.add_child(label)
		label.visible = false
		label.text = ""
		_text_labels.append(label)
	_continue_btn = get_node_or_null("ContinueBtn")
	_continue_btn.visible = false
	_continue_btn.pressed.connect(_on_continue_pressed)
	_char_timer = get_node_or_null("CharTimer")
	_char_timer.timeout.connect(_on_char_tick)


func _build_ui() -> void:
	# 深色背景
	var bg := ColorRect.new()
	bg.color = Color(UiAnimator.COLOR_BG_DEEP, 0.97)
	bg.anchors_preset = Control.PRESET_FULL_RECT
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# 网格纸纹理 — 用线条模拟
	var grid := Control.new()
	grid.anchors_preset = Control.PRESET_FULL_RECT
	# 直接画线，不重复挂脚本
	grid.draw.connect(_draw_grid.bind(grid))
	add_child(grid)

	# 文本容器
	var text_margin := MarginContainer.new()
	text_margin.add_theme_constant_override("margin_left", 120)
	text_margin.add_theme_constant_override("margin_top", 100)
	text_margin.add_theme_constant_override("margin_right", 120)
	text_margin.add_theme_constant_override("margin_bottom", 100)
	text_margin.anchors_preset = Control.PRESET_FULL_RECT
	add_child(text_margin)

	var text_vbox := VBoxContainer.new()
	text_vbox.add_theme_constant_override("separation", 24)
	text_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_margin.add_child(text_vbox)

	# 预创建12行文本标签（双语叙事最多10行，留2行余量）
	for i in range(12):
		var label := RichTextLabel.new()
		label.bbcode_enabled = true
		label.fit_content = true
		label.scroll_active = false
		label.custom_minimum_size = Vector2(0, 36)
		label.add_theme_font_size_override("normal_font_size", 24)
		label.add_theme_color_override("default_color", Color(UiAnimator.PAPER, 0.0))
		label.visible = false
		label.add_theme_font_override("normal_font", UiAnimator.make_ui_font(24, true))
		text_vbox.add_child(label)
		_text_labels.append(label)

	# 继续按钮
	_continue_btn = Button.new()
	_continue_btn.text = "Continue"
	_continue_btn.add_theme_font_override("font", UiAnimator.make_ui_font(24, true))
	_continue_btn.add_theme_font_size_override("font_size", 24)
	_continue_btn.add_theme_color_override("font_color", Color(0.7, 0.85, 0.95))
	_continue_btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	_continue_btn.custom_minimum_size = Vector2(200, 50)
	_continue_btn.position = Vector2(get_viewport_rect().size.x / 2.0 - 100, get_viewport_rect().size.y - 100)
	_continue_btn.visible = false
	_continue_btn.pressed.connect(_on_continue_pressed)
	add_child(_continue_btn)

	# 打字机定时器
	_char_timer = Timer.new()
	_char_timer.one_shot = false
	_char_timer.wait_time = _char_delay
	_char_timer.timeout.connect(_on_char_tick)
	add_child(_char_timer)


func _draw_grid(control: Control) -> void:
	# 绘制淡色网格线 — 模拟方格纸
	var color := Color(0.12, 0.12, 0.18, 0.3)
	var spacing := 40.0
	var size := control.size
	for x in range(0, int(size.x), int(spacing)):
		control.draw_line(Vector2(x, 0), Vector2(x, size.y), color, 1.0)
	for y in range(0, int(size.y), int(spacing)):
		control.draw_line(Vector2(0, y), Vector2(size.x, y), color, 1.0)


func play_transition(from_chapter: int, to_chapter: int) -> void:
	var key := ""
	if to_chapter == -1:
		# Ch4完成特殊结局（4章制）
		key = "4_ending"
	else:
		key = "%d_to_%d" % [from_chapter, to_chapter]

	if not CHAPTER_TRANSITIONS.has(key):
		transition_finished.emit()
		return

	_current_lines = CHAPTER_TRANSITIONS[key]
	_current_line_idx = 0
	_current_char_idx = 0
	_is_playing = true
	visible = true

	# 重置所有标签
	for label in _text_labels:
		label.visible = false
		label.text = ""
		label.add_theme_color_override("default_color", Color(UiAnimator.PAPER, 0.0))

	_continue_btn.visible = false
	SoundManager.play(SoundManager.SoundType.CHAPTER_TRANSITION)
	UiAnimator.animate_in(self)
	_char_timer.start()


func play_journal_entry(entry_text: String) -> void:
	# 简短手记条目 — 在关卡完成弹窗中显示
	_current_lines = [entry_text]
	_current_line_idx = 0
	_current_char_idx = 0
	_is_playing = true
	visible = true

	for label in _text_labels:
		label.visible = false
		label.text = ""
		label.add_theme_color_override("default_color", Color(UiAnimator.PAPER, 0.0))

	_continue_btn.visible = false
	SoundManager.play(SoundManager.SoundType.JOURNAL_ENTRY)
	UiAnimator.animate_in(self)
	_char_timer.start()


func _on_char_tick() -> void:
	if _current_line_idx >= _current_lines.size():
		_char_timer.stop()
		_show_continue()
		return

	var line: String = _current_lines[_current_line_idx]
	var label: RichTextLabel = _text_labels[_current_line_idx]
	label.visible = true

	if _current_char_idx == 0:
		# 新行开始 — 淡入
		label.add_theme_color_override("default_color", Color(UiAnimator.PAPER, 1.0))

	_current_char_idx += 1
	var visible_text: String = line.substr(0, _current_char_idx)
	label.text = visible_text

	if _current_char_idx >= line.length():
		# 当前行完成
		_current_line_idx += 1
		_current_char_idx = 0


func _show_continue() -> void:
	_is_playing = false
	_continue_btn.visible = true
	_continue_btn.position = Vector2(get_viewport_rect().size.x / 2.0 - 100, get_viewport_rect().size.y - 100)

	# 淡入按钮
	var tween := create_tween()
	_continue_btn.modulate.a = 0.0
	tween.tween_property(_continue_btn, "modulate:a", 1.0, 0.5)


func _on_continue_pressed() -> void:
	UiAnimator.animate_out(self, func() -> void:
		visible = false
		modulate.a = 1.0
		transition_finished.emit()
	)


func _on_language_changed(_locale: String) -> void:
	_refresh_text()

func _refresh_text() -> void:
	if _i18n == null:
		return
	if _continue_btn:
		_continue_btn.text = _i18n.translate("hud.continue")
