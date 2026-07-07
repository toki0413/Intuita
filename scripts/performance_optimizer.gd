# performance_optimizer.gd
# 动态性能优化器 - 根据帧率自动调整渲染质量
# 在大型原子场景（2000+ 原子）下保持可玩 FPS
#
# Responsibilities:
#   - 监控实时 FPS
#   - 根据 FPS 阈值切换渲染质量预设
#   - 提供材质/阴影/后处理的动态降级
#   - 在性能恢复后自动升级质量
#
# Usage:
#   - AutoLoad: 作为全局单例挂载，或在 GameState 中初始化
#   - Manual: PerformanceOptimizer.apply_preset("balanced")
#
# Dependencies:
#   - WorldEnvironment 节点（场景中的环境）
#   - DirectionalLight3D 节点（主光源）

class_name PerformanceOptimizer
extends Node

enum Preset {
	HIGH_QUALITY,    # 最高画质（原子数 < 100 或 FPS > 60）
	BALANCED,        # 平衡画质（默认，原子数 < 500 或 FPS > 45）
	LOW_QUALITY,     # 低画质（原子数 > 1000 或 FPS < 30）
	MINIMUM,         # 最低画质（FPS < 20，确保可玩）
}

# FPS 阈值（每 N 帧评估一次）
@export var check_interval_frames: int = 60
@export var fps_threshold_high: float = 55.0
@export var fps_threshold_low: float = 30.0
@export var fps_threshold_critical: float = 20.0

# 当前预设
var _current_preset: Preset = Preset.BALANCED
var _frame_count: int = 0
var _fps_history: Array[float] = []
const FPS_HISTORY_SIZE := 10

# 场景引用（延迟获取）
var _world_env: WorldEnvironment = null
var _main_light: DirectionalLight3D = null
var _camera: Camera3D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 延迟获取场景节点（避免 _ready 时场景未完全加载）
	call_deferred("_find_scene_nodes")
	apply_preset(Preset.BALANCED)


func _find_scene_nodes() -> void:
	# 在当前场景树中查找关键渲染节点
	var root := get_tree().current_scene
	if root == null:
		return
	
	_world_env = root.find_child("WorldEnvironment", true, false)
	_main_light = root.find_child("DirectionalLight3D", true, false)
	_camera = root.find_child("Camera3D", true, false)
	
	# 如果找不到，尝试遍历
	if _world_env == null:
		for child in root.find_children("*", "WorldEnvironment", true, false):
			_world_env = child
			break
	if _main_light == null:
		for child in root.find_children("*", "DirectionalLight3D", true, false):
			_main_light = child
			break


func _process(_delta: float) -> void:
	_frame_count += 1
	if _frame_count % check_interval_frames != 0:
		return
	
	var fps := Engine.get_frames_per_second()
	_fps_history.append(fps)
	if _fps_history.size() > FPS_HISTORY_SIZE:
		_fps_history.pop_front()
	
	# 使用平均 FPS 做决策，避免瞬时波动
	var avg_fps := _average_fps()
	
	match _current_preset:
		Preset.HIGH_QUALITY:
			if avg_fps < fps_threshold_low:
				apply_preset(Preset.BALANCED)
		Preset.BALANCED:
			if avg_fps < fps_threshold_critical:
				apply_preset(Preset.MINIMUM)
			elif avg_fps < fps_threshold_low:
				apply_preset(Preset.LOW_QUALITY)
			elif avg_fps > fps_threshold_high + 10.0:
				apply_preset(Preset.HIGH_QUALITY)
		Preset.LOW_QUALITY:
			if avg_fps < fps_threshold_critical:
				apply_preset(Preset.MINIMUM)
			elif avg_fps > fps_threshold_high:
				apply_preset(Preset.BALANCED)
		Preset.MINIMUM:
			if avg_fps > fps_threshold_low + 5.0:
				apply_preset(Preset.LOW_QUALITY)
			elif avg_fps > fps_threshold_high:
				apply_preset(Preset.BALANCED)


func _average_fps() -> float:
	if _fps_history.is_empty():
		return 60.0
	var sum := 0.0
	for f in _fps_history:
		sum += f
	return sum / _fps_history.size()


func apply_preset(preset: Preset) -> void:
	if _current_preset == preset:
		return

	# 确保场景节点引用仍然有效，场景切换后需重新获取
	_ensure_scene_nodes()

	_current_preset = preset
	var preset_name: String = Preset.keys()[preset]
	push_warning("PerformanceOptimizer: 切换到 %s 预设" % preset_name)
	
	match preset:
		Preset.HIGH_QUALITY:
			_apply_high_quality()
		Preset.BALANCED:
			_apply_balanced()
		Preset.LOW_QUALITY:
			_apply_low_quality()
		Preset.MINIMUM:
			_apply_minimum()
	
	# 触发信号（如果有监听器）
	emit_signal("preset_changed", preset)


