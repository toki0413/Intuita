# strain_field_system.gd
# 应变张量场 - 基于Eshelby点缺陷弹性场理论的简化模型
# 每个原子产生3x3对称应变张量，全场叠加
# 应变影响: 缺陷形成能、相变临界温度、磁各向异性

extends RefCounted

signal strain_critical(atom: Node3D, magnitude: float)
signal strain_relaxed(bonus_cores: int)

# 元素应变系数（原子半径越大应变越强）
const STRAIN_COEFFICIENTS: Dictionary = {
	"H": 0.4, "He": 0.2, "Li": 0.9, "Be": 0.5, "B": 0.4,
	"C": 0.3, "N": 0.3, "O": 0.3, "F": 0.3,
	"Na": 1.0, "Mg": 0.7, "Al": 0.6, "Si": 0.5,
	"P": 0.5, "S": 0.5, "Cl": 0.6,
	"Fe": 0.7, "Cu": 0.6, "Zn": 0.6, "Mn": 0.7, "Ni": 0.6, "Co": 0.6,
}

const STRAIN_THRESHOLD: float = 0.8
const RELAX_THRESHOLD: float = 0.2
const STRAIN_RANGE: float = 3.0
const SINGULARITY_CUTOFF: float = 0.15

var _canvas: Node3D = null
var _atom_mgr = null
var _float_text = null

# 应变源: atom_id -> {position, coefficient, symbol, node}
var _strain_sources: Dictionary = {}
# 缓存: atom_id -> {magnitude, volumetric, deviatoric}
var _strain_cache: Dictionary = {}
var _cache_dirty: bool = true

func _init(canvas: Node3D, atom_mgr, float_text) -> void:
	_canvas = canvas
	_atom_mgr = atom_mgr
	_float_text = float_text

# 原子放置时注册应变源
func on_atom_placed(atom: Node3D) -> void:
	if atom == null or not is_instance_valid(atom):
		return
	var symbol: String = _get_atom_symbol(atom)
	var coeff: float = STRAIN_COEFFICIENTS.get(symbol, 0.5)
	var a_id: int = atom.get_instance_id()
	_strain_sources[a_id] = {
		"position": atom.global_position,
		"coefficient": coeff,
		"symbol": symbol,
		"node": atom,
	}
	_cache_dirty = true
	_check_strain_at_atom(atom)

# 原子移除时注销应变源
func on_atom_removed(atom: Node3D) -> void:
	if atom == null:
		return
	var a_id: int = atom.get_instance_id()
	_strain_sources.erase(a_id)
	_strain_cache.erase(a_id)
	_cache_dirty = true

# 计算位置pos处的3x3应变张量（row-major, 长度9）
# exclude_id: 排除的原子ID（避免自身贡献导致的奇异性）
func compute_strain_tensor(pos: Vector3, exclude_id: int = -1) -> Array:
	var tensor: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

	for a_id in _strain_sources:
		if a_id == exclude_id:
			continue
		var source: Dictionary = _strain_sources[a_id]
		var src_pos: Vector3 = source["position"]
		var coeff: float = source["coefficient"]
		
		var r: Vector3 = pos - src_pos
		var r_mag: float = r.length()
		if r_mag > STRAIN_RANGE:
			continue
		r_mag = maxf(r_mag, SINGULARITY_CUTOFF)
		
		var r3: float = r_mag * r_mag * r_mag
		var factor: float = coeff / r3
		var r2: float = r_mag * r_mag
		
		# ε_ij = factor * (δ_ij - 3 * r_i * r_j / r²)
		tensor[0] += factor * (1.0 - 3.0 * r.x * r.x / r2)  # ε_xx
		tensor[1] += factor * (-3.0 * r.x * r.y / r2)         # ε_xy
		tensor[2] += factor * (-3.0 * r.x * r.z / r2)         # ε_xz
		tensor[3] = tensor[1]                                   # ε_yx = ε_xy
		tensor[4] += factor * (1.0 - 3.0 * r.y * r.y / r2)  # ε_yy
		tensor[5] += factor * (-3.0 * r.y * r.z / r2)         # ε_yz
		tensor[6] = tensor[2]                                   # ε_zx = ε_xz
		tensor[7] = tensor[5]                                   # ε_zy = ε_yz
		tensor[8] += factor * (1.0 - 3.0 * r.z * r.z / r2)  # ε_zz
	
	return tensor

