# pathfinder.gd
# A* 寻路 - 在晶格坐标中移动，考虑障碍物

extends RefCounted
class_name LatticePathfinder

var lattice_size: Vector3i = Vector3i(8, 8, 8)
var obstacles: Array[Vector3i] = []

func _init(size: Vector3i = Vector3i(8, 8, 8)) -> void:
	lattice_size = size

func set_obstacles(obs: Array[Vector3i]) -> void:
	obstacles = obs.duplicate()

func find_path(start: Vector3i, goal: Vector3i) -> Array[Vector3i]:
	if start == goal:
		return [start]

	var open_set: Array[Vector3i] = [start]
	var came_from: Dictionary = {}
	var g_score: Dictionary = { _vec3i_key(start): 0.0 }
	var f_score: Dictionary = { _vec3i_key(start): _heuristic(start, goal) }

	while not open_set.is_empty():
		# 找到 f_score 最小的节点
		var current: Vector3i = open_set[0]
		var current_key := _vec3i_key(current)
		var best_f: float = f_score.get(current_key, INF)
		for node in open_set:
			var k := _vec3i_key(node)
			if f_score.get(k, INF) < best_f:
				best_f = f_score[k]
				current = node
				current_key = k

		if current == goal:
			return _reconstruct_path(came_from, current)

		open_set.erase(current)

		for neighbor in _neighbors(current):
			var n_key := _vec3i_key(neighbor)
			var tentative_g: float = g_score[current_key] + 1.0
			if tentative_g < g_score.get(n_key, INF):
				came_from[n_key] = current
				g_score[n_key] = tentative_g
				f_score[n_key] = tentative_g + _heuristic(neighbor, goal)
				if not neighbor in open_set:
					open_set.append(neighbor)

	return []

func _neighbors(pos: Vector3i) -> Array[Vector3i]:
	var dirs := [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
		Vector3i(0, 1, 0), Vector3i(0, -1, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	]
	var result: Array[Vector3i] = []
	for d in dirs:
		var n: Vector3i = pos + d
		if n.x < 0 or n.x >= lattice_size.x:
			continue
		if n.y < 0 or n.y >= lattice_size.y:
			continue
		if n.z < 0 or n.z >= lattice_size.z:
			continue
		if n in obstacles:
			continue
		result.append(n)
	return result

func _heuristic(a: Vector3i, b: Vector3i) -> float:
	return abs(a.x - b.x) + abs(a.y - b.y) + abs(a.z - b.z)

func _vec3i_key(v: Vector3i) -> String:
	return "%d,%d,%d" % [v.x, v.y, v.z]

func _reconstruct_path(came_from: Dictionary, current: Vector3i) -> Array[Vector3i]:
	var path: Array[Vector3i] = [current]
	var key := _vec3i_key(current)
	while came_from.has(key):
		current = came_from[key]
		key = _vec3i_key(current)
		path.append(current)
	path.reverse()
	return path
