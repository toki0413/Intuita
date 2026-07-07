# dynamic_difficulty.gd
# 动态难度调整 - 根据玩家表现实时调整关卡参数

class_name DynamicDifficulty
extends RefCounted

var _level_manager: Node = null

# 追踪玩家行为
var _placement_count: int = 0
var _undo_count: int = 0
var _verify_attempts: int = 0
var _verify_failures: int = 0
var _avg_placement_time: float = 0.0
var _last_placement_time: float = 0.0
var _total_level_time: float = 0.0

# 难度调整状态
var _difficulty_modifier: float = 1.0  # 1.0 = 正常, <1 = 更简单, >1 = 更难
var _hint_level: int = 0  # 0=无提示, 1=基本, 2=详细
var _fog_density_modifier: float = 1.0
var _instability_modifier: float = 1.0

func _init(level_manager: Node) -> void:
	_level_manager = level_manager

func on_level_start() -> void:
	_placement_count = 0
	_undo_count = 0
	_verify_attempts = 0
	_verify_failures = 0
	_avg_placement_time = 0.0
	_last_placement_time = Time.get_ticks_msec() / 1000.0
	_total_level_time = 0.0
	_difficulty_modifier = 1.0
	_hint_level = 0
	_fog_density_modifier = 1.0
	_instability_modifier = 1.0

func on_atom_placed() -> void:
	_placement_count += 1
	var now: float = Time.get_ticks_msec() / 1000.0
	var dt: float = now - _last_placement_time
	if _avg_placement_time == 0.0:
		_avg_placement_time = dt
	else:
		_avg_placement_time = _avg_placement_time * 0.7 + dt * 0.3
	_last_placement_time = now
	
	_update_difficulty()

func on_undo() -> void:
	_undo_count += 1
	# 频繁撤销 → 降低难度，增加提示
	if _undo_count >= 3 and _hint_level < 1:
		_hint_level = 1
		_show_hint("提示: 观察守恒矩阵的变化趋势")
	if _undo_count >= 6 and _hint_level < 2:
		_hint_level = 2
		_show_hint("详细提示: 尝试先放置较轻的元素来稳定基础结构")

func on_verify(attempted: bool, passed: bool) -> void:
	_verify_attempts += 1
	if attempted and not passed:
		_verify_failures += 1
		# 验证失败 → 降低瓦解阈值，给玩家更多容错
		_instability_modifier = maxf(0.5, _instability_modifier - 0.1)
	elif attempted and passed:
		# 验证成功 → 恢复正常
		_instability_modifier = minf(1.5, _instability_modifier + 0.05)
	
	_update_difficulty()

func _update_difficulty() -> void:
	# 基于玩家表现计算难度调整
	var speed_factor: float = 1.0
	if _avg_placement_time < 1.0:
		speed_factor = 1.2  # 快速放置 → 增加难度
	elif _avg_placement_time > 5.0:
		speed_factor = 0.8  # 慢速放置 → 降低难度
	
	var accuracy_factor: float = 1.0
	if _verify_attempts > 0:
		var success_rate: float = float(_verify_attempts - _verify_failures) / float(_verify_attempts)
		accuracy_factor = 0.7 + (1.0 - success_rate) * 0.6
	
	var undo_factor: float = 1.0
	if _undo_count > _placement_count * 0.5:
		undo_factor = 0.8  # 频繁撤销 → 降低难度
	
	_difficulty_modifier = clampf((speed_factor + accuracy_factor + undo_factor) / 3.0, 0.5, 1.5)
	
	# 应用难度调整
	_apply_difficulty()

func _apply_difficulty() -> void:
	if _level_manager == null:
		return
	
	# 调整不稳定性累积速率
	_level_manager._instability_modifier = _instability_modifier
	
	# 调整迷雾密度（如果存在迷雾系统）
	var fog_system = Engine.get_main_loop().root.get_node_or_null("/root/FogSystem")
	if fog_system != null and fog_system.has_method("set_density_multiplier"):
		fog_system.set_density_multiplier(_fog_density_modifier * _difficulty_modifier)

func get_difficulty_info() -> Dictionary:
	return {
		"modifier": _difficulty_modifier,
		"hint_level": _hint_level,
		"instability_mod": _instability_modifier,
		"placement_count": _placement_count,
		"undo_count": _undo_count,
		"verify_success_rate": float(_verify_attempts - _verify_failures) / maxi(_verify_attempts, 1),
	}

func _show_hint(text: String) -> void:
	# 通过 GameLogger 显示提示
	if GameLogger != null:
		GameLogger.info("Tutorial", text)
