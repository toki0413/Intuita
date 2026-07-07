# atom_node.gd
# 原子节点 - 3D场景中的单个原子表示
# 包含元素信息、Wyckoff位置、守恒辉光和交互
#
# Responsibilities:
#   - 原子3D网格和材质管理
#   - 碰撞检测和点击交互
#   - 元素标签显示
#   - 守恒辉光效果
#   - 瓦解动画
#   - Wyckoff位置吸附
#
# Signals:
#   atom_clicked(atom_node) - 原子被点击
#   atom_state_changed(atom_node, new_state) - 原子视觉状态变化
#
# Dependencies:
#   - Shaders: conservation_glow.gdshader

extends MeshInstance3D

enum VisualState { IDLE, SELECTED, HOVER, WARNING, DISINTEGRATING }

@export var element_symbol: String = "H"
@export var atomic_number: int = 1
@export var fractional_position: Vector3 = Vector3.ZERO
@export var wyckoff_label: String = "a"

var _current_state: VisualState = VisualState.IDLE
var _deviation: float = 0.0  # 守恒偏离度 0~1
var _glow_material: ShaderMaterial
var _base_color: Color = Color.WHITE
var _atom_radius: float = 0.3
var _original_y: float = 0.0  # 原始Y坐标，用于质量偏离下沉效果
var _original_x: float = 0.0  # 原始X坐标，用于振动基准
var _original_z: float = 0.0  # 原始Z坐标，用于振动基准
var _is_disintegrating: bool = false
var _disintegration_time: float = 0.0
var _failed_row: int = -1  # 崩解时哪个守恒行失败
var _disintegration_material: ShaderMaterial

# 守恒应力振动
var _vibration_time: float = 0.0
var _vibration_offset: Vector3 = Vector3.ZERO

# 碰撞检测用的子节点引用
var _static_body: StaticBody3D
var _collision_shape: CollisionShape3D
var _label_3d: Label3D

# 应变松弛 — 让原子在放置后自动微调到低能量位置
var _strain_ref: RefCounted = null  # StrainField 引用
var _atom_list_ref: RefCounted = null  # AtomPlacementManager 引用
var _relaxation_pos: Vector3 = Vector3.ZERO  # 松弛后的目标位置
var _is_relaxing: bool = false

signal atom_clicked(atom_node: Node)
signal atom_state_changed(atom_node: Node, new_state: int)


func set_strain_field(strain: RefCounted, atom_mgr: RefCounted) -> void:
	_strain_ref = strain
	_atom_list_ref = atom_mgr
	_relaxation_pos = global_position
	_is_relaxing = true
	set_process(true)


func _ready() -> void:
	_setup_mesh()
	_setup_collision()
	_setup_label()
	_setup_glow_material()
	_update_visual()


func _enter_tree() -> void:
	# 进入场景树时先隐藏，等play_spawn_animation()触发
	# 不用scale=ZERO，会导致物理引擎basis求逆失败
	visible = false
	_original_y = global_position.y
	_original_x = global_position.x
	_original_z = global_position.z


func _setup_mesh() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = _atom_radius
	sphere.height = _atom_radius * 2.0
	sphere.radial_segments = 24
	sphere.rings = 16
	mesh = sphere

	# 基础材质
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _base_color
	mat.metallic = 0.2
	mat.roughness = 0.4
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	set_surface_override_material(0, mat)


func _setup_collision() -> void:
	_static_body = StaticBody3D.new()
	_static_body.collision_layer = 1
	_static_body.collision_mask = 1
	_static_body.add_to_group("atom")
	add_child(_static_body)

	_collision_shape = CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = _atom_radius * 1.2  # 稍大一点方便点击
	_collision_shape.shape = sphere_shape
	_static_body.add_child(_collision_shape)

	_static_body.input_event.connect(_on_input_event)


