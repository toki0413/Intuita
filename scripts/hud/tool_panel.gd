# tool_panel.gd
# 工具面板 - 构造操作和核心显示

extends PanelContainer

const HudUtils = preload("res://scripts/hud/hud_utils.gd")

var _i18n = null
signal tool_selected(tool_index: int)

@onready var cores_label: Label = $MarginContainer/VBox/CoreCard/MarginContainer/HBox/CoresLabel
@onready var _core_card: Control = $MarginContainer/VBox/CoreCard
@onready var _vbox: VBoxContainer = $MarginContainer/VBox

var _evolve_panel: Control = null
var _canvas: Node3D = null
var _active_tool_btn: Button = null
var _active_style: StyleBoxFlat
var _inactive_style: StyleBoxFlat
var _element_palette: HBoxContainer = null
var _element_buttons: Array[Button] = []
var _active_element_btn: Button = null


func _ready() -> void:
	_i18n = Engine.get_main_loop().root.get_node_or_null("/root/I18nManager")
	if _i18n != null and _i18n.has_signal("language_changed"):
		_i18n.language_changed.connect(_on_language_changed)
	UiAnimator.style_panel(self)
	if _core_card:
		UiAnimator.style_panel(_core_card)

	# 让非交互子节点不拦截鼠标，点击穿透到3D场景
	HudUtils.set_passthrough(self)

	GameState.cores_changed.connect(_on_cores_changed)
	_update_cores_display()

	# 绑定按钮
	var place_btn: Button = _vbox.get_node_or_null("PlaceBtn")
	if place_btn:
		place_btn.pressed.connect(_on_place)
	var delete_btn: Button = _vbox.get_node_or_null("DeleteBtn")
	if delete_btn:
		delete_btn.pressed.connect(_on_delete)
	var bond_btn: Button = _vbox.get_node_or_null("BondBtn")
	if bond_btn:
		bond_btn.pressed.connect(_on_bond)
	var break_btn: Button = _vbox.get_node_or_null("BreakBtn")
	if break_btn:
		break_btn.pressed.connect(_on_break)
	var verify_btn: Button = _vbox.get_node_or_null("VerifyBtn")
	if verify_btn:
		verify_btn.pressed.connect(_on_verify)

	# 动态补全缺失的工具按钮（ASSEMBLE/PATH_BUILD/CELLULAR_STEP等）
	_create_extra_tool_buttons()

	# 自进化按钮 - 第一章完成后解锁
	var evolve_btn: Button = _vbox.get_node_or_null("EvolveBtn")
	if evolve_btn:
		evolve_btn.pressed.connect(_on_evolve)
		evolve_btn.visible = SelfEvolve.is_chapter1_complete()
	SelfEvolve.evolve_points_changed.connect(_on_evolve_points_changed)

	# 添加工具说明 tooltip（参考 Foldit 的工具提示风格）
	_setup_tooltips()

	# 为按钮添加标准反馈
	_setup_button_feedback(_vbox)

	# 关联 ConstructionCanvas 的工具切换信号
	_canvas = get_node_or_null("/root/Game/ConstructionCanvas")
	if _canvas and _canvas.has_signal("tool_changed"):
		_canvas.tool_changed.connect(_on_tool_changed)

	_refresh_text()
	# 预构建工具状态样式
	_active_style = _make_active_style()
	_inactive_style = _make_inactive_style()

	# 默认选中放置工具
	_set_active_tool("PlaceBtn")

	# 元素调色板 — 让玩家看到本关可用元素并选择
	_create_element_palette()
	LevelManager.level_loaded.connect(_on_level_loaded_for_palette)


func _create_extra_tool_buttons() -> void:
	# 为缺少面板入口的工具动态创建按钮
	# Tool枚举: PLACE(0) SUBSTITUTE(1) SOFT_MODE(2) INTERCALATE(3) DELETE(4) BOND_BUILD(5) ASSEMBLE(6) PATH_BUILD(7) CELLULAR_STEP(8)
	var extra_tools: Array[Dictionary] = [
		{"name": "SubstituteBtn", "tool": 1, "text": "替换", "tooltip": "替换原子元素种类", "modes": ["wyckoff_fill", "assembly", "free"]},
		{"name": "SoftModeBtn", "tool": 2, "text": "软模式", "tooltip": "软模式：允许临时违反守恒", "modes": ["free", "assembly"]},
		{"name": "IntercalateBtn", "tool": 3, "text": "插层", "tooltip": "在层间插入原子", "modes": ["mesh_build", "assembly", "free"]},
		{"name": "AssembleBtn", "tool": 6, "text": "组装", "tooltip": "组装模式：自由放置原子", "modes": ["assembly", "free"]},
		{"name": "PathBuildBtn", "tool": 7, "text": "路径", "tooltip": "构建反应路径", "modes": ["path_build", "free"]},
		{"name": "CellularStepBtn", "tool": 8, "text": "CA步进", "tooltip": "元胞自动机单步演化（空格键）", "modes": ["cellular_automaton"]},
	]
	# 找到 EvolveBtn 作为插入锚点，额外按钮插在它前面
	var anchor: Node = _vbox.get_node_or_null("EvolveBtn")
	var insert_index: int = _vbox.get_child_count() - 1
	if anchor != null:
		insert_index = anchor.get_index()
	for info in extra_tools:
		if _vbox.has_node(info.name):
			continue  # 已存在则跳过
		var btn := Button.new()
		btn.name = info.name
		btn.text = info.text
		btn.tooltip_text = info.tooltip
		# 默认隐藏，根据构造模式动态显示
		btn.visible = false
		btn.pressed.connect(_on_extra_tool_pressed.bind(info.tool, info.name))
		_vbox.add_child(btn)
		_vbox.move_child(btn, insert_index)
		insert_index += 1


