# core_shop_panel.gd
# 核心商店（游戏性） - 用验证核心购买游戏性增强
# 与纯装饰性core_shop不同，这里的购买有实际游戏效果
#
# 商品:
#   - 预览迷雾: 1核心, 降低迷雾透明度5秒
#   - 紧急回溯: 2核心, 恢复守恒矩阵到上次WARNING状态
#   - 进化点兑换: 3核心=1进化点
#   - 解锁皮肤: 5核心, 随机解锁一个装饰皮肤
#
# Dependencies:
#   - Autoload: GameState, FogSystem, SoundManager

extends Control

var _i18n = null
signal purchase_made(item_id: String)

const SHOP_ITEMS: Array[Dictionary] = [
	{
		"id": "preview_fog",
		"name": "预览迷雾",
		"desc": "降低迷雾透明度5秒，窥见内部结构",
		"price": 1,
		"icon_color": Color(0.3, 0.5, 1.0),
	},
	{
		"id": "emergency_backtrack",
		"name": "紧急回溯",
		"desc": "将守恒矩阵恢复到上次WARNING状态",
		"price": 2,
		"icon_color": Color(1.0, 0.7, 0.2),
	},
	{
		"id": "evolve_exchange",
		"name": "进化点兑换",
		"desc": "3核心兑换1进化点，用于升级能力",
		"price": 3,
		"icon_color": Color(0.2, 1.0, 0.5),
	},
	{
		"id": "unlock_skin",
		"name": "解锁皮肤",
		"desc": "随机解锁一个装饰性原子皮肤",
		"price": 5,
		"icon_color": Color(1.0, 0.3, 0.8),
	},
]

var _cores_label: Label = null
var _evolve_label: Label = null
var _item_buttons: Dictionary = {}  # item_id -> Button
var _result_label: Label = null


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
	GameState.cores_changed.connect(_update_display)


func _assign_scene_nodes() -> void:
	var title_hbox = get_node_or_null("MainPanel/MarginContainer/VBox/TitleHBox")
	if title_hbox == null:
		push_warning("[核心商店] TitleHBox 节点缺失，回退到 _build_ui")
		_build_ui()
		return
	_cores_label = title_hbox.get_node_or_null("CoresLabel")
	var close_btn: Button = title_hbox.get_node_or_null("CloseBtn")
	if close_btn:
		close_btn.pressed.connect(_on_close)
	var evolve_hbox = get_node_or_null("MainPanel/MarginContainer/VBox/EvolveHBox")
	if evolve_hbox:
		_evolve_label = evolve_hbox.get_node_or_null("EvolveLabel")
	var items_container = get_node_or_null("MainPanel/MarginContainer/VBox/ItemsContainer")
	if items_container == null:
		push_warning("[核心商店] ItemsContainer 节点缺失")
		return
	# populate shop items
	for item in SHOP_ITEMS:
		var item_hbox := HBoxContainer.new()
		item_hbox.add_theme_constant_override("separation", 12)
		var icon := ColorRect.new()
		icon.color = item.icon_color
		icon.custom_minimum_size = Vector2(8, 50)
		item_hbox.add_child(icon)
		var info_vbox := VBoxContainer.new()
		info_vbox.add_theme_constant_override("separation", 2)
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_hbox.add_child(info_vbox)
		var name_label := Label.new()
		name_label.text = _i18n.translate("shop.item." + item.id) if _i18n != null else item.name
		name_label.add_theme_font_size_override("font_size", 22)
		info_vbox.add_child(name_label)
		var desc_label := Label.new()
		desc_label.text = _i18n.translate("shop.desc." + item.id) if _i18n != null else item.desc
		desc_label.add_theme_font_size_override("font_size", 18)
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		info_vbox.add_child(desc_label)
		var buy_vbox := VBoxContainer.new()
		buy_vbox.add_theme_constant_override("separation", 4)
		buy_vbox.custom_minimum_size = Vector2(120, 0)
		item_hbox.add_child(buy_vbox)
		var price_label := Label.new()
		price_label.text = _i18n.translate("hud.shop.price", {"n": item.price})
		price_label.add_theme_font_size_override("font_size", 20)
		price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		buy_vbox.add_child(price_label)
		var buy_btn := Button.new()
		buy_btn.text = _i18n.translate("hud.shop.buy")
		buy_btn.add_theme_font_size_override("font_size", 20)
		buy_btn.custom_minimum_size = Vector2(100, 36)
		buy_btn.pressed.connect(_on_purchase.bind(item.id))
		buy_vbox.add_child(buy_btn)
		_item_buttons[item.id] = buy_btn
		items_container.add_child(item_hbox)
	_result_label = get_node_or_null("MainPanel/MarginContainer/VBox/ResultLabel")
	_update_display()


