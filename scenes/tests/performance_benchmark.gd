extends Node3D
# 性能基准测试 - 大规模原子场景性能分析
# 运行方式: 在 Godot 编辑器中运行此场景，或从命令行运行
# 结果保存到: user://performance_report.csv

@export var test_atom_counts: Array[int] = [10, 50, 100, 200, 500, 1000, 2000]
@export var stabilization_frames: int = 60
@export var measurement_frames: int = 120
@export var output_path: String = "user://performance_report.csv"

var _test_index: int = 0
var _current_phase: int = 0
var _frame_counter: int = 0
var _measurements: Array[Dictionary] = []
var _atoms_container: Node3D
var _phase_names: Array[String] = ["SETUP", "STABILIZE", "MEASURE", "CLEANUP", "REPORT"]


func _ready() -> void:
	_parse_args()
	_atoms_container = Node3D.new()
	_atoms_container.name = "TestAtoms"
	add_child(_atoms_container)
	print("[性能测试] ==========================================")
	print("[性能测试] 开始基准测试...")
	print("[性能测试] 测试规模: %s" % str(test_atom_counts))
	print("[性能测试] 稳定帧数: %d, 测量帧数: %d" % [stabilization_frames, measurement_frames])
	print("[性能测试] ==========================================")
	
	# 隐藏 UI 标签（如果不需要可视化监控）
	var ui := get_node_or_null("UI")
	if ui:
		var status := ui.get_node_or_null("StatusLabel")
		if status: status.text = "性能测试: 准备中..."
		var progress := ui.get_node_or_null("ProgressBar")
		if progress: progress.max_value = test_atom_counts.size()
		var fps_label := ui.get_node_or_null("FPSLabel")
		if fps_label: fps_label.text = "FPS: -- | Atoms: 0"


func _parse_args() -> void:
	var args := OS.get_cmdline_args()
	for i in range(args.size()):
		match args[i]:
			"--atoms":
				if i + 1 < args.size():
					test_atom_counts = _parse_int_array(args[i + 1])
			"--stabilize":
				if i + 1 < args.size():
					stabilization_frames = int(args[i + 1])
			"--measure":
				if i + 1 < args.size():
					measurement_frames = int(args[i + 1])
			"--output":
				if i + 1 < args.size():
					output_path = args[i + 1]
			"--headless":
				# 隐藏 UI
				var ui := get_node_or_null("UI")
				if ui: ui.visible = false


func _parse_int_array(s: String) -> Array[int]:
	var result: Array[int] = []
	for part in s.split(","):
		result.append(int(part.strip_edges()))
	return result


func _process(_delta: float) -> void:
	_update_ui()
	match _current_phase:
		0: _setup_phase()
		1: _stabilize_phase()
		2: _measure_phase()
		3: _cleanup_phase()
		4: _report_phase()


func _update_ui() -> void:
	var ui := get_node_or_null("UI")
	if not ui:
		return
	var status := ui.get_node_or_null("StatusLabel")
	var progress := ui.get_node_or_null("ProgressBar")
	var fps_label := ui.get_node_or_null("FPSLabel")
	
	var total_phases := test_atom_counts.size() * 4
	var current_progress := _test_index * 4 + _current_phase
	if progress: progress.value = current_progress
	
	var current_atoms := test_atom_counts[_test_index] if _test_index < test_atom_counts.size() else 0
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	if fps_label: fps_label.text = "FPS: %.0f | Atoms: %d | Phase: %s" % [fps, current_atoms, _phase_names[_current_phase]]
	if status: status.text = "性能测试: %d/%d - %s (%d atoms)" % [_test_index + 1, test_atom_counts.size(), _phase_names[_current_phase], current_atoms]


func _setup_phase() -> void:
	# 清除旧原子
	for child in _atoms_container.get_children():
		child.queue_free()
	
	if _test_index >= test_atom_counts.size():
		_current_phase = 4
		return
	
	var target_count: int = test_atom_counts[_test_index]
	print("[性能测试] [%d/%d] 准备放置 %d 个原子..." % [
		_test_index + 1, test_atom_counts.size(), target_count
	])
	_place_atoms(target_count)
	_current_phase = 1
	_frame_counter = 0


func _stabilize_phase() -> void:
	_frame_counter += 1
	if _frame_counter >= stabilization_frames:
		_current_phase = 2
		_frame_counter = 0
		print("[性能测试] 稳定完成 (%d 帧)，开始测量..." % stabilization_frames)


