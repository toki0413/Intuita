# main_menu.gd
# 主菜单控制器 - 处理模式选择和场景切换

extends Control

@onready var _menu_card: Control = $CenterContainer/MenuCard
@onready var _title_label: Label = $CenterContainer/MenuCard/MarginContainer/VBox/Title
@onready var _version_label: Label = $VersionLabel
@onready var _vbox: VBoxContainer = $CenterContainer/MenuCard/MarginContainer/VBox

var _codex_panel: Control = null
var _structure_codex_panel: Control = null
var _evolution_tree_panel: Control = null
var _sandbox_config: Control = null
var _dev_panel: Control = null
var _dev_status_label: Label = null


func _ready() -> void:
	# 自动化测试入口: 命令行传入 --ca-test 直接加载 CA 关卡
	for arg in OS.get_cmdline_args():
		if arg == "--ca-test":
			# 延迟切换场景，避免主菜单节点树还在初始化时报错
			call_deferred("_enter_ca_test")
			return
		if arg == "--start-campaign":
			call_deferred("_start_campaign_direct")
			return

	# 绑定按钮信号
	var btn_specs := [
		{"name": "CampaignBtn", "cb": _on_campaign_pressed},
		{"name": "SandboxBtn", "cb": _on_sandbox_pressed},
		{"name": "ChallengeBtn", "cb": _on_challenge_pressed},
		{"name": "CodexBtn", "cb": _on_codex_pressed},
		{"name": "StructureCodexBtn", "cb": _on_structure_codex_pressed},
		{"name": "EvolutionTreeBtn", "cb": _on_evolution_tree_pressed},
		{"name": "BottomBar/HowToPlayBtn", "cb": _on_how_to_play_pressed},
		{"name": "BottomBar/DevBtn", "cb": _on_dev_pressed},
	]
	for spec in btn_specs:
		var btn := _vbox.get_node_or_null(spec["name"])
		if btn:
			btn.pressed.connect(spec["cb"])
		else:
			push_warning("[主菜单] 按钮不存在: %s" % spec["name"])

	var quit_btn := _vbox.get_node_or_null("BottomBar/QuitBtn")
	if quit_btn:
		quit_btn.pressed.connect(_on_quit_pressed)

	# 为所有按钮添加标准反馈（缩放 + 音效）
	_setup_button_feedback(_vbox)

	# 应用新设计系统样式
	UiAnimator.style_panel(_menu_card)
	UiAnimator.style_all_buttons(_vbox, ["CampaignBtn"])
	if _title_label:
		_title_label.add_theme_font_size_override("font_size", 48)
		_title_label.add_theme_color_override("font_color", UiAnimator.PAPER)

	# 动态读取版本号
	if _version_label:
		_version_label.text = "v" + ProjectSettings.get_setting("application/config/version", "0.1.0")
		_version_label.add_theme_color_override("font_color", UiAnimator.MUTED)

	# 播放主菜单背景音乐
	SoundManager.play_music(SoundManager.MusicStyle.MENU)

	# 入场动画
	_animate_entrance()

	# 加载图鉴面板
	_load_codex_panel()
	_load_structure_codex_panel()
	_load_evolution_tree_panel()

	# 预加载沙盒配置面板
	_load_sandbox_config()


func _enter_ca_test() -> void:
	GameState.set_mode(GameState.GameMode.CAMPAIGN)
	LevelManager.load_level(4, 6)
	UiAnimator.fade_change_scene("res://scenes/game.tscn")

func _start_campaign_direct() -> void:
	GameState.set_mode(GameState.GameMode.CAMPAIGN)
	LevelManager.load_level(1, 1)
	UiAnimator.fade_change_scene("res://scenes/game.tscn")


func _setup_button_feedback(container: Node) -> void:
	for child in container.get_children():
		if child is Button and child.get_script() == null:
			child.set_script(load("res://scripts/hud/button_helper.gd"))
		if child is Container:
			_setup_button_feedback(child)


func _animate_entrance() -> void:
	_menu_card.modulate.a = 0.0
	_menu_card.position.y += 40
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_menu_card, "modulate:a", 1.0, 0.7)
	tween.parallel().tween_property(_menu_card, "position:y", _menu_card.position.y - 40, 0.7)

	# 标题发光闪烁
	if _title_label:
		_title_label.add_theme_color_override("font_color", UiAnimator.CYAN)
		tween.tween_property(_title_label, "modulate", Color(1, 1, 1, 1), 0.3)


