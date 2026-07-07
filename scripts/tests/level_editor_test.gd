# level_editor_test.gd
# GdUnit4 测试: LevelEditor 核心逻辑

extends GdUnitTestSuite

const __source = "res://scripts/tools/level_editor.gd"

var _editor = null
var _received_path: String = ""

func _temp_path(chapter: int, level: int) -> String:
	return "res://data/levels/json/chapter_%d_level_%d.json" % [chapter, level]

func _cleanup(chapter: int, level: int) -> void:
	var file_name := "chapter_%d_level_%d.json" % [chapter, level]
	var dir := DirAccess.open("res://data/levels/json/")
	if dir != null and dir.file_exists(file_name):
		dir.remove(file_name)

func _on_level_saved(path: String) -> void:
	_received_path = path

func before_test() -> void:
	_editor = load(__source).new()
	var i18n = Engine.get_main_loop().root.get_node_or_null("/root/I18nManager")
	if i18n != null and i18n.has_method("set_language"):
		i18n.set_language("en")
	for l in range(990, 1000):
		_cleanup(999, l)

func after_test() -> void:
	_editor = null
	var i18n = Engine.get_main_loop().root.get_node_or_null("/root/I18nManager")
	if i18n != null and i18n.has_method("set_language"):
		i18n.set_language("zh_CN")
	for l in range(990, 1000):
		_cleanup(999, l)

func test_new_level_creates_blank_data() -> void:
	_editor.new_level(1, 1)
	var data: Variant = _editor.get_current_data()
	assert_object(data).is_not_null()
	assert_int(data.chapter).is_equal(1)
	assert_int(data.level).is_equal(1)
	assert_str(data.title).is_equal("New Level 1-1")
	assert_str(data.description).is_equal("")
	assert_str(data.domain).is_equal("crystal")
	assert_str(data.construction_mode).is_equal("wyckoff_fill")
	assert_int(data.space_group_number).is_equal(1)
	assert_str(data.space_group_symbol).is_equal("P1")
	assert_float(data.lattice_parameters.x).is_equal(1.0)
	assert_float(data.lattice_parameters.y).is_equal(1.0)
	assert_float(data.lattice_parameters.z).is_equal(1.0)
	assert_float(data.lattice_angles.x).is_equal(90.0)
	assert_float(data.lattice_angles.y).is_equal(90.0)
	assert_float(data.lattice_angles.z).is_equal(90.0)
	assert_int(data.reward_cores).is_equal(1)
	assert_array(data.elements).has_size(0)
	assert_array(data.goals).has_size(0)
	assert_array(data.available_tools).has_size(2)
	assert_str(data.scale_label).is_equal("Å")
	assert_float(data.scale_range.x).is_equal(0.5)
	assert_float(data.scale_range.y).is_equal(10.0)

func test_load_level_populates_fields() -> void:
	var success: bool = _editor.load_level(1, 1)
	assert_bool(success).is_true()
	var data: Variant = _editor.get_current_data()
	assert_object(data).is_not_null()
	assert_str(data.title).is_equal("First Experiment")
	assert_int(data.space_group_number).is_equal(225)
	assert_str(data.space_group_symbol).is_equal("Fm-3m")
	assert_int(data.elements.size()).is_equal(2)
	assert_int(data.goals.size()).is_equal(2)

func test_save_level_writes_json() -> void:
	_editor.new_level(999, 990)
	_editor.set_title("Test Save")
	_editor.set_description("Test desc")
	_editor.add_element({"symbol": "Fe", "wyckoff_label": "a", "wyckoff_multiplicity": 4, "position": Vector3(0, 0, 0)})
	_editor.add_goal({"type": "wyckoff_fill", "description": "Fill Fe", "element": "Fe", "wyckoff": "a", "required_count": 4})
	_editor.set_reward_cores(3)
	var success: bool = _editor.save_level()
	assert_bool(success).is_true()

	var path := _temp_path(999, 990)
	var file := FileAccess.open(path, FileAccess.READ)
	assert_object(file).is_not_null()
	var raw := file.get_as_text()
	file.close()
	var json := JSON.new()
	assert_int(json.parse(raw)).is_equal(OK)
	var dict: Dictionary = json.data
	assert_str(dict.get("title", "")).is_equal("Test Save")
	assert_str(dict.get("description", "")).is_equal("Test desc")
	assert_array(dict.get("elements", [])).has_size(1)
	assert_array(dict.get("goals", [])).has_size(1)
	assert_float(float(dict.get("reward_cores", 0))).is_equal(3.0)
	var required_keys := [
		"chapter", "level", "title", "description", "domain",
		"construction_mode", "space_group_number", "space_group_symbol",
		"lattice_parameters", "lattice_angles", "reward_cores", "hint",
		"elements", "goals", "available_tools", "fog_zones",
		"constraints", "scene_config", "scale_label", "scale_range", "journal_entry"
	]
	for key in required_keys:
		assert_bool(dict.has(key)).is_true()

