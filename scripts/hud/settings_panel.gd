# settings_panel.gd
# 设置面板 - 图形/音频/游戏/控制/LLM标签页
#
# Responsibilities:
#   - 分标签页显示和编辑设置
#   - 实时预览设置变更
#   - 重置到默认值
#
# Dependencies:
#   - Autoload: SettingsManager, I18nManager, LLMBridge

extends Control

var _tab_container: TabContainer
var _font_normal: SystemFont
var _font_mono: SystemFont


func _ready() -> void:
	_init_fonts()
	if get_child_count() > 0:
		_assign_scene_nodes()
	else:
		_build_ui()
	_setup_visuals()
	_load_current_settings()
	SettingsManager.setting_changed.connect(_on_setting_changed)
	I18nManager.language_changed.connect(_on_language_changed)


func _assign_scene_nodes() -> void:
	_tab_container = get_node_or_null("VBox/TabContainer")
	if _tab_container == null:
		push_warning("[设置] TabContainer 节点缺失，回退到 _build_ui")
		_build_ui()
		return
	_tab_container.add_theme_font_override("font", _font_normal)
	_tab_container.add_theme_font_size_override("font_size", 22)
	# remove placeholder tab children so _build_*_tab can create proper ones
	for child in _tab_container.get_children():
		child.queue_free()
	# populate tabs with dynamic content
	_build_graphics_tab()
	_build_audio_tab()
	_build_gameplay_tab()
	_build_controls_tab()
	_build_llm_tab()
	var bottom_hbox = get_node_or_null("VBox/BottomHBox")
	if bottom_hbox == null:
		push_warning("[设置] BottomHBox 节点缺失")
		return
	var reset_btn: Button = bottom_hbox.get_node_or_null("ResetBtn")
	if reset_btn:
		reset_btn.pressed.connect(_on_reset_pressed)
	var close_btn: Button = bottom_hbox.get_node_or_null("CloseBtn")
	if close_btn:
		close_btn.pressed.connect(_on_close_pressed)


func _setup_visuals() -> void:
	# 样式化所有嵌套面板
	UiAnimator.style_all_panels(self)
	# 统一按钮样式和反馈
	UiAnimator.style_all_buttons(self)
	UiAnimator.attach_button_helpers(self)
	UiAnimator.animate_in(self)


func _init_fonts() -> void:
	_font_normal = SystemFont.new()
	_font_normal.font_names = PackedStringArray(["Arial", "Segoe UI"])
	_font_normal.font_weight = 700
	_font_normal.font_size = 22

	_font_mono = SystemFont.new()
	_font_mono.font_names = PackedStringArray(["Cascadia Code", "Consolas"])
	_font_mono.font_size = 20


func _build_ui() -> void:
	# 主容器
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	add_child(vbox)

	# 标题
	var title := Label.new()
	title.text = I18nManager.translate("menu.settings")
	title.add_theme_font_override("font", _font_normal)
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# 标签容器
	_tab_container = TabContainer.new()
	_tab_container.add_theme_font_override("font", _font_normal)
	_tab_container.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_tab_container)
	_tab_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_build_graphics_tab()
	_build_audio_tab()
	_build_gameplay_tab()
	_build_controls_tab()
	_build_llm_tab()

	# 底部按钮
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var reset_btn := Button.new()
	reset_btn.text = "Reset to Defaults"
	reset_btn.add_theme_font_override("font", _font_normal)
	reset_btn.add_theme_font_size_override("font_size", 22)
	reset_btn.pressed.connect(_on_reset_pressed)
	hbox.add_child(reset_btn)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.add_theme_font_override("font", _font_normal)
	close_btn.add_theme_font_size_override("font_size", 22)
	close_btn.pressed.connect(_on_close_pressed)
	hbox.add_child(close_btn)


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _font_normal)
	label.add_theme_font_size_override("font_size", 22)
	return label


func _make_check(text: String, pressed: bool) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = text
	cb.button_pressed = pressed
	cb.add_theme_font_override("font", _font_normal)
	cb.add_theme_font_size_override("font_size", 22)
	return cb


