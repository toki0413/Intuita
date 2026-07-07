# sandbox_config.gd
# 沙盒模式配置面板 - 进入沙盒前的参数设置
# 空间群选择、晶格参数、模板预设、核心/迷雾选项
#
# Responsibilities:
#   - 沙盒参数配置UI
#   - 230空间群可搜索下拉
#   - 6个晶格参数滑条
#   - 10种材料模板预设
#   - 无限核心/迷雾开关
#
# Dependencies:
#   - Autoload: GameState

extends Control

var _i18n = null
signal sandbox_started()

var _sg_option: OptionButton = null
var _sg_search: LineEdit = null
var _lattice_sliders: Dictionary = {}
var _lattice_labels: Dictionary = {}
var _infinite_cores_check: CheckBox = null
var _fog_enabled_check: CheckBox = null
var _template_option: OptionButton = null

# 10种材料模板预设
const TEMPLATES: Array[Dictionary] = [
	{"name": "Free (P1)", "space_group": 1, "a": 5.0, "b": 5.0, "c": 5.0, "alpha": 90, "beta": 90, "gamma": 90},
	{"name": "NaCl", "space_group": 225, "a": 5.64, "b": 5.64, "c": 5.64, "alpha": 90, "beta": 90, "gamma": 90},
	{"name": "Diamond", "space_group": 227, "a": 3.57, "b": 3.57, "c": 3.57, "alpha": 90, "beta": 90, "gamma": 90},
	{"name": "Perovskite", "space_group": 221, "a": 3.91, "b": 3.91, "c": 3.91, "alpha": 90, "beta": 90, "gamma": 90},
	{"name": "Graphite", "space_group": 194, "a": 2.46, "b": 2.46, "c": 6.70, "alpha": 90, "beta": 90, "gamma": 120},
	{"name": "Olivine", "space_group": 62, "a": 4.76, "b": 10.20, "c": 5.99, "alpha": 90, "beta": 90, "gamma": 90},
	{"name": "Spinel", "space_group": 227, "a": 8.08, "b": 8.08, "c": 8.08, "alpha": 90, "beta": 90, "gamma": 90},
	{"name": "Wurtzite", "space_group": 186, "a": 3.25, "b": 3.25, "c": 5.20, "alpha": 90, "beta": 90, "gamma": 120},
	{"name": "Fluorite", "space_group": 225, "a": 5.46, "b": 5.46, "c": 5.46, "alpha": 90, "beta": 90, "gamma": 90},
	{"name": "Garnet", "space_group": 230, "a": 11.53, "b": 11.53, "c": 11.53, "alpha": 90, "beta": 90, "gamma": 90},
]

# 空间群列表（按晶系分组，简化为常用+代表）
const SPACE_GROUPS: Array[Dictionary] = [
	{"number": 1, "symbol": "P1", "system": "Triclinic"},
	{"number": 2, "symbol": "P-1", "system": "Triclinic"},
	{"number": 3, "symbol": "P2", "system": "Monoclinic"},
	{"number": 10, "symbol": "P2/m", "system": "Monoclinic"},
	{"number": 14, "symbol": "P2₁/c", "system": "Monoclinic"},
	{"number": 15, "symbol": "C2/c", "system": "Monoclinic"},
	{"number": 16, "symbol": "P222", "system": "Orthorhombic"},
	{"number": 25, "symbol": "Pmm2", "system": "Orthorhombic"},
	{"number": 47, "symbol": "Pmmm", "system": "Orthorhombic"},
	{"number": 62, "symbol": "Pnma", "system": "Orthorhombic"},
	{"number": 74, "symbol": "Imma", "system": "Orthorhombic"},
	{"number": 75, "symbol": "P4", "system": "Tetragonal"},
	{"number": 99, "symbol": "P4mm", "system": "Tetragonal"},
	{"number": 129, "symbol": "P4/nmm", "system": "Tetragonal"},
	{"number": 141, "symbol": "I4₁/amd", "system": "Tetragonal"},
	{"number": 143, "symbol": "P3", "system": "Trigonal"},
	{"number": 160, "symbol": "R3m", "system": "Trigonal"},
	{"number": 167, "symbol": "R-3c", "system": "Trigonal"},
	{"number": 168, "symbol": "P6", "system": "Hexagonal"},
	{"number": 186, "symbol": "P6₃mc", "system": "Hexagonal"},
	{"number": 194, "symbol": "P6₃/mmc", "system": "Hexagonal"},
	{"number": 195, "symbol": "P23", "system": "Cubic"},
	{"number": 216, "symbol": "F-43m", "system": "Cubic"},
	{"number": 221, "symbol": "Pm-3m", "system": "Cubic"},
	{"number": 225, "symbol": "Fm-3m", "system": "Cubic"},
	{"number": 227, "symbol": "Fd-3m", "system": "Cubic"},
	{"number": 229, "symbol": "Im-3m", "system": "Cubic"},
	{"number": 230, "symbol": "Ia-3d", "system": "Cubic"},
]


