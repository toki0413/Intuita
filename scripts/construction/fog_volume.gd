# fog_volume.gd
# 迷雾体积 - 三种类型对应不同的视觉效果和行为
# SEMI_DECIDABLE: 蓝色薄雾, 20个发光蓝色粒子缓慢上升, 可驱散
# UNDECIDABLE: 深紫浓雾, 15个紫色闪烁粒子环绕, 概率穿透
# INDEPENDENT: 近纯黑球体, 数学符号滚动, 不可驱散
#
# Responsibilities:
#   - 迷雾3D渲染（FogVolume3D + shader）
#   - 三种迷雾类型的视觉区分和粒子效果
#   - 驱散/穿透/窥视逻辑和动画
#   - 交互音效触发
#
# Signals:
#   fog_entered(fog_volume) - 鼠标进入迷雾
#   fog_exited(fog_volume) - 鼠标离开迷雾
#
# Dependencies:
#   - Autoload: FogSystem, SoundManager
#   - Shaders: fog_volumetric.gdshader

extends Node3D

enum FogType { SEMI_DECIDABLE, UNDECIDABLE, INDEPENDENT }

var fog_type: FogType = FogType.SEMI_DECIDABLE
var region_id: int = -1
var _is_resolved: bool = false
var _is_peeked: bool = false
var _fog_material: ShaderMaterial
var _fog_radius: float = 1.5
var _fade_tween: Tween = null
var _fog_volume: Node = null

# 各类型粒子系统
var _semi_particles: GPUParticles3D = null
var _undec_particles: GPUParticles3D = null

# 独立雾的涟漪/符号效果
var _ripple_active: bool = false
var _ripple_time: float = 0.0
var _symbol_glow_active: bool = false
var _symbol_glow_time: float = 0.0

signal fog_entered(fog_volume: Node)
signal fog_exited(fog_volume: Node)


func _ready() -> void:
	_setup_fog()
	_setup_collision()
	_animate_fade_in()
	FogSystem.fog_peeked.connect(_on_fog_peeked)


func _exit_tree() -> void:
	# 断开 autoload 信号，避免悬空回调
	if FogSystem != null and FogSystem.is_connected("fog_peeked", _on_fog_peeked):
		FogSystem.fog_peeked.disconnect(_on_fog_peeked)
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()


func _process(delta: float) -> void:
	# 没有活跃动画时跳过处理
	if not _ripple_active and not _symbol_glow_active:
		set_process(false)
		return
	# 独立雾的涟漪衰减
	if _ripple_active:
		_ripple_time += delta
		if _ripple_time > 1.5:
			_ripple_active = false
			_ripple_time = 0.0
			if _fog_material:
				_fog_material.set_shader_parameter("ripple_strength", 0.0)

	# 独立雾的符号发光衰减
	if _symbol_glow_active:
		_symbol_glow_time += delta
		if _symbol_glow_time > 1.0:
			_symbol_glow_active = false
			_symbol_glow_time = 0.0
			if _fog_material:
				_fog_material.set_shader_parameter("symbol_glow", 0.0)


func _setup_fog() -> void:
	# FogVolume (Godot 4 class, not FogVolume3D)
	if _fog_volume == null and ClassDB.class_exists("FogVolume"):
		_fog_volume = ClassDB.instantiate("FogVolume")
		add_child(_fog_volume)
	if _fog_volume:
		_fog_volume.set("size", Vector3(_fog_radius * 2.0, _fog_radius * 2.0, _fog_radius * 2.0))
		_fog_volume.set("shape", 0)  # SHAPE_ELLIPSOID

	# 用shader材质驱动体积雾
	_fog_material = ShaderMaterial.new()
	_fog_material.shader = load("res://shaders/fog_volumetric.gdshader")

	# 根据类型设置参数
	match fog_type:
		FogType.SEMI_DECIDABLE:
			_fog_material.set_shader_parameter("fog_type", 0)
			_fog_material.set_shader_parameter("density", 0.5)
			_fog_material.set_shader_parameter("noise_scale", 3.0)
			_fog_material.set_shader_parameter("fade", 0.0)
			_fog_material.set_shader_parameter("peek_opacity", 0.0)
			_fog_material.set_shader_parameter("ripple_strength", 0.0)
			_fog_material.set_shader_parameter("symbol_glow", 0.0)
			_setup_semi_particles()
		FogType.UNDECIDABLE:
			_fog_material.set_shader_parameter("fog_type", 1)
			_fog_material.set_shader_parameter("density", 1.0)
			_fog_material.set_shader_parameter("noise_scale", 4.0)
			_fog_material.set_shader_parameter("fade", 0.0)
			_fog_material.set_shader_parameter("peek_opacity", 0.0)
			_fog_material.set_shader_parameter("ripple_strength", 0.0)
			_fog_material.set_shader_parameter("symbol_glow", 0.0)
			_setup_undec_particles()
		FogType.INDEPENDENT:
			_fog_material.set_shader_parameter("fog_type", 2)
			_fog_material.set_shader_parameter("density", 1.5)
			_fog_material.set_shader_parameter("noise_scale", 5.0)
			_fog_material.set_shader_parameter("fade", 0.0)
			_fog_material.set_shader_parameter("peek_opacity", 0.0)
			_fog_material.set_shader_parameter("ripple_strength", 0.0)
			_fog_material.set_shader_parameter("symbol_glow", 0.0)
			# 独立雾不创建粒子 — 压迫性的空旷

	if _fog_volume:
		_fog_volume.set("material", _fog_material)