func _on_extra_tool_pressed(tool_index: int, btn_name: String) -> void:
	tool_selected.emit(tool_index)
	# _set_active_tool 由 _on_tool_changed 回调驱动


func _update_contextual_tools(construction_mode: String) -> void:
	# 根据当前构造模式显示/隐藏工具按钮
	var mode_map: Dictionary = {
		"SubstituteBtn": ["wyckoff_fill", "assembly", "free"],
		"SoftModeBtn": ["free", "assembly"],
		"IntercalateBtn": ["mesh_build", "assembly", "free"],
		"AssembleBtn": ["assembly", "free"],
		"PathBuildBtn": ["path_build", "free"],
		"CellularStepBtn": ["cellular_automaton"],
	}
	for btn_name in mode_map:
		var btn: Button = _vbox.get_node_or_null(btn_name)
		if btn != null:
			btn.visible = mode_map[btn_name].has(construction_mode)


func _setup_tooltips() -> void:
	var tooltips := {
		"PlaceBtn": _i18n.translate("hud.tool.place_tooltip") if _i18n != null else "",
		"DeleteBtn": _i18n.translate("hud.tool.delete_tooltip") if _i18n != null else "",
		"BondBtn": _i18n.translate("hud.tool.bond_tooltip") if _i18n != null else "",
		"BreakBtn": _i18n.translate("hud.tool.break_tooltip") if _i18n != null else "",
		"VerifyBtn": _i18n.translate("hud.tool.verify_tooltip") if _i18n != null else "",
		"EvolveBtn": _i18n.translate("hud.tool.evolve_tooltip") if _i18n != null else "",
	}
	for btn_name in tooltips:
		var btn: Button = _vbox.get_node_or_null(btn_name)
		if btn:
			btn.tooltip_text = tooltips[btn_name]

	# 核心数量标签也加说明
	if cores_label:
		cores_label.tooltip_text = _i18n.translate("hud.tool.cores_tooltip") if _i18n != null else ""


func _setup_button_feedback(container: Node) -> void:
	var helper_script := load("res://scripts/hud/button_helper.gd")
	for child in container.get_children():
		if child is Button:
			if child.get_script() == null:
				child.set_script(helper_script)
			if child.name == "VerifyBtn":
				child.disabled = GameState.verification_cores < 1
		if child is Container:
			_setup_button_feedback(child)


func _make_active_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiAnimator.CYAN_DIM
	sb.border_color = UiAnimator.CYAN
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	return sb


func _make_inactive_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = UiAnimator.BORDER
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	return sb


func _on_cores_changed(_new_count: int) -> void:
	_update_cores_display()


func _update_cores_display() -> void:
	cores_label.text = _i18n.translate("hud.cores_format", {"n": GameState.verification_cores}) if _i18n != null else ""


func _set_active_tool(btn_name: String) -> void:
	for child in _vbox.get_children():
		if not child is Button:
			continue
		var btn := child as Button
		if btn.name == btn_name:
			_active_tool_btn = btn
			btn.add_theme_color_override("font_color", UiAnimator.CYAN)
			btn.add_theme_stylebox_override("normal", _active_style)
			btn.add_theme_stylebox_override("hover", _active_style)
			btn.add_theme_stylebox_override("pressed", _active_style)
			# 切换到新工具时给一个轻微脉冲反馈
			UiAnimator.pulse_scale(btn, 1.08)
		else:
			btn.remove_theme_color_override("font_color")
			btn.add_theme_stylebox_override("normal", _inactive_style)
			btn.add_theme_stylebox_override("hover", _inactive_style)
			btn.add_theme_stylebox_override("pressed", _inactive_style)


