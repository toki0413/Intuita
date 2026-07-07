# placement_guide_system.gd
# 智能放置引导 - 解决"玩家不知道怎么放原子"的核心痛点
# 综合分析Wyckoff位置、反应势、催化网络、隧穿概率、共振模
# 为玩家提供多维度放置建议: 最佳位置、预期效果、风险评估
# 视觉: 幽灵原子标记 + 彩色光环 + 浮动说明文本

extends RefCounted

signal guide_updated(suggestions: Array)
signal optimal_placement_found(position: Vector3, reason: String, score: float)
signal danger_placement_warned(position: Vector3, reason: String)

# 引导模式
enum GuideMode {
	WYCKOFF,       # 仅显示Wyckoff位置
	REACTION,      # 反应势分析
	CATALYST,      # 催化网络优化
	TUNNELING,     # 隧穿风险/机会
	COMPREHENSIVE, # 综合分析(默认)
}

# 评分权重
const W_WYCKOFF: float = 0.35       # Wyckoff对称位置权重
const W_REACTION: float = 0.25      # 反应势权重
const W_CATALYST: float = 0.15      # 催化网络权重
const W_TUNNELING: float = 0.15     # 隧穿潜力权重
const W_STRAIN: float = 0.10        # 应变场权重

const MAX_SUGGESTIONS: int = 5       # 最多显示建议数
const SUGGESTION_RADIUS: float = 5.0 # 搜索半径
const MIN_SCORE_THRESHOLD: float = 0.2  # 最低评分阈值

var _canvas: Node3D = null
var _atom_mgr = null
var _float_text = null
var _catalyst_sys = null
var _tunneling_sys = null
var _strain_field = null

var _current_mode: GuideMode = GuideMode.COMPREHENSIVE
var _suggestions: Array = []
var _guide_markers: Array = []  # 视觉标记节点
var _is_active: bool = true

func _init(canvas: Node3D, atom_mgr, float_text) -> void:
	_canvas = canvas
	_atom_mgr = atom_mgr
	_float_text = float_text

func set_subsystems(catalyst_sys, tunneling_sys, strain_field) -> void:
	_catalyst_sys = catalyst_sys
	_tunneling_sys = tunneling_sys
	_strain_field = strain_field

# 计算某个位置的放置评分
func evaluate_placement(pos: Vector3, element: String) -> Dictionary:
	var scores: Dictionary = {
		"wyckoff": 0.0,
		"reaction": 0.0,
		"catalyst": 0.0,
		"tunneling": 0.0,
		"strain": 0.0,
	}
	var reasons: Array = []
	var risks: Array = []
	
	# 1. Wyckoff位置评分: 对称位置得分高
	scores["wyckoff"] = _score_wyckoff(pos, reasons)
	
	# 2. 反应势评分: 附近有可反应的原子得分高
	scores["reaction"] = _score_reaction_potential(pos, element, reasons)
	
	# 3. 催化网络评分: 在催化剂影响范围内得分高
	scores["catalyst"] = _score_catalyst_network(pos, element, reasons)
	
	# 4. 隧穿潜力/风险评分
	scores["tunneling"] = _score_tunneling_potential(pos, element, reasons, risks)
	
	# 5. 应变场评分: 低应变区域更稳定
	scores["strain"] = _score_strain_compatibility(pos, reasons)
	
	# 加权总分
	var total: float = 0.0
	total += scores["wyckoff"] * W_WYCKOFF
	total += scores["reaction"] * W_REACTION
	total += scores["catalyst"] * W_CATALYST
	total += scores["tunneling"] * W_TUNNELING
	total += scores["strain"] * W_STRAIN
	
	var risk_level: String = "safe"
	if risks.size() > 0:
		risk_level = "danger" if scores["tunneling"] < 0.0 else "caution"
	
	return {
		"position": pos,
		"element": element,
		"total_score": clampf(total, 0.0, 1.0),
		"scores": scores,
		"reasons": reasons,
		"risks": risks,
		"risk_level": risk_level,
	}

