extends Control
var _i18n = null
# 材料图鉴面板 - 展示已收集的材料卡片
# 网格视图 + 详情视图 + 搜索/过滤

const CARD_SIZE := Vector2(140, 180)
const CARD_COLS := 5

var _grid_container: GridContainer = null
var _detail_panel: VBoxContainer = null
var _progress_bar: ProgressBar = null
var _progress_label: Label = null
var _search_box: LineEdit = null
var _rarity_filter: OptionButton = null
var _close_btn: Button = null
var _detail_name: Label = null
var _detail_formula: Label = null
var _detail_rarity: Label = null
var _detail_sg: Label = null
var _detail_props: RichTextLabel = null
var _detail_backstory: RichTextLabel = null
var _detail_score: Label = null
var _detail_3d_area: Control = null
var _selected_id: String = ""

# 过滤状态
var _filter_rarity: String = "all"
var _filter_text: String = ""


func _ready() -> void:
	_i18n = Engine.get_main_loop().root.get_node_or_null("/root/I18nManager")
	if _i18n != null and _i18n.has_signal("language_changed"):
		_i18n.language_changed.connect(_on_language_changed)
	if get_child_count() > 0:
		_assign_scene_nodes()
	else:
		_build_ui()
	_setup_visuals()
	_refresh_text()
	MaterialCodex.codex_updated.connect(_on_codex_updated)
	MaterialCodex.codex_entry_unlocked.connect(_on_entry_unlocked)
	_refresh_grid()


func _assign_scene_nodes() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	var top_hbox = get_node_or_null("MarginContainer/MainVBox/TopHBox")
	if top_hbox == null:
		push_warning("[图鉴] TopHBox 节点缺失，回退到 _build_ui")
		_build_ui()
		return
	_progress_label = top_hbox.get_node_or_null("ProgressLabel")
	_progress_bar = top_hbox.get_node_or_null("ProgressBar")
	_close_btn = top_hbox.get_node_or_null("CloseBtn")
	if _close_btn:
		_close_btn.pressed.connect(_on_close)
	var filter_hbox = get_node_or_null("MarginContainer/MainVBox/FilterHBox")
	if filter_hbox == null:
		push_warning("[图鉴] FilterHBox 节点缺失")
		return
	_search_box = filter_hbox.get_node_or_null("SearchBox")
	if _search_box:
		_search_box.text_changed.connect(_on_search_changed)
	_rarity_filter = filter_hbox.get_node_or_null("RarityFilter")
	if _rarity_filter:
		_rarity_filter.add_item("全部", 0)
		_rarity_filter.add_item("Common", 1)
		_rarity_filter.add_item("Uncommon", 2)
		_rarity_filter.add_item("Rare", 3)
		_rarity_filter.add_item("Legendary", 4)
		_rarity_filter.item_selected.connect(_on_rarity_filter_changed)
	_grid_container = get_node_or_null("MarginContainer/MainVBox/ContentHBox/ScrollContainer/GridContainer")
	var detail = get_node_or_null("MarginContainer/MainVBox/ContentHBox/DetailPanel")
	if detail == null:
		push_warning("[图鉴] DetailPanel 节点缺失")
		return
	_detail_3d_area = detail.get_node_or_null("Detail3DArea")
	_detail_name = detail.get_node_or_null("DetailName")
	_detail_formula = detail.get_node_or_null("DetailFormula")
	_detail_rarity = detail.get_node_or_null("DetailRarity")
	_detail_sg = detail.get_node_or_null("DetailSG")
	_detail_score = detail.get_node_or_null("DetailScore")
	_detail_props = detail.get_node_or_null("DetailProps")
	_detail_backstory = detail.get_node_or_null("DetailBackstory")
	_update_progress()
	_show_empty_detail()