func _on_tool_changed(tool: int) -> void:
	# 根据 ConstructionCanvas 的工具类型高亮对应按钮
	match tool:
		0: _set_active_tool("PlaceBtn")
		1: _set_active_tool("SubstituteBtn")
		2: _set_active_tool("SoftModeBtn")
		3: _set_active_tool("IntercalateBtn")
		4: _set_active_tool("DeleteBtn")
		5: _set_active_tool("BondBtn")
		6: _set_active_tool("AssembleBtn")
		7: _set_active_tool("PathBuildBtn")
		8: _set_active_tool("CellularStepBtn")
		_:
			pass


# ---- 元素调色板 ----

func _create_element_palette() -> void:
	if _element_palette != null:
		return
	_element_palette = HBoxContainer.new()
	_element_palette.name = "ElementPalette"
	_element_palette.alignment = BoxContainer.ALIGNMENT_CENTER
	_element_palette.add_theme_constant_override("separation", 4)
	_vbox.add_child(_element_palette)
	_refresh_element_palette()


func _on_level_loaded_for_palette(_data: Dictionary) -> void:
	# 关卡切换后延迟刷新，等 atom_mgr 加载完元素数据
	call_deferred("_refresh_element_palette")


func _refresh_element_palette() -> void:
	if _element_palette == null or _canvas == null:
		return
	for btn in _element_buttons:
		btn.queue_free()
	_element_buttons.clear()
	_active_element_btn = null

	var elem_data: Dictionary = {}
	if _canvas._atom_mgr != null:
		elem_data = _canvas._atom_mgr.get_element_data()
	if elem_data.is_empty():
		_element_palette.visible = false
		return

	_element_palette.visible = true
	var count: int = 0
	for i in range(elem_data.size()):
		var elem: Dictionary = elem_data[i]
		var sym: String = elem.get("symbol", "?")
		var col: Color = elem.get("color", Color.WHITE)
		var btn := Button.new()
		btn.text = sym
		btn.custom_minimum_size = Vector2(44, 36)
		btn.tooltip_text = "%s (键 %d)" % [sym, count + 1]
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(col.r * 0.3, col.g * 0.3, col.b * 0.3, 0.9)
		sb.border_color = col
		sb.border_width_left = 2
		sb.border_width_top = 2
		sb.border_width_right = 2
		sb.border_width_bottom = 2
		sb.corner_radius_top_left = 6
		sb.corner_radius_top_right = 6
		sb.corner_radius_bottom_left = 6
		sb.corner_radius_bottom_right = 6
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_stylebox_override("pressed", sb)
		btn.pressed.connect(_on_element_selected.bind(i))
		_element_palette.add_child(btn)
		_element_buttons.append(btn)
		count += 1
		if count >= 9:
			break

	# 默认选中第一个元素
	if _element_buttons.size() > 0:
		_on_element_selected(0)


func _on_element_selected(index: int) -> void:
	if _canvas == null:
		return
	_canvas.current_element_index = index
	if _canvas._atom_mgr != null:
		_canvas._atom_mgr.current_element_index = index
	# 高亮当前选中
	for btn in _element_buttons:
		var sb := btn.get_theme_stylebox("normal")
		if sb is StyleBoxFlat:
			var clone := (sb as StyleBoxFlat).duplicate()
			clone.border_width_left = 3
			clone.border_width_top = 3
			clone.border_width_right = 3
			clone.border_width_bottom = 3
			btn.add_theme_stylebox_override("normal", clone)
			btn.add_theme_stylebox_override("hover", clone)
			btn.add_theme_stylebox_override("pressed", clone)
	# 恢复其他按钮
	var active_btn: Button = _element_buttons[index] if index < _element_buttons.size() else null
	if active_btn != null:
		var sb := active_btn.get_theme_stylebox("normal")
		if sb is StyleBoxFlat:
			var clone := (sb as StyleBoxFlat).duplicate()
			clone.border_width_left = 4
			clone.border_width_top = 4
			clone.border_width_right = 4
			clone.border_width_bottom = 4
			clone.bg_color = Color(clone.bg_color.r + 0.15, clone.bg_color.g + 0.15, clone.bg_color.b + 0.15, 1.0)
			active_btn.add_theme_stylebox_override("normal", clone)
			active_btn.add_theme_stylebox_override("hover", clone)
			active_btn.add_theme_stylebox_override("pressed", clone)
	_active_element_btn = active_btn
	if active_btn != null and UiAnimator != null:
		UiAnimator.pulse_scale(active_btn, 1.15)


func _on_place() -> void:
	tool_selected.emit(0)  # Tool.PLACE
	# _set_active_tool 由 _on_tool_changed 回调驱动，确保 canvas 接受后再生效
	MorphismSystem.apply_operation(
		MorphismSystem.MorphismCategory.MONOMORPHISM,
		["structure"],
		[],
		["new_element"]
	)


