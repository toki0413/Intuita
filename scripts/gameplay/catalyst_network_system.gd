# catalyst_network_system.gd
# 催化剂网络 - 基于Arrhenius方程的活化能降低与反应链
# k = A * exp(-Ea / RT), 催化剂降低Ea → 反应速率指数级提升
# 多个催化剂形成网络: 总速率 = Π(ki), 连击倍率随链长增长
# 玩家策略: 放置催化剂原子创建反应路径，链接反应物到产物

extends RefCounted

signal catalyst_activated(catalyst_id: int, rate_boost: float)
signal reaction_chain_completed(chain_length: int, total_multiplier: float)
signal catalyst_synergy_detected(catalysts: Array, synergy_factor: float)

# Arrhenius参数
const GAS_CONSTANT: float = 8.314e-3      # kJ/(mol·K), 方便数值范围
const PRE_EXPONENTIAL_A: float = 1e10      # 前指因子 (1/s)
const DEFAULT_ACTIVATION_E: float = 150.0  # kJ/mol, 默认活化能
const CATALYST_REDUCTION: float = 40.0     # 每个催化剂降低的活化能 (kJ/mol)
const SYNERGY_BONUS: float = 0.15          # 网络协同效应每边+15%
const MAX_CHAIN_BONUS: float = 10.0        # 连击上限
const NETWORK_RADIUS: float = 3.5          # 催化剂影响半径 (Å)

# 催化剂元素及其特性
const CATALYST_TYPES: Dictionary = {
	"Pt": {"reduction": 60.0, "specialty": "oxidation", "color": Color(0.9, 0.8, 0.5)},
	"Pd": {"reduction": 55.0, "specialty": "hydrogenation", "color": Color(0.8, 0.9, 0.6)},
	"Ni": {"reduction": 45.0, "specialty": "hydrogenation", "color": Color(0.7, 0.8, 0.7)},
	"Fe": {"reduction": 35.0, "specialty": "ammonia", "color": Color(0.9, 0.6, 0.4)},
	"Cu": {"reduction": 30.0, "specialty": "redox", "color": Color(0.8, 0.5, 0.3)},
	"Mn": {"reduction": 25.0, "specialty": "decomposition", "color": Color(0.6, 0.5, 0.8)},
}

# 活跃催化剂: id -> {node, position, element, reduction, specialty, color}
var _catalysts: Dictionary = {}
# 反应链历史 (用于连击)
var _chain_history: Array = []
var _last_chain_time: float = 0.0
const CHAIN_WINDOW: float = 8.0

# 当前温度 (K)
var _temperature: float = 300.0

var _canvas: Node3D = null
var _atom_mgr = null
var _float_text = null

# 视觉节点
var _network_lines: Array = []  # 连线MeshInstance3D引用

func _init(canvas: Node3D, atom_mgr, float_text) -> void:
	_canvas = canvas
	_atom_mgr = atom_mgr
	_float_text = float_text

# 注册催化剂原子
func register_catalyst(atom: Node3D) -> Dictionary:
	if atom == null or not is_instance_valid(atom):
		return {"success": false, "reason": "invalid_atom"}
	
	var symbol: String = _get_symbol(atom)
	if not CATALYST_TYPES.has(symbol):
		return {"success": false, "reason": "not_catalyst"}
	
	var cat_info: Dictionary = CATALYST_TYPES[symbol]
	var cat_id: int = atom.get_instance_id()
	
	_catalysts[cat_id] = {
		"node": atom,
		"position": atom.global_position,
		"element": symbol,
		"reduction": cat_info["reduction"],
		"specialty": cat_info["specialty"],
		"color": cat_info["color"],
	}
	
	# 检测网络协同
	var nearby: Array = _find_nearby_catalysts(atom.global_position, cat_id)
	if nearby.size() >= 1:
		var synergy: float = 1.0 + SYNERGY_BONUS * nearby.size()
		catalyst_synergy_detected.emit([cat_id] + nearby, synergy)
		if _float_text != null:
			_float_text.show_float_text(
				atom.global_position + Vector3(0, 1.2, 0),
				"催化网络 x%d (协同%.0f%%)" % [nearby.size() + 1, synergy * 100.0],
				cat_info["color"],
				2.5
			)
	
	# 视觉反馈
	if _float_text != null:
		_float_text.show_float_text(
			atom.global_position + Vector3(0, 0.8, 0),
			"⚡%s 催化剂" % symbol,
			cat_info["color"],
			2.0
		)
	
	catalyst_activated.emit(cat_id, _compute_rate_boost(cat_info["reduction"]))
	return {"success": true, "catalyst_id": cat_id, "reduction": cat_info["reduction"]}