func _setup_label() -> void:
	_label_3d = Label3D.new()
	_label_3d.text = element_symbol
	_label_3d.font_size = 24
	_label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label_3d.position = Vector3(0, _atom_radius + 0.15, 0)
	_label_3d.pixel_size = 0.02
	# 用Arial字体
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Arial"])
	_label_3d.font = font
	add_child(_label_3d)


func _setup_glow_material() -> void:
	# 创建辉光球体 - 比原子稍大的半透明球
	var glow_mesh := MeshInstance3D.new()
	var glow_sphere := SphereMesh.new()
	glow_sphere.radius = _atom_radius * 1.4
	glow_sphere.height = _atom_radius * 2.8
	glow_sphere.radial_segments = 16
	glow_sphere.rings = 12
	glow_mesh.mesh = glow_sphere

	_glow_material = ShaderMaterial.new()
	_glow_material.shader = load("res://shaders/conservation_glow.gdshader")
	_glow_material.set_shader_parameter("deviation", 0.0)
	_glow_material.set_shader_parameter("pulse_speed", 2.0)
	_glow_material.set_shader_parameter("intensity", 1.0)
	_update_glow_colors()
	glow_mesh.set_surface_override_material(0, _glow_material)
	glow_mesh.name = "Glow"

	add_child(glow_mesh)


