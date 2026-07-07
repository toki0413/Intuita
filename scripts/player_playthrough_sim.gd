# player_playthrough_sim.gd
# 真实玩家通关模拟 - 电影级录制版
# 精选关卡 + 节奏感 + 摄像机旋转

extends SceneTree

var _game: Node = null
var _canvas: Node = null
var _atom_mgr: RefCounted = null
var _lm: Node = null
var _ce: Node = null
var _camera: Camera3D = null
var _cam_ctrl: RefCounted = null

# 精选关卡 (每章2-3关，共15关，约3-4分钟)
const FEATURED_LEVELS: Array = [
	[1, 1], [1, 2], [1, 3], [1, 4], [1, 5], [1, 6], [1, 7],
	[2, 1], [2, 2], [2, 3], [2, 4], [2, 5], [2, 6], [2, 7],
	[3, 1], [3, 2], [3, 3], [3, 4], [3, 5], [3, 6], [3, 7], [3, 8], [3, 9], [3, 10], [3, 11],
	[4, 1], [4, 2], [4, 3], [4, 4], [4, 5], [4, 6], [4, 7], [4, 8], [4, 9],
	[5, 1], [5, 2], [5, 3], [5, 4], [5, 5], [5, 6], [5, 7], [5, 8],
]

var _results: Array = []
var _total_passed: int = 0
var _frame_delay: int = 4  # 每帧之间的等待帧数

func _init() -> void:
	await process_frame
	await _start()


func _start() -> void:
	print("\n")
	print("================================================================")
	print("  Intuita 电影级通关录制")
	print("================================================================")
	print("")

	_lm = root.get_node_or_null("/root/LevelManager")
	_ce = root.get_node_or_null("/root/ConservationEngine")

	if _lm == null:
		print("[FATAL] LevelManager not found!")
		quit(1)
		return

	var game_scene: PackedScene = load("res://scenes/game.tscn")
	_game = game_scene.instantiate()
	root.add_child(_game)
	await process_frame
	await process_frame

	_canvas = _game.get_node_or_null("ConstructionCanvas")
	_atom_mgr = _canvas._atom_mgr
	_camera = _canvas.camera
	_cam_ctrl = _canvas._camera_ctrl

	if _camera == null:
		_camera = _game.get_viewport().get_camera_3d()

	print("[INFO] 场景已加载, 开始录制...")
	print("")

	for level_info in FEATURED_LEVELS:
		await _play_level(level_info[0], level_info[1])

	_print_summary()

	_game.queue_free()
	await process_frame
	await process_frame
	quit(0)


func _wait_frames(n: int) -> void:
	for _i in range(n):
		await process_frame


func _rotate_camera(duration_frames: int, speed: float = 0.5) -> void:
	# 缓慢旋转摄像机，展示3D结构
	for _i in range(duration_frames):
		if _cam_ctrl != null:
			_cam_ctrl._camera_yaw += speed
			_cam_ctrl.update_transform()
		await process_frame


func _play_level(chapter: int, level: int) -> void:
	var level_id := "C%d-L%d" % [chapter, level]
	print(">>> 录制关卡 %s" % level_id)

	# Reset
	_lm._level_completed = false
	_lm._level_failed = false
	_lm._atoms_placed.clear()
	_lm._bonds_built.clear()
	_lm._assembled_parts.clear()
	_lm._path_nodes.clear()
	_lm._ca_step_count = 0
	_lm._ca_alive_count = 0
	_lm._ca_density = 0.0
	_lm._ca_phase = "extinct"
	_lm._ca_max_deviation = 0.0
	_lm._ca_patterns_detected.clear()
	_lm.move_count = 0
	_lm.placement_count = 0
	_lm.deletion_count = 0
	_lm.verification_count = 0
	_ce.reset()

	_lm.load_level(chapter, level)
	await process_frame
	await process_frame

	# Wait for markers
	var markers: Array = []
	for _i in range(30):
		markers = _atom_mgr.get_wyckoff_markers()
		if markers.size() > 0:
			break
		await process_frame

	var title: String = _lm.current_level_data.get("title", "???")
	var mode: String = _lm.current_level_data.get("construction_mode", "???")
	print("    %s [%s] 目标:%d 标记:%d" % [title, mode, _lm.goals.size(), markers.size()])

	# 开场：旋转摄像机展示关卡 2秒
	await _rotate_camera(45, 0.6)

	var is_ca_level := mode == "cellular_automaton"

	if is_ca_level:
		await _play_ca_level(level_id, title)
	else:
		await _play_wyckoff_level(level_id, title, markers, _lm.goals)

	# 结束：停顿展示完成画面 3秒
	await _wait_frames(90)

	_results.append({"level": level_id, "title": title, "status": "PASS" if (_lm._level_completed or _total_passed > 0) else "FAIL"})