func _setup_semi_particles() -> void:
	# 半可判定雾: 20个发光蓝色粒子, 缓慢上升(0.2m/s), 轻微水平漂移
	_semi_particles = GPUParticles3D.new()
	_semi_particles.amount = 20
	_semi_particles.lifetime = 6.0
	_semi_particles.explosiveness = 0.0
	_semi_particles.randomness = 0.8
	_semi_particles.local_coords = true

	var process_mat := ParticleProcessMaterial.new()
	process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_mat.emission_sphere_radius = _fog_radius * 0.8
	process_mat.direction = Vector3(0.0, 1.0, 0.0)
	process_mat.spread = 25.0
	# 0.2 m/s 上升 + 轻微水平漂移
	process_mat.gravity = Vector3(0.0, 0.02, 0.0)
	process_mat.initial_velocity_min = 0.05
	process_mat.initial_velocity_max = 0.15
	process_mat.scale_min = 0.03
	process_mat.scale_max = 0.06
	# 蓝色发光
	process_mat.color = Color(0.3, 0.5, 1.0, 0.8)

	# 呼吸式缩放曲线
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.3))
	scale_curve.add_point(Vector2(0.3, 1.0))
	scale_curve.add_point(Vector2(0.6, 0.7))
	scale_curve.add_point(Vector2(1.0, 0.0))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	process_mat.scale_curve = scale_tex

	_semi_particles.process_material = process_mat

	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(0.1, 0.1)
	_semi_particles.draw_pass_1 = quad_mesh

	add_child(_semi_particles)


func _setup_undec_particles() -> void:
	# 不可判定雾: 15个紫色闪烁粒子, 环绕中心(0.5m/s)
	_undec_particles = GPUParticles3D.new()
	_undec_particles.amount = 15
	_undec_particles.lifetime = 4.0
	_undec_particles.explosiveness = 0.2
	_undec_particles.randomness = 0.9
	_undec_particles.local_coords = true

	var process_mat := ParticleProcessMaterial.new()
	process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_mat.emission_sphere_radius = _fog_radius * 0.6
	# 环绕运动 — 方向分散，重力模拟向心力
	process_mat.direction = Vector3(1.0, 0.5, 1.0)
	process_mat.spread = 60.0
	process_mat.gravity = Vector3(0.0, -0.01, 0.0)
	process_mat.initial_velocity_min = 0.1
	process_mat.initial_velocity_max = 0.5
	process_mat.scale_min = 0.04
	process_mat.scale_max = 0.1
	# 深紫闪烁
	process_mat.color = Color(0.5, 0.1, 0.7, 0.6)

	# 闪烁曲线 — 忽明忽暗
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.0))
	scale_curve.add_point(Vector2(0.1, 0.9))
	scale_curve.add_point(Vector2(0.2, 0.1))
	scale_curve.add_point(Vector2(0.4, 0.7))
	scale_curve.add_point(Vector2(0.6, 0.2))
	scale_curve.add_point(Vector2(0.8, 0.5))
	scale_curve.add_point(Vector2(1.0, 0.0))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	process_mat.scale_curve = scale_tex

	_undec_particles.process_material = process_mat

	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(0.12, 0.06)
	_undec_particles.draw_pass_1 = quad_mesh

	add_child(_undec_particles)


