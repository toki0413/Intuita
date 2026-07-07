# spin_ordering_system.gd
# 磁序与自旋织构 - 每个磁性原子携带自旋向量，相邻自旋耦合产生涌现性质
# 不同磁序解锁不同奖励：铁磁/反铁磁/亚铁磁/螺旋磁

extends RefCounted

signal magnetic_order_changed(order_type: String, net_moment: float)
signal spin_assigned(atom: Node3D, direction: Vector3)
signal order_melted(old_order: String)

# 磁性元素及其磁矩大小
const MAGNETIC_ELEMENTS: Dictionary = {
	"Fe": 2.2, "Mn": 1.5, "Ni": 0.6, "Co": 1.6,
}

# 磁序类型
const ORDER_TYPES: Dictionary = {
	"ferro": {
		"name": "铁磁有序",
		"color": Color(0.2, 0.4, 1.0),
		"reward": "连击不衰减",
		"spin_tolerance": 0.8,
	},
	"antiferro": {
		"name": "反铁磁有序",
		"color": Color(0.8, 0.2, 0.2),
		"reward": "自旋行自动归零",
		"spin_tolerance": 0.1,
	},
	"ferri": {
		"name": "亚铁磁有序",
		"color": Color(0.8, 0.4, 0.8),
		"reward": "目标属性偏移加成",
		"spin_tolerance": 0.4,
	},
	"helical": {
		"name": "螺旋磁有序",
		"color": Color(0.4, 0.8, 1.0),
		"reward": "免疫一次瓦解级联",
		"spin_tolerance": 0.3,
	},
	"paramagnetic": {
		"name": "顺磁态",
		"color": Color(0.5, 0.5, 0.5),
		"reward": "无",
		"spin_tolerance": 1.0,
	},
}

# Curie/Néel 临界温度
const CRITICAL_TEMPS: Dictionary = {
	"Fe": 1043.0,  # Curie
	"Co": 1400.0,
	"Ni": 627.0,
	"Mn": 95.0,   # Néel (反铁磁)
}

var _canvas: Node3D = null
var _atom_mgr = null
var _float_text = null

var _current_order: String = "paramagnetic"
var _spin_arrows: Dictionary = {}  # atom_id -> MeshInstance3D
var _atom_spins: Dictionary = {}   # atom_id -> Vector3
var _current_temperature: float = 300.0
var _is_melted: bool = false
var _helical_immunity_used: bool = false

func _init(canvas: Node3D, atom_mgr, float_text) -> void:
	_canvas = canvas
	_atom_mgr = atom_mgr
	_float_text = float_text

# 为原子设置自旋方向
func set_spin(atom: Node3D, direction: Vector3) -> void:
	if atom == null or not is_instance_valid(atom):
		return
	var symbol: String = _get_atom_symbol(atom)
	if not MAGNETIC_ELEMENTS.has(symbol):
		return
	
	var normalized: Vector3 = direction.normalized()
	var a_id: int = atom.get_instance_id()
	_atom_spins[a_id] = normalized
	
	# 创建/更新自旋箭头
	_update_spin_arrow(atom, normalized, symbol)
	
	# 重新判定磁序
	_classify_order()
	
	spin_assigned.emit(atom, normalized)

# 自动分配自旋（放置磁性原子时调用）
func on_atom_placed(atom: Node3D) -> void:
	if atom == null or not is_instance_valid(atom):
		return
	var symbol: String = _get_atom_symbol(atom)
	if not MAGNETIC_ELEMENTS.has(symbol):
		return
	
	# 默认向上自旋
	var default_spin: Vector3 = Vector3.UP
	if _current_order == "antiferro":
		# 反铁磁模式：交替方向
		var existing_count: int = _atom_spins.size()
		default_spin = Vector3.UP if existing_count % 2 == 0 else Vector3.DOWN
	elif _current_order == "helical":
		# 螺旋模式：根据位置旋转
		var angle: float = atom.global_position.x * 0.5 + atom.global_position.z * 0.5
		default_spin = Vector3(cos(angle), 0.5, sin(angle)).normalized()
	
	set_spin(atom, default_spin)

