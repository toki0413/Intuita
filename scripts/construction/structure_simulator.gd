# structure_simulator.gd
# 结构物理模拟器 - 让原子自己动、键自动形成/断裂
# 这是三种新模式（晶体生长/物理诊断/连锁反应）的共同基础
#
# 核心思想：物理是"演员"不是"裁判"
#   - 原子会根据力场自动移动（不是玩家手动放置）
#   - 键会根据距离和价态规则自动形成/断裂
#   - 结构会自发演化到平衡态（或远离平衡态）
#   - 玩家通过设置条件来引导物理，而不是直接控制
#
# Responsibilities:
#   - 简化分子动力学：弹簧力+排斥力+守恒约束力
#   - 自动键形成/断裂
#   - 晶体生长模拟
#   - 缺陷传播模拟
#   - 连锁反应模拟
#
# Dependencies:
#   - ConservationEngine (守恒约束力)

extends Node

# 模拟参数
@export var simulation_speed: float = 1.0
@export var damping: float = 0.85  # 速度阻尼，防止振荡
@export var bond_form_distance: float = 2.0  # 自动成键距离阈值
@export var bond_break_distance: float = 3.5  # 自动断键距离阈值
@export var repulsion_strength: float = 0.5  # 原子间排斥力强度
@export var spring_strength: float = 2.0  # 键弹簧力强度
@export var conservation_force: float = 1.5  # 守恒约束力强度
@export var temperature: float = 0.3  # 温度（热运动幅度）
@export var growth_rate: float = 0.0  # 晶体生长速率（0=不生长）
@export var auto_bond_formation: bool = false  # 是否自动形成/断裂键

# 模拟状态
var _atoms: Array[Node3D] = []
var _bonds: Array[Dictionary] = []  # [{a: Node3D, b: Node3D, rest_length: float}]
var _velocities: Dictionary = {}  # {atom_id: Vector3}
var _bond_pairs: Dictionary = {}  # {pair_key: true} 用于O(1)键存在检查
var _is_running: bool = false
var _sim_time: float = 0.0
var _growth_timer: float = 0.0
var _growth_queue: Array[Dictionary] = []  # 待生长的原子位置

# 元素价态规则
var _valence_rules: Dictionary = {
	"H": 1, "Na": 1, "K": 1, "Li": 1,
	"O": 2, "Ca": 2, "Mg": 2, "Sr": 2, "Ba": 2, "Fe": 2,
	"N": 3, "Al": 3,
	"C": 4, "Si": 4, "Ti": 4,
	"Cl": 1, "F": 1, "Br": 1,  # 卤素接受1个键
}

# 信号
signal atom_auto_placed(atom_node: Node3D)
signal bond_auto_formed(atom_a: Node3D, atom_b: Node3D)
signal bond_auto_broken(atom_a: Node3D, atom_b: Node3D)
signal cascade_triggered(source: Node3D, affected: Array[Node3D])


func _process(delta: float) -> void:
	if not _is_running or _atoms.is_empty():
		return

	_sim_time += delta
	var sim_delta := delta * simulation_speed

	# 1. 计算力并移动原子
	_apply_forces(sim_delta)

	# 2. 自动键形成/断裂
	_update_bonds()

	# 3. 晶体生长
	if growth_rate > 0.0:
		_process_growth(sim_delta)

	# 4. 连锁反应检测
	_detect_cascades()


func start_simulation() -> void:
	_is_running = true


func stop_simulation() -> void:
	_is_running = false


func set_atoms(atoms: Array[Node3D]) -> void:
	_atoms = atoms
	_velocities.clear()
	for atom in atoms:
		if is_instance_valid(atom):
			_velocities[atom.get_instance_id()] = Vector3.ZERO


func add_atom(atom: Node3D) -> void:
	if atom not in _atoms:
		_atoms.append(atom)
		_velocities[atom.get_instance_id()] = Vector3.ZERO


func remove_atom(atom: Node3D) -> void:
	_atoms.erase(atom)
	_velocities.erase(atom.get_instance_id())
	# 移除相关键
	var bonds_to_remove: Array[int] = []
	for i in range(_bonds.size()):
		if _bonds[i]["a"] == atom or _bonds[i]["b"] == atom:
			bonds_to_remove.append(i)
	bonds_to_remove.reverse()
	for i in bonds_to_remove:
		_remove_bond_pair(_bonds[i]["a"], _bonds[i]["b"])
		_bonds.remove_at(i)


