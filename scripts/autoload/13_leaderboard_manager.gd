# leaderboard_manager.gd
# 排行榜管理器 - 记录每关最高分、最少步数、最短用时
#
# Responsibilities:
#   - 记录关卡完成数据 (score, time, moves, cores, stars)
#   - 持久化到 user://leaderboard.json
#   - 查询每关最佳记录和全局统计
#   - 提供星级评定 (1-3 stars)
#
# Signals:
#   score_recorded(chapter, level, entry) - 新记录存入
#   new_best_score(chapter, level, old, new) - 打破最高分
#   new_best_time(chapter, level, old, new) - 打破最快记录
#
# Dependencies:
#   - Autoload: LevelManager, GameState

extends Node

const SAVE_PATH := "user://leaderboard.json"
const MAX_STARS := 3

signal score_recorded(chapter: int, level: int, entry: Dictionary)
signal new_best_score(chapter: int, level: int, old_score: float, new_score: float)
signal new_best_time(chapter: int, level: int, old_time: float, new_time: float)

var _records: Dictionary = {}  # "chapter-level" -> {"best": entry, "history": [entries]}
var _logger: Node = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_logger = Engine.get_main_loop().root.get_node_or_null("/root/GameLogger")
	_load_records()
	_connect_signals()


func _connect_signals() -> void:
	var lm = Engine.get_main_loop().root.get_node_or_null("/root/LevelManager")
	if lm != null and lm.has_signal("level_completed"):
		lm.level_completed.connect(_on_level_completed)
	if lm != null and lm.has_signal("level_failed"):
		lm.level_failed.connect(_on_level_failed)


func _on_level_failed(_reason: String) -> void:
	# Fail metrics are recorded via get_metrics when level is retried or completed,
	# but we do not create a leaderboard entry on fail. The fail_reason is stored
	# in LevelManager._metrics and will be picked up on the next record attempt.
	pass


func _load_records() -> void:
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
	if data.get("records") is Dictionary:
		_records = data["records"]


func _save_records() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	var data := {"records": _records}
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


# ============ 公共 API ============

func record_level_result(chapter: int, level: int, score: float, time_seconds: float, moves: int, cores_earned: int, warnings: int, perfect: bool, undo_count: int = 0, redo_count: int = 0, hint_count: int = 0, retry_count: int = 0, fail_reason: String = "") -> Dictionary:
	var key := "%d-%d" % [chapter, level]
	var stars := _calculate_stars(score, time_seconds, moves, warnings, perfect)
	var entry := {
		"chapter": chapter,
		"level": level,
		"score": score,
		"time_seconds": time_seconds,
		"moves": moves,
		"cores_earned": cores_earned,
		"warnings": warnings,
		"perfect": perfect,
		"stars": stars,
		"date": Time.get_unix_time_from_system(),
		"undo_count": undo_count,
		"redo_count": redo_count,
		"hint_count": hint_count,
		"retry_count": retry_count,
		"fail_reason": fail_reason,
	}

	if not _records.has(key):
		_records[key] = {"best": entry, "history": [entry]}
	else:
		var slot: Dictionary = _records[key]
		var best: Dictionary = slot.get("best", {})
		var history: Array = slot.get("history", [])
		var old_score: float = float(best.get("score", 0.0))
		var old_time: float = float(best.get("time_seconds", 99999.0))
		var old_perfect: bool = bool(best.get("perfect", false))
		var old_stars: int = int(best.get("stars", 0))

		if score > old_score:
			new_best_score.emit(chapter, level, old_score, score)
			best = entry
		if time_seconds < old_time:
			new_best_time.emit(chapter, level, old_time, time_seconds)
			if score <= old_score:
				# time-only improvement: update best if score is same or lower but time is better
				best = entry
		# perfect bonus: if not strictly better by score/time but perfect when old wasn't
		if not best.is_empty() and perfect and not old_perfect and score >= old_score and time_seconds <= old_time:
			best = entry

		# keep best if neither score nor time improved
		if score <= old_score and time_seconds >= old_time and not (perfect and not old_perfect):
			# no improvement, but still append history
			pass
		else:
			slot["best"] = best

		history.append(entry)
		if history.size() > 20:
			history.pop_front()
		slot["history"] = history

	_save_records()
	score_recorded.emit(chapter, level, entry)
	if _logger:
		_logger.info("LeaderboardManager", "Recorded %s: score=%.1f time=%.1fs stars=%d" % [key, score, time_seconds, stars])
	return entry