func _measure_phase() -> void:
	_frame_counter += 1
	_record_frame()
	if _frame_counter >= measurement_frames:
		_current_phase = 3
		_frame_counter = 0
		print("[性能测试] 测量完成 (%d 帧)" % measurement_frames)


func _cleanup_phase() -> void:
	_test_index += 1
	_current_phase = 0


func _report_phase() -> void:
	_write_csv()
	_write_summary()
	_write_markdown_report()
	print("[性能测试] ==========================================")
	print("[性能测试] 报告已保存到: %s" % output_path)
	print("[性能测试] Markdown 报告已保存到: user://performance_report.md")
	print("[性能测试] 测试完成，退出...")
	print("[性能测试] ==========================================")
	get_tree().quit()


func _place_atoms(count: int) -> void:
	var grid_size: int = int(ceil(sqrt(count)))
	var spacing: float = 1.5
	
	for i in range(count):
		var atom := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.3
		mesh.height = 0.6
		mesh.radial_segments = 16
		mesh.rings = 8
		atom.mesh = mesh
		
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(randf(), randf(), randf())
		mat.metallic = 0.3
		mat.roughness = 0.4
		atom.set_surface_override_material(0, mat)
		
		var x := (i % grid_size) * spacing
		var z := (i / grid_size) * spacing
		atom.position = Vector3(x - grid_size * spacing * 0.5, 0.0, z - grid_size * spacing * 0.5)
		
		_atoms_container.add_child(atom)


func _record_frame() -> void:
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	var frame_time_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var draw_calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var primitives := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var memory_mb := Performance.get_monitor(Performance.MEMORY_STATIC) / 1024.0 / 1024.0
	var object_count := Performance.get_monitor(Performance.OBJECT_COUNT)
	var physics_time_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	
	var nav_time_ms := Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0
	var idle_time_ms := 0.0
	var vertex_mem_mb := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1024.0 / 1024.0
	var texture_mem_mb := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1024.0 / 1024.0
	var buffer_mem_mb := Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1024.0 / 1024.0
	
	_measurements.append({
		"atoms": test_atom_counts[_test_index - 1] if _test_index > 0 else 0,
		"fps": fps,
		"frame_time_ms": frame_time_ms,
		"physics_time_ms": physics_time_ms,
		"nav_time_ms": nav_time_ms,
		"idle_time_ms": idle_time_ms,
		"draw_calls": draw_calls,
		"primitives": primitives,
		"memory_mb": memory_mb,
		"vertex_mem_mb": vertex_mem_mb,
		"texture_mem_mb": texture_mem_mb,
		"buffer_mem_mb": buffer_mem_mb,
		"object_count": object_count,
	})


func _write_csv() -> void:
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if not file:
		push_error("[性能测试] 无法写入报告: %s" % output_path)
		return
	
	file.store_string("atoms,fps,frame_time_ms,physics_time_ms,nav_time_ms,idle_time_ms,draw_calls,primitives,memory_mb,vertex_mem_mb,texture_mem_mb,buffer_mem_mb,object_count\n")
	for m in _measurements:
		file.store_string("%d,%.1f,%.2f,%.2f,%.2f,%.2f,%d,%d,%.1f,%.1f,%.1f,%.1f,%d\n" % [
			m["atoms"], m["fps"], m["frame_time_ms"], m["physics_time_ms"],
			m["nav_time_ms"], m["idle_time_ms"],
			m["draw_calls"], m["primitives"], m["memory_mb"],
			m["vertex_mem_mb"], m["texture_mem_mb"], m["buffer_mem_mb"], m["object_count"]
		])
	file.close()


