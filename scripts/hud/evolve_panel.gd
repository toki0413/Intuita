# evolve_panel.gd
# 自进化面板 - 规则创建、模板选择、导入导出
# 第一章完成后解锁，从工具面板按钮进入
#
# Responsibilities:
#   - 显示可用模板和自定义规则
#   - 规则创建表单（名称/描述/影响滑条/颜色选择）
#   - 实时验证反馈
#   - 导入导出按钮
#
# Dependencies:
#   - Autoload: SelfEvolve, GameState, ConservationEngine

extends PanelContainer

var _i18n = null
const ROW_LABELS := ["M", "Q", "P", "E"]

var _selected_template: int = -1
var _impact_sliders: Array[HSlider] = []
var _impact_labels: Array[Label] = []
var _validation_label: Label = null
var _rules_container: VBoxContainer = null
var _color_picker: ColorPickerButton = null
var _name_edit: LineEdit = null
var _desc_edit: LineEdit = null


func _ready() -> void:
	_i18n = Engine.get_main_loop().root.get_node_or_null("/root/I18nManager")
	if _i18n != null and _i18n.has_signal("language_changed"):
		_i18n.language_changed.connect(_on_language_changed)
	_init_node_refs()
	_connect_signals()
	UiAnimator.style_panel(self)
	UiAnimator.style_all_buttons(self, ["CreateBtn"])
	_refresh_text()
	UiAnimator.attach_button_helpers(self)
	_refresh_rules_list()
	_update_points_display()


func _init_node_refs() -> void:
	_name_edit = get_node_or_null("MarginContainer/VBox/NameBox/NameEdit")
	_desc_edit = get_node_or_null("MarginContainer/VBox/DescBox/DescEdit")
	_color_picker = get_node_or_null("MarginContainer/VBox/ColorBox/ColorPicker")
	_validation_label = get_node_or_null("MarginContainer/VBox/ValidationLabel")
	_rules_container = get_node_or_null("MarginContainer/VBox/RulesList")

	# 收集4x4滑条和数值标签
	var impact_grid: GridContainer = get_node_or_null("MarginContainer/VBox/ImpactGrid")
	var value_grid: GridContainer = get_node_or_null("MarginContainer/VBox/ValueGrid")
	if impact_grid == null or value_grid == null:
		push_warning("[自进化] ImpactGrid/ValueGrid 节点缺失，滑条功能不可用")
		return

	_impact_sliders.clear()
	_impact_labels.clear()

	# 滑条在ImpactGrid中的节点名: Slider00..Slider33
	for i in range(4):
		for j in range(4):
			var slider_name := "Slider%d%d" % [i, j]
			var slider: HSlider = impact_grid.get_node_or_null(slider_name)
			if slider == null:
				push_warning("[自进化] 缺少滑条节点: " + slider_name)
				_impact_sliders.clear()
				_impact_labels.clear()
				return

			var val_name := "Val%d%d" % [i, j]
			var val_label: Label = value_grid.get_node_or_null(val_name)
			if val_label == null:
				push_warning("[自进化] 缺少数值标签节点: " + val_name)
				_impact_sliders.clear()
				_impact_labels.clear()
				return
			_impact_sliders.append(slider)
			_impact_labels.append(val_label)


