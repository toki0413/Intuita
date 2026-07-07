extends Node
class_name LevelEditor

signal level_loaded(data: LevelData)
signal level_saved(path: String)
signal data_changed()

const DEFAULT_JSON_DIR := "res://data/levels/json"

var _current_data: LevelData = null
var _loader = null
var _validator_script = null
var _json_dir: String = DEFAULT_JSON_DIR

func _init() -> void:
	_loader = load("res://scripts/autoload/level_data_loader.gd").new()
	_validator_script = load("res://scripts/autoload/level_data_validator.gd")
	_rebuild_loader()

func _rebuild_loader() -> void:
	_loader._registry.clear()
	_loader._cache.clear()
	var dir := DirAccess.open(_json_dir)
	if dir == null:
		push_warning("LevelEditor: cannot open json dir %s" % _json_dir)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var path := _json_dir.path_join(file_name)
			var parsed := _parse_filename(file_name)
			if parsed != null and not parsed.is_empty():
				var chapter: int = parsed["chapter"]
				var level: int = parsed["level"]
				if not _loader._registry.has(chapter):
					_loader._registry[chapter] = {}
				_loader._registry[chapter][level] = path
		file_name = dir.get_next()

func _parse_filename(file_name: String) -> Dictionary:
	var regex := RegEx.new()
	regex.compile(r"chapter_(-?\d+)_level_(\d+)\.json")
	var match_result := regex.search(file_name)
	if match_result == null:
		return {}
	return {
		"chapter": int(match_result.get_string(1)),
		"level": int(match_result.get_string(2)),
	}

func set_json_dir(path: String) -> void:
	_json_dir = path
	_rebuild_loader()

func get_json_dir() -> String:
	return _json_dir

func get_current_data() -> LevelData:
	return _current_data

func new_level(chapter: int, level: int) -> void:
	var i18n = Engine.get_main_loop().root.get_node_or_null("/root/I18nManager")
	_current_data = LevelData.new()
	_current_data.chapter = chapter
	_current_data.level = level
	_current_data.title = i18n.translate("editor.new_level", {"chapter": chapter, "level": level}) if i18n != null else "New Level %d-%d" % [chapter, level]
	_current_data.description = ""
	_current_data.domain = "crystal"
	_current_data.construction_mode = "wyckoff_fill"
	_current_data.space_group_number = 1
	_current_data.space_group_symbol = "P1"
	_current_data.lattice_parameters = Vector3(1.0, 1.0, 1.0)
	_current_data.lattice_angles = Vector3(90.0, 90.0, 90.0)
	_current_data.reward_cores = 1
	_current_data.elements = []
	_current_data.goals = []
	_current_data.available_tools = ["element_block", "wyckoff_snap"]
	_current_data.fog_zones = []
	_current_data.constraints = {}
	_current_data.scene_config = {}
	_current_data.hint = ""
	_current_data.journal_entry = ""
	_current_data.scale_label = "Å"
	_current_data.scale_range = Vector2(0.5, 10.0)
	level_loaded.emit(_current_data)
	data_changed.emit()

func load_level(chapter: int, level: int) -> bool:
	var ld = _loader.load_level_data(chapter, level)
	if ld == null:
		return false
	_current_data = ld
	level_loaded.emit(_current_data)
	data_changed.emit()
	return true

func save_level() -> bool:
	if _current_data == null:
		push_error("LevelEditor: no current data to save")
		return false

	var json_data := _current_data.to_json()
	var errors: Array[String] = _validator_script.validate(json_data)
	if not errors.is_empty():
		push_error("LevelEditor: validation failed: %s" % ", ".join(errors))
		return false

	var file_name := "chapter_%d_level_%d.json" % [_current_data.chapter, _current_data.level]
	var path := _json_dir.path_join(file_name)

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("LevelEditor: cannot write to %s (error %d)" % [path, FileAccess.get_open_error()])
		return false

	var json := JSON.new()
	file.store_string(json.stringify(json_data, "\t"))
	file.close()

	_rebuild_loader()

	level_saved.emit(path)
	return true

func set_title(value: String) -> void:
	if _current_data == null:
		return
	if _current_data.title != value:
		_current_data.title = value
		data_changed.emit()

