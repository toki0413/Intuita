# conservation_hud.gd
# 守恒矩阵HUD - 实时显示4x4矩阵和状态
# 行列标签: M=质量 Q=电荷 P=宇称 E=能量
# 对角线=守恒量偏离1.0的程度, 非对角线=交叉耦合

extends PanelContainer

const HudUtils = preload("res://scripts/hud/hud_utils.gd")

const ROW_LABELS := ["M", "Q", "P", "E"]
var _i18n = null
var _row_full_names: Array = []
var _state_names: Array = []
var _state_descriptions: Array = []
var _explanation_label: Label = null
var _meaning_label: Label = null
var _legend_labels: Array = []

var _grid_labels: Array = []
var _grid_cells: Array = []
var _last_matrix_state: int = 0
var _state_label: Label = null
var _status_icon: Label = null
var _status_card: Control = null
var _desc_label: Label = null
var _collapse_btn: Button = null
var _content_wrapper: Control = null
var _is_collapsed: bool = false  # 默认展开，让玩家看到守恒矩阵


var _update_timer: Timer = null


func _ready() -> void:
	_i18n = Engine.get_main_loop().root.get_node_or_null("/root/I18nManager")
	if _i18n != null and _i18n.has_signal("language_changed"):
		_i18n.language_changed.connect(_on_language_changed)

	UiAnimator.style_panel(self)
	_status_card = get_node_or_null("MarginContainer/VBox/StatusCard")
	if _status_card:
		UiAnimator.style_panel(_status_card)

	# 让非交互子节点不拦截鼠标
	HudUtils.set_passthrough(self)

	# 给标题Label添加点击折叠功能
	_setup_collapse()

	# 用定时器代替_process，降低CPU开销
	_update_timer = Timer.new()
	_update_timer.wait_time = 0.5
	_update_timer.autostart = true
	_update_timer.timeout.connect(_update_display)
	add_child(_update_timer)

	_refresh_text()
	_build_grid()
	_state_label = get_node_or_null("MarginContainer/VBox/StatusCard/MarginContainer/StatusRow/StateLabel")
	_status_icon = get_node_or_null("MarginContainer/VBox/StatusCard/MarginContainer/StatusRow/StatusIcon")

	# 在标题下方插入一行通俗说明
	_add_explanation_label()

	ConservationEngine.state_changed.connect(_on_state_changed)
	ConservationEngine.eigenvalue_warning.connect(_on_eigenvalue_warning)
	_refresh_text()
	_update_display()

	# 默认折叠
	if _is_collapsed:
		_apply_collapse(true)


func _setup_collapse() -> void:
	# 找到标题Label，给它加点击信号
	var title_label: Label = get_node_or_null("MarginContainer/VBox/Title")
	if title_label:
		title_label.mouse_filter = Control.MOUSE_FILTER_STOP
		title_label.gui_input.connect(_on_title_input)


func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_is_collapsed = not _is_collapsed
		_apply_collapse(_is_collapsed)


func _apply_collapse(collapsed: bool) -> void:
	var vbox: VBoxContainer = get_node_or_null("MarginContainer/VBox")
	if vbox == null:
		return
	# 折叠时只显示标题，隐藏其余内容
	for i in range(vbox.get_child_count()):
		var child: Node = vbox.get_child(i)
		if child is Label and child.name == "Title":
			# 标题始终可见，折叠时加 ▶ 标记
			if collapsed:
				child.text = "▶ " + (_i18n.translate("hud.conservation.title") if _i18n != null else "Conservation")
			else:
				child.text = "▼ " + (_i18n.translate("hud.conservation.title") if _i18n != null else "Conservation")
			continue
		if child is Control:
			child.visible = not collapsed
