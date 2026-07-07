# quantum_tunneling_system.gd
# 量子隧穿事件 - 基于WKB近似的概率性奇特反应
# T ≈ exp(-2 * ∫κ(x)dx), κ = sqrt(2m(V-E))/ℏ
# 原子极近时势垒变薄，隧穿概率飙升
# 可合成常规无法实现的奇特化合物，但有随机风险
# 解决"放原子无聊": 近距离放置变得刺激，有惊喜有风险

extends RefCounted

signal tunneling_event_triggered(atom_a: Node3D, atom_b: Node3D, probability: float, outcome: String)
signal exotic_compound_formed(formula: String, bonus_cores: int)
signal tunneling_catastrophe(atom: Node3D, reason: String)

# 物理常数
const HBAR: float = 1.055e-34      # J·s
const ELECTRON_MASS: float = 9.109e-31  # kg
const EV_TO_J: float = 1.602e-19    # eV → J 转换

# 游戏参数
const TUNNELING_THRESHOLD: float = 1.2   # Å, 小于此距离开始计算隧穿
const BARRIER_HEIGHT_EV: float = 2.0     # eV, 默认势垒高度
const PROBABILITY_CAP: float = 0.95      # 隧穿概率上限
const CATASTROPHE_THRESHOLD: float = 0.85  # 超过此概率可能灾难
const COOLDOWN_FRAMES: int = 60          # 防连续触发冷却

# 奇特化合物库 (隧穿才能合成)
const EXOTIC_COMPOUNDS: Array = [
	{"formula": "H•H", "name": "量子氢分子", "bonus": 8, "color": Color(0.5, 0.9, 1.0), "stability": 0.7},
	{"formula": "He@C60", "name": "富勒烯囚氦", "bonus": 15, "color": Color(0.8, 0.6, 1.0), "stability": 0.5},
	{"formula": "Fe•O•Fe", "name": "量子氧化铁簇", "bonus": 12, "color": Color(1.0, 0.5, 0.3), "stability": 0.6},
	{"formula": "Cu•Cu•Cu", "name": "量子铜三角", "bonus": 10, "color": Color(0.9, 0.7, 0.4), "stability": 0.8},
	{"formula": "Na•Cl•Na", "name": "离子隧穿键", "bonus": 14, "color": Color(0.6, 1.0, 0.6), "stability": 0.65},
	{"formula": "C•C•C•C", "name": "量子碳环", "bonus": 20, "color": Color(0.4, 0.8, 1.0), "stability": 0.55},
	{"formula": "H•O•H", "name": "量子水分子", "bonus": 6, "color": Color(0.3, 0.7, 1.0), "stability": 0.9},
]

var _canvas: Node3D = null
var _atom_mgr = null
var _float_text = null

# 已触发的隧穿事件记录
var _tunneling_history: Array = []
var _last_trigger_frame: int = -COOLDOWN_FRAMES
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# 量子概率云视觉节点
var _probability_clouds: Dictionary = {}  # pair_key -> MeshInstance3D

func _init(canvas: Node3D, atom_mgr, float_text) -> void:
	_canvas = canvas
	_atom_mgr = atom_mgr
	_float_text = float_text
	_rng.randomize()

# 检查两个原子间的隧穿概率
func compute_tunneling_probability(atom_a: Node3D, atom_b: Node3D) -> float:
	if atom_a == null or atom_b == null:
		return 0.0
	if not is_instance_valid(atom_a) or not is_instance_valid(atom_b):
		return 0.0
	
	var dist: float = atom_a.global_position.distance_to(atom_b.global_position)
	
	# 距离大于阈值，无隧穿
	if dist > TUNNELING_THRESHOLD:
		return 0.0
	
	# WKB近似: T = exp(-2 * κ * L)
	# κ = sqrt(2m(V-E))/ℏ
	# L = 势垒宽度 ≈ 原子间距
	var mass_kg: float = ELECTRON_MASS  # 电子隧穿
	var barrier_j: float = BARRIER_HEIGHT_EV * EV_TO_J
	var energy_j: float = 0.1 * EV_TO_J  # 假设粒子能量0.1eV
	
	var delta_v: float = barrier_j - energy_j
	if delta_v <= 0.0:
		return PROBABILITY_CAP  # E > V, 经典允许区
	
	var kappa: float = sqrt(2.0 * mass_kg * delta_v) / HBAR
	# L转换为米 (Godot单位≈Å)
	var L_meters: float = dist * 1e-10
	var exponent: float = -2.0 * kappa * L_meters
	
	# 限制指数避免溢出
	exponent = clampf(exponent, -500.0, 0.0)
	var probability: float = exp(exponent)
	
	# 距离越近概率越高，但永远<1
	probability = clampf(probability, 0.0, PROBABILITY_CAP)
	
	return probability

