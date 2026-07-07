# structure_codex_panel.gd
# 结构图鉴面板 - 浏览/保存/导入导出/杂交变异玩家创造的结构
# 独立于材料图鉴（MaterialCodex），专注于玩家自建结构的基因管理
#
# Responsibilities:
#   - 列出已保存的结构（基因码/名称/原子数/时间）
#   - 保存当前构造画布的结构为新基因
#   - 导入/导出 .intuita_struct 文件
#   - 杂交两个结构（A骨架+B元素）
#   - 变异结构（随机扰动）
#
# Dependencies:
#   - Autoload: StructureCodex, UiAnimator, GameLogger

extends Control

signal panel_closed()

var _i18n = null
var _grid_container: GridContainer = null
var _close_btn: Button = null
var _save_btn: Button = null
var _import_btn: Button = null
var _export_btn: Button = null
var _hybrid_btn: Button = null
var _mutate_btn: Button = null
var _delete_btn: Button = null
var _name_edit: LineEdit = null
var _detail_label: RichTextLabel = null
var _empty_hint: Label = null
var _selected_gene: String = ""
var _selected_gene_b: String = ""  # 杂交第二选择


func _ready() -> void:
	_i18n = Engine.get_main_loop().root.get_node_or_null("/root/I18nManager")
	if get_child_count() > 0:
		_assign_scene_nodes()
	else:
		_build_ui()
	_setup_visuals()
	_refresh_grid()


func _assign_scene_nodes() -> void:
	# 如果将来做成 .tscn，这里挂接节点
	_build_ui()


func _build_ui() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	visible = false

	var bg := ColorRect.new()
	bg.color = Color(UiAnimator.COLOR_BG_DEEP, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 16)
	margin.add_child(main_vbox)

	# 顶部标题栏
	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 20)
	main_vbox.add_child(top_hbox)

	var title := Label.new()
	title.text = "结构图鉴 / Structure Codex"
	title.add_theme_font_override("font", UiAnimator.make_ui_font(28, true))
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UiAnimator.AMBER)
	top_hbox.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(spacer)

	_close_btn = Button.new()
	_close_btn.text = "关闭 / Close"
	_close_btn.add_theme_font_override("font", UiAnimator.make_ui_font(20, true))
	_close_btn.add_theme_font_size_override("font_size", 20)
	_close_btn.pressed.connect(_on_close)
	top_hbox.add_child(_close_btn)

	# 保存栏：命名 + 保存按钮
	var save_hbox := HBoxContainer.new()
	save_hbox.add_theme_constant_override("separation", 12)
	main_vbox.add_child(save_hbox)

	var name_label := Label.new()
	name_label.text = "命名 / Name:"
	name_label.add_theme_font_override("font", UiAnimator.make_ui_font(20, false))
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", UiAnimator.PAPER)
	save_hbox.add_child(name_label)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "My Structure"
	_name_edit.custom_minimum_size = Vector2(240, 36)
	_name_edit.add_theme_font_size_override("font_size", 20)
	save_hbox.add_child(_name_edit)

	_save_btn = Button.new()
	_save_btn.text = "保存当前 / Save Current"
	_save_btn.add_theme_font_override("font", UiAnimator.make_ui_font(20, true))
	_save_btn.add_theme_font_size_override("font_size", 20)
	_save_btn.tooltip_text = "将构造画布上的当前结构保存到图鉴"
	_save_btn.pressed.connect(_on_save_current)
	save_hbox.add_child(_save_btn)

	# 操作栏：导入/导出/杂交/变异/删除
	var action_hbox := HBoxContainer.new()
	action_hbox.add_theme_constant_override("separation", 10)
	main_vbox.add_child(action_hbox)

	_import_btn = Button.new()
	_import_btn.text = "导入 / Import"
	_import_btn.add_theme_font_override("font", UiAnimator.make_ui_font(20, true))
	_import_btn.add_theme_font_size_override("font_size", 20)
	_import_btn.pressed.connect(_on_import)
	action_hbox.add_child(_import_btn)

	_export_btn = Button.new()
	_export_btn.text = "导出 / Export"
	_export_btn.add_theme_font_override("font", UiAnimator.make_ui_font(20, true))
	_export_btn.add_theme_font_size_override("font_size", 20)
	_export_btn.disabled = true
	_export_btn.pressed.connect(_on_export)
	action_hbox.add_child(_export_btn)

	_hybrid_btn = Button.new()
	_hybrid_btn.text = "杂交 / Hybridize"
	_hybrid_btn.add_theme_font_override("font", UiAnimator.make_ui_font(20, true))
	_hybrid_btn.add_theme_font_size_override("font_size", 20)
	_hybrid_btn.tooltip_text = "选择两个结构后点击：A骨架+B元素"
	_hybrid_btn.pressed.connect(_on_hybridize)
	action_hbox.add_child(_hybrid_btn)

	_mutate_btn = Button.new()
	_mutate_btn.text = "变异 / Mutate"
	_mutate_btn.add_theme_font_override("font", UiAnimator.make_ui_font(20, true))
	_mutate_btn.add_theme_font_size_override("font_size", 20)
	_mutate_btn.disabled = true
	_mutate_btn.pressed.connect(_on_mutate)
	action_hbox.add_child(_mutate_btn)

	_delete_btn = Button.new()
	_delete_btn.text = "删除 / Delete"
	_delete_btn.add_theme_font_override("font", UiAnimator.make_ui_font(20, true))
	_delete_btn.add_theme_font_size_override("font_size", 20)
	_delete_btn.disabled = true
	_delete_btn.pressed.connect(_on_delete)
	action_hbox.add_child(_delete_btn)

	# 主内容区：左侧网格 + 右侧详情
	var content_hbox := HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 20)
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(content_hbox)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_child(scroll)

	_grid_container = GridContainer.new()
	_grid_container.columns = 4
	_grid_container.add_theme_constant_override("h_separation", 12)
	_grid_container.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid_container)

	# 右侧详情
	_detail_label = RichTextLabel.new()
	_detail_label.bbcode_enabled = true
	_detail_label.fit_content = true
	_detail_label.custom_minimum_size = Vector2(320, 200)
	_detail_label.add_theme_font_override("normal_font", UiAnimator.make_ui_font(20, false))
	_detail_label.add_theme_font_size_override("normal_font_size", 20)
	content_hbox.add_child(_detail_label)

	_empty_hint = Label.new()
	_empty_hint.text = "暂无保存的结构。在沙盒模式中构造后点击\"保存当前\"。\nNo saved structures. Build in sandbox then click \"Save Current\"."
	_empty_hint.add_theme_font_override("font", UiAnimator.make_ui_font(20, false))
	_empty_hint.add_theme_font_size_override("font_size", 20)
	_empty_hint.add_theme_color_override("font_color", UiAnimator.MUTED)
	_empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_hint.visible = false
	main_vbox.add_child(_empty_hint)


