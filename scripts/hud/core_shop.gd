# core_shop.gd
# 核心商店 - 纯装饰性物品购买，不影响游戏性
# 物品类型: 原子皮肤 / Wyckoff标记样式 / 背景主题 / 音效包
#
# Responsibilities:
#   - 商品展示和购买逻辑
#   - 已购物品持久化存储
#   - 物品预览和装备切换
#
# Dependencies:
#   - Autoload: GameState

extends Control

var _i18n = null
const SAVE_PATH := "user://core_shop_save.dat"

enum ItemCategory { ATOM_SKIN, WYCKOFF_MARKER, BACKGROUND_THEME, SOUND_PACK }

# 商品目录 — 全部纯装饰
const SHOP_CATALOG: Array[Dictionary] = [
	# 原子皮肤
	{"id": "atom_neon", "category": 0, "name": "霓虹原子", "desc": "发光霓虹风格原子外观", "price": 5},
	{"id": "atom_glass", "category": 0, "name": "玻璃原子", "desc": "半透明玻璃质感原子", "price": 5},
	{"id": "atom_wireframe", "category": 0, "name": "线框原子", "desc": "极简线框风格原子", "price": 5},
	{"id": "atom_holographic", "category": 0, "name": "全息原子", "desc": "全息投影效果原子", "price": 5},
	# Wyckoff标记样式
	{"id": "wyckoff_diamond", "category": 1, "name": "菱形标记", "desc": "菱形Wyckoff位置标记", "price": 3},
	{"id": "wyckoff_star", "category": 1, "name": "星形标记", "desc": "五角星Wyckoff位置标记", "price": 3},
	{"id": "wyckoff_hexagon", "category": 1, "name": "六边形标记", "desc": "六边形Wyckoff位置标记", "price": 3},
	# 背景主题
	{"id": "bg_lab", "category": 2, "name": "实验室", "desc": "经典实验室3D场景背景", "price": 10},
	{"id": "bg_space", "category": 2, "name": "太空", "desc": "深空星域3D场景背景", "price": 10},
	{"id": "bg_ocean", "category": 2, "name": "深海", "desc": "深海环境3D场景背景", "price": 10},
	{"id": "bg_abstract", "category": 2, "name": "抽象", "desc": "抽象几何3D场景背景", "price": 10},
	# 音效包
	{"id": "snd_mechanical", "category": 3, "name": "机械音效", "desc": "齿轮与金属碰撞风格音效", "price": 8},
	{"id": "snd_organic", "category": 3, "name": "有机音效", "desc": "自然与生命风格音效", "price": 8},
	{"id": "snd_digital", "category": 3, "name": "数字音效", "desc": "电子与数字风格音效", "price": 8},
]

var _purchased_items: Dictionary = {}  # id -> true
var _equipped_items: Dictionary = {}   # category -> id

var _category_tabs: TabBar = null
var _item_grid: GridContainer = null
var _cores_label: Label = null
var _preview_panel: PanelContainer = null
var _preview_title: Label = null
var _preview_desc: Label = null
var _preview_price: Label = null
var _buy_btn: Button = null
var _equip_btn: Button = null
var _close_btn: Button = null

var _selected_item_id: String = ""


func _ready() -> void:
	_i18n = Engine.get_main_loop().root.get_node_or_null("/root/I18nManager")
	if _i18n != null and _i18n.has_signal("language_changed"):
		_i18n.language_changed.connect(_on_language_changed)
	_load_save()
	if get_child_count() > 0:
		_assign_scene_nodes()
	else:
		_build_ui()
	_setup_visuals()
	_update_cores_display()


func _exit_tree() -> void:
	if _i18n != null and _i18n.is_connected("language_changed", _on_language_changed):
		_i18n.language_changed.disconnect(_on_language_changed)


func _assign_scene_nodes() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	self_modulate = Color(1, 1, 1, 0)
	var title_hbox = get_node_or_null("MainPanel/MarginContainer/VBox/TitleHBox")
	if title_hbox == null:
		push_warning("[核心商店] TitleHBox 节点缺失，回退到 _build_ui")
		_build_ui()
		return
	_cores_label = title_hbox.get_node_or_null("CoresLabel")
	_close_btn = title_hbox.get_node_or_null("CloseBtn")
	if _close_btn:
		_close_btn.pressed.connect(_on_close)
	_category_tabs = get_node_or_null("MainPanel/MarginContainer/VBox/CategoryTabs")
	if _category_tabs:
		_category_tabs.tab_changed.connect(_on_category_changed)
	_item_grid = get_node_or_null("MainPanel/MarginContainer/VBox/ContentHBox/ScrollContainer/ItemGrid")
	var preview_panel = get_node_or_null("MainPanel/MarginContainer/VBox/ContentHBox/PreviewPanel")
	if preview_panel == null:
		push_warning("[核心商店] PreviewPanel 节点缺失")
		return
	var preview_vbox = preview_panel.get_node_or_null("PreviewMargin/PreviewVBox")
	if preview_vbox == null:
		push_warning("[核心商店] PreviewVBox 节点缺失")
		return
	_preview_title = preview_vbox.get_node_or_null("PreviewTitle")
	_preview_desc = preview_vbox.get_node_or_null("PreviewDesc")
	_preview_price = preview_vbox.get_node_or_null("PreviewPrice")
	_buy_btn = preview_vbox.get_node_or_null("BuyBtn")
	if _buy_btn:
		_buy_btn.pressed.connect(_on_buy)
	_equip_btn = preview_vbox.get_node_or_null("EquipBtn")
	if _equip_btn:
		_equip_btn.pressed.connect(_on_equip)
	_populate_grid(0)