# 高画质 - 全开效果
func _apply_high_quality() -> void:
	# 世界环境
	if _world_env and _world_env.environment:
		var env := _world_env.environment
		env.ssao_enabled = true
		env.ssr_enabled = true
		env.glow_enabled = true
		env.fog_enabled = true
		env.ssil_enabled = true
		env.sdfgi_enabled = true
	
	# 阴影
	if _main_light:
		_main_light.shadow_enabled = true
		_main_light.shadow_map_size = DirectionalLight3D.SHADOW_MAP_SIZE_4096
		_main_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	
	# 视距/LOD
	if _camera:
		_camera.attributes.dof_blur_near_enabled = true
	
	# 全局渲染设置
	RenderingServer.viewport_set_msaa_3d(get_viewport().get_viewport_rid(), RenderingServer.VIEWPORT_MSAA_4X)
	get_viewport().mesh_lod_threshold = 1.0


# 平衡画质 - 默认
func _apply_balanced() -> void:
	if _world_env and _world_env.environment:
		var env := _world_env.environment
		env.ssao_enabled = true
		env.ssao_quality = Environment.SSAOQuality.SSAO_QUALITY_MEDIUM
		env.ssr_enabled = true
		env.ssr_max_steps = 32
		env.glow_enabled = true
		env.glow_intensity = 0.3
		env.fog_enabled = true
		env.fog_density = 0.04
		env.ssil_enabled = false
		env.sdfgi_enabled = false
	
	if _main_light:
		_main_light.shadow_enabled = true
		_main_light.shadow_map_size = DirectionalLight3D.SHADOW_MAP_SIZE_2048
		_main_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	
	if _camera and is_instance_valid(_camera) and _camera.attributes:
		_camera.attributes.dof_blur_near_enabled = false

	RenderingServer.viewport_set_msaa_3d(get_viewport().get_viewport_rid(), RenderingServer.VIEWPORT_MSAA_2X)
	get_viewport().mesh_lod_threshold = 2.0


# 低画质 - 关闭昂贵效果
func _apply_low_quality() -> void:
	if _world_env and _world_env.environment:
		var env := _world_env.environment
		env.ssao_enabled = false
		env.ssr_enabled = false
		env.glow_enabled = false
		env.fog_enabled = false
		env.ssil_enabled = false
		env.sdfgi_enabled = false
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.3, 0.3, 0.3)
		env.ambient_light_energy = 0.5
	
	if _main_light:
		_main_light.shadow_enabled = true
		_main_light.shadow_map_size = DirectionalLight3D.SHADOW_MAP_SIZE_1024
		_main_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		_main_light.shadow_bias = 0.1
	
	if _camera and is_instance_valid(_camera) and _camera.attributes:
		_camera.attributes.dof_blur_near_enabled = false

	RenderingServer.viewport_set_msaa_3d(get_viewport().get_viewport_rid(), RenderingServer.VIEWPORT_MSAA_DISABLED)
	get_viewport().mesh_lod_threshold = 4.0
	
	# 降低远处细节
	get_viewport().positional_shadow_atlas_size = 1024


# 最低画质 - 确保可玩
func _apply_minimum() -> void:
	if _world_env and _world_env.environment:
		var env := _world_env.environment
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.1, 0.1, 0.1)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_energy = 0.3
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env.ssao_enabled = false
		env.ssr_enabled = false
		env.glow_enabled = false
		env.fog_enabled = false
		env.reflection_source = Environment.REFLECTION_SOURCE_DISABLED
	
	if _main_light:
		_main_light.shadow_enabled = false
		_main_light.light_energy = 1.0
	
	if _camera and is_instance_valid(_camera):
		if _camera.attributes:
			_camera.attributes.dof_blur_near_enabled = false
		_camera.far = 50.0  # 缩短视距
	
	RenderingServer.viewport_set_msaa_3d(get_viewport().get_viewport_rid(), RenderingServer.VIEWPORT_MSAA_DISABLED)
	get_viewport().mesh_lod_threshold = 8.0
	get_viewport().positional_shadow_atlas_size = 512


# 公共 API：获取当前预设
func get_current_preset() -> Preset:
	return _current_preset


# 检查场景节点引用是否仍然有效，无效则重新获取
func _ensure_scene_nodes() -> void:
	var need_refresh := false
	if _world_env != null and not is_instance_valid(_world_env):
		_world_env = null
		need_refresh = true
	if _main_light != null and not is_instance_valid(_main_light):
		_main_light = null
		need_refresh = true
	if _camera != null and not is_instance_valid(_camera):
		_camera = null
		need_refresh = true
	if need_refresh or (_world_env == null and _main_light == null and _camera == null):
		_find_scene_nodes()


# 公共 API：强制刷新场景节点引用（场景切换后调用）
func refresh_scene_nodes() -> void:
	_find_scene_nodes()


# 信号
signal preset_changed(preset: Preset)
