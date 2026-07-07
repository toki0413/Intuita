# settings_manager.gd
# 设置管理器 - 图形/音频/游戏/控制/LLM配置
# 持久化到 user://settings.json
#
# Responsibilities:
#   - 管理所有游戏设置项的读写
#   - 图形设置应用到Viewport
#   - 音频设置应用到AudioServer
#   - 设置变更通知
#   - 默认值和重置
#
# Signals:
#   setting_changed(key, value) - 单项设置变化
#   settings_loaded() - 设置加载完成
#
# Dependencies:
#   - Autoload: 无（被其他系统依赖）

extends Node

const SETTINGS_PATH := "user://settings.json"

var _settings: Dictionary = {}
var _defaults: Dictionary = {}

signal setting_changed(key: String, value: Variant)
signal settings_loaded()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_init_defaults()
	_load_settings()
	settings_loaded.emit()


func _init_defaults() -> void:
	# 加载外部 JSON 默认值（若存在），否则使用硬编码默认值
	var json_path := "res://data/settings/settings_defaults.json"
	if FileAccess.file_exists(json_path):
		var file := FileAccess.open(json_path, FileAccess.READ)
		if file == null:
			push_warning("SettingsManager: 默认设置文件无法打开，使用硬编码默认值")
		else:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK:
				var data: Dictionary = json.data
				if data.has("defaults"):
					for key in data["defaults"]:
						_defaults[key] = data["defaults"][key]
			file.close()

	# 硬编码 fallback（分层键兼容旧格式）
	var screen := DisplayServer.screen_get_size(0)
	_defaults["intuita:render:resolution"] = Vector2i(screen.x, screen.y)
	_defaults["intuita:render:fullscreen"] = false
	_defaults["intuita:render:vsync"] = true
	_defaults["intuita:render:anti_aliasing"] = 2
	_defaults["intuita:render:fog_quality"] = 2
	_defaults["intuita:render:particle_quality"] = 2
	_defaults["intuita:render:atom_glow"] = true
	_defaults["intuita:render:fog_density"] = 0.36
	_defaults["intuita:render:hdri_quality"] = "high"
	_defaults["intuita:audio:master_volume"] = 0.8
	_defaults["intuita:audio:sfx_volume"] = 1.0
	_defaults["intuita:audio:music_volume"] = 0.5
	_defaults["intuita:game:auto_save_interval"] = 120
	_defaults["intuita:game:show_tutorial"] = true
	_defaults["intuita:game:hints_enabled"] = true
	_defaults["intuita:game:colorblind_mode"] = 0
	_defaults["intuita:game:font_scale"] = 1.0
	_defaults["intuita:game:reduce_flashing"] = false
	_defaults["intuita:control:key_bindings"] = {}
	_defaults["intuita:llm:api_endpoint"] = "https://api.openai.com/v1/chat/completions"
	_defaults["intuita:llm:model_name"] = "gpt-4o-mini"
	_defaults["intuita:llm:max_tokens"] = 256
	_defaults["intuita:llm:temperature"] = 0.3
	_defaults["intuita:game:language"] = ""

	# 旧格式兼容映射（shortcut）
	_defaults["resolution"] = _defaults["intuita:render:resolution"]
	_defaults["fullscreen"] = _defaults["intuita:render:fullscreen"]
	_defaults["vsync"] = _defaults["intuita:render:vsync"]
	_defaults["anti_aliasing"] = _defaults["intuita:render:anti_aliasing"]
	_defaults["fog_quality"] = _defaults["intuita:render:fog_quality"]
	_defaults["particle_quality"] = _defaults["intuita:render:particle_quality"]
	_defaults["master_volume"] = _defaults["intuita:audio:master_volume"]
	_defaults["sfx_volume"] = _defaults["intuita:audio:sfx_volume"]
	_defaults["music_volume"] = _defaults["intuita:audio:music_volume"]
	_defaults["auto_save_interval"] = _defaults["intuita:game:auto_save_interval"]
	_defaults["tutorial_enabled"] = _defaults["intuita:game:show_tutorial"]
	_defaults["hints_enabled"] = _defaults["intuita:game:hints_enabled"]
	_defaults["fog_intensity"] = _defaults["intuita:render:fog_density"]
	_defaults["colorblind_mode"] = _defaults["intuita:game:colorblind_mode"]
	_defaults["font_scale"] = _defaults["intuita:game:font_scale"]
	_defaults["reduce_flashing"] = _defaults["intuita:game:reduce_flashing"]
	_defaults["key_bindings"] = _defaults["intuita:control:key_bindings"]
	_defaults["api_endpoint"] = _defaults["intuita:llm:api_endpoint"]
	_defaults["model_name"] = _defaults["intuita:llm:model_name"]
	_defaults["max_tokens"] = _defaults["intuita:llm:max_tokens"]
	_defaults["temperature"] = _defaults["intuita:llm:temperature"]
	_defaults["language"] = _defaults["intuita:game:language"]