# 温度更新（由PhaseTransitionSystem调用）
func on_temperature_changed(temp: float) -> void:
	_current_temperature = temp
	_check_melting(temp)

# 检查磁序熔化
func _check_melting(temp: float) -> void:
	for symbol in CRITICAL_TEMPS:
		var tc: float = CRITICAL_TEMPS[symbol]
		if temp > tc and not _is_melted:
			_melt_order()
			return
		if temp < tc * 0.8 and _is_melted:
			_is_melted = false
			# 恢复箭头可见性
			for a_id in _spin_arrows:
				var arrow = _spin_arrows[a_id]
				if is_instance_valid(arrow):
					arrow.visible = true
			_classify_order()

# 熔化磁序
func _melt_order() -> void:
	if _is_melted:
		return
	_is_melted = true
	var old_order: String = _current_order
	_current_order = "paramagnetic"
	
	# 随机化所有自旋箭头方向
	for a_id in _atom_spins:
		var random_dir: Vector3 = Vector3(
			randf() - 0.5, randf() - 0.5, randf() - 0.5
		).normalized()
		_atom_spins[a_id] = random_dir
		var arrow = _spin_arrows.get(a_id, null)
		if arrow != null and is_instance_valid(arrow):
			# 抖动动画
			if _canvas != null:
				var tween := _canvas.get_tree().create_tween()
				tween.tween_property(arrow, "rotation", Vector3(randf(), randf(), randf()) * PI, 0.5)
	
	if _float_text != null and _atom_spins.size() > 0:
		_float_text.show_float_text(
			Vector3(0, 3, 0),
			"磁序熔化!",
			Color(1.0, 0.3, 0.3),
			3.0
		)
	
	if SoundManager != null:
		SoundManager.play(SoundManager.SoundType.CONSERVATION_WARN)
	
	order_melted.emit(old_order)
	magnetic_order_changed.emit("paramagnetic", 0.0)

# 判定磁序类型
func _classify_order() -> void:
	if _is_melted or _atom_spins.size() == 0:
		_current_order = "paramagnetic"
		magnetic_order_changed.emit(_current_order, 0.0)
		return
	
	var spins: Array = _atom_spins.values()
	var up_count: int = 0
	var down_count: int = 0
	var total_moment: float = 0.0
	
	for s in spins:
		if s.y > 0.5:
			up_count += 1
			total_moment += 1.0
		elif s.y < -0.5:
			down_count += 1
			total_moment -= 1.0
	
	# 检测螺旋磁：自旋方向随空间旋转
	var is_helical: bool = _detect_helical_order(spins)
	
	var new_order: String = "paramagnetic"
	if is_helical:
		new_order = "helical"
	elif up_count == spins.size():
		new_order = "ferro"
	elif absi(up_count - down_count) <= 1 and spins.size() >= 2:
		new_order = "antiferro"
	elif up_count > 0 and down_count > 0:
		new_order = "ferri"
	
	if new_order != _current_order:
		_current_order = new_order
		_apply_order_reward(new_order, total_moment)
		magnetic_order_changed.emit(new_order, total_moment)
		
		if _float_text != null:
			var order_info: Dictionary = ORDER_TYPES.get(new_order, {})
			_float_text.show_float_text(
				Vector3(0, 3, 0),
				"%s! %s" % [order_info.get("name", ""), order_info.get("reward", "")],
				order_info.get("color", Color.WHITE),
				3.0
			)
		
		if SoundManager != null:
			SoundManager.play(SoundManager.SoundType.VERIFICATION_PASS)

# 检测螺旋磁序
func _detect_helical_order(spins: Array) -> bool:
	if spins.size() < 3:
		return false
	# 检查自旋方向是否沿空间旋转
	var angle_variations: Array = []
	for i in range(1, spins.size()):
		var prev: Vector3 = spins[i - 1]
		var curr: Vector3 = spins[i]
		var angle: float = prev.angle_to(curr)
		angle_variations.append(angle)
	
	# 如果角度变化一致且非零，判定为螺旋
	if angle_variations.size() < 2:
		return false
	var first_angle: float = angle_variations[0]
	if first_angle < 0.3:  # 角度太小不是螺旋
		return false
	for a in angle_variations:
		if abs(a - first_angle) > 0.5:
			return false
	return true