func _setup_visuals() -> void:
	UiAnimator.style_all_buttons(self)


func _refresh_grid() -> void:
	for child in _grid_container.get_children():
		child.queue_free()

	var structures: Array[Dictionary] = StructureCodex.list_structures()
	if structures.is_empty():
		_empty_hint.visible = true
		return
	_empty_hint.visible = false

	# 按时间倒序
	structures.sort_custom(func(a, b): return float(a.get("timestamp", 0)) > float(b.get("timestamp", 0)))

	for entry in structures:
		var card := _create_card(entry)
		_grid_container.add_child(card)


func _create_card(entry: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(180, 120)

	var is_selected: bool = entry.get("gene_code", "") == _selected_gene
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiAnimator.COLOR_BG_PANEL, 0.9)
	style.border_color = UiAnimator.AMBER if is_selected else UiAnimator.BORDER
	style.border_width_bottom = 3
	style.border_width_top = 3
	style.border_width_left = 3
	style.border_width_right = 3
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	var name_label := Label.new()
	name_label.text = String(entry.get("name", "Unknown"))
	name_label.add_theme_font_override("font", UiAnimator.make_ui_font(20, true))
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", UiAnimator.PAPER)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(name_label)

	var gene_label := Label.new()
	gene_label.text = String(entry.get("gene_code", ""))
	gene_label.add_theme_font_override("font", UiAnimator.make_ui_font(18, false))
	gene_label.add_theme_font_size_override("font_size", 18)
	gene_label.add_theme_color_override("font_color", UiAnimator.CYAN)
	vbox.add_child(gene_label)

	var info_label := Label.new()
	info_label.text = "原子: %d" % int(entry.get("atoms", 0))
	info_label.add_theme_font_override("font", UiAnimator.make_ui_font(18, false))
	info_label.add_theme_font_size_override("font_size", 18)
	info_label.add_theme_color_override("font_color", UiAnimator.MUTED)
	vbox.add_child(info_label)

	card.gui_input.connect(_on_card_input.bind(entry.get("gene_code", "")))
	return card


