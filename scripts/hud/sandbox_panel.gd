# sandbox_panel.gd
# 沙盒模式创意工具面板 - 仅在沙盒模式下可见
#
# Responsibilities:
#   - 空间群选择器（230个空间群可搜索）
#   - 晶格参数滑条（6个参数实时预览）
#   - 材料模板预设（10种常见结构）
#   - 自定义挑战目标
#   - 截图按钮
#
# Signals:
#   space_group_changed(sg_number) - 空间群变更
#   lattice_changed(params) - 晶格参数变更
#   template_applied(template_name) - 模板应用
#   custom_goal_set(goal) - 自定义目标设定
#   screenshot_requested() - 截图请求
#
# Dependencies:
#   - Autoload: GameState, LevelManager

extends PanelContainer

var _i18n = null
signal space_group_changed(sg_number: int)
signal lattice_changed(params: Dictionary)
signal template_applied(template_name: String)
signal custom_goal_set(goal: Dictionary)
signal screenshot_requested()

# 230个空间群的编号和符号（按晶系分组）
const SPACE_GROUPS: Array[Dictionary] = [
	# Triclinic (1-2)
	{"number": 1, "symbol": "P1", "system": "Triclinic"},
	{"number": 2, "symbol": "P-1", "system": "Triclinic"},
	# Monoclinic (3-15)
	{"number": 3, "symbol": "P2", "system": "Monoclinic"},
	{"number": 4, "symbol": "P2₁", "system": "Monoclinic"},
	{"number": 5, "symbol": "C2", "system": "Monoclinic"},
	{"number": 6, "symbol": "Pm", "system": "Monoclinic"},
	{"number": 7, "symbol": "Pc", "system": "Monoclinic"},
	{"number": 8, "symbol": "Cm", "system": "Monoclinic"},
	{"number": 9, "symbol": "Cc", "system": "Monoclinic"},
	{"number": 10, "symbol": "P2/m", "system": "Monoclinic"},
	{"number": 11, "symbol": "P2₁/m", "system": "Monoclinic"},
	{"number": 12, "symbol": "C2/m", "system": "Monoclinic"},
	{"number": 13, "symbol": "P2/c", "system": "Monoclinic"},
	{"number": 14, "symbol": "P2₁/c", "system": "Monoclinic"},
	{"number": 15, "symbol": "C2/c", "system": "Monoclinic"},
	# Orthorhombic (16-74)
	{"number": 16, "symbol": "P222", "system": "Orthorhombic"},
	{"number": 25, "symbol": "Pmm2", "system": "Orthorhombic"},
	{"number": 47, "symbol": "Pmmm", "system": "Orthorhombic"},
	{"number": 62, "symbol": "Pnma", "system": "Orthorhombic"},
	{"number": 74, "symbol": "Imma", "system": "Orthorhombic"},
	# Tetragonal (75-142)
	{"number": 75, "symbol": "P4", "system": "Tetragonal"},
	{"number": 99, "symbol": "P4mm", "system": "Tetragonal"},
	{"number": 129, "symbol": "P4/nmm", "system": "Tetragonal"},
	{"number": 141, "symbol": "I4₁/amd", "system": "Tetragonal"},
	# Trigonal (143-167)
	{"number": 143, "symbol": "P3", "system": "Trigonal"},
	{"number": 160, "symbol": "R3m", "system": "Trigonal"},
	{"number": 167, "symbol": "R-3c", "system": "Trigonal"},
	# Hexagonal (168-194)
	{"number": 168, "symbol": "P6", "system": "Hexagonal"},
	{"number": 186, "symbol": "P6₃mc", "system": "Hexagonal"},
	{"number": 194, "symbol": "P6₃/mmc", "system": "Hexagonal"},
	# Cubic (195-230)
	{"number": 195, "symbol": "P23", "system": "Cubic"},
	{"number": 216, "symbol": "F-43m", "system": "Cubic"},
	{"number": 221, "symbol": "Pm-3m", "system": "Cubic"},
	{"number": 225, "symbol": "Fm-3m", "system": "Cubic"},
	{"number": 227, "symbol": "Fd-3m", "system": "Cubic"},
	{"number": 229, "symbol": "Im-3m", "system": "Cubic"},
	{"number": 230, "symbol": "Ia-3d", "system": "Cubic"},
]