func _exit_tree() -> void:
	if _i18n != null and _i18n.is_connected("language_changed", _on_language_changed):
		_i18n.language_changed.disconnect(_on_language_changed)
	if ConservationEngine != null:
		if ConservationEngine.state_changed.is_connected(_on_state_changed):
			ConservationEngine.state_changed.disconnect(_on_state_changed)
		if ConservationEngine.eigenvalue_warning.is_connected(_on_eigenvalue_warning):
			ConservationEngine.eigenvalue_warning.disconnect(_on_eigenvalue_warning)



func _add_explanation_label() -> void:
	var vbox = get_node_or_null("MarginContainer/VBox")
	if vbox == null:
		return
	# 在标题(索引0)之后、网格之前插入说明
	var desc := Label.new()
	desc.name = "ExplanationLabel"
	_explanation_label = desc
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7, 1))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(250, 0)
	# 插入到标题之后（索引1）
	vbox.add_child(desc)
	vbox.move_child(desc, 1)


func _build_grid() -> void:
	var grid: GridContainer = get_node_or_null("MarginContainer/VBox/GridContainer")
	if grid == null:
		return
	_grid_labels.clear()
	_grid_cells.clear()

	# 清除现有的16个单元格，重建带标签的5列网格
	for child in grid.get_children():
		child.queue_free()

	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)

	var mono_font = UiAnimator._load_system_font(["JetBrains Mono", "Consolas"], 400)
	var label_color = UiAnimator.CYAN
	var muted_color = UiAnimator.MUTED

	# 第一行: 空角 + 列头 M/Q/P/E
	var corner := _make_label("", mono_font, 13, muted_color)
	corner.custom_minimum_size = Vector2(24, 24)
	grid.add_child(corner)
	for j in range(4):
		var header := _make_label(ROW_LABELS[j], mono_font, 16, label_color)
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.tooltip_text = _i18n.translate("hud.conservation.row_tooltip", {"label": ROW_LABELS[j], "name": _row_full_names[j] if _row_full_names.size() > j else ""}) if _i18n != null else ""
		grid.add_child(header)

	# 4行数据: 行头 + 4个数据格
	for i in range(4):
		var row_labels: Array = []
		var row_cells: Array = []

		# 行头标签
		var row_header := _make_label(ROW_LABELS[i], mono_font, 16, label_color)
		row_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row_header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row_header.custom_minimum_size = Vector2(24, 36)
		row_header.tooltip_text = _i18n.translate("hud.conservation.row_tooltip", {"label": ROW_LABELS[i], "name": _row_full_names[i]}) if _i18n != null else ""
		grid.add_child(row_header)

		# 4个数据单元格
		for j in range(4):
			var cell := PanelContainer.new()
			cell.custom_minimum_size = Vector2(52, 36)
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.973, 0.98, 0.988, 0.06)
			sb.border_color = Color(0.973, 0.98, 0.988, 0.12)
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(6)
			cell.add_theme_stylebox_override("panel", sb)

			var label := _make_label("0.00", mono_font, 14, muted_color)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			cell.add_child(label)

			# tooltip 解释单元格含义
			if i == j:
				label.tooltip_text = _i18n.translate("hud.conservation.cell_tooltip_diag", {"row": ROW_LABELS[i], "col": ROW_LABELS[j], "name": _row_full_names[i] if _row_full_names.size() > i else ""}) if _i18n != null else ""
			else:
				label.tooltip_text = _i18n.translate("hud.conservation.cell_tooltip_off", {"row": ROW_LABELS[i], "col": ROW_LABELS[j], "row_name": _row_full_names[i] if _row_full_names.size() > i else "", "col_name": _row_full_names[j] if _row_full_names.size() > j else ""}) if _i18n != null else ""

			grid.add_child(cell)
			row_labels.append(label)
			row_cells.append(cell)

		_grid_labels.append(row_labels)
		_grid_cells.append(row_cells)

	# 在网格下方添加图例说明（含M/Q/P/E含义）
	var legend := _build_legend(mono_font)
	var vbox = $MarginContainer/VBox
	vbox.add_child(legend)

	# M/Q/P/E 含义说明
	var meaning := Label.new()
	meaning.name = "MeaningLabel"
	_meaning_label = meaning
	meaning.add_theme_font_override("font", mono_font)
	meaning.add_theme_font_size_override("font_size", 11)
	meaning.add_theme_color_override("font_color", UiAnimator.MUTED)
	meaning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meaning.tooltip_text = _i18n.translate("hud.conservation.meaning_tooltip") if _i18n != null else ""
	vbox.add_child(meaning)