# Wyckoff位置评分
func _score_wyckoff(pos: Vector3, reasons: Array) -> float:
	if _atom_mgr == null:
		return 0.0
	
	# 检查是否在Wyckoff标记附近
	var wyckoff_markers: Array = []
	if _atom_mgr.has_method("_wyckoff_markers"):
		wyckoff_markers = _atom_mgr._wyckoff_markers
	elif _atom_mgr.has_method("get_wyckoff_markers"):
		wyckoff_markers = _atom_mgr.get_wyckoff_markers()
	
	var best_score: float = 0.0
	for marker in wyckoff_markers:
		if marker == null or not is_instance_valid(marker):
			continue
		var dist: float = pos.distance_to(marker.global_position)
		if dist < 0.3:
			best_score = 1.0
			reasons.append("精确Wyckoff位置")
			break
		elif dist < 0.8:
			var score: float = 1.0 - (dist / 0.8)
			if score > best_score:
				best_score = score
				reasons.append("近Wyckoff位置")
	
	return best_score

# 反应势评分
func _score_reaction_potential(pos: Vector3, element: String, reasons: Array) -> float:
	if _atom_mgr == null or not _atom_mgr.has_method("get_atoms"):
		return 0.0
	
	var score: float = 0.0
	var atoms: Array = _atom_mgr.get_atoms()
	
	for atom in atoms:
		if not is_instance_valid(atom):
			continue
		var dist: float = pos.distance_to(atom.global_position)
		if dist > 0.5 and dist < 3.0:
			var other_elem: String = _get_symbol(atom)
			# 简单反应势判断: 不同元素近距离有反应潜力
			if other_elem != element:
				var potential: float = 1.0 - (dist / 3.0)
				score = maxf(score, potential)
				if potential > 0.7:
					reasons.append("可与%s反应" % other_elem)
			else:
				# 同类元素可以成键
				var bond_potential: float = (1.0 - dist / 3.0) * 0.6
				score = maxf(score, bond_potential)
	
	return clampf(score, 0.0, 1.0)

# 催化网络评分
func _score_catalyst_network(pos: Vector3, element: String, reasons: Array) -> float:
	if _catalyst_sys == null:
		return 0.0
	
	var eval_result: Dictionary = {}
	if _catalyst_sys.has_method("evaluate_reaction"):
		eval_result = _catalyst_sys.evaluate_reaction(pos, element)
		if eval_result.get("catalyzed", false):
			reasons.append("催化加速%.1fx" % eval_result["rate_boost"])
			# 速率提升越高得分越高, 但有上限
			var boost: float = eval_result["rate_boost"]
			return clampf(log(boost + 1.0) / log(100.0), 0.0, 1.0)
	
	return 0.0

# 隧穿潜力评分
func _score_tunneling_potential(pos: Vector3, element: String, reasons: Array, risks: Array) -> float:
	if _tunneling_sys == null:
		return 0.0
	
	var prediction: Dictionary = {}
	if _tunneling_sys.has_method("predict_tunneling_at"):
		prediction = _tunneling_sys.predict_tunneling_at(pos, element)
	
	var prob: float = prediction.get("probability", 0.0)
	var risk: String = prediction.get("risk", "none")
	
	match risk:
		"high":
			risks.append("隧穿灾难风险")
			return -0.5  # 高风险扣分
		"medium":
			reasons.append("量子隧穿机会 (%.0f%%)" % (prob * 100.0))
			return prob * 0.8  # 中等风险有机会分
		"low":
			reasons.append("微弱隧穿效应")
			return prob * 0.3
		_:
			return 0.0

# 应变场兼容性评分
func _score_strain_compatibility(pos: Vector3, reasons: Array) -> float:
	if _strain_field == null:
		return 0.5  # 默认中等
	
	var mag: float = 0.0
	if _strain_field.has_method("get_strain_magnitude"):
		mag = _strain_field.get_strain_magnitude(pos)
	
	# 低应变 → 高分 (更稳定)
	var score: float = 1.0 - clampf(mag / 0.5, 0.0, 1.0)
	if score > 0.8:
		reasons.append("低应变稳定区")
	elif score < 0.3:
		reasons.append("高应变不稳定区")
	
	return score