# 10种常见结构模板
const MATERIAL_TEMPLATES: Array[Dictionary] = [
	{"name": "NaCl", "space_group": 225, "a": 5.64, "b": 5.64, "c": 5.64, "alpha": 90, "beta": 90, "gamma": 90, "elements": ["Na", "Cl"]},
	{"name": "CsCl", "space_group": 221, "a": 4.12, "b": 4.12, "c": 4.12, "alpha": 90, "beta": 90, "gamma": 90, "elements": ["Cs", "Cl"]},
	{"name": "Diamond", "space_group": 227, "a": 3.57, "b": 3.57, "c": 3.57, "alpha": 90, "beta": 90, "gamma": 90, "elements": ["C"]},
	{"name": "Perovskite", "space_group": 221, "a": 3.91, "b": 3.91, "c": 3.91, "alpha": 90, "beta": 90, "gamma": 90, "elements": ["Ba", "Ti", "O"]},
	{"name": "Zincblende", "space_group": 216, "a": 5.41, "b": 5.41, "c": 5.41, "alpha": 90, "beta": 90, "gamma": 90, "elements": ["Zn", "S"]},
	{"name": "Fluorite", "space_group": 225, "a": 5.46, "b": 5.46, "c": 5.46, "alpha": 90, "beta": 90, "gamma": 90, "elements": ["Ca", "F"]},
	{"name": "Wurtzite", "space_group": 186, "a": 3.25, "b": 3.25, "c": 5.20, "alpha": 90, "beta": 90, "gamma": 120, "elements": ["Zn", "S"]},
	{"name": "Spinel", "space_group": 227, "a": 8.08, "b": 8.08, "c": 8.08, "alpha": 90, "beta": 90, "gamma": 90, "elements": ["Mg", "Al", "O"]},
	{"name": "Garnet", "space_group": 230, "a": 11.53, "b": 11.53, "c": 11.53, "alpha": 90, "beta": 90, "gamma": 90, "elements": ["Fe", "Al", "Si", "O"]},
	{"name": "Olivine", "space_group": 62, "a": 4.76, "b": 10.20, "c": 5.99, "alpha": 90, "beta": 90, "gamma": 90, "elements": ["Mg", "Fe", "Si", "O"]},
]

var _sg_search: LineEdit = null
var _sg_list: ItemList = null
var _lattice_sliders: Dictionary = {}  # param_name -> HSlider
var _lattice_labels: Dictionary = {}  # param_name -> Label
var _custom_goals: Array[Dictionary] = []


func _ready() -> void:
	_i18n = Engine.get_main_loop().root.get_node_or_null("/root/I18nManager")
	if _i18n != null and _i18n.has_signal("language_changed"):
		_i18n.language_changed.connect(_on_language_changed)
	# 仅沙盒模式可见
	visible = false
	GameState.mode_changed.connect(_on_mode_changed)
	_refresh_text()
	_check_visibility()
	if get_child_count() > 0:
		_assign_scene_nodes()
	else:
		_build_ui()
	UiAnimator.style_panel(self)
	UiAnimator.style_all_buttons(self)
	UiAnimator.attach_button_helpers(self)


func _assign_scene_nodes() -> void:
	var margin = get_node_or_null("MarginContainer")
	var main_vbox = margin.get_node("MainVBox")
	var scroll = main_vbox.get_node("ScrollContainer")
	var content = scroll.get_node("Content")
	_build_space_group_section(content)
	_build_lattice_section(content)
	_build_template_section(content)
	_build_custom_challenge_section(content)
	_build_screenshot_section(content)


func _on_mode_changed(_new_mode: int) -> void:
	_refresh_text()
	_check_visibility()


func _check_visibility() -> void:
	# 沙盒面板只在沙盒模式下显示
	if not GameState.current_mode == GameState.GameMode.SANDBOX:
		visible = false


func show_panel() -> void:
	if GameState.current_mode == GameState.GameMode.SANDBOX:
		visible = true
		UiAnimator.animate_in(self)


func hide_panel() -> void:
	UiAnimator.animate_out(self, func(): visible = false)


func toggle_panel() -> void:
	if visible:
		hide_panel()
	else:
		show_panel()


func _build_ui() -> void:
	# 主容器
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)
	margin.add_child(main_vbox)

	# 标题
	var title := Label.new()
	title.text = _i18n.translate("hud.sandbox.tools_title")
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", UiAnimator.CYAN)
	main_vbox.add_child(title)

	# 可滚动区域
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320, 600)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	scroll.add_child(content)

	# === 1. 空间群选择器 ===
	_build_space_group_section(content)

	# === 2. 晶格参数滑条 ===
	_build_lattice_section(content)

	# === 3. 材料模板 ===
	_build_template_section(content)

	# === 4. 自定义挑战 ===
	_build_custom_challenge_section(content)

	# === 5. 截图按钮 ===
	_build_screenshot_section(content)


