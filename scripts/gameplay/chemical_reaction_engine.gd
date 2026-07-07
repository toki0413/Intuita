# chemical_reaction_engine.gd
# 化学反应引擎 - 相邻原子自动反应，释放能量
# Na + Cl → NaCl 离子键 + 能量释放

class_name ChemicalReactionEngine
extends RefCounted

signal reaction_occurred(reaction_name: String, energy_released: float, bonus_cores: int)
signal bond_energy_released(amount: float, position: Vector3)

var _canvas: Node3D = null
var _atom_mgr = null
var _float_text: FloatingTextSystem = null

# 反应数据库: [元素A, 元素B] -> {反应名, 键类型, 能量释放, 距离阈值, 奖励核心}
const REACTIONS: Dictionary = {
	"Na+Cl": {
		"name": "NaCl 离子键",
		"bond_type": 1,  # 离子键
		"energy": 3.5,
		"max_dist": 2.8,
		"bonus_cores": 2,
		"color": Color(0.9, 0.9, 1.0),
	},
	"Na+F": {
		"name": "NaF 离子键",
		"bond_type": 1,
		"energy": 4.0,
		"max_dist": 2.3,
		"bonus_cores": 2,
		"color": Color(0.8, 1.0, 0.9),
	},
	"Li+Cl": {
		"name": "LiCl 离子键",
		"bond_type": 1,
		"energy": 3.0,
		"max_dist": 2.5,
		"bonus_cores": 1,
		"color": Color(0.9, 0.9, 1.0),
	},
	"H+O": {
		"name": "O-H 共价键",
		"bond_type": 0,  # 共价键
		"energy": 4.8,
		"max_dist": 1.0,
		"bonus_cores": 1,
		"color": Color(0.7, 0.9, 1.0),
	},
	"H+H": {
		"name": "H-H 共价键",
		"bond_type": 0,
		"energy": 4.5,
		"max_dist": 0.8,
		"bonus_cores": 1,
		"color": Color(0.7, 0.9, 1.0),
	},
	"C+H": {
		"name": "C-H 共价键",
		"bond_type": 0,
		"energy": 4.3,
		"max_dist": 1.1,
		"bonus_cores": 1,
		"color": Color(0.7, 0.9, 1.0),
	},
	"C+O": {
		"name": "C=O 双键",
		"bond_type": 2,  # 双键
		"energy": 7.5,
		"max_dist": 1.2,
		"bonus_cores": 3,
		"color": Color(1.0, 0.7, 0.3),
	},
	"Fe+O": {
		"name": "Fe-O 配位键",
		"bond_type": 3,  # 配位键
		"energy": 3.0,
		"max_dist": 2.0,
		"bonus_cores": 2,
		"color": Color(1.0, 0.5, 0.2),
	},
}

# 已发生的反应（避免重复触发）
var _reacted_pairs: Array = []  # [{a_id, b_id}]

func _init(canvas: Node3D, atom_mgr, float_text: FloatingTextSystem) -> void:
	_canvas = canvas
	_atom_mgr = atom_mgr
	_float_text = float_text

func on_atom_placed(atom: Node3D) -> void:
	if atom == null or not is_instance_valid(atom):
		return
	
	var symbol: String = _get_atom_symbol(atom)
	if symbol == "":
		return
	
	var atom_pos: Vector3 = atom.global_position
	var atoms: Array = _atom_mgr.get_atoms() if _atom_mgr.has_method("get_atoms") else []
	
	for other in atoms:
		if other == atom or not is_instance_valid(other):
			continue
		var other_sym: String = _get_atom_symbol(other)
		if other_sym == "":
			continue
		
		var pair_key: String = _make_pair_key(symbol, other_sym)
		if not REACTIONS.has(pair_key):
			continue
		
		var reaction: Dictionary = REACTIONS[pair_key]
		var dist: float = atom_pos.distance_to(other.global_position)
		var max_dist: float = reaction["max_dist"]
		
		if dist > max_dist:
			continue
		
		# 检查是否已经反应过
		var a_id: int = atom.get_instance_id()
		var b_id: int = other.get_instance_id()
		if _already_reacted(a_id, b_id):
			continue
		
		# 触发反应!
		_trigger_reaction(atom, other, reaction)