func _connect_signals() -> void:
	SelfEvolve.evolve_points_changed.connect(_on_evolve_points_changed)
	SelfEvolve.rule_created.connect(_on_rule_created)
	SelfEvolve.rule_validated.connect(_on_rule_validated)
	SelfEvolve.rule_imported.connect(_on_rule_imported)

	# 模板选择
	var template_list: ItemList = get_node_or_null("MarginContainer/VBox/TemplateList")
	if template_list:
		template_list.item_selected.connect(_on_template_selected)

	# 滑条变化
	for slider in _impact_sliders:
		slider.value_changed.connect(_on_impact_slider_changed)

	# 创建按钮
	var create_btn: Button = get_node_or_null("MarginContainer/VBox/CreateBtn")
	if create_btn:
		create_btn.pressed.connect(_on_create_pressed)

	# NameEdit/DescEdit 支持 Enter 提交
	if _name_edit:
		_name_edit.text_submitted.connect(func(_t): _on_create_pressed())
	if _desc_edit:
		_desc_edit.text_submitted.connect(func(_t): _on_create_pressed())

	# ColorPicker 实时预览
	if _color_picker:
		_color_picker.color_changed.connect(func(_c): _run_live_validation())

	# 导入按钮
	var import_btn: Button = get_node_or_null("MarginContainer/VBox/IOBox/ImportBtn")
	if import_btn:
		import_btn.pressed.connect(_on_import_pressed)

	# 导出全部按钮
	var export_all_btn: Button = get_node_or_null("MarginContainer/VBox/IOBox/ExportAllBtn")
	if export_all_btn:
		export_all_btn.pressed.connect(_on_export_all_pressed)


func _on_evolve_points_changed(_new_amount: int) -> void:
	_update_points_display()


func _update_points_display() -> void:
	var label: Label = $MarginContainer/VBox/PointsLabel
	if label:
		label.text = _i18n.translate("hud.evolve.points", {"current": SelfEvolve.evolve_points, "cost": SelfEvolve.MIN_EVOLVE_POINTS_TO_CREATE})


# ============ 模板选择 ============

func _on_template_selected(index: int) -> void:
	_selected_template = index
	var templates := SelfEvolve.get_templates()
	if index < 0 or index >= templates.size():
		return

	var t: Dictionary = templates[index]
	if _name_edit:
		_name_edit.text = t.name
	if _desc_edit:
		_desc_edit.text = t.description
	if _color_picker:
		_color_picker.color = t.color

	# 预填滑条
	_set_impact_from_dict(t.conservation_impact)


func _set_impact_from_dict(impact: Dictionary) -> void:
	# 重置所有滑条
	for slider in _impact_sliders:
		slider.value = 0.0
	_update_impact_labels()

	# 设置有值的滑条
	for key in impact:
		var parts: PackedStringArray = key.split("_")
		if parts.size() != 2:
			continue
		var row := int(parts[0])
		var col := int(parts[1])
		var idx := row * 4 + col
		if idx >= 0 and idx < _impact_sliders.size():
			_impact_sliders[idx].value = impact[key] * 100.0  # 滑条范围-10到10, 乘100映射


# ============ 实时验证 ============

func _on_impact_slider_changed(_value: float) -> void:
	_update_impact_labels()
	_run_live_validation()


func _update_impact_labels() -> void:
	for i in range(_impact_sliders.size()):
		var val := _impact_sliders[i].value / 100.0
		_impact_labels[i].text = "%.2f" % val


func _run_live_validation() -> void:
	var impact := _get_current_impact()
	var result := SelfEvolve.validate_impact(impact)

	if _validation_label == null:
		return

	if result.passed:
		_validation_label.text = _i18n.translate("hud.evolve.valid_pass")
		_validation_label.add_theme_color_override("font_color", UiAnimator.GREEN)
	elif result.has_negative:
		_validation_label.text = _i18n.translate("hud.evolve.valid_neg")
		_validation_label.add_theme_color_override("font_color", UiAnimator.RED)
	elif result.borderline:
		_validation_label.text = _i18n.translate("hud.evolve.valid_boundary")
		_validation_label.add_theme_color_override("font_color", UiAnimator.AMBER)
	else:
		_validation_label.text = _i18n.translate("hud.evolve.valid_drift")
		_validation_label.add_theme_color_override("font_color", UiAnimator.RED)


func _get_current_impact() -> Dictionary:
	var impact: Dictionary = {}
	# 滑条节点没拿到时直接返回空，避免越界访问
	if _impact_sliders.is_empty():
		return impact
	for i in range(4):
		for j in range(4):
			var val := _impact_sliders[i * 4 + j].value / 100.0
			if absf(val) > 0.001:
				impact["%d_%d" % [i, j]] = val
	return impact


# ============ 规则创建 ============

