# error_handler.gd
# 错误处理与韧性框架 - 全局错误拦截、优雅降级、恢复策略
#
# Responsibilities:
#   - 全局错误拦截和分类 (FATAL/ERROR/WARNING/INFO)
#   - 优雅降级: Rust不可用时回退GDScript
#   - 恢复策略: LLM不可用→规则提示, 资源缺失→占位符, 存档损坏→备份
#   - safe_call包装器: 带回退的可调用执行
#   - 错误计数和频率追踪
#   - 用户可见错误弹窗
#
# Signals:
#   error_occurred(error_dict) - 错误发生
#   fatal_error(message) - 致命错误
#
# Dependencies:
#   - Autoload: Logger

extends Node

enum Category { FATAL, ERROR, WARNING, INFO }

var _error_counts: Dictionary = {}  # category_name -> count
var _rust_available: bool = false
var _rust_checked: bool = false
var _llm_available: bool = false
var _llm_checked: bool = false

signal error_occurred(error_dict: Dictionary)
signal fatal_error(message: String)


var _logger: Node = null  # Logger autoload引用


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_logger = get_node_or_null("/root/GameLogger")
	_check_rust_availability()
	if _logger:
		_logger.info("ErrorHandler", "Initialized, rust_available=%s" % _rust_available)


# ============ 公共API ============

func report_error(category: String, message: String, context: Dictionary = {}) -> void:
	var error_dict := _build_error_dict(category, message, context)
	_increment_count(category)

	match category:
		"FATAL":
			if _logger: _logger.error("ErrorHandler", "FATAL: %s" % message, context)
			error_occurred.emit(error_dict)
			fatal_error.emit(message)
			_show_fatal_dialog(message)
		"ERROR":
			if _logger: _logger.error("ErrorHandler", message, context)
			error_occurred.emit(error_dict)
		"WARNING":
			if _logger: _logger.warn("ErrorHandler", message, context)
		"INFO":
			if _logger: _logger.info("ErrorHandler", message, context)
		_:
			if _logger: _logger.info("ErrorHandler", message, context)


func report_warning(message: String, context: Dictionary = {}) -> void:
	report_error("WARNING", message, context)


func safe_call(callable: Callable, fallback: Variant = null, context: String = "") -> Variant:
	# 注意：GDScript 无异常机制，safe_call 只能捕获 callable 是否为 null
	if not callable.is_valid():
		if _logger: _logger.warn("ErrorHandler", "safe_call received invalid callable: %s, using fallback" % context)
		return fallback
	
	var result = callable.call()
	return result


func is_rust_available() -> bool:
	_check_rust_availability()
	return _rust_available


func is_llm_available() -> bool:
	return _check_llm_availability()


func get_error_count(category: String = "") -> int:
	if category == "":
		var total := 0
		for key in _error_counts:
			total += _error_counts[key]
		return total
	return _error_counts.get(category, 0)


# ============ 内部实现 ============

func _build_error_dict(category: String, message: String, context: Dictionary) -> Dictionary:
	return {
		"category": category,
		"message": message,
		"context": context,
		"timestamp": Time.get_datetime_string_from_system(),
		"stack_hint": _get_stack_hint(),
	}


func _get_stack_hint() -> String:
	# 获取调用栈的简略信息用于调试
	var stack := get_stack()
	if stack.size() < 3:
		return ""
	# 跳过前两帧(_get_stack_hint和report_error)
	var frame: Dictionary = stack[2]
	var source: String = frame.get("source", "?")
	var line: int = frame.get("line", 0)
	var func_name: String = frame.get("function", "?")
	return "%s:%d @ %s" % [source.get_file(), line, func_name]


func _increment_count(category: String) -> void:
	_error_counts[category] = _error_counts.get(category, 0) + 1


func _check_rust_availability() -> void:
	# 尝试加载Rust DLL - 检查conservation_matrix_rust是否存在
	var rust_lib := ClassDB.class_exists("ConservationMatrix")
	_rust_available = rust_lib
	if not _rust_available:
		if _logger: _logger.info("ErrorHandler", "Rust DLL not found, using GDScript fallback for conservation engine")


func _check_llm_availability() -> bool:
	if not is_instance_valid(LLMBridge):
		return false
	return LLMBridge.has_api_key()


func _show_fatal_dialog(message: String) -> void:
	# 在主线程显示错误对话框
	call_deferred("_deferred_show_fatal", message)


func _deferred_show_fatal(message: String) -> void:
	var i18n = Engine.get_main_loop().root.get_node_or_null("/root/I18nManager")
	var dialog := AcceptDialog.new()
	dialog.title = i18n.translate("error.dialog_title") if i18n != null else "Intuita - Critical Error"
	dialog.dialog_text = message
	dialog.dialog_autowrap = true
	dialog.min_size = Vector2(400, 200)

	# 字体设置: Arial 20pt+ 加粗
	var font := UiAnimator.make_ui_font(22, true)
	if font:
		dialog.add_theme_font_override("font", font)
		dialog.add_theme_font_size_override("font_size", 22)

	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())

	var scene_tree := Engine.get_main_loop() as SceneTree
	if scene_tree and scene_tree.root:
		scene_tree.root.add_child(dialog)
		dialog.popup_centered()