# 注销催化剂
func unregister_catalyst(atom: Node3D) -> void:
	if atom == null:
		return
	var cat_id: int = atom.get_instance_id()
	_catalysts.erase(cat_id)

# Arrhenius反应速率: k = A * exp(-Ea / RT)
func compute_reaction_rate(activation_energy: float, temperature: float) -> float:
	if temperature <= 0.0:
		return 0.0
	var ea_eff: float = maxf(0.0, activation_energy)
	return PRE_EXPONENTIAL_A * exp(-ea_eff / (GAS_CONSTANT * temperature))

# 计算催化剂对反应的加速倍率
func _compute_rate_boost(reduction: float) -> float:
	# k_cat/k_uncat = exp(ΔEa / RT)
	var temp_k: float = maxf(1.0, _temperature)
	return exp(reduction / (GAS_CONSTANT * temp_k))

# 评估某位置放置反应物后的反应可行性
func evaluate_reaction(reactant_pos: Vector3, reactant_element: String) -> Dictionary:
	var result: Dictionary = {
		"catalyzed": false,
		"rate_boost": 1.0,
		"activating_catalysts": [],
		"chain_potential": 0,
		"predicted_rate": 0.0,
	}
	
	var base_ea: float = DEFAULT_ACTIVATION_E
	var total_reduction: float = 0.0
	var activating: Array = []
	
	for cat_id in _catalysts:
		var cat: Dictionary = _catalysts[cat_id]
		if not is_instance_valid(cat["node"]):
			continue
		var dist: float = reactant_pos.distance_to(cat["position"])
		if dist <= NETWORK_RADIUS:
			# 距离衰减: 近的催化剂效果更强
			var proximity_factor: float = 1.0 - (dist / NETWORK_RADIUS) * 0.5
			var effective_reduction: float = cat["reduction"] * proximity_factor
			total_reduction += effective_reduction
			activating.append({
				"id": cat_id,
				"element": cat["element"],
				"reduction": effective_reduction,
				"distance": dist,
			})
	
	if total_reduction > 0.0:
		result["catalyzed"] = true
		result["rate_boost"] = _compute_rate_boost(total_reduction)
		result["activating_catalysts"] = activating
		result["predicted_rate"] = compute_reaction_rate(base_ea - total_reduction, _temperature)
		result["chain_potential"] = activating.size()
	
	return result

