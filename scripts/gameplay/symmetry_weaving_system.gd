# symmetry_weaving_system.gd
# 对称编织 - 利用晶体对称操作在轨道上批量生成等价原子
# 镜面/旋转/滑移/螺旋操作放大守恒扰动，连续编织触发连击

extends RefCounted

signal weave_completed(operation_name: String, orbit_size: int, amplified_deviation: float)
signal weave_failed(reason: String)

var _canvas: Node3D = null
var _atom_mgr = null
var _float_text = null
var _crystal_cell: Node3D = null

# 可用的对称操作
const WEAVE_OPS: Dictionary = {
	"mirror": {
		"name": "镜面编织",
		"mult": 2,
		"color": Color(0.6, 0.9, 1.0),
		"desc": "沿镜面生成对称原子",
	},
	"rotate_2": {
		"name": "二重旋转编织",
		"mult": 2,
		"color": Color(0.9, 0.7, 1.0),
		"desc": "180度旋转生成等效位置",
	},
	"rotate_3": {
		"name": "三重旋转编织",
		"mult": 3,
		"color": Color(1.0, 0.8, 0.5),
		"desc": "120度旋转生成等效位置",
	},
	"rotate_4": {
		"name": "四重旋转编织",
		"mult": 4,
		"color": Color(1.0, 0.6, 0.3),
		"desc": "90度旋转生成等效位置",
	},
	"rotate_6": {
		"name": "六重旋转编织",
		"mult": 6,
		"color": Color(1.0, 0.4, 0.2),
		"desc": "60度旋转生成等效位置",
	},
	"glide": {
		"name": "滑移面编织",
		"mult": 2,
		"color": Color(0.5, 1.0, 0.7),
		"desc": "镜面+平移生成等效位置",
	},
	"screw_3": {
		"name": "三重螺旋编织",
		"mult": 3,
		"color": Color(0.8, 0.5, 1.0),
		"desc": "旋转+平移生成螺旋排列",
	},
}

# 连击追踪
var _weave_chain: int = 0
var _last_weave_time: float = 0.0
const CHAIN_WINDOW: float = 10.0  # 连击窗口10秒

func _init(canvas: Node3D, atom_mgr, float_text) -> void:
	_canvas = canvas
	_atom_mgr = atom_mgr
	_float_text = float_text
	_crystal_cell = canvas.get_node_or_null("CrystalCell")

# 执行对称编织操作
func weave(seed_atom: Node3D, op_id: String) -> Dictionary:
	if seed_atom == null or not is_instance_valid(seed_atom):
		return {"success": false, "reason": "invalid_seed"}
	
	if not WEAVE_OPS.has(op_id):
		return {"success": false, "reason": "unknown_operation"}
	
	var op: Dictionary = WEAVE_OPS[op_id]
	var mult: int = op["mult"]
	var symbol: String = _get_atom_symbol(seed_atom)
	if symbol == "":
		return {"success": false, "reason": "no_element"}
	
	# 计算等效位置
	var equiv_positions: Array = _compute_equivalent_positions(seed_atom, op_id, mult)
	if equiv_positions.is_empty():
		return {"success": false, "reason": "no_equivalent_positions"}
	
	# 守恒扰动放大
	var seed_dev: float = _get_atom_deviation(seed_atom)
	var amplified: float = seed_dev * float(mult)
	
	# 施加到守恒矩阵
	var row: int = _element_to_row(symbol)
	if ConservationEngine != null:
		ConservationEngine.apply_perturbation(row, row, amplified * 0.1, "weave_%s" % op_id)
	
	# 生成幽灵原子并飞入
	var spawned: int = 0
	for pos in equiv_positions:
		var ghost: Node3D = _spawn_ghost_atom(pos, symbol, op["color"])
		if ghost != null:
			spawned += 1
	
	# 连击逻辑
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_weave_time < CHAIN_WINDOW:
		_weave_chain += 1
	else:
		_weave_chain = 1
	_last_weave_time = now
	
	# 连击奖励
	if _weave_chain >= 3:
		var bonus: int = _weave_chain / 3
		if LevelManager != null:
			GameState.gain_cores(bonus)
		if _float_text != null:
			_float_text.show_float_text(
				seed_atom.global_position + Vector3(0, 1.5, 0),
				"编织连击 x%d! +%d核心" % [_weave_chain, bonus],
				Color(1.0, 0.85, 0.0),
				2.0
			)
	
	# 视觉反馈
	if _float_text != null:
		var mid_pos: Vector3 = seed_atom.global_position + Vector3(0, 1.0, 0)
		_float_text.show_float_text(
			mid_pos,
			"%s (x%d)" % [op["name"], mult],
			op["color"],
			2.5
		)
		if amplified > 0.3:
			_float_text.show_float_text(
				mid_pos + Vector3(0, 0.4, 0),
				"扰动放大: +%.2f" % amplified,
				Color(1.0, 0.4, 0.3),
				2.0
			)
	
	# 音效
	if SoundManager != null:
		SoundManager.play(SoundManager.SoundType.PROOF_COMPLETE)
	
	# 粒子效果
	_spawn_weave_particles(seed_atom.global_position, op["color"], mult)
	
	weave_completed.emit(op["name"], spawned, amplified)
	return {
		"success": true,
		"orbit_size": spawned,
		"amplified_deviation": amplified,
		"chain": _weave_chain,
	}

