# sandbox_manager.gd
# 沙盒模式管理器 - 从 construction_canvas.gd 拆分
#
# 负责：
#   - 沙盒右键菜单 (PopupMenu)
#   - 沙盒工具栏 (HBoxContainer)
#   - 结构序列化/保存/分享/截图

class_name SandboxManager
extends RefCounted

var _host: Node3D = null
var _context_menu: PopupMenu = null
var _toolbar: HBoxContainer = null

var _atom_mgr: RefCounted = null
var _camera_ctrl: RefCounted = null

func _init(host: Node3D, atom_mgr: RefCounted, camera_ctrl: RefCounted) -> void:
	_host = host
	_atom_mgr = atom_mgr
	_camera_ctrl = camera_ctrl

func build_ui() -> void:
	_build_context_menu()
	_build_toolbar()

func _build_context_menu() -> void:
	_context_menu = PopupMenu.new()
	_context_menu.name = "SandboxContextMenu"

	# 工具子菜单
	var tools_menu := PopupMenu.new()
	tools_menu.name = "ToolsSubMenu"
	tools_menu.add_item("放置原子", 0)
	tools_menu.add_item("替换原子", 1)
	tools_menu.add_item("软模式", 2)
	tools_menu.add_item("插入原子", 3)
	tools_menu.add_item("删除原子", 4)
	tools_menu.add_item("构建键", 5)
	tools_menu.add_item("组装", 6)
	tools_menu.add_item("路径构建", 7)
	tools_menu.id_pressed.connect(_on_context_tool_selected)
	_context_menu.add_child(tools_menu)
	_context_menu.add_submenu_item("工具", "ToolsSubMenu")

	_context_menu.add_separator()
	_context_menu.add_item("清空结构", 10)
	_context_menu.add_item("重置视角", 11)
	_context_menu.add_separator()
	_context_menu.add_item("保存结构", 20)
	_context_menu.add_item("分享结构", 21)
	_context_menu.add_item("截图", 22)
	_context_menu.id_pressed.connect(_on_context_action)

	_host.add_child(_context_menu)

func _build_toolbar() -> void:
	# host 可能还没进树或已被释放，先确认再拿 viewport
	if not is_instance_valid(_host) or not _host.is_inside_tree():
		return
	var canvas := _host.get_viewport().get_node_or_null("Game/HUD")
	if not canvas:
		canvas = _host.get_parent()

	_toolbar = HBoxContainer.new()
	_toolbar.name = "SandboxToolbar"
	_toolbar.anchors_preset = Control.PRESET_CENTER_BOTTOM
	_toolbar.offset_top = -60
	_toolbar.offset_bottom = -10
	_toolbar.add_theme_constant_override("separation", 12)

	var actions := [
		{"text": "保存", "id": "save"},
		{"text": "分享", "id": "share"},
		{"text": "截图", "id": "screenshot"},
		{"text": "清空", "id": "clear"},
	]
	for action in actions:
		var btn := Button.new()
		btn.text = action.text
		btn.add_theme_font_override("font", UiAnimator.make_ui_font(20, true))
		btn.add_theme_font_size_override("font_size", 20)
		btn.custom_minimum_size = Vector2(80, 40)
		btn.pressed.connect(_on_toolbar_action.bind(action.id))
		_toolbar.add_child(btn)
	canvas.add_child(_toolbar)

func show_context_menu() -> void:
	if _context_menu:
		_context_menu.position = DisplayServer.mouse_get_position()
		_context_menu.popup()

func _on_context_tool_selected(id: int) -> void:
	match id:
		0: _host.set_tool(0)   # PLACE
		1: _host.set_tool(1)   # SUBSTITUTE
		2: _host.set_tool(2)   # SOFT_MODE
		3: _host.set_tool(3)   # INTERCALATE
		4: _host.set_tool(4)   # DELETE
		5: _host.set_tool(5)   # BOND_BUILD
		6: _host.set_tool(6)   # ASSEMBLE
		7: _host.set_tool(7)   # PATH_BUILD

func _on_context_action(id: int) -> void:
	match id:
		10: _host.clear_structure()
		11: _camera_ctrl.update_transform()
		20: _save_structure()
		21: _share_structure()
		22: _take_screenshot()

func _on_toolbar_action(action_id: String) -> void:
	match action_id:
		"save": _save_structure()
		"share": _share_structure()
		"screenshot": _take_screenshot()
		"clear": _host.clear_structure()

func _save_structure() -> void:
	var data := _serialize_structure()
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var path := "user://sandbox_save_%s.json" % timestamp
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		GameLogger.debug("General", "[沙盒] 结构已保存: %s" % path)

func _share_structure() -> void:
	var data := _serialize_structure()
	var json_str := JSON.stringify(data)
	DisplayServer.clipboard_set(json_str)
	GameLogger.debug("General", "[沙盒] 结构JSON已复制到剪贴板 (%d 字符)" % json_str.length())

func _take_screenshot() -> void:
	if not is_instance_valid(_host):
		return
	await _host.get_tree().process_frame
	if not is_instance_valid(_host):
		return
	var img := _host.get_viewport().get_texture().get_image()
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var path := "user://sandbox_screenshot_%s.png" % timestamp
	img.save_png(path)
	GameLogger.debug("General", "[沙盒] 截图已保存: %s" % path)

func _serialize_structure() -> Dictionary:
	var atoms_data := []
	for atom in _atom_mgr.get_atoms():
		if not is_instance_valid(atom):
			continue
		atoms_data.append({
			"element": atom.get("element_symbol") if atom.has_method("get_element_symbol") else "C",
			"position": {"x": atom.position.x, "y": atom.position.y, "z": atom.position.z},
		})
	return {
		"space_group": GameState.sandbox_selected_space_group,
		"lattice_params": {
			"a": GameState.sandbox_lattice_params.x,
			"b": GameState.sandbox_lattice_params.y,
			"c": GameState.sandbox_lattice_params.z,
		},
		"lattice_angles": {
			"alpha": GameState.sandbox_lattice_angles.x,
			"beta": GameState.sandbox_lattice_angles.y,
			"gamma": GameState.sandbox_lattice_angles.z,
		},
		"atoms": atoms_data,
		"timestamp": Time.get_ticks_msec(),
	}