# 尝试触发反应链
func try_reaction_chain(reaction_pos: Vector3) -> Dictionary:
	var now: float = Time.get_ticks_msec() / 1000.0
	var involved: Array = []
	var total_multiplier: float = 1.0
	
	# 找到所有参与反应的催化剂
	for cat_id in _catalysts:
		var cat: Dictionary = _catalysts[cat_id]
		if not is_instance_valid(cat["node"]):
			continue
		var dist: float = reaction_pos.distance_to(cat["position"])
		if dist <= NETWORK_RADIUS:
			var proximity: float = 1.0 - (dist / NETWORK_RADIUS) * 0.5
			var boost: float = _compute_rate_boost(cat["reduction"] * proximity)
			total_multiplier *= boost
			involved.append(cat_id)
	
	if involved.size() == 0:
		return {"triggered": false}
	
	# 连击逻辑
	if now - _last_chain_time < CHAIN_WINDOW:
		_chain_history.append(involved.size())
	else:
		_chain_history = [involved.size()]
	_last_chain_time = now
	
	var chain_length: int = _chain_history.size()
	total_multiplier = minf(total_multiplier, MAX_CHAIN_BONUS)
	
	# 连击奖励核心
	if chain_length >= 2:
		var bonus_cores: int = chain_length
		GameState.gain_cores(bonus_cores)
		if _float_text != null:
			_float_text.show_float_text(
				reaction_pos + Vector3(0, 2.0, 0),
				"催化连击 x%d! 倍率%.1fx +%d核心" % [chain_length, total_multiplier, bonus_cores],
				Color(1.0, 0.85, 0.2),
				3.0
			)
	
	reaction_chain_completed.emit(chain_length, total_multiplier)
	
	return {
		"triggered": true,
		"chain_length": chain_length,
		"total_multiplier": total_multiplier,
		"involved_catalysts": involved,
	}

# 寻找附近催化剂
func _find_nearby_catalysts(pos: Vector3, exclude_id: int) -> Array:
	var nearby: Array = []
	for cat_id in _catalysts:
		if cat_id == exclude_id:
			continue
		var cat: Dictionary = _catalysts[cat_id]
		if not is_instance_valid(cat["node"]):
			continue
		var dist: float = pos.distance_to(cat["position"])
		if dist <= NETWORK_RADIUS:
			nearby.append(cat_id)
	return nearby

# 获取催化剂位置建议 (给放置引导系统用)
func get_optimal_catalyst_positions(existing_atoms: Array) -> Array:
	var suggestions: Array = []
	if existing_atoms.size() == 0:
		return suggestions
	
	# 找到原子密集区域的边缘，催化剂放在边缘效果最好
	for atom in existing_atoms:
		if not is_instance_valid(atom):
			continue
		var pos: Vector3 = atom.global_position
		# 在原子周围3-4Å处建议催化剂位置
		var angles: Array = [0.0, 90.0, 180.0, 270.0]
		for angle in angles:
			var rad: float = deg_to_rad(angle)
			var suggest_pos: Vector3 = pos + Vector3(
				cos(rad) * 3.5, 0.0, sin(rad) * 3.5
			)
			# 检查建议点是否已有原子
			var occupied: bool = false
			for other in existing_atoms:
				if is_instance_valid(other) and other.global_position.distance_to(suggest_pos) < 1.0:
					occupied = true
					break
			if not occupied:
				suggestions.append({
					"position": suggest_pos,
					"reason": "催化位点",
					"priority": 0.8,
				})
	
	# 去重（保留最高优先级）
	var unique: Array = []
	for s in suggestions:
		var dup: bool = false
		for u in unique:
			if u["position"].distance_to(s["position"]) < 0.5:
				dup = true
				break
		if not dup:
			unique.append(s)
	
	return unique

func set_temperature(temp: float) -> void:
	_temperature = clampf(temp, 1.0, 5000.0)

func get_catalyst_count() -> int:
	return _catalysts.size()

func get_chain_count() -> int:
	return _chain_history.size()

func get_network_info() -> Dictionary:
	var active_count: int = 0
	for cat_id in _catalysts:
		if is_instance_valid(_catalysts[cat_id]["node"]):
			active_count += 1
	return {
		"total_catalysts": active_count,
		"chain_length": _chain_history.size(),
		"temperature": _temperature,
		"max_rate_boost": _compute_rate_boost(CATALYST_REDUCTION * 3.0),
	}

func on_level_reset() -> void:
	_catalysts.clear()
	_chain_history.clear()
	_last_chain_time = 0.0
	_temperature = 300.0
	_network_lines.clear()

func _get_symbol(atom: Node3D) -> String:
	if atom == null:
		return ""
	var sym: Variant = atom.get("element_symbol")
	if sym == null:
		return ""
	return str(sym)
