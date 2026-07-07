# diagnostic_highlighter.gd
# 错误诊断高亮 - 放置错误时高亮显示问题原子，给出修复建议

class_name DiagnosticHighlighter
extends RefCounted

var _canvas: Node3D = null
var _atom_mgr = null
var _float_text: FloatingTextSystem = null

var _highlighted_atoms: Array = []
var _diagnostic_labels: Array = []
var _is_diagnostic_mode: bool = false

func _init(canvas: Node3D, atom_mgr, float_text: FloatingTextSystem) -> void:
	_canvas = canvas
	_atom_mgr = atom_mgr
	_float_text = float_text

func trigger_diagnostic(failed_property: String, target_deviation: float) -> void:
	# 清除之前的高亮
	_clear_highlights()
	_is_diagnostic_mode = true
	
	if _atom_mgr == null:
		return
	
	var atoms: Array = _atom_mgr.get_atoms() if _atom_mgr.has_method("get_atoms") else []
	if atoms.size() == 0:
		return
	
	# 找出对偏离贡献最大的原子
	var worst_atoms: Array = _find_worst_contributors(atoms, failed_property)
	
	for i in range(mini(worst_atoms.size(), 3)):
		var atom: Node3D = worst_atoms[i]
		if not is_instance_valid(atom):
			continue
		_highlight_atom(atom, i == 0)
		
		# 显示修复建议浮字
		if _float_text != null:
			var suggestion: String = _generate_suggestion(atom, failed_property)
			_float_text.show_float_text(
				atom.global_position + Vector3(0, 1.0, 0),
				suggestion,
				Color(1.0, 0.7, 0.2),
				3.0
			)

func _find_worst_contributors(atoms: Array, property: String) -> Array:
	# 简单启发式: 最近放置的原子更可能是问题来源
	# 实际实现中应该根据原子的元素属性和位置计算贡献
	var scored: Array = []
	for atom in atoms:
		if not is_instance_valid(atom):
			continue
		var score: float = 0.0
		# 高Z元素对质量守恒影响更大
		if atom.has_method("get"):
			var symbol: String = atom.get("element_symbol") if atom.has_method("get") else ""
			score = _element_impact_score(symbol)
		scored.append({"atom": atom, "score": score})
	
	scored.sort_custom(func(a, b): return a["score"] > b["score"])
	var result: Array = []
	for item in scored:
		result.append(item["atom"])
	return result

func _element_impact_score(symbol: String) -> float:
	# 元素对守恒矩阵的影响评分（简单启发式）
	var heavy_elements: Dictionary = {"Fe": 3.0, "Na": 2.0, "Cl": 2.0, "Li": 1.5, "O": 1.0, "F": 1.0, "H": 0.5}
	return heavy_elements.get(symbol, 1.0)

func _generate_suggestion(atom: Node3D, property: String) -> String:
	var symbol: String = ""
	if atom.has_method("get") and atom.has_method("has_method"):
		if atom.has_method("get"):
			symbol = atom.get("element_symbol") if atom.has_method("get") else "?"
	
	var suggestions: Dictionary = {
		"mass": ["尝试更轻的元素", "检查原子数量", "减少重元素"],
		"charge": ["平衡正负电荷", "尝试中性元素", "检查离子状态"],
		"spin": ["调整自旋方向", "尝试配对电子", "检查磁性元素"],
		"flavor": ["检查味量子数", "尝试不同夸克组合"],
	}
	var list: Array = suggestions.get(property, ["检查原子配置"])
	return list[randi() % list.size()]

func _highlight_atom(atom: Node3D, is_primary: bool) -> void:
	_highlighted_atoms.append(atom)
	
	# 创建高亮球体
	var highlight: MeshInstance3D = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.6 if is_primary else 0.45
	sphere.height = sphere.radius * 2
	highlight.mesh = sphere
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.2, 0.2, 0.4) if is_primary else Color(1.0, 0.6, 0.2, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	highlight.material_override = mat
	
	highlight.position = atom.global_position
	_canvas.add_child(highlight)
	_diagnostic_labels.append(highlight)
	
	# 脉冲动画
	if _canvas.get_tree() != null:
		var tween := _canvas.get_tree().create_tween().set_loops(3)
		tween.tween_property(highlight, "scale", Vector3.ONE * 1.3, 0.5)
		tween.tween_property(highlight, "scale", Vector3.ONE, 0.5)

func clear_diagnostic() -> void:
	_clear_highlights()
	_is_diagnostic_mode = false

func _clear_highlights() -> void:
	for label in _diagnostic_labels:
		if is_instance_valid(label):
			label.queue_free()
	_diagnostic_labels.clear()
	_highlighted_atoms.clear()
