# particle_system.gd
# 粒子氛围系统 - 根据守恒矩阵状态和关卡域切换氛围效果
#
# Responsibilities:
#   - 根据守恒状态创建/更新粒子云（颜色变化）
#   - 根据关卡 domain 创建不同氛围（晶体: 光点/尘埃; 分子: 电子云; 流体: 气泡）
#   - 验证成功时的粒子爆发
#   - 不依赖外部资源，纯 GDScript + GPUParticles3D

extends Node3D

class_name ParticleSystem

# 粒子节点引用
var _clouds: GPUParticles3D = null
var _ambient: GPUParticles3D = null
var _burst: GPUParticles3D = null

# 状态颜色映射（基于色盲安全配色，附加氛围 alpha）
var _state_colors: Dictionary = {}

func _build_state_colors() -> void:
	# 从 ConservationEngine 获取色盲安全颜色，再叠加氛围透明度
	_state_colors = {
		ConservationEngine.State.HEALTHY: Color(ConservationEngine.get_state_color(0), 0.3),
		ConservationEngine.State.WARNING: Color(ConservationEngine.get_state_color(1), 0.4),
		ConservationEngine.State.CRITICAL: Color(ConservationEngine.get_state_color(2), 0.5),
		ConservationEngine.State.DISINTEGRATED: Color(ConservationEngine.get_state_color(3), 0.6),
	}

# 域氛围映射
var _domain_presets: Dictionary = {
	"crystal": {"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_BOX, "box_size": Vector3(10, 2, 10)},
	"molecular": {"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE, "sphere_radius": 8.0},
	"fluid": {"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_BOX, "box_size": Vector3(12, 8, 12)},
	"device": {"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_BOX, "box_size": Vector3(8, 4, 8)},
	"reaction": {"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE, "sphere_radius": 6.0},
	"topology": {"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_BOX, "box_size": Vector3(10, 6, 10)},
}

func _init() -> void:
	name = "ParticleSystem"

func setup(domain: String = "crystal") -> void:
	_build_state_colors()
	_create_clouds(domain)
	_create_ambient(domain)
	_create_burst()

func _create_clouds(domain: String) -> void:
	_clouds = GPUParticles3D.new()
	_clouds.name = "CloudParticles"
	_clouds.amount = 64
	_clouds.lifetime = 4.0
	_clouds.preprocess = 2.0
	_clouds.position = Vector3(0, 6, 0)

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = _domain_presets.get(domain, {}).get("emission_shape", ParticleProcessMaterial.EMISSION_SHAPE_BOX)
	if mat.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_BOX:
		mat.emission_box_extents = _domain_presets.get(domain, {}).get("box_size", Vector3(10, 2, 10))
	elif mat.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_SPHERE:
		mat.emission_sphere_radius = _domain_presets.get(domain, {}).get("sphere_radius", 8.0)

	mat.gravity = Vector3(0, -0.2, 0)
	mat.scale_min = 0.5
	mat.scale_max = 2.0
	mat.color = _state_colors[ConservationEngine.State.HEALTHY]
	mat.color_ramp = _create_ramp(_state_colors[ConservationEngine.State.HEALTHY])
	_clouds.process_material = mat

	# 使用点精灵
	var draw_pass := QuadMesh.new()
	draw_pass.size = Vector2(0.3, 0.3)
	_clouds.draw_pass_1 = draw_pass

	add_child(_clouds)

func _create_ambient(domain: String) -> void:
	_ambient = GPUParticles3D.new()
	_ambient.name = "AmbientParticles"
	_ambient.amount = 128
	_ambient.lifetime = 6.0
	_ambient.preprocess = 3.0
	_ambient.position = Vector3(0, 2, 0)

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = _domain_presets.get(domain, {}).get("emission_shape", ParticleProcessMaterial.EMISSION_SHAPE_BOX)
	if mat.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_BOX:
		mat.emission_box_extents = _domain_presets.get(domain, {}).get("box_size", Vector3(10, 4, 10))
	elif mat.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_SPHERE:
		mat.emission_sphere_radius = _domain_presets.get(domain, {}).get("sphere_radius", 8.0)

	mat.gravity = Vector3(0, 0.05, 0)
	mat.scale_min = 0.2
	mat.scale_max = 0.8
	mat.color = Color(1, 1, 1, 0.15)
	mat.color_ramp = _create_ramp(Color(1, 1, 1, 0.15))
	_ambient.process_material = mat

	var draw_pass := QuadMesh.new()
	draw_pass.size = Vector2(0.1, 0.1)
	_ambient.draw_pass_1 = draw_pass

	add_child(_ambient)

func _create_burst() -> void:
	_burst = GPUParticles3D.new()
	_burst.name = "BurstParticles"
	_burst.amount = 80
	_burst.lifetime = 1.0
	_burst.one_shot = true
	_burst.emitting = false
	_burst.position = Vector3.ZERO

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.5
	mat.initial_velocity_min = 1.5
	mat.initial_velocity_max = 4.0
	mat.gravity = Vector3(0, -2.0, 0)
	mat.scale_min = 0.2
	mat.scale_max = 0.6
	mat.color = Color(0.8, 0.7, 0.3, 0.6)
	mat.color_ramp = _create_ramp(Color(0.8, 0.7, 0.3, 0.6))
	_burst.process_material = mat

	var draw_pass := QuadMesh.new()
	draw_pass.size = Vector2(0.12, 0.12)
	_burst.draw_pass_1 = draw_pass

	add_child(_burst)

func _create_ramp(base_color: Color) -> GradientTexture1D:
	var grad := Gradient.new()
	grad.add_point(0.0, base_color)
	grad.add_point(1.0, Color(base_color.r, base_color.g, base_color.b, 0.0))
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	return tex

func update_atmosphere(state: int) -> void:
	var color: Color = _state_colors.get(state, Color.WHITE)
	if _clouds and _clouds.process_material is ParticleProcessMaterial:
		var mat := _clouds.process_material as ParticleProcessMaterial
		mat.color = color
		mat.color_ramp = _create_ramp(color)

func create_precipitation(type: String, intensity: float) -> void:
	# 雨/雪粒子系统（按需创建）
	var precip := GPUParticles3D.new()
	precip.name = "Precipitation_%s" % type
	precip.amount = int(64 * intensity)
	precip.lifetime = 2.0
	precip.position = Vector3(0, 8, 0)

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(12, 1, 12)
	mat.gravity = Vector3(0, -4.0, 0)
	mat.scale_min = 0.1
	mat.scale_max = 0.3
	if type == "snow":
		mat.color = Color(0.95, 0.95, 1.0, 0.6)
		mat.gravity = Vector3(0, -1.0, 0)
	else:
		mat.color = Color(0.7, 0.8, 0.95, 0.4)
	mat.color_ramp = _create_ramp(mat.color)
	precip.process_material = mat

	var draw_pass := QuadMesh.new()
	draw_pass.size = Vector2(0.05, 0.2) if type == "rain" else Vector2(0.08, 0.08)
	precip.draw_pass_1 = draw_pass

	add_child(precip)
	# 自动清理
	get_tree().create_timer(10.0).timeout.connect(precip.queue_free)

func create_validation_burst(position: Vector3) -> void:
	if _burst == null:
		return
	_burst.global_position = position
	_burst.restart()
	_burst.emitting = true

func clear() -> void:
	if _clouds:
		_clouds.queue_free()
		_clouds = null
	if _ambient:
		_ambient.queue_free()
		_ambient = null
	if _burst:
		_burst.queue_free()
		_burst = null