func get_best_record(chapter: int, level: int) -> Dictionary:
	var key := "%d-%d" % [chapter, level]
	if not _records.has(key):
		return {}
	var slot: Dictionary = _records[key]
	var best: Dictionary = slot.get("best", {}).duplicate(true)
	# backward compatibility: inject defaults for missing metric fields
	for metric_key in ["undo_count", "redo_count", "hint_count", "retry_count"]:
		if not best.has(metric_key):
			best[metric_key] = 0
	if not best.has("fail_reason"):
		best["fail_reason"] = ""
	return best


func get_history(chapter: int, level: int) -> Array:
	var key := "%d-%d" % [chapter, level]
	if not _records.has(key):
		return []
	var slot: Dictionary = _records[key]
	var history: Array = slot.get("history", [])
	return history.duplicate(true)


func get_all_best_scores() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key in _records:
		var slot: Dictionary = _records[key]
		var best = slot.get("best")
		if best is Dictionary:
			out.append(best.duplicate(true))
	return out


func get_total_score() -> float:
	var total := 0.0
	for key in _records:
		var slot: Dictionary = _records[key]
		var best = slot.get("best")
		if best is Dictionary:
			total += float(best.get("score", 0.0))
	return total


func get_total_stars() -> int:
	var total := 0
	for key in _records:
		var slot: Dictionary = _records[key]
		var best = slot.get("best")
		if best is Dictionary:
			total += int(best.get("stars", 0))
	return total


func has_perfect_record(min_stars: int) -> bool:
	for key in _records:
		var slot: Dictionary = _records[key]
		var best = slot.get("best")
		if best is Dictionary:
			if int(best.get("stars", 0)) >= min_stars:
				return true
	return false


func has_speed_run(time_limit: int) -> bool:
	for key in _records:
		var slot: Dictionary = _records[key]
		var best = slot.get("best")
		if best is Dictionary:
			if float(best.get("time_seconds", 99999.0)) <= float(time_limit):
				return true
	return false


func is_level_played(chapter: int, level: int) -> bool:
	var key := "%d-%d" % [chapter, level]
	return _records.has(key)


func get_ranking_for_level(chapter: int, level: int) -> String:
	var key := "%d-%d" % [chapter, level]
	if not _records.has(key):
		return "-"
	var best = _records[key].get("best", {})
	var stars: int = int(best.get("stars", 0))
	match stars:
		3: return "S"
		2: return "A"
		1: return "B"
		_: return "C"


func get_avg_metric(chapter: int, level: int, metric_key: String) -> float:
	var key := "%d-%d" % [chapter, level]
	if not _records.has(key):
		return 0.0
	var slot: Dictionary = _records[key]
	var history: Array = slot.get("history", [])
	if history.is_empty():
		return 0.0
	var total := 0.0
	var count := 0
	for entry in history:
		if entry is Dictionary and entry.has(metric_key):
			var val = entry[metric_key]
			if val is float or val is int:
				total += float(val)
				count += 1
	if count == 0:
		return 0.0
	return total / float(count)