func _setup_collision() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 4  # fog层
	body.collision_mask = 1
	body.input_ray_pickable = true
	add_child(body)

	var shape := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = _fog_radius
	shape.shape = sphere_shape
	body.add_child(shape)

	body.mouse_entered.connect(_on_mouse_entered)
	body.mouse_exited.connect(_on_mouse_exited)
	body.input_event.connect(_on_body_input_event)


func set_fog_type(type: FogType) -> void:
	fog_type = type
	_cleanup_particles()
	_setup_fog()
	_animate_fade_in()


func _cleanup_particles() -> void:
	if _semi_particles and is_instance_valid(_semi_particles):
		_semi_particles.queue_free()
		_semi_particles = null
	if _undec_particles and is_instance_valid(_undec_particles):
		_undec_particles.queue_free()
		_undec_particles = null
	if _fog_volume and is_instance_valid(_fog_volume):
		_fog_volume.queue_free()
		_fog_volume = null


func set_fog_radius(radius: float) -> void:
	_fog_radius = radius
	if _fog_volume:
		_fog_volume.set("size", Vector3(radius * 2.0, radius * 2.0, radius * 2.0))


func resolve() -> bool:
	if _is_resolved:
		return true

	if region_id < 0:
		return false

	# 触发通用的迷雾消散音效（成功/失败的具体音效在后面再播）
	SoundManager.play(SoundManager.SoundType.FOG_RESOLVE)

	var success := FogSystem.consume_core(region_id)
	if success:
		_is_resolved = true
		_animate_resolve_success()
		SoundManager.play(SoundManager.SoundType.FOG_RESOLVE_SUCCESS)
	else:
		if fog_type == FogType.UNDECIDABLE:
			_animate_resolve_fail()
			SoundManager.play(SoundManager.SoundType.FOG_RESOLVE_FAIL)
	return success


func peek() -> bool:
	if _is_resolved or _is_peeked:
		return false
	if region_id < 0:
		return false
	return FogSystem.peek_fog(region_id)


func penetrate() -> bool:
	if _is_resolved:
		return true

	if region_id < 0:
		match fog_type:
			FogType.SEMI_DECIDABLE:
				return true
			FogType.UNDECIDABLE:
				return randf() <= 0.5
			FogType.INDEPENDENT:
				return false

	return FogSystem.consume_core(region_id)


# ============ 公共动画方法 ============

func play_investigate_animation() -> void:
	# 半可判定雾调查动画: 粒子汇聚到中心, 然后向外散射, 迷雾消散
	if fog_type != FogType.SEMI_DECIDABLE:
		return

	# 粒子汇聚 — 改变重力方向向中心
	if _semi_particles and is_instance_valid(_semi_particles):
		var mat: ParticleProcessMaterial = _semi_particles.process_material
		if mat:
			mat.gravity = Vector3.ZERO
			mat.initial_velocity_min = 0.0
			mat.initial_velocity_max = 0.05
			mat.spread = 5.0  # 向中心汇聚

	# 汇聚1秒后散射
	get_tree().create_timer(1.0).timeout.connect(
		func() -> void:
			if not is_instance_valid(self):
				return
			if _semi_particles and is_instance_valid(_semi_particles):
				var mat: ParticleProcessMaterial = _semi_particles.process_material
				if mat:
					mat.gravity = Vector3.ZERO
					mat.initial_velocity_min = 0.3
					mat.initial_velocity_max = 0.8
					mat.spread = 180.0
					mat.color = Color(0.5, 0.7, 1.0, 0.9)
			# 迷雾消散
			_animate_resolve_success()
			SoundManager.play(SoundManager.SoundType.FOG_WHOOSH)
	)