# 体积应变（迹）
func get_volumetric_strain(pos: Vector3, exclude_id: int = -1) -> float:
	var t: Array = compute_strain_tensor(pos, exclude_id)
	return t[0] + t[4] + t[8]

# 应变大小（Frobenius范数）
func get_strain_magnitude(pos: Vector3, exclude_id: int = -1) -> float:
	var t: Array = compute_strain_tensor(pos, exclude_id)
	var sum_sq: float = 0.0
	for v in t:
		sum_sq += v * v
	return sqrt(sum_sq)

# 偏应变大小（形状变化部分）
func get_deviatoric_strain(pos: Vector3, exclude_id: int = -1) -> float:
	var t: Array = compute_strain_tensor(pos, exclude_id)
	var trace_val: float = t[0] + t[4] + t[8]
	var third: float = trace_val / 3.0
	var dev_sq: float = 0.0
	dev_sq += pow(t[0] - third, 2.0)
	dev_sq += pow(t[4] - third, 2.0)
	dev_sq += pow(t[8] - third, 2.0)
	dev_sq += 2.0 * (pow(t[1], 2.0) + pow(t[2], 2.0) + pow(t[5], 2.0))
	return sqrt(dev_sq)

# 获取原子的局部应变（带缓存）
func get_atom_strain(atom: Node3D) -> Dictionary:
	if atom == null:
		return {"magnitude": 0.0, "volumetric": 0.0, "deviatoric": 0.0}
	var a_id: int = atom.get_instance_id()
	if _cache_dirty:
		_rebuild_cache()
	return _strain_cache.get(a_id, {"magnitude": 0.0, "volumetric": 0.0, "deviatoric": 0.0})

# 应变对缺陷预算的修正：高应变区域每3个原子+1预算
func get_defect_budget_modifier() -> int:
	if _cache_dirty:
		_rebuild_cache()
	var high_count: int = 0
	for a_id in _strain_cache:
		var data: Dictionary = _strain_cache[a_id]
		if data.get("magnitude", 0.0) > STRAIN_THRESHOLD:
			high_count += 1
	return high_count / 3

# 应变对相变温度的修正：高应变降低临界温度
func get_phase_temp_modifier() -> float:
	if _cache_dirty:
		_rebuild_cache()
	if _strain_cache.is_empty():
		return 0.0
	var total: float = 0.0
	for a_id in _strain_cache:
		total += _strain_cache[a_id].get("magnitude", 0.0)
	var avg: float = total / float(_strain_cache.size())
	return -avg * 50.0

# 应变方向（用于磁各向异性）
func get_strain_direction(pos: Vector3) -> Vector3:
	var t: Array = compute_strain_tensor(pos)
	# 主应变方向近似：取对角元素最大的轴
	var xx: float = absf(t[0])
	var yy: float = absf(t[4])
	var zz: float = absf(t[8])
	if xx >= yy and xx >= zz:
		return Vector3(1.0, 0.0, 0.0)
	elif yy >= zz:
		return Vector3(0.0, 1.0, 0.0)
	else:
		return Vector3(0.0, 0.0, 1.0)

