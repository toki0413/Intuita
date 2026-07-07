extends Node
# UI 动画与样式工具 autoload
# 提供统一的入场/出场/hover/状态反馈动画

# 字体缩放因子，从 SettingsManager 读取
var _font_scale: float = 1.0
# 减少闪烁（癫痫安全），从 SettingsManager 读取
var _reduce_flashing: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if SettingsManager != null:
		_font_scale = float(SettingsManager.get_setting("font_scale", 1.0))
		_reduce_flashing = bool(SettingsManager.get_setting("reduce_flashing", false))
		SettingsManager.setting_changed.connect(_on_setting_changed)

func _exit_tree() -> void:
	if SettingsManager != null and SettingsManager.is_connected("setting_changed", _on_setting_changed):
		SettingsManager.setting_changed.disconnect(_on_setting_changed)

func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "font_scale":
		_font_scale = float(value)
		# 清除字体缓存，让后续调用按新缩放重建
		_font_cache.clear()
	elif key == "reduce_flashing":
		_reduce_flashing = bool(value)

# 查询是否启用了减少闪烁模式
func is_flashing_reduced() -> bool:
	return _reduce_flashing

# 根据闪烁安全设置缩放动画时长：开启时所有闪烁动画至少 0.4s
func safe_flash_duration(duration: float) -> float:
	if _reduce_flashing:
		return maxf(duration, 0.4)
	return duration

const COLOR_BG_DEEP := Color("030406")
const COLOR_BG_PANEL := Color("0a0d12")
const COLOR_PAPER := Color("e8e6e3")
const COLOR_MUTED := Color("8b919c")
const COLOR_CYAN := Color("00f0ff")
const CYAN_DIM := Color("001d1f") # 约等于 COLOR_CYAN.darkened(0.88)
const BORDER := Color("002629")   # 约等于 COLOR_CYAN.darkened(0.84)
const BORDER_HOVER := Color("007880") # 约等于 COLOR_CYAN.darkened(0.5)
const COLOR_AMBER := Color("ff9f43")
const COLOR_GREEN := Color("39ff14")
const COLOR_RED := Color("ff4d4d")

# 颜色常量别名，方便面板脚本直接使用
const PAPER := COLOR_PAPER
const MUTED := COLOR_MUTED
const CYAN := COLOR_CYAN
const AMBER := COLOR_AMBER
const GREEN := COLOR_GREEN
const RED := COLOR_RED

# 内部使用的完整命名别名（与外部短别名保持同一值）
const COLOR_CYAN_DIM := CYAN_DIM
const COLOR_BORDER := BORDER
const COLOR_BORDER_HOVER := BORDER_HOVER

const DURATION_FAST := 0.2
const DURATION_NORMAL := 0.35
const DURATION_SLOW := 0.6

# 给面板应用统一玻璃拟态样式
func style_panel(panel: Control) -> void:
	if panel == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG_PANEL
	style.bg_color.a = 0.72
	style.border_color = COLOR_BORDER
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_right = 12
	style.corner_radius_bottom_left = 12
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 20
	style.shadow_offset = Vector2(0, 8)
	panel.add_theme_stylebox_override("panel", style)

# 给按钮应用统一样式
func style_button(btn: Button, is_primary: bool = false) -> void:
	if btn == null:
		return
	var normal := StyleBoxFlat.new()
	var hover := StyleBoxFlat.new()
	var pressed := StyleBoxFlat.new()

	if is_primary:
		_setup_flat(normal, COLOR_CYAN, COLOR_CYAN, 8)
		_setup_flat(hover, COLOR_PAPER, COLOR_PAPER, 8)
		_setup_flat(pressed, COLOR_CYAN.darkened(0.2), COLOR_CYAN.darkened(0.2), 8)
		btn.add_theme_color_override("font_color", COLOR_BG_DEEP)
		btn.add_theme_color_override("font_hover_color", COLOR_BG_DEEP)
		btn.add_theme_color_override("font_pressed_color", COLOR_BG_DEEP)
	else:
		_setup_flat(normal, Color(0, 0, 0, 0), COLOR_BORDER, 8)
		_setup_flat(hover, COLOR_CYAN_DIM, COLOR_BORDER_HOVER, 8)
		_setup_flat(pressed, COLOR_CYAN.darkened(0.85), COLOR_CYAN, 8)
		btn.add_theme_color_override("font_color", COLOR_CYAN)
		btn.add_theme_color_override("font_hover_color", COLOR_PAPER)
		btn.add_theme_color_override("font_pressed_color", COLOR_PAPER)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	btn.focus_mode = Control.FOCUS_NONE

func _setup_flat(style: StyleBoxFlat, bg: Color, border: Color, radius: int) -> void:
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius

# 给标签上色
func style_label(label: Label, is_muted: bool = false, is_code: bool = false) -> void:
	if label == null:
		return
	if is_code:
		label.add_theme_color_override("font_color", COLOR_CYAN)
		label.add_theme_font_size_override("font_size", 12)
	elif is_muted:
		label.add_theme_color_override("font_color", COLOR_MUTED)
	else:
		label.add_theme_color_override("font_color", COLOR_PAPER)

# ---- 统一字体工厂 ----
# 字体缓存：避免每次调用都新建 FontVariation，key = "size_bold"
var _font_cache: Dictionary = {}