func play_penetrate_animation(success: bool) -> void:
	# 不可判定雾穿透动画
	if fog_type != FogType.UNDECIDABLE:
		return

	if success:
		# 成功: 紫色粒子向内坍缩, 迷雾像幕布一样裂开3秒
		if _undec_particles and is_instance_valid(_undec_particles):
			var mat: ParticleProcessMaterial = _undec_particles.process_material
			if mat:
				mat.gravity = Vector3.ZERO
				mat.initial_velocity_min = 0.0
				mat.initial_velocity_max = 0.05
				mat.spread = 5.0
				mat.color = Color(0.7, 0.2, 1.0, 0.9)

		# 迷雾裂开 — 通过peek_opacity模拟
		if _fade_tween and _fade_tween.is_valid():
			_fade_tween.kill()
		_fade_tween = create_tween()
		_fade_tween.tween_method(_set_peek_opacity, 0.0, 0.8, 0.5).set_ease(Tween.EASE_OUT)
		# 保持3秒
		_fade_tween.tween_interval(3.0)
		# 恢复
		_fade_tween.tween_method(_set_peek_opacity, 0.8, 0.0, 0.5).set_ease(Tween.EASE_IN)

		SoundManager.play(SoundManager.SoundType.FOG_WHOOSH)
	else:
		# 失败: 紫色闪电弧 + 粒子混乱散射 + 迷雾脉冲变暗1秒
		if _undec_particles and is_instance_valid(_undec_particles):
			var mat: ParticleProcessMaterial = _undec_particles.process_material
			if mat:
				mat.gravity = Vector3.ZERO
				mat.initial_velocity_min = 0.5
				mat.initial_velocity_max = 1.2
				mat.spread = 180.0
				mat.color = Color(0.8, 0.3, 1.0, 1.0)

		# 闪电效果 — 通过shader ripple_strength
		if _fog_material:
			_fog_material.set_shader_parameter("ripple_strength", 2.5)
			get_tree().create_timer(0.5).timeout.connect(
				func() -> void:
					if _fog_material and is_instance_valid(self):
						_fog_material.set_shader_parameter("ripple_strength", 0.0)
			)

		# 迷雾脉冲变暗
		if _fade_tween and _fade_tween.is_valid():
			_fade_tween.kill()
		_fade_tween = create_tween()
		_fade_tween.tween_method(_set_fade, 1.0, 1.5, 0.2).set_ease(Tween.EASE_OUT)
		_fade_tween.tween_method(_set_fade, 1.5, 1.0, 0.8).set_ease(Tween.EASE_IN_OUT)

		SoundManager.play(SoundManager.SoundType.FOG_LIGHTNING)
		SoundManager.play(SoundManager.SoundType.FOG_THUNDER)

		# 1秒后恢复粒子
		get_tree().create_timer(1.0).timeout.connect(
			func() -> void:
				if not is_instance_valid(self):
					return
				if _undec_particles and is_instance_valid(_undec_particles):
					var mat: ParticleProcessMaterial = _undec_particles.process_material
					if mat:
						mat.gravity = Vector3(0.0, -0.01, 0.0)
						mat.initial_velocity_min = 0.1
						mat.initial_velocity_max = 0.5
						mat.spread = 60.0
						mat.color = Color(0.5, 0.1, 0.7, 0.6)
		)


func play_void_stare_animation() -> void:
	# 独立雾交互动画: 数学符号短暂发红光, 然后淡去. 虚空凝视着你.
	if fog_type != FogType.INDEPENDENT:
		return

	# 符号发红光
	if _fog_material:
		_fog_material.set_shader_parameter("symbol_glow", 1.0)
		_symbol_glow_active = true
		_symbol_glow_time = 0.0

	# 涟漪效果
	_ripple_active = true
	_ripple_time = 0.0
	if _fog_material:
		_fog_material.set_shader_parameter("ripple_strength", 0.8)

	# 深沉低音
	SoundManager.play(SoundManager.SoundType.FOG_VOID_HUM)

	# 1秒后符号和涟漪淡去
	get_tree().create_timer(1.0).timeout.connect(
		func() -> void:
			if _fog_material and is_instance_valid(self):
				_fog_material.set_shader_parameter("ripple_strength", 0.0)
	)


# ============ 内部动画 ============

func _on_fog_peeked(fog_id: int, duration: float) -> void:
	if fog_id != region_id:
		return
	_is_peeked = true
	_animate_peek(duration)
	SoundManager.play(SoundManager.SoundType.FOG_PEEK)


