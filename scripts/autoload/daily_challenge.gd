# daily_challenge.gd
# 每日挑战系统 - 基于日期种子确定性生成每日关卡
# 同一天所有玩家面对相同挑战，支持社区竞赛排名
# 存档路径: user://daily_challenge.dat

extends Node

signal daily_challenge_loaded(challenge_data: LevelData)
signal daily_best_score_updated(day_seed: int, score: float)

const SAVE_PATH := "user://daily_challenge.dat"

# 每日最佳成绩缓存 {day_seed: {"score": float, "cores": int, "timestamp": int}}
var _best_scores: Dictionary = {}
var _current_daily: LevelData = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_save_data()


# 用日期生成确定性种子
func get_today_seed() -> int:
	var now := Time.get_datetime_dict_from_system()
	# 年月日拼成一个整数，保证同一天种子相同
	return now["year"] * 10000 + now["month"] * 100 + now["day"]


# 加载今日每日挑战
func load_today_challenge() -> LevelData:
	var seed_val := get_today_seed()
	_current_daily = LevelData.create_daily_challenge(seed_val)
	daily_challenge_loaded.emit(_current_daily)
	return _current_daily


# 获取当前已加载的每日挑战
func get_current_daily() -> LevelData:
	return _current_daily


# 记录每日挑战成绩
func submit_daily_score(score: float, cores: int) -> void:
	var seed_val := get_today_seed()
	if not _best_scores.has(seed_val) or score > _best_scores[seed_val]["score"]:
		_best_scores[seed_val] = {
			"score": score,
			"cores": cores,
			"timestamp": Time.get_ticks_msec(),
		}
		_save_data()
		daily_best_score_updated.emit(seed_val, score)


# 获取指定日期的最佳成绩
func get_best_score(day_seed: int) -> Dictionary:
	return _best_scores.get(day_seed, {})


# 获取今日最佳成绩
func get_today_best_score() -> Dictionary:
	return get_best_score(get_today_seed())


# 获取历史记录(最近N天)
func get_recent_best_scores(count: int = 7) -> Array[Dictionary]:
	var seeds := _best_scores.keys()
	seeds.sort()
	seeds = seeds.slice(maxi(seeds.size() - count, 0), seeds.size() - 1)
	var result: Array[Dictionary] = []
	for s in seeds:
		var entry: Dictionary = _best_scores[s].duplicate()
		entry["day_seed"] = s
		result.append(entry)
	return result


# 检查今日是否已完成挑战
func is_today_completed() -> bool:
	return _best_scores.has(get_today_seed())


func _load_save_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		# 首次运行无存档属于正常情况，静默返回避免测试日志污染
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_warning("DailyChallenge: 无法打开存档文件")
		return
	var json_text := f.get_as_text()
	f.close()

	var json := JSON.new()
	if json.parse(json_text) != OK:
		push_warning("DailyChallenge: JSON 解析失败")
		return
	var data = json.data
	if data == null or not data is Dictionary:
		push_warning("DailyChallenge: 存档数据格式无效")
		return
	_best_scores = data.get("best_scores", {})

func _save_data() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("每日挑战存档写入失败")
		return
	var data := {"best_scores": _best_scores}
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