func _build_ui() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	# 半透明背景
	var bg := ColorRect.new()
	bg.color = Color(UiAnimator.COLOR_BG_DEEP, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 12)
	# margin
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)
	margin.add_child(main_vbox)

	# 顶部栏: 标题 + 进度 + 关闭
	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 20)
	main_vbox.add_child(top_hbox)

	var title := Label.new()
	title.text = _i18n.translate("hud.codex.title")
	title.add_theme_font_override("font", UiAnimator.make_ui_font(28, true))
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UiAnimator.AMBER)
	top_hbox.add_child(title)

	_progress_label = Label.new()
	_progress_label.add_theme_font_override("font", UiAnimator.make_ui_font(22, false))
	_progress_label.add_theme_font_size_override("font_size", 22)
	_progress_label.add_theme_color_override("font_color", UiAnimator.MUTED)
	top_hbox.add_child(_progress_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(200, 20)
	_progress_bar.show_percentage = false
	top_hbox.add_child(_progress_bar)

	# 弹性空间
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(spacer)

	_close_btn = Button.new()
	_close_btn.text = _i18n.translate("hud.close")
	_close_btn.add_theme_font_override("font", UiAnimator.make_ui_font(22, true))
	_close_btn.add_theme_font_size_override("font_size", 22)
	_close_btn.pressed.connect(_on_close)
	top_hbox.add_child(_close_btn)

	# 搜索/过滤栏
	var filter_hbox := HBoxContainer.new()
	filter_hbox.add_theme_constant_override("separation", 12)
	main_vbox.add_child(filter_hbox)

	var search_label := Label.new()
	search_label.text = _i18n.translate("hud.codex.search")
	search_label.add_theme_font_override("font", UiAnimator.make_ui_font(20, false))
	search_label.add_theme_font_size_override("font_size", 20)
	filter_hbox.add_child(search_label)

	_search_box = LineEdit.new()
	_search_box.placeholder_text = _i18n.translate("hud.codex.placeholder")
	_search_box.custom_minimum_size = Vector2(200, 36)
	_search_box.text_changed.connect(_on_search_changed)
	filter_hbox.add_child(_search_box)

	var rarity_label := Label.new()
	rarity_label.text = _i18n.translate("hud.codex.rarity")
	rarity_label.add_theme_font_override("font", UiAnimator.make_ui_font(20, false))
	rarity_label.add_theme_font_size_override("font_size", 20)
	filter_hbox.add_child(rarity_label)

	_rarity_filter = OptionButton.new()
	_rarity_filter.add_item("全部", 0)
	_rarity_filter.add_item("Common", 1)
	_rarity_filter.add_item("Uncommon", 2)
	_rarity_filter.add_item("Rare", 3)
	_rarity_filter.add_item("Legendary", 4)
	_rarity_filter.item_selected.connect(_on_rarity_filter_changed)
	filter_hbox.add_child(_rarity_filter)

	# 主内容区: 左侧网格 + 右侧详情
	var content_hbox := HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 20)
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(content_hbox)

	# 左侧: 卡片网格 (带滚动)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_child(scroll)

	_grid_container = GridContainer.new()
	_grid_container.columns = CARD_COLS
	_grid_container.add_theme_constant_override("h_separation", 12)
	_grid_container.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid_container)

	# 右侧: 详情面板
	_detail_panel = VBoxContainer.new()
	_detail_panel.custom_minimum_size = Vector2(320, 0)
	_detail_panel.add_theme_constant_override("separation", 8)
	content_hbox.add_child(_detail_panel)

	# 3D预览区
	_detail_3d_area = ColorRect.new()
	_detail_3d_area.custom_minimum_size = Vector2(300, 200)
	_detail_3d_area.color = Color(0.08, 0.08, 0.15)
	_detail_3d_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_panel.add_child(_detail_3d_area)

	# 详情字段
	_detail_name = Label.new()
	_detail_name.add_theme_font_override("font", UiAnimator.make_ui_font(24, true))
	_detail_name.add_theme_font_size_override("font_size", 24)
	_detail_name.add_theme_color_override("font_color", UiAnimator.PAPER)
	_detail_panel.add_child(_detail_name)

	_detail_formula = Label.new()
	_detail_formula.add_theme_font_override("font", UiAnimator.make_ui_font(22, false))
	_detail_formula.add_theme_font_size_override("font_size", 22)
	_detail_formula.add_theme_color_override("font_color", UiAnimator.CYAN)
	_detail_panel.add_child(_detail_formula)

	_detail_rarity = Label.new()
	_detail_rarity.add_theme_font_override("font", UiAnimator.make_ui_font(20, true))
	_detail_rarity.add_theme_font_size_override("font_size", 20)
	_detail_panel.add_child(_detail_rarity)

	_detail_sg = Label.new()
	_detail_sg.add_theme_font_override("font", UiAnimator.make_ui_font(20, false))
	_detail_sg.add_theme_font_size_override("font_size", 20)
	_detail_sg.add_theme_color_override("font_color", UiAnimator.MUTED)
	_detail_panel.add_child(_detail_sg)

	_detail_score = Label.new()
	_detail_score.add_theme_font_override("font", UiAnimator.make_ui_font(20, false))
	_detail_score.add_theme_font_size_override("font_size", 20)
	_detail_score.add_theme_color_override("font_color", UiAnimator.GREEN)
	_detail_panel.add_child(_detail_score)

	_detail_props = RichTextLabel.new()
	_detail_props.bbcode_enabled = true
	_detail_props.fit_content = true
	_detail_props.custom_minimum_size = Vector2(0, 100)
	_detail_panel.add_child(_detail_props)

	_detail_backstory = RichTextLabel.new()
	_detail_backstory.bbcode_enabled = true
	_detail_backstory.fit_content = true
	_detail_backstory.custom_minimum_size = Vector2(0, 80)
	_detail_panel.add_child(_detail_backstory)

	_update_progress()
	_show_empty_detail()