# 检测放置新原子后是否触发隧穿事件
func check_tunneling_on_placement(new_atom: Node3D, nearby_atoms: Array) -> Dictionary:
	var current_frame: int = Engine.get_process_frames()
	if current_frame - _last_trigger_frame < COOLDOWN_FRAMES:
		return {"triggered": false, "reason": "cooldown"}
	
	if nearby_atoms.is_empty():
		return {"triggered": false, "reason": "no_neighbors"}
	
	var best_prob: float = 0.0
	var best_partner: Node3D = null
	
	for partner in nearby_atoms:
		if not is_instance_valid(partner):
			continue
		var prob: float = compute_tunneling_probability(new_atom, partner)
		if prob > best_prob:
			best_prob = prob
			best_partner = partner
	
	if best_partner == null or best_prob < 0.01:
		return {"triggered": false, "reason": "low_probability"}
	
	# 概率检定
	var roll: float = _rng.randf()
	if roll > best_prob:
		# 未通过概率检定，但显示概率云
		_show_probability_cloud(new_atom, best_partner, best_prob)
		return {
			"triggered": false,
			"reason": "roll_failed",
			"probability": best_prob,
		}
	
	# 隧穿成功！
	_last_trigger_frame = current_frame
	
	# 灾难检定
	if best_prob > CATASTROPHE_THRESHOLD and _rng.randf() < 0.3:
		return _trigger_catastrophe(new_atom, best_partner, best_prob)
	
	return _trigger_successful_tunneling(new_atom, best_partner, best_prob)

# 成功隧穿
func _trigger_successful_tunneling(atom_a: Node3D, atom_b: Node3D, prob: float) -> Dictionary:
	var formula_a: String = _get_symbol(atom_a)
	var formula_b: String = _get_symbol(atom_b)
	
	# 选择奇特化合物
	var compound: Dictionary = _select_exotic_compound(formula_a, formula_b)
	var bonus: int = compound["bonus"]
	
	# 奖励核心
	GameState.gain_cores(bonus)
	
	# 视觉特效
	if _float_text != null:
		var mid_pos: Vector3 = (atom_a.global_position + atom_b.global_position) / 2.0
		_float_text.show_float_text(
			mid_pos + Vector3(0, 1.5, 0),
			"⚛ 量子隧穿! %s (+%d核心)" % [compound["formula"], bonus],
			compound["color"],
			3.5
		)
		_float_text.show_float_text(
			mid_pos + Vector3(0, 2.0, 0),
			"概率: %.1f%%" % (prob * 100.0),
			Color(0.7, 0.9, 1.0),
			2.5
		)
	
	# 粒子效果
	_spawn_quantum_burst(atom_a.global_position, atom_b.global_position, compound["color"])
	
	_tunneling_history.append({
		"formula": compound["formula"],
		"probability": prob,
		"bonus": bonus,
	})
	
	exotic_compound_formed.emit(compound["formula"], bonus)
	tunneling_event_triggered.emit(atom_a, atom_b, prob, "success")
	
	return {
		"triggered": true,
		"outcome": "exotic_compound",
		"formula": compound["formula"],
		"bonus": bonus,
		"probability": prob,
	}

# 隧穿灾难 (概率过高时原子被弹射)
func _trigger_catastrophe(atom: Node3D, partner: Node3D, prob: float) -> Dictionary:
	var catastrophe_types: Array = [
		{"reason": "原子弹射", "damage": 5},
		{"reason": "量子退相干", "damage": 3},
		{"reason": "真空击穿", "damage": 7},
	]
	var cat: Dictionary = catastrophe_types[_rng.randi() % catastrophe_types.size()]
	
	# 扣除核心
	if GameState.has_method("spend_cores"):
		GameState.spend_cores(cat["damage"])
	
	if _float_text != null:
		_float_text.show_float_text(
			atom.global_position + Vector3(0, 1.5, 0),
			"⚠ 量子灾难: %s! -%d核心" % [cat["reason"], cat["damage"]],
			Color(1.0, 0.2, 0.2),
			3.0
		)
	
	# 弹射视觉效果
	_spawn_quantum_burst(atom.global_position, partner.global_position, Color(1.0, 0.3, 0.3))
	
	tunneling_catastrophe.emit(atom, cat["reason"])
	tunneling_event_triggered.emit(atom, partner, prob, "catastrophe")
	
	return {
		"triggered": true,
		"outcome": "catastrophe",
		"reason": cat["reason"],
		"damage": cat["damage"],
		"probability": prob,
	}

