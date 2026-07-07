# intuita_theme.gd
# Intuita UI主题 - 深色科技感设计系统
# 通过代码动态构建Theme资源，确保跨平台字体回退

extends Theme

# 色彩系统
const BG_DEEP := Color("030406")
const BG_PANEL := Color("0a0d12")
const PAPER := Color("e8e6e3")
const MUTED := Color("8b919c")
const CYAN := Color("00f0ff")
const CYAN_DIM := Color(0.0, 0.94, 1.0, 0.12)
const AMBER := Color("ff9f43")
const GREEN := Color("39ff14")
const RED := Color("ff4d4d")
const BORDER := Color(0.0, 0.94, 1.0, 0.16)
const BORDER_HOVER := Color(0.0, 0.94, 1.0, 0.5)


func _init() -> void:
	_setup_fonts()
	_setup_colors()
	_setup_constants()
	_setup_button_styles()
	_setup_panel_styles()
	_setup_line_edit_styles()


func _setup_fonts() -> void:
	# Arial 优先，保留 CJK 字体作为中文回退
	var ui_font: Font = _load_system_font(
		["Arial", "Microsoft YaHei", "PingFang SC", "Segoe UI"], 500)
	var ui_font_bold: Font = _load_system_font(
		["Arial", "Microsoft YaHei", "PingFang SC", "Segoe UI"], 700)
	var code_font: Font = _load_system_font(
		["JetBrains Mono", "Cascadia Code", "Consolas", "Menlo", "Courier New"], 400)

	set_font("font", "Label", ui_font)
	set_font_size("font_size", "Label", 20)

	set_font("font", "Button", ui_font_bold)
	set_font_size("font_size", "Button", 20)

	set_font("font", "RichTextLabel", ui_font)
	set_font("mono_font", "RichTextLabel", code_font)
	set_font_size("font_size", "RichTextLabel", 20)
	set_font_size("mono_font_size", "RichTextLabel", 18)

	set_font("font", "CheckBox", ui_font)
	set_font_size("font_size", "CheckBox", 20)

	set_font("font", "LineEdit", ui_font)
	set_font_size("font_size", "LineEdit", 20)

	set_font("title_font", "Label", ui_font_bold)
	set_font_size("title_font_size", "Label", 26)

	set_font("header_font", "Label", ui_font_bold)
	set_font_size("header_font_size", "Label", 34)


func _load_system_font(names: Array, weight: int) -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(names)
	font.font_weight = weight
	font.font_stretch = 100
	return font


func _setup_colors() -> void:
	set_color("font_color", "Label", PAPER)
	set_color("font_color", "Button", CYAN)
	set_color("font_hover_color", "Button", PAPER)
	set_color("font_pressed_color", "Button", PAPER)
	set_color("font_disabled_color", "Button", Color(MUTED, 0.5))
	set_color("font_color", "CheckBox", PAPER)
	set_color("font_color", "RichTextLabel", PAPER)
	set_color("icon_color", "Button", CYAN)
	set_color("icon_hover_color", "Button", PAPER)
	set_color("font_color", "LineEdit", PAPER)
	set_color("font_placeholder_color", "LineEdit", MUTED)
	set_color("caret_color", "LineEdit", CYAN)
	set_color("selection_color", "LineEdit", CYAN_DIM)

	# 守恒状态颜色
	set_type_variation("ConservationHealthy", "Label")
	set_color("font_color", "ConservationHealthy", GREEN)
	set_type_variation("ConservationWarning", "Label")
	set_color("font_color", "ConservationWarning", AMBER)
	set_type_variation("ConservationCritical", "Label")
	set_color("font_color", "ConservationCritical", RED)
	set_type_variation("ConservationDisintegrated", "Label")
	set_color("font_color", "ConservationDisintegrated", Color(0.7, 0.2, 0.6))


func _setup_constants() -> void:
	set_constant("separation", "VBoxContainer", 16)
	set_constant("separation", "HBoxContainer", 16)
	set_constant("h_separation", "Button", 16)
	set_constant("v_separation", "Button", 12)
	set_constant("line_spacing", "Label", 6)
	set_constant("margin_left", "MarginContainer", 24)
	set_constant("margin_top", "MarginContainer", 24)
	set_constant("margin_right", "MarginContainer", 24)
	set_constant("margin_bottom", "MarginContainer", 24)


func _setup_button_styles() -> void:
	var normal := _make_flat_style(Color(0, 0, 0, 0), BORDER, 8)
	var hover := _make_flat_style(CYAN_DIM, BORDER_HOVER, 8)
	var pressed := _make_flat_style(Color(CYAN.r * 0.15, CYAN.g * 0.15, CYAN.b * 0.15, 0.6), CYAN, 8)
	var disabled := _make_flat_style(Color(0, 0, 0, 0), Color(MUTED, 0.25), 8)

	set_stylebox("normal", "Button", normal)
	set_stylebox("hover", "Button", hover)
	set_stylebox("pressed", "Button", pressed)
	set_stylebox("disabled", "Button", disabled)
	set_stylebox("focus", "Button", StyleBoxEmpty.new())

	# 主要按钮样式（青色实心）
	var primary_normal := _make_flat_style(CYAN, CYAN, 8)
	var primary_hover := _make_flat_style(PAPER, PAPER, 8)
	var primary_pressed := _make_flat_style(CYAN.darkened(0.2), CYAN.darkened(0.2), 8)
	set_stylebox("normal", "PrimaryButton", primary_normal)
	set_stylebox("hover", "PrimaryButton", primary_hover)
	set_stylebox("pressed", "PrimaryButton", primary_pressed)
	set_color("font_color", "PrimaryButton", BG_DEEP)
	set_color("font_hover_color", "PrimaryButton", BG_DEEP)
	set_color("font_pressed_color", "PrimaryButton", BG_DEEP)


func _setup_panel_styles() -> void:
	var panel := _make_flat_style(Color(BG_PANEL, 0.72), BORDER, 12)
	panel.shadow_color = Color(0, 0, 0, 0.5)
	panel.shadow_size = 24
	panel.shadow_offset = Vector2(0, 10)
	set_stylebox("panel", "Panel", panel)
	set_stylebox("panel", "PanelContainer", panel)


func _setup_line_edit_styles() -> void:
	var normal := _make_flat_style(Color(0, 0, 0, 0.3), BORDER, 6)
	var focus := _make_flat_style(Color(CYAN.r * 0.1, CYAN.g * 0.1, CYAN.b * 0.1, 0.4), CYAN, 6)
	set_stylebox("normal", "LineEdit", normal)
	set_stylebox("focus", "LineEdit", focus)
	set_stylebox("read_only", "LineEdit", normal)


func _make_flat_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
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
	return style
