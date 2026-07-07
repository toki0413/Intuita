# evolution_tree.gd
# 进化树系统 - 记录玩家通关路径，可视化成长轨迹，授予称号
# 每次完成关卡都记录一条"进化枝"，按章节组织成树状结构
#
# Responsibilities:
#   - 记录通关路径（章节/关卡/评分/时间）
#   - 计算玩家称号（基于完成度/速度/风格）
#   - 导出进化树快照供UI渲染
#
# Dependencies:
#   - Autoload: SaveManager (持久化), LevelManager (事件源)

extends Node

signal node_added(node_data: Dictionary)
signal title_changed(old_title: String, new_title: String)

const SAVE_KEY: String = "evolution_tree"
const SAVE_PATH: String = "user://evolution_tree.json"

# 称号定义：基于玩家行为风格
const TITLES: Array[Dictionary] = [
	{"id": "novice", "name_cn": "初学者", "name_en": "Novice", "min_levels": 0, "desc_cn": "刚刚踏入构造的世界", "desc_en": "Just stepped into the world of construction"},
	{"id": "architect", "name_cn": "建筑师", "name_en": "Architect", "min_levels": 10, "desc_cn": "已能稳定构造晶体结构", "desc_en": "Can build crystal structures reliably"},
	{"id": "conservationist", "name_cn": "守恒者", "name_en": "Conservationist", "min_levels": 20, "desc_cn": "深刻理解守恒定律", "desc_en": "Deep understanding of conservation laws"},
	{"id": "proof_master", "name_cn": "证明大师", "name_en": "Proof Master", "min_levels": 30, "desc_cn": "证明树深不可测", "desc_en": "Proof trees run deep"},
	{"id": "evolutionist", "name_cn": "进化者", "name_en": "Evolutionist", "min_levels": 40, "desc_cn": "驾驭涌现与混沌", "desc_en": "Master of emergence and chaos"},
	{"id": "intuitist", "name_cn": "直觉主义者", "name_en": "Intuitist", "min_levels": 54, "desc_cn": "存在即被构造", "desc_en": "Existence is construction"},
]

# 进化树节点：每个完成的关卡一个节点
# {chapter, level, title, score, stars, proof_depth, time_spent, timestamp, path_meta}
var _nodes: Array[Dictionary] = []
var _current_title: String = "novice"


func _ready() -> void:
	_load_from_save()
	if LevelManager != null:
		LevelManager.level_completed.connect(_on_level_completed)


func _exit_tree() -> void:
	if LevelManager != null and LevelManager.is_connected("level_completed", _on_level_completed):
		LevelManager.level_completed.disconnect(_on_level_completed)


# ---- 节点记录 ----

func _on_level_completed(score: float, cores_earned: int) -> void:
	var level_data: Dictionary = LevelManager.current_level_data
	if level_data.is_empty():
		return
	var node: Dictionary = {
		"chapter": int(level_data.get("chapter", 0)),
		"level": int(level_data.get("level", 0)),
		"title": String(level_data.get("title", "")),
		"score": float(score),
		"cores": int(cores_earned),
		"stars": _compute_stars(score),
		"proof_depth": int(level_data.get("_proof_depth", 0)),
		"time_spent": float(Time.get_ticks_msec() / 1000.0 - LevelManager._level_start_time),
		"timestamp": Time.get_unix_time_from_system(),
	}
	_nodes.append(node)
	_check_title_upgrade()
	node_added.emit(node)
	_save_to_save()


func _compute_stars(score: float) -> int:
	if score >= 240.0:
		return 3
	elif score >= 180.0:
		return 2
	elif score >= 120.0:
		return 1
	return 0


# ---- 称号系统 ----

func _check_title_upgrade() -> void:
	var completed: int = _nodes.size()
	var new_title: String = _current_title
	for title in TITLES:
		if completed >= title["min_levels"]:
			new_title = title["id"]
	if new_title != _current_title:
		var old: String = _current_title
		_current_title = new_title
		title_changed.emit(old, new_title)
		GameLogger.info("EvolutionTree", "[进化树] 称号升级: %s → %s" % [old, new_title])


func get_current_title() -> Dictionary:
	for title in TITLES:
		if title["id"] == _current_title:
			return title
	return TITLES[0]


func get_current_title_name(locale: String = "en") -> String:
	var title: Dictionary = get_current_title()
	return title.get("name_" + locale, title["name_en"])


# ---- 查询接口 ----

func get_tree_data() -> Array[Dictionary]:
	return _nodes


func get_chapter_stats(chapter: int) -> Dictionary:
	# 返回某章节的统计：完成数/总星数/平均分/总时间
	var chapter_nodes: Array = _nodes.filter(func(n): return n["chapter"] == chapter)
	if chapter_nodes.is_empty():
		return {"completed": 0, "stars": 0, "avg_score": 0.0, "total_time": 0.0}
	var stars: int = 0
	var score_sum: float = 0.0
	var time_sum: float = 0.0
	for n in chapter_nodes:
		stars += n["stars"]
		score_sum += n["score"]
		time_sum += n["time_spent"]
	return {
		"completed": chapter_nodes.size(),
		"stars": stars,
		"avg_score": score_sum / float(chapter_nodes.size()),
		"total_time": time_sum,
	}


func get_total_stars() -> int:
	var sum: int = 0
	for n in _nodes:
		sum += n["stars"]
	return sum


func get_completion_rate(total_levels: int) -> float:
	if total_levels <= 0:
		return 0.0
	return clampf(float(_nodes.size()) / float(total_levels), 0.0, 1.0)


# ---- 持久化 ----

func _save_to_save() -> void:
	# 独立文件持久化，避免侵入 SaveManager 的签名校验流程
	var data: Dictionary = {"nodes": _nodes, "title": _current_title}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("[进化树] 无法写入存档: %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


func _load_from_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var raw: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(raw) != OK:
		push_warning("[进化树] 存档解析失败")
		return
	var data: Dictionary = json.data
	var nodes_arr: Array = data.get("nodes", [])
	_nodes.clear()
	for n in nodes_arr:
		if n is Dictionary:
			_nodes.append(n)
	_current_title = String(data.get("title", "novice"))


func reset() -> void:
	# 供"重新开始游戏"使用
	_nodes.clear()
	_current_title = "novice"
	_save_to_save()
