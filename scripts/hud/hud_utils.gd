# hud_utils.gd
# HUD通用工具函数 - 递归设置mouse_filter、折叠逻辑等
# 使用 const HudUtils = preload("res://scripts/hud/hud_utils.gd") 引用


# 交互控件类名白名单 - 这些需要接收鼠标事件
const INTERACTIVE_CLASSES: PackedStringArray = [
	"Button", "CheckBox", "CheckButton", "Tree", "ItemList",
	"LineEdit", "TextEdit", "RichTextLabel", "Slider", "SpinBox",
	"OptionButton", "MenuButton", "TextureButton", "LinkButton",
	"PopupMenu", "TabBar", "TabContainer",
]


# 递归设置所有非交互子节点的mouse_filter为IGNORE
# 交互控件保持默认STOP，其余全部设为IGNORE，让鼠标事件穿透到3D场景
static func set_passthrough(node: Control) -> void:
	var class_name_str: String = node.get_class()
	var is_interactive: bool = class_name_str in INTERACTIVE_CLASSES
	if not is_interactive:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 递归处理子节点
	for child in node.get_children():
		if child is Control:
			set_passthrough(child)


# 给面板添加折叠标题栏
# 返回值: [collapse_btn, content_wrapper, title_label]
static func make_collapsible(panel: PanelContainer, title: String, collapsed_by_default: bool = false) -> Array:
	# 找到第一个MarginContainer/VBoxContainer作为内容包装
	var content_wrapper: Control = null
	for child in panel.get_children():
		if child is MarginContainer or child is VBoxContainer:
			content_wrapper = child
			break

	if content_wrapper == null:
		# 没有内容包装，创建一个
		content_wrapper = VBoxContainer.new()
		var children_to_move: Array = []
		for child in panel.get_children():
			children_to_move.append(child)
		for child in children_to_move:
			panel.remove_child(child)
			content_wrapper.add_child(child)
		panel.add_child(content_wrapper)

	# 创建标题栏
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)

	var collapse_btn := Button.new()
	collapse_btn.text = "▼" if not collapsed_by_default else "▶"
	collapse_btn.custom_minimum_size = Vector2(28, 28)
	collapse_btn.add_theme_font_size_override("font_size", 14)
	collapse_btn.flat = true

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", Color(0, 0.831, 1, 1))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	header.add_child(collapse_btn)
	header.add_child(title_label)

	# 插入标题栏到面板最前面
	panel.add_child(header)
	panel.move_child(header, 0)

	# 折叠状态
	var is_collapsed: bool = collapsed_by_default
	if collapsed_by_default:
		content_wrapper.visible = false

	# 绑定折叠切换
	collapse_btn.pressed.connect(func() -> void:
		is_collapsed = not is_collapsed
		content_wrapper.visible = not is_collapsed
		collapse_btn.text = "▶" if is_collapsed else "▼"
	)

	return [collapse_btn, content_wrapper, title_label]
