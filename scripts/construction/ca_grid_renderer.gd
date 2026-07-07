# ca_grid_renderer.gd
# 3D 元胞自动机网格渲染器
# 活细胞 = 发光球体, 死细胞 = 半透明线框立方体
# 支持点击切换细胞状态, 演化动画

extends Node3D

const CellularAutomatonEngine = preload("res://scripts/simulation/cellular_automaton_engine.gd")

signal cell_toggled(x: int, y: int, z: int, alive: int)

var engine: CellularAutomatonEngine = null

var _cell_size: float = 1.0
var _alive_instances: Array[MeshInstance3D] = []
var _dead_markers: Array[MeshInstance3D] = []
var _alive_material: StandardMaterial3D = null
var _dead_material: StandardMaterial3D = null
var _birth_material: StandardMaterial3D = null
var _death_material: StandardMaterial3D = null

var _prev_alive: PackedByteArray = PackedByteArray()
var _animating: bool = false
var _auto_evolve: bool = false
var _auto_evolve_timer: float = 0.0
var _auto_evolve_interval: float = 0.5

# 演化控制
var _evolution_paused: bool = true


func _ready() -> void:
	_build_materials()
	_setup_input()


func _build_materials() -> void:
	# 活细胞: 青色发光
	_alive_material = StandardMaterial3D.new()
	_alive_material.albedo_color = Color(0, 0.831, 1, 0.9)
	_alive_material.emission_enabled = true
	_alive_material.emission = Color(0, 0.6, 0.9, 1)
	_alive_material.emission_energy_multiplier = 1.5
	_alive_material.roughness = 0.2
	_alive_material.metallic = 0.3

	# 死细胞: 暗灰半透明
	_dead_material = StandardMaterial3D.new()
	_dead_material.albedo_color = Color(0.3, 0.3, 0.35, 0.08)
	_dead_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dead_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# 新生细胞: 绿色闪光
	_birth_material = StandardMaterial3D.new()
	_birth_material.albedo_color = Color(0.3, 0.95, 0.4, 0.95)
	_birth_material.emission_enabled = true
	_birth_material.emission = Color(0.2, 0.8, 0.3, 1)
	_birth_material.emission_energy_multiplier = 2.0

	# 死亡细胞: 红色淡出
	_death_material = StandardMaterial3D.new()
	_death_material.albedo_color = Color(0.95, 0.3, 0.2, 0.6)
	_death_material.emission_enabled = true
	_death_material.emission = Color(0.8, 0.2, 0.1, 1)
	_death_material.emission_energy_multiplier = 1.5


func _setup_input() -> void:
	# 确保可以接收输入
	if get_viewport():
		get_viewport().gui_disable_input = false


func initialize(ca_engine: CellularAutomatonEngine, cell_size: float = 1.0) -> void:
	engine = ca_engine
	_cell_size = cell_size
	_build_grid()
	_update_visuals()


func _build_grid() -> void:
	# 清除旧网格
	for child in get_children():
		child.queue_free()
	_alive_instances.clear()
	_dead_markers.clear()

	if engine == null:
		return

	var total := engine.size_x * engine.size_y * engine.size_z
	_alive_instances.resize(total)
	_dead_markers.resize(total)
	_prev_alive.resize(total)
	_prev_alive.fill(0)

	var sphere := SphereMesh.new()
	sphere.radius = _cell_size * 0.35
	sphere.height = _cell_size * 0.7
	sphere.radial_segments = 16
	sphere.rings = 8

	var box := BoxMesh.new()
	box.size = Vector3(_cell_size * 0.9, _cell_size * 0.9, _cell_size * 0.9)

	var offset := Vector3(
		-(engine.size_x - 1) * _cell_size * 0.5,
		-(engine.size_y - 1) * _cell_size * 0.5,
		-(engine.size_z - 1) * _cell_size * 0.5
	)

	for x in range(engine.size_x):
		for y in range(engine.size_y):
			for z in range(engine.size_z):
				var i := engine.idx(x, y, z)
				var pos := offset + Vector3(x, y, z) * _cell_size

				# 活细胞实例
				var alive_mi := MeshInstance3D.new()
				alive_mi.mesh = sphere
				alive_mi.material_override = _alive_material
				alive_mi.position = pos
				alive_mi.visible = false
				add_child(alive_mi)
				_alive_instances[i] = alive_mi

				# 死细胞标记 (线框立方体)
				var dead_mi := MeshInstance3D.new()
				dead_mi.mesh = box
				dead_mi.material_override = _dead_material
				dead_mi.position = pos
				dead_mi.visible = true
				add_child(dead_mi)
				_dead_markers[i] = dead_mi