func _on_input_event(_camera: Camera3D, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		atom_clicked.emit(self)
	elif event is InputEventMouseMotion:
		if _current_state != VisualState.SELECTED:
			set_state(VisualState.HOVER)


func set_state(new_state: VisualState) -> void:
	if _current_state == new_state:
		return
	var old := _current_state
	_current_state = new_state
	_update_visual()
	atom_state_changed.emit(self, new_state)


func get_state() -> VisualState:
	return _current_state


func _update_visual() -> void:
	var mat := get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		return

	match _current_state:
		VisualState.IDLE:
			mat.albedo_color = _base_color
			mat.emission_enabled = false
			if _glow_material:
				_glow_material.set_shader_parameter("intensity", 1.0)
				_glow_material.set_shader_parameter("pulse_speed", 2.0)
		VisualState.SELECTED:
			mat.albedo_color = _base_color
			mat.emission_enabled = true
			mat.emission = Color(0.3, 0.6, 1.0)
			mat.emission_energy_multiplier = 0.5
			# 选中辉光 — MolGame 风格高亮脉冲
			if _glow_material:
				_glow_material.set_shader_parameter("intensity", 3.0)
				_glow_material.set_shader_parameter("pulse_speed", 5.0)
		VisualState.HOVER:
			mat.albedo_color = _base_color * 1.2
			mat.emission_enabled = true
			mat.emission = Color(0.2, 0.4, 0.8)
			mat.emission_energy_multiplier = 0.3
			if _glow_material:
				_glow_material.set_shader_parameter("intensity", 1.8)
				_glow_material.set_shader_parameter("pulse_speed", 3.0)
		VisualState.WARNING:
			mat.emission_enabled = true
			mat.emission = ConservationEngine.get_state_color(1)
			mat.emission_energy_multiplier = 0.6
		VisualState.DISINTEGRATING:
			mat.emission_enabled = true
			mat.emission = ConservationEngine.get_state_color(3)
			mat.emission_energy_multiplier = 1.0


func update_glow_from_conservation(deviation: float) -> void:
	_deviation = deviation
	# 特征值偏离度 abs(lambda - 1) 理论上可大于 1.0，不在此处截断
	# shader 内部负责将任意正数映射到可视化范围
	if _glow_material:
		_glow_material.set_shader_parameter("deviation", _deviation)
		_update_glow_colors()

	# 根据偏离度自动切换视觉状态
	if _deviation > 0.6:
		if _current_state != VisualState.SELECTED:
			set_state(VisualState.WARNING)
	elif _deviation > 0.3:
		if _current_state == VisualState.WARNING:
			set_state(VisualState.IDLE)
	elif _current_state == VisualState.WARNING:
		set_state(VisualState.IDLE)

	# 脉冲速度随偏离度增加，减少闪烁模式下限制到安全范围
	if _glow_material:
		var pulse_speed: float = 2.0 + _deviation * 6.0
		if UiAnimator != null and UiAnimator.is_flashing_reduced():
			pulse_speed = minf(pulse_speed, 1.0)
		_glow_material.set_shader_parameter("pulse_speed", pulse_speed)

	# 矩阵物理可视化：根据守恒矩阵各行偏离调整原子视觉效果
	_apply_matrix_physical_visuals()


func _update_glow_colors() -> void:
	if _glow_material == null:
		return
	var healthy := ConservationEngine.get_state_color(0)
	var warning := ConservationEngine.get_state_color(1)
	var critical := ConservationEngine.get_state_color(2)
	_glow_material.set_shader_parameter("healthy_color", Vector3(healthy.r, healthy.g, healthy.b))
	_glow_material.set_shader_parameter("warning_color", Vector3(warning.r, warning.g, warning.b))
	_glow_material.set_shader_parameter("critical_color", Vector3(critical.r, critical.g, critical.b))


func _apply_matrix_physical_visuals() -> void:
	# 守恒矩阵物理可视化：
	# 行0(质量) → Y轴下沉效果，偏离越大越明显
	# 行1(电荷) → 颜色色相偏移
	# 行2(能量) → 辉光强度
	# 行3(宇称) → 镜像残影（通过缩放不对称实现）
	# 全局偏离 → 应力振动（原子在平衡位置附近抖动）
	var dev_summary: Dictionary = ConservationEngine.get_deviation_summary()
	var mass_dev: float = dev_summary.get("0", {}).get("deviation", 0.0)
	var charge_dev: float = dev_summary.get("1", {}).get("deviation", 0.0)
	var energy_dev: float = dev_summary.get("2", {}).get("deviation", 0.0)
	var parity_dev: float = dev_summary.get("3", {}).get("deviation", 0.0)

	# 质量行→Y轴下沉（最大0.3单位）
	var sink: float = mass_dev * 0.3
	global_position.y = _original_y - sink if _original_y != 0.0 else global_position.y

	# 能量行→辉光强度
	if _glow_material:
		var glow_intensity: float = 1.0 + energy_dev * 3.0
		_glow_material.set_shader_parameter("intensity", glow_intensity)

	# 电荷行→颜色色相偏移
	var mat := get_surface_override_material(0) as StandardMaterial3D
	if mat:
		var hue_shift: float = charge_dev * 0.3
		var shifted_color := _base_color
		var h: float = shifted_color.h + hue_shift
		shifted_color.h = fposmod(h, 1.0)
		mat.albedo_color = shifted_color

	# 宇称行→非对称缩放（镜像残影效果）
	if parity_dev > 0.1:
		scale.x = 1.0 + parity_dev * 0.2
		scale.z = 1.0 - parity_dev * 0.2
	else:
		scale.x = 1.0
		scale.z = 1.0

	# 应力振动：偏离>0.2时原子开始抖动
	# 振动在 _process 中持续更新，这里只启用/禁用
	if _deviation > 0.2 and not _is_disintegrating:
		set_process(true)
	elif _vibration_offset == Vector3.ZERO and not _is_disintegrating:
		set_process(false)


func set_element(symbol: String, number: int, color: Color, radius: float) -> void:
	element_symbol = symbol
	atomic_number = number
	_base_color = color
	_atom_radius = radius

	# 更新网格
	if mesh is SphereMesh:
		mesh.radius = radius
		mesh.height = radius * 2.0

	# 更新碰撞体
	if _collision_shape and _collision_shape.shape is SphereShape3D:
		(_collision_shape.shape as SphereShape3D).radius = radius * 1.2

	# 更新标签
	if _label_3d:
		_label_3d.text = symbol
		_label_3d.position = Vector3(0, radius + 0.15, 0)

	# 更新辉光球体大小
	var glow_node := get_node_or_null("Glow") as MeshInstance3D
	if glow_node and glow_node.mesh is SphereMesh:
		glow_node.mesh.radius = radius * 1.4
		glow_node.mesh.height = radius * 2.8

	_update_visual()


# 模拟期间根据应变大小着色，给玩家直观的受力反馈
func set_strain_visual(magnitude: float) -> void:
	var mat := get_active_material(0) as StandardMaterial3D
	if mat == null:
		return
	if magnitude < 0.2:
		mat.albedo_color = _base_color
	elif magnitude < 0.5:
		var t := (magnitude - 0.2) / 0.3
		mat.albedo_color = _base_color.lerp(Color(0.95, 0.85, 0.2), t)
	elif magnitude < 0.8:
		var t := (magnitude - 0.5) / 0.3
		mat.albedo_color = Color(0.95, 0.85, 0.2).lerp(Color(0.95, 0.5, 0.1), t)
	else:
		var t := minf((magnitude - 0.8) / 0.5, 1.0)
		mat.albedo_color = Color(0.95, 0.5, 0.1).lerp(Color(0.95, 0.15, 0.15), t)


func snap_to_wyckoff(wyckoff_positions: Array) -> void:
	# 找最近的Wyckoff位置并吸附
	var best_pos := fractional_position
	var best_dist := INF

	for wp in wyckoff_positions:
		if wp is Dictionary and wp.has("positions"):
			for pos in wp["positions"]:
				if pos is Array and pos.size() >= 3:
					var wp_vec := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
					var dist := fractional_position.distance_to(wp_vec)
					if dist < best_dist:
						best_dist = dist
						best_pos = wp_vec
						if wp.has("label"):
							wyckoff_label = str(wp["label"])

	fractional_position = best_pos


# ---- 微奖励动画 ----

func play_spawn_animation() -> void:
	# 弹入动画: 缩放接近 0 → 1.15 → 1.0 over 0.3s
	# 避免 scale=ZERO，否则物理引擎求逆 basis 会报错
	visible = true
	scale = Vector3.ONE * 0.001
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "scale", Vector3.ONE * 1.15, 0.2)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "scale", Vector3.ONE, 0.1)

	# 发射光闪白→正常
	var mat := get_surface_override_material(0) as StandardMaterial3D
	if mat:
		var orig_emission := mat.emission
		var orig_energy: float = mat.emission_energy_multiplier
		mat.emission_enabled = true
		mat.emission = Color.WHITE
		mat.emission_energy_multiplier = 2.0
		var flash_tween := create_tween()
		flash_tween.tween_property(mat, "emission_energy_multiplier", orig_energy, 0.2)
		flash_tween.tween_callback(func():
			if is_instance_valid(mat):
				mat.emission = orig_emission
				if orig_energy < 0.01:
					mat.emission_enabled = false
		)

	# 放置粒子爆发
	_spawn_placement_burst()


