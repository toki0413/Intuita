# reachability_validator_test.gd
# 校验所有56个JSON关卡的可达性，确保没有目标在约束下不可达
# 这是"防止问题再发生"机制的核心测试

class_name ReachabilityValidatorTest
extends GdUnitTestSuite


func test_all_json_levels_reachable() -> void:
	var loader_script: Resource = load("res://scripts/autoload/level_data_loader.gd")
	var loader: Variant = loader_script.new()
	loader._rebuild_registry()
	var validator_script: Resource = load("res://scripts/autoload/level_data_validator.gd")

	# 所有关卡列表
	var levels: Array[Dictionary] = [
		{"c": 0, "l": 1}, {"c": 0, "l": 2},
		{"c": 1, "l": 1}, {"c": 1, "l": 2}, {"c": 1, "l": 3}, {"c": 1, "l": 4}, {"c": 1, "l": 5},
		{"c": 1, "l": 6}, {"c": 1, "l": 7}, {"c": 1, "l": 8}, {"c": 1, "l": 9}, {"c": 1, "l": 10},
		{"c": 1, "l": 11}, {"c": 1, "l": 12}, {"c": 1, "l": 13}, {"c": 1, "l": 14},
		{"c": 2, "l": 1}, {"c": 2, "l": 2}, {"c": 2, "l": 3}, {"c": 2, "l": 4}, {"c": 2, "l": 5},
		{"c": 2, "l": 6}, {"c": 2, "l": 7}, {"c": 2, "l": 8}, {"c": 2, "l": 9}, {"c": 2, "l": 10},
		{"c": 2, "l": 11}, {"c": 2, "l": 12}, {"c": 2, "l": 13},
		{"c": 3, "l": 1}, {"c": 3, "l": 2}, {"c": 3, "l": 3}, {"c": 3, "l": 4}, {"c": 3, "l": 5},
		{"c": 3, "l": 6}, {"c": 3, "l": 7}, {"c": 3, "l": 8}, {"c": 3, "l": 9}, {"c": 3, "l": 10},
		{"c": 3, "l": 11}, {"c": 3, "l": 12},
		{"c": 4, "l": 1}, {"c": 4, "l": 2}, {"c": 4, "l": 3}, {"c": 4, "l": 4}, {"c": 4, "l": 5},
		{"c": 4, "l": 6}, {"c": 4, "l": 7}, {"c": 4, "l": 8}, {"c": 4, "l": 9}, {"c": 4, "l": 10},
		{"c": -1, "l": 1}, {"c": -1, "l": 2}, {"c": -1, "l": 3}, {"c": -1, "l": 4}, {"c": -1, "l": 5},
	]

	var all_warnings: Array[String] = []
	for info in levels:
		if not loader.has_level(info.c, info.l):
			continue
		var ld: Variant = loader.load_level_data(info.c, info.l)
		if ld == null:
			continue
		var json_data: Dictionary = ld.to_json()
		var warnings: Array[String] = validator_script.validate_reachability(json_data)
		for w in warnings:
			all_warnings.append("C%d-L%d: %s" % [info.c, info.l, w])

	if not all_warnings.is_empty():
		push_warning("可达性警告:\n" + "\n".join(all_warnings))
	assert_bool(all_warnings.is_empty()).override_failure_message(
		"可达性校验发现 %d 个问题:\n%s" % [all_warnings.size(), "\n".join(all_warnings)]
	).is_true()