func _make_label(text: String, font: Font, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _build_legend(font: Font) -> HBoxContainer:
	var legend := HBoxContainer.new()
	legend.name = "Legend"
	legend.alignment = BoxContainer.ALIGNMENT_CENTER
	legend.add_theme_constant_override("separation", 16)

	var items := [
		{color = ConservationEngine.get_state_color(0), text = "hud.conservation.legend_safe"},
		{color = ConservationEngine.get_state_color(1), text = "hud.conservation.legend_warning"},
		{color = ConservationEngine.get_state_color(2), text = "hud.conservation.legend_danger"},
	]
	for item in items:
		var dot := Label.new()
		dot.text = "●"
		dot.add_theme_font_override("font", font)
		dot.add_theme_font_size_override("font_size", 14)
		dot.add_theme_color_override("font_color", item.color)
		legend.add_child(dot)

		var text_label := Label.new()
		text_label.text = _i18n.translate(item.text) if _i18n != null else ""
		_legend_labels.append(text_label)
		text_label.add_theme_font_override("font", font)
		text_label.add_theme_font_size_override("font_size", 12)
		text_label.add_theme_color_override("font_color", UiAnimator.MUTED)
		legend.add_child(text_label)

	return legend


func _update_display() -> void:
	var healthy_color := ConservationEngine.get_state_color(0)
	var warning_color := ConservationEngine.get_state_color(1)
	var critical_color := ConservationEngine.get_state_color(2)

	for i in range(4):
		for j in range(4):
			var val: float = ConservationEngine.get_entry(i, j)
			var label: Label = _grid_labels[i][j]
			label.text = "%.2f" % val

			# 对角线元素用不同颜色，非对角线用暗色
			if i == j:
				var deviation := absf(val - 1.0)
				if deviation < 0.1:
					label.add_theme_color_override("font_color", healthy_color)
				elif deviation < 0.3:
					label.add_theme_color_override("font_color", warning_color)
				else:
					label.add_theme_color_override("font_color", critical_color)
			else:
				# 非对角线: 有耦合时高亮
				if absf(val) > 0.05:
					label.add_theme_color_override("font_color", warning_color)
				else:
					label.add_theme_color_override("font_color", UiAnimator.MUTED)

	# 更新状态标签
	if _state_label == null:
		return
	var state := ConservationEngine.get_state()
	_state_label.text = _i18n.translate("hud.conservation.status_format", {"status": _state_names[state]}) if _i18n != null else ""
	_state_label.tooltip_text = _state_descriptions[state] if state < _state_descriptions.size() else ""
	_set_status_icon_color(ConservationEngine.get_state_color(state))


func _set_status_icon_color(color: Color) -> void:
	if _status_icon:
		_status_icon.add_theme_color_override("font_color", color)


func _on_state_changed(old_state: int, new_state: int) -> void:
	if _state_label == null:
		return
	var tween := create_tween()
	tween.tween_property(_state_label, "modulate", Color(2, 2, 2), UiAnimator.safe_flash_duration(0.1))
	tween.tween_property(_state_label, "modulate", Color(1, 1, 1), UiAnimator.safe_flash_duration(0.3))

	if old_state == 0 and new_state >= 1:
		_flash_entire_matrix()


func _on_eigenvalue_warning(index: int, _value: float) -> void:
	flash_row(index)


func flash_row(row: int) -> void:
	if row < 0 or row >= 4:
		return
	# 减少闪烁模式下跳过行闪烁，仅保留状态色变化
	if UiAnimator.is_flashing_reduced():
		return
	for j in range(4):
		var label: Label = _grid_labels[row][j]
		if not is_instance_valid(label):
			continue
		var tween := create_tween()
		tween.tween_property(label, "modulate", Color(2.5, 2.5, 2.5), UiAnimator.safe_flash_duration(0.08))
		tween.tween_property(label, "modulate", Color(1, 1, 1), UiAnimator.safe_flash_duration(0.22))


func _flash_entire_matrix() -> void:
	# 减少闪烁模式下跳过全矩阵闪烁
	if UiAnimator.is_flashing_reduced():
		return
	var grid := $MarginContainer/VBox/GridContainer
	if not grid:
		return
	var tween := create_tween()
	tween.tween_property(grid, "modulate", Color(2.0, 1.5, 0.5), UiAnimator.safe_flash_duration(0.1))
	tween.tween_property(grid, "modulate", Color(1, 1, 1), UiAnimator.safe_flash_duration(0.3))
func _on_language_changed(_locale: String) -> void:
	_refresh_text()

func _refresh_text() -> void:
	if _i18n == null:
		return
	var title = get_node_or_null("MarginContainer/VBox/Title")
	if title:
		title.text = _i18n.translate("hud.conservation.title")
	_row_full_names = _i18n.translate("hud.conservation.row_names").split(",")
	_state_names = _i18n.translate("hud.conservation.states").split(",")
	_state_descriptions = _i18n.translate("hud.conservation.state_descriptions").split(",")
	if _explanation_label:
		_explanation_label.text = _i18n.translate("hud.conservation.explanation")
	if _meaning_label:
		_meaning_label.text = _i18n.translate("hud.conservation.meaning")
		_meaning_label.tooltip_text = _i18n.translate("hud.conservation.meaning_tooltip")
	for i in range(min(_legend_labels.size(), 3)):
		var keys = ["hud.conservation.legend_safe", "hud.conservation.legend_warning", "hud.conservation.legend_danger"]
		_legend_labels[i].text = _i18n.translate(keys[i])
	# Update grid header tooltips
	var grid = get_node_or_null("MarginContainer/VBox/GridContainer")
	if grid:
		var children = grid.get_children()
		# Column headers at indices 1-4
		for j in range(4):
			if j + 1 < children.size() and children[j + 1] is Label:
				children[j + 1].tooltip_text = _i18n.translate("hud.conservation.row_tooltip", {"label": ROW_LABELS[j], "name": _row_full_names[j]}) if _row_full_names.size() > j else ""
		# Row headers at indices 5, 10, 15, 20
		for i in range(4):
			var idx = 5 + i * 5
			if idx < children.size() and children[idx] is Label:
				children[idx].tooltip_text = _i18n.translate("hud.conservation.row_tooltip", {"label": ROW_LABELS[i], "name": _row_full_names[i]}) if _row_full_names.size() > i else ""
		# Update cell tooltips (indices 6-8, 11-13, etc.)
		for i in range(4):
			for j in range(4):
				var idx = 6 + i * 5 + j
				if idx < children.size():
					var cell = children[idx]
					if cell is PanelContainer:
						var label = cell.get_child(0) if cell.get_child_count() > 0 else null
						if label is Label:
							if i == j:
								label.tooltip_text = _i18n.translate("hud.conservation.cell_tooltip_diag", {"row": ROW_LABELS[i], "col": ROW_LABELS[j], "name": _row_full_names[i]}) if _row_full_names.size() > i else ""
							else:
								label.tooltip_text = _i18n.translate("hud.conservation.cell_tooltip_off", {"row": ROW_LABELS[i], "col": ROW_LABELS[j], "row_name": _row_full_names[i], "col_name": _row_full_names[j]}) if _row_full_names.size() > i and _row_full_names.size() > j else ""
