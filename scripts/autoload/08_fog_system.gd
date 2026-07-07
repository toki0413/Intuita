# fog_system.gd
# 迷雾/不可判定系统 - 三种迷雾类型，不同行为和消耗
# SEMI_DECIDABLE: 可用核心驱散, 蓝色粒子汇聚后散射
# UNDECIDABLE: 只能穿透，无法完全驱散, 紫色粒子环绕
# INDEPENDENT: 永远无法驱散，只能绕行, 数学符号凝视
#
# Responsibilities:
#   - 创建和管理迷雾区域
#   - 核心消耗驱散/穿透逻辑
#   - 迷雾区域位置查询
#   - 窥视/预览功能
#
# Signals:
#   fog_created(region_id, fog_type) - 迷雾区域创建
#   fog_resolved(region_id) - 迷雾被驱散
#   fog_penetrated(region_id, success) - 穿透尝试结果
#   fog_peeked(fog_id, duration) - 迷雾被窥视
#
# Dependencies:
#   - Autoload: GameState（核心消耗）

extends Node

enum FogType { SEMI_DECIDABLE, UNDECIDABLE, INDEPENDENT }

var active_fog_regions: Dictionary = {}  # region_id -> FogRegion
var _next_region_id: int = 0
var _dispelled_count: int = 0  # 累计驱散的迷雾数

# fog_volume实例引用, region_id -> FogVolume
var _fog_volumes: Dictionary = {}

signal fog_created(region_id: int, fog_type: int)
signal fog_resolved(region_id: int)
signal fog_penetrated(region_id: int, success: bool)
signal fog_peeked(fog_id: int, duration: float)


class FogRegion:
	var id: int
	var fog_type: FogType
	var position: Vector3
	var radius: float
	var core_cost: int
	var penetration_chance: float  # UNDECIDABLE类型的穿透概率
	var is_resolved: bool = false
	var is_peeked: bool = false
	var metadata: Dictionary = {}

	func _init(p_id: int, p_type: FogType, p_pos: Vector3, p_radius: float) -> void:
		id = p_id
		fog_type = p_type
		position = p_pos
		radius = p_radius
		# 不同类型的核心消耗
		match fog_type:
			FogType.SEMI_DECIDABLE:
				core_cost = 1
				penetration_chance = 1.0
			FogType.UNDECIDABLE:
				core_cost = 3
				penetration_chance = 0.5
			FogType.INDEPENDENT:
				core_cost = -1  # 不可消耗
				penetration_chance = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func reset() -> void:
	active_fog_regions.clear()
	_fog_volumes.clear()
	_next_region_id = 0
	_dispelled_count = 0


func create_fog(fog_type: FogType, position: Vector3, radius: float, meta: Dictionary = {}) -> int:
	var region := FogRegion.new(_next_region_id, fog_type, position, radius)
	region.metadata = meta
	active_fog_regions[_next_region_id] = region
	var rid := _next_region_id
	_next_region_id += 1
	fog_created.emit(rid, fog_type)
	return rid


func register_fog_volume(region_id: int, fog_volume: Node) -> void:
	_fog_volumes[region_id] = fog_volume


func consume_core(region_id: int) -> bool:
	if not active_fog_regions.has(region_id):
		push_warning("Fog region %d not found" % region_id)
		return false

	var region: FogRegion = active_fog_regions[region_id]

	if region.is_resolved:
		return true  # 已经解决

	match region.fog_type:
		FogType.SEMI_DECIDABLE:
			# 确定性驱散 - 消耗核心即可
			if not GameState.spend_cores(region.core_cost):
				return false
			region.is_resolved = true
			fog_resolved.emit(region_id)
			# 触发调查动画
			_play_fog_animation(region_id, "investigate")
			return true

		FogType.UNDECIDABLE:
			# 概率性穿透 - 消耗核心后掷骰
			if not GameState.spend_cores(region.core_cost):
				return false
			var roll := randf()
			if roll <= region.penetration_chance:
				region.is_resolved = true
				fog_resolved.emit(region_id)
				fog_penetrated.emit(region_id, true)
				# 触发穿透成功动画
				_play_fog_animation(region_id, "penetrate_success")
				return true
			else:
				fog_penetrated.emit(region_id, false)
				# 触发穿透失败动画
				_play_fog_animation(region_id, "penetrate_fail")
				return false

		FogType.INDEPENDENT:
			# 永远无法驱散
			fog_penetrated.emit(region_id, false)
			# 触发虚空凝视动画
			_play_fog_animation(region_id, "void_stare")
			return false

	return false


func _play_fog_animation(region_id: int, animation_type: String) -> void:
	var fog_volume = _fog_volumes.get(region_id)
	if fog_volume and is_instance_valid(fog_volume):
		match animation_type:
			"investigate":
				fog_volume.play_investigate_animation()
			"penetrate_success":
				fog_volume.play_penetrate_animation(true)
			"penetrate_fail":
				fog_volume.play_penetrate_animation(false)
			"void_stare":
				fog_volume.play_void_stare_animation()


func remove_fog(region_id: int) -> void:
	if _fog_volumes.has(region_id):
		var vol = _fog_volumes[region_id]
		if is_instance_valid(vol):
			vol.queue_free()
	if active_fog_regions.has(region_id):
		active_fog_regions.erase(region_id)
		_dispelled_count += 1
	_fog_volumes.erase(region_id)


func get_dispelled_count() -> int:
	return _dispelled_count


func get_fog_at_position(pos: Vector3) -> Array:
	var result: Array = []
	for region_id in active_fog_regions:
		var region: FogRegion = active_fog_regions[region_id]
		if not region.is_resolved:
			var dist := pos.distance_to(region.position)
			if dist <= region.radius:
				result.append(region)
	return result


func get_active_fog_count() -> int:
	var count := 0
	for region_id in active_fog_regions:
		if not active_fog_regions[region_id].is_resolved:
			count += 1
	return count


func _peek_or_preview(fog_id: int, duration: float, cost: int, is_preview: bool) -> bool:
	if not active_fog_regions.has(fog_id):
		push_warning("迷雾区域 %d 不存在" % fog_id)
		return false

	var region: FogRegion = active_fog_regions[fog_id]

	if region.is_resolved:
		return false

	if region.is_peeked:
		return false

	if not GameState.spend_cores(cost):
		return false

	region.is_peeked = true
	fog_peeked.emit(fog_id, duration)

	get_tree().create_timer(duration).timeout.connect(
		func() -> void:
			if active_fog_regions.has(fog_id):
				active_fog_regions[fog_id].is_peeked = false
	)

	return true


func peek_fog(fog_id: int) -> bool:
	# 花费1核心临时降低迷雾透明度5秒，不实际驱散
	return _peek_or_preview(fog_id, 5.0, 1, false)


func preview_fog(fog_id: int) -> bool:
	# 预览迷雾 - 花费1核心降低透明度5秒, 对所有类型有效
	# 与peek不同: preview不驱散, 只是暂时降低透明度
	return _peek_or_preview(fog_id, 5.0, 1, true)
