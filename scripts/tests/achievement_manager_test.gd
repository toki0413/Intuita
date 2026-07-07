# achievement_manager_test.gd
# GdUnit4 测试: AchievementManager 成就解锁与条件检查

extends GdUnitTestSuite

const __source = "res://scripts/autoload/04_achievement_manager.gd"

var _am: Node = null
var _saved_locale: String = ""

func before_test() -> void:
	var i18n = Engine.get_main_loop().root.get_node_or_null("/root/I18nManager")
	if i18n != null and i18n.has_method("get_language"):
		_saved_locale = i18n.get_language()
	var ref = load(__source)
	_am = ref.new()
	_am._load_definitions()
	# 不加载已有解锁，保持干净状态
	_am._unlocked = {}
	_am._progress = {}

func after_test() -> void:
	var i18n = Engine.get_main_loop().root.get_node_or_null("/root/I18nManager")
	if i18n != null and i18n.has_method("set_language"):
		i18n.set_language(_saved_locale)
	_am = null

func test_definitions_loaded() -> void:
	assert_int(_am._definitions.size()).is_greater(0)

func test_is_unlocked_false_initially() -> void:
	assert_bool(_am.is_unlocked("first_step")).is_false()

func test_unlocked_count_zero_initially() -> void:
	assert_int(_am.get_unlocked_count()).is_equal(0)

func test_get_title() -> void:
	assert_str(_am.get_title("first_step")).is_equal("First Step")
	assert_str(_am.get_title("nonexistent")).is_equal("nonexistent")

func test_get_progress() -> void:
	assert_int(_am.get_progress("fog_master")).is_equal(0)

func test_unlock_single() -> void:
	_am._unlocked["first_step"] = {"unlocked_at": 0}
	assert_bool(_am.is_unlocked("first_step")).is_true()
	assert_int(_am.get_unlocked_count()).is_equal(1)

func test_get_all_achievements() -> void:
	var all = _am.get_all_achievements()
	assert_int(all.size()).is_greater(0)
	var found := false
	for a in all:
		if a.get("id") == "first_step":
			found = true
	assert_bool(found).is_true()

func test_progress_increment() -> void:
	_am._increment_progress("fog_master", 5)
	assert_int(_am.get_progress("fog_master")).is_equal(5)
	_am._increment_progress("fog_master", 6)
	assert_int(_am.get_progress("fog_master")).is_equal(10)

func test_check_single_fog_master() -> void:
	_am._progress["fog_master"] = 10
	var unlocked = _am._check_single("fog_master")
	assert_bool(unlocked).is_true()
	assert_bool(_am.is_unlocked("fog_master")).is_true()

func test_check_single_already_unlocked() -> void:
	_am._unlocked["first_step"] = {"unlocked_at": 0}
	var unlocked = _am._check_single("first_step")
	assert_bool(unlocked).is_false()

func test_streak_master_progress() -> void:
	_am._progress["streak_master"] = 9
	var unlocked = _am._check_single("streak_master")
	assert_bool(unlocked).is_false()
	_am._progress["streak_master"] = 10
	unlocked = _am._check_single("streak_master")
	assert_bool(unlocked).is_true()

func test_conservation_purist_progress() -> void:
	_am._progress["conservation_purist"] = 5
	var unlocked = _am._check_single("conservation_purist")
	assert_bool(unlocked).is_true()

func test_sandbox_explorer_progress() -> void:
	_am._progress["sandbox_explorer"] = 100
	var unlocked = _am._check_single("sandbox_explorer")
	assert_bool(unlocked).is_true()

func test_level_complete_unlocks_first_step() -> void:
	# simulate 1 level completed via progress (bypass GameState dependency)
	_am._progress["level_complete"] = 1
	var unlocked = _am._check_single("first_step")
	assert_bool(unlocked).is_true()

func test_achievement_unlocked_signal_emitted() -> void:
	var received := {"id": "", "title": ""}
	var cb := func(id, title, _icon):
		received["id"] = id
		received["title"] = title
	_am.achievement_unlocked.connect(cb)
	_am._progress["fog_master"] = 10
	_am._check_single("fog_master")
	assert_that(received["id"]).is_equal("fog_master")
	assert_that(received["title"]).is_equal("Fog Master")
	_am.achievement_unlocked.disconnect(cb)

func test_get_title_localized_zh() -> void:
	var i18n = Engine.get_main_loop().root.get_node_or_null("/root/I18nManager")
	if i18n != null and i18n.has_method("set_language"):
		i18n.set_language("zh_CN")
	assert_str(_am.get_title_localized("first_step")).is_equal("第一步")

func test_save_and_load_unlocked() -> void:
	_am._unlocked["first_step"] = {"unlocked_at": 123.0}
	_am._save_unlocked()
	var am2 = load(__source).new()
	am2._load_unlocked()
	assert_bool(am2.is_unlocked("first_step")).is_true()
	am2.queue_free()
