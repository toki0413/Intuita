# 撤销重做系统测试
class_name UndoRedoTest
extends GdUnitTestSuite


func test_undo_redo_atom_placement() -> void:
	var runner: GdUnitSceneRunner = scene_runner("res://scenes/game.tscn", false)
	assert_that(runner).is_not_null()

	# 等待场景稳定
	await await_idle_frame()
	await runner.simulate_frames(5)

	var game: Node = runner.scene()
	var canvas: Node3D = game.get_node_or_null("ConstructionCanvas")
	assert_that(canvas).is_not_null()

	var atom_mgr: RefCounted = canvas._atom_mgr
	assert_that(atom_mgr).is_not_null()

	# 确保有 Wyckoff marker 可点
	var markers: Array = atom_mgr.get_wyckoff_markers()
	if markers.is_empty():
		return

	var initial_atom_count: int = atom_mgr.get_atoms().size()

	# 放置一个原子
	var marker: Node = markers[0]
	var placed: Node3D = atom_mgr.place_atom_at_marker(marker)
	assert_that(placed).is_not_null()
	assert_int(atom_mgr.get_atoms().size()).is_equal(initial_atom_count + 1)

	# 撤销: 原子数应恢复
	canvas._undo_redo_mgr.undo()
	await runner.simulate_frames(2)
	assert_int(atom_mgr.get_atoms().size()).is_equal(initial_atom_count)

	# 重做: 原子数应增加
	canvas._undo_redo_mgr.redo()
	await runner.simulate_frames(2)
	assert_int(atom_mgr.get_atoms().size()).is_equal(initial_atom_count + 1)

	if is_instance_valid(game):
		game.queue_free()
		for _i in range(5):
			await await_idle_frame()


func test_undo_redo_substitute_atom() -> void:
	var runner: GdUnitSceneRunner = scene_runner("res://scenes/game.tscn", false)
	await await_idle_frame()
	await runner.simulate_frames(5)

	var game: Node = runner.scene()
	var canvas: Node3D = game.get_node_or_null("ConstructionCanvas")
	var atom_mgr: RefCounted = canvas._atom_mgr
	var markers: Array = atom_mgr.get_wyckoff_markers()
	if markers.is_empty():
		return

	# 放置原子, 并切换到另一个元素
	var marker: Node = markers[0]
	var placed: Node3D = atom_mgr.place_atom_at_marker(marker)
	assert_that(placed).is_not_null()
	var original_symbol: String = placed.element_symbol

	# 切到第二个元素(如果存在)
	var elem_data: Dictionary = atom_mgr.get_element_data()
	if elem_data.size() < 2:
		return
	canvas.current_element_index = 1
	atom_mgr.current_element_index = 1

	# 替换
	var sub_info: Dictionary = atom_mgr.substitute_atom(placed)
	assert_that(sub_info).is_not_empty()
	assert_str(placed.element_symbol).is_not_equal(original_symbol)

	# 撤销替换
	canvas._undo_redo_mgr.undo()
	await runner.simulate_frames(2)
	assert_str(placed.element_symbol).is_equal(original_symbol)

	# 重做替换
	canvas._undo_redo_mgr.redo()
	await runner.simulate_frames(2)
	assert_str(placed.element_symbol).is_not_equal(original_symbol)

	if is_instance_valid(game):
		game.queue_free()
		for _i in range(5):
			await await_idle_frame()