# 计算等效位置
func _compute_equivalent_positions(seed: Node3D, op_id: String, mult: int) -> Array:
	var positions: Array = []
	var seed_pos: Vector3 = seed.global_position
	
	if _crystal_cell == null or not _crystal_cell.has_method("cartesian_to_fractional"):
		# 退化模式：用简单的空间变换
		return _simple_symmetry_positions(seed_pos, op_id, mult)
	
	# 转换到分数坐标
	var frac: Vector3 = _crystal_cell.cartesian_to_fractional(seed_pos)
	
	match op_id:
		"mirror":
			# 镜面：x,y,z -> -x,y,z (近似)
			positions.append(_crystal_cell.fractional_to_cartesian(Vector3(-frac.x, frac.y, frac.z)))
		"rotate_2":
			# 二重：x,y,z -> -x,-y,z
			positions.append(_crystal_cell.fractional_to_cartesian(Vector3(-frac.x, -frac.y, frac.z)))
		"rotate_3":
			# 三重：绕c轴旋转120度
			var a1: Vector3 = _rotate_in_plane(frac, 120.0)
			var a2: Vector3 = _rotate_in_plane(frac, 240.0)
			positions.append(_crystal_cell.fractional_to_cartesian(a1))
			positions.append(_crystal_cell.fractional_to_cartesian(a2))
		"rotate_4":
			# 四重：绕c轴旋转90,180,270度
			positions.append(_crystal_cell.fractional_to_cartesian(_rotate_in_plane(frac, 90.0)))
			positions.append(_crystal_cell.fractional_to_cartesian(_rotate_in_plane(frac, 180.0)))
			positions.append(_crystal_cell.fractional_to_cartesian(_rotate_in_plane(frac, 270.0)))
		"rotate_6":
			# 六重：绕c轴旋转60,120,180,240,300度
			for i in range(1, 6):
				positions.append(_crystal_cell.fractional_to_cartesian(_rotate_in_plane(frac, 60.0 * i)))
		"glide":
			# 滑移面：镜面+半平移
			positions.append(_crystal_cell.fractional_to_cartesian(Vector3(-frac.x + 0.5, frac.y, frac.z)))
		"screw_3":
			# 三重螺旋：旋转120度+c/3平移
			positions.append(_crystal_cell.fractional_to_cartesian(Vector3(
				_cos_proj(frac, 120.0), _sin_proj(frac, 120.0), frac.z + 1.0/3.0)))
			positions.append(_crystal_cell.fractional_to_cartesian(Vector3(
				_cos_proj(frac, 240.0), _sin_proj(frac, 240.0), frac.z + 2.0/3.0)))
	
	# 过滤掉与已有原子过近的位置
	var atoms: Array = []
	if _atom_mgr != null and _atom_mgr.has_method("get_atoms"):
		atoms = _atom_mgr.get_atoms()
	
	var filtered: Array = []
	for pos in positions:
		var too_close: bool = false
		for atom in atoms:
			if is_instance_valid(atom) and atom.global_position.distance_to(pos) < 0.5:
				too_close = true
				break
		if not too_close:
			filtered.append(pos)
	
	return filtered

# 退化模式：没有crystal_cell时的简单对称
func _simple_symmetry_positions(seed_pos: Vector3, op_id: String, mult: int) -> Array:
	var positions: Array = []
	match op_id:
		"mirror":
			positions.append(Vector3(-seed_pos.x, seed_pos.y, seed_pos.z))
		"rotate_2":
			positions.append(Vector3(-seed_pos.x, -seed_pos.y, seed_pos.z))
		"rotate_3":
			var a1: Vector3 = _rotate_vec_y(seed_pos, 120.0)
			var a2: Vector3 = _rotate_vec_y(seed_pos, 240.0)
			positions.append(a1)
			positions.append(a2)
		"rotate_4":
			for i in range(1, 4):
				positions.append(_rotate_vec_y(seed_pos, 90.0 * i))
		"rotate_6":
			for i in range(1, 6):
				positions.append(_rotate_vec_y(seed_pos, 60.0 * i))
		"glide":
			positions.append(Vector3(-seed_pos.x + 1.0, seed_pos.y, seed_pos.z))
		"screw_3":
			positions.append(_rotate_vec_y(seed_pos, 120.0) + Vector3(0, 0.5, 0))
			positions.append(_rotate_vec_y(seed_pos, 240.0) + Vector3(0, 1.0, 0))
	return positions