# 选择匹配的奇特化合物
func _select_exotic_compound(element_a: String, element_b: String) -> Dictionary:
	# 尝试精确匹配
	for compound in EXOTIC_COMPOUNDS:
		var formula: String = compound["formula"]
		if formula.find(element_a) >= 0 and formula.find(element_b) >= 0:
			return compound
	
	# 通用匹配: 生成自定义化合物
	var formula: String = "%s•%s" % [element_a, element_b]
	return {
		"formula": formula,
		"name": "量子隧穿键",
		"bonus": 5 + _rng.randi() % 10,
		"color": Color(0.6, 0.8, 1.0),
		"stability": 0.6,
	}

# 显示量子概率云
func _show_probability_cloud(atom_a: Node3D, atom_b: Node3D, prob: float) -> void:
	if _canvas == null or not _canvas.is_inside_tree():
		return
	if _float_text != null:
		var mid_pos: Vector3 = (atom_a.global_position + atom_b.global_position) / 2.0
		_float_text.show_float_text(
			mid_pos + Vector3(0, 0.8, 0),
			"量子概率: %.1f%%" % (prob * 100.0),
			Color(0.5, 0.7, 1.0, 0.7),
			1.5
		)

# 量子爆发粒子效果
func _spawn_quantum_burst(pos_a: Vector3, pos_b: Vector3, color: Color) -> void:
	if _canvas == null or not _canvas.is_inside_tree():
		return
	
	var mid: Vector3 = (pos_a + pos_b) / 2.0
	var count: int = 12
	for i in range(count):
		var p := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.05
		sphere.height = 0.1
		p.mesh = sphere
		
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 3.0
		p.material_override = mat
		
		p.position = mid
		_canvas.add_child(p)
		
		var angle: float = (float(i) / float(count)) * TAU
		var dir := Vector3(cos(angle), randf() * 0.5 + 0.3, sin(angle)).normalized()
		var tween := _canvas.get_tree().create_tween()
		tween.tween_property(p, "position", mid + dir * 2.5, 0.8)
		tween.parallel().tween_property(p, "scale", Vector3.ZERO, 0.8)
		tween.tween_callback(func():
			if is_instance_valid(p):
				p.queue_free()
		)

# 获取附近原子
func _get_nearby_atoms(atom: Node3D, radius: float = TUNNELING_THRESHOLD) -> Array:
	var result: Array = []
	if _atom_mgr == null or not _atom_mgr.has_method("get_atoms"):
		return result
	for other in _atom_mgr.get_atoms():
		if other == atom or not is_instance_valid(other):
			continue
		var dist: float = atom.global_position.distance_to(other.global_position)
		if dist <= radius:
			result.append(other)
	return result

# 预测放置位置的隧穿概率 (给放置引导系统用)
func predict_tunneling_at(pos: Vector3, element: String) -> Dictionary:
	if _atom_mgr == null or not _atom_mgr.has_method("get_atoms"):
		return {"probability": 0.0, "risk": "none"}
	
	var max_prob: float = 0.0
	var partner_count: int = 0
	
	for other in _atom_mgr.get_atoms():
		if not is_instance_valid(other):
			continue
		var dist: float = pos.distance_to(other.global_position)
		if dist <= TUNNELING_THRESHOLD:
			partner_count += 1
			# 简化概率计算
			var kappa: float = sqrt(2.0 * ELECTRON_MASS * (BARRIER_HEIGHT_EV - 0.1) * EV_TO_J) / HBAR
			var L_m: float = dist * 1e-10
			var prob: float = exp(-2.0 * kappa * L_m)
			max_prob = maxf(max_prob, prob)
	
	var risk: String = "none"
	if max_prob > CATASTROPHE_THRESHOLD:
		risk = "high"
	elif max_prob > 0.3:
		risk = "medium"
	elif max_prob > 0.01:
		risk = "low"
	
	return {
		"probability": clampf(max_prob, 0.0, PROBABILITY_CAP),
		"risk": risk,
		"partner_count": partner_count,
	}

func get_tunneling_history() -> Array:
	return _tunneling_history.duplicate()

func get_tunneling_count() -> int:
	return _tunneling_history.size()

func on_level_reset() -> void:
	_tunneling_history.clear()
	_last_trigger_frame = -COOLDOWN_FRAMES
	_probability_clouds.clear()

func _get_symbol(atom: Node3D) -> String:
	if atom == null:
		return ""
	var sym: Variant = atom.get("element_symbol")
	if sym == null:
		return ""
	return str(sym)