func _write_summary() -> void:
	# 计算每阶段的平均值并打印到控制台
	print("\n[性能测试] 汇总报告:")
	print("%-8s %-8s %-10s %-12s %-10s %-12s" % [
		"Atoms", "FPS", "Frame(ms)", "Physics(ms)", "DrawCall", "Memory(MB)"
	])
	print("-".repeat(70))
	
	var idx := 0
	for count in test_atom_counts:
		var stage_measurements: Array[Dictionary] = []
		while idx < _measurements.size() and _measurements[idx]["atoms"] == count:
			stage_measurements.append(_measurements[idx])
			idx += 1
		
		if stage_measurements.is_empty():
			continue
		
		var avg_fps := 0.0
		var avg_frame := 0.0
		var avg_physics := 0.0
		var avg_nav := 0.0
		var avg_idle := 0.0
		var avg_draw := 0.0
		var avg_mem := 0.0
		var avg_vertex_mem := 0.0
		var avg_texture_mem := 0.0
		var avg_buffer_mem := 0.0
		
		for m in stage_measurements:
			avg_fps += m["fps"]
			avg_frame += m["frame_time_ms"]
			avg_physics += m["physics_time_ms"]
			avg_nav += m["nav_time_ms"]
			avg_idle += m["idle_time_ms"]
			avg_draw += m["draw_calls"]
			avg_mem += m["memory_mb"]
			avg_vertex_mem += m["vertex_mem_mb"]
			avg_texture_mem += m["texture_mem_mb"]
			avg_buffer_mem += m["buffer_mem_mb"]
		
		var n := float(stage_measurements.size())
		avg_fps /= n
		avg_frame /= n
		avg_physics /= n
		avg_nav /= n
		avg_idle /= n
		avg_draw /= n
		avg_mem /= n
		avg_vertex_mem /= n
		avg_texture_mem /= n
		avg_buffer_mem /= n
		
		print("%-8d %-8.1f %-10.2f %-12.2f %-10.0f %-12.1f" % [
			count, avg_fps, avg_frame, avg_physics,
			avg_draw, avg_mem
		])
		
		# 瓶颈诊断
		if avg_frame > 16.6:
			var max_subsystem := "渲染"
			var max_time := avg_frame - avg_physics - avg_nav - avg_idle
			if avg_physics > max_time:
				max_time = avg_physics
				max_subsystem = "物理"
			if avg_nav > max_time:
				max_time = avg_nav
				max_subsystem = "导航"
			if avg_idle > max_time:
				max_time = avg_idle
				max_subsystem = "空闲/脚本"
			print("  ⚠️ 帧时间 %.2f ms (低于 60fps)，最长耗时子系统: %s (%.2f ms)" % [avg_frame, max_subsystem, max_time])
		
		if avg_draw > 1000:
			print("  ⚠️  Draw calls %.0f > 1000，可能存在 GPU 瓶颈" % avg_draw)
		
		if avg_mem > 500:
			print("  ⚠️  内存使用 %.1f MB > 500 MB，内存使用过高" % avg_mem)
		
		if avg_physics > 5.0:
			print("  ⚠️  物理计算 %.2f ms > 5 ms，物理计算过重" % avg_physics)
	
	print("-".repeat(70))


