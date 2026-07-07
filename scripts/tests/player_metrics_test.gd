# player_metrics_test.gd
# GdUnit4 测试: 玩家过程级指标系统

extends GdUnitTestSuite

const __source = "res://scripts/autoload/05_level_manager.gd"
const LB_SOURCE = "res://scripts/autoload/13_leaderboard_manager.gd"

var _lm: Node = null
var _lb: Node = null

func before_test() -> void:
	var ref = load(__source)
	_lm = ref.new()
	var lb_ref = load(LB_SOURCE)
	_lb = lb_ref.new()
	_lb._records = {}

func after_test() -> void:
	_lm = null
	_lb = null


func test_metrics_reset_on_level_load() -> void:
	# Simulate load_level resetting metrics
	_lm._metrics = {
		"undo_count": 0,
		"redo_count": 0,
		"hint_count": 0,
		"retry_count": 0,
		"fail_reason": "",
		"goal_completion_times": {},
		"verification_requests": 0,
	}
	assert_int(_lm._metrics["undo_count"]).is_equal(0)
	assert_int(_lm._metrics["hint_count"]).is_equal(0)
	assert_str(_lm._metrics["fail_reason"]).is_equal("")


func test_undo_counts_correctly() -> void:
	_lm._metrics = {"undo_count": 0}
	_lm.increment_metric("undo_count")
	assert_int(_lm._metrics["undo_count"]).is_equal(1)
	_lm.increment_metric("undo_count")
	assert_int(_lm._metrics["undo_count"]).is_equal(2)


func test_hint_counts_correctly() -> void:
	_lm._metrics = {"hint_count": 0}
	_lm.increment_metric("hint_count")
	assert_int(_lm._metrics["hint_count"]).is_equal(1)


func test_retry_counts_correctly() -> void:
	_lm._metrics = {"retry_count": 0}
	_lm.increment_metric("retry_count")
	assert_int(_lm._metrics["retry_count"]).is_equal(1)


func test_leaderboard_records_metrics() -> void:
	var entry = _lb.record_level_result(1, 1, 85.0, 45.0, 12, 3, 0, true, 2, 1, 1, 0, "")
	assert_dict(entry).contains_keys(["undo_count", "redo_count", "hint_count", "retry_count", "fail_reason"])
	assert_int(entry["undo_count"]).is_equal(2)
	assert_int(entry["redo_count"]).is_equal(1)
	assert_int(entry["hint_count"]).is_equal(1)
	assert_int(entry["retry_count"]).is_equal(0)
	assert_str(entry["fail_reason"]).is_equal("")

	var best = _lb.get_best_record(1, 1)
	assert_int(best["undo_count"]).is_equal(2)
	assert_int(best["hint_count"]).is_equal(1)


func test_player_profile_calculates() -> void:
	_lb.record_level_result(1, 1, 80.0, 30.0, 10, 3, 0, true, 1, 0, 0, 0, "")
	_lb.record_level_result(1, 2, 60.0, 45.0, 15, 2, 0, false, 0, 0, 1, 1, "")
	var profile = _lb.get_player_profile()
	assert_int(profile["total_levels_played"]).is_equal(2)
	assert_float(profile["total_time_seconds"]).is_equal(75.0)
	assert_float(profile["avg_moves_per_level"]).is_equal(12.5)
	assert_float(profile["avg_undo_ratio"]).is_equal(1.0 / 25.0)
	assert_float(profile["hint_dependency_rate"]).is_equal(0.5)
	assert_float(profile["retry_rate"]).is_equal(0.5)
	assert_float(profile["perfect_rate"]).is_equal(0.5)
	assert_int(profile["total_stars"]).is_equal(4)


func test_backward_compatibility() -> void:
	# Simulate old record without new metric fields
	var old_entry = {
		"chapter": 1,
		"level": 1,
		"score": 70.0,
		"time_seconds": 40.0,
		"moves": 12,
		"cores_earned": 2,
		"warnings": 0,
		"perfect": false,
		"stars": 2,
		"date": 1234567890,
	}
	_lb._records["1-1"] = {"best": old_entry, "history": [old_entry]}

	var best = _lb.get_best_record(1, 1)
	assert_dict(best).is_not_empty()
	assert_int(best["undo_count"]).is_equal(0)
	assert_int(best["hint_count"]).is_equal(0)
	assert_str(best["fail_reason"]).is_equal("")
	assert_float(best["score"]).is_equal(70.0)

	# get_player_profile should not crash with old entries
	var profile = _lb.get_player_profile()
	assert_int(profile["total_levels_played"]).is_equal(1)


func test_avg_metric_calculates() -> void:
	_lb.record_level_result(1, 1, 50.0, 60.0, 20, 2, 1, false, 2, 0, 0, 0, "")
	_lb.record_level_result(1, 1, 55.0, 55.0, 18, 2, 0, false, 4, 1, 1, 0, "")
	var avg_undo = _lb.get_avg_metric(1, 1, "undo_count")
	assert_float(avg_undo).is_equal(3.0)
	var avg_hint = _lb.get_avg_metric(1, 1, "hint_count")
	assert_float(avg_hint).is_equal(0.5)
	var avg_nonexistent = _lb.get_avg_metric(1, 1, "nonexistent")
	assert_float(avg_nonexistent).is_equal(0.0)


func test_get_metrics_returns_copy() -> void:
	_lm._metrics = {"undo_count": 5, "hint_count": 2}
	var copy = _lm.get_metrics()
	copy["undo_count"] = 99
	assert_int(_lm._metrics["undo_count"]).is_equal(5)


func test_set_metric_stores_value() -> void:
	_lm._metrics = {"fail_reason": ""}
	_lm.set_metric("fail_reason", "时间耗尽")
	assert_str(_lm._metrics["fail_reason"]).is_equal("时间耗尽")
