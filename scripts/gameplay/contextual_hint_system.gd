# contextual_hint_system.gd
# 上下文指引系统 - 根据当前工具和游戏状态动态显示操作提示
# 解决"玩家不知道怎么放原子"的核心痛点
#
# 工作方式:
#   1. 监听 tool_changed 信号，切换工具时显示该工具的操作说明
#   2. 定期检查游戏状态(无原子/有原子无键/有键未验证等)，给出下一步建议
#   3. PLACE 模式下若无原子，高亮脉冲最近的 Wyckoff 标记

extends Node

var _canvas: Node3D = null
var _atom_mgr: RefCounted = null
var _camera: Camera3D = null
var _hint_label: Label = null
var _hint_panel: PanelContainer = null
var _state_timer: Timer = null
var _pulse_tween: Tween = null
var _pulse_marker: Node3D = null

# 每个工具的指引文字
const TOOL_HINTS: Dictionary = {
	0: "点击蓝色 Wyckoff 标记放置原子 | 滚轮缩放 | 右键拖拽旋转视角",
	1: "点击已有原子替换元素 | 1-9 切换元素",
	2: "点击位置放置软模原子 — 用于柔性结构",
	3: "点击位置插入层间原子",
	4: "点击原子将其删除 — 相关化学键也会断开",
	5: "依次点击两个原子建立化学键 | 构建分子结构",
	6: "点击多个原子组装结构单元",
	7: "按顺序点击位置构建路径",
	8: "执行元胞自动机演化步骤",
	9: "调整晶格矩阵参数",
	10: "引爆选中的原子 — 高风险高回报",
}

# 游戏状态指引
const STATE_HINTS: Array[Dictionary] = [
	{"condition": "no_atoms", "text": "提示: 点击闪烁的蓝色标记放置第一个原子"},
	{"condition": "has_atoms_no_bonds", "text": "提示: 切换到「成键」工具，依次点击两个原子建立化学键"},
	{"condition": "has_bonds_not_verified", "text": "提示: 点击「验证」按钮检查结构是否符合关卡目标"},
	{"condition": "verified", "text": "结构已验证! 继续优化或进入下一关"},
]


func setup(canvas: Node3D, atom_mgr: RefCounted, camera: Camera3D) -> void:
	_canvas = canvas
	_atom_mgr = atom_mgr
	_camera = camera
	if _canvas and _canvas.has_signal("tool_changed"):
		_canvas.tool_changed.connect(_on_tool_changed)
	_start_state_check()
	# Defer UI creation — HUD CanvasLayer may not exist yet during _ready()
	call_deferred("_build_ui_deferred")


func _build_ui_deferred() -> void:
	# Wait two frames so game.gd's _ready() has run and HUD exists
	await get_tree().process_frame
	await get_tree().process_frame
	_build_ui()


func _build_ui() -> void:
	# Find the existing HintBar created by game.gd and repurpose it for contextual hints
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var hint_bar = tree.root.find_child("HintBar", true, false)
		if hint_bar and hint_bar is PanelContainer:
			_hint_panel = hint_bar
			# Find or create the label inside
			var label = hint_bar.find_child("HintLabel", true, false)
			if label and label is Label:
				_hint_label = label
				_hint_label.add_theme_font_size_override("font_size", 15)
			print("[ContextualHint] Reusing existing HintBar")
			_show_hint("提示: 点击蓝色标记放置原子 | 滚轮缩放 | 右键旋转", Color(0.4, 0.8, 1.0, 1.0))
			return

	# Fallback: create our own panel if HintBar not found
	_hint_panel = PanelContainer.new()
	_hint_panel.name = "ContextualHint"
	_hint_panel.anchors_preset = Control.PRESET_CENTER_BOTTOM
	_hint_panel.anchor_left = 0.5
	_hint_panel.anchor_right = 0.5
	_hint_panel.offset_top = -72
	_hint_panel.offset_bottom = -50
	_hint_panel.offset_left = -420
	_hint_panel.offset_right = 420
	_hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_panel.custom_minimum_size = Vector2(400, 36)
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.z_index = 50

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.10, 0.18, 0.85)
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.6, 1.0, 0.6)
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	_hint_panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 8)
	_hint_panel.add_child(margin)

	_hint_label = Label.new()
	_hint_label.name = "HintText"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 16)
	_hint_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 0.95))
	_hint_label.text = ""
	margin.add_child(_hint_label)

	var parent_node: Node = null
	if tree and tree.root:
		parent_node = tree.root.find_child("HUD", true, false)
		if parent_node == null:
			for child in tree.root.get_children():
				parent_node = _find_canvas_layer(child)
				if parent_node:
					break
	if parent_node == null:
		parent_node = _canvas.get_parent() if _canvas and _canvas.get_parent() else _canvas
	if parent_node:
		parent_node.call_deferred("add_child", _hint_panel)
		print("[ContextualHint] Created new panel, added to: %s" % parent_node.name)
	_show_hint("提示: 点击蓝色标记放置原子", Color(0.4, 0.8, 1.0, 1.0))