func _on_create_pressed() -> void:
	var name_text := _name_edit.text.strip_edges()
	if name_text == "":
		name_text = _i18n.translate("hud.evolve.default_name")

	var impact := _get_current_impact()
	var color := Color.WHITE
	if _color_picker:
		color = _color_picker.color

	var cost_evolve := 3
	var cost_cores := 1
	if _selected_template >= 0:
		var templates := SelfEvolve.get_templates()
		if _selected_template < templates.size():
			cost_evolve = templates[_selected_template].cost_evolve
			cost_cores = templates[_selected_template].cost_cores

	SelfEvolve.create_rule(name_text, _desc_edit.text, impact, cost_evolve, cost_cores, color)


func _on_rule_created(rule: Dictionary) -> void:
	_refresh_rules_list()
	_reset_form()


func _on_rule_validated(rule: Dictionary, passed: bool) -> void:
	if not passed:
		if _validation_label:
			_validation_label.text = _i18n.translate("hud.evolve.create_fail")
			_validation_label.add_theme_color_override("font_color", UiAnimator.RED)


func _reset_form() -> void:
	if _name_edit:
		_name_edit.text = ""
	if _desc_edit:
		_desc_edit.text = ""
	for slider in _impact_sliders:
		slider.value = 0.0
	_update_impact_labels()
	if _validation_label:
		_validation_label.text = _i18n.translate("hud.evolve.adjust_slider")
		_validation_label.add_theme_color_override("font_color", UiAnimator.MUTED)


# ============ 规则列表 ============

func _refresh_rules_list() -> void:
	if _rules_container == null:
		return

	for child in _rules_container.get_children():
		child.queue_free()

	var rules := SelfEvolve.get_all_rules()
	for rule in rules:
		var hbox := HBoxContainer.new()

		var name_label := Label.new()
		name_label.text = rule.name
		name_label.custom_minimum_size.x = 120
		hbox.add_child(name_label)

		var status := _i18n.translate("hud.evolve.status_pass") if rule.validated else _i18n.translate("hud.evolve.status_fail")
		var status_label := Label.new()
		status_label.text = "[%s]" % status
		status_label.add_theme_color_override("font_color",
			UiAnimator.GREEN if rule.validated else UiAnimator.RED)
		hbox.add_child(status_label)

		var apply_btn := Button.new()
		apply_btn.text = _i18n.translate("hud.evolve.apply")
		apply_btn.pressed.connect(_on_apply_rule.bind(rule.id))
		hbox.add_child(apply_btn)

		var export_btn := Button.new()
		export_btn.text = _i18n.translate("hud.evolve.export")
		export_btn.pressed.connect(_on_export_rule.bind(rule.id))
		hbox.add_child(export_btn)

		_rules_container.add_child(hbox)


func _on_apply_rule(rule_id: String) -> void:
	SelfEvolve.apply_rule(rule_id)


func _on_export_rule(rule_id: String) -> void:
	SelfEvolve.export_rule(rule_id)


# ============ 导入 ============

func _on_import_pressed() -> void:
	# 使用FileDialog选择文件
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.intuita_rule ; Intuita规则文件"])
	# 选完文件或取消都要把对话框释放掉，否则会一直挂在树上
	dialog.file_selected.connect(func(path: String):
		_on_import_file_selected(path)
		dialog.queue_free()
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
	)
	add_child(dialog)
	dialog.popup_centered(Vector2i(600, 400))


func _on_import_file_selected(path: String) -> void:
	SelfEvolve.import_rule(path)


func _on_export_all_pressed() -> void:
	var rules := SelfEvolve.get_all_rules()
	for rule in rules:
		SelfEvolve.export_rule(rule.id)


func _on_rule_imported(rule: Dictionary) -> void:
	_refresh_rules_list()


# ============ 显示/隐藏 ============

func slide_in() -> void:
	visible = true
	UiAnimator.animate_in(self)
	var tween := create_tween()
	tween.tween_property(self, "position:x", position.x, 0.3).from(position.x + 100.0)


