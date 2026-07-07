# evolution_tree_panel.gd
# 进化树可视化面板 - 树状展示玩家通关路径 + 当前称号
#
# Responsibilities:
#   - 按章节分组显示已完成的关卡节点
#   - 显示每章的统计（完成数/星数/均分）
#   - 显示玩家当前称号及进度
#   - 节点点击可查看详情
#
# Dependencies:
#   - Autoload: EvolutionTree, UiAnimator

extends Control

signal panel_closed()

var _i18n = null
var _tree_container: VBoxContainer = null
var _close_btn: Button = null
var _title_label: Label = null
var _stats_label: Label = null
var _detail_label: RichTextLabel = null


func _ready() -> void:
	_i18n = Engine.get_main_loop().root.get_node_or_null("/root/I18nManager")
	if get_child_count() > 0:
		_assign_scene_nodes()
	else:
		_build_ui()
	_setup_visuals()


func _assign_scene_nodes() -> void:
	# 场景已带预构建节点时直接复用，避免 _build_ui 再叠一份重复 UI
	_title_label = find_child("TitleLabel", true, false)
	_close_btn = find_child("CloseBtn", true, false)
	if _close_btn and not _close_btn.pressed.is_connected(_on_close):
		_close_btn.pressed.connect(_on_close)
	_stats_label = find_child("StatsLabel", true, false)
	_tree_container = find_child("TreeContainer", true, false)
	_detail_label = find_child("DetailLabel", true, false)
	# 关键节点没拿到，说明场景里没有预构建 UI，走代码构建
	if _tree_container == null:
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

	# 标题栏
	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 20)
	main_vbox.add_child(top_hbox)

	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.text = "进化树 / Evolution Tree"
	_title_label.add_theme_font_override("font", UiAnimator.make_ui_font(28, true))
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.add_theme_color_override("font_color", UiAnimator.AMBER)
	top_hbox.add_child(_title_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(spacer)

	_close_btn = Button.new()
	_close_btn.name = "CloseBtn"
	_close_btn.text = "关闭 / Close"
	_close_btn.add_theme_font_override("font", UiAnimator.make_ui_font(20, true))
	_close_btn.add_theme_font_size_override("font_size", 20)
	_close_btn.pressed.connect(_on_close)
	top_hbox.add_child(_close_btn)

	# 称号与统计
	_stats_label = Label.new()
	_stats_label.name = "StatsLabel"
	_stats_label.add_theme_font_override("font", UiAnimator.make_ui_font(20, true))
	_stats_label.add_theme_font_size_override("font_size", 20)
	_stats_label.add_theme_color_override("font_color", UiAnimator.PAPER)
	main_vbox.add_child(_stats_label)

	# 主内容：左侧树 + 右侧详情
	var content_hbox := HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 20)
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(content_hbox)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_child(scroll)

	_tree_container = VBoxContainer.new()
	_tree_container.name = "TreeContainer"
	_tree_container.add_theme_constant_override("separation", 8)
	scroll.add_child(_tree_container)

	_detail_label = RichTextLabel.new()
	_detail_label.name = "DetailLabel"
	_detail_label.bbcode_enabled = true
	_detail_label.fit_content = true
	_detail_label.custom_minimum_size = Vector2(300, 200)
	_detail_label.add_theme_font_override("normal_font", UiAnimator.make_ui_font(20, false))
	_detail_label.add_theme_font_size_override("normal_font_size", 20)
	content_hbox.add_child(_detail_label)


func _setup_visuals() -> void:
	UiAnimator.style_all_buttons(self)


