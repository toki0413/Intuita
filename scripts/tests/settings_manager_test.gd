# settings_manager_test.gd
# GdUnit4 测试：SettingsManager 设置持久化

extends GdUnitTestSuite


const __source = "res://scripts/autoload/02_settings_manager.gd"

var _settings: Node = null
var _backup_settings: Dictionary = {}


func before() -> void:
	_settings = Engine.get_main_loop().root.get_node_or_null("/root/SettingsManager")
	if _settings != null:
		# 备份当前设置，测试后恢复
		_backup_settings = _settings._settings.duplicate(true)


func after() -> void:
	if _settings != null:
		# 恢复原始设置
		_settings._settings = _backup_settings.duplicate(true)
		_settings._save_settings()


func test_autoload_exists() -> void:
	assert_object(_settings).is_not_null()


func test_get_setting_returns_default() -> void:
	if _settings == null:
		return

	var val = _settings.get_setting("fullscreen", false)
	assert_bool(val).is_equal(false)

	var master: float = _settings.get_setting("master_volume", 0.0)
	assert_float(master).is_equal(0.8)


func test_get_setting_returns_custom_default() -> void:
	if _settings == null:
		return

	var unknown: int = _settings.get_setting("nonexistent_key", 42)
	assert_int(unknown).is_equal(42)


func test_set_setting_and_get() -> void:
	if _settings == null:
		return

	_settings.set_setting("test_key", "test_value")
	assert_str(_settings.get_setting("test_key")).is_equal("test_value")

	_settings.set_setting("test_number", 123)
	assert_int(_settings.get_setting("test_number")).is_equal(123)


func test_setting_changed_signal_emitted() -> void:
	if _settings == null:
		return

	var received: Dictionary = {"key": "", "value": null}
	var cb := func(key: String, value: Variant):
		received["key"] = key
		received["value"] = value
	var err: int = _settings.setting_changed.connect(cb)
	assert_int(err).is_equal(OK)

	_settings.set_setting("signal_test", 999)
	assert_str(received.get("key", "")).is_equal("signal_test")
	assert_int(received.get("value", 0)).is_equal(999)

	_settings.setting_changed.disconnect(cb)


func test_reset_to_defaults_restores_values() -> void:
	if _settings == null:
		return

	_settings.set_setting("fullscreen", true)
	_settings.set_setting("master_volume", 0.2)

	assert_bool(_settings.get_setting("fullscreen")).is_equal(true)
	assert_float(_settings.get_setting("master_volume")).is_equal(0.2)

	_settings.reset_to_defaults()

	assert_bool(_settings.get_setting("fullscreen")).is_equal(false)
	assert_float(_settings.get_setting("master_volume")).is_equal(0.8)


func test_persistence_load_and_save() -> void:
	if _settings == null:
		return

	# 修改一个值并保存
	_settings.set_setting("test_persist", "hello")

	# 模拟重新加载：构造新字典并调用 _load_settings
	var original: Dictionary = _settings._settings.duplicate(true)
	_settings._settings = {}
	_settings._load_settings()

	assert_str(_settings.get_setting("test_persist")).is_equal("hello")


func test_all_default_keys_present() -> void:
	if _settings == null:
		return

	var expected_keys = [
		"resolution", "fullscreen", "vsync", "anti_aliasing",
		"fog_quality", "particle_quality", "master_volume",
		"sfx_volume", "music_volume", "auto_save_interval",
		"tutorial_enabled", "hints_enabled", "fog_intensity",
		"colorblind_mode", "font_scale", "key_bindings",
		"api_endpoint", "model_name", "max_tokens", "temperature",
		"language",
	]

	for key in expected_keys:
		var val = _settings.get_setting(key)
		assert_that(val).is_not_null()