func _make_slider(min_val: float, max_val: float, step: float, value: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step
	slider.value = value
	slider.custom_minimum_size.x = 200
	return slider


func _make_option(items: Array, selected: int) -> OptionButton:
	var btn := OptionButton.new()
	btn.add_theme_font_override("font", _font_normal)
	btn.add_theme_font_size_override("font_size", 22)
	for i in range(items.size()):
		btn.add_item(str(items[i]))
		if i == selected:
			btn.selected = i
	return btn


func _make_line_edit(text: String, placeholder: String = "") -> LineEdit:
	var le := LineEdit.new()
	le.text = text
	le.placeholder_text = placeholder
	le.add_theme_font_override("font", _font_mono)
	le.add_theme_font_size_override("font_size", 20)
	le.custom_minimum_size.x = 300
	return le


func _make_spinbox(min_val: int, max_val: int, value: int) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = min_val
	sb.max_value = max_val
	sb.value = value
	sb.add_theme_font_override("font", _font_mono)
	sb.add_theme_font_size_override("font_size", 20)
	return sb


# ============ 图形标签 ============

func _build_graphics_tab() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_tab_container.add_child(vbox)
	_tab_container.set_tab_title(0, I18nManager.translate("settings.graphics"))

	# 全屏
	var fullscreen_cb := _make_check("Fullscreen", SettingsManager.get_setting("fullscreen", false))
	fullscreen_cb.toggled.connect(func(v): SettingsManager.set_setting("fullscreen", v))
	vbox.add_child(fullscreen_cb)

	# VSync
	var vsync_cb := _make_check("VSync", SettingsManager.get_setting("vsync", true))
	vsync_cb.toggled.connect(func(v): SettingsManager.set_setting("vsync", v))
	vbox.add_child(vsync_cb)

	# 抗锯齿
	var aa_hbox := HBoxContainer.new()
	aa_hbox.add_child(_make_label("Anti-Aliasing:"))
	var aa_opt := _make_option(["Off", "MSAA 2x", "MSAA 4x"], SettingsManager.get_setting("anti_aliasing", 0))
	aa_opt.item_selected.connect(func(i):
		var vals := [0, 2, 4]
		SettingsManager.set_setting("anti_aliasing", vals[i])
	)
	aa_hbox.add_child(aa_opt)
	vbox.add_child(aa_hbox)

	# 迷雾质量
	var fog_hbox := HBoxContainer.new()
	fog_hbox.add_child(_make_label("Fog Quality:"))
	var fog_opt := _make_option(["Off", "Low", "High"], SettingsManager.get_setting("fog_quality", 2))
	fog_opt.item_selected.connect(func(i): SettingsManager.set_setting("fog_quality", i))
	fog_hbox.add_child(fog_opt)
	vbox.add_child(fog_hbox)

	# 粒子质量
	var part_hbox := HBoxContainer.new()
	part_hbox.add_child(_make_label("Particle Quality:"))
	var part_opt := _make_option(["Off", "Low", "High"], SettingsManager.get_setting("particle_quality", 2))
	part_opt.item_selected.connect(func(i): SettingsManager.set_setting("particle_quality", i))
	part_hbox.add_child(part_opt)
	vbox.add_child(part_hbox)

	# 应用按钮
	var apply_btn := Button.new()
	apply_btn.text = "Apply Graphics"
	apply_btn.add_theme_font_override("font", _font_normal)
	apply_btn.add_theme_font_size_override("font_size", 22)
	apply_btn.pressed.connect(func(): SettingsManager.apply_graphics_settings())
	vbox.add_child(apply_btn)


# ============ 音频标签 ============

func _build_audio_tab() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_tab_container.add_child(vbox)
	_tab_container.set_tab_title(1, I18nManager.translate("settings.audio"))

	# 主音量
	vbox.add_child(_make_label("Master Volume:"))
	var master_slider := _make_slider(0.0, 1.0, 0.05, SettingsManager.get_setting("master_volume", 0.8))
	master_slider.value_changed.connect(func(v): SettingsManager.set_setting("master_volume", v))
	vbox.add_child(master_slider)

	# 音效
	vbox.add_child(_make_label("SFX Volume:"))
	var sfx_slider := _make_slider(0.0, 1.0, 0.05, SettingsManager.get_setting("sfx_volume", 1.0))
	sfx_slider.value_changed.connect(func(v): SettingsManager.set_setting("sfx_volume", v))
	vbox.add_child(sfx_slider)

	# 音乐
	vbox.add_child(_make_label("Music Volume:"))
	var music_slider := _make_slider(0.0, 1.0, 0.05, SettingsManager.get_setting("music_volume", 0.5))
	music_slider.value_changed.connect(func(v): SettingsManager.set_setting("music_volume", v))
	vbox.add_child(music_slider)

	# 应用按钮
	var apply_btn := Button.new()
	apply_btn.text = "Apply Audio"
	apply_btn.add_theme_font_override("font", _font_normal)
	apply_btn.add_theme_font_size_override("font_size", 22)
	apply_btn.pressed.connect(func(): SettingsManager.apply_audio_settings())
	vbox.add_child(apply_btn)


# ============ 游戏标签 ============

func _build_gameplay_tab() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_tab_container.add_child(vbox)
	_tab_container.set_tab_title(2, I18nManager.translate("settings.gameplay"))

	# 教程
	var tut_cb := _make_check("Tutorial", SettingsManager.get_setting("tutorial_enabled", true))
	tut_cb.toggled.connect(func(v): SettingsManager.set_setting("tutorial_enabled", v))
	vbox.add_child(tut_cb)

	# 重看教程按钮
	var replay_btn := Button.new()
	replay_btn.text = "Replay Tutorial"
	replay_btn.add_theme_font_override("font", _font_normal)
	replay_btn.add_theme_font_size_override("font_size", 22)
	replay_btn.pressed.connect(_on_replay_tutorial_pressed)
	vbox.add_child(replay_btn)

	# 提示
	var hints_cb := _make_check("Hints", SettingsManager.get_setting("hints_enabled", true))
	hints_cb.toggled.connect(func(v): SettingsManager.set_setting("hints_enabled", v))
	vbox.add_child(hints_cb)

	# 自动保存间隔
	var autosave_hbox := HBoxContainer.new()
	autosave_hbox.add_child(_make_label("Auto-Save Interval (s):"))
	var autosave_spin := _make_spinbox(30, 600, SettingsManager.get_setting("auto_save_interval", 120))
	autosave_spin.value_changed.connect(func(v): SettingsManager.set_setting("auto_save_interval", int(v)))
	autosave_hbox.add_child(autosave_spin)
	vbox.add_child(autosave_hbox)

	# 迷雾强度（光敏性）
	vbox.add_child(_make_label("Fog Intensity (photosensitivity):"))
	var fog_slider := _make_slider(0.0, 1.0, 0.1, SettingsManager.get_setting("fog_intensity", 1.0))
	fog_slider.value_changed.connect(func(v): SettingsManager.set_setting("fog_intensity", v))
	vbox.add_child(fog_slider)

	# 色盲模式
	var cb_hbox := HBoxContainer.new()
	cb_hbox.add_child(_make_label("Colorblind Mode:"))
	var cb_opt := _make_option(
		["Off", "Protanopia", "Deuteranopia", "Tritanopia"],
		SettingsManager.get_setting("colorblind_mode", 0)
	)
	cb_opt.item_selected.connect(func(i): SettingsManager.set_setting("colorblind_mode", i))
	cb_hbox.add_child(cb_opt)
	vbox.add_child(cb_hbox)

	# 字体缩放
	vbox.add_child(_make_label("Font Scale:"))
	var font_slider := _make_slider(0.8, 1.5, 0.1, SettingsManager.get_setting("font_scale", 1.0))
	font_slider.value_changed.connect(func(v): SettingsManager.set_setting("font_scale", v))
	vbox.add_child(font_slider)

	# 减少闪烁（癫痫安全）
	var flash_cb := _make_check("Reduce Flashing (Photosensitivity)", SettingsManager.get_setting("reduce_flashing", false))
	flash_cb.toggled.connect(func(p: bool): SettingsManager.set_setting("reduce_flashing", p))
	vbox.add_child(flash_cb)

	# 语言
	var lang_hbox := HBoxContainer.new()
	lang_hbox.add_child(_make_label("Language:"))
	var lang_opt := OptionButton.new()
	lang_opt.add_theme_font_override("font", _font_normal)
	lang_opt.add_theme_font_size_override("font_size", 22)
	var locales := I18nManager.get_supported_locales()
	var current := I18nManager.get_language()
	for i in range(locales.size()):
		lang_opt.add_item(locales[i])
		if locales[i] == current:
			lang_opt.selected = i
	lang_opt.item_selected.connect(func(i): I18nManager.set_language(locales[i]))
	lang_hbox.add_child(lang_opt)
	vbox.add_child(lang_hbox)


# ============ 控制标签 ============

func _build_controls_tab() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_tab_container.add_child(vbox)
	_tab_container.set_tab_title(3, I18nManager.translate("settings.controls"))

	vbox.add_child(_make_label("Key bindings (edit in Input Map)"))

	# 列出当前按键绑定
	var actions := InputMap.get_actions()
	for action in actions:
		if action.begins_with("ui_"):
			continue
		var events := InputMap.action_get_events(action)
		if events.is_empty():
			continue
		var hbox := HBoxContainer.new()
		hbox.add_child(_make_label(action))
		var key_label := _make_label(events[0].as_text())
		key_label.add_theme_font_override("font", _font_mono)
		hbox.add_child(key_label)
		vbox.add_child(hbox)


# ============ LLM标签 ============

func _build_llm_tab() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_tab_container.add_child(vbox)
	_tab_container.set_tab_title(4, I18nManager.translate("settings.llm"))

	# API Key
	vbox.add_child(_make_label("API Key:"))
	var key_hbox := HBoxContainer.new()
	var key_input := _make_line_edit("", "Enter API key...")
	key_input.secret = true
	if LLMBridge.has_api_key():
		key_input.text = "••••••••"
	key_input.text_submitted.connect(func(v):
		LLMBridge.set_api_key(v)
		key_input.text = "••••••••"
	)
	key_hbox.add_child(key_input)

	var clear_key_btn := Button.new()
	clear_key_btn.text = "Clear"
	clear_key_btn.add_theme_font_override("font", _font_normal)
	clear_key_btn.add_theme_font_size_override("font_size", 22)
	clear_key_btn.pressed.connect(func():
		LLMBridge.clear_api_key()
		key_input.text = ""
	)
	key_hbox.add_child(clear_key_btn)
	vbox.add_child(key_hbox)

	# Endpoint
	vbox.add_child(_make_label("API Endpoint:"))
	var endpoint_input := _make_line_edit(
		SettingsManager.get_setting("api_endpoint", "https://api.openai.com/v1/chat/completions"),
		"https://api.openai.com/v1/chat/completions"
	)
	endpoint_input.text_changed.connect(func(v): SettingsManager.set_setting("api_endpoint", v))
	vbox.add_child(endpoint_input)

	# Model
	vbox.add_child(_make_label("Model:"))
	var model_input := _make_line_edit(
		SettingsManager.get_setting("model_name", "gpt-4o-mini"),
		"gpt-4o-mini"
	)
	model_input.text_changed.connect(func(v): SettingsManager.set_setting("model_name", v))
	vbox.add_child(model_input)

	# Max Tokens
	var tokens_hbox := HBoxContainer.new()
	tokens_hbox.add_child(_make_label("Max Tokens:"))
	var tokens_spin := _make_spinbox(32, 4096, SettingsManager.get_setting("max_tokens", 256))
	tokens_spin.value_changed.connect(func(v): SettingsManager.set_setting("max_tokens", int(v)))
	tokens_hbox.add_child(tokens_spin)
	vbox.add_child(tokens_hbox)

	# Temperature
	vbox.add_child(_make_label("Temperature:"))
	var temp_slider := _make_slider(0.0, 2.0, 0.1, SettingsManager.get_setting("temperature", 0.3))
	temp_slider.value_changed.connect(func(v): SettingsManager.set_setting("temperature", v))
	vbox.add_child(temp_slider)


# ============ 事件 ============

func _on_setting_changed(key: String, value: Variant) -> void:
	# 音频设置实时应用
	if key == "master_volume" or key == "sfx_volume" or key == "music_volume":
		SettingsManager.apply_audio_settings()


func _on_language_changed(_locale: String) -> void:
	# 更新标签标题
	if _tab_container.get_tab_count() >= 5:
		_tab_container.set_tab_title(0, I18nManager.translate("settings.graphics"))
		_tab_container.set_tab_title(1, I18nManager.translate("settings.audio"))
		_tab_container.set_tab_title(2, I18nManager.translate("settings.gameplay"))
		_tab_container.set_tab_title(3, I18nManager.translate("settings.controls"))
		_tab_container.set_tab_title(4, I18nManager.translate("settings.llm"))


func _on_reset_pressed() -> void:
	SettingsManager.reset_to_defaults()
	_load_current_settings()


func _on_replay_tutorial_pressed() -> void:
	# 重置教程进度并重新播放
	TutorialManager.replay_tutorial()
	_on_close_pressed()


func _on_close_pressed() -> void:
	UiAnimator.animate_out(self, func(): visible = false)


func _load_current_settings() -> void:
	# 设置面板在构建时已读取当前值，此处可做额外同步
	pass

func _exit_tree() -> void:
	if SettingsManager != null and SettingsManager.setting_changed.is_connected(_on_setting_changed):
		SettingsManager.setting_changed.disconnect(_on_setting_changed)
	if I18nManager != null and I18nManager.language_changed.is_connected(_on_language_changed):
		I18nManager.language_changed.disconnect(_on_language_changed)