func _ready() -> void:
	_i18n = Engine.get_main_loop().root.get_node_or_null("/root/I18nManager")
	if _i18n != null and _i18n.has_signal("language_changed"):
		_i18n.language_changed.connect(_on_language_changed)
	anchors_preset = Control.PRESET_FULL_RECT
	if get_child_count() > 0:
		_assign_scene_nodes()
	else:
		_build_ui()
	_setup_visuals()
	_refresh_text()
	UiAnimator.animate_in(self)


func _exit_tree() -> void:
	if _i18n != null and _i18n.is_connected("language_changed", _on_language_changed):
		_i18n.language_changed.disconnect(_on_language_changed)


func _assign_scene_nodes() -> void:
	var vbox = get_node_or_null("MainPanel/MarginContainer/VBox")
	if vbox == null:
		push_warning("[沙盒配置] VBox 节点缺失，回退到 _build_ui")
		_build_ui()
		return
	var scroll = vbox.get_node_or_null("ScrollContainer")
	if scroll == null:
		push_warning("[沙盒配置] ScrollContainer 节点缺失")
		return
	var content = scroll.get_node_or_null("Content")
	if content == null:
		push_warning("[沙盒配置] Content 节点缺失")
		return
	# build dynamic sections into content
	_build_space_group_section(content)
	_build_lattice_section(content)
	_build_template_section(content)
	_build_options_section(content)
	var start_btn: Button = vbox.get_node_or_null("StartBtn")
	if start_btn:
		start_btn.pressed.connect(_on_start_sandbox)
	var cancel_btn: Button = vbox.get_node_or_null("CancelBtn")
	if cancel_btn:
		cancel_btn.pressed.connect(_on_cancel)


func _setup_visuals() -> void:
	# 主面板样式
	var main_panel = get_node_or_null("MainPanel")
	if main_panel:
		UiAnimator.style_panel(main_panel)
	# 统一按钮样式和反馈
	UiAnimator.style_all_buttons(self)
	UiAnimator.attach_button_helpers(self)


func _build_ui() -> void:
	# 半透明背景
	var bg := ColorRect.new()
	bg.color = Color(UiAnimator.COLOR_BG_DEEP, 0.92)
	bg.anchors_preset = Control.PRESET_FULL_RECT
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# 主面板
	var main_panel := PanelContainer.new()
	main_panel.anchors_preset = Control.PRESET_CENTER
	main_panel.offset_left = -350
	main_panel.offset_top = -350
	main_panel.offset_right = 350
	main_panel.offset_bottom = 350
	add_child(main_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	main_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	# 标题
	var title := Label.new()
	title.text = _i18n.translate("hud.sandbox.config_title")
	_set_font(title, UiAnimator.make_ui_font(28, true))
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UiAnimator.CYAN)
	vbox.add_child(title)

	# 可滚动区域
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	scroll.add_child(content)

	# === 1. 空间群选择器 ===
	_build_space_group_section(content)

	# === 2. 晶格参数 ===
	_build_lattice_section(content)

	# === 3. 模板预设 ===
	_build_template_section(content)

	# === 4. 选项 ===
	_build_options_section(content)

	# === 5. 开始按钮 ===
	var start_btn := Button.new()
	start_btn.text = _i18n.translate("hud.sandbox.start")
	_set_font(start_btn, UiAnimator.make_ui_font(24, true))
	start_btn.add_theme_font_size_override("font_size", 24)
	start_btn.custom_minimum_size = Vector2(0, 55)
	start_btn.pressed.connect(_on_start_sandbox)
	vbox.add_child(start_btn)

	# 取消按钮
	var cancel_btn := Button.new()
	cancel_btn.text = _i18n.translate("hud.cancel")
	_set_font(cancel_btn, UiAnimator.make_ui_font(22, true))
	cancel_btn.add_theme_font_size_override("font_size", 22)
	cancel_btn.pressed.connect(_on_cancel)
	vbox.add_child(cancel_btn)