func _find_canvas_layer(node: Node) -> Node:
	if node is CanvasLayer:
		return node
	for child in node.get_children():
		var found := _find_canvas_layer(child)
		if found:
			return found
	return null


func _start_state_check() -> void:
	_state_timer = Timer.new()
	_state_timer.wait_time = 2.0
	_state_timer.autostart = true
	_state_timer.timeout.connect(_check_game_state)
	add_child(_state_timer)


func _on_tool_changed(tool_index: int) -> void:
	# Get mode-specific hint
	var mode: String = _canvas.get("_current_construction_mode") if _canvas else ""
	var domain: String = _canvas.get("_current_domain") if _canvas else ""

	var hint: String = _get_mode_aware_hint(tool_index, mode, domain)
	if hint != "":
		_show_hint(hint, Color(0.4, 0.8, 1.0, 1.0))
	_stop_pulse()
	# PLACE 模式下如果没有原子，脉冲最近的标记
	if tool_index == 0 and _atom_mgr and _atom_mgr.get_atoms().size() == 0:
		call_deferred("_pulse_nearest_marker")


func _get_mode_aware_hint(tool_index: int, mode: String, domain: String) -> String:
	# For non-wyckoff modes, give mode-specific guidance
	if mode == "path_build" or domain in ["topology", "reaction"]:
		match tool_index:
			0: return "点击空间放置原子起点 | 滚轮缩放 | 右键旋转"
			7: return "依次点击位置构建路径 — 连接起点到终点"
			5: return "点击两个原子建立化学键"
			4: return "点击原子删除 — 路径会断开"
			_: return "使用路径构建工具(P)依次点击位置构建路径"
	if mode == "assembly" or domain == "device":
		match tool_index:
			0: return "点击标记放置组件原子 | 滚轮缩放"
			6: return "点击多个原子组装结构单元 (电极/电解质等)"
			5: return "点击两个原子建立连接"
			4: return "点击原子删除"
			_: return "使用组装工具(A)构建器件结构"
	if mode == "mesh_build" or domain == "fluid":
		match tool_index:
			0: return "点击网格点放置原子 | 构建流体结构"
			7: return "点击位置构建网格路径"
			_: return "使用放置工具构建网格结构"
	if mode == "cellular_automaton":
		return "放置种子原子后按空格键演化 | 观察 CA 模式变化"
	# Default: wyckoff_fill mode
	return TOOL_HINTS.get(tool_index, "")