func _setup_visuals() -> void:
	# 修复 self_modulate 初始为 0 导致不可见的问题
	self_modulate = Color.WHITE
	# 样式化所有嵌套面板
	UiAnimator.style_all_panels(self)
	# 统一按钮样式和反馈
	UiAnimator.style_all_buttons(self, ["BuyBtn"])
	UiAnimator.attach_button_helpers(self)
	_refresh_text()
	UiAnimator.animate_in(self)


func _build_ui() -> void:
	# 全屏半透明背景
	anchors_preset = Control.PRESET_FULL_RECT
	self_modulate = Color(1, 1, 1, 0)

	var bg := ColorRect.new()
	bg.color = Color(UiAnimator.COLOR_BG_DEEP, 0.92)
	bg.anchors_preset = Control.PRESET_FULL_RECT
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# 主面板
	var main_panel := PanelContainer.new()
	main_panel.anchors_preset = Control.PRESET_CENTER
	main_panel.offset_left = -420
	main_panel.offset_top = -320
	main_panel.offset_right = 420
	main_panel.offset_bottom = 320
	add_child(main_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	main_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# 标题行
	var title_hbox := HBoxContainer.new()
	vbox.add_child(title_hbox)

	var title := Label.new()
	title.text = _i18n.translate("hud.shop.title")
	title.add_theme_font_override("font", UiAnimator.make_ui_font(28, true))
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UiAnimator.CYAN)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_hbox.add_child(title)

	_cores_label = Label.new()
	_cores_label.add_theme_font_override("font", UiAnimator.make_ui_font(22, true))
	_cores_label.add_theme_font_size_override("font_size", 22)
	_cores_label.add_theme_color_override("font_color", UiAnimator.AMBER)
	title_hbox.add_child(_cores_label)

	_close_btn = Button.new()
	_close_btn.text = _i18n.translate("hud.close")
	_close_btn.add_theme_font_override("font", UiAnimator.make_ui_font(22, true))
	_close_btn.add_theme_font_size_override("font_size", 22)
	_close_btn.pressed.connect(_on_close)
	title_hbox.add_child(_close_btn)

	# 分类标签
	_category_tabs = TabBar.new()
	_category_tabs.tab_count = 4
	_category_tabs.set_tab_title(0, _i18n.translate("hud.shop.tab_skins"))
	_category_tabs.set_tab_title(1, _i18n.translate("hud.shop.tab_wyckoff"))
	_category_tabs.set_tab_title(2, _i18n.translate("hud.shop.tab_backgrounds"))
	_category_tabs.set_tab_title(3, _i18n.translate("hud.shop.tab_sounds"))
	_category_tabs.add_theme_font_override("font", UiAnimator.make_ui_font(20, true))
	_category_tabs.add_theme_font_size_override("font_size", 20)
	_category_tabs.tab_changed.connect(_on_category_changed)
	vbox.add_child(_category_tabs)

	# 内容区域: 左侧商品列表 + 右侧预览
	var content_hbox := HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 16)
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(content_hbox)

	# 左侧: 商品网格
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 2.0
	content_hbox.add_child(scroll)

	_item_grid = GridContainer.new()
	_item_grid.columns = 2
	_item_grid.add_theme_constant_override("h_separation", 8)
	_item_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_item_grid)

	# 右侧: 预览面板
	_preview_panel = PanelContainer.new()
	_preview_panel.custom_minimum_size = Vector2(200, 0)
	_preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_panel.size_flags_stretch_ratio = 1.0
	content_hbox.add_child(_preview_panel)

	var preview_margin := MarginContainer.new()
	preview_margin.add_theme_constant_override("margin_all", 16)
	_preview_panel.add_child(preview_margin)

	var preview_vbox := VBoxContainer.new()
	preview_vbox.add_theme_constant_override("separation", 12)
	preview_margin.add_child(preview_vbox)

	_preview_title = Label.new()
	_preview_title.add_theme_font_override("font", UiAnimator.make_ui_font(24, true))
	_preview_title.add_theme_font_size_override("font_size", 24)
	_preview_title.add_theme_color_override("font_color", UiAnimator.PAPER)
	preview_vbox.add_child(_preview_title)

	_preview_desc = Label.new()
	_preview_desc.add_theme_font_override("font", UiAnimator.make_ui_font(20, false))
	_preview_desc.add_theme_font_size_override("font_size", 20)
	_preview_desc.add_theme_color_override("font_color", UiAnimator.MUTED)
	_preview_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	preview_vbox.add_child(_preview_desc)

	_preview_price = Label.new()
	_preview_price.add_theme_font_override("font", _make_code_font(20, true))
	_preview_price.add_theme_font_size_override("font_size", 20)
	_preview_price.add_theme_color_override("font_color", UiAnimator.AMBER)
	preview_vbox.add_child(_preview_price)

	var btn_spacer := VSeparator.new()
	btn_spacer.custom_minimum_size = Vector2(0, 20)
	preview_vbox.add_child(btn_spacer)

	_buy_btn = Button.new()
	_buy_btn.text = _i18n.translate("hud.shop.buy")
	_buy_btn.add_theme_font_override("font", UiAnimator.make_ui_font(22, true))
	_buy_btn.add_theme_font_size_override("font_size", 22)
	_buy_btn.pressed.connect(_on_buy)
	_buy_btn.disabled = true
	preview_vbox.add_child(_buy_btn)

	_equip_btn = Button.new()
	_equip_btn.text = _i18n.translate("hud.shop.equip")
	_equip_btn.add_theme_font_override("font", UiAnimator.make_ui_font(22, true))
	_equip_btn.add_theme_font_size_override("font_size", 22)
	_equip_btn.pressed.connect(_on_equip)
	_equip_btn.disabled = true
	preview_vbox.add_child(_equip_btn)

	# 初始填充
	_populate_grid(0)


