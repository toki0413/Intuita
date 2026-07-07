# leaderboard_manager_test.gd
# GdUnit4 测试: LeaderboardManager 记录、查询、星级评定

extends GdUnitTestSuite

const __source = "res://scripts/autoload/13_leaderboard_manager.gd"

var _lb: Node = null

func before_test() -> void:
	var ref = load(__source)
	_lb = ref.new()
	_lb._records = {}

func after_test() -> void:
	_lb = null

func test_record_level_result_creates_entry() -> void:
	var entry = _lb.record_level_result(1, 1, 85.0, 45.0, 12, 3, 0, true)
	assert_dict(entry).is_not_empty()
	assert_float(entry["score"]).is_equal(85.0)
	assert_int(entry["stars"]).is_equal(2)

func test_get_best_record() -> void:
	_lb.record_level_result(1, 1, 85.0, 45.0, 12, 3, 0, true)
	var best = _lb.get_best_record(1, 1)
	assert_dict(best).is_not_empty()
	assert_float(best["score"]).is_equal(85.0)

func test_record_beat_score_updates_best() -> void:
	_lb.record_level_result(1, 1, 50.0, 60.0, 20, 2, 1, false)
	_lb.record_level_result(1, 1, 90.0, 55.0, 18, 3, 0, true)
	var best = _lb.get_best_record(1, 1)
	assert_float(best["score"]).is_equal(90.0)

func test_record_worse_score_keeps_best() -> void:
	_lb.record_level_result(1, 1, 90.0, 55.0, 18, 3, 0, true)
	_lb.record_level_result(1, 1, 40.0, 90.0, 25, 1, 2, false)
	var best = _lb.get_best_record(1, 1)
	assert_float(best["score"]).is_equal(90.0)

func test_get_history_multiple() -> void:
	_lb.record_level_result(1, 1, 50.0, 60.0, 20, 2, 1, false)
	_lb.record_level_result(1, 1, 90.0, 55.0, 18, 3, 0, true)
	var history = _lb.get_history(1, 1)
	assert_int(history.size()).is_equal(2)

func test_get_total_score() -> void:
	_lb.record_level_result(1, 1, 50.0, 60.0, 20, 2, 1, false)
	_lb.record_level_result(1, 2, 80.0, 45.0, 12, 3, 0, true)
	assert_float(_lb.get_total_score()).is_equal(130.0)

func test_get_total_stars() -> void:
	_lb.record_level_result(1, 1, 50.0, 60.0, 20, 2, 1, false)
	_lb.record_level_result(1, 2, 80.0, 45.0, 12, 3, 0, true)
	assert_int(_lb.get_total_stars()).is_equal(3)

func test_has_perfect_record_true() -> void:
	_lb.record_level_result(1, 1, 95.0, 30.0, 10, 3, 0, true)
	assert_bool(_lb.has_perfect_record(3)).is_true()

func test_has_perfect_record_false() -> void:
	_lb.record_level_result(1, 1, 40.0, 60.0, 20, 2, 1, false)
	assert_bool(_lb.has_perfect_record(3)).is_false()

func test_has_speed_run_true() -> void:
	_lb.record_level_result(1, 1, 60.0, 30.0, 15, 2, 0, true)
	assert_bool(_lb.has_speed_run(60)).is_true()

func test_has_speed_run_false() -> void:
	_lb.record_level_result(1, 1, 60.0, 90.0, 15, 2, 0, true)
	assert_bool(_lb.has_speed_run(60)).is_false()

func test_is_level_played() -> void:
	assert_bool(_lb.is_level_played(1, 1)).is_false()
	_lb.record_level_result(1, 1, 60.0, 30.0, 15, 2, 0, true)
	assert_bool(_lb.is_level_played(1, 1)).is_true()

func test_get_ranking_for_level() -> void:
	_lb.record_level_result(1, 1, 95.0, 30.0, 10, 3, 0, true)
	assert_str(_lb.get_ranking_for_level(1, 1)).is_equal("S")

func test_get_ranking_for_level_unplayed() -> void:
	assert_str(_lb.get_ranking_for_level(1, 1)).is_equal("-")

func test_calculate_stars_3() -> void:
	assert_int(_lb._calculate_stars(95.0, 30.0, 10, 0, true)).is_equal(3)

func test_calculate_stars_2() -> void:
	assert_int(_lb._calculate_stars(70.0, 60.0, 20, 0, false)).is_equal(2)

func test_calculate_stars_1() -> void:
	assert_int(_lb._calculate_stars(40.0, 60.0, 20, 1, false)).is_equal(1)

func test_calculate_stars_0() -> void:
	assert_int(_lb._calculate_stars(10.0, 120.0, 50, 5, false)).is_equal(0)

func test_new_best_score_signal() -> void:
	var state := {"old_s": 0.0, "new_s": 0.0}
	var cb := func(_c, _l, old_score, new_score):
		state["old_s"] = old_score
		state["new_s"] = new_score
	_lb.new_best_score.connect(cb)
	_lb.record_level_result(1, 1, 50.0, 60.0, 20, 2, 1, false)
	_lb.record_level_result(1, 1, 80.0, 55.0, 18, 3, 0, true)
	assert_float(state["old_s"]).is_equal(50.0)
	assert_float(state["new_s"]).is_equal(80.0)
	_lb.new_best_score.disconnect(cb)

func test_clear_all() -> void:
	_lb.record_level_result(1, 1, 50.0, 60.0, 20, 2, 1, false)
	_lb.clear_all()
	assert_bool(_lb.is_level_played(1, 1)).is_false()
	assert_float(_lb.get_total_score()).is_equal(0.0)

func test_save_and_load() -> void:
	_lb.record_level_result(1, 1, 50.0, 60.0, 20, 2, 1, false)
	_lb._save_records()
	var lb2 = load(__source).new()
	lb2._load_records()
	assert_bool(lb2.is_level_played(1, 1)).is_true()
	var best = lb2.get_best_record(1, 1)
	assert_float(best["score"]).is_equal(50.0)
	lb2.queue_free()
