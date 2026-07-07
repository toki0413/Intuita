# level_data_validator_test.gd
# GdUnit4 测试: LevelDataValidator 运行时校验

extends GdUnitTestSuite

const __source = "res://scripts/autoload/level_data_validator.gd"

var _validator_ref: Variant = null

func before() -> void:
	_validator_ref = load(__source)

func test_valid_data_passes() -> void:
	var data := {
		"chapter": 1,
		"level": 1,
		"title": "Test Level",
		"description": "A test level",
		"goals": [
			{"type": "wyckoff_fill", "description": "Fill Na", "element": "Na", "wyckoff": "a", "required_count": 4},
		],
		"reward_cores": 3,
		"construction_mode": "wyckoff_fill",
		"domain": "crystal",
		"elements": [{"symbol": "Na"}],
		"lattice_parameters": {"x": 5.0, "y": 5.0, "z": 5.0},
		"scene_config": {},
		"constraints": {},
		"fog_zones": [],
		"available_tools": ["element_block"],
	}
	var errors: Array[String] = _validator_ref.validate(data)
	assert_int(errors.size()).is_equal(0)

func test_missing_title_fails() -> void:
	var data := {
		"chapter": 1,
		"level": 1,
		"description": "desc",
		"goals": [{"type": "wyckoff_fill", "description": "d"}],
	}
	var errors: Array[String] = _validator_ref.validate(data)
	assert_bool(errors.size() > 0).is_true()
	var found := false
	for e in errors:
		if e.find("Missing required field: title") >= 0:
			found = true
	assert_bool(found).is_true()

func test_empty_goals_fails() -> void:
	var data := {
		"chapter": 1, "level": 1, "title": "T", "description": "D",
		"goals": [],
	}
	var errors: Array[String] = _validator_ref.validate(data)
	var found := false
	for e in errors:
		if e.find("Goals array is empty") >= 0:
			found = true
	assert_bool(found).is_true()

func test_invalid_goal_type_fails() -> void:
	var data := {
		"chapter": 1, "level": 1, "title": "T", "description": "D",
		"goals": [{"type": "invalid_type", "description": "d"}],
	}
	var errors: Array[String] = _validator_ref.validate(data)
	var found := false
	for e in errors:
		if e.find("invalid type") >= 0:
			found = true
	assert_bool(found).is_true()

func test_reward_cores_zero_fails() -> void:
	var data := {
		"chapter": 1, "level": 1, "title": "T", "description": "D",
		"goals": [{"type": "wyckoff_fill", "description": "d"}],
		"reward_cores": 0,
	}
	var errors: Array[String] = _validator_ref.validate(data)
	var found := false
	for e in errors:
		if e.find("reward_cores must be > 0") >= 0:
			found = true
	assert_bool(found).is_true()

func test_empty_elements_non_free_mode_fails() -> void:
	var data := {
		"chapter": 1, "level": 1, "title": "T", "description": "D",
		"goals": [{"type": "wyckoff_fill", "description": "d"}],
		"construction_mode": "wyckoff_fill",
		"elements": [],
	}
	var errors: Array[String] = _validator_ref.validate(data)
	var found := false
	for e in errors:
		if e.find("elements array is empty") >= 0:
			found = true
	assert_bool(found).is_true()

func test_free_mode_allows_empty_elements() -> void:
	var data := {
		"chapter": 1, "level": 1, "title": "T", "description": "D",
		"goals": [{"type": "verification", "description": "d"}],
		"construction_mode": "free",
		"elements": [],
	}
	var errors: Array[String] = _validator_ref.validate(data)
	var has_elements_error := false
	for e in errors:
		if e.find("elements array is empty") >= 0:
			has_elements_error = true
	assert_bool(has_elements_error).is_false()

func test_negative_lattice_parameter_fails() -> void:
	var data := {
		"chapter": 1, "level": 1, "title": "T", "description": "D",
		"goals": [{"type": "wyckoff_fill", "description": "d"}],
		"lattice_parameters": {"x": -1.0, "y": 5.0, "z": 5.0},
	}
	var errors: Array[String] = _validator_ref.validate(data)
	var found := false
	for e in errors:
		if e.find("lattice_parameters must all be > 0") >= 0:
			found = true
	assert_bool(found).is_true()

func test_invalid_construction_mode_fails() -> void:
	var data := {
		"chapter": 1, "level": 1, "title": "T", "description": "D",
		"goals": [{"type": "wyckoff_fill", "description": "d"}],
		"construction_mode": "invalid_mode",
	}
	var errors: Array[String] = _validator_ref.validate(data)
	var found := false
	for e in errors:
		if e.find("Invalid construction_mode") >= 0:
			found = true
	assert_bool(found).is_true()

func test_invalid_domain_fails() -> void:
	var data := {
		"chapter": 1, "level": 1, "title": "T", "description": "D",
		"goals": [{"type": "wyckoff_fill", "description": "d"}],
		"domain": "invalid_domain",
	}
	var errors: Array[String] = _validator_ref.validate(data)
	var found := false
	for e in errors:
		if e.find("Invalid domain") >= 0:
			found = true
	assert_bool(found).is_true()

func test_is_valid_helper() -> void:
	var data := {
		"chapter": 1, "level": 1, "title": "T", "description": "D",
		"goals": [{"type": "wyckoff_fill", "description": "d"}],
		"reward_cores": 3,
		"lattice_parameters": {"x": 5.0, "y": 5.0, "z": 5.0},
		"elements": [{"symbol": "Na"}],
	}
	assert_bool(_validator_ref.is_valid(data)).is_true()
	assert_bool(_validator_ref.is_valid({})).is_false()
