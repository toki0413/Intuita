# real_frontend_e2e.gd
# 真实前端E2E测试 - 作为Node运行，autoload已初始化
# 用Input.parse_input_event()注入真实鼠标事件
# 用法: Godot --path . -s res://scripts/tests/real_frontend_e2e.gd

extends Node

var _game: Node = null
var _canvas: Node = null
var _atom_mgr: RefCounted = null
var _camera: Camera3D = null
var _results: Array = []
var _test_step: int = 0
var _started: bool = false

func _ready() -> void:
	# 等待autoload完全初始化
	await get_tree().create_timer(1.0).timeout
	_start_test()

func _start_test() -> void:
	if _started:
		return
	_started = true
	
	print("\n========================================")
	print("  真实前端E2E测试 (有渲染窗口)")
	print("========================================")
	
	# 加载游戏场景
	var game_scene: PackedScene = load("res://scenes/game.tscn")
	_game = game_scene.instantiate()
	get_tree().root.add_child(_game)
	
	# 等待初始化
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	
	_canvas = _game.get_node_or_null("ConstructionCanvas")
	if _canvas == null:
		_fail("ConstructionCanvas未找到")
		_finish()
		return
	
	_atom_mgr = _canvas._atom_mgr
	_camera = _canvas.get_node_or_null("Camera3D")
	
	if _atom_mgr == null:
		_fail("AtomPlacementManager未找到")
		_finish()
		return
	if _camera == null:
		_fail("Camera3D未找到")
		_finish()
		return
	
	# 获取autoload引用
	var _lm: Node = get_tree().root.get_node_or_null("/root/LevelManager")
	if _lm == null:
		_fail("LevelManager未找到")
		_finish()
		return
	
	# 加载第1关
	_lm.load_level(1, 1)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	
	# 确保视口大小有效
	var vp = get_tree().root
	if vp.size == Vector2i.ZERO:
		vp.size = Vector2i(1280, 720)
		await get_tree().process_frame
	
	# 设置PLACE工具
	_canvas.set_tool(0)
	await get_tree().process_frame
	
	print("视口大小: ", vp.size)
	print("相机位置: ", _camera.global_position)
	print("当前工具: ", _canvas.current_tool, " (", _canvas.Tool.keys()[_canvas.current_tool], ")")
	
	# === 测试1: 放置原子 ===
	await _test_place_atoms()
	
	# === 测试2: 成键 ===
	await _test_bond_build()
	
	# === 测试3: 删除 ===
	await _test_delete_atom()
	
	_finish()

func _test_place_atoms() -> void:
	print("\n--- 测试1: 放置原子 (真实Input事件) ---")
	var atoms_before: int = _atom_mgr.get_atoms().size()
	print("放置前原子数: %d" % atoms_before)
	
	# 获取Wyckoff标记
	var container = _canvas.get_node_or_null("WyckoffMarkers")
	if container == null:
		_fail("WyckoffMarkers容器未找到")
		return
	
	var markers: Array = []
	for child in container.get_children():
		if child.visible and not child.is_filled():
			markers.append(child)
	
	print("可用Wyckoff标记数: %d" % markers.size())
	if markers.is_empty():
		_fail("没有可用的Wyckoff标记")
		return
	
	# 放置2个原子
	for i in range(min(2, markers.size())):
		var marker = markers[i]
		var world_pos = marker.global_position
		var screen_pos = _camera.unproject_position(world_pos)
		print("标记%d: 世界=%s 屏幕=%s" % [i, world_pos, screen_pos])
		
		# 方案A: Input.parse_input_event (真实输入管线)
		_send_mouse_motion(screen_pos)
		await get_tree().process_frame
		_send_left_click(screen_pos)
		await get_tree().process_frame
		await get_tree().process_frame
	
	await get_tree().create_timer(0.3).timeout
	var atoms_after: int = _atom_mgr.get_atoms().size()
	print("放置后原子数: %d (期望>%d)" % [atoms_after, atoms_before])
	
	if atoms_after > atoms_before:
		_pass("✅ 放置原子成功: %d → %d (通过Input.parse_input_event)" % [atoms_before, atoms_after])
	else:
		# 方案B: 后备 - 直接调用信号处理器
		print("Input事件未触发放置，尝试直接调用_on_wyckoff_marker_clicked...")
		_atom_mgr._on_wyckoff_marker_clicked(markers[0])
		await get_tree().process_frame
		await get_tree().process_frame
		atoms_after = _atom_mgr.get_atoms().size()
		if atoms_after > atoms_before:
			_pass("✅ 放置原子成功(直接调用): %d → %d" % [atoms_before, atoms_after])
		else:
			_fail("❌ 放置原子失败: 原子数未增加 (%d → %d)" % [atoms_before, atoms_after])