func play_lock_animation() -> void:
	# Wyckoff位置填满时的锁定动画
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "scale", Vector3.ONE * 1.2, 0.12)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "scale", Vector3.ONE, 0.12)

	# 金色闪光
	var mat := get_surface_override_material(0) as StandardMaterial3D
	if mat:
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.85, 0.3)  # 金色
		mat.emission_energy_multiplier = 1.5
		var gold_tween := create_tween()
		gold_tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.4)
		gold_tween.tween_callback(func():
			if is_instance_valid(mat):
				mat.emission_enabled = false
		)

	SoundManager.play(SoundManager.SoundType.WYCKOFF_LOCK)

	# 金色粒子爆发
	_spawn_gold_burst()


func _spawn_placement_burst() -> void:
	var particles := ParticlePool.acquire_particle(
		ParticlePool.ParticleType.PLACEMENT_BURST, global_position)
	if particles == null:
		return
	ParticlePool.set_placement_color(particles, _base_color)

	var cleanup_tween := create_tween()
	cleanup_tween.tween_callback(func():
		ParticlePool.release_particle(ParticlePool.ParticleType.PLACEMENT_BURST, particles)
	).set_delay(0.6)


func _spawn_gold_burst() -> void:
	var particles := ParticlePool.acquire_particle(
		ParticlePool.ParticleType.GOLD_BURST, global_position)
	if particles == null:
		return

	var cleanup_tween := create_tween()
	cleanup_tween.tween_callback(func():
		ParticlePool.release_particle(ParticlePool.ParticleType.GOLD_BURST, particles)
	).set_delay(0.6)