func _on_campaign_pressed() -> void:
	GameState.set_mode(GameState.GameMode.CAMPAIGN)
	LevelManager.load_level(1, 1)
	_start_game()


func _on_how_to_play_pressed() -> void:
	# 重置教程状态，确保进入游戏后能看到新手引导
	TutorialManager.reset_tutorial_progress()
	GameState.set_mode(GameState.GameMode.CAMPAIGN)
	LevelManager.load_level(1, 1)
	_start_game()


func _on_sandbox_pressed() -> void:
	if _sandbox_config:
		_sandbox_config.visible = true
		UiAnimator.animate_in(_sandbox_config)


func _on_challenge_pressed() -> void:
	GameState.set_mode(GameState.GameMode.CHALLENGE)
	DailyChallenge.load_today_challenge()
	LevelManager.load_level(-2, DailyChallenge.get_today_seed())
	_start_game()


func _start_game() -> void:
	UiAnimator.fade_change_scene("res://scenes/game.tscn")


func _on_codex_pressed() -> void:
	if _codex_panel:
		_codex_panel.show_codex()


func _on_structure_codex_pressed() -> void:
	if _structure_codex_panel:
		_structure_codex_panel.show_panel()


func _on_evolution_tree_pressed() -> void:
	if _evolution_tree_panel:
		_evolution_tree_panel.show_panel()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _load_codex_panel() -> void:
	var scene := load("res://scenes/hud/codex_panel.tscn")
	if scene:
		_codex_panel = scene.instantiate()
		add_child(_codex_panel)


func _load_structure_codex_panel() -> void:
	# 纯代码构建，无需 .tscn
	var script := load("res://scripts/hud/structure_codex_panel.gd")
	_structure_codex_panel = Control.new()
	_structure_codex_panel.set_script(script)
	add_child(_structure_codex_panel)


func _load_evolution_tree_panel() -> void:
	var script := load("res://scripts/hud/evolution_tree_panel.gd")
	_evolution_tree_panel = Control.new()
	_evolution_tree_panel.set_script(script)
	add_child(_evolution_tree_panel)


func _load_sandbox_config() -> void:
	var scene := load("res://scenes/hud/sandbox_config.tscn")
	if scene:
		_sandbox_config = scene.instantiate()
		_sandbox_config.visible = false
		add_child(_sandbox_config)


# ============ 开发者选项 ============

func _on_dev_pressed() -> void:
	if _dev_panel == null:
		_build_dev_panel()
	if _dev_panel:
		_dev_panel.visible = true
		UiAnimator.animate_in(_dev_panel)


