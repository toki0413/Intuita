# pathfinder_test.gd
# GdUnit4 测试: A* 晶格寻路

extends GdUnitTestSuite

const __source = "res://scripts/simulation/pathfinder.gd"

var _pf = null

func before() -> void:
	_pf = load(__source).new()

func after() -> void:
	if _pf != null:
		_pf = null

func test_find_path_direct_neighbor() -> void:
	var start := Vector3i(0, 0, 0)
	var goal := Vector3i(1, 0, 0)
	var path: Array[Vector3i] = _pf.find_path(start, goal)
	assert_int(path.size()).is_greater(0)
	assert_bool(path[0] == Vector3i(0, 0, 0)).is_true()
	assert_bool(path[path.size() - 1] == Vector3i(1, 0, 0)).is_true()

func test_find_path_avoids_obstacles() -> void:
	var start := Vector3i(0, 0, 0)
	var goal := Vector3i(2, 0, 0)
	var obstacles: Array[Vector3i] = [Vector3i(1, 0, 0)]
	_pf.set_obstacles(obstacles)
	var path: Array[Vector3i] = _pf.find_path(start, goal)
	assert_int(path.size()).is_greater(0)
	assert_bool(path[path.size() - 1] == Vector3i(2, 0, 0)).is_true()
	for p in path:
		assert_bool(p == Vector3i(1, 0, 0)).is_false()

func test_no_path_returns_empty() -> void:
	var start := Vector3i(0, 0, 0)
	var goal := Vector3i(1, 0, 0)
	var obstacles: Array[Vector3i] = [Vector3i(1, 0, 0)]
	_pf.set_obstacles(obstacles)
	var path: Array[Vector3i] = _pf.find_path(start, goal)
	assert_int(path.size()).is_equal(0)

func test_path_length_optimal() -> void:
	var start := Vector3i(0, 0, 0)
	var goal := Vector3i(3, 3, 3)
	var path: Array[Vector3i] = _pf.find_path(start, goal)
	var manhattan_dist: int = abs(start.x - goal.x) + abs(start.y - goal.y) + abs(start.z - goal.z)
	assert_int(path.size()).is_equal(manhattan_dist + 1)
	assert_bool(path[path.size() - 1] == Vector3i(3, 3, 3)).is_true()