func _on_delete() -> void:
	tool_selected.emit(4)  # Tool.DELETE
	MorphismSystem.apply_operation(
		MorphismSystem.MorphismCategory.EPIMORPHISM,
		["structure"],
		["removed_element"],
		[]
	)


func _on_bond() -> void:
	tool_selected.emit(5)  # Tool.BOND_BUILD
	MorphismSystem.apply_operation(
		MorphismSystem.MorphismCategory.HOMOMORPHISM,
		["elements"],
		[],
		["bond"]
	)


func _on_break() -> void:
	tool_selected.emit(5)  # Tool.BOND_BUILD（断键与成键共用同一工具模式）
	MorphismSystem.apply_operation(
		MorphismSystem.MorphismCategory.HOMOMORPHISM,
		["elements"],
		["bond"],
		[]
	)


func _on_verify() -> void:
	var pipeline := get_node_or_null("/root/VerificationPipeline")
	if pipeline == null:
		return
	# 监听本次验证结果，给按钮即时反馈
	if not pipeline.verification_completed.is_connected(_on_verify_result):
		pipeline.verification_completed.connect(_on_verify_result)
	await pipeline.verify(
		0,  # LAYER_SYMBOLIC
		"structure_check",
		{}
	)


func _on_verify_result(_layer: int, success: bool, _confidence: float) -> void:
	var pipeline := get_node_or_null("/root/VerificationPipeline")
	if pipeline and pipeline.verification_completed.is_connected(_on_verify_result):
		pipeline.verification_completed.disconnect(_on_verify_result)
	var verify_btn: Button = _vbox.get_node_or_null("VerifyBtn")
	if verify_btn == null:
		return
	if success:
		UiAnimator.flash_success(verify_btn)
	else:
		UiAnimator.shake(verify_btn)


func _on_evolve() -> void:
	if _evolve_panel == null:
		# 延迟加载evolve面板场景
		var scene := load("res://scenes/hud/evolve_panel.tscn") as PackedScene
		if scene:
			_evolve_panel = scene.instantiate()
			# 挂到HUD层
			var hud := get_parent()
			while hud and not hud is CanvasLayer:
				hud = hud.get_parent()
			if hud:
				hud.add_child(_evolve_panel)
			else:
				get_parent().add_child(_evolve_panel)
	if _evolve_panel:
		_evolve_panel.visible = not _evolve_panel.visible
		if _evolve_panel.visible:
			_evolve_panel.slide_in()


func _on_evolve_points_changed(_new_amount: int) -> void:
	var vbox := get_node_or_null("MarginContainer/VBox")
	if vbox == null:
		return
	var evolve_btn: Button = vbox.get_node_or_null("EvolveBtn")
	if evolve_btn:
		evolve_btn.visible = SelfEvolve.is_chapter1_complete()

func _exit_tree() -> void:
	if _i18n != null and _i18n.is_connected("language_changed", _on_language_changed):
		_i18n.language_changed.disconnect(_on_language_changed)
	if GameState != null and GameState.cores_changed.is_connected(_on_cores_changed):
		GameState.cores_changed.disconnect(_on_cores_changed)
	if SelfEvolve != null and SelfEvolve.evolve_points_changed.is_connected(_on_evolve_points_changed):
		SelfEvolve.evolve_points_changed.disconnect(_on_evolve_points_changed)
	if _canvas != null and _canvas.tool_changed.is_connected(_on_tool_changed):
		_canvas.tool_changed.disconnect(_on_tool_changed)

func _on_language_changed(_locale: String) -> void:
	_refresh_text()

func _refresh_text() -> void:
	if _i18n == null:
		return
	var title = get_node_or_null("MarginContainer/VBox/Title")
	if title:
		title.text = _i18n.translate("hud.tools.title")
	var place_btn = get_node_or_null("MarginContainer/VBox/PlaceBtn")
	if place_btn:
		place_btn.text = _i18n.translate("hud.tool.place")
	var delete_btn = get_node_or_null("MarginContainer/VBox/DeleteBtn")
	if delete_btn:
		delete_btn.text = _i18n.translate("hud.tool.delete")
	var bond_btn = get_node_or_null("MarginContainer/VBox/BondBtn")
	if bond_btn:
		bond_btn.text = _i18n.translate("hud.tool.bond")
	var break_btn = get_node_or_null("MarginContainer/VBox/BreakBtn")
	if break_btn:
		break_btn.text = _i18n.translate("hud.tool.break")
	var verify_btn = get_node_or_null("MarginContainer/VBox/VerifyBtn")
	if verify_btn:
		verify_btn.text = _i18n.translate("hud.tool.verify")
	var evolve_btn = get_node_or_null("MarginContainer/VBox/EvolveBtn")
	if evolve_btn:
		evolve_btn.text = _i18n.translate("hud.tool.evolve")
	_update_cores_display()
	_setup_tooltips()