func _build_space_group_section(parent: VBoxContainer) -> void:
	var section_title := Label.new()
	section_title.text = _i18n.translate("hud.sandbox.space_group")
	section_title.add_theme_font_size_override("font_size", 22)
	section_title.add_theme_color_override("font_color", UiAnimator.MUTED)
	parent.add_child(section_title)

	# 搜索框
	_sg_search = LineEdit.new()
	_sg_search.placeholder_text = _i18n.translate("hud.sandbox.search_placeholder")
	_sg_search.add_theme_font_size_override("font_size", 20)
	_sg_search.text_changed.connect(_on_sg_search_changed)
	parent.add_child(_sg_search)

	# 空间群列表
	_sg_list = ItemList.new()
	_sg_list.custom_minimum_size = Vector2(0, 150)
	_sg_list.add_theme_font_size_override("font_size", 20)
	_sg_list.item_selected.connect(_on_sg_selected)
	parent.add_child(_sg_list)

	_populate_sg_list("")


func _populate_sg_list(filter: String) -> void:
	_sg_list.clear()
	var filter_lower := filter.to_lower()
	for sg in SPACE_GROUPS:
		var text := "%d - %s [%s]" % [sg.number, sg.symbol, sg.system]
		if filter_lower == "" or text.to_lower().find(filter_lower) >= 0:
			_sg_list.add_item(text)
			_sg_list.set_item_metadata(_sg_list.item_count - 1, sg.number)


func _on_sg_search_changed(new_text: String) -> void:
	_populate_sg_list(new_text)


func _on_sg_selected(index: int) -> void:
	var sg_number: int = _sg_list.get_item_metadata(index)
	space_group_changed.emit(sg_number)
	GameLogger.debug("General", "[沙盒] 空间群变更: %d" % sg_number)


func _build_lattice_section(parent: VBoxContainer) -> void:
	var section_title := Label.new()
	section_title.text = _i18n.translate("hud.sandbox.lattice")
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
		label.add_theme_font_size_override("font_size", 20)
		label.custom_minimum_size = Vector2(60, 0)
		hbox.add_child(label)

		var slider := HSlider.new()
		slider.min_value = p.min
		slider.max_value = p.max
		slider.step = p.step
		slider.value = p.default
		slider.custom_minimum_size = Vector2(120, 0)
		slider.value_changed.connect(_on_lattice_slider_changed)
		hbox.add_child(slider)

		var val_label := Label.new()
		val_label.text = "%.1f%s" % [p.default, p.unit]
		val_label.add_theme_font_size_override("font_size", 20)
		val_label.custom_minimum_size = Vector2(70, 0)
		hbox.add_child(val_label)

		_lattice_sliders[p.name] = slider
		_lattice_labels[p.name] = val_label

		parent.add_child(hbox)


func _on_lattice_slider_changed(_value: float) -> void:
	# 更新标签并发出信号
	var params := {}
	for key in _lattice_sliders:
		var slider: HSlider = _lattice_sliders[key]
		var val_label: Label = _lattice_labels[key]
		var unit := "Å" if key in ["a", "b", "c"] else "°"
		val_label.text = "%.1f%s" % [slider.value, unit]
		params[key] = slider.value

	lattice_changed.emit(params)


func _build_template_section(parent: VBoxContainer) -> void:
	var section_title := Label.new()
	section_title.text = _i18n.translate("hud.sandbox.templates")
	section_title.add_theme_font_size_override("font_size", 22)
	section_title.add_theme_color_override("font_color", UiAnimator.MUTED)
	parent.add_child(section_title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)

	for tmpl in MATERIAL_TEMPLATES:
		var btn := Button.new()
		btn.text = tmpl.name
		btn.add_theme_font_size_override("font_size", 20)
		btn.custom_minimum_size = Vector2(130, 40)
		btn.pressed.connect(_on_template_pressed.bind(tmpl.name))
		grid.add_child(btn)


func _on_template_pressed(template_name: String) -> void:
	# 找到模板并应用参数
	for tmpl in MATERIAL_TEMPLATES:
		if tmpl.name == template_name:
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
			_select_sg_in_list(tmpl.space_group)

			template_applied.emit(template_name)
			GameLogger.debug("General", "[沙盒] 应用模板: %s" % template_name)
			break


func _select_sg_in_list(sg_number: int) -> void:
	for i in range(_sg_list.item_count):
		var meta = _sg_list.get_item_metadata(i)
		if meta == sg_number:
			_sg_list.select(i)
			_on_sg_selected(i)
			break