func _setup_visuals() -> void:
	UiAnimator.style_all_panels(self)
	UiAnimator.style_all_buttons(self)
	UiAnimator.attach_button_helpers(self)
	_refresh_text()
	UiAnimator.animate_in(self)


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
	main_panel.offset_left = -320
	main_panel.offset_top = -280
	main_panel.offset_right = 320
	main_panel.offset_bottom = 280
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

	var close_btn := Button.new()
	close_btn.text = _i18n.translate("hud.close")
	close_btn.add_theme_font_override("font", UiAnimator.make_ui_font(22, true))
	close_btn.add_theme_font_size_override("font_size", 22)
	close_btn.pressed.connect(_on_close)
	title_hbox.add_child(close_btn)

	# 进化点显示
	var evolve_hbox := HBoxContainer.new()
	vbox.add_child(evolve_hbox)

	var evolve_prefix := Label.new()
	evolve_prefix.text = _i18n.translate("hud.evolve_points")
	evolve_prefix.add_theme_font_override("font", UiAnimator.make_ui_font(22, true))
	evolve_prefix.add_theme_font_size_override("font_size", 22)
	evolve_prefix.add_theme_color_override("font_color", UiAnimator.MUTED)
	evolve_hbox.add_child(evolve_prefix)

	_evolve_label = Label.new()
	_evolve_label.add_theme_font_override("font", _make_code_font(22, true))
	_evolve_label.add_theme_font_size_override("font_size", 22)
	_evolve_label.add_theme_color_override("font_color", UiAnimator.GREEN)
	evolve_hbox.add_child(_evolve_label)

	# 商品列表
	var sep1 := HSeparator.new()
	vbox.add_child(sep1)

	for item in SHOP_ITEMS:
		var item_hbox := HBoxContainer.new()
		item_hbox.add_theme_constant_override("separation", 12)
		vbox.add_child(item_hbox)

		# 图标色块
		var icon := ColorRect.new()
		icon.color = item.icon_color
		icon.custom_minimum_size = Vector2(8, 50)
		item_hbox.add_child(icon)

		# 信息区
		var info_vbox := VBoxContainer.new()
		info_vbox.add_theme_constant_override("separation", 2)
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_hbox.add_child(info_vbox)

		var name_label := Label.new()
		name_label.text = _i18n.translate("shop.item." + item.id) if _i18n != null else item.name
		name_label.add_theme_font_override("font", UiAnimator.make_ui_font(22, true))
		name_label.add_theme_font_size_override("font_size", 22)
		name_label.add_theme_color_override("font_color", UiAnimator.PAPER)
		info_vbox.add_child(name_label)

		var desc_label := Label.new()
		desc_label.text = _i18n.translate("shop.desc." + item.id) if _i18n != null else item.desc
		desc_label.add_theme_font_override("font", UiAnimator.make_ui_font(18, false))
		desc_label.add_theme_font_size_override("font_size", 18)
		desc_label.add_theme_color_override("font_color", UiAnimator.MUTED)
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		info_vbox.add_child(desc_label)

		# 价格 + 购买按钮
		var buy_vbox := VBoxContainer.new()
		buy_vbox.add_theme_constant_override("separation", 4)
		buy_vbox.custom_minimum_size = Vector2(120, 0)
		item_hbox.add_child(buy_vbox)

		var price_label := Label.new()
		price_label.text = _i18n.translate("hud.shop.price", {"n": item.price})
		price_label.add_theme_font_override("font", _make_code_font(20, true))
		price_label.add_theme_font_size_override("font_size", 20)
		price_label.add_theme_color_override("font_color", UiAnimator.AMBER)
		price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		buy_vbox.add_child(price_label)

		var buy_btn := Button.new()
		buy_btn.text = _i18n.translate("hud.shop.buy")
		buy_btn.add_theme_font_override("font", UiAnimator.make_ui_font(20, true))
		buy_btn.add_theme_font_size_override("font_size", 20)
		buy_btn.custom_minimum_size = Vector2(100, 36)
		buy_btn.pressed.connect(_on_purchase.bind(item.id))
		buy_vbox.add_child(buy_btn)

		_item_buttons[item.id] = buy_btn

	# 结果提示
	_result_label = Label.new()
	_result_label.add_theme_font_override("font", UiAnimator.make_ui_font(20, true))
	_result_label.add_theme_font_size_override("font_size", 20)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_result_label)

	_update_display()


