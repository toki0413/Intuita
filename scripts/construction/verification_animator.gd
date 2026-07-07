# verification_animator.gd
# 验证动画管理器 - 从 construction_canvas.gd 拆分
#
# 负责：
#   - L0-L5 验证层动画播放
#   - 金色粒子爆发 (_spawn_golden_burst)
#   - 原子/键逐个高亮闪烁

class_name VerificationAnimator
extends RefCounted

var _host: Node3D = null
var _is_animating: bool = false

func _init(host: Node3D) -> void:
	_host = host

func is_animating() -> bool:
	return _is_animating

func play(layer: int, passed: bool, atoms: Array[Node3D], bonds: Array[Node3D] = []) -> void:
	_is_animating = true
	match layer:
		0: _animate_l0_symbolic(atoms, passed)
		1: _animate_l1_type_system(bonds, passed)
		2: _animate_l2_logic(passed)
		3: _animate_l3_llm(atoms, passed)
		4: _animate_l5_formal(atoms, passed)

func _animate_l0_symbolic(atoms: Array[Node3D], passed: bool) -> void:
	for i in range(atoms.size()):
		var atom := atoms[i]
		if not is_instance_valid(atom):
			continue
		var delay := i * 0.1
		_host.get_tree().create_timer(delay).timeout.connect(func():
			if not is_instance_valid(_host) or not is_instance_valid(atom):
				return
			var mat := atom.surface_get_material(0) as StandardMaterial3D
			if mat:
				mat.emission_enabled = true
				mat.emission = Color.WHITE
				mat.emission_energy = 2.0
				var t := atom.create_tween()
				t.tween_property(mat, "emission_energy_multiplier", 0.0, 0.15)
			SoundManager.play(SoundManager.SoundType.VERIFICATION_PASS)
		)

	var total_time := atoms.size() * 0.1 + 0.2
	_host.get_tree().create_timer(total_time).timeout.connect(func():
		if not is_instance_valid(_host):
			return
		if not passed:
			_flash_all_atoms(atoms, Color(1.0, 0.2, 0.2))
			SoundManager.play(SoundManager.SoundType.VERIFICATION_FAIL)
		_is_animating = false
	)

func _animate_l1_type_system(bonds: Array[Node3D], passed: bool) -> void:
	for i in range(bonds.size()):
		var bond := bonds[i]
		if not is_instance_valid(bond):
			continue
		var delay := i * 0.1
		_host.get_tree().create_timer(delay).timeout.connect(func():
			if not is_instance_valid(_host) or not is_instance_valid(bond):
				return
			var mat := bond.surface_get_material(0) as StandardMaterial3D
			if mat:
				mat.emission_enabled = true
				mat.emission = Color(0.0, 0.9, 0.9)
				mat.emission_energy = 2.0
				var t := bond.create_tween()
				t.tween_property(mat, "emission_energy_multiplier", 0.0, 0.15)
			SoundManager.play(SoundManager.SoundType.VERIFICATION_PASS)
		)

	var total_time := bonds.size() * 0.1 + 0.2
	_host.get_tree().create_timer(total_time).timeout.connect(func():
		if not is_instance_valid(_host):
			return
		if not passed:
			SoundManager.play(SoundManager.SoundType.VERIFICATION_FAIL)
		_is_animating = false
	)

func _animate_l2_logic(passed: bool) -> void:
	var hud := _host.get_node_or_null("../HUD/ConservationHUD")
	for i in range(4):
		var delay := i * 0.3
		_host.get_tree().create_timer(delay).timeout.connect(func():
			if not is_instance_valid(_host):
				return
			if hud and hud.has_method("flash_row"):
				hud.call("flash_row", i)
			SoundManager.play(SoundManager.SoundType.VERIFICATION_PASS, 0.8 + i * 0.1)
		)

	_host.get_tree().create_timer(1.5).timeout.connect(func():
		if not is_instance_valid(_host):
			return
		if not passed:
			SoundManager.play(SoundManager.SoundType.VERIFICATION_FAIL)
		_is_animating = false
	)