func _build_custom_challenge_section(parent: VBoxContainer) -> void:
	var section_title := Label.new()
	section_title.text = _i18n.translate("hud.sandbox.custom_challenge")
	section_title.add_theme_font_size_override("font_size", 22)
	section_title.add_theme_color_override("font_color", UiAnimator.MUTED)
	parent.add_child(section_title)

	# 目标类型选择
	var type_box := HBoxContainer.new()
	var type_label := Label.new()
	type_label.text = _i18n.translate("hud.sandbox.goal_type")
	type_label.add_theme_font_size_override("font_size", 20)
	type_box.add_child(type_label)

	var type_option := OptionButton.new()
	type_option.add_theme_font_size_override("font_size", 20)
	type_option.add_item("离子电导率 > X", 0)
	type_option.add_item("带隙在 [a, b] 范围", 1)
	type_option.add_item("守恒偏离 < X", 2)
	type_option.add_item("对称性保持", 3)
	type_option.add_item("自定义", 4)
	type_box.add_child(type_option)
	parent.add_child(type_box)

	# 阈值输入
	var threshold_box := HBoxContainer.new()
	var threshold_label := Label.new()
	threshold_label.text = _i18n.translate("hud.sandbox.threshold")
	threshold_label.add_theme_font_size_override("font_size", 20)
	threshold_box.add_child(threshold_label)

	var threshold_input := SpinBox.new()
	threshold_input.min_value = 0.0
	threshold_input.max_value = 100.0
	threshold_input.step = 0.1
	threshold_input.value = 1.0
	threshold_box.add_child(threshold_input)
	parent.add_child(threshold_box)

	# 添加目标按钮
	var add_btn := Button.new()
	add_btn.text = _i18n.translate("hud.sandbox.add_goal")
	add_btn.add_theme_font_size_override("font_size", 20)
	add_btn.pressed.connect(_on_add_custom_goal.bind(type_option, threshold_input))
	parent.add_child(add_btn)


func _on_add_custom_goal(type_option: OptionButton, threshold_input: SpinBox) -> void:
	var goal_type: String = ["conductivity", "bandgap", "conservation", "symmetry", "custom"][type_option.selected]
	var goal := {
		"type": goal_type,
		"threshold": threshold_input.value,
		"description": type_option.get_item_text(type_option.selected),
	}
	_custom_goals.append(goal)
	custom_goal_set.emit(goal)
	GameLogger.debug("General", "[沙盒] 自定义目标: %s > %.1f" % [goal_type, goal.threshold])


func _build_screenshot_section(parent: VBoxContainer) -> void:
	var section_title := Label.new()
	section_title.text = _i18n.translate("hud.sandbox.tools")
	section_title.add_theme_font_size_override("font_size", 22)
	section_title.add_theme_color_override("font_color", UiAnimator.MUTED)
	parent.add_child(section_title)

	var btn := Button.new()
	btn.text = _i18n.translate("hud.sandbox.screenshot")
	btn.add_theme_font_size_override("font_size", 22)
	btn.custom_minimum_size = Vector2(0, 50)
	btn.pressed.connect(_on_screenshot)
	parent.add_child(btn)


func _on_screenshot() -> void:
	screenshot_requested.emit()
	# 等一帧后截图，确保信号处理完毕
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var path := "user://sandbox_screenshot_%s.png" % timestamp
	img.save_png(path)
	GameLogger.debug("General", "[沙盒] 截图已保存: %s" % path)

func _exit_tree() -> void:
	if _i18n != null and _i18n.is_connected("language_changed", _on_language_changed):
		_i18n.language_changed.disconnect(_on_language_changed)
	if GameState != null and GameState.mode_changed.is_connected(_on_mode_changed):
		GameState.mode_changed.disconnect(_on_mode_changed)

func _on_language_changed(_locale: String) -> void:
	_refresh_text()

func _refresh_text() -> void:
	if _i18n == null:
		return
	var title = get_node_or_null("MarginContainer/MainVBox/Title")
	if title:
		title.text = _i18n.translate("hud.sandbox.tools_title")
	var scroll = get_node_or_null("MarginContainer/MainVBox/ScrollContainer")
	if scroll:
		var content = scroll.get_node_or_null("Content")
		if content:
			# Update template button texts if they exist
			var template_grid = content.get_node_or_null("TemplateGrid")
			if template_grid:
				var idx = 0
				for child in template_grid.get_children():
					if child is Button and idx < MATERIAL_TEMPLATES.size():
						child.text = _i18n.translate("hud.sandbox.template_" + MATERIAL_TEMPLATES[idx].name.to_lower())
						idx += 1


