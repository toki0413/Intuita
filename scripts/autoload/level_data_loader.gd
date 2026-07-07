# level_data_loader.gd
# 关卡数据加载器 - 从 JSON 文件加载关卡数据并构建注册表
# 替代 level_manager.gd 中庞大的 switch 语句
#
# Responsibilities:
#   - 扫描 data/levels/json/ 建立 chapter/level -> path 注册表
#   - 从 JSON 反序列化 LevelData
#   - 运行时缓存已加载的关卡

extends Node
class_name LevelDataLoader

const JSON_DIR := "res://data/levels/json"

var _registry: Dictionary = {}  # {chapter: {level: String(path)}}
var _cache: Dictionary = {}     # {path: LevelData}


func _ready() -> void:
	_rebuild_registry()


func _rebuild_registry() -> void:
	_registry.clear()
	_cache.clear()
	var dir := DirAccess.open(JSON_DIR)
	if dir == null:
		push_warning("LevelDataLoader: cannot open %s" % JSON_DIR)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var path := JSON_DIR.path_join(file_name)
			var parsed := _parse_filename(file_name)
			if parsed != null:
				var chapter: int = parsed["chapter"]
				var level: int = parsed["level"]
				if not _registry.has(chapter):
					_registry[chapter] = {}
				_registry[chapter][level] = path
		file_name = dir.get_next()


func _parse_filename(file_name: String) -> Dictionary:
	# 格式: chapter_{c}_level_{l}.json
	var regex := RegEx.new()
	regex.compile(r"chapter_(-?\d+)_level_(\d+)\.json")
	var match_result := regex.search(file_name)
	if match_result == null:
		return {}
	return {
		"chapter": int(match_result.get_string(1)),
		"level": int(match_result.get_string(2)),
	}


func has_level(chapter: int, level: int) -> bool:
	return _registry.has(chapter) and _registry[chapter].has(level)


func list_chapters() -> Array[int]:
	var out: Array[int] = []
	for key in _registry:
		out.append(int(key))
	out.sort()
	return out


func list_levels(chapter: int) -> Array[int]:
	if not _registry.has(chapter):
		return []
	var out: Array[int] = []
	for key in _registry[chapter]:
		out.append(int(key))
	out.sort()
	return out


func load_level_data(chapter: int, level: int) -> LevelData:
	if not has_level(chapter, level):
		return null
	var path: String = _registry[chapter][level]
	if _cache.has(path):
		return _cache[path]

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("LevelDataLoader: cannot read %s" % path)
		return null
	var raw := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(raw) != OK:
		push_error("LevelDataLoader: JSON parse error in %s" % path)
		return null

	var data: Dictionary = json.data
	if not data is Dictionary:
		push_error("LevelDataLoader: top-level JSON is not Dictionary in %s" % path)
		return null

	var ld := LevelData.new()
	if data.get("compact", false):
		ld.from_compact_json(data)
	else:
		ld.from_json(data)
	_cache[path] = ld
	return ld


func clear_cache() -> void:
	_cache.clear()


func load_level_data_from_path(file_path: String) -> LevelData:
	"""从任意文件路径加载关卡数据（拖放导入用）。"""
	if not FileAccess.file_exists(file_path):
		push_error("LevelDataLoader: file not found %s" % file_path)
		return null

	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("LevelDataLoader: cannot read %s" % file_path)
		return null
	var raw := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(raw) != OK:
		push_error("LevelDataLoader: JSON parse error in %s" % file_path)
		return null

	var data: Dictionary = json.data
	if not data is Dictionary:
		push_error("LevelDataLoader: top-level JSON is not Dictionary in %s" % file_path)
		return null

	var ld := LevelData.new()
	if data.get("compact", false):
		ld.from_compact_json(data)
	else:
		ld.from_json(data)
	return ld
