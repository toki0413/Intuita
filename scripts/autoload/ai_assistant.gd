extends Node
# AI助手 - 30分钟后解锁，提供关卡提示和守恒诊断
# 每次提示消耗1个验证核心，每关最多3次

signal assistant_unlocked
signal hint_requested(cost: int)
signal hint_delivered(text: String)

const UNLOCK_MINUTES := 30.0
const MAX_HINTS_PER_LEVEL := 3
const HINT_CORE_COST := 1

var _total_playtime: float = 0.0
var _is_unlocked: bool = false
var _hints_used_this_level: int = 0
var _panel: Control = null


var _on_level_loaded_conn: Callable

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_on_level_loaded_conn = _on_level_loaded
	if LevelManager != null:
		LevelManager.level_loaded.connect(_on_level_loaded_conn)

func _exit_tree() -> void:
	if LevelManager != null and LevelManager.level_loaded.is_connected(_on_level_loaded_conn):
		LevelManager.level_loaded.disconnect(_on_level_loaded_conn)


func _process(delta: float) -> void:
	if _is_unlocked:
		return
	_total_playtime += delta
	if _total_playtime >= UNLOCK_MINUTES * 60.0:
		_unlock()


func is_unlocked() -> bool:
	return _is_unlocked


func get_playtime_minutes() -> float:
	return _total_playtime / 60.0


func get_hints_remaining() -> int:
	return MAX_HINTS_PER_LEVEL - _hints_used_this_level


func request_hint() -> String:
	if not _is_unlocked:
		return ""
	if _hints_used_this_level >= MAX_HINTS_PER_LEVEL:
		return "本关提示次数已用完"
	if not GameState.spend_cores(HINT_CORE_COST):
		return "核心不足，无法获取提示"

	_hints_used_this_level += 1
	if LevelManager != null and LevelManager.has_method("increment_metric"):
		LevelManager.increment_metric("hint_count")
	var hint_text := _generate_hint()
	hint_delivered.emit(hint_text)
	return hint_text


func set_panel(panel: Control) -> void:
	_panel = panel


func _unlock() -> void:
	_is_unlocked = true
	assistant_unlocked.emit()
	GameLogger.info("AIAssistant", "[助手] 已解锁 - 累计游玩%.1f分钟" % (_total_playtime / 60.0))


func set_unlocked(value: bool) -> void:
	_is_unlocked = value


func _on_level_loaded(_data: Dictionary) -> void:
	_hints_used_this_level = 0


func _generate_hint() -> String:
	# 从关卡数据推导提示，不依赖LLM
	var goals: Array = LevelManager.goals
	var goal_states: Array = LevelManager.goal_states
	var incomplete_goals: Array[Dictionary] = []

	for i in range(goals.size()):
		if goal_states[i] != LevelManager.GoalState.COMPLETED:
			incomplete_goals.append({"index": i, "goal": goals[i], "state": goal_states[i]})

	if incomplete_goals.is_empty():
		return "所有目标已完成！试试右键验证吧。"

	# 找最优先的未完成目标
	var primary := incomplete_goals[0]
	var goal_type: String = primary["goal"]["type"]

	match goal_type:
		"wyckoff_fill":
			var element: String = primary["goal"].get("element", "?")
			var wyckoff: String = primary["goal"].get("wyckoff", "?")
			var required: int = primary["goal"].get("required_count", 0)
			return "将%s放置到%s位置（需要%d个）。点击Wyckoff标记选择元素。" % [element, wyckoff, required]

		"conservation_check":
			return _diagnose_conservation()

		"verification":
			return "右键点击或按空格键触发验证。验证会消耗核心但确认结构正确性。"

		"symmetry_check":
			var src: int = primary["goal"].get("source_sg", 0)
			var tgt: int = primary["goal"].get("target_sg", 0)
			return "当前结构需要从空间群#%d降至#%d。施加软模操作来降低对称性。" % [src, tgt]

		"bond_check":
			return "检查原子间距是否在合理成键范围内。"

	return "继续完成剩余目标。"


func _diagnose_conservation() -> String:
	var summary: Dictionary = ConservationEngine.get_deviation_summary()
	var worst_key := ""
	var worst_dev := 0.0

	for key in summary:
		var dev: float = summary[key]["deviation"]
		if dev > worst_dev:
			worst_dev = dev
			worst_key = key

	if worst_key.is_empty():
		return "守恒矩阵看起来正常。检查其他目标。"

	var eigenvalue: float = summary[worst_key]["eigenvalue"]
	var direction := "偏低" if eigenvalue < 1.0 else "偏高"
	return "守恒矩阵%s行偏离最大(λ=%.3f, %s)。检查该守恒量相关的原子操作。" % [worst_key, eigenvalue, direction]