func slide_out() -> void:
	UiAnimator.animate_out(self, func(): visible = false)
	var tween := create_tween()
	tween.tween_property(self, "position:x", position.x + 100.0, 0.3)

func _exit_tree() -> void:
	if _i18n != null and _i18n.is_connected("language_changed", _on_language_changed):
		_i18n.language_changed.disconnect(_on_language_changed)
	if SelfEvolve != null and SelfEvolve.evolve_points_changed.is_connected(_on_evolve_points_changed):
		SelfEvolve.evolve_points_changed.disconnect(_on_evolve_points_changed)
	if SelfEvolve != null and SelfEvolve.rule_created.is_connected(_on_rule_created):
		SelfEvolve.rule_created.disconnect(_on_rule_created)
	if SelfEvolve != null and SelfEvolve.rule_validated.is_connected(_on_rule_validated):
		SelfEvolve.rule_validated.disconnect(_on_rule_validated)
	if SelfEvolve != null and SelfEvolve.rule_imported.is_connected(_on_rule_imported):
		SelfEvolve.rule_imported.disconnect(_on_rule_imported)

func _on_language_changed(_locale: String) -> void:
	_refresh_text()

func _refresh_text() -> void:
	if _i18n == null:
		return
	var title = get_node_or_null("MarginContainer/VBox/Title")
	if title:
		title.text = _i18n.translate("hud.evolve.title")
	var template_label = get_node_or_null("MarginContainer/VBox/TemplateLabel")
	if template_label:
		template_label.text = _i18n.translate("hud.evolve.template")
	var create_label = get_node_or_null("MarginContainer/VBox/CreateLabel")
	if create_label:
		create_label.text = _i18n.translate("hud.evolve.create_rule")
	var name_label = get_node_or_null("MarginContainer/VBox/NameBox/NameLabel")
	if name_label:
		name_label.text = _i18n.translate("hud.evolve.name")
	var name_edit = get_node_or_null("MarginContainer/VBox/NameBox/NameEdit")
	if name_edit:
		name_edit.placeholder_text = _i18n.translate("hud.evolve.name_placeholder")
	var desc_label = get_node_or_null("MarginContainer/VBox/DescBox/DescLabel")
	if desc_label:
		desc_label.text = _i18n.translate("hud.evolve.description")
	var desc_edit = get_node_or_null("MarginContainer/VBox/DescBox/DescEdit")
	if desc_edit:
		desc_edit.placeholder_text = _i18n.translate("hud.evolve.desc_placeholder")
	var impact_label = get_node_or_null("MarginContainer/VBox/ImpactLabel")
	if impact_label:
		impact_label.text = _i18n.translate("hud.evolve.impact")
	var color_label = get_node_or_null("MarginContainer/VBox/ColorBox/ColorLabel")
	if color_label:
		color_label.text = _i18n.translate("hud.evolve.color")
	var create_btn = get_node_or_null("MarginContainer/VBox/CreateBtn")
	if create_btn:
		create_btn.text = _i18n.translate("hud.evolve.create_rule")
	var rules_label = get_node_or_null("MarginContainer/VBox/RulesLabel")
	if rules_label:
		rules_label.text = _i18n.translate("hud.evolve.rules")
	var import_btn = get_node_or_null("MarginContainer/VBox/IOBox/ImportBtn")
	if import_btn:
		import_btn.text = _i18n.translate("hud.evolve.import")
	var export_btn = get_node_or_null("MarginContainer/VBox/IOBox/ExportAllBtn")
	if export_btn:
		export_btn.text = _i18n.translate("hud.evolve.export_all")
	var template_list = get_node_or_null("MarginContainer/VBox/TemplateList")
	if template_list and template_list.item_count >= 4:
		template_list.set_item_text(0, _i18n.translate("evolve.template.tunnel"))
		template_list.set_item_text(1, _i18n.translate("evolve.template.thermal"))
		template_list.set_item_text(2, _i18n.translate("evolve.template.strain"))
		template_list.set_item_text(3, _i18n.translate("evolve.template.defect"))
	_update_points_display()
	_run_live_validation()
	_refresh_rules_list()


