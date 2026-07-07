# cellular_automaton_engine.gd
# 3D 元胞自动机引擎 - Bays' 规则变体
# 参考: Carter Bays, "Candidates for the Game of Life in Three Dimensions"
# 规则记法 B/S: B=出生邻居数, S=存活邻居数
# 经典 Bays' 4555: 活细胞 4-5 邻居存活, 死细胞 5 邻居复活
# 3D Moore 邻域 (26 个邻居)

class_name CellularAutomatonEngine
extends RefCounted

signal step_completed(step: int, alive_count: int)
signal pattern_detected(pattern_type: String, details: Dictionary)
signal phase_transition_detected(from_phase: String, to_phase: String)

# 规则定义
var birth_rules: Array[int] = [5]       # 死细胞复活所需邻居数
var survival_rules: Array[int] = [4, 5]  # 活细胞存活所需邻居数

# 网格尺寸
var size_x: int = 10
var size_y: int = 10
var size_z: int = 10

# 细胞状态: 0=死 1=活 用一维数组存三维网格
var _cells: PackedByteArray = PackedByteArray()
var _next_cells: PackedByteArray = PackedByteArray()

# 演化历史 (用于振荡器检测)
var _history: Array = []
var _max_history: int = 8

# 统计
var _step_count: int = 0
var _alive_count: int = 0
var _prev_alive_count: int = 0

# 相变检测: 密度变化率
var _density_history: Array[float] = []
var _phase_state: String = "extinct"  # extinct / sparse / dense / chaotic / stable

# 滑翔机检测：追踪质心位移历史
var _com_history: Array[Vector3] = []
var _glider_detected: bool = false


func _init(sx: int = 10, sy: int = 10, sz: int = 10) -> void:
	size_x = maxi(sx, 2)
	size_y = maxi(sy, 2)
	size_z = maxi(sz, 2)
	var total := size_x * size_y * size_z
	_cells.resize(total)
	_next_cells.resize(total)
	_cells.fill(0)
	_next_cells.fill(0)


# ---- 网格操作 ----

func idx(x: int, y: int, z: int) -> int:
	return x + y * size_x + z * size_x * size_y


func in_bounds(x: int, y: int, z: int) -> bool:
	return x >= 0 and x < size_x and y >= 0 and y < size_y and z >= 0 and z < size_z


func get_cell(x: int, y: int, z: int) -> int:
	if not in_bounds(x, y, z):
		return 0
	return _cells[idx(x, y, z)]


func set_cell(x: int, y: int, z: int, alive: int) -> void:
	if not in_bounds(x, y, z):
		return
	_cells[idx(x, y, z)] = 1 if alive else 0


func toggle_cell(x: int, y: int, z: int) -> int:
	var cur := get_cell(x, y, z)
	set_cell(x, y, z, 1 - cur)
	return 1 - cur


func clear() -> void:
	_cells.fill(0)
	_next_cells.fill(0)
	_history.clear()
	_density_history.clear()
	_step_count = 0
	_alive_count = 0
	_prev_alive_count = 0
	_phase_state = "extinct"


func get_alive_count() -> int:
	return _alive_count


func get_step_count() -> int:
	return _step_count


func get_density() -> float:
	var total := size_x * size_y * size_z
	if total == 0:
		return 0.0
	return float(_alive_count) / float(total)


# ---- 邻居计数 (3D Moore 邻域, 26 个) ----

func count_neighbors(x: int, y: int, z: int) -> int:
	var count := 0
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				if dx == 0 and dy == 0 and dz == 0:
					continue
				var nx := x + dx
				var ny := y + dy
				var nz := z + dz
				# 周期性边界条件
				nx = (nx + size_x) % size_x
				ny = (ny + size_y) % size_y
				nz = (nz + size_z) % size_z
				count += _cells[idx(nx, ny, nz)]
	return count


# ---- 演化步 ----