func _animate_l3_llm(atoms: Array[Node3D], passed: bool) -> void:
	for atom in atoms:
		if not is_instance_valid(atom):
			continue
		var mat := atom.surface_get_material(0) as StandardMaterial3D
		if mat:
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.85, 0.3)
			mat.emission_energy = 1.0
			var t := atom.create_tween()
			t.tween_property(mat, "emission_energy_multiplier", 0.0, 1.0)
	SoundManager.play(SoundManager.SoundType.VERIFICATION_PASS, 1.2)

	_host.get_tree().create_timer(1.5).timeout.connect(func():
		if not is_instance_valid(_host):
			return
		if not passed:
			SoundManager.play(SoundManager.SoundType.VERIFICATION_FAIL)
		_is_animating = false
	)

func _animate_l5_formal(atoms: Array[Node3D], passed: bool) -> void:
	for atom in atoms:
		if not is_instance_valid(atom):
			continue
		var mat := atom.surface_get_material(0) as StandardMaterial3D
		if mat:
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.9, 0.3)
			mat.emission_energy = 3.0
			var t := atom.create_tween()
			t.tween_property(mat, "emission_energy_multiplier", 0.0, 1.5)
		_spawn_golden_burst(atom)
		if passed and atom.has_method("apply_proof_gold"):
			atom.apply_proof_gold()
	SoundManager.play(SoundManager.SoundType.PROOF_COMPLETE)

	_host.get_tree().create_timer(2.0).timeout.connect(func():
		if not is_instance_valid(_host):
			return
		if not passed:
			SoundManager.play(SoundManager.SoundType.VERIFICATION_FAIL)
		_is_animating = false
	)

func _spawn_golden_burst(atom: Node3D) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "GoldenBurst"
	var process_mat := ParticleProcessMaterial.new()
	process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	process_mat.direction = Vector3(0, 1, 0)
	process_mat.spread = 180.0
	process_mat.gravity = Vector3.ZERO
	process_mat.initial_velocity_min = 0.5
	process_mat.initial_velocity_max = 2.0

	var color_ramp := Gradient.new()
	color_ramp.add_point(0.0, Color(1.0, 0.9, 0.3, 1.0))
	color_ramp.add_point(0.4, Color(1.0, 0.85, 0.2, 0.7))
	color_ramp.add_point(1.0, Color(1.0, 0.8, 0.1, 0.0))
	var color_tex := GradientTexture1D.new()
	color_tex.gradient = color_ramp
	process_mat.color_ramp = color_tex

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(0.5, 0.5))
	scale_curve.add_point(Vector2(1.0, 0.0))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	process_mat.scale_curve = scale_tex

	particles.process_material = process_mat
	var sphere := SphereMesh.new()
	sphere.radius = 0.04
	sphere.height = 0.08
	sphere.radial_segments = 6
	sphere.rings = 4
	particles.draw_pass_1 = sphere
	particles.amount = 12
	particles.lifetime = 0.8
	particles.one_shot = true
	particles.explosiveness = 0.8

	atom.add_child(particles)
	var cleanup_tween := atom.create_tween()
	cleanup_tween.tween_callback(particles.queue_free).set_delay(1.0)

func _flash_all_atoms(atoms: Array[Node3D], color: Color) -> void:
	# 减少闪烁模式下跳过原子集体闪烁
	if UiAnimator != null and UiAnimator.is_flashing_reduced():
		return
	for atom in atoms:
		if not is_instance_valid(atom):
			continue
		var mat := atom.surface_get_material(0) as StandardMaterial3D
		if mat:
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy = 1.5
			var t := atom.create_tween()
			t.tween_property(mat, "emission_energy_multiplier", 0.0, UiAnimator.safe_flash_duration(0.3))