func _populate_grid(category: int) -> void:
	for child in _item_grid.get_children():
		child.queue_free()

	for item in SHOP_CATALOG:
		if item["category"] != category:
			continue

		var btn := Button.new()
		btn.text = _i18n.translate("shop.item." + item["id"]) if _i18n != null else item["name"]
		btn.add_theme_font_override("font", UiAnimator.make_ui_font(20, true))
		btn.add_theme_font_size_override("font_size", 20)

		if _purchased_items.has(item["id"]):
			btn.add_theme_color_override("font_color", UiAnimator.GREEN)
		else:
			btn.add_theme_color_override("font_color", UiAnimator.PAPER)

		var item_id: String = item["id"]
		btn.pressed.connect(_on_item_selected.bind(item_id))
		_item_grid.add_child(btn)


func _on_category_changed(idx: int) -> void:
	_selected_item_id = ""
	_populate_grid(idx)
	_clear_preview()


func _on_item_selected(item_id: String) -> void:
	_selected_item_id = item_id
	var item := _find_item(item_id)
	if item.is_empty():
		return

	_preview_title.text = _i18n.translate("shop.item." + item["id"]) if _i18n != null else item["name"]
	_preview_desc.text = _i18n.translate("shop.desc." + item["id"]) if _i18n != null else item["desc"]

	if _purchased_items.has(item_id):
		_preview_price.text = _i18n.translate("hud.shop.owned")
		_buy_btn.disabled = true
		_equip_btn.disabled = false
		if _equipped_items.get(item["category"]) == item_id:
			_equip_btn.text = _i18n.translate("hud.shop.equipped")
			_equip_btn.disabled = true
		else:
			_equip_btn.text = _i18n.translate("hud.shop.equip")
			_equip_btn.disabled = false
	else:
		_preview_price.text = "%d 核心" % item["price"]
		_buy_btn.disabled = GameState.verification_cores < item["price"]
		_equip_btn.disabled = true
		_equip_btn.text = _i18n.translate("hud.shop.equip")


func _on_buy() -> void:
	if _selected_item_id == "":
		return
	var item := _find_item(_selected_item_id)
	if item.is_empty():
		return
	if _purchased_items.has(_selected_item_id):
		return
	if not GameState.spend_cores(item["price"]):
		return

	_purchased_items[_selected_item_id] = true
	_save()
	_update_cores_display()
	_on_item_selected(_selected_item_id)
	_populate_grid(_category_tabs.current_tab)
	SoundManager.play(SoundManager.SoundType.CORE_SPEND)


func _on_equip() -> void:
	if _selected_item_id == "":
		return
	var item := _find_item(_selected_item_id)
	if item.is_empty():
		return
	if not _purchased_items.has(_selected_item_id):
		return

	_equipped_items[item["category"]] = _selected_item_id
	_save()
	_on_item_selected(_selected_item_id)


func _on_close() -> void:
	UiAnimator.animate_out(self, queue_free)


func _clear_preview() -> void:
	_preview_title.text = _i18n.translate("hud.shop.select_item")
	_preview_desc.text = ""
	_preview_price.text = ""
	_buy_btn.disabled = true
	_equip_btn.disabled = true


func _update_cores_display() -> void:
	_cores_label.text = _i18n.translate("hud.cores_format", {"n": GameState.verification_cores})


func _find_item(item_id: String) -> Dictionary:
	for item in SHOP_CATALOG:
		if item["id"] == item_id:
			return item
	return {}


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


func _save() -> void:
	var data := {
		"purchased": _purchased_items,
		"equipped": _equipped_items,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()


func _load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	var data: Dictionary = json.data
	_purchased_items = data.get("purchased", {})
	_equipped_items = data.get("equipped", {})

func _on_language_changed(_locale: String) -> void:
	_refresh_text()

func _refresh_text() -> void:
	if _i18n == null:
		return