func _check_game_state() -> void:
	if not _atom_mgr or not _canvas:
		return
	var atom_count: int = _atom_mgr.get_atoms().size()
	var bond_count: int = _atom_mgr._bonds.size() if _atom_mgr.get("_bonds") else 0
	var mode: String = _canvas.get("_current_construction_mode") if _canvas else ""
	var domain: String = _canvas.get("_current_domain") if _canvas else ""

	# Mode-specific state hints
	var condition := ""
	if atom_count == 0:
		condition = "no_atoms"
	elif atom_count > 0 and bond_count == 0 and mode != "path_build":
		condition = "has_atoms_no_bonds"
	elif bond_count > 0:
		condition = "has_bonds_not_verified"
	elif mode == "path_build" and atom_count > 0:
		condition = "path_in_progress"

	# Get mode-aware state hint
	var state_text: String = ""
	match condition:
		"no_atoms":
			if mode == "path_build" or domain in ["topology", "reaction"]:
				state_text = "提示: 使用路径构建工具(P)点击空间放置第一个节点"
			elif mode == "assembly" or domain == "device":
				state_text = "提示: 点击标记放置组件原子，然后用组装工具(A)构建器件"
			elif mode == "cellular_automaton":
				state_text = "提示: 放置种子原子后按空格键开始演化"
			else:
				state_text = "提示: 点击闪烁的蓝色标记放置第一个原子"
		"has_atoms_no_bonds":
			state_text = "提示: 切换到「成键」工具，依次点击两个原子建立化学键"
		"has_bonds_not_verified":
			state_text = "提示: 点击「验证」按钮检查结构是否符合关卡目标"
		"path_in_progress":
			state_text = "提示: 继续点击位置延伸路径，或切换工具完成构建"

	if state_text != "" and _hint_label and _hint_label.text != state_text:
		_show_hint(state_text, Color(1.0, 0.85, 0.4, 1.0))

	# 如果处于 no_atoms 且当前是 PLACE 工具，确保脉冲在运行
	if condition == "no_atoms" and _canvas.current_tool == 0 and _pulse_marker == null:
		_pulse_nearest_marker()
	elif condition != "no_atoms":
		_stop_pulse()


func _show_hint(text: String, color: Color) -> void:
	if not _hint_label:
		print("[ContextualHint] _show_hint called but _hint_label is null")
		return
	_hint_label.text = text
	_hint_label.add_theme_color_override("font_color", color)
	if _hint_panel:
		_hint_panel.visible = true
		_hint_panel.modulate.a = 1.0
		print("[ContextualHint] hint shown: '%s' (panel=%s label=%s)" % [text, _hint_panel.visible, _hint_label.text])


func _pulse_nearest_marker() -> void:
	if not _canvas:
		return
	var wm = _canvas.get_node_or_null("WyckoffMarkers")
	if not wm:
		return
	var nearest: Node3D = null
	var nearest_dist: float = INF
	var cam_pos: Vector3 = _camera.global_position if _camera else Vector3.ZERO
	for child in wm.get_children():
		if child.visible and not child.is_filled():
			var d: float = child.global_position.distance_to(cam_pos)
			if d < nearest_dist:
				nearest_dist = d
				nearest = child
	if nearest == null:
		return
	_pulse_marker = nearest
	if _pulse_tween:
		_pulse_tween.kill()
	_pulse_tween = nearest.create_tween()
	_pulse_tween.set_loops()
	_pulse_tween.set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.set_trans(Tween.TRANS_SINE)
	_pulse_tween.tween_property(nearest, "scale", Vector3(1.5, 1.5, 1.5), 0.6)
	_pulse_tween.tween_property(nearest, "scale", Vector3.ONE, 0.6)


func _stop_pulse() -> void:
	if _pulse_tween:
		_pulse_tween.kill()
		_pulse_tween = null
	if _pulse_marker and is_instance_valid(_pulse_marker):
		_pulse_marker.scale = Vector3.ONE
	_pulse_marker = null


func hide_hint() -> void:
	if _hint_panel:
		_hint_panel.visible = false
	_stop_pulse()


func cleanup() -> void:
	_stop_pulse()
	if _state_timer:
		_state_timer.stop()
	if _canvas and _canvas.has_signal("tool_changed") and _canvas.tool_changed.is_connected(_on_tool_changed):
		_canvas.tool_changed.disconnect(_on_tool_changed)