func _on_card_input(event: InputEvent, gene_code: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 单击选中A，shift+单击选中B（用于杂交）
		if event.shift:
			_selected_gene_b = gene_code
		else:
			_selected_gene = gene_code
		_update_detail()
		_refresh_grid()
		_update_buttons()


func _update_detail() -> void:
	if _selected_gene.is_empty():
		_detail_label.text = ""
		return
	var structure: Dictionary = StructureCodex.load_structure(_selected_gene)
	if structure.is_empty():
		_detail_label.text = "[color=red]加载失败[/color]"
		return
	var atoms: Array = structure.get("atoms", [])
	var bonds: Array = structure.get("bonds", [])
	var meta: Dictionary = structure.get("metadata", {})
	var elem_count: Dictionary = {}
	for atom in atoms:
		var elem: String = String(atom.get("elem", "?"))
		elem_count[elem] = int(elem_count.get(elem, 0)) + 1
	var elem_str: String = ""
	for elem in elem_count:
		elem_str += "%s×%d " % [elem, elem_count[elem]]
	_detail_label.text = "[b]%s[/b]\n基因码: %s\n原子数: %d\n键数: %d\n元素: %s\n类型: %s" % [
		String(structure.get("name", "")),
		_selected_gene,
		atoms.size(),
		bonds.size(),
		elem_str if not elem_str.is_empty() else "—",
		String(meta.get("type", "original")),
	]
	if not _selected_gene_b.is_empty():
		_detail_label.text += "\n\n[color=cyan]杂交B: %s[/color]" % _selected_gene_b


func _update_buttons() -> void:
	var has_sel: bool = not _selected_gene.is_empty()
	_export_btn.disabled = not has_sel
	_mutate_btn.disabled = not has_sel
	_delete_btn.disabled = not has_sel
	# 杂交需要两个选择
	_hybrid_btn.disabled = not (has_sel and not _selected_gene_b.is_empty())


func _on_save_current() -> void:
	# 从构造画布获取当前结构
	var canvas = _get_construction_canvas()
	if canvas == null:
		_show_toast("无法找到构造画布 / Construction canvas not found")
		return
	var atoms: Array = canvas.get_atoms_for_codex() if canvas.has_method("get_atoms_for_codex") else []
	var bonds: Array = canvas.get_bonds_for_codex() if canvas.has_method("get_bonds_for_codex") else []
	if atoms.is_empty():
		_show_toast("画布上没有原子 / No atoms on canvas")
		return
	var name: String = _name_edit.text.strip_edges()
	if name.is_empty():
		name = "Structure_%d" % Time.get_unix_time_from_system()
	var gene: String = StructureCodex.save_structure(atoms, bonds, name)
	if not gene.is_empty():
		_show_toast("已保存: %s" % gene)
		_name_edit.text = ""
		_refresh_grid()
	else:
		_show_toast("保存失败 / Save failed")


func _on_import() -> void:
	# 使用原生文件对话框
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.intuita_struct ; Intuita Structure"])
	dialog.title = "导入结构 / Import Structure"
	add_child(dialog)
	dialog.file_selected.connect(func(path: String):
		var gene: String = StructureCodex.import_structure(path)
		if not gene.is_empty():
			_show_toast("导入成功: %s" % gene)
			_refresh_grid()
		else:
			_show_toast("导入失败 / Import failed")
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered(Vector2i(800, 600))


func _on_export() -> void:
	if _selected_gene.is_empty():
		return
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.intuita_struct ; Intuita Structure"])
	dialog.title = "导出结构 / Export Structure"
	dialog.current_file = _selected_gene + ".intuita_struct"
	add_child(dialog)
	dialog.file_selected.connect(func(path: String):
		var ok: bool = StructureCodex.export_structure(_selected_gene, path)
		if ok:
			_show_toast("已导出到: %s" % path)
		else:
			_show_toast("导出失败 / Export failed")
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered(Vector2i(800, 600))


func _on_hybridize() -> void:
	if _selected_gene.is_empty() or _selected_gene_b.is_empty():
		return
	var gene: String = StructureCodex.hybridize(_selected_gene, _selected_gene_b)
	if not gene.is_empty():
		_show_toast("杂交完成: %s" % gene)
		_selected_gene = gene
		_selected_gene_b = ""
		_refresh_grid()
		_update_detail()
		_update_buttons()
	else:
		_show_toast("杂交失败 / Hybridization failed")


func _on_mutate() -> void:
	if _selected_gene.is_empty():
		return
	var gene: String = StructureCodex.mutate(_selected_gene, 0.15)
	if not gene.is_empty():
		_show_toast("变异完成: %s" % gene)
		_selected_gene = gene
		_refresh_grid()
		_update_detail()
	else:
		_show_toast("变异失败 / Mutation failed")


func _on_delete() -> void:
	if _selected_gene.is_empty():
		return
	var ok: bool = StructureCodex.delete_structure(_selected_gene)
	if ok:
		_show_toast("已删除 / Deleted")
		_selected_gene = ""
		_selected_gene_b = ""
		_refresh_grid()
		_update_detail()
		_update_buttons()


func _get_construction_canvas() -> Node:
	# 在游戏场景中查找构造画布
	var game_scene = get_tree().current_scene
	if game_scene == null:
		return null
	return game_scene.get_node_or_null("ConstructionCanvas")


func _show_toast(msg: String) -> void:
	# 简单的临时提示标签
	var toast := Label.new()
	toast.text = msg
	toast.add_theme_font_override("font", UiAnimator.make_ui_font(20, true))
	toast.add_theme_font_size_override("font_size", 20)
	toast.add_theme_color_override("font_color", UiAnimator.AMBER)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	toast.position.y -= 60
	add_child(toast)
	var tween := create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(toast, "modulate:a", 0.0, 0.5)
	tween.tween_callback(toast.queue_free)


func _on_close() -> void:
	UiAnimator.animate_out(self, func():
		visible = false
		panel_closed.emit()
	)


func show_panel() -> void:
	visible = true
	_refresh_grid()
	UiAnimator.animate_in(self)
