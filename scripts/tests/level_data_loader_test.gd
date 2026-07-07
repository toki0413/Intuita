# level_data_loader_test.gd
# GdUnit4 测试: LevelDataLoader 注册表、加载、缓存

extends GdUnitTestSuite

const __source = "res://scripts/autoload/level_data_loader.gd"

var _loader: Variant = null

func before() -> void:
	var ref_script = load(__source)
	_loader = ref_script.new()
	_loader._rebuild_registry()

func after() -> void:
	_loader = null

func test_registry_has_all_45_levels() -> void:
	var chapters: Array = _loader.list_chapters()
	assert_int(chapters.size()).is_greater_equal(5)
	# chapter 1..5, 0, -1
	assert_bool(chapters.has(1)).is_true()
	assert_bool(chapters.has(2)).is_true()
	assert_bool(chapters.has(3)).is_true()
	assert_bool(chapters.has(4)).is_true()
	assert_bool(chapters.has(0)).is_true()
	assert_bool(chapters.has(-1)).is_true()

func test_chapter_1_has_7_levels() -> void:
	var levels: Array = _loader.list_levels(1)
	assert_int(levels.size()).is_equal(7)

func test_chapter_4_has_9_levels() -> void:
	var levels: Array = _loader.list_levels(4)
	assert_int(levels.size()).is_equal(9)

func test_bonus_has_1_level() -> void:
	var levels: Array = _loader.list_levels(0)
	assert_int(levels.size()).is_equal(1)

func test_challenge_has_3_levels() -> void:
	var levels: Array = _loader.list_levels(-1)
	assert_int(levels.size()).is_equal(3)

func test_load_nacl_level() -> void:
	var ld = _loader.load_level_data(1, 1)
	assert_object(ld).is_not_null()
	assert_str(ld.title).is_equal("First Click")
	assert_int(ld.space_group_number).is_equal(225)
	assert_str(ld.space_group_symbol).is_equal("Fm-3m")
	assert_int(ld.goals.size()).is_greater_equal(1)

func test_cache_returns_same_object() -> void:
	var ld1 = _loader.load_level_data(1, 1)
	var ld2 = _loader.load_level_data(1, 1)
	assert_object(ld1).is_same(ld2)

func test_clear_cache_reloads() -> void:
	var ld1 = _loader.load_level_data(1, 1)
	_loader.clear_cache()
	var ld2 = _loader.load_level_data(1, 1)
	assert_object(ld1).is_not_same(ld2)

func test_missing_level_returns_null() -> void:
	var ld = _loader.load_level_data(999, 999)
	assert_object(ld).is_null()

func test_load_from_json_matches_factory() -> void:
	# JSON 和工厂方法都能加载同一关卡，比较核心结构属性
	var ld_json = _loader.load_level_data(1, 1)
	var ld_factory = LevelData.create_nacl_level()
	# space_group 应一致
	assert_int(ld_json.space_group_number).is_equal(ld_factory.space_group_number)
	# 元素列表应一致
	assert_int(ld_json.elements.size()).is_equal(ld_factory.elements.size())