func step() -> int:
	_prev_alive_count = _alive_count
	_alive_count = 0

	for x in range(size_x):
		for y in range(size_y):
			for z in range(size_z):
				var i := idx(x, y, z)
				var neighbors := count_neighbors(x, y, z)
				var current := _cells[i]
				var next_state := 0

				if current == 1:
					# 活细胞: 检查存活规则
					if neighbors in survival_rules:
						next_state = 1
				else:
					# 死细胞: 检查出生规则
					if neighbors in birth_rules:
						next_state = 1

				_next_cells[i] = next_state
				if next_state == 1:
					_alive_count += 1

	# 交换缓冲区
	var tmp := _cells
	_cells = _next_cells
	_next_cells = tmp

	_step_count += 1

	# 记录历史用于模式检测
	_record_history()
	_detect_patterns()

	step_completed.emit(_step_count, _alive_count)
	return _alive_count


func step_n(n: int) -> void:
	for i in range(n):
		step()


# ---- 规则设置 ----

func set_rule(birth: Array[int], survival: Array[int]) -> void:
	birth_rules = birth.duplicate()
	survival_rules = survival.duplicate()


func set_rule_by_name(rule_name: String) -> void:
	# 常见 3D 生命游戏规则
	match rule_name:
		"bays_4555":
			set_rule([5], [4, 5])
		"bays_5766":
			set_rule([6], [5, 7])
		"bays_2456":
			set_rule([5, 6], [2, 4])
		"conway_3d":  # 3D 版康威规则
			set_rule([3], [2, 3])
		_:
			set_rule([5], [4, 5])  # 默认 Bays 4555


# ---- 预设模式 ----

func load_pattern(pattern_name: String) -> void:
	clear()
	match pattern_name:
		"glider_3d":
			_place_glider()
		"blinker_3d":
			_place_blinker()
		"block_3d":
			_place_block()
		"random_sparse":
			_fill_random(0.15)
		"random_dense":
			_fill_random(0.4)
		"random_medium":
			_fill_random(0.25)
		"center_seed":
			set_cell(size_x / 2, size_y / 2, size_z / 2, 1)
		"cross_seed":
			var cx := size_x / 2
			var cy := size_y / 2
			var cz := size_z / 2
			set_cell(cx, cy, cz, 1)
			set_cell(cx + 1, cy, cz, 1)
			set_cell(cx - 1, cy, cz, 1)
			set_cell(cx, cy + 1, cz, 1)
			set_cell(cx, cy - 1, cz, 1)
			set_cell(cx, cy, cz + 1, 1)
			set_cell(cx, cy, cz - 1, 1)
		_:
			_fill_random(0.2)
	_recount_alive()


