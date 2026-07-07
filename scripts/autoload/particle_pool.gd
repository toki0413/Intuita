# particle_pool.gd
# Particle effect pool - reuses particle nodes via ObjectPool
# to reduce frequent instantiation / freeing overhead

extends Node

enum ParticleType { PLACEMENT_BURST, LOCK_BURST, GOLD_BURST, DISINTEGRATION }

var _pools: Dictionary = {}
var _containers: Dictionary = {}


func _ready() -> void:
	var configs := [
		[ParticleType.PLACEMENT_BURST, "placement_burst", "res://scenes/particles/placement_burst.tscn", 8],
		[ParticleType.LOCK_BURST, "lock_burst", "res://scenes/particles/lock_burst.tscn", 6],
		[ParticleType.GOLD_BURST, "gold_burst", "res://scenes/particles/gold_burst.tscn", 6],
		[ParticleType.DISINTEGRATION, "disintegration", "res://scenes/particles/disintegration.tscn", 4],
	]

	for cfg in configs:
		var type: int = cfg[0]
		var pool_name: String = cfg[1]
		var path: String = cfg[2]
		var initial_size: int = cfg[3]

		var container := Node3D.new()
		container.name = pool_name + "_pool"
		add_child(container)
		_containers[type] = container

		var pool = ObjectPool.new(path, container, initial_size)
		if pool == null or not is_instance_valid(pool):
			push_warning("ParticlePool: 无法初始化 %s 的池" % pool_name)
			continue
		_pools[type] = pool

	# Pre-warmed particles need configuration (disintegration configures itself via script)
	_configure_warm_pool(ParticleType.PLACEMENT_BURST)
	_configure_warm_pool(ParticleType.LOCK_BURST)
	_configure_warm_pool(ParticleType.GOLD_BURST)


func acquire_particle(type: int, pos: Vector3) -> GPUParticles3D:
	if not _pools.has(type):
		push_warning("ParticlePool: 类型 %d 未初始化" % type)
		return null
	var pool: ObjectPool = _pools[type]
	if pool == null or not is_instance_valid(pool):
		push_warning("ParticlePool: 类型 %d 的池无效" % type)
		return null
	var particle: GPUParticles3D = pool.acquire()
	if particle == null:
		return null
	particle.global_position = pos

	# Lazy-configure particles created by pool expansion
	if type != ParticleType.DISINTEGRATION and particle.process_material == null:
		_configure_particle(type, particle)

	if type != ParticleType.DISINTEGRATION:
		particle.emitting = true

	return particle


func release_particle(type: int, particle: GPUParticles3D) -> void:
	if not _pools.has(type):
		push_warning("ParticlePool: 类型 %d 未初始化，无法释放" % type)
		return
	var pool: ObjectPool = _pools[type]
	if pool == null or not is_instance_valid(pool):
		push_warning("ParticlePool: 类型 %d 的池无效，无法释放" % type)
		return
	particle.emitting = false
	pool.release(particle)


func set_placement_color(particle: GPUParticles3D, color: Color) -> void:
	var mat := particle.process_material as ParticleProcessMaterial
	if mat == null:
		return
	var tex := mat.color_ramp as GradientTexture1D
	if tex == null:
		return
	var grad := tex.gradient
	if grad == null or grad.get_point_count() < 3:
		return
	grad.set_color(0, Color(color.r, color.g, color.b, 1.0))
	grad.set_color(1, Color(minf(color.r * 1.3, 1.0), minf(color.g * 1.3, 1.0), minf(color.b * 1.3, 1.0), 0.6))
	grad.set_color(2, Color(color.r, color.g, color.b, 0.0))


func _configure_warm_pool(type: int) -> void:
	var container: Node3D = _containers[type]
	for child in container.get_children():
		if child is GPUParticles3D:
			_configure_particle(type, child)


func _configure_particle(type: int, p: GPUParticles3D) -> void:
	match type:
		ParticleType.PLACEMENT_BURST:
			_configure_placement_burst(p)
		ParticleType.LOCK_BURST:
			_configure_lock_burst(p)
		ParticleType.GOLD_BURST:
			_configure_gold_burst(p)


func _configure_placement_burst(p: GPUParticles3D) -> void:
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.gravity = Vector3.ZERO
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 1.5

	var color_ramp := Gradient.new()
	color_ramp.add_point(0.0, Color.WHITE)
	color_ramp.add_point(0.5, Color(1.0, 1.0, 1.0, 0.6))
	color_ramp.add_point(1.0, Color(1.0, 1.0, 1.0, 0.0))
	var color_tex := GradientTexture1D.new()
	color_tex.gradient = color_ramp
	mat.color_ramp = color_tex

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.8))
	scale_curve.add_point(Vector2(0.4, 0.4))
	scale_curve.add_point(Vector2(1.0, 0.0))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	mat.scale_curve = scale_tex

	p.process_material = mat

	var sphere := SphereMesh.new()
	sphere.radius = 0.03
	sphere.height = 0.06
	sphere.radial_segments = 6
	sphere.rings = 4
	p.draw_pass_1 = sphere

	p.amount = 8
	p.lifetime = 0.5
	p.one_shot = true
	p.explosiveness = 0.9
	p.randomness = 0.4


func _configure_lock_burst(p: GPUParticles3D) -> void:
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.gravity = Vector3.ZERO
	mat.initial_velocity_min = 0.3
	mat.initial_velocity_max = 1.0

	var color_ramp := Gradient.new()
	color_ramp.add_point(0.0, Color(1.0, 0.85, 0.3, 1.0))
	color_ramp.add_point(0.5, Color(1.0, 0.9, 0.5, 0.6))
	color_ramp.add_point(1.0, Color(1.0, 0.85, 0.3, 0.0))
	var color_tex := GradientTexture1D.new()
	color_tex.gradient = color_ramp
	mat.color_ramp = color_tex

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.6))
	scale_curve.add_point(Vector2(0.5, 0.3))
	scale_curve.add_point(Vector2(1.0, 0.0))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	mat.scale_curve = scale_tex

	p.process_material = mat

	var sphere := SphereMesh.new()
	sphere.radius = 0.02
	sphere.height = 0.04
	sphere.radial_segments = 6
	sphere.rings = 4
	p.draw_pass_1 = sphere

	p.amount = 6
	p.lifetime = 0.4
	p.one_shot = true
	p.explosiveness = 0.9


func _configure_gold_burst(p: GPUParticles3D) -> void:
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.gravity = Vector3.ZERO
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 1.5

	var color_ramp := Gradient.new()
	color_ramp.add_point(0.0, Color(1.0, 0.9, 0.3, 1.0))
	color_ramp.add_point(0.4, Color(1.0, 0.85, 0.4, 0.7))
	color_ramp.add_point(1.0, Color(1.0, 0.8, 0.2, 0.0))
	var color_tex := GradientTexture1D.new()
	color_tex.gradient = color_ramp
	mat.color_ramp = color_tex

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.8))
	scale_curve.add_point(Vector2(0.4, 0.5))
	scale_curve.add_point(Vector2(1.0, 0.0))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	mat.scale_curve = scale_tex

	p.process_material = mat

	var sphere := SphereMesh.new()
	sphere.radius = 0.025
	sphere.height = 0.05
	sphere.radial_segments = 6
	sphere.rings = 4
	p.draw_pass_1 = sphere

	p.amount = 10
	p.lifetime = 0.5
	p.one_shot = true
	p.explosiveness = 0.85
	p.randomness = 0.3