func _on_purchase(item_id: String) -> void:
	match item_id:
		"preview_fog":
			_purchase_preview_fog()
		"emergency_backtrack":
			_purchase_emergency_backtrack()
		"evolve_exchange":
			_purchase_evolve_exchange()
		"unlock_skin":
			_purchase_unlock_skin()


func _purchase_preview_fog() -> void:
	if not GameState.spend_cores(1):
		_show_result(_i18n.translate("hud.shop.not_enough_cores") if _i18n != null else "", UiAnimator.RED)
		return
	# 调用迷雾预览
	var preview_ok := FogSystem.preview_fog(0)
	if preview_ok:
		_show_result(_i18n.translate("hud.shop.result_fog") if _i18n != null else "", UiAnimator.CYAN)
		SoundManager.play(SoundManager.SoundType.FOG_PEEK)
	else:
		_show_result(_i18n.translate("hud.shop.result_no_fog") if _i18n != null else "", UiAnimator.AMBER)
	purchase_made.emit("preview_fog")
	_update_display()


func _purchase_emergency_backtrack() -> void:
	if not GameState.spend_cores(2):
		_show_result(_i18n.translate("hud.shop.not_enough_cores") if _i18n != null else "", UiAnimator.RED)
		return
	var ok := GameState.emergency_backtrack()
	if ok:
		_show_result(_i18n.translate("hud.shop.result_backtrack") if _i18n != null else "", UiAnimator.AMBER)
		SoundManager.play(SoundManager.SoundType.DISINTEGRATE_START)
	else:
		_show_result(_i18n.translate("hud.shop.result_no_backtrack") if _i18n != null else "", UiAnimator.AMBER)
	purchase_made.emit("emergency_backtrack")
	_update_display()


func _purchase_evolve_exchange() -> void:
	if not GameState.exchange_cores_for_evolve_points(3):
		_show_result("核心不足! (需要3核心)", UiAnimator.RED)
		return
	_show_result(_i18n.translate("hud.shop.result_evolve") if _i18n != null else "", UiAnimator.GREEN)
	SoundManager.play(SoundManager.SoundType.CORE_SPEND)
	purchase_made.emit("evolve_exchange")
	_update_display()


func _purchase_unlock_skin() -> void:
	if not GameState.spend_cores(5):
		_show_result(_i18n.translate("hud.shop.not_enough_cores_cost", {"n": 5}) if _i18n != null else "", UiAnimator.RED)
		return
	# 随机选择一个皮肤解锁
	var skins := ["atom_neon", "atom_glass", "atom_wireframe", "atom_holographic"]
	var chosen: String = skins[randi() % skins.size()]
	_show_result(_i18n.translate("hud.shop.result_skin", {"skin": chosen}) if _i18n != null else "", UiAnimator.AMBER)
	SoundManager.play(SoundManager.SoundType.CORE_SPEND)
	purchase_made.emit("unlock_skin")
	_update_display()


func _show_result(text: String, color: Color) -> void:
	_result_label.text = text
	_result_label.add_theme_color_override("font_color", color)
	# 3秒后清除
	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(_result_label):
			_result_label.text = ""
	)


func _update_display() -> void:
	if _cores_label:
		_cores_label.text = _i18n.translate("hud.cores_format", {"n": GameState.verification_cores})
	if _evolve_label:
		_evolve_label.text = "%d" % GameState.evolve_points

	# 更新按钮可用状态
	for item in SHOP_ITEMS:
		var btn: Button = _item_buttons.get(item.id)
		if btn:
			btn.disabled = GameState.verification_cores < item.price


func _on_close() -> void:
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

func _exit_tree() -> void:
	if _i18n != null and _i18n.is_connected("language_changed", _on_language_changed):
		_i18n.language_changed.disconnect(_on_language_changed)
	if GameState != null and GameState.cores_changed.is_connected(_update_display):
		GameState.cores_changed.disconnect(_update_display)

func _on_language_changed(_locale: String) -> void:
	_refresh_text()

func _refresh_text() -> void:
	if _i18n == null:
		return