func _build_space_group_section(parent: VBoxContainer) -> void:
	var section_title := Label.new()
	section_title.text = _i18n.translate("hud.sandbox.space_group")
	_set_font(section_title, UiAnimator.make_ui_font(22, true))
	section_title.add_theme_font_size_override("font_size", 22)
	section_title.add_theme_color_override("font_color", UiAnimator.MUTED)
	parent.add_child(section_title)

	# 搜索框
	_sg_search = LineEdit.new()
	_sg_search.placeholder_text = _i18n.translate("hud.sandbox.search_placeholder")
	_set_font(_sg_search, UiAnimator.make_ui_font(20, false))
	_sg_search.add_theme_font_size_override("font_size", 20)
	_sg_search.text_changed.connect(_on_sg_search_changed)
	parent.add_child(_sg_search)

	# 下拉选择
	_sg_option = OptionButton.new()
	_set_font(_sg_option, UiAnimator.make_ui_font(20, false))
	_sg_option.add_theme_font_size_override("font_size", 20)
	_populate_sg_option("")
	_sg_option.item_selected.connect(_on_sg_selected)
	parent.add_child(_sg_option)


func _populate_sg_option(filter: String) -> void:
	_sg_option.clear()
	var filter_lower := filter.to_lower()
	for sg in SPACE_GROUPS:
		var text := "%d - %s [%s]" % [sg.number, sg.symbol, sg.system]
		if filter_lower == "" or text.to_lower().find(filter_lower) >= 0:
			_sg_option.add_item(text)
			_sg_option.set_item_metadata(_sg_option.item_count - 1, sg.number)
	if _sg_option.item_count > 0:
		_sg_option.select(0)


func _on_sg_search_changed(new_text: String) -> void:
	_populate_sg_option(new_text)


func _on_sg_selected(_index: int) -> void:
	pass


func _build_lattice_section(parent: VBoxContainer) -> void:
	var section_title := Label.new()
	section_title.text = _i18n.translate("hud.sandbox.lattice")
	_set_font(section_title, UiAnimator.make_ui_font(22, true))
	section_title.add_theme_font_size_override("font_size", 22)
	section_title.add_theme_color_override("font_color", UiAnimator.MUTED)
	parent.add_child(section_title)

	var params := [
		{"name": "a", "min": 1.0, "max": 30.0, "default": 5.0, "step": 0.1, "unit": "Å"},
		{"name": "b", "min": 1.0, "max": 30.0, "default": 5.0, "step": 0.1, "unit": "Å"},
		{"name": "c", "min": 1.0, "max": 30.0, "default": 5.0, "step": 0.1, "unit": "Å"},
		{"name": "alpha", "min": 30.0, "max": 150.0, "default": 90.0, "step": 1.0, "unit": "°"},
		{"name": "beta", "min": 30.0, "max": 150.0, "default": 90.0, "step": 1.0, "unit": "°"},
		{"name": "gamma", "min": 30.0, "max": 150.0, "default": 90.0, "step": 1.0, "unit": "°"},
	]

	for p in params:
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)

		var label := Label.new()
		label.text = "%s:" % p.name
		_set_font(label, UiAnimator.make_ui_font(20, true))
		label.add_theme_font_size_override("font_size", 20)
		label.custom_minimum_size = Vector2(60, 0)
		hbox.add_child(label)

		var slider := HSlider.new()
		slider.min_value = p.min
		slider.max_value = p.max
		slider.step = p.step
		slider.value = p.default
		slider.custom_minimum_size = Vector2(150, 0)
		slider.value_changed.connect(_on_lattice_slider_changed)
		hbox.add_child(slider)

		var val_label := Label.new()
		val_label.text = "%.1f%s" % [p.default, p.unit]
		_set_font(val_label, _make_code_font(20, true))
		val_label.add_theme_font_size_override("font_size", 20)
		val_label.custom_minimum_size = Vector2(70, 0)
		hbox.add_child(val_label)

		_lattice_sliders[p.name] = slider
		_lattice_labels[p.name] = val_label

		parent.add_child(hbox)


func _on_lattice_slider_changed(_value: float) -> void:
	for key in _lattice_sliders:
		var slider: HSlider = _lattice_sliders[key]
		var val_label: Label = _lattice_labels[key]
		var unit := "Å" if key in ["a", "b", "c"] else "°"
		val_label.text = "%.1f%s" % [slider.value, unit]


