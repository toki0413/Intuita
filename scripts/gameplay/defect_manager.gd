# defect_manager.gd
# 缺陷工程 - 有意识地引入点缺陷（空位/填隙/置换）
# 缺陷结构无法通过免费验证层，强制玩家投资核心走付费层

extends RefCounted

signal defect_created(defect_type: String, position: Vector3, element: String)
signal defect_removed(defect_id: String)
signal budget_changed(remaining: int, total: int)

const DEFECT_TYPES: Dictionary = {
	"vacancy": {
		"name": "空位缺陷",
		"cost": 1,
		"color": Color(0.3, 0.3, 0.3, 0.6),
		"conservation_row": 0,  # 质量
		"desc": "移除原子，降低占据率，开启扩散通道",
	},
	"interstitial": {
		"name": "填隙缺陷",
		"cost": 2,
		"color": Color(1.0, 0.6, 0.2),
		"conservation_row": 1,  # 电荷
		"desc": "在非Wyckoff位掺杂原子，偏移目标属性",
	},
	"substitutional": {
		"name": "置换缺陷",
		"cost": 2,
		"color": Color(0.8, 0.4, 1.0),
		"conservation_row": 1,  # 电荷
		"desc": "用不同元素替换，融合亲和度加成",
	},
}

var _canvas: Node3D = null
var _atom_mgr = null
var _float_text = null

var _defect_budget: int = 3
var _max_budget: int = 3
var _defects: Dictionary = {}  # id -> {type, atom, position, element}

func _init(canvas: Node3D, atom_mgr, float_text) -> void:
	_canvas = canvas
	_atom_mgr = atom_mgr
	_float_text = float_text

func setup_for_level(level_data: Dictionary) -> void:
	var constraints: Dictionary = level_data.get("constraints", {})
	_max_budget = int(constraints.get("defect_budget", 3))
	_defect_budget = _max_budget
	_defects.clear()
	budget_changed.emit(_defect_budget, _max_budget)

# 创建空位缺陷
func create_vacancy(atom: Node3D) -> Dictionary:
	if atom == null or not is_instance_valid(atom):
		return {"success": false, "reason": "invalid_atom"}
	if _defect_budget < DEFECT_TYPES["vacancy"]["cost"]:
		return {"success": false, "reason": "insufficient_budget"}
	
	var symbol: String = _get_atom_symbol(atom)
	var pos: Vector3 = atom.global_position
	var defect_id: String = "vacancy_%d" % atom.get_instance_id()
	
	# 守恒扰动：质量行 -
	var row: int = DEFECT_TYPES["vacancy"]["conservation_row"]
	if ConservationEngine != null:
		ConservationEngine.apply_perturbation(row, row, -0.3, "defect_vacancy")
	
	# 视觉：移除原子网格，留暗色线框
	var wireframe := _create_vacancy_wireframe(pos)
	
	# 移除原子
	if _atom_mgr != null and _atom_mgr.has_method("delete_atom"):
		_atom_mgr.delete_atom(atom)
	elif atom.get_parent() != null:
		atom.get_parent().remove_child(atom)
		atom.queue_free()
	
	_defects[defect_id] = {
		"type": "vacancy",
		"position": pos,
		"element": symbol,
		"node": wireframe,
	}
	_defect_budget -= DEFECT_TYPES["vacancy"]["cost"]
	
	# 反馈
	if _float_text != null:
		_float_text.show_float_text(pos + Vector3(0, 0.8, 0), "空位缺陷", Color(0.5, 0.5, 0.5), 2.0)
	if SoundManager != null:
		SoundManager.play(SoundManager.SoundType.CONSERVATION_WARN)
	
	defect_created.emit("vacancy", pos, symbol)
	budget_changed.emit(_defect_budget, _max_budget)
	
	if GameLogger != null:
		GameLogger.info("Defect", "[缺陷] 创建空位 @ %s, 剩余预算: %d" % [pos, _defect_budget])
	
	return {"success": true, "defect_id": defect_id, "remaining_budget": _defect_budget}

# 创建填隙缺陷
func create_interstitial(pos: Vector3, element: String) -> Dictionary:
	if _defect_budget < DEFECT_TYPES["interstitial"]["cost"]:
		return {"success": false, "reason": "insufficient_budget"}
	
	var defect_id: String = "interstitial_%d_%d" % [Time.get_ticks_msec(), _defects.size()]
	
	# 守恒扰动：电荷行 +
	var row: int = DEFECT_TYPES["interstitial"]["conservation_row"]
	if ConservationEngine != null:
		ConservationEngine.apply_perturbation(row, row, 0.4, "defect_interstitial")
	
	# 视觉：在非Wyckoff位创建原子
	var atom := _create_defect_atom(pos, element, DEFECT_TYPES["interstitial"]["color"])
	
	_defects[defect_id] = {
		"type": "interstitial",
		"position": pos,
		"element": element,
		"node": atom,
	}
	_defect_budget -= DEFECT_TYPES["interstitial"]["cost"]
	
	# 反馈
	if _float_text != null:
		_float_text.show_float_text(pos + Vector3(0, 0.8, 0), "填隙: %s" % element, DEFECT_TYPES["interstitial"]["color"], 2.0)
	if SoundManager != null:
		SoundManager.play(SoundManager.SoundType.ATOM_PLACE)

	defect_created.emit("interstitial", pos, element)
	budget_changed.emit(_defect_budget, _max_budget)
	
	return {"success": true, "defect_id": defect_id, "remaining_budget": _defect_budget}