func _refresh() -> void:
	for child in _tree_container.get_children():
		child.queue_free()

	# 称号与统计
	var title: Dictionary = EvolutionTree.get_current_title()
	var total_stars: int = EvolutionTree.get_total_stars()
	var nodes: Array[Dictionary] = EvolutionTree.get_tree_data()
	var locale: String = "en"
	if _i18n != null:
		locale = String(_i18n.get_language()).substr(0, 2)
	var title_name: String = title.get("name_" + locale, title.get("name_en", ""))
	var title_desc: String = title.get("desc_" + locale, title.get("desc_en", ""))
	_stats_label.text = "称号: %s (%s)    通关: %d    总星数: %d" % [
		title_name, title.get("id", ""), nodes.size(), total_stars
	]

	# 按章节分组
	var by_chapter: Dictionary = {}
	for node in nodes:
		var ch: int = int(node.get("chapter", 0))
		if not by_chapter.has(ch):
			by_chapter[ch] = []
		by_chapter[ch].append(node)

	# 按章节顺序渲染
	var chapters: Array = by_chapter.keys()
	chapters.sort()
	for ch in chapters:
		var chapter_nodes: Array = by_chapter[ch]
		# 章节按 level 排序
		chapter_nodes.sort_custom(func(a, b): return int(a.get("level", 0)) < int(b.get("level", 0)))
		var stats: Dictionary = EvolutionTree.get_chapter_stats(ch)
		var chapter_header := Label.new()
		chapter_header.text = "第 %d 章 / Chapter %d    完成: %d    星: %d    均分: %.0f" % [
			ch, ch, stats.get("completed", 0), stats.get("stars", 0), stats.get("avg_score", 0.0)
		]
		chapter_header.add_theme_font_override("font", UiAnimator.make_ui_font(22, true))
		chapter_header.add_theme_font_size_override("font_size", 22)
		chapter_header.add_theme_color_override("font_color", UiAnimator.CYAN)
		_tree_container.add_child(chapter_header)

		# 关卡节点行
		var level_row := HBoxContainer.new()
		level_row.add_theme_constant_override("separation", 8)
		_tree_container.add_child(level_row)

		# 留出缩进
		var indent := Control.new()
		indent.custom_minimum_size = Vector2(30, 0)
		level_row.add_child(indent)

		for node in chapter_nodes:
			var btn := Button.new()
			var stars: int = int(node.get("stars", 0))
			var star_str: String = "★".repeat(stars) + "☆".repeat(3 - stars)
			btn.text = "L%d %s\n%s" % [int(node.get("level", 0)), star_str, String(node.get("title", ""))]
			btn.add_theme_font_override("font", UiAnimator.make_ui_font(18, false))
			btn.add_theme_font_size_override("font_size", 18)
			btn.custom_minimum_size = Vector2(160, 60)
			btn.tooltip_text = "分数: %.0f\n证明深度: %d\n用时: %.1fs" % [
				float(node.get("score", 0)),
				int(node.get("proof_depth", 0)),
				float(node.get("time_spent", 0))
			]
			btn.pressed.connect(_on_node_clicked.bind(node))
			level_row.add_child(btn)

	# 称号进度提示
	var progress_label := Label.new()
	progress_label.text = "\n称号进度 / Title Progress:"
	progress_label.add_theme_font_override("font", UiAnimator.make_ui_font(20, true))
	progress_label.add_theme_font_size_override("font_size", 20)
	progress_label.add_theme_color_override("font_color", UiAnimator.MUTED)
	_tree_container.add_child(progress_label)

	for t in EvolutionTree.TITLES:
		var tlabel := Label.new()
		var unlocked: bool = nodes.size() >= int(t.get("min_levels", 0))
		var color: Color = UiAnimator.AMBER if unlocked else UiAnimator.MUTED
		tlabel.text = "%s %s (%d关) - %s" % [
			"●" if unlocked else "○",
			String(t.get("name_" + locale, t.get("name_en", ""))),
			int(t.get("min_levels", 0)),
			String(t.get("desc_" + locale, t.get("desc_en", "")))
		]
		tlabel.add_theme_font_override("font", UiAnimator.make_ui_font(18, false))
		tlabel.add_theme_font_size_override("font_size", 18)
		tlabel.add_theme_color_override("font_color", color)
		_tree_container.add_child(tlabel)


func _on_node_clicked(node: Dictionary) -> void:
	_detail_label.text = "[b]%s[/b]\n第%d章 第%d关\n\n分数: %.1f\n星数: %d\n证明深度: %d\n用时: %.1fs\n核心奖励: %d" % [
		String(node.get("title", "")),
		int(node.get("chapter", 0)),
		int(node.get("level", 0)),
		float(node.get("score", 0)),
		int(node.get("stars", 0)),
		int(node.get("proof_depth", 0)),
		float(node.get("time_spent", 0)),
		int(node.get("cores", 0)),
	]


func _on_close() -> void:
	UiAnimator.animate_out(self, func():
		visible = false
		panel_closed.emit()
	)


func show_panel() -> void:
	visible = true
	_refresh()
	UiAnimator.animate_in(self)