func get_setting(key: String, default: Variant = null) -> Variant:
	# 优先直接查找
	if _settings.has(key):
		return _settings[key]
	if _defaults.has(key):
		return _defaults[key]
	# 尝试旧格式兼容映射（如 "music_volume" -> "intuita:audio:music_volume"）
	var mapped := _legacy_to_namespaced(key)
	if mapped != key:
		if _settings.has(mapped):
			return _settings[mapped]
		if _defaults.has(mapped):
			return _defaults[mapped]
	return default


func _legacy_to_namespaced(key: String) -> String:
	# 旧格式键到分层命名空间键的映射
	match key:
		"resolution": return "intuita:render:resolution"
		"fullscreen": return "intuita:render:fullscreen"
		"vsync": return "intuita:render:vsync"
		"anti_aliasing": return "intuita:render:anti_aliasing"
		"fog_quality": return "intuita:render:fog_quality"
		"particle_quality": return "intuita:render:particle_quality"
		"atom_glow": return "intuita:render:atom_glow"
		"fog_density", "fog_intensity": return "intuita:render:fog_density"
		"hdri_quality": return "intuita:render:hdri_quality"
		"master_volume": return "intuita:audio:master_volume"
		"sfx_volume": return "intuita:audio:sfx_volume"
		"music_volume": return "intuita:audio:music_volume"
		"auto_save_interval": return "intuita:game:auto_save_interval"
		"tutorial_enabled", "show_tutorial": return "intuita:game:show_tutorial"
		"hints_enabled": return "intuita:game:hints_enabled"
		"colorblind_mode": return "intuita:game:colorblind_mode"
		"font_scale": return "intuita:game:font_scale"
		"reduce_flashing": return "intuita:game:reduce_flashing"
		"key_bindings": return "intuita:control:key_bindings"
		"api_endpoint": return "intuita:llm:api_endpoint"
		"model_name": return "intuita:llm:model_name"
		"max_tokens": return "intuita:llm:max_tokens"
		"temperature": return "intuita:llm:temperature"
		"language": return "intuita:game:language"
		_:
			return key


func set_setting(key: String, value: Variant) -> void:
	_settings[key] = value
	setting_changed.emit(key, value)
	# 同时写入命名空间版本（如果 key 是旧格式）
	var mapped := _legacy_to_namespaced(key)
	if mapped != key and not _settings.has(mapped):
		_settings[mapped] = value
	_save_settings()


func reset_to_defaults() -> void:
	_settings = _defaults.duplicate(true)
	_save_settings()
	apply_graphics_settings()
	apply_audio_settings()
	for key in _settings:
		setting_changed.emit(key, _settings[key])


func apply_graphics_settings() -> void:
	# 全屏
	var fullscreen: bool = get_setting("intuita:render:fullscreen", false)
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	# VSync
	var vsync: bool = get_setting("intuita:render:vsync", true)
	if vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	# 分辨率
	var res: Vector2i = get_setting("intuita:render:resolution", Vector2i(1920, 1080))
	if not fullscreen:
		DisplayServer.window_set_size(res)

	# MSAA
	var aa: int = get_setting("intuita:render:anti_aliasing", 0)
	match aa:
		0: get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		2: get_viewport().msaa_3d = Viewport.MSAA_2X
		4: get_viewport().msaa_3d = Viewport.MSAA_4X
		_: get_viewport().msaa_3d = Viewport.MSAA_DISABLED


func apply_audio_settings() -> void:
	var master: float = get_setting("intuita:audio:master_volume", 0.8)
	var sfx: float = get_setting("intuita:audio:sfx_volume", 1.0)
	var music: float = get_setting("intuita:audio:music_volume", 0.5)

	AudioServer.set_bus_volume_db(0, linear_to_db(master))
	var sfx_idx := AudioServer.get_bus_index("SFX")
	if sfx_idx != -1:
		AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(sfx))
	var music_idx := AudioServer.get_bus_index("Music")
	if music_idx != -1:
		AudioServer.set_bus_volume_db(music_idx, linear_to_db(music))


func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		_settings = _defaults.duplicate(true)
		return

	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		_settings = _defaults.duplicate(true)
		return

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_warning("设置文件解析失败，使用默认值")
		_settings = _defaults.duplicate(true)
		return

	var data: Dictionary = json.data
	_settings = _defaults.duplicate(true)
	for key in data:
		var value = data[key]
		match key:
			"resolution":
				if value is Dictionary:
					_settings[key] = Vector2i(int(value.get("x", 1920)), int(value.get("y", 1080)))
				elif value is Array and value.size() >= 2:
					_settings[key] = Vector2i(int(value[0]), int(value[1]))
				else:
					_settings[key] = value
			"colorblind_mode", "anti_aliasing", "fog_quality", "particle_quality":
				# 这些应该是 int
				if value is float:
					_settings[key] = int(value)
				else:
					_settings[key] = value
			_:
				_settings[key] = value


func _save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_settings, "\t"))
		file.close()