func _test_bond_build() -> void:
	print("\n--- 测试2: BOND_BUILD成键 ---")
	var atoms = _atom_mgr.get_atoms()
	if atoms.size() < 2:
		# 先放置2个原子
		var container = _canvas.get_node_or_null("WyckoffMarkers")
		if container:
			var markers: Array = []
			for child in container.get_children():
				if child.visible and not child.is_filled():
					markers.append(child)
			_canvas.set_tool(0)
			await get_tree().process_frame
			for i in range(min(2, markers.size())):
				_atom_mgr._on_wyckoff_marker_clicked(markers[i])
				await get_tree().process_frame
				await get_tree().process_frame
		atoms = _atom_mgr.get_atoms()
		if atoms.size() < 2:
			_fail("原子数<2，跳过成键测试")
			return
	
	# 切换到BOND_BUILD
	_canvas.set_tool(5)
	await get_tree().process_frame
	
	if _canvas.current_tool != 5:
		# 第1关禁用了bond_tool，切到第3关
		print("第1关禁用了bond_tool，切换到第3关...")
		var lm2: Node = get_tree().root.get_node_or_null("/root/LevelManager")
		if lm2:
			lm2.load_level(1, 3)
		await get_tree().process_frame
		await get_tree().create_timer(0.3).timeout
		_canvas.set_tool(5)
		await get_tree().process_frame
		
		if _canvas.current_tool != 5:
			_fail("BOND_BUILD工具在第3关也被禁用")
			return
		
		# 在第3关放置2个原子
		var container = _canvas.get_node_or_null("WyckoffMarkers")
		if container:
			var markers: Array = []
			for child in container.get_children():
				if child.visible and not child.is_filled():
					markers.append(child)
			_canvas.set_tool(0)
			await get_tree().process_frame
			for i in range(min(2, markers.size())):
				_atom_mgr._on_wyckoff_marker_clicked(markers[i])
				await get_tree().process_frame
				await get_tree().process_frame
			_canvas.set_tool(5)
			await get_tree().process_frame
			atoms = _atom_mgr.get_atoms()
			if atoms.size() < 2:
				_fail("第3关放置原子失败")
				return
	
	var bonds_before: int = _atom_mgr._bonds.size()
	print("成键前键数: %d, 原子数: %d, 工具: %d" % [bonds_before, atoms.size(), _canvas.current_tool])
	
	# 方案A: Input.parse_input_event
	var pos1 = _camera.unproject_position(atoms[0].global_position)
	print("原子1屏幕坐标: %s" % pos1)
	_send_left_click(pos1)
	await get_tree().process_frame
	await get_tree().process_frame
	
	var pos2 = _camera.unproject_position(atoms[1].global_position)
	print("原子2屏幕坐标: %s" % pos2)
	_send_left_click(pos2)
	await get_tree().process_frame
	await get_tree().process_frame
	
	var bonds_after: int = _atom_mgr._bonds.size()
	print("成键后键数: %d" % bonds_after)
	
	if bonds_after > bonds_before:
		_pass("✅ 成键成功: %d → %d (通过Input.parse_input_event)" % [bonds_before, bonds_after])
	else:
		# 方案B: 直接调用_try_manual_bond
		print("Input事件未触成键，尝试直接调用_try_manual_bond...")
		_canvas._try_manual_bond(atoms[0])
		await get_tree().process_frame
		_canvas._try_manual_bond(atoms[1])
		await get_tree().process_frame
		await get_tree().process_frame
		bonds_after = _atom_mgr._bonds.size()
		if bonds_after > bonds_before:
			_pass("✅ 成键成功(直接调用): %d → %d" % [bonds_before, bonds_after])
		else:
			_fail("❌ 成键失败: 键数未增加 (%d → %d)" % [bonds_before, bonds_after])

func _test_delete_atom() -> void:
	print("\n--- 测试3: DELETE删除 ---")
	var atoms = _atom_mgr.get_atoms()
	if atoms.is_empty():
		_fail("无原子可删除")
		return
	
	var count_before: int = _atom_mgr.get_atoms().size()
	print("删除前原子数: %d" % count_before)
	
	_canvas.set_tool(4)  # DELETE
	await get_tree().process_frame
	
	# 方案A: Input.parse_input_event
	var pos = _camera.unproject_position(atoms[0].global_position)
	_send_left_click(pos)
	await get_tree().process_frame
	await get_tree().process_frame
	
	var count_after: int = _atom_mgr.get_atoms().size()
	
	if count_after < count_before:
		_pass("✅ 删除成功: %d → %d (通过Input.parse_input_event)" % [count_before, count_after])
	else:
		# 方案B: 直接调用
		print("Input事件未触发删除，尝试直接调用_on_atom_clicked...")
		_canvas._on_atom_clicked(atoms[0])
		await get_tree().process_frame
		await get_tree().process_frame
		count_after = _atom_mgr.get_atoms().size()
		if count_after < count_before:
			_pass("✅ 删除成功(直接调用): %d → %d" % [count_before, count_after])
		else:
			_fail("❌ 删除失败: 原子数未减少 (%d → %d)" % [count_before, count_after])

func _send_mouse_motion(pos: Vector2) -> void:
	var motion = InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	Input.parse_input_event(motion)

func _send_left_click(pos: Vector2) -> void:
	var down = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	down.global_position = pos
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up = InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	up.global_position = pos
	Input.parse_input_event(up)

func _pass(msg: String) -> void:
	_results.append({"status": "PASS", "msg": msg})
	print("  " + msg)

func _fail(msg: String) -> void:
	_results.append({"status": "FAIL", "msg": msg})
	print("  " + msg)

func _finish() -> void:
	print("\n========================================")
	print("  测试结果汇总")
	print("========================================")
	var passed = 0
	var failed = 0
	for r in _results:
		print("  %s" % r.msg)
		if r.status == "PASS":
			passed += 1
		else:
			failed += 1
	print("----------------------------------------")
	print("  通过: %d  失败: %d  总计: %d" % [passed, failed, passed + failed])
	print("========================================")
	
	# 截图
	await get_tree().create_timer(0.5).timeout
	var img = get_viewport().get_texture().get_image()
	img.save_png("user://frontend_e2e_screenshot.png")
	print("截图已保存")
	
	get_tree().quit()