func start_disintegration(failed_row: int = -1) -> void:
	if _is_disintegrating:
		return
	_is_disintegrating = true
	_failed_row = failed_row
	_disintegration_time = 0.0
	set_state(VisualState.DISINTEGRATING)

	# Hide label and glow
	if _label_3d:
		_label_3d.visible = false
	var glow_node := get_node_or_null("Glow") as MeshInstance3D
	if glow_node:
		glow_node.visible = false

	# Disable collision
	if _static_body:
		_static_body.process_mode = Node.PROCESS_MODE_DISABLED

	# Apply disintegration shader to the main mesh
	_disintegration_material = ShaderMaterial.new()
	_disintegration_material.shader = load("res://shaders/disintegration.gdshader")

	var frag_color := _get_fragment_color()
	_disintegration_material.set_shader_parameter("base_color", Vector3(frag_color.r, frag_color.g, frag_color.b))
	_disintegration_material.set_shader_parameter("disintegration_progress", 0.0)
	_disintegration_material.set_shader_parameter("scatter_strength", 2.0)
	_disintegration_material.set_shader_parameter("crack_origin", Vector3.ZERO)

	set_surface_override_material(0, _disintegration_material)

	# Animate progress 0 → 1 over 1.5s, then free
	var tween := create_tween()
	tween.tween_method(_set_disintegration_progress, 0.0, 1.0, 1.5)
	tween.tween_callback(queue_free)

	set_process(true)


func start_disintegration_v2(failed_row: int = -1) -> void:
	start_disintegration(failed_row)


func apply_proof_gold() -> void:
	# L5验证通过时应用金色护盾shader
	var existing := get_node_or_null("ProofGold")
	if existing:
		return

	var gold_mesh := MeshInstance3D.new()
	var gold_sphere := SphereMesh.new()
	gold_sphere.radius = _atom_radius * 1.5
	gold_sphere.height = _atom_radius * 3.0
	gold_sphere.radial_segments = 16
	gold_sphere.rings = 12
	gold_mesh.mesh = gold_sphere

	var gold_mat := ShaderMaterial.new()
	gold_mat.shader = load("res://shaders/proof_gold.gdshader")
	gold_mat.set_shader_parameter("activation_time", Time.get_ticks_msec() / 1000.0)
	gold_mat.set_shader_parameter("glow_intensity", 1.5)
	gold_mat.set_shader_parameter("pulse_speed", 1.5)
	gold_mat.set_shader_parameter("hex_scale", 8.0)
	gold_mesh.surface_set_material(0, gold_mat)
	gold_mesh.name = "ProofGold"

	add_child(gold_mesh)


func _get_fragment_color() -> Color:
	match _failed_row:
		0: return Color(0.9, 0.2, 0.1)    # 质量→红
		1: return Color(0.2, 0.4, 0.9)    # 电荷→蓝
		2: return Color(0.1, 0.8, 0.3)    # 动量→绿
		3: return Color(0.95, 0.85, 0.1)  # 能量→黄
		_: return Color(0.9, 0.3, 0.05)   # 默认→红橙


func _set_disintegration_progress(value: float) -> void:
	if _disintegration_material:
		_disintegration_material.set_shader_parameter("disintegration_progress", value)


