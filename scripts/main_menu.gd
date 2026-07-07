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