func set_growth_positions(positions: Array[Dictionary]) -> void:
	# 设置晶体生长的候选位置
	# 每个位置: {position: Vector3, element: String, priority: float}
	_growth_queue = positions.duplicate(true)
	_growth_queue.sort_custom(func(a, b): return a.get("priority", 0.0) > b.get("priority", 0.0))


func _apply_forces(delta: float) -> void:
	# 简化分子动力学：计算每个原子受到的合力并更新位置
	var forces: Dictionary = {}  # {atom_id: Vector3}

	# 初始化力
	for atom in _atoms:
		if not is_instance_valid(atom):
			continue
		forces[atom.get_instance_id()] = Vector3.ZERO

	# 1. 键弹簧力（胡克定律）
	for bond in _bonds:
		var a: Node3D = bond["a"]
		var b: Node3D = bond["b"]
		if not is_instance_valid(a) or not is_instance_valid(b):
			continue
		var diff := b.global_position - a.global_position
		var dist := diff.length()
		if dist < 0.001:
			continue
		var rest: float = bond.get("rest_length", 1.5)
		var displacement := dist - rest
		var force := diff.normalized() * displacement * spring_strength
		forces[a.get_instance_id()] += force
		forces[b.get_instance_id()] -= force

	# 2. 原子间排斥力（短程排斥，使用空间分桶优化）
	var repulsion_cutoff := 4.0
	var grid_r: Dictionary = {}
	for atom in _atoms:
		if not is_instance_valid(atom):
			continue
		var gk := _grid_key(atom.global_position, repulsion_cutoff)
		if not grid_r.has(gk):
			grid_r[gk] = []
		grid_r[gk].append(atom)

	for key in grid_r:
		var cell: Array = grid_r[key]
		# 同格子内
		for i in range(cell.size()):
			for j in range(i + 1, cell.size()):
				_apply_repulsion(cell[i], cell[j], forces, repulsion_strength)
		# 相邻格子
		var cx2: int = key.x
		var cy2: int = key.y
		var cz2: int = key.z
		for dx in [0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					if dx == 0 and dy <= 0 and dz <= 0:
						continue
					var nk := Vector3i(cx2 + dx, cy2 + dy, cz2 + dz)
					if not grid_r.has(nk):
						continue
					for a in cell:
						for b in grid_r[nk]:
							_apply_repulsion(a, b, forces, repulsion_strength)

	# 3. 守恒约束力：偏离越大，拉回力越强
	var dev_summary: Dictionary = ConservationEngine.get_deviation_summary()
	var max_dev: float = 0.0
	for key in dev_summary:
		max_dev = maxf(max_dev, dev_summary[key]["deviation"])
	if max_dev > 0.1:
		# 守恒偏离时，原子被拉向最近的Wyckoff位置
		# 简化实现：向晶格中心施加恢复力
		var center := _get_structure_center()
		for atom in _atoms:
			if not is_instance_valid(atom):
				continue
			var to_center := center - atom.global_position
			var force := to_center * conservation_force * max_dev
			forces[atom.get_instance_id()] += force

	# 4. 热运动（随机力）
	if temperature > 0.01:
		for atom in _atoms:
			if not is_instance_valid(atom):
				continue
			var thermal := Vector3(
				randfn(0.0, temperature),
				randfn(0.0, temperature),
				randfn(0.0, temperature)
			)
			forces[atom.get_instance_id()] += thermal

	# 更新速度和位置
	for atom in _atoms:
		if not is_instance_valid(atom):
			continue
		var id := atom.get_instance_id()
		var vel: Vector3 = _velocities.get(id, Vector3.ZERO)
		vel = (vel + forces.get(id, Vector3.ZERO) * delta) * damping
		_velocities[id] = vel
		atom.global_position += vel * delta


func _update_bonds() -> void:
	# 自动键形成和断裂
	# 1. 检查已有键是否需要断裂
	var bonds_to_break: Array[int] = []
	for i in range(_bonds.size()):
		var bond := _bonds[i]
		var a: Node3D = bond["a"]
		var b: Node3D = bond["b"]
		if not is_instance_valid(a) or not is_instance_valid(b):
			bonds_to_break.append(i)
			continue
		var dist := a.global_position.distance_to(b.global_position)
		if dist > bond_break_distance:
			bonds_to_break.append(i)
	bonds_to_break.reverse()
	for i in bonds_to_break:
		var bond := _bonds[i]
		_remove_bond_pair(bond["a"], bond["b"])
		bond_auto_broken.emit(bond["a"], bond["b"])
		_bonds.remove_at(i)

	# 2. 检查是否需要形成新键（使用空间分桶减少候选对）
	if not auto_bond_formation:
		return
	# 构建空间哈希网格，格子大小=成键距离
	var cell_size := bond_form_distance
	var grid: Dictionary = {}
	for atom in _atoms:
		if not is_instance_valid(atom):
			continue
		var key := _grid_key(atom.global_position, cell_size)
		if not grid.has(key):
			grid[key] = []
		grid[key].append(atom)

	# 只检查相邻格子内的原子对
	var checked_pairs: Dictionary = {}
	for key in grid:
		var cell_atoms: Array = grid[key]
		# 同格子内的原子对
		for i in range(cell_atoms.size()):
			for j in range(i + 1, cell_atoms.size()):
				_try_form_bond(cell_atoms[i], cell_atoms[j], checked_pairs)
		# 相邻格子（只查+1方向避免重复）
		var cx: int = key.x
		var cy: int = key.y
		var cz: int = key.z
		for dx in [0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					if dx == 0 and dy <= 0 and dz <= 0:
						continue
					var nkey := Vector3i(cx + dx, cy + dy, cz + dz)
					if not grid.has(nkey):
						continue
					var neighbors: Array = grid[nkey]
					for a in cell_atoms:
						for b in neighbors:
							_try_form_bond(a, b, checked_pairs)


func _grid_key(pos: Vector3, cell_size: float) -> Vector3i:
	return Vector3i(
		int(pos.x / cell_size),
		int(pos.y / cell_size),
		int(pos.z / cell_size)
	)


func _apply_repulsion(a: Node3D, b: Node3D, forces: Dictionary, strength: float) -> void:
	if not is_instance_valid(a) or not is_instance_valid(b):
		return
	var diff := b.global_position - a.global_position
	var dist := diff.length()
	if dist < 0.001 or dist > 4.0:
		return
	var repulsion := diff.normalized() * strength / maxf(dist * dist, 0.1)
	forces[a.get_instance_id()] -= repulsion
	forces[b.get_instance_id()] += repulsion


func _bond_key(a: Node3D, b: Node3D) -> String:
	var id_a := a.get_instance_id()
	var id_b := b.get_instance_id()
	if id_a < id_b:
		return "%d-%d" % [id_a, id_b]
	return "%d-%d" % [id_b, id_a]


func _add_bond_pair(a: Node3D, b: Node3D) -> void:
	_bond_pairs[_bond_key(a, b)] = true


func _remove_bond_pair(a: Node3D, b: Node3D) -> void:
	_bond_pairs.erase(_bond_key(a, b))


func _try_form_bond(a: Node3D, b: Node3D, checked: Dictionary) -> void:
	if not is_instance_valid(a) or not is_instance_valid(b):
		return
	var bk := _bond_key(a, b)
	if checked.has(bk):
		return
	checked[bk] = true
	if _bond_pairs.has(bk):
		return
	var dist := a.global_position.distance_to(b.global_position)
	if dist < bond_form_distance:
		if _can_form_bond(a, b):
			var rest_length := dist
			_bonds.append({"a": a, "b": b, "rest_length": rest_length})
			_add_bond_pair(a, b)
			bond_auto_formed.emit(a, b)


func _can_form_bond(a: Node3D, b: Node3D) -> bool:
	# 检查两个原子是否可以形成键（价态检查）
	var a_bonds := _count_bonds_for(a)
	var b_bonds := _count_bonds_for(b)
	var a_symbol: String = _get_element_symbol(a)
	var b_symbol: String = _get_element_symbol(b)
	var a_max: int = _valence_rules.get(a_symbol, 4)
	var b_max: int = _valence_rules.get(b_symbol, 4)
	return a_bonds < a_max and b_bonds < b_max


func _count_bonds_for(atom: Node3D) -> int:
	var count := 0
	for bond in _bonds:
		if bond["a"] == atom or bond["b"] == atom:
			count += 1
	return count


func _get_element_symbol(atom: Node3D) -> String:
	# 从atom_node获取元素符号
	if atom.has_method("get_element_symbol"):
		return atom.get_element_symbol()
	# 回退：从名称或元数据获取
	var name: String = atom.name
	if name.find("_") >= 0:
		return name.split("_")[0]
	return "X"


func _get_structure_center() -> Vector3:
	if _atoms.is_empty():
		return Vector3.ZERO
	var center := Vector3.ZERO
	var count := 0
	for atom in _atoms:
		if is_instance_valid(atom):
			center += atom.global_position
			count += 1
	return center / maxf(count, 1)


func _process_growth(delta: float) -> void:
	# 晶体生长：按速率在候选位置添加新原子
	_growth_timer += delta
	var growth_interval := 1.0 / maxf(growth_rate, 0.01)
	if _growth_timer >= growth_interval and not _growth_queue.is_empty():
		_growth_timer = 0.0
		var next_pos := _growth_queue.pop_front() as Dictionary
		# 通知外部系统在指定位置创建原子
		atom_auto_placed.emit(_create_ghost_atom(next_pos))


func _create_ghost_atom(pos_data: Dictionary) -> Node3D:
	# 创建一个幽灵原子节点（仅用于信号传递）
	# 实际原子创建由 ConstructionCanvas 处理
	var ghost := Node3D.new()
	ghost.name = "GrowthGhost_%s" % pos_data.get("element", "X")
	ghost.global_position = pos_data.get("position", Vector3.ZERO)
	ghost.set_meta("element", pos_data.get("element", "X"))
	ghost.set_meta("is_growth_ghost", true)
	return ghost


func _detect_cascades() -> void:
	# 检测连锁反应：一个原子的剧烈移动是否影响邻居
	for atom in _atoms:
		if not is_instance_valid(atom):
			continue
		var id := atom.get_instance_id()
		var vel: Vector3 = _velocities.get(id, Vector3.ZERO)
		var speed := vel.length()
		# 速度超过阈值 = 剧烈移动
		if speed > 2.0:
			var affected: Array[Node3D] = []
			for other in _atoms:
				if other == atom or not is_instance_valid(other):
					continue
				var dist := atom.global_position.distance_to(other.global_position)
				if dist < 3.0:
					affected.append(other)
			if not affected.is_empty():
				cascade_triggered.emit(atom, affected)


func get_simulation_info() -> Dictionary:
	return {
		"running": _is_running,
		"atom_count": _atoms.size(),
		"bond_count": _bonds.size(),
		"sim_time": _sim_time,
		"temperature": temperature,
		"growth_rate": growth_rate,
		"growth_queue_size": _growth_queue.size(),
	}


func inject_defect(atom: Node3D, defect_type: String) -> void:
	# 注入缺陷（物理诊断模式用）
	# defect_type: "vacancy"（空位）, "substitution"（替换）, "displacement"（位移）
	if not is_instance_valid(atom):
		return
	match defect_type:
		"vacancy":
			remove_atom(atom)
			if atom.has_method("start_disintegration"):
				atom.start_disintegration(0)
			else:
				atom.queue_free()
		"displacement":
			# 将原子随机偏移
			var offset := Vector3(
				randfn(0.0, 1.0),
				randfn(0.0, 1.0),
				randfn(0.0, 1.0)
			)
			atom.global_position += offset
			_velocities[atom.get_instance_id()] = offset * 2.0
		"substitution":
			# 标记为需要替换（由外部系统处理）
			atom.set_meta("needs_substitution", true)


func trigger_cascade_at(position: Vector3, radius: float = 3.0, impulse: float = 5.0) -> void:
	# 在指定位置触发连锁反应（连锁反应模式用）
	for atom in _atoms:
		if not is_instance_valid(atom):
			continue
		var dist := atom.global_position.distance_to(position)
		if dist < radius:
			var direction := (atom.global_position - position).normalized()
			var strength := impulse * (1.0 - dist / radius)
			_velocities[atom.get_instance_id()] = direction * strength
