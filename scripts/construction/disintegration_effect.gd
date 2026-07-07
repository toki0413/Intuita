# disintegration_effect.gd
# 瓦解粒子效果 - 原子崩溃时的红橙色火花
# 1.5秒后自动释放回ParticlePool
#
# Responsibilities:
#   - 瓦解粒子系统配置
#   - 跟随目标原子位置
#   - 自动释放回对象池
#
# Dependencies:
#   - ParticlePool autoload

extends GPUParticles3D

var _target_atom: Node3D = null
var _lifetime_total: float = 1.5
var _elapsed: float = 0.0
var _started: bool = false


func _ready() -> void:
	_setup_particles()
	# Don't auto-start; wait for start() call from pool
	emitting = false
	set_process(false)


func start(atom: Node3D) -> void:
	_target_atom = atom
	if atom:
		global_position = atom.global_position
	_elapsed = 0.0
	_started = true
	emitting = true
	set_process(true)


func set_target(atom: Node3D) -> void:
	_target_atom = atom
	if atom:
		global_position = atom.global_position


func _setup_particles() -> void:
	# 粒子数量
	amount = 64

	# 处理材质
	var process_mat := ParticleProcessMaterial.new()
	process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	process_mat.direction = Vector3(0, 1, 0)
	process_mat.spread = 180.0
	process_mat.gravity = Vector3(0, -2.0, 0)  # 轻微下坠

	# 初始速度 - 向外飞散
	process_mat.initial_velocity_min = 1.5
	process_mat.initial_velocity_max = 4.0

	# 随机旋转
	process_mat.angular_velocity_min = -5.0
	process_mat.angular_velocity_max = 5.0

	# 缩放曲线 - 从大到小
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(0.5, 0.6))
	scale_curve.add_point(Vector2(1.0, 0.0))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	process_mat.scale_curve = scale_tex

	# 颜色: 红橙渐变
	var color_ramp := Gradient.new()
	color_ramp.add_point(0.0, Color(1.0, 0.6, 0.1, 1.0))   # 橙色
	color_ramp.add_point(0.3, Color(1.0, 0.3, 0.05, 0.9))   # 红橙
	color_ramp.add_point(0.7, Color(0.9, 0.1, 0.0, 0.5))    # 红色
	color_ramp.add_point(1.0, Color(0.5, 0.0, 0.0, 0.0))    # 暗红消失

	var color_curve := GradientTexture1D.new()
	color_curve.gradient = color_ramp
	process_mat.color_ramp = color_curve

	process_material = process_mat

	# 粒子mesh
	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(0.1, 0.1)
	draw_pass_1 = quad_mesh

	# 生命周期
	lifetime = _lifetime_total
	one_shot = true
	explosiveness = 0.8
	randomness = 0.3


func _process(delta: float) -> void:
	if not _started:
		return

	_elapsed += delta

	# 跟随目标原子位置（如果还在瓦解过程中）
	if _target_atom and is_instance_valid(_target_atom) and _target_atom.is_inside_tree():
		global_position = _target_atom.global_position

	if _elapsed >= _lifetime_total + 0.5:
		_release_to_pool()


func _release_to_pool() -> void:
	_started = false
	emitting = false
	ParticlePool.release_particle(ParticlePool.ParticleType.DISINTEGRATION, self)
