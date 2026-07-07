# wyckoff_marker.gd
# Wyckoff位置标记 - 半透明小球 + 标签
# 悬停时发光，点击放置原子，位置被填充后消失
#
# Responsibilities:
#   - Wyckoff位置可视化（半透明球+标签）
#   - 悬停高亮效果
#   - 点击信号发射
#   - 填充状态管理
#
# Signals:
#   marker_clicked(marker) - 标记被点击
#   marker_hovered(marker) - 标记被悬停
#
# Dependencies:
#   - 无外部依赖

extends MeshInstance3D

var wyckoff_label: String = "a"
var element_hint: String = ""
var fractional_pos: Vector3 = Vector3.ZERO
var _is_filled: bool = false
var _is_hovered: bool = false
var _base_alpha: float = 0.65
var _hover_alpha: float = 0.85
var _pickable_body: StaticBody3D
var _pulse_tween: Tween = null
var _hover_tween: Tween = null
var _click_tween: Tween = null
var _lock_animating: bool = false

signal marker_clicked(marker: Node)
signal marker_hovered(marker: Node)


func _ready() -> void:
	_setup_mesh()
	_setup_collision()
	_setup_label()
	_start_pulse()


func _setup_mesh() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	sphere.radial_segments = 12
	sphere.rings = 8
	mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.7, 1.0, _base_alpha)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.5, 0.8)
	mat.emission_energy_multiplier = 0.0
	set_surface_override_material(0, mat)


func _setup_collision() -> void:
	_pickable_body = StaticBody3D.new()
	_pickable_body.collision_layer = 1
	_pickable_body.collision_mask = 1
	_pickable_body.add_to_group("wyckoff_marker")
	add_child(_pickable_body)

	var shape := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = 0.35
	shape.shape = sphere_shape
	_pickable_body.add_child(shape)

	_pickable_body.input_event.connect(_on_input_event)
	_pickable_body.mouse_entered.connect(_on_mouse_entered)
	_pickable_body.mouse_exited.connect(_on_mouse_exited)


func _setup_label() -> void:
	var label := Label3D.new()
	label.text = wyckoff_label
	label.font_size = 20
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 0.2, 0)
	label.pixel_size = 0.015
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Arial"])
	label.font = font
	add_child(label)
	# Element hint shown below the wyckoff label
	if element_hint != "":
		var hint_label := Label3D.new()
		hint_label.text = element_hint
		hint_label.font_size = 18
		hint_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		hint_label.position = Vector3(0, -0.15, 0)
		hint_label.pixel_size = 0.015
		hint_label.modulate = Color(1, 0.85, 0.3)
		hint_label.font = font
		add_child(hint_label)


func _on_input_event(_camera: Camera3D, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _is_filled:
			_play_click_feedback()
			marker_clicked.emit(self)


func _on_mouse_entered() -> void:
	_is_hovered = true
	_update_appearance()
	_play_hover_scale(true)
	marker_hovered.emit(self)


func _on_mouse_exited() -> void:
	_is_hovered = false
	_update_appearance()
	_play_hover_scale(false)


func _update_appearance() -> void:
	var mat := get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		return

	if _is_hovered and not _is_filled:
		mat.albedo_color.a = _hover_alpha
		mat.emission_energy_multiplier = 1.2
	else:
		mat.albedo_color.a = _base_alpha
		mat.emission_energy_multiplier = 0.0


func _play_hover_scale(hovered: bool) -> void:
	# 悬停时放大到1.3，离开时恢复并重新启动呼吸动画
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.set_ease(Tween.EASE_OUT)
	_hover_tween.set_trans(Tween.TRANS_BACK)
	if hovered:
		_stop_pulse()
		_hover_tween.tween_property(self, "scale", Vector3(1.3, 1.3, 1.3), 0.2)
	else:
		_hover_tween.tween_property(self, "scale", Vector3.ONE, 0.2)
		_hover_tween.tween_callback(_start_pulse)


func _play_click_feedback() -> void:
	# 点击时闪白并产生涟漪感，随后恢复
	var mat := get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		return

	if _click_tween:
		_click_tween.kill()

	var original_emission: Color = mat.emission
	var original_energy: float = mat.emission_energy_multiplier

	mat.emission = Color.WHITE
	mat.emission_energy_multiplier = 2.0

	_click_tween = create_tween()
	_click_tween.set_ease(Tween.EASE_OUT)
	_click_tween.set_trans(Tween.TRANS_QUAD)
	_click_tween.tween_property(mat, "emission_energy_multiplier", original_energy, 0.25)
	_click_tween.parallel().tween_property(mat, "emission", original_emission, 0.25)


func set_filled(filled: bool) -> void:
	_is_filled = filled
	if _pickable_body:
		_pickable_body.input_ray_pickable = not filled
	if filled:
		# 位置被占，先播放锁定动画再消失，而不是直接隐藏
		if not _lock_animating:
			play_lock_animation()
	else:
		_lock_animating = false
		visible = true
		scale = Vector3.ONE
		_start_pulse()
		_update_appearance()


func _start_pulse() -> void:
	# 呼吸动画：让标记更易被发现
	if _pulse_tween:
		_pulse_tween.kill()
	_pulse_tween = create_tween()
	_pulse_tween.set_loops()
	_pulse_tween.set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.set_trans(Tween.TRANS_SINE)
	_pulse_tween.tween_property(self, "scale", Vector3(1.18, 1.18, 1.18), 0.9)
	_pulse_tween.tween_property(self, "scale", Vector3.ONE, 0.9)


func _stop_pulse() -> void:
	if _pulse_tween:
		_pulse_tween.kill()
		_pulse_tween = null


func is_filled() -> bool:
	return _is_filled


func play_lock_animation() -> void:
	if _lock_animating:
		return
	_lock_animating = true
	_stop_pulse()

	# Wyckoff位置填满时的锁定动画: 缩小+淡出+粒子爆发
	var mat := get_surface_override_material(0) as StandardMaterial3D
	if mat:
		# 闪白
		mat.emission_enabled = true
		mat.emission = Color.WHITE
		mat.emission_energy_multiplier = 2.0

		var tween := create_tween()
		# 缩小到接近 0，避免 scale=ZERO 导致物理引擎 basis 求逆失败
		tween.set_ease(Tween.EASE_IN)
		tween.set_trans(Tween.TRANS_QUAD)
		tween.tween_property(self, "scale", Vector3.ONE * 0.001, 0.4)
		# 淡出
		tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.4)
		tween.parallel().tween_property(mat, "emission_energy_multiplier", 0.0, 0.4)
		tween.tween_callback(func():
			visible = false
			_lock_animating = false
		)
	else:
		var tween := create_tween()
		# 避免 scale=ZERO 导致物理引擎 basis 求逆失败
		tween.tween_property(self, "scale", Vector3.ONE * 0.001, 0.4)
		tween.tween_callback(func():
			visible = false
			_lock_animating = false
		)

	# 粒子爆发
	_spawn_lock_burst()


func _spawn_lock_burst() -> void:
	var particles := ParticlePool.acquire_particle(
		ParticlePool.ParticleType.LOCK_BURST, global_position)
	if particles == null:
		return

	var cleanup_tween := create_tween()
	cleanup_tween.tween_callback(func():
		ParticlePool.release_particle(ParticlePool.ParticleType.LOCK_BURST, particles)
	).set_delay(0.5)