# 创建置换缺陷
func create_substitution(atom: Node3D, new_element: String) -> Dictionary:
	if atom == null or not is_instance_valid(atom):
		return {"success": false, "reason": "invalid_atom"}
	if _defect_budget < DEFECT_TYPES["substitutional"]["cost"]:
		return {"success": false, "reason": "insufficient_budget"}
	
	var old_symbol: String = _get_atom_symbol(atom)
	var pos: Vector3 = atom.global_position
	var defect_id: String = "subst_%d" % atom.get_instance_id()
	
	# 守恒扰动：电荷行 +/-（取决于价态差）
	var row: int = DEFECT_TYPES["substitutional"]["conservation_row"]
	var delta: float = _valence_delta(old_symbol, new_element)
	if ConservationEngine != null:
		ConservationEngine.apply_perturbation(row, row, delta, "defect_substitution")
	
	# 替换元素
	atom.set("element_symbol", new_element)
	_update_atom_visual(atom, new_element, DEFECT_TYPES["substitutional"]["color"])
	
	_defects[defect_id] = {
		"type": "substitutional",
		"position": pos,
		"element": new_element,
		"old_element": old_symbol,
		"node": atom,
	}
	_defect_budget -= DEFECT_TYPES["substitutional"]["cost"]
	
	# 反馈
	if _float_text != null:
		_float_text.show_float_text(pos + Vector3(0, 0.8, 0), "%s→%s" % [old_symbol, new_element], DEFECT_TYPES["substitutional"]["color"], 2.0)
	if SoundManager != null:
		SoundManager.play(SoundManager.SoundType.ATOM_PLACE)
	
	defect_created.emit("substitutional", pos, new_element)
	budget_changed.emit(_defect_budget, _max_budget)
	
	return {"success": true, "defect_id": defect_id, "remaining_budget": _defect_budget}

# 检查是否有缺陷（影响验证层）
func has_defects() -> bool:
	return _defects.size() > 0

func get_defect_count() -> int:
	return _defects.size()

func get_remaining_budget() -> int:
	return _defect_budget

func get_max_budget() -> int:
	return _max_budget

# 移除缺陷
func remove_defect(defect_id: String) -> bool:
	if not _defects.has(defect_id):
		return false
	
	var defect: Dictionary = _defects[defect_id]
	var defect_type: String = defect["type"]
	
	# 恢复预算
	_defect_budget += DEFECT_TYPES[defect_type]["cost"]
	_defect_budget = min(_defect_budget, _max_budget)
	
	# 清理视觉
	var node = defect.get("node", null)
	if node != null and is_instance_valid(node):
		node.queue_free()
	
	# 反向守恒扰动
	var row: int = DEFECT_TYPES[defect_type]["conservation_row"]
	if ConservationEngine != null:
		ConservationEngine.apply_perturbation(row, row, -0.2, "defect_removed")
	
	_defects.erase(defect_id)
	defect_removed.emit(defect_id)
	budget_changed.emit(_defect_budget, _max_budget)
	
	return true

func on_level_reset() -> void:
	for defect_id in _defects.keys():
		var node = _defects[defect_id].get("node", null)
		if node != null and is_instance_valid(node):
			node.queue_free()
	_defects.clear()
	_defect_budget = _max_budget
	budget_changed.emit(_defect_budget, _max_budget)

# ===== 内部方法 =====

func _create_vacancy_wireframe(pos: Vector3) -> Node3D:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	mesh.mesh = sphere
	
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.2, 0.2, 0.2, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat
	
	mesh.position = pos
	if _canvas != null:
		_canvas.add_child(mesh)
	
	# 吸入动画
	if _canvas != null:
		var tween := _canvas.get_tree().create_tween()
		var orig_scale := Vector3.ONE
		mesh.scale = Vector3(1.5, 1.5, 1.5)
		tween.tween_property(mesh, "scale", orig_scale, 0.4)
	
	return mesh

func _create_defect_atom(pos: Vector3, element: String, tint: Color) -> Node3D:
	var atom := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.25
	sphere.height = 0.5
	atom.mesh = sphere
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.emission_enabled = true
	mat.emission = tint * 0.5
	mat.emission_energy_multiplier = 1.2
	atom.material_override = mat
	
	atom.position = pos
	atom.set("element_symbol", element)
	
	if _canvas != null:
		_canvas.add_child(atom)
	
	# 脉冲动画
	if _canvas != null:
		var tween := _canvas.get_tree().create_tween()
		atom.scale = Vector3.ZERO
		tween.tween_property(atom, "scale", Vector3.ONE, 0.3)
	
	return atom

func _update_atom_visual(atom: Node3D, element: String, tint: Color) -> void:
	atom.set("element_symbol", element)
	if atom is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = tint
		mat.emission_enabled = true
		mat.emission = tint * 0.5
		atom.material_override = mat

func _valence_delta(old_elem: String, new_elem: String) -> float:
	# 简化的价态差计算
	var valences: Dictionary = {
		"H": 1, "Li": 1, "Na": 1, "Fe": 2, "Cu": 2,
		"Be": 2, "Mg": 2, "Ca": 2, "Zn": 2,
		"B": 3, "Al": 3,
		"C": 4, "Si": 4,
		"N": -3, "P": -3,
		"O": -2, "S": -2,
		"F": -1, "Cl": -1,
	}
	var old_v: int = valences.get(old_elem, 0)
	var new_v: int = valences.get(new_elem, 0)
	return float(new_v - old_v) * 0.15

func _get_atom_symbol(atom: Node3D) -> String:
	if atom == null:
		return ""
	var sym = atom.get("element_symbol") if atom.get("element_symbol") != null else ""
	return sym