func _process(delta: float) -> void:
	if _is_disintegrating:
		_disintegration_time += delta
		if _disintegration_time > 3.0:
			queue_free()
		return

	# 应变松弛：原子放置后受应变梯度推动，微调到低能量位置
	if _is_relaxing and _strain_ref != null and _atom_list_ref != null:
		var all_atoms = _atom_list_ref.get_atoms()
		var force: Vector3 = _strain_ref.compute_relaxation_force(self, all_atoms)
		if force.length() > 0.0001:
			# 阻尼松弛：力 → 速度 → 位置，每帧衰减
			_relaxation_pos += force * delta * 50.0
			# 限制松弛范围，避免原子飘走
			var offset: Vector3 = _relaxation_pos - Vector3(_original_x, _original_y, _original_z)
			if offset.length() > 0.5:
				_relaxation_pos = Vector3(_original_x, _original_y, _original_z) + offset.normalized() * 0.5

	# 守恒应力振动：偏离>0.2时原子在平衡位置附近抖动
	if _deviation > 0.2:
		_vibration_time += delta
		var amplitude := _deviation * 0.03
		var freq := 6.0 + _deviation * 15.0
		if UiAnimator != null and UiAnimator.is_flashing_reduced():
			amplitude *= 0.3
			freq = minf(freq, 4.0)
		_vibration_offset = Vector3(
			sin(_vibration_time * freq) * amplitude,
			cos(_vibration_time * freq * 1.2) * amplitude * 0.5,
			sin(_vibration_time * freq * 0.8 + 2.0) * amplitude
		)
		var base_y := _relaxation_pos.y - _deviation * 0.3
		global_position = Vector3(
			_relaxation_pos.x + _vibration_offset.x,
			base_y + _vibration_offset.y,
			_relaxation_pos.z + _vibration_offset.z
		)
	else:
		if _vibration_offset != Vector3.ZERO:
			_vibration_offset = Vector3.ZERO
		# 有松弛力时持续更新位置，否则恢复原位
		if _is_relaxing and _strain_ref != null:
			var all_atoms2 = _atom_list_ref.get_atoms()
			var force2: Vector3 = _strain_ref.compute_relaxation_force(self, all_atoms2)
			if force2.length() > 0.0001:
				global_position = _relaxation_pos
			else:
				_is_relaxing = false
				global_position = Vector3(_original_x, _original_y, _original_z)
				set_process(false)
		else:
			global_position = Vector3(
				_original_x,
				_original_y - _deviation * 0.3 if _original_y != 0.0 else global_position.y,
				_original_z
			)
			set_process(false)


# ============================================================
# Adjacency-Aware Rendering (P2)
# ============================================================
# Detect nearby atoms and update visual state based on neighbor types

func update_neighbor_visuals(neighbors: Array[Node3D] = []) -> void:
	var _neighbor_threshold: float = _atom_radius * 3.0
	var _bonding_threshold: float = _atom_radius * 2.2

	var has_bonding_neighbor := false
	var neighbor_count := 0

	for n in neighbors:
		if n == self or not is_instance_valid(n):
			continue
		var dist := global_position.distance_to(n.global_position)
		if dist < _neighbor_threshold:
			neighbor_count += 1
			if dist < _bonding_threshold:
				has_bonding_neighbor = true

	var mat := get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		return

	if has_bonding_neighbor:
		# Bonding neighbor: increase emission and make slightly translucent
		mat.emission_enabled = true
		mat.emission = _base_color * 0.5
		mat.emission_energy_multiplier = 0.8
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.85
	elif neighbor_count > 0:
		# Nearby but not bonding: subtle highlight
		mat.emission_enabled = true
		mat.emission = _base_color * 0.2
		mat.emission_energy_multiplier = 0.3
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.95
	else:
		# Isolated: reset to base visual
		if _current_state == VisualState.IDLE:
			mat.emission_enabled = false
		mat.albedo_color = _base_color
		mat.albedo_color.a = 1.0

	atom_state_changed.emit(self, _current_state)