func get_player_profile() -> Dictionary:
	var total_levels_played := 0
	var total_time_seconds := 0.0
	var total_moves := 0.0
	var total_undo := 0.0
	var total_moves_for_ratio := 0.0
	var levels_with_hint := 0
	var levels_with_retry := 0
	var levels_with_fail := 0
	var perfect_levels := 0
	var total_stars := 0

	for key in _records:
		var slot: Dictionary = _records[key]
		var best: Dictionary = slot.get("best", {})
		if best.is_empty():
			continue
		total_levels_played += 1
		total_time_seconds += float(best.get("time_seconds", 0.0))
		total_moves += float(best.get("moves", 0))
		var undo_count: int = int(best.get("undo_count", 0))
		var moves: int = int(best.get("moves", 0))
		if moves > 0:
			total_undo += float(undo_count)
			total_moves_for_ratio += float(moves)
		if int(best.get("hint_count", 0)) > 0:
			levels_with_hint += 1
		if int(best.get("retry_count", 0)) > 0:
			levels_with_retry += 1
		if not str(best.get("fail_reason", "")).is_empty():
			levels_with_fail += 1
		if bool(best.get("perfect", false)):
			perfect_levels += 1
		total_stars += int(best.get("stars", 0))

	var avg_moves_per_level := 0.0
	var avg_undo_ratio := 0.0
	var hint_dependency_rate := 0.0
	var retry_rate := 0.0
	var fail_rate := 0.0
	var perfect_rate := 0.0

	if total_levels_played > 0:
		avg_moves_per_level = total_moves / float(total_levels_played)
		if total_moves_for_ratio > 0:
			avg_undo_ratio = total_undo / total_moves_for_ratio
		hint_dependency_rate = float(levels_with_hint) / float(total_levels_played)
		retry_rate = float(levels_with_retry) / float(total_levels_played)
		fail_rate = float(levels_with_fail) / float(total_levels_played)
		perfect_rate = float(perfect_levels) / float(total_levels_played)

	return {
		"total_levels_played": total_levels_played,
		"total_time_seconds": total_time_seconds,
		"avg_moves_per_level": avg_moves_per_level,
		"avg_undo_ratio": avg_undo_ratio,
		"hint_dependency_rate": hint_dependency_rate,
		"retry_rate": retry_rate,
		"fail_rate": fail_rate,
		"perfect_rate": perfect_rate,
		"total_stars": total_stars,
	}


# ============ 内部 ============

func _on_level_completed(score: float, cores_earned: int) -> void:
	var chapter := 0
	var level := 0
	var time_seconds := 0.0
	var moves := 0
	var warnings := 0
	var perfect := false
	var undo_count := 0
	var redo_count := 0
	var hint_count := 0
	var retry_count := 0
	var fail_reason := ""

	var lm = Engine.get_main_loop().root.get_node_or_null("/root/LevelManager")
	if lm != null:
		var cld = lm.get("current_level_data")
		if cld is Dictionary:
			chapter = int(cld.get("chapter", 0))
			level = int(cld.get("level", 0))
		time_seconds = float(lm.get("_level_start_time") or 0.0)
		if time_seconds > 0.0:
			time_seconds = Time.get_ticks_msec() / 1000.0 - time_seconds
		moves = int(lm.get("move_count") or 0)
		# warnings: check if any instability occurred (simplified)
		warnings = int(lm.get("_instability_accumulator") or 0.0)
		perfect = warnings <= 0.0 and moves <= 50
		# pull runtime metrics
		var metrics: Dictionary = lm.get_metrics() if lm.has_method("get_metrics") else {}
		undo_count = int(metrics.get("undo_count", 0))
		redo_count = int(metrics.get("redo_count", 0))
		hint_count = int(metrics.get("hint_count", 0))
		retry_count = int(metrics.get("retry_count", 0))
		fail_reason = str(metrics.get("fail_reason", ""))

	record_level_result(chapter, level, score, time_seconds, moves, cores_earned, warnings, perfect, undo_count, redo_count, hint_count, retry_count, fail_reason)


func _calculate_stars(score: float, time_seconds: float, moves: int, warnings: int, perfect: bool) -> int:
	if perfect and score >= 90.0:
		return 3
	if score >= 70.0 or (score >= 50.0 and warnings == 0):
		return 2
	if score >= 30.0:
		return 1
	return 0


func clear_all() -> void:
	_records.clear()
	_save_records()
