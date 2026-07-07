# settings_namespace_test.gd
# GdUnit4 测试: SettingsManager 分层命名空间与旧格式兼容

extends GdUnitTestSuite

const __source = "res://scripts/autoload/02_settings_manager.gd"

func test_legacy_resolution_maps_to_namespaced() -> void:
	var val = SettingsManager.get_setting("resolution")
	assert_bool(val != null).is_true()

func test_legacy_fullscreen_maps_to_namespaced() -> void:
	var val = SettingsManager.get_setting("fullscreen")
	assert_bool(val is bool).is_true()

func test_namespaced_key_works_directly() -> void:
	SettingsManager.set_setting("intuita:render:resolution", Vector2i(1280, 720))
	var val = SettingsManager.get_setting("intuita:render:resolution")
	assert_bool(val is Vector2i).is_true()
	assert_int(val.x).is_equal(1280)
	assert_int(val.y).is_equal(720)

func test_unknown_key_returns_default() -> void:
	var val = SettingsManager.get_setting("nonexistent_key", "fallback")
	assert_str(val).is_equal("fallback")

func test_legacy_music_volume_maps_to_audio() -> void:
	var val = SettingsManager.get_setting("music_volume")
	assert_bool(val is float).is_true()