func _build_template_section(parent: VBoxContainer) -> void:
	var section_title := Label.new()
	section_title.text = _i18n.translate("hud.sandbox.template")
	_set_font(section_title, UiAnimator.make_ui_font(22, true))
	section_title.add_theme_font_size_override("font_size", 22)
	section_title.add_theme_color_override("font_color", UiAnimator.MUTED)
	parent.add_child(section_title)

	_template_option = OptionButton.new()
	_set_font(_template_option, UiAnimator.make_ui_font(20, false))
	_template_option.add_theme_font_size_override("font_size", 20)
	for tmpl in TEMPLATES:
		_template_option.add_item(tmpl.name)
	_template_option.item_selected.connect(_on_template_selected)
	parent.add_child(_template_option)


func _on_template_selected(index: int) -> void:
	if index < 0 or index >= TEMPLATES.size():
		return
	var tmpl: Dictionary = TEMPLATES[index]

	# 更新滑条
	if _lattice_sliders.has("a"):
		_lattice_sliders["a"].value = tmpl.a
	if _lattice_sliders.has("b"):
		_lattice_sliders["b"].value = tmpl.b
	if _lattice_sliders.has("c"):
		_lattice_sliders["c"].value = tmpl.c
	if _lattice_sliders.has("alpha"):
		_lattice_sliders["alpha"].value = tmpl.alpha
	if _lattice_sliders.has("beta"):
		_lattice_sliders["beta"].value = tmpl.beta
	if _lattice_sliders.has("gamma"):
		_lattice_sliders["gamma"].value = tmpl.gamma

	# 选择空间群
	_select_sg_in_option(tmpl.space_group)


func _select_sg_in_option(sg_number: int) -> void:
	for i in range(_sg_option.item_count):
		var meta = _sg_option.get_item_metadata(i)
		if meta == sg_number:
			_sg_option.select(i)
			return


func _build_options_section(parent: VBoxContainer) -> void:
	var section_title := Label.new()
	section_title.text = _i18n.translate("hud.sandbox.options")
	_set_font(section_title, UiAnimator.make_ui_font(22, true))
	section_title.add_theme_font_size_override("font_size", 22)
	section_title.add_theme_color_override("font_color", UiAnimator.MUTED)
	parent.add_child(section_title)

	_infinite_cores_check = CheckBox.new()
	_infinite_cores_check.text = _i18n.translate("hud.sandbox.infinite_cores")
	_infinite_cores_check.button_pressed = true
	_set_font(_infinite_cores_check, UiAnimator.make_ui_font(22, true))
	_infinite_cores_check.add_theme_font_size_override("font_size", 22)
	parent.add_child(_infinite_cores_check)

	_fog_enabled_check = CheckBox.new()
	_fog_enabled_check.text = _i18n.translate("hud.sandbox.fog_enabled")
	_fog_enabled_check.button_pressed = false
	_set_font(_fog_enabled_check, UiAnimator.make_ui_font(22, true))
	_fog_enabled_check.add_theme_font_size_override("font_size", 22)
	parent.add_child(_fog_enabled_check)


func _on_start_sandbox() -> void:
	# 应用配置到GameState
	GameState.set_mode(GameState.GameMode.SANDBOX)
	GameState.sandbox_infinite_cores = _infinite_cores_check.button_pressed
	GameState.sandbox_fog_enabled = _fog_enabled_check.button_pressed

	# 空间群
	var sg_idx := _sg_option.selected
	if sg_idx >= 0:
		GameState.sandbox_selected_space_group = _sg_option.get_item_metadata(sg_idx)

	# 晶格参数
	GameState.sandbox_lattice_params = Vector3(
		_lattice_sliders["a"].value if _lattice_sliders.has("a") else 5.0,
		_lattice_sliders["b"].value if _lattice_sliders.has("b") else 5.0,
		_lattice_sliders["c"].value if _lattice_sliders.has("c") else 5.0,
	)
	GameState.sandbox_lattice_angles = Vector3(
		_lattice_sliders["alpha"].value if _lattice_sliders.has("alpha") else 90.0,
		_lattice_sliders["beta"].value if _lattice_sliders.has("beta") else 90.0,
		_lattice_sliders["gamma"].value if _lattice_sliders.has("gamma") else 90.0,
	)

	sandbox_started.emit()

	# 切换到游戏场景
	UiAnimator.fade_change_scene("res://scenes/game.tscn")


func _on_cancel() -> void:
	UiAnimator.animate_out(self, queue_free)


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


func _set_font(control: Control, font: Font) -> void:
	if font != null:
		control.add_theme_font_override("font", font)

func _on_language_changed(_locale: String) -> void:
	_refresh_text()

func _refresh_text() -> void:
	if _i18n == null:
		return