func _setup_visuals() -> void:
	# 关闭按钮添加缩放/音效反馈
	if _close_btn and _close_btn.get_script() == null:
		_close_btn.set_script(load("res://scripts/hud/button_helper.gd"))
	# 统一按钮样式
	UiAnimator.style_all_buttons(self)


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


func _refresh_grid() -> void:
	for child in _grid_container.get_children():
		child.queue_free()

	var entries := _get_filtered_entries()
	for entry in entries:
		var card := _create_card(entry)
		_grid_container.add_child(card)


func _get_filtered_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var all: Dictionary = MaterialCodex.get_all_entries()

	for entry in all.values():
		# 稀有度过滤
		if _filter_rarity != "all" and entry.get("rarity", "") != _filter_rarity:
			continue
		# 文本搜索
		if not _filter_text.is_empty():
			var text_lower: String = _filter_text.to_lower()
			var is_match: bool = false
			if String(entry.get("name", "")).to_lower().find(text_lower) >= 0:
				is_match = true
			if String(entry.get("formula", "")).to_lower().find(text_lower) >= 0:
				is_match = true
			if String(entry.get("space_group", "")).to_lower().find(text_lower) >= 0:
				is_match = true
			if not is_match:
				continue
		result.append(entry)

	# 按稀有度排序: legendary > rare > uncommon > common
	var rarity_order := {"legendary": 0, "rare": 1, "uncommon": 2, "common": 3}
	result.sort_custom(func(a, b): return rarity_order.get(a.get("rarity", ""), 4) < rarity_order.get(b.get("rarity", ""), 4))
	return result


func _create_card(entry: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE

	var rarity_color: Color = MaterialCodex.get_rarity_color(entry.get("rarity", ""))

	if entry.get("unlocked", false):
		# 已解锁 - 显示内容
		var style := StyleBoxFlat.new()
		style.bg_color = Color(UiAnimator.COLOR_BG_PANEL, 0.9)
		style.border_color = rarity_color
		style.border_width_bottom = 3
		style.border_width_top = 3
		style.border_width_left = 3
		style.border_width_right = 3
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		card.add_theme_stylebox_override("panel", style)
	else:
		# 未解锁 - 剪影
		var style := StyleBoxFlat.new()
		style.bg_color = Color(UiAnimator.COLOR_BG_DEEP, 0.8)
		style.border_color = UiAnimator.BORDER
		style.border_width_bottom = 2
		style.border_width_top = 2
		style.border_width_left = 2
		style.border_width_right = 2
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	# 上部: 图标区 (模拟3D预览)
	var icon_area := ColorRect.new()
	icon_area.custom_minimum_size = Vector2(120, 80)
	icon_area.color = Color(UiAnimator.COLOR_BG_DEEP, 1.0) if entry.get("unlocked", false) else Color(UiAnimator.COLOR_BG_DEEP, 0.5)
	icon_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_area)

	if entry.get("unlocked", false):
		# 化学式标签
		var formula_label := Label.new()
		formula_label.text = entry.get("formula", "")
		formula_label.add_theme_font_override("font", UiAnimator.make_ui_font(20, true))
		formula_label.add_theme_font_size_override("font_size", 20)
		formula_label.add_theme_color_override("font_color", rarity_color)
		formula_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(formula_label)

		var name_label := Label.new()
		name_label.text = entry.get("name", "")
		name_label.add_theme_font_override("font", UiAnimator.make_ui_font(14, false))
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.add_theme_color_override("font_color", UiAnimator.MUTED)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		vbox.add_child(name_label)

		# 稀有度标签
		var rarity_label := Label.new()
		rarity_label.text = String(entry.get("rarity", "")).to_upper()
		rarity_label.add_theme_font_override("font", UiAnimator.make_ui_font(14, true))
		rarity_label.add_theme_font_size_override("font_size", 14)
		rarity_label.add_theme_color_override("font_color", rarity_color)
		rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(rarity_label)
	else:
		var lock_label := Label.new()
		lock_label.text = _i18n.translate("hud.codex.locked")
		lock_label.add_theme_font_override("font", UiAnimator.make_ui_font(24, true))
		lock_label.add_theme_font_size_override("font_size", 24)
		lock_label.add_theme_color_override("font_color", UiAnimator.MUTED)
		lock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(lock_label)

	# 点击信号
	card.gui_input.connect(_on_card_input.bind(entry.get("id", "")))
	return card