func _trigger_reaction(atom_a: Node3D, atom_b: Node3D, reaction: Dictionary) -> void:
	var a_id: int = atom_a.get_instance_id()
	var b_id: int = atom_b.get_instance_id()
	_reacted_pairs.append({"a": a_id, "b": b_id})
	
	var name: String = reaction["name"]
	var energy: float = reaction["energy"]
	var bonus: int = reaction["bonus_cores"]
	var color: Color = reaction["color"]
	var mid_pos: Vector3 = (atom_a.global_position + atom_b.global_position) * 0.5
	
	# 1. 创建键（如果 atom_mgr 支持）
	if _atom_mgr != null and _atom_mgr.has_method("create_bond"):
		_atom_mgr.create_bond(atom_a, atom_b, reaction["bond_type"])
	
	# 2. 释放能量 = 降低守恒偏离（通过日志反馈）
	var stability_boost: float = energy * 0.02
	if GameLogger != null:
		GameLogger.info("Chemistry", "[化学反应] %s 释放 %.2f eV, 稳定性+%.2f" % [name, energy, stability_boost])
	
	# 3. 奖励核心
	if LevelManager != null and bonus > 0:
		GameState.gain_cores(bonus)
	
	# 4. 视觉反馈
	if _float_text != null:
		_float_text.show_float_text(
			mid_pos + Vector3(0, 0.5, 0),
			"%s! -%.1f eV" % [name, energy],
			color,
			2.5
		)
		_float_text.show_float_text(
			mid_pos + Vector3(0, 0.8, 0),
			"+%d 核心" % bonus,
			Color(1.0, 0.85, 0.0),
			1.5
		)
	
	# 5. 反应粒子效果
	_spawn_reaction_particles(mid_pos, color)
	
	# 6. 音效
	if SoundManager != null:
		SoundManager.play(SoundManager.SoundType.PROOF_COMPLETE)
	
	reaction_occurred.emit(name, energy, bonus)
	bond_energy_released.emit(energy, mid_pos)

func _spawn_reaction_particles(pos: Vector3, color: Color) -> void:
	if _canvas == null or not _canvas.is_inside_tree():
		return
	
	# 创建简单的粒子爆发
	for i in range(8):
		var p := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.05
		sphere.height = 0.1
		p.mesh = sphere
		
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 2.0
		p.material_override = mat
		
		p.position = pos
		_canvas.add_child(p)
		
		# 随机方向飞散
		var dir := Vector3(randf() - 0.5, randf() * 0.5 + 0.3, randf() - 0.5).normalized()
		var tween := _canvas.get_tree().create_tween()
		tween.tween_property(p, "position", pos + dir * 1.5, 0.8)
		tween.parallel().tween_property(p, "scale", Vector3.ZERO, 0.8)
		tween.tween_callback(func():
			if is_instance_valid(p):
				p.queue_free()
		)

func _get_atom_symbol(atom: Node3D) -> String:
	if atom == null:
		return ""
	if atom.has_method("get"):
		return atom.get("element_symbol") if atom.get("element_symbol") != null else ""
	return ""

func _make_pair_key(a: String, b: String) -> String:
	# 排序确保 A+B 和 B+A 是同一个键
	if a < b:
		return a + "+" + b
	return b + "+" + a

func _already_reacted(a_id: int, b_id: int) -> bool:
	for pair in _reacted_pairs:
		if (pair["a"] == a_id and pair["b"] == b_id) or (pair["a"] == b_id and pair["b"] == a_id):
			return true
	return false

func on_level_reset() -> void:
	_reacted_pairs.clear()