func _fill_random(density: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_msec()
	for i in range(_cells.size()):
		_cells[i] = 1 if rng.randf() < density else 0
	_recount_alive()


func _place_glider() -> void:
	# 3D 滑翔机: 一个会移动的小模式
	var cx := size_x / 2
	var cy := size_y / 2
	var cz := size_z / 2
	var offsets := [
		[0, 0, 0], [1, 0, 0], [2, 0, 0],
		[0, 1, 0], [1, 2, 0],
		[2, 1, 0],
	]
	for o in offsets:
		set_cell(cx + o[0], cy + o[1], cz + o[2], 1)
	_recount_alive()


func _place_blinker() -> void:
	# 3D 闪烁器: 周期2振荡
	var cx := size_x / 2
	var cy := size_y / 2
	var cz := size_z / 2
	set_cell(cx, cy, cz, 1)
	set_cell(cx + 1, cy, cz, 1)
	set_cell(cx - 1, cy, cz, 1)
	_recount_alive()


func _place_block() -> void:
	# 2x2x2 稳定块
	var cx := size_x / 2
	var cy := size_y / 2
	var cz := size_z / 2
	for dx in range(2):
		for dy in range(2):
			for dz in range(2):
				set_cell(cx + dx, cy + dy, cz + dz, 1)
	_recount_alive()


func _recount_alive() -> void:
	_alive_count = 0
	for i in range(_cells.size()):
		if _cells[i] == 1:
			_alive_count += 1


# ---- 模式检测 ----

func _record_history() -> void:
	_history.append(_cells.duplicate())
	if _history.size() > _max_history:
		_history.pop_front()

	_density_history.append(get_density())
	if _density_history.size() > _max_history:
		_density_history.pop_front()


func _detect_patterns() -> void:
	# 1. 灭绝检测
	if _alive_count == 0:
		if _phase_state != "extinct":
			phase_transition_detected.emit(_phase_state, "extinct")
		_phase_state = "extinct"
		pattern_detected.emit("extinct", {"step": _step_count})
		return

	# 2. 稳定态检测: 与上一步完全相同
	if _history.size() >= 2:
		if _cells == _history[_history.size() - 2]:
			if _phase_state != "stable":
				phase_transition_detected.emit(_phase_state, "stable")
			_phase_state = "stable"
			pattern_detected.emit("stable", {"step": _step_count, "alive": _alive_count})
			return

	# 3. 振荡器检测: 周期2-4
	for period in range(2, 5):
		if _history.size() > period:
			if _cells == _history[_history.size() - 1 - period]:
				if _phase_state != "oscillator":
					phase_transition_detected.emit(_phase_state, "oscillator")
				_phase_state = "oscillator"
				pattern_detected.emit("oscillator", {
					"step": _step_count,
					"period": period,
					"alive": _alive_count
				})
				return

	# 4. 相变检测: 基于密度变化
	var density := get_density()
	if _density_history.size() >= 4:
		var recent_avg := _avg(_density_history.slice(-4, -1))
		var change_rate := absf(density - recent_avg)

		var new_phase := "chaotic"
		if density < 0.05:
			new_phase = "sparse"
		elif density > 0.45:
			new_phase = "dense"
		elif change_rate < 0.02:
			new_phase = "stable"

		if new_phase != _phase_state and new_phase != "chaotic":
			phase_transition_detected.emit(_phase_state, new_phase)
		_phase_state = new_phase

	# 5. 滑翔机检测：质心持续位移且存活数稳定 → 判定为移动图案
	_check_glider()


func _avg(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var s := 0.0
	for v in arr:
		s += v
	return s / arr.size()


func _compute_center_of_mass() -> Vector3:
	# 计算存活细胞的质心（归一化坐标）
	if _alive_count == 0:
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for z in range(size_z):
		for y in range(size_y):
			for x in range(size_x):
				if _cells[idx(x, y, z)] != 0:
					sum += Vector3(x, y, z)
	return sum / float(_alive_count)


func _check_glider() -> void:
	# 滑翔机判定：连续4步质心位移方向一致且存活数波动小
	var com := _compute_center_of_mass()
	_com_history.append(com)
	if _com_history.size() > 6:
		_com_history.pop_front()
	if _com_history.size() < 4:
		return
	# 检查最近4步的位移向量是否方向一致
	var d1: Vector3 = _com_history[-1] - _com_history[-2]
	var d2: Vector3 = _com_history[-2] - _com_history[-3]
	var d3: Vector3 = _com_history[-3] - _com_history[-4]
	# 位移不能为零（静止的不是滑翔机）
	if d1.length() < 0.1 or d2.length() < 0.1 or d3.length() < 0.1:
		return
	# 方向一致性：点积为正且夹角小
	var cos12: float = d1.normalized().dot(d2.normalized())
	var cos23: float = d2.normalized().dot(d3.normalized())
	# 存活数波动小（±20%内）
	var alive_stable: bool = absf(float(_alive_count - _prev_alive_count)) < float(_alive_count) * 0.2
	if cos12 > 0.7 and cos23 > 0.7 and alive_stable:
		if not _glider_detected:
			_glider_detected = true
			pattern_detected.emit("glider", {
				"step": _step_count,
				"velocity": d1,
				"alive": _alive_count
			})
			if _phase_state != "glider":
				phase_transition_detected.emit(_phase_state, "glider")
				_phase_state = "glider"
	else:
		# 不再满足滑翔机条件时重置标志，允许后续重新检测
		_glider_detected = false


func is_glider_detected() -> bool:
	return _glider_detected


# ---- 守恒矩阵接口 ----
# CA 演化影响守恒: 细胞出生/死亡扰动质量/能量项

func get_conservation_perturbation() -> Dictionary:
	# 返回本步演化对守恒矩阵的扰动建议
	var births := maxi(0, _alive_count - _prev_alive_count)
	var deaths := maxi(0, _prev_alive_count - _alive_count)
	var density := get_density()
	var total_cells := size_x * size_y * size_z
	var cell_ratio := 1.0 / float(max(total_cells, 1))

	# 出生 → 质量增加, 死亡 → 能量释放
	# 按总格子数归一化, 避免大网格一步就瓦解
	# 不应用硬截断：返回原始物理值, 由 ConservationEngine 判断
	var mass_delta := (births - deaths) * cell_ratio * 0.6
	var energy_delta := (deaths - births) * cell_ratio * 0.4
	# 高密度 → 动量耦合增强, 但只在密度显著时触发
	var momentum_delta := (density - 0.05) * 0.08

	return {
		"mass": mass_delta,           # row 0
		"charge": 0.0,                # row 1 (CA 不直接影响电荷)
		"momentum": momentum_delta,   # row 2
		"energy": energy_delta,       # row 3
		"births": births,
		"deaths": deaths,
		"density": density,
	}


# ---- 序列化 ----

func serialize() -> Dictionary:
	return {
		"size": [size_x, size_y, size_z],
		"cells": _cells,
		"step": _step_count,
		"alive": _alive_count,
		"rule": {"birth": birth_rules, "survival": survival_rules},
		"phase": _phase_state,
	}


func get_cells() -> PackedByteArray:
	# 返回当前细胞状态副本，供育种保存使用
	return _cells.duplicate()


func set_cells(cells: PackedByteArray) -> void:
	# 从外部恢复细胞状态，供育种加载使用
	if cells.is_empty():
		push_warning("[CA] set_cells: 传入空数组，跳过")
		return
	if cells.size() != _cells.size():
		push_warning("[CA] set_cells: 大小不匹配 %d != %d，将调整" % [cells.size(), _cells.size()])
		_cells.resize(cells.size())
		_next_cells.resize(cells.size())
		# 网格维度变了，按立方体重新推算尺寸
		var cube_root := int(round(pow(float(cells.size()), 1.0 / 3.0)))
		if cube_root >= 2 and cube_root * cube_root * cube_root == cells.size():
			size_x = cube_root
			size_y = cube_root
			size_z = cube_root
	_cells = cells.duplicate()
	_next_cells.resize(_cells.size())
	_next_cells.fill(0)
	_alive_count = 0
	for i in range(_cells.size()):
		if _cells[i] != 0:
			_alive_count += 1
	# 重置历史，避免旧状态干扰模式检测
	_history.clear()
	_density_history.clear()
	_com_history.clear()
	_glider_detected = false


func deserialize(data: Dictionary) -> void:
	var s: Array = data.get("size", [10, 10, 10])
	if s.size() < 3:
		push_warning("[CA] deserialize: size 数组长度不足，使用默认值")
		s = [10, 10, 10]
	size_x = int(s[0])
	size_y = int(s[1])
	size_z = int(s[2])
	_cells = data.get("cells", PackedByteArray())
	_next_cells.resize(_cells.size())
	_next_cells.fill(0)
	_step_count = int(data.get("step", 0))
	_alive_count = int(data.get("alive", 0))
	var rule: Dictionary = data.get("rule", {})
	birth_rules = rule.get("birth", [5])
	survival_rules = rule.get("survival", [4, 5])
	_phase_state = data.get("phase", "extinct")
	_history.clear()
	_density_history.clear()