func set_description(value: String) -> void:
	if _current_data == null:
		return
	if _current_data.description != value:
		_current_data.description = value
		data_changed.emit()

func set_domain(value: String) -> void:
	if _current_data == null:
		return
	if _current_data.domain != value:
		_current_data.domain = value
		data_changed.emit()

func set_construction_mode(value: String) -> void:
	if _current_data == null:
		return
	if _current_data.construction_mode != value:
		_current_data.construction_mode = value
		data_changed.emit()

func set_space_group_number(value: int) -> void:
	if _current_data == null:
		return
	if _current_data.space_group_number != value:
		_current_data.space_group_number = value
		data_changed.emit()

func set_space_group_symbol(value: String) -> void:
	if _current_data == null:
		return
	if _current_data.space_group_symbol != value:
		_current_data.space_group_symbol = value
		data_changed.emit()

func set_lattice_parameters(v: Vector3) -> void:
	if _current_data == null:
		return
	if _current_data.lattice_parameters != v:
		_current_data.lattice_parameters = v
		data_changed.emit()

func set_lattice_angles(v: Vector3) -> void:
	if _current_data == null:
		return
	if _current_data.lattice_angles != v:
		_current_data.lattice_angles = v
		data_changed.emit()

func set_reward_cores(value: int) -> void:
	if _current_data == null:
		return
	if _current_data.reward_cores != value:
		_current_data.reward_cores = value
		data_changed.emit()

func set_hint(value: String) -> void:
	if _current_data == null:
		return
	if _current_data.hint != value:
		_current_data.hint = value
		data_changed.emit()

func set_journal_entry(value: String) -> void:
	if _current_data == null:
		return
	if _current_data.journal_entry != value:
		_current_data.journal_entry = value
		data_changed.emit()

func set_scale_label(value: String) -> void:
	if _current_data == null:
		return
	if _current_data.scale_label != value:
		_current_data.scale_label = value
		data_changed.emit()

func set_scale_range(v: Vector2) -> void:
	if _current_data == null:
		return
	if _current_data.scale_range != v:
		_current_data.scale_range = v
		data_changed.emit()

func set_elements(arr: Array[Dictionary]) -> void:
	if _current_data == null:
		return
	_current_data.elements = arr.duplicate(true)
	data_changed.emit()

func add_element(el: Dictionary) -> void:
	if _current_data == null:
		return
	_current_data.elements.append(el.duplicate(true))
	data_changed.emit()

func remove_element(index: int) -> void:
	if _current_data == null:
		return
	if index >= 0 and index < _current_data.elements.size():
		_current_data.elements.remove_at(index)
		data_changed.emit()

func update_element(index: int, el: Dictionary) -> void:
	if _current_data == null:
		return
	if index >= 0 and index < _current_data.elements.size():
		_current_data.elements[index] = el.duplicate(true)
		data_changed.emit()

func set_goals(arr: Array[Dictionary]) -> void:
	if _current_data == null:
		return
	_current_data.goals = arr.duplicate(true)
	data_changed.emit()

func add_goal(g: Dictionary) -> void:
	if _current_data == null:
		return
	_current_data.goals.append(g.duplicate(true))
	data_changed.emit()

func remove_goal(index: int) -> void:
	if _current_data == null:
		return
	if index >= 0 and index < _current_data.goals.size():
		_current_data.goals.remove_at(index)
		data_changed.emit()

func update_goal(index: int, g: Dictionary) -> void:
	if _current_data == null:
		return
	if index >= 0 and index < _current_data.goals.size():
		_current_data.goals[index] = g.duplicate(true)
		data_changed.emit()

func set_available_tools(arr: Array[String]) -> void:
	if _current_data == null:
		return
	_current_data.available_tools = arr.duplicate()
	data_changed.emit()

func set_fog_zones(arr: Array[Dictionary]) -> void:
	if _current_data == null:
		return
	_current_data.fog_zones = arr.duplicate(true)
	data_changed.emit()

func set_constraints(d: Dictionary) -> void:
	if _current_data == null:
		return
	_current_data.constraints = d.duplicate(true)
	data_changed.emit()

func set_scene_config(d: Dictionary) -> void:
	if _current_data == null:
		return
	_current_data.scene_config = d.duplicate(true)
	data_changed.emit()
