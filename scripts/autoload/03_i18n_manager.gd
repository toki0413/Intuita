# i18n_manager.gd
# 国际化管理器 - 多语言翻译和运行时切换
# 翻译文件: res://data/i18n/{locale}.json
#
# Responsibilities:
#   - 加载和管理翻译字典
#   - 运行时语言切换（无需重启）
#   - 参数替换 (tr("key", {"n": 5}))
#   - 缺失key回退到英文
#   - OS语言自动检测
#
# Signals:
#   language_changed(locale) - 语言切换
#
# Dependencies:
#   - Autoload: SettingsManager（读取语言偏好）

extends Node

const I18N_DIR := "res://data/i18n/"
const SUPPORTED_LOCALES := ["en", "zh_CN"]
const FALLBACK_LOCALE := "en"

var _current_locale: String = "en"
var _translations: Dictionary = {}  # locale -> Dictionary of key->value

signal language_changed(locale: String)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_all_translations()
	_detect_locale()


func _load_all_translations() -> void:
	for locale_str: String in SUPPORTED_LOCALES:
		var path: String = I18N_DIR + locale_str + ".json"
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK:
			_translations[locale_str] = json.data


func _detect_locale() -> void:
	# 优先使用保存的设置
	var saved := ""
	if is_instance_valid(SettingsManager) and SettingsManager.has_method("get_setting"):
		saved = str(SettingsManager.get_setting("language", ""))
	if saved != "" and saved in SUPPORTED_LOCALES:
		set_language(saved)
		return

	# 检测OS语言
	var os_locale := OS.get_locale()
	if os_locale in SUPPORTED_LOCALES:
		set_language(os_locale)
	elif os_locale.begins_with("zh"):
		set_language("zh_CN")
	else:
		set_language(FALLBACK_LOCALE)


func set_language(locale: String) -> void:
	if locale == _current_locale:
		return
	if not locale in SUPPORTED_LOCALES:
		push_warning("不支持的语言: %s" % locale)
		return
	_current_locale = locale
	SettingsManager.set_setting("language", locale)
	language_changed.emit(locale)


func get_language() -> String:
	return _current_locale


func translate(key: String, params: Dictionary = {}) -> String:
	var text := _get_raw(key)
	if params.is_empty():
		return text
	# 替换 {param} 格式的占位符
	for param_key in params:
		text = text.replace("{%s}" % param_key, str(params[param_key]))
	return text


func _get_raw(key: String) -> String:
	# 当前语言查找
	if _translations.has(_current_locale):
		var dict: Dictionary = _translations[_current_locale]
		if dict.has(key):
			return str(dict[key])

	# 回退到英文
	if _current_locale != FALLBACK_LOCALE and _translations.has(FALLBACK_LOCALE):
		var dict: Dictionary = _translations[FALLBACK_LOCALE]
		if dict.has(key):
			return str(dict[key])

	# 都没有就返回key本身
	return key


func get_supported_locales() -> Array:
	return SUPPORTED_LOCALES