func _build_dev_panel() -> void:
	# 纯代码构建，和 structure_codex_panel / evolution_tree_panel 一致
	var panel := Control.new()
	panel.name = "DevPanel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# 半透明遮罩
	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)

	var card := PanelContainer.new()
	card.name = "Card"
	card.custom_minimum_size = Vector2(520, 420)
	card.add_theme_stylebox_override("panel", _make_card_style())
	center.add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "开发者选项"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", UiAnimator.CYAN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var unlock_btn := Button.new()
	unlock_btn.text = "解锁全部内容（速通）"
	unlock_btn.custom_minimum_size = Vector2(0, 56)
	unlock_btn.add_theme_font_size_override("font_size", 22)
	unlock_btn.pressed.connect(_on_unlock_all_pressed)
	vbox.add_child(unlock_btn)

	vbox.add_child(HSeparator.new())

	var hint := Label.new()
	hint.text = "关卡跳转 — 选择章节和关卡后开始游戏"
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", UiAnimator.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	# 关卡跳转: 章节下拉 + 关卡下拉
	var jump_row := HBoxContainer.new()
	jump_row.alignment = BoxContainer.ALIGNMENT_CENTER
	jump_row.add_theme_constant_override("separation", 16)
	vbox.add_child(jump_row)

	var ch_label := Label.new()
	ch_label.text = "章节"
	ch_label.add_theme_font_size_override("font_size", 20)
	jump_row.add_child(ch_label)

	var chapter_option := OptionButton.new()
	chapter_option.name = "ChapterOption"
	chapter_option.custom_minimum_size = Vector2(120, 44)
	jump_row.add_child(chapter_option)

	var lv_label := Label.new()
	lv_label.text = "关卡"
	lv_label.add_theme_font_size_override("font_size", 20)
	jump_row.add_child(lv_label)

	var level_option := OptionButton.new()
	level_option.name = "LevelOption"
	level_option.custom_minimum_size = Vector2(120, 44)
	jump_row.add_child(level_option)

	# 填充章节列表
	var loader = _get_level_loader()
	var chapters: Array[int] = []
	if loader:
		chapters = loader.list_chapters()
	for ch in chapters:
		chapter_option.add_item("第%d章" % ch, ch)
	chapter_option.item_selected.connect(func(idx): _populate_levels(level_option, chapter_option.get_item_id(idx)))
	if chapters.size() > 0:
		chapter_option.select(0)
		_populate_levels(level_option, chapters[0])

	var jump_btn := Button.new()
	jump_btn.text = "跳转到所选关卡"
	jump_btn.custom_minimum_size = Vector2(0, 50)
	jump_btn.add_theme_font_size_override("font_size", 20)
	jump_btn.pressed.connect(_on_jump_pressed.bind(chapter_option, level_option))
	vbox.add_child(jump_btn)

	vbox.add_child(HSeparator.new())

	var status_label := Label.new()
	status_label.name = "StatusLabel"
	status_label.text = ""
	status_label.add_theme_font_size_override("font_size", 18)
	status_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_label)
	_dev_status_label = status_label

	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.custom_minimum_size = Vector2(0, 44)
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.pressed.connect(func(): _dev_panel.visible = false)
	vbox.add_child(close_btn)

	add_child(panel)
	_dev_panel = panel
	UiAnimator.style_panel(card)
	_setup_button_feedback(vbox)


func _make_card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.047, 0.055, 0.078, 0.92)
	style.border_color = Color(0, 0.831, 1, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(24)
	style.shadow_color = Color(0, 0.831, 1, 0.2)
	style.shadow_size = 24
	style.shadow_offset = Vector2(0, 8)
	return style


func _get_level_loader():
	# LevelDataLoader 是 autoload，直接取
	return get_node_or_null("/root/LevelDataLoader")


func _populate_levels(level_option: OptionButton, chapter: int) -> void:
	level_option.clear()
	var loader = _get_level_loader()
	if not loader:
		return
	var levels: Array[int] = loader.list_levels(chapter)
	for lv in levels:
		level_option.add_item("第%d关" % lv, lv)
	if levels.size() > 0:
		level_option.select(0)


func _on_unlock_all_pressed() -> void:
	var loader = _get_level_loader()
	if not loader:
		_set_dev_status("错误: 关卡加载器不可用", Color(0.9, 0.3, 0.3))
		return

	# 标记全部关卡为已完成
	var count := 0
	for ch in loader.list_chapters():
		for lv in loader.list_levels(ch):
			GameState.mark_level_completed(ch, lv)
			count += 1

	# 给足核心和进化点
	GameState.gain_cores(9999)
	GameState.evolve_points = 9999

	# 解锁 AI 助手
	if is_instance_valid(AIAssistant) and AIAssistant.has_method("set_unlocked"):
		AIAssistant.set_unlocked(true)
		AIAssistant.assistant_unlocked.emit()

	# 存档
	if is_instance_valid(SaveManager) and SaveManager.has_method("save_game"):
		SaveManager.save_game()

	_set_dev_status("已解锁 %d 个关卡 + 9999 核心 + AI助手" % count, Color(0.4, 0.9, 0.5))


func _on_jump_pressed(chapter_option: OptionButton, level_option: OptionButton) -> void:
	var ch := chapter_option.get_item_id(chapter_option.selected)
	var lv := level_option.get_item_id(level_option.selected)
	if ch <= 0 or lv <= 0:
		_set_dev_status("请先选择章节和关卡", Color(0.9, 0.3, 0.3))
		return
	GameState.set_mode(GameState.GameMode.CAMPAIGN)
	LevelManager.load_level(ch, lv)
	_start_game()


func _set_dev_status(text: String, color: Color) -> void:
	if _dev_status_label:
		_dev_status_label.text = text
		_dev_status_label.add_theme_color_override("font_color", color)