func _on_card_input(event: InputEvent, entry_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_show_detail(entry_id)


func _show_detail(entry_id: String) -> void:
	var entry: Dictionary = MaterialCodex.get_entry(entry_id)
	if entry.is_empty() or not entry.get("unlocked", false):
		_show_empty_detail()
		return

	_selected_id = entry_id
	var rarity_color: Color = MaterialCodex.get_rarity_color(entry.get("rarity", ""))

	_detail_name.text = entry.get("name", "")
	if _detail_formula: _detail_formula.text = entry.get("formula", "")
	_detail_rarity.text = String(entry.get("rarity", "")).to_upper()
	_detail_rarity.add_theme_color_override("font_color", rarity_color)
	if _detail_sg: _detail_sg.text = _i18n.translate("hud.codex.space_group", {"sg": entry.get("space_group", "")})

	if _detail_score:
		if entry.get("best_score", 0) > 0:
			_detail_score.text = _i18n.translate("hud.codex.best_score", {"score": entry.get("best_score", 0)})
		else:
			_detail_score.text = ""

	# 属性表
	var props_bb := ""
	for key in entry.get("properties", {}):
		props_bb += "[b]%s[/b]: %s\n" % [key.replace("_", " ").capitalize(), entry.get("properties", {})[key]]
	_detail_props.text = props_bb

	# 背景
	_detail_backstory.text = entry.get("backstory", "")


func _show_empty_detail() -> void:
	_selected_id = ""
	_detail_name.text = _i18n.translate("hud.codex.select_material")
	if _detail_formula: _detail_formula.text = ""
	_detail_rarity.text = ""
	if _detail_sg: _detail_sg.text = ""
	if _detail_score: _detail_score.text = ""
	if _detail_props: _detail_props.text = ""
	if _detail_backstory: _detail_backstory.text = ""


func _update_progress() -> void:
	var unlocked := MaterialCodex.get_unlocked_count()
	var total := MaterialCodex.get_total_count()
	_progress_label.text = _i18n.translate("hud.codex.progress", {"current": unlocked, "total": total})
	_progress_bar.max_value = total
	_progress_bar.value = unlocked


func _on_codex_updated(_entry_id: String) -> void:
	_refresh_grid()
	_update_progress()


func _on_entry_unlocked(entry_id: String) -> void:
	_refresh_grid()
	_update_progress()
	if _selected_id == entry_id:
		_show_detail(entry_id)


func _on_search_changed(new_text: String) -> void:
	_filter_text = new_text.strip_edges()
	_refresh_grid()


func _on_rarity_filter_changed(index: int) -> void:
	match index:
		0: _filter_rarity = "all"
		1: _filter_rarity = "common"
		2: _filter_rarity = "uncommon"
		3: _filter_rarity = "rare"
		4: _filter_rarity = "legendary"
	_refresh_grid()


func _on_close() -> void:
	UiAnimator.animate_out(self, func(): visible = false)


func show_codex() -> void:
	visible = true
	_refresh_grid()
	_update_progress()
	UiAnimator.animate_in(self)

func _exit_tree() -> void:
	if _i18n != null and _i18n.is_connected("language_changed", _on_language_changed):
		_i18n.language_changed.disconnect(_on_language_changed)
	if MaterialCodex != null and MaterialCodex.codex_updated.is_connected(_on_codex_updated):
		MaterialCodex.codex_updated.disconnect(_on_codex_updated)
	if MaterialCodex != null and MaterialCodex.codex_entry_unlocked.is_connected(_on_entry_unlocked):
		MaterialCodex.codex_entry_unlocked.disconnect(_on_entry_unlocked)

func _on_language_changed(_locale: String) -> void:
	_refresh_text()

func _refresh_text() -> void:
	if _i18n == null:
		return