func test_edit_title_updates_data() -> void:
	_editor.new_level(1, 1)
	_editor.set_title("Edited Title")
	assert_str(_editor.get_current_data().title).is_equal("Edited Title")

func test_add_element_increases_count() -> void:
	_editor.new_level(1, 1)
	assert_int(_editor.get_current_data().elements.size()).is_equal(0)
	_editor.add_element({"symbol": "Na", "wyckoff_label": "a", "wyckoff_multiplicity": 4, "position": Vector3(0, 0, 0)})
	assert_int(_editor.get_current_data().elements.size()).is_equal(1)

func test_add_goal_increases_count() -> void:
	_editor.new_level(1, 1)
	assert_int(_editor.get_current_data().goals.size()).is_equal(0)
	_editor.add_goal({"type": "wyckoff_fill", "description": "Fill Na"})
	assert_int(_editor.get_current_data().goals.size()).is_equal(1)

func test_save_updates_registry() -> void:
	_editor.new_level(999, 991)
	_editor.set_title("Registry Test")
	_editor.add_goal({"type": "wyckoff_fill", "description": "Test"})
	_editor.add_element({"symbol": "Na"})
	var success: bool = _editor.save_level()
	assert_bool(success).is_true()

	var loader = load("res://scripts/autoload/level_data_loader.gd").new()
	loader._rebuild_registry()
	assert_bool(loader.has_level(999, 991)).is_true()

func test_signal_level_saved_emitted() -> void:
	_received_path = ""
	_editor.level_saved.connect(_on_level_saved)
	_editor.new_level(999, 992)
	_editor.set_title("Signal Test")
	_editor.add_goal({"type": "wyckoff_fill", "description": "Test"})
	_editor.add_element({"symbol": "Na"})
	var success: bool = _editor.save_level()
	assert_bool(success).is_true()
	assert_str(_received_path).is_not_empty()

func test_invalid_data_save_blocked() -> void:
	_editor.new_level(1, 1)
	# Empty goals and empty elements in non-free mode should fail validation
	var success: bool = _editor.save_level()
	assert_bool(success).is_false()

func test_vector3_roundtrip() -> void:
	_editor.new_level(999, 993)
	_editor.set_title("Vector3 Roundtrip")
	_editor.set_lattice_parameters(Vector3(3.14159, 2.71828, 1.41421))
	_editor.add_goal({"type": "wyckoff_fill", "description": "Test"})
	_editor.add_element({"symbol": "Na", "position": Vector3(0.123456789, 0.987654321, 0.555555555)})
	var success: bool = _editor.save_level()
	assert_bool(success).is_true()

	var path := _temp_path(999, 993)
	var file := FileAccess.open(path, FileAccess.READ)
	assert_object(file).is_not_null()
	var raw := file.get_as_text()
	file.close()
	var json := JSON.new()
	assert_int(json.parse(raw)).is_equal(OK)
	var dict: Dictionary = json.data

	var lp = dict.get("lattice_parameters", {})
	assert_float(float(lp.get("x", 0))).is_equal_approx(3.14159, 0.0001)
	assert_float(float(lp.get("y", 0))).is_equal_approx(2.71828, 0.0001)
	assert_float(float(lp.get("z", 0))).is_equal_approx(1.41421, 0.0001)

	var elements: Array = dict.get("elements", [])
	assert_int(elements.size()).is_equal(1)
	var pos = elements[0].get("position", {})
	assert_float(float(pos.get("x", 0))).is_equal_approx(0.123456789, 0.0001)
	assert_float(float(pos.get("y", 0))).is_equal_approx(0.987654321, 0.0001)
	assert_float(float(pos.get("z", 0))).is_equal_approx(0.555555555, 0.0001)
