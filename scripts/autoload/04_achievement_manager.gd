# achievement_manager.gd
# 成就管理器 - 加载成就定义、跟踪解锁状态、检查条件
#
# Responsibilities:
#   - 从 JSON 加载成就定义
#   - 持久化解锁状态到 user://achievements_unlocked.json
#   - 监听游戏事件自动检查条件
#   - 提供查询和手动触发接口
#
# Signals:
#   achievement_unlocked(id, title, icon) - 成就解锁
#   progress_updated(id, current, target) - 进度更新
#
# Dependencies:
#   - Autoload: LevelManager, GameState, TutorialManager, FogSystem, SelfEvolve

extends Node

const DEFINITIONS_PATH := "res://data/achievements.json"
const SAVE_PATH := "user://achievements_unlocked.json"

signal achievement_unlocked(id: String, title: String, icon: String)
signal progress_updated(id: String, current: int, target: int)

var _definitions: Array[Dictionary] = []
var _unlocked: Dictionary = {}  # id -> {unlocked_at: timestamp}
var _progress: Dictionary = {}  # id -> current progress counter
var _logger: Node = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_logger = Engine.get_main_loop().root.get_node_or_null("/root/GameLogger")
	_load_definitions()
	_load_unlocked()
	_connect_signals()
	if _logger:
		_logger.info("AchievementManager", "Loaded %d achievements, %d unlocked" % [_definitions.size(), _unlocked.size()])


func _load_definitions() -> void:
	if not FileAccess.file_exists(DEFINITIONS_PATH):
		push_warning("AchievementManager: definitions not found at %s" % DEFINITIONS_PATH)
		return
	var file := FileAccess.open(DEFINITIONS_PATH, FileAccess.READ)
	if file == null:
		push_warning("AchievementManager: cannot read %s" % DEFINITIONS_PATH)
		return
	var raw := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(raw) != OK:
		push_warning("AchievementManager: JSON parse error in %s" % DEFINITIONS_PATH)
		return
	var data: Dictionary = json.data
	var arr: Array = data.get("achievements", [])
	for item in arr:
		if item is Dictionary:
			_definitions.append(item)


func _load_unlocked() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var raw := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(raw) != OK:
		return
	var data: Dictionary = json.data
	if data.get("unlocked") is Dictionary:
		_unlocked = data["unlocked"]
	if data.get("progress") is Dictionary:
		_progress = data["progress"]


func _save_unlocked() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	var data := {
		"unlocked": _unlocked,
		"progress": _progress,
	}
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


func _connect_signals() -> void:
	# 关卡完成
	var lm = Engine.get_main_loop().root.get_node_or_null("/root/LevelManager")
	if lm != null and lm.has_signal("level_completed"):
		lm.level_completed.connect(_on_level_completed)
	if lm != null and lm.has_signal("level_failed"):
		lm.level_failed.connect(_on_level_failed)
	# 教程完成
	var tm = Engine.get_main_loop().root.get_node_or_null("/root/TutorialManager")
	if tm != null and tm.has_signal("tutorial_completed"):
		tm.tutorial_completed.connect(_on_tutorial_completed)
	# 迷雾驱散
	var fs = Engine.get_main_loop().root.get_node_or_null("/root/FogSystem")
	if fs != null and fs.has_signal("fog_resolved"):
		fs.fog_resolved.connect(_on_fog_resolved)
	# 进化规则创建
	var se = Engine.get_main_loop().root.get_node_or_null("/root/SelfEvolve")
	if se != null and se.has_signal("rule_created"):
		se.rule_created.connect(_on_rule_created)


func _exit_tree() -> void:
	var lm = Engine.get_main_loop().root.get_node_or_null("/root/LevelManager")
	if lm != null and lm.has_signal("level_completed") and lm.level_completed.is_connected(_on_level_completed):
		lm.level_completed.disconnect(_on_level_completed)
	if lm != null and lm.has_signal("level_failed") and lm.level_failed.is_connected(_on_level_failed):
		lm.level_failed.disconnect(_on_level_failed)
	var tm = Engine.get_main_loop().root.get_node_or_null("/root/TutorialManager")
	if tm != null and tm.has_signal("tutorial_completed") and tm.tutorial_completed.is_connected(_on_tutorial_completed):
		tm.tutorial_completed.disconnect(_on_tutorial_completed)
	var fs = Engine.get_main_loop().root.get_node_or_null("/root/FogSystem")
	if fs != null and fs.has_signal("fog_resolved") and fs.fog_resolved.is_connected(_on_fog_resolved):
		fs.fog_resolved.disconnect(_on_fog_resolved)
	var se = Engine.get_main_loop().root.get_node_or_null("/root/SelfEvolve")
	if se != null and se.has_signal("rule_created") and se.rule_created.is_connected(_on_rule_created):
		se.rule_created.disconnect(_on_rule_created)