# 计算原子受到的应变松弛力 — 梯度下降方向
# 力 = -∇U，U ~ Σ (coeff/r³)，所以 F ~ Σ (coeff/r⁴) * r̂
# 这个力把原子推向低应变区域，让放置后的原子自动微调到能量更低的位置
func compute_relaxation_force(atom: Node3D, all_atoms: Array) -> Vector3:
	if atom == null or not is_instance_valid(atom):
		return Vector3.ZERO
	var pos: Vector3 = atom.global_position
	var force: Vector3 = Vector3.ZERO
	for other in all_atoms:
		if other == atom or not is_instance_valid(other):
			continue
		var r: Vector3 = pos - other.global_position
		var r_mag: float = r.length()
		if r_mag > STRAIN_RANGE or r_mag < SINGULARITY_CUTOFF:
			continue
		var sym: String = other.get("element_symbol") if other.get("element_symbol") else "?"
		var coeff: float = STRAIN_COEFFICIENTS.get(sym, 0.5)
		# 排斥力 ~ coeff / r⁴ * r̂（应变能的梯度）
		var r4: float = r_mag * r_mag * r_mag * r_mag
		force += r.normalized() * (coeff / r4 * 0.001)
	return force

# 检查原子处应变是否超临界
func _check_strain_at_atom(atom: Node3D) -> void:
	if atom == null or not is_instance_valid(atom):
		return
	var pos: Vector3 = atom.global_position
	var mag: float = get_strain_magnitude(pos, atom.get_instance_id())
	if mag > STRAIN_THRESHOLD:
		strain_critical.emit(atom, mag)
		if _float_text != null:
			_float_text.show_float_text(
				pos + Vector3(0, 0.5, 0),
				"应变超临界! %.2f" % mag,
				Color(1.0, 0.3, 0.3),
				2.0
			)

# 重建应变缓存
func _rebuild_cache() -> void:
	_strain_cache.clear()
	for a_id in _strain_sources:
		var source: Dictionary = _strain_sources[a_id]
		var node = source.get("node", null)
		if node == null or not is_instance_valid(node) or not node.is_inside_tree():
			continue
		var pos: Vector3 = node.global_position
		var mag: float = get_strain_magnitude(pos, a_id)
		var vol: float = get_volumetric_strain(pos, a_id)
		var dev: float = get_deviatoric_strain(pos, a_id)
		_strain_cache[a_id] = {
			"magnitude": mag,
			"volumetric": vol,
			"deviatoric": dev,
		}
	_cache_dirty = false
	_check_relaxation_reward()

# 检查应变松弛奖励
func _check_relaxation_reward() -> void:
	if _strain_cache.size() < 3:
		return
	var total_mag: float = 0.0
	for a_id in _strain_cache:
		total_mag += _strain_cache[a_id].get("magnitude", 0.0)
	var avg_mag: float = total_mag / float(_strain_cache.size())
	if avg_mag < RELAX_THRESHOLD:
		var bonus: int = 2
		strain_relaxed.emit(bonus)
		if GameState != null:
			GameState.gain_cores(bonus)
		if _float_text != null:
			_float_text.show_float_text(
				Vector3(0, 3, 0),
				"应变松弛! +%d核心" % bonus,
				Color(0.3, 1.0, 0.5),
				3.0
			)
		if GameLogger != null:
			GameLogger.info("StrainField", "[应变] 结构松弛奖励 +%d核心, 平均应变: %.3f" % [bonus, avg_mag])

func on_level_reset() -> void:
	_strain_sources.clear()
	_strain_cache.clear()
	_cache_dirty = true

# 获取全场应变摘要
func get_strain_info() -> Dictionary:
	if _cache_dirty:
		_rebuild_cache()
	var total_mag: float = 0.0
	var max_mag: float = 0.0
	var high_count: int = 0
	for a_id in _strain_cache:
		var mag: float = _strain_cache[a_id].get("magnitude", 0.0)
		total_mag += mag
		max_mag = maxf(max_mag, mag)
		if mag > STRAIN_THRESHOLD:
			high_count += 1
	var count: int = _strain_cache.size()
	return {
		"avg_strain": total_mag / maxf(1.0, float(count)),
		"max_strain": max_mag,
		"high_strain_atoms": high_count,
		"total_atoms": count,
		"defect_budget_bonus": get_defect_budget_modifier(),
		"phase_temp_shift": get_phase_temp_modifier(),
	}

func _get_atom_symbol(atom: Node3D) -> String:
	if atom == null:
		return ""
	var sym: Variant = atom.get("element_symbol")
	if sym == null:
		return ""
	return str(sym)