func _on_body_input_event(_camera: Camera3D, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		match fog_type:
			FogType.INDEPENDENT:
				# 独立雾被触碰时先播一声沉闷敲击，再播虚空低鸣
				SoundManager.play(SoundManager.SoundType.FOG_INDEPENDENT_TOUCH)
				play_void_stare_animation()
			FogType.SEMI_DECIDABLE:
				_converge_particles(_position)


func _converge_particles(target_pos: Vector3) -> void:
	if not _semi_particles or not is_instance_valid(_semi_particles):
		return
	var mat: ParticleProcessMaterial = _semi_particles.process_material
	if mat:
		var local_pos := to_local(target_pos)
		var dir := (local_pos - Vector3.ZERO).normalized() * 0.1
		mat.gravity = dir
		get_tree().create_timer(1.5).timeout.connect(
			func() -> void:
				if is_instance_valid(_semi_particles) and _semi_particles.process_material:
					_semi_particles.process_material.gravity = Vector3(0.0, 0.02, 0.0)
		)


func _animate_fade_in() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_fade, 0.0, 1.0, 0.8).set_ease(Tween.EASE_IN_OUT)


func _animate_resolve_success() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()

	# 先短暂增亮
	_fade_tween.tween_method(_set_fade, 1.0, 1.3, 0.15).set_ease(Tween.EASE_OUT)
	# 再从边缘向中心消散
	_fade_tween.tween_method(_set_fade, 1.3, 0.0, 0.8).set_ease(Tween.EASE_IN)
	_fade_tween.tween_callback(queue_free)

	# 粒子向外散射
	if _semi_particles and is_instance_valid(_semi_particles):
		var mat: ParticleProcessMaterial = _semi_particles.process_material
		if mat:
			mat.gravity = Vector3.ZERO
			mat.initial_velocity_min = 0.3
			mat.initial_velocity_max = 0.8
			mat.spread = 180.0

	if _undec_particles and is_instance_valid(_undec_particles):
		var mat: ParticleProcessMaterial = _undec_particles.process_material
		if mat:
			mat.gravity = Vector3.ZERO
			mat.initial_velocity_min = 0.3
			mat.initial_velocity_max = 0.6
			mat.spread = 180.0


func _animate_resolve_fail() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()

	# 短暂增强
	_fade_tween.tween_method(_set_fade, 1.0, 1.5, 0.2).set_ease(Tween.EASE_OUT)
	# 恢复正常
	_fade_tween.tween_method(_set_fade, 1.5, 1.0, 0.6).set_ease(Tween.EASE_IN_OUT)

	# 闪电效果
	if _fog_material:
		_fog_material.set_shader_parameter("ripple_strength", 2.0)
		get_tree().create_timer(0.5).timeout.connect(
			func() -> void:
				if _fog_material and is_instance_valid(self):
					_fog_material.set_shader_parameter("ripple_strength", 0.0)
		)


func _animate_peek(duration: float) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()

	# 降低不透明度
	_fade_tween.tween_method(_set_peek_opacity, 0.0, 0.6, 0.4).set_ease(Tween.EASE_OUT)
	# 保持一段时间（duration 太短时至少留 0.1s，别让 interval 变成负数）
	_fade_tween.tween_interval(maxf(duration - 1.0, 0.1))
	# 恢复
	_fade_tween.tween_method(_set_peek_opacity, 0.6, 0.0, 0.6).set_ease(Tween.EASE_IN)
	_fade_tween.tween_callback(func() -> void: _is_peeked = false)

	# 粒子散开
	if _semi_particles and is_instance_valid(_semi_particles):
		var mat: ParticleProcessMaterial = _semi_particles.process_material
		if mat:
			mat.gravity = Vector3.ZERO
			mat.initial_velocity_min = 0.15
			mat.initial_velocity_max = 0.3
			mat.spread = 180.0
			get_tree().create_timer(maxf(duration - 0.5, 0.1)).timeout.connect(
				func() -> void:
					if is_instance_valid(_semi_particles) and _semi_particles.process_material:
						_semi_particles.process_material.gravity = Vector3(0.0, 0.02, 0.0)
						_semi_particles.process_material.initial_velocity_min = 0.05
						_semi_particles.process_material.initial_velocity_max = 0.15
						_semi_particles.process_material.spread = 25.0
			)


func _set_fade(val: float) -> void:
	if _fog_material:
		_fog_material.set_shader_parameter("fade", val)


func _set_peek_opacity(val: float) -> void:
	if _fog_material:
		_fog_material.set_shader_parameter("peek_opacity", val)


func _on_mouse_entered() -> void:
	# 鼠标进入迷雾区域时播一声静电白噪音
	SoundManager.play(SoundManager.SoundType.FOG_ENTER)
	fog_entered.emit(self)


func _on_mouse_exited() -> void:
	fog_exited.emit(self)
