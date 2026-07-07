# game_state.gd
# 全局游戏状态 - 跟踪当前模式、章节、核心数量等
#
# Responsibilities:
#   - 游戏模式管理（战役/沙盒/挑战）
#   - 章节和关卡进度
#   - 验证核心的收支
#
# Signals:
#   mode_changed(new_mode) - 游戏模式切换
#   chapter_changed(chapter) - 章节变化
#   level_changed(level) - 关卡变化
#   cores_changed(new_count) - 核心数量变化
#
# Dependencies:
#   - Autoload: 无

extends Node

enum GameMode { CAMPAIGN, SANDBOX, CHALLENGE }

@export var current_mode: GameMode = GameMode.CAMPAIGN
@export var current_chapter: int = 1
@export var current_level: int = 1
@export var _verification_cores: int = 10
@export var _evolve_points: int = 0
@export var conservation_matrix_state: int = 0  # mirrors ConservationEngine.State

var proof_tree_root: RefCounted = null

# 已通关关卡列表，格式 "chapter-level"
var completed_levels: Array[String] = []

# 沙盒模式下的虚拟无限值
const SANDBOX_UNLIMITED := 9999

# 沙盒模式配置
var sandbox_infinite_cores: bool = false
var sandbox_selected_space_group: int = 1
var sandbox_lattice_params: Vector3 = Vector3(5.0, 5.0, 5.0)
var sandbox_lattice_angles: Vector3 = Vector3(90.0, 90.0, 90.0)
var sandbox_fog_enabled: bool = false


func _is_sandbox() -> bool:
	return current_mode == GameMode.SANDBOX


# verification_cores在沙盒模式下返回9999
var verification_cores: int:
	get:
		if _is_sandbox():
			return SANDBOX_UNLIMITED
		return _verification_cores
	set(v):
		_verification_cores = maxi(v, 0)
		if _is_sandbox():
			cores_changed.emit(SANDBOX_UNLIMITED)
		else:
			cores_changed.emit(_verification_cores)


# evolve_points在沙盒模式下返回9999
var evolve_points: int:
	get:
		if _is_sandbox():
			return SANDBOX_UNLIMITED
		return _evolve_points
	set(v):
		_evolve_points = maxi(v, 0)
		evolve_points_changed.emit(_evolve_points)
var _last_warning_matrix_state: int = 0  # 上次WARNING状态的快照

signal mode_changed(new_mode: GameMode)
signal chapter_changed(chapter: int)
signal level_changed(level: int)
signal cores_changed(new_count: int)
signal evolve_points_changed(new_count: int)
signal emergency_backtrack_used()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func set_mode(mode: GameMode) -> void:
	if current_mode == mode:
		return
	current_mode = mode
	mode_changed.emit(mode)


func set_chapter(chapter: int) -> void:
	current_chapter = clampi(chapter, 1, 99)
	chapter_changed.emit(current_chapter)


func set_level(level: int) -> void:
	current_level = clampi(level, 1, 99)
	level_changed.emit(current_level)


func spend_cores(amount: int) -> bool:
	if _is_sandbox():
		return true  # 沙盒模式不消耗核心
	if _verification_cores < amount:
		return false
	_verification_cores -= amount
	cores_changed.emit(_verification_cores)
	return true


func gain_cores(amount: int) -> void:
	_verification_cores += amount
	cores_changed.emit(_verification_cores)


func emergency_backtrack() -> bool:
	# 花费2核心将守恒矩阵恢复到上次WARNING状态
	if verification_cores < 2:
		return false
	# setter 内已会 emit cores_changed，无需重复发射
	verification_cores -= 2
	conservation_matrix_state = _last_warning_matrix_state
	emergency_backtrack_used.emit()
	return true


# G10: 核心兑换进化点 — 3核心=1进化点
func exchange_cores_for_evolve_points(cores_to_spend: int) -> bool:
	if _is_sandbox():
		return true  # 沙盒模式不需要兑换
	var points_gained := cores_to_spend / 3
	if points_gained <= 0:
		return false
	if _verification_cores < cores_to_spend:
		return false
	_verification_cores -= cores_to_spend
	_evolve_points += points_gained
	cores_changed.emit(_verification_cores)
	return true


const WARNING_STATE_VALUE = 1

func update_warning_snapshot(state: int) -> void:
	# 当守恒矩阵进入WARNING状态时调用，保存快照
	if state == WARNING_STATE_VALUE:
		_last_warning_matrix_state = state


func get_level_key() -> String:
	return "chapter_%d_level_%d" % [current_chapter, current_level]


func mark_level_completed(chapter: int, level: int) -> void:
	# 记录已通关关卡，用于存档和进度追踪
	var key := "%d-%d" % [chapter, level]
	if not completed_levels.has(key):
		completed_levels.append(key)


func is_level_completed(chapter: int, level: int) -> bool:
	var key := "%d-%d" % [chapter, level]
	return completed_levels.has(key)


# 沙盒模式下所有工具都可用
func is_tool_available(_tool_name: String) -> bool:
	if _is_sandbox():
		return true
	return false  # 战役模式下由关卡配置决定