# ============ 公共查询 API ============

func get_all_achievements() -> Array[Dictionary]:
	return _definitions.duplicate(true)


func is_unlocked(id: String) -> bool:
	return _unlocked.has(id)


func get_unlocked_count() -> int:
	return _unlocked.size()


func get_progress(id: String) -> int:
	return _progress.get(id, 0)


func get_title(id: String) -> String:
	for def in _definitions:
		if def.get("id", "") == id:
			return str(def.get("title", id))
	return id


func get_title_localized(id: String) -> String:
	var locale := "en"
	var i18n = Engine.get_main_loop().root.get_node_or_null("/root/I18nManager")
	if i18n != null and i18n.has_method("get_language"):
		locale = i18n.get_language()
	var key := "title" if locale == "en" else "title_zh"
	for def in _definitions:
		if def.get("id", "") == id:
			var t = def.get(key, "")
			if t == "":
				t = def.get("title", id)
			return str(t)
	return id


# ============ 事件处理 ============

func _on_level_completed(score: float, cores_earned: int) -> void:
	var chapter: int = 0
	var level: int = 0
	var lm = Engine.get_main_loop().root.get_node_or_null("/root/LevelManager")
	if lm != null and lm.has_method("current_level_data"):
		var cld = lm.current_level_data
		chapter = int(cld.get("chapter", 0))
		level = int(cld.get("level", 0))

	var domain := ""
	if lm != null and lm.has_method("current_level_data"):
		domain = str(lm.current_level_data.get("domain", ""))

	# 通用关卡完成
	_increment_progress("level_complete", 1)
	_check_type("level_complete")
	_check_type("level_perfect")
	_check_type("chapter_complete")
	_check_type("all_chapters")
	_check_type("conservation_purist")
	_check_type("speed_run")
	_check_type("streak_master")

	if domain == "cellular_automaton":
		_check_single("ca_wizard")


func _on_level_failed(_reason: String) -> void:
	# 失败重置连胜
	_progress["streak_master"] = 0
	_save_unlocked()


func _on_tutorial_completed() -> void:
	_unlock_single("tutorial_complete")


func _on_fog_resolved(_region_id: int) -> void:
	_increment_progress("fog_master", 1)
	_check_single("fog_master")


func _on_rule_created(_rule_data: Dictionary) -> void:
	_unlock_single("first_evolution")


# ============ 条件检查 ============

func _increment_progress(condition_type: String, amount: int) -> void:
	for def in _definitions:
		if def.get("condition_type", "") == condition_type:
			var id: String = str(def.get("id", ""))
			if id == "":
				continue
			var current: int = _progress.get(id, 0)
			var params: Dictionary = def.get("condition_params", {})
			var target: int = int(params.get("count", params.get("atom_count", 1)))
			current = mini(current + amount, target)
			_progress[id] = current
			progress_updated.emit(id, current, target)


func _check_type(condition_type: String) -> void:
	for def in _definitions:
		if def.get("condition_type", "") == condition_type:
			_check_definition(def)


func _unlock_single(id: String) -> void:
	if is_unlocked(id):
		return
	_progress[id] = 999
	_unlocked[id] = {"unlocked_at": Time.get_unix_time_from_system()}
	_save_unlocked()
	for def in _definitions:
		if def.get("id", "") == id:
			var title: String = str(def.get("title", id))
			var icon: String = str(def.get("icon", "🏅"))
			achievement_unlocked.emit(id, title, icon)
			if _logger:
				_logger.info("AchievementManager", "Achievement unlocked: %s" % title)
			return

func _check_single(id: String) -> bool:
	for def in _definitions:
		if def.get("id", "") == id:
			return _check_definition(def)
	return false


