# diffusion_engine.gd
# 扩散模拟引擎 - 晶格上的 Metropolis 蒙特卡洛分子动力学
#
# 在 "reaction" 和 "device" 域中运行。
# 使用正确的 Metropolis 算法：
#   1. 提出随机移动（6 方向邻居）
#   2. 计算能量差 ΔE = E_new - E_old
#   3. 若 ΔE < 0，无条件接受；否则以 exp(-ΔE / kT) 概率接受
#   4. 尝试频率由 mobility * dt 控制
#
# 能量模型：
#   - 同号电荷粒子在相邻格子的 Coulomb 排斥（简化 1/r²）
#   - 障碍物为无限势垒（在提出阶段排除）
#   - 可选外部势场 callback

extends Node
class_name DiffusionEngine

# 晶格参数
var lattice_size: Vector3i = Vector3i(8, 8, 8)
var cell_size: float = 1.0

# 粒子: Array[Dictionary]
# 每个 particle: {"id": int, "type": String, "position": Vector3i, "charge": float, "mobility": float}
var particles: Array

# 障碍物: Array[Vector3i] - 已占据的晶格位置（无限势垒）
var obstacles: Array

# 温度 (K) 与热能量 kT（eV 单位，k_B = 8.617333262e-5 eV/K）
var temperature: float = 300.0
var _kT: float = 0.02585  # 300K 默认值

# 电荷相互作用截断半径（格子单位）
var interaction_radius: float = 2.0

# 时间步长
var dt: float = 0.01

# 运行状态
var _running: bool = false

# 6 方向邻居（类常量，GDScript 不支持 static const Array）
var _DIRECTIONS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

# 外部势场回调: func(pos: Vector3i) -> float
var _external_field: Callable = Callable()

# 信号
signal particle_moved(id: int, from_pos: Vector3i, to_pos: Vector3i)
signal concentration_updated(field: Dictionary)

func _init(size: Vector3i = Vector3i(8, 8, 8), cell: float = 1.0) -> void:
	lattice_size = size
	cell_size = cell
	particles = []
	obstacles = []
	_update_kT()

func set_temperature(kelvin: float) -> void:
	temperature = maxf(kelvin, 1.0)
	_update_kT()

func _update_kT() -> void:
	const BOLTZMANN_EV: float = 8.617333262e-5
	_kT = BOLTZMANN_EV * temperature

func set_external_field(callback: Callable) -> void:
	_external_field = callback

func reset() -> void:
	particles = []
	obstacles = []
	_running = false

func add_particle(type: String, pos: Vector3i, charge: float = 1.0, mobility: float = 1.0) -> int:
	var id := particles.size()
	particles.append({
		"id": id,
		"type": type,
		"position": pos,
		"charge": charge,
		"mobility": mobility,
	})
	return id

func add_obstacle(pos: Vector3i) -> void:
	if not pos in obstacles:
		obstacles.append(pos)

func remove_obstacle(pos: Vector3i) -> void:
	obstacles.erase(pos)

func start() -> void:
	_running = true

func stop() -> void:
	_running = false

func step() -> void:
	if not _running:
		return

	for p in particles:
		var pid: int = p["id"]
		var old_pos: Vector3i = p["position"]
		var mobility: float = p["mobility"]
		var charge: float = p["charge"]

		# 尝试频率： mobility * dt 决定每步尝试次数的期望值
		var attempt_count := int(ceilf(mobility * dt))
		if attempt_count <= 0 and randf() < mobility * dt:
			attempt_count = 1

		for _attempt in range(attempt_count):
			# 随机选择 6 方向之一
			var dir := _DIRECTIONS[randi() % _DIRECTIONS.size()]
			var new_pos := old_pos + dir

			# 边界检查
			if not _in_bounds(new_pos):
				continue

			# 障碍物检查（无限势垒）
			if new_pos in obstacles:
				continue

			# 其他粒子占据检查（硬球排斥）
			if _is_occupied_by_other(pid, new_pos):
				continue

			# Metropolis 接受准则
			var E_old := _compute_energy(pid, old_pos)
			var E_new := _compute_energy(pid, new_pos)
			var dE := E_new - E_old

			var accepted := false
			if dE <= 0.0:
				accepted = true
			else:
				var boltzmann := exp(-dE / maxf(_kT, 1e-9))
				if randf() < boltzmann:
					accepted = true

			if accepted:
				p["position"] = new_pos
				particle_moved.emit(pid, old_pos, new_pos)

				# 通知守恒引擎：电荷位移产生微小电荷扰动
				if ConservationEngine != null:
					var delta: float = charge * 0.001
					ConservationEngine.apply_perturbation(1, 1, delta, "diffusion_move_%d" % pid)

				# 更新 old_pos 以允许连续同步移动
				old_pos = new_pos

	_emit_concentration_field()

func _in_bounds(pos: Vector3i) -> bool:
	return pos.x >= 0 and pos.x < lattice_size.x and pos.y >= 0 and pos.y < lattice_size.y and pos.z >= 0 and pos.z < lattice_size.z

func _is_occupied_by_other(exclude_id: int, pos: Vector3i) -> bool:
	for other in particles:
		if other["id"] != exclude_id and other["position"] == pos:
			return true
	return false

func _compute_energy(particle_id: int, pos: Vector3i) -> float:
	var p = particles[particle_id]
	var charge: float = p["charge"]
	var energy := 0.0

	# 粒子-粒子相互作用（简化 Coulomb：同号排斥，异号吸引）
	for other in particles:
		if other["id"] == particle_id:
			continue
		var d_sq := float(pos.distance_squared_to(other["position"]))
		if d_sq > 0.0 and d_sq <= interaction_radius * interaction_radius:
			# 1/r² 势（晶格单位），避免除以零
			energy += charge * other["charge"] / maxf(d_sq, 0.1)

	# 外部势场
	if _external_field.is_valid():
		energy += _external_field.call(pos)

	return energy

func _emit_concentration_field() -> void:
	var field: Dictionary = {}
	for p in particles:
		var pos: Vector3i = p["position"]
		var key := "%d,%d,%d" % [pos.x, pos.y, pos.z]
		if not field.has(key):
			field[key] = 0
		field[key] += 1
	concentration_updated.emit(field)

func get_concentration_at(pos: Vector3i) -> int:
	var count := 0
	for p in particles:
		if p["position"] == pos:
			count += 1
	return count

func is_running() -> bool:
	return _running

func get_kT() -> float:
	return _kT

func get_particle_energy(particle_id: int) -> float:
	if particle_id < 0 or particle_id >= particles.size():
		return 0.0
	return _compute_energy(particle_id, particles[particle_id]["position"])