func _rotate_in_plane(frac: Vector3, deg: float) -> Vector3:
	var rad: float = deg * 0.01745329
	return Vector3(
		frac.x * cos(rad) - frac.y * sin(rad),
		frac.x * sin(rad) + frac.y * cos(rad),
		frac.z
	)

func _cos_proj(frac: Vector3, deg: float) -> float:
	var rad: float = deg * 0.01745329
	return frac.x * cos(rad) - frac.y * sin(rad)

func _sin_proj(frac: Vector3, deg: float) -> float:
	var rad: float = deg * 0.01745329
	return frac.x * sin(rad) + frac.y * cos(rad)

func _rotate_vec_y(v: Vector3, deg: float) -> Vector3:
	var rad: float = deg * 0.01745329
	return Vector3(
		v.x * cos(rad) + v.z * sin(rad),
		v.y,
		-v.x * sin(rad) + v.z * cos(rad)
	)

# 生成幽灵原子
func _spawn_ghost_atom(pos: Vector3, symbol: String, color: Color) -> Node3D:
	if _canvas == null or not _canvas.is_inside_tree():
		return null
	
	var atom := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	atom.mesh = sphere
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.4
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5
	atom.material_override = mat
	
	atom.position = pos
	atom.set("element_symbol", symbol)
	_canvas.add_child(atom)
	
	# 飞入动画
	var tween := _canvas.get_tree().create_tween()
	var start_offset: Vector3 = Vector3(
		randf() - 0.5, randf() * 2.0 + 1.0, randf() - 0.5
	) * 2.0
	atom.position = pos + start_offset
	atom.scale = Vector3.ZERO
	
	tween.parallel().tween_property(atom, "position", pos, 0.6)
	tween.parallel().tween_property(atom, "scale", Vector3.ONE, 0.6)
	tween.tween_callback(func():
		if is_instance_valid(atom):
			# 固化：恢复正常材质
			var fix_mat := StandardMaterial3D.new()
			fix_mat.albedo_color = color
			atom.material_override = fix_mat
			# 爆发粒子
			_spawn_weave_particles(pos, color, 4)
	)
	
	return atom

func _spawn_weave_particles(pos: Vector3, color: Color, count: int) -> void:
	if _canvas == null or not _canvas.is_inside_tree():
		return
	
	for i in range(count):
		var p := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.06
		sphere.height = 0.12
		p.mesh = sphere
		
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 2.0
		p.material_override = mat
		
		p.position = pos
		_canvas.add_child(p)
		
		var dir := Vector3(randf() - 0.5, randf() * 0.5 + 0.2, randf() - 0.5).normalized()
		var tween := _canvas.get_tree().create_tween()
		tween.tween_property(p, "position", pos + dir * 2.0, 1.0)
		tween.parallel().tween_property(p, "scale", Vector3.ZERO, 1.0)
		tween.tween_callback(func():
			if is_instance_valid(p):
				p.queue_free()
		)

func _get_atom_symbol(atom: Node3D) -> String:
	if atom == null:
		return ""
	var sym = atom.get("element_symbol") if atom.get("element_symbol") != null else ""
	return sym

func _get_atom_deviation(atom: Node3D) -> float:
	if atom == null:
		return 0.0
	var dev = atom.get("_deviation") if atom.get("_deviation") != null else 0.0
	return dev

func _element_to_row(symbol: String) -> int:
	# 简单映射：质量行=0, 电荷行=1, 自旋行=2, 味觉行=3
	# 根据元素的原子序数模4决定影响哪一行
	var z: int = _element_to_z(symbol)
	return z % 4

func _element_to_z(symbol: String) -> int:
	var table: Dictionary = {
		"H": 1, "He": 2, "Li": 3, "Be": 4, "B": 5, "C": 6, "N": 7, "O": 8, "F": 9,
		"Na": 11, "Mg": 12, "Al": 13, "Si": 14, "P": 15, "S": 16, "Cl": 17,
		"Fe": 26, "Cu": 29, "Zn": 30, "Mn": 25, "Ni": 28, "Co": 27,
	}
	return table.get(symbol, 1)

func get_available_operations() -> Dictionary:
	return WEAVE_OPS

func get_chain_count() -> int:
	return _weave_chain

func on_level_reset() -> void:
	_weave_chain = 0
	_last_weave_time = 0.0