func _check_definition(def: Dictionary) -> bool:
	var id: String = str(def.get("id", ""))
	if id == "" or is_unlocked(id):
		return false

	var condition_type: String = str(def.get("condition_type", ""))
	var params: Dictionary = def.get("condition_params", {})
	var unlocked := false

	match condition_type:
		"level_complete":
			var target: int = int(params.get("count", 1))
			var current: int = _get_total_levels_completed()
			if params.has("domain"):
				# domain-specific completion handled separately
				pass
			else:
				unlocked = current >= target

		"level_perfect":
			var stars: int = int(params.get("stars", 3))
			unlocked = _has_perfect_level(stars)

		"chapter_complete":
			var chapter: int = int(params.get("chapter", 1))
			unlocked = _is_chapter_complete(chapter)

		"all_chapters":
			unlocked = _is_chapter_complete(1) and _is_chapter_complete(2) and _is_chapter_complete(3) and _is_chapter_complete(4)

		"conservation_purist":
			var target: int = int(params.get("count", 5))
			var current: int = _progress.get(id, 0)
			unlocked = current >= target

		"speed_run":
			var time_limit: int = int(params.get("time_seconds", 60))
			unlocked = _has_speed_run(time_limit)

		"fog_master":
			var target: int = int(params.get("count", 10))
			var current: int = _progress.get(id, 0)
			unlocked = current >= target

		"first_evolution":
			unlocked = _progress.get(id, 0) > 0 or _unlocked.has(id)

		"tutorial_complete":
			unlocked = _progress.get(id, 0) > 0 or _unlocked.has(id)

		"sandbox_explorer":
			var target: int = int(params.get("atom_count", 100))
			var current: int = _progress.get(id, 0)
			unlocked = current >= target

		"streak_master":
			var target: int = int(params.get("count", 10))
			var current: int = _progress.get(id, 0)
			unlocked = current >= target

		"ca_wizard":
			unlocked = _progress.get(id, 0) > 0 or _unlocked.has(id)

	if unlocked:
		_unlocked[id] = {"unlocked_at": Time.get_unix_time_from_system()}
		_save_unlocked()
		var title: String = str(def.get("title", id))
		var icon: String = str(def.get("icon", "🏅"))
		achievement_unlocked.emit(id, title, icon)
		if _logger:
			_logger.info("AchievementManager", "Achievement unlocked: %s" % title)

	return unlocked


# ============ 辅助数据查询 ============

func _get_total_levels_completed() -> int:
	var gs = Engine.get_main_loop().root.get_node_or_null("/root/GameState")
	var count := 0
	if gs != null:
		var arr = gs.get("completed_levels")
		if arr is Array:
			count = arr.size()
	# 合并手动/测试进度计数
	count += _progress.get("level_complete", 0)
	return count


func _is_chapter_complete(chapter: int) -> bool:
	var gs = Engine.get_main_loop().root.get_node_or_null("/root/GameState")
	if gs == null:
		return false
	var completed = gs.get("completed_levels")
	if not completed is Array:
		return false
	var loader = Engine.get_main_loop().root.get_node_or_null("/root/LevelManager")
	var total_levels := 0
	if loader != null:
		var ld = loader.get("_loader")
		if ld != null and ld.has_method("list_levels"):
			var levels: Array = ld.list_levels(chapter)
			total_levels = levels.size()
	if total_levels == 0:
		# fallback: known chapter sizes
		match chapter:
			1, 2, 3: total_levels = 10
			4: total_levels = 8
			0: total_levels = 2
			-1: total_levels = 5
			_: total_levels = 0
	var completed_in_chapter := 0
	for key in completed:
		var parts := str(key).split("-")
		if parts.size() >= 2 and int(parts[0]) == chapter:
			completed_in_chapter += 1
	return completed_in_chapter >= total_levels and total_levels > 0


func _has_perfect_level(stars: int) -> bool:
	# 查询 LeaderboardManager 是否有完美记录
	var lb = Engine.get_main_loop().root.get_node_or_null("/root/LeaderboardManager")
	if lb != null and lb.has_method("has_perfect_record"):
		return lb.has_perfect_record(stars)
	return false


func _has_speed_run(time_limit: int) -> bool:
	var lb = Engine.get_main_loop().root.get_node_or_null("/root/LeaderboardManager")
	if lb != null and lb.has_method("has_speed_run"):
		return lb.has_speed_run(time_limit)
	return false


# ============ 手动触发（供沙盒/特殊事件） ============

func notify_sandbox_atom_placed() -> void:
	_increment_progress("sandbox_explorer", 1)
	_check_single("sandbox_explorer")


func notify_conservation_purist_level() -> void:
	_increment_progress("conservation_purist", 1)
	_check_single("conservation_purist")


func notify_ca_level_completed() -> void:
	_unlock_single("ca_wizard")