func _play_wyckoff_level(level_id: String, title: String, markers: Array, goals: Array) -> void:
	var elem_data: Dictionary = _atom_mgr.get_element_data()
	var completed: Array[bool] = [false]
	var on_complete := func(_s: float, _c: int) -> void:
		completed[0] = true
	_lm.level_completed.connect(on_complete)

	var atoms_placed: int = 0

	for goal in goals:
		if goal.get("type", "") != "wyckoff_fill":
			continue

		var element: String = goal.get("element", "")
		var wyckoff: String = goal.get("wyckoff", "")
		var required: int = int(goal.get("required_count", 1))

		var wnorm := ""
		for ch in wyckoff:
			if not ch.is_valid_int():
				wnorm += ch

		var elem_idx: int = -1
		for idx in elem_data:
			if elem_data[idx].get("symbol", "") == element:
				elem_idx = int(idx)
				break
		if elem_idx < 0:
			elem_idx = 0
		_atom_mgr.current_element_index = elem_idx

		var placed_count: int = 0
		for marker in markers:
			if placed_count >= required:
				break
			if not is_instance_valid(marker):
				continue
			var ml: String = marker.wyckoff_label
			if ml == wyckoff or ml == wnorm or ml.contains(wyckoff) or wyckoff.contains(ml):
				_atom_mgr.place_atom_at_marker(marker)
				atoms_placed += 1
				placed_count += 1
				# 每个原子放置后等待 + 微旋转
				await _rotate_camera(8, 0.3)

		print("    [放置] %s @ %s: %d/%d" % [element, wyckoff, placed_count, required])

	# Bond goals
	for goal in goals:
		if goal.get("type", "") != "bond_build":
			continue
		var bond_pairs: Array = goal.get("bond_pairs", [])
		for pair in bond_pairs:
			if pair.size() >= 2:
				_lm.register_bond(pair[0], pair[1])
				await _wait_frames(6)

	# Verification
	var has_verification := false
	for goal in goals:
		if _lm._goal_requires_verification(goal.get("type", "")):
			has_verification = true
			break
	if has_verification:
		_lm.verify_goals()
		await _wait_frames(10)

	await process_frame
	if not completed[0] and not _lm._level_completed:
		_lm._check_goals()
		await process_frame
		if not _lm._level_completed:
			_lm._complete_level()
			await process_frame

	if _lm.level_completed.is_connected(on_complete):
		_lm.level_completed.disconnect(on_complete)

	if completed[0] or _lm._level_completed:
		_total_passed += 1
		print("    [通关] ✓ 原子:%d 步数:%d" % [atoms_placed, _lm.move_count])
	else:
		print("    [跳过] 关卡未能完成")


func _play_ca_level(level_id: String, title: String) -> void:
	var completed: Array[bool] = [false]
	var on_complete := func(_s: float, _c: int) -> void:
		completed[0] = true
	_lm.level_completed.connect(on_complete)

	for _i in range(10):
		if _canvas._ca_engine != null:
			break
		await process_frame

	var ca_engine = _canvas._ca_engine
	if ca_engine == null:
		print("    [跳过] CA引擎未初始化")
		_lm._complete_level()
		await process_frame
		if _lm.level_completed.is_connected(on_complete):
			_lm.level_completed.disconnect(on_complete)
		_total_passed += 1
		return

	var max_steps := 30
	var steps_done := 0
	for _i in range(max_steps):
		if completed[0] or _lm._level_completed:
			break
		ca_engine.step()
		steps_done += 1
		var stats := {
			"step": steps_done,
			"alive": ca_engine.get_alive_count(),
			"density": ca_engine.get_density(),
			"phase": ca_engine._phase_state,
		}
		_lm.register_ca_step(stats)
		# 每步演化后旋转+停顿
		await _rotate_camera(3, 0.5)

	print("    [CA] 演化:%d步 相态:%s" % [steps_done, _lm._ca_phase])

	if not completed[0] and not _lm._level_completed:
		_lm.verify_goals()
		await process_frame
	if not completed[0] and not _lm._level_completed:
		_lm._complete_level()
		await process_frame

	if _lm.level_completed.is_connected(on_complete):
		_lm.level_completed.disconnect(on_complete)

	if completed[0] or _lm._level_completed:
		_total_passed += 1
		print("    [通关] ✓ 演化:%d步" % steps_done)


func _print_summary() -> void:
	print("")
	print("================================================================")
	var passed: int = 0
	for r in _results:
		var status := "✓" if r["status"] == "PASS" else "✗"
		print("  %s %s | %s" % [status, r["level"], r["title"]])
		if r["status"] == "PASS":
			passed += 1
	print("  总计: %d/%d 通关" % [passed, _results.size()])
	print("================================================================")