# 创建统一 UI 字体。Arial 优先，20pt 起步，加粗由 bold 控制。
# 所有 HUD 面板都应通过此方法获取字体，不要各自重复实现。
func make_ui_font(size: int, bold: bool = false) -> Font:
	# 强制最小 20pt，再乘以用户设置的缩放因子
	var scaled_size: int = maxi(int(roundi(size * _font_scale)), 20)
	var cache_key := "%d_%d" % [scaled_size, 1 if bold else 0]
	if _font_cache.has(cache_key):
		return _font_cache[cache_key]

	var sys_font := SystemFont.new()
	# Arial 放第一位，保证 Windows/跨平台一致性
	sys_font.font_names = PackedStringArray(["Arial", "Segoe UI", "Helvetica", "Noto Sans"])
	sys_font.font_weight = 700 if bold else 400
	sys_font.font_stretch = 100

	var fv := FontVariation.new()
	fv.base_font = sys_font
	fv.variation_embolden = 0.6 if bold else 0.0
	_font_cache[cache_key] = fv
	return fv

# ---- 场景切换过渡 ----
var _fade_overlay: ColorRect = null

# 用淡入淡出包裹场景切换，避免突兀的硬切
func fade_change_scene(scene_path: String, fade_duration: float = 0.3) -> void:
	var tree := get_tree()
	if tree == null:
		return
	# 创建全屏遮罩
	if _fade_overlay == null:
		_fade_overlay = ColorRect.new()
		_fade_overlay.color = Color.BLACK
		_fade_overlay.color.a = 0.0
		_fade_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
		_fade_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		var canvas := CanvasLayer.new()
		canvas.layer = 100
		canvas.add_child(_fade_overlay)
		tree.root.add_child(canvas)
	# 淡出 → 切换 → 淡入
	var tween := create_tween()
	tween.tween_property(_fade_overlay, "color:a", 1.0, fade_duration)
	tween.tween_callback(func():
		tree.change_scene_to_file(scene_path)
	)
	tween.tween_interval(0.05)
	tween.tween_property(_fade_overlay, "color:a", 0.0, fade_duration)

# 面板入场动画：从下方淡入 + 轻微上浮
func animate_in(node: Control, delay: float = 0.0) -> void:
	if node == null:
		return
	node.modulate.a = 0.0
	node.position.y += 30
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_OUT)
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(node, "modulate:a", 1.0, DURATION_SLOW)
	tween.parallel().tween_property(node, "position:y", node.position.y - 30, DURATION_SLOW)

# 面板出场动画
func animate_out(node: Control, callback: Callable = Callable()) -> void:
	if node == null:
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(node, "modulate:a", 0.0, DURATION_NORMAL)
	tween.parallel().tween_property(node, "position:y", node.position.y + 20, DURATION_NORMAL)
	if callback.is_valid():
		tween.tween_callback(callback)

# 按钮 hover 缩放脉冲
func pulse_scale(node: Control, amount: float = 1.05) -> void:
	if node == null:
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "scale", Vector2(amount, amount), 0.15)
	tween.tween_property(node, "scale", Vector2(1.0, 1.0), 0.25)

# 成功闪光
func flash_success(node: Control) -> void:
	if node == null:
		return
	var tween := create_tween()
	var base := node.modulate
	tween.tween_property(node, "modulate", COLOR_GREEN, safe_flash_duration(0.1))
	tween.tween_property(node, "modulate", base, safe_flash_duration(0.4))

# 失败抖动
func shake(node: Control) -> void:
	if node == null:
		return
	var original := node.position.x
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	for i in range(6):
		var offset := 8.0 if i % 2 == 0 else -8.0
		tween.tween_property(node, "position:x", original + offset, 0.05)
	tween.tween_property(node, "position:x", original, 0.05)

# 构造统一样式的自定义 tooltip，配合 _make_custom_tooltip 使用
# 返回的 PanelContainer 自带淡入动画
func make_tooltip(text: String) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG_DEEP
	style.bg_color.a = 0.92
	style.border_color = COLOR_CYAN_DIM
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 10
	style.content_margin_top = 6
	style.content_margin_right = 10
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", COLOR_PAPER)
	label.add_theme_font_size_override("font_size", 13)
	panel.add_child(label)

	# 入场淡入
	panel.modulate.a = 0.0
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "modulate:a", 1.0, 0.15)
	return panel

# 给容器内所有按钮统一应用样式
func style_all_buttons(root: Control, primary_names: Array[String] = []) -> void:
	if root == null:
		return
	for child in root.get_children(true):
		if child is Button:
			style_button(child, child.name in primary_names)

# 给容器内所有面板统一应用样式
func style_all_panels(root: Control) -> void:
	if root == null:
		return
	for child in root.get_children(true):
		if child is Panel or child is PanelContainer:
			style_panel(child)


# 为容器内所有无脚本按钮挂载 button_helper.gd，获得统一缩放和音效反馈
func attach_button_helpers(root: Control) -> void:
	if root == null:
		return
	var helper_script := load("res://scripts/hud/button_helper.gd")
	if helper_script == null:
		push_warning("UiAnimator: 无法加载 button_helper.gd")
		return
	for child in root.get_children(true):
		if child is Button and child.get_script() == null:
			child.set_script(helper_script)


# 加载系统字体备用（兼容旧面板脚本）
func _load_system_font(names: PackedStringArray, weight: int = 400) -> Font:
	var sys_font := SystemFont.new()
	sys_font.font_names = names
	sys_font.font_weight = weight
	sys_font.font_stretch = 100
	var fv := FontVariation.new()
	fv.base_font = sys_font
	fv.variation_embolden = 0.6 if weight >= 600 else 0.0
	return fv
