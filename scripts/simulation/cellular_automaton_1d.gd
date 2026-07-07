# cellular_automaton_1d.gd
# 1D 元胞自动机引擎 - 经典 Wolfram 规则
# 参考: Stephen Wolfram, "A New Kind of Science"
# 规则编号 0-255，由3位二进制邻居模式决定输出
# Rule 30: 混沌生成器，Rule 90: 分形(Sierpinski)，Rule 110: 图灵完备

class_name CellularAutomaton1D
extends RefCounted

signal step_completed(step: int, alive_count: int)
signal pattern_detected(pattern_type: String, details: Dictionary)

var rule_number: int = 30
var size: int = 64
var _cells: PackedByteArray = PackedByteArray()
var _next_cells: PackedByteArray = PackedByteArray()
var _step_count: int = 0
var _alive_count: int = 0
var _history: Array[PackedByteArray] = []
var _max_history: int = 16


func _init(s: int = 64, rule: int = 30) -> void:
	size = maxi(s, 8)
	rule_number = rule
	_cells.resize(size)
	_next_cells.resize(size)
	_cells.fill(0)
	_next_cells.fill(0)


func set_rule(rule: int) -> void:
	rule_number = clampi(rule, 0, 255)


func set_cell(x: int, state: int) -> void:
	if x >= 0 and x < size:
		_cells[x] = state


func get_cell(x: int) -> int:
	if x < 0 or x >= size:
		return 0
	return _cells[x]


func get_cells() -> PackedByteArray:
	return _cells.duplicate()


func set_cells(cells: PackedByteArray) -> void:
	var copy_len: int = mini(cells.size(), size)
	for i in range(copy_len):
		_cells[i] = cells[i]


func step() -> void:
	# 保存历史用于振荡器检测
	_history.append(_cells.duplicate())
	if _history.size() > _max_history:
		_history.pop_front()

	for x in range(size):
		var left: int = _cells[wrapi(x - 1, 0, size)]
		var center: int = _cells[x]
		var right: int = _cells[wrapi(x + 1, 0, size)]
		# 3位邻居模式: left(4) center(2) right(1)
		var pattern: int = (left << 2) | (center << 1) | right
		# 检查规则的对应位
		_next_cells[x] = (rule_number >> pattern) & 1

	# 交换缓冲区
	var tmp := _cells
	_cells = _next_cells
	_next_cells = tmp

	_step_count += 1
	_alive_count = _count_alive()
	step_completed.emit(_step_count, _alive_count)

	# 检测图案
	_detect_patterns()


func step_n(n: int) -> void:
	for i in range(n):
		step()


func _count_alive() -> int:
	var count: int = 0
	for i in range(size):
		count += _cells[i]
	return count


func get_alive_count() -> int:
	return _alive_count


func get_step_count() -> int:
	return _step_count


func get_density() -> float:
	if size == 0:
		return 0.0
	return float(_alive_count) / float(size)


func _detect_patterns() -> void:
	# 振荡器检测：当前状态是否与历史中某个状态相同
	for i in range(_history.size()):
		if _cells == _history[i]:
			var period: int = _history.size() - i
			if period > 0:
				pattern_detected.emit("oscillator", {"period": period, "step": _step_count})
			return

	# 灭绝检测
	if _alive_count == 0:
		pattern_detected.emit("extinct", {"step": _step_count})

	# 稳定态检测
	if _history.size() >= 2 and _cells == _history[_history.size() - 2]:
		pattern_detected.emit("stable", {"step": _step_count})

	# 滑翔机检测：密度稳定但状态变化
	if _history.size() >= 4:
		var density_var: float = 0.0
		var base_density: float = get_density()
		for i in range(_history.size() - 4, _history.size()):
			var h_alive: int = 0
			for j in range(_history[i].size()):
				h_alive += _history[i][j]
			density_var += absf(float(h_alive) / float(size) - base_density)
		if density_var < 0.1 and _alive_count > 0:
			pattern_detected.emit("glider", {"step": _step_count, "density": base_density})


func reset() -> void:
	_cells.fill(0)
	_next_cells.fill(0)
	_step_count = 0
	_alive_count = 0
	_history.clear()


func seed_random(seed_val: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	for i in range(size):
		_cells[i] = rng.randi() % 2


func seed_center() -> void:
	# 经典初始态：仅中心一个活细胞
	_cells.fill(0)
	_cells[size / 2] = 1


func to_binary_string() -> String:
	var s := ""
	for i in range(size):
		s += "1" if _cells[i] == 1 else "0"
	return s


func from_binary_string(s: String) -> void:
	_cells.fill(0)
	var len: int = mini(s.length(), size)
	for i in range(len):
		_cells[i] = 1 if s[i] == "1" else 0