# 生成放置建议 (扫描周围空间)
func generate_suggestions(center: Vector3, element: String) -> Array:
	var candidates: Array = []
	
	# 从Wyckoff标记中寻找候选
	if _atom_mgr != null:
		var markers: Array = []
		if _atom_mgr.has_method("_wyckoff_markers"):
			markers = _atom_mgr._wyckoff_markers
		elif _atom_mgr.has_method("get_wyckoff_markers"):
			markers = _atom_mgr.get_wyckoff_markers()
		
		for marker in markers:
			if marker == null or not is_instance_valid(marker):
				continue
			# 检查该位置是否已被占用
			if _is_position_occupied(marker.global_position):
				continue
			candidates.append(marker.global_position)
	
	# 在已有原子周围生成候选
	if _atom_mgr != null and _atom_mgr.has_method("get_atoms"):
		for atom in _atom_mgr.get_atoms():
			if not is_instance_valid(atom):
				continue
			# 在成键距离(~1.5Å)处生成候选
			var bond_dist: float = 1.5
			for angle in [0.0, 60.0, 120.0, 180.0, 240.0, 300.0]:
				var rad: float = deg_to_rad(angle)
				var candidate: Vector3 = atom.global_position + Vector3(
					cos(rad) * bond_dist, 0.0, sin(rad) * bond_dist
				)
				if not _is_position_occupied(candidate):
					candidates.append(candidate)
	
	# 催化剂系统建议
	if _catalyst_sys != null and _catalyst_sys.has_method("get_optimal_catalyst_positions"):
		var cat_suggestions: Array = _catalyst_sys.get_optimal_catalyst_positions(
			_atom_mgr.get_atoms() if _atom_mgr.has_method("get_atoms") else []
		)
		for s in cat_suggestions:
			if not _is_position_occupied(s["position"]):
				candidates.append(s["position"])
	
	# 评估每个候选位置
	var scored: Array = []
	for pos in candidates:
		if pos.distance_to(center) > SUGGESTION_RADIUS * 2.0:
			continue
		var evaluation: Dictionary = evaluate_placement(pos, element)
		if evaluation["total_score"] >= MIN_SCORE_THRESHOLD:
			scored.append(evaluation)
	
	# 按评分排序, 取前N个
	scored.sort_custom(func(a, b): return a["total_score"] > b["total_score"])
	_suggestions = scored.slice(0, MAX_SUGGESTIONS)
	
	guide_updated.emit(_suggestions)
	
	# 如果有高评分建议, 发出信号
	if _suggestions.size() > 0:
		var best: Dictionary = _suggestions[0]
		optimal_placement_found.emit(
			best["position"],
			", ".join(best["reasons"]) if best["reasons"].size() > 0 else "综合评分最优",
			best["total_score"]
		)
	
	# 如果有危险位置, 发出警告
	for s in scored:
		if s.get("risk_level") == "danger":
			danger_placement_warned.emit(s["position"], ", ".join(s["risks"]))
			break
	
	return _suggestions

# 检查位置是否已被占用
func _is_position_occupied(pos: Vector3) -> bool:
	if _atom_mgr == null or not _atom_mgr.has_method("get_atoms"):
		return false
	for atom in _atom_mgr.get_atoms():
		if not is_instance_valid(atom):
			continue
		if atom.global_position.distance_to(pos) < 0.5:
			return true
	return false

# 切换引导模式
func set_mode(mode: GuideMode) -> void:
	_current_mode = mode

# 激活/关闭引导
func set_active(active: bool) -> void:
	_is_active = active
	if not active:
		clear_markers()

# 清除视觉标记
func clear_markers() -> void:
	for marker in _guide_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_guide_markers.clear()

# 获取当前建议
func get_suggestions() -> Array:
	return _suggestions

# 获取最佳建议
func get_best_suggestion() -> Dictionary:
	if _suggestions.is_empty():
		return {}
	return _suggestions[0]

# 获取建议摘要文本 (给HUD显示)
func get_guide_summary() -> String:
	if _suggestions.is_empty():
		return "暂无放置建议"
	
	var best: Dictionary = _suggestions[0]
	var pos: Vector3 = best["position"]
	var score: float = best["total_score"]
	var reasons: Array = best.get("reasons", [])
	
	var risk_text: String = ""
	if best.get("risk_level") == "danger":
		risk_text = " [⚠危险]"
	elif best.get("risk_level") == "caution":
		risk_text = " [注意]"
	
	var reason_text: String = reasons[0] if reasons.size() > 0 else "综合最优"
	
	return "推荐放置: %s (%.0f%%) %s%s" % [
		reason_text, score * 100.0, risk_text,
		" | 共%d个建议" % _suggestions.size() if _suggestions.size() > 1 else ""
	]

func on_level_reset() -> void:
	_suggestions.clear()
	clear_markers()


func _get_symbol(atom: Node3D) -> String:
	if atom == null:
		return ""
	var sym: Variant = atom.get("element_symbol")
	if sym == null:
		return ""
	return str(sym)