# 应用磁序奖励
func _apply_order_reward(order: String, net_moment: float) -> void:
	match order:
		"ferro":
			# 铁磁：连击不衰减（通过日志反馈）
			if GameLogger != null:
				GameLogger.info("SpinOrder", "[磁序] 铁磁有序! 连击锁定, 净磁矩: %.2f" % net_moment)
		"antiferro":
			# 反铁磁：自旋行自动归零
			if ConservationEngine != null:
				ConservationEngine.apply_perturbation(2, 2, -net_moment * 0.5, "antiferro_balance")
			if GameLogger != null:
				GameLogger.info("SpinOrder", "[磁序] 反铁磁有序! 自旋行自动平衡")
		"ferri":
			# 亚铁磁：核心奖励
			if LevelManager != null:
				GameState.gain_cores(2)
			if GameLogger != null:
				GameLogger.info("SpinOrder", "[磁序] 亚铁磁有序! +2核心")
		"helical":
			# 螺旋磁：免疫一次瓦解
			_helical_immunity_used = false
			if GameLogger != null:
				GameLogger.info("SpinOrder", "[磁序] 螺旋磁有序! 获得瓦解免疫")

# 消耗螺旋磁免疫（被ConstructionCanvas调用）
func consume_helical_immunity() -> bool:
	if _current_order == "helical" and not _helical_immunity_used:
		_helical_immunity_used = true
		if _float_text != null:
			_float_text.show_float_text(
				Vector3(0, 3, 0),
				"螺旋磁护盾! 免疫瓦解!",
				Color(0.4, 0.8, 1.0),
				3.0
			)
		return true
	return false

# 创建/更新自旋箭头
func _update_spin_arrow(atom: Node3D, direction: Vector3, symbol: String) -> void:
	var a_id: int = atom.get_instance_id()
	
	# 移除旧箭头
	if _spin_arrows.has(a_id):
		var old_arrow = _spin_arrows[a_id]
		if is_instance_valid(old_arrow):
			old_arrow.queue_free()
	
	# 创建新箭头
	var arrow := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.08
	cone.height = 0.3
	arrow.mesh = cone
	
	var mat := StandardMaterial3D.new()
	var arrow_color: Color = Color(0.3, 0.5, 1.0) if direction.y > 0 else Color(1.0, 0.3, 0.3)
	mat.albedo_color = arrow_color
	mat.emission_enabled = true
	mat.emission = arrow_color * 0.5
	mat.emission_energy_multiplier = 1.5
	arrow.material_override = mat
	
	# 定位在原子顶部
	arrow.position = atom.global_position + Vector3(0, 0.5, 0)
	
	# 朝向自旋方向
	if direction != Vector3.ZERO:
		var look_at_pos: Vector3 = arrow.position + direction
		arrow.look_at(look_at_pos)
		arrow.rotate_x(PI / 2)  # Cone默认朝下，需要翻转
	
	if _canvas != null:
		_canvas.add_child(arrow)
	_spin_arrows[a_id] = arrow
	
	# 出现动画
	if _canvas != null:
		var tween := _canvas.get_tree().create_tween()
		arrow.scale = Vector3.ZERO
		tween.tween_property(arrow, "scale", Vector3.ONE, 0.3)

func get_current_order() -> String:
	return _current_order

func get_order_info() -> Dictionary:
	return ORDER_TYPES.get(_current_order, {})

func get_net_moment() -> float:
	var total: float = 0.0
	for s in _atom_spins.values():
		total += s.y
	return total

func on_level_reset() -> void:
	for a_id in _spin_arrows:
		var arrow = _spin_arrows[a_id]
		if is_instance_valid(arrow):
			arrow.queue_free()
	_spin_arrows.clear()
	_atom_spins.clear()
	_current_order = "paramagnetic"
	_is_melted = false
	_helical_immunity_used = false

func _get_atom_symbol(atom: Node3D) -> String:
	if atom == null:
		return ""
	var sym = atom.get("element_symbol") if atom.get("element_symbol") != null else ""
	return sym