func _update_visuals() -> void:
	if engine == null:
		return

	for x in range(engine.size_x):
		for y in range(engine.size_y):
			for z in range(engine.size_z):
				var i := engine.idx(x, y, z)
				var alive := engine.get_cell(x, y, z) == 1
				var was_alive := _prev_alive[i] == 1

				var alive_mi := _alive_instances[i]
				var dead_mi := _dead_markers[i]

				if alive_mi:
					alive_mi.visible = alive
					# 新生细胞用绿色, 存活用青色
					if alive and not was_alive:
						alive_mi.material_override = _birth_material
						_play_spawn_anim(alive_mi)
					elif alive:
						alive_mi.material_override = _alive_material

				if dead_mi:
					# 死细胞标记: 只在网格较小时显示
					dead_mi.visible = not alive and engine.size_x <= 12
					# 刚死亡的细胞闪红
					if not alive and was_alive:
						dead_mi.material_override = _death_material
						_play_death_anim(dead_mi)
					else:
						dead_mi.material_override = _dead_material

	# 更新历史
	_prev_alive = engine.get_cells()


func _play_spawn_anim(node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	var tween := create_tween()
	node.scale = Vector3(0.1, 0.1, 0.1)
	tween.tween_property(node, "scale", Vector3(1, 1, 1), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _play_death_anim(node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	var tween := create_tween()
	tween.tween_property(node, "scale", Vector3(1.2, 1.2, 1.2), 0.1)
	tween.tween_property(node, "scale", Vector3(1, 1, 1), 0.15)


# ---- 演化控制 ----

func evolve_step() -> void:
	if engine == null:
		return
	engine.step()
	_update_visuals()
	_apply_conservation_perturbation()


func evolve_n(n: int) -> void:
	if engine == null:
		return
	for i in range(n):
		engine.step()
	_update_visuals()
	_apply_conservation_perturbation()


func toggle_auto_evolve() -> bool:
	_evolution_paused = not _evolution_paused
	return not _evolution_paused


func set_auto_evolve_interval(seconds: float) -> void:
	_auto_evolve_interval = clampf(seconds, 0.1, 5.0)


func is_evolution_running() -> bool:
	return not _evolution_paused


func _process(delta: float) -> void:
	if _evolution_paused or engine == null:
		return
	_auto_evolve_timer += delta
	if _auto_evolve_timer >= _auto_evolve_interval:
		_auto_evolve_timer = 0.0
		evolve_step()


func _apply_conservation_perturbation() -> void:
	if engine == null:
		return
	var pert := engine.get_conservation_perturbation()
	# 接入守恒引擎
	var ce := get_node_or_null("/root/ConservationEngine")
	if ce == null:
		return
	var mass_d: float = pert.get("mass", 0.0)
	var mom_d: float = pert.get("momentum", 0.0)
	var energy_d: float = pert.get("energy", 0.0)
	if absf(mass_d) > 0.001:
		ce.apply_perturbation(0, 0, mass_d, "ca_evolve_mass")
	if absf(mom_d) > 0.001:
		ce.apply_perturbation(2, 2, mom_d, "ca_evolve_momentum")
	if absf(energy_d) > 0.001:
		ce.apply_perturbation(3, 3, energy_d, "ca_evolve_energy")


# ---- 点击交互 ----

func _input(event: InputEvent) -> void:
	if engine == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click(event)


func _handle_click(event: InputEventMouseButton) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var from := camera.project_ray_origin(event.position)
	var dir := camera.project_ray_normal(event.position)

	# 射线检测最近的网格点
	var best_cell: Array[int] = [-1, -1, -1]
	var best_dist := 9999.0
	var offset := Vector3(
		-(engine.size_x - 1) * _cell_size * 0.5,
		-(engine.size_y - 1) * _cell_size * 0.5,
		-(engine.size_z - 1) * _cell_size * 0.5
	)

	for x in range(engine.size_x):
		for y in range(engine.size_y):
			for z in range(engine.size_z):
				var cell_pos := offset + Vector3(x, y, z) * _cell_size
				# 射线到球心距离
				var to_center := cell_pos - from
				var proj := to_center.dot(dir)
				if proj < 0:
					continue
				var closest := from + dir * proj
				var dist := closest.distance_to(cell_pos)
				if dist < _cell_size * 0.5 and proj < best_dist:
					best_dist = proj
					best_cell = [x, y, z]

	if best_cell[0] >= 0:
		var x := best_cell[0]
		var y := best_cell[1]
		var z := best_cell[2]
		var new_state := engine.toggle_cell(x, y, z)
		_update_visuals()
		cell_toggled.emit(x, y, z, new_state)


# ---- 状态查询 ----

func get_phase_state() -> String:
	if engine:
		return engine._phase_state
	return "unknown"


func get_stats() -> Dictionary:
	if engine == null:
		return {}
	return {
		"step": engine.get_step_count(),
		"alive": engine.get_alive_count(),
		"density": engine.get_density(),
		"phase": get_phase_state(),
		"rule": "B%s/S%s" % [
			"".join(engine.birth_rules.map(func(n): return str(n))),
			"".join(engine.survival_rules.map(func(n): return str(n)))
		],
		"running": not _evolution_paused,
	}