func _write_markdown_report() -> void:
	var md_path := "user://performance_report.md"
	var file := FileAccess.open(md_path, FileAccess.WRITE)
	if not file:
		push_error("[性能测试] 无法写入 Markdown 报告: %s" % md_path)
		return
	
	var md := "# Intuita 性能基准测试报告\n\n"
	md += "## 测试配置\n\n"
	md += "| 参数 | 值 |\n"
	md += "|------|------|\n"
	md += "| 测试原子数量 | %s |\n" % str(test_atom_counts)
	md += "| 稳定帧数 | %d |\n" % stabilization_frames
	md += "| 测量帧数 | %d |\n" % measurement_frames
	md += "| 输出路径 | %s |\n\n" % output_path
	md += "### 系统信息\n\n"
	md += "- Godot 版本: %s\n" % Engine.get_version_info()["string"]
	md += "- 操作系统: %s\n" % OS.get_name()
	md += "- 处理器: %s\n\n" % OS.get_processor_name()
	
	md += "## 汇总表格\n\n"
	md += "| Atoms | FPS | Frame(ms) | Physics(ms) | Nav(ms) | Idle(ms) | DrawCalls | Memory(MB) | Vertex(MB) | Texture(MB) | Buffer(MB) |\n"
	md += "|-------|-----|-----------|-------------|---------|----------|-----------|------------|------------|-------------|------------|\n"
	
	var idx := 0
	for count in test_atom_counts:
		var stage_measurements: Array[Dictionary] = []
		while idx < _measurements.size() and _measurements[idx]["atoms"] == count:
			stage_measurements.append(_measurements[idx])
			idx += 1
		
		if stage_measurements.is_empty():
			continue
		
		var avg_fps := 0.0
		var avg_frame := 0.0
		var avg_physics := 0.0
		var avg_nav := 0.0
		var avg_idle := 0.0
		var avg_draw := 0.0
		var avg_mem := 0.0
		var avg_vertex_mem := 0.0
		var avg_texture_mem := 0.0
		var avg_buffer_mem := 0.0
		
		for m in stage_measurements:
			avg_fps += m["fps"]
			avg_frame += m["frame_time_ms"]
			avg_physics += m["physics_time_ms"]
			avg_nav += m["nav_time_ms"]
			avg_idle += m["idle_time_ms"]
			avg_draw += m["draw_calls"]
			avg_mem += m["memory_mb"]
			avg_vertex_mem += m["vertex_mem_mb"]
			avg_texture_mem += m["texture_mem_mb"]
			avg_buffer_mem += m["buffer_mem_mb"]
		
		var n := float(stage_measurements.size())
		avg_fps /= n
		avg_frame /= n
		avg_physics /= n
		avg_nav /= n
		avg_idle /= n
		avg_draw /= n
		avg_mem /= n
		avg_vertex_mem /= n
		avg_texture_mem /= n
		avg_buffer_mem /= n
		
		md += "| %d | %.1f | %.2f | %.2f | %.2f | %.2f | %.0f | %.1f | %.1f | %.1f | %.1f |\n" % [
			count, avg_fps, avg_frame, avg_physics, avg_nav, avg_idle,
			avg_draw, avg_mem, avg_vertex_mem, avg_texture_mem, avg_buffer_mem
		]
	
	md += "\n## 瓶颈分析\n\n"
	idx = 0
	for count in test_atom_counts:
		var stage_measurements: Array[Dictionary] = []
		while idx < _measurements.size() and _measurements[idx]["atoms"] == count:
			stage_measurements.append(_measurements[idx])
			idx += 1
		
		if stage_measurements.is_empty():
			continue
		
		var avg_frame := 0.0
		var avg_physics := 0.0
		var avg_nav := 0.0
		var avg_idle := 0.0
		var avg_draw := 0.0
		var avg_mem := 0.0
		
		for m in stage_measurements:
			avg_frame += m["frame_time_ms"]
			avg_physics += m["physics_time_ms"]
			avg_nav += m["nav_time_ms"]
			avg_idle += m["idle_time_ms"]
			avg_draw += m["draw_calls"]
			avg_mem += m["memory_mb"]
		
		var n := float(stage_measurements.size())
		avg_frame /= n
		avg_physics /= n
		avg_nav /= n
		avg_idle /= n
		avg_draw /= n
		avg_mem /= n
		
		md += "### %d Atoms\n\n" % count
		
		if avg_frame > 16.6:
			var max_subsystem := "渲染"
			var max_time := avg_frame - avg_physics - avg_nav - avg_idle
			if avg_physics > max_time:
				max_time = avg_physics
				max_subsystem = "物理"
			if avg_nav > max_time:
				max_time = avg_nav
				max_subsystem = "导航"
			if avg_idle > max_time:
				max_time = avg_idle
				max_subsystem = "空闲/脚本"
			md += "- ⚠️ 帧时间 %.2f ms (低于 60fps)，最长耗时子系统: **%s** (%.2f ms)\n" % [avg_frame, max_subsystem, max_time]
		
		if avg_draw > 1000:
			md += "- ⚠️ Draw calls %.0f > 1000，可能存在 **GPU 瓶颈**\n" % avg_draw
		
		if avg_mem > 500:
			md += "- ⚠️ 内存使用 %.1f MB > 500 MB，**内存使用过高**\n" % avg_mem
		
		if avg_physics > 5.0:
			md += "- ⚠️ 物理计算 %.2f ms > 5 ms，**物理计算过重**\n" % avg_physics
		
		md += "\n"
	
	md += "## 建议\n\n"
	md += "1. 若帧时间 > 16.6 ms，优先分析最长耗时子系统，考虑优化或降级对应模块。\n"
	md += "2. 若 Draw Calls > 1000，尝试使用多实例渲染（MultiMesh）或合并网格减少绘制调用。\n"
	md += "3. 若内存 > 500 MB，检查纹理压缩、模型 LOD 和资源卸载策略。\n"
	md += "4. 若物理计算 > 5 ms，减少碰撞体复杂度、降低物理更新频率或使用简化的物理代理。\n"
	md += "5. 大规模原子场景建议使用 GPU 粒子或实例化渲染替代独立 MeshInstance3D。\n"
	
	file.store_string(md)
	file.close()
