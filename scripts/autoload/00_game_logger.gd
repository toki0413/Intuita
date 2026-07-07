# logger.gd
# 结构化日志系统 - 分级日志、文件输出、日志轮转、内存环形缓冲
#
# Responsibilities:
#   - 分级日志输出 (DEBUG/INFO/WARN/ERROR)
#   - 模块标签标识每条日志来源
#   - 文件输出到 user://logs/ 目录
#   - 7天日志轮转，自动清理过期文件
#   - 性能日志记录
#   - 内存环形缓冲保留最近100条用于崩溃上下文
#
# Signals:
#   无 (Logger不应依赖信号，避免循环)
#
# Dependencies:
#   - Autoload: 无 (必须是最先加载的autoload)

extends Node

enum Level { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 }

const RING_BUFFER_SIZE := 100
const LOG_ROTATION_DAYS := 7
const LOG_DIR := "user://logs"

var _current_level: int = Level.INFO
var _ring_buffer: Array[Dictionary] = []
var _ring_index: int = 0
var _log_file: FileAccess = null
var _current_log_path: String = ""
var _flush_timer: float = 0.0
const FLUSH_INTERVAL := 5.0  # 每5秒刷盘一次


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_log_dir()
	_open_log_file()
	_rotate_old_logs()

	# 开发环境默认DEBUG级别
	if OS.is_debug_build():
		_current_level = Level.DEBUG

	_log_raw(Level.INFO, "Logger", "Logger initialized, level=%d" % _current_level, {})


func _process(delta: float) -> void:
	_flush_timer += delta
	if _flush_timer >= FLUSH_INTERVAL:
		_flush_timer = 0.0
		flush()


func _exit_tree() -> void:
	flush()
	if _log_file:
		_log_file.close()
		_log_file = null


# ============ 公共API ============

func debug(module: String, message: String, context: Dictionary = {}) -> void:
	if _current_level <= Level.DEBUG:
		_log_raw(Level.DEBUG, module, message, context)


func info(module: String, message: String, context: Dictionary = {}) -> void:
	if _current_level <= Level.INFO:
		_log_raw(Level.INFO, module, message, context)


func warn(module: String, message: String, context: Dictionary = {}) -> void:
	if _current_level <= Level.WARN:
		_log_raw(Level.WARN, module, message, context)


func error(module: String, message: String, context: Dictionary = {}) -> void:
	if _current_level <= Level.ERROR:
		_log_raw(Level.ERROR, module, message, context)


func perf(module: String, operation: String, duration_ms: float) -> void:
	var ctx := {"operation": operation, "duration_ms": duration_ms}
	_log_raw(Level.INFO, "Perf|%s" % module, "%s took %.2fms" % [operation, duration_ms], ctx)


func set_level(level: int) -> void:
	_current_level = clampi(level, Level.DEBUG, Level.ERROR)


func get_level() -> int:
	return _current_level


func get_recent(count: int = 20) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var total := _ring_buffer.size()
	var start := maxi(0, total - count)
	for i in range(start, total):
		result.append(_ring_buffer[i])
	return result


func flush() -> void:
	if _log_file:
		_log_file.flush()


# ============ 内部实现 ============

func _log_raw(level: int, module: String, message: String, context: Dictionary) -> void:
	var level_name: String = Level.keys()[level]
	var timestamp := Time.get_datetime_string_from_system()
	var context_str := ""
	if not context.is_empty():
		context_str = " | " + JSON.stringify(context)

	var formatted := "[%s] [%s] [%s] %s%s" % [timestamp, level_name, module, message, context_str]

	# 控制台输出
	match level:
		Level.ERROR:
			push_error(formatted)
		Level.WARN:
			push_warning(formatted)
		_:
			print(formatted)

	# 写入文件
	if _log_file:
		_log_file.store_line(formatted)

	# 环形缓冲
	var entry := {
		"timestamp": timestamp,
		"level": level,
		"level_name": level_name,
		"module": module,
		"message": message,
		"context": context,
	}
	if _ring_buffer.size() < RING_BUFFER_SIZE:
		_ring_buffer.append(entry)
	else:
		_ring_buffer[_ring_index] = entry
		_ring_index = (_ring_index + 1) % RING_BUFFER_SIZE


func _ensure_log_dir() -> void:
	var dir := DirAccess.open("user://")
	if dir and not dir.dir_exists("logs"):
		dir.make_dir("logs")


func _open_log_file() -> void:
	var date := Time.get_date_string_from_system().replace("-", "")
	_current_log_path = "%s/intuita_%s.log" % [LOG_DIR, date]

	# 追加模式打开
	_log_file = FileAccess.open(_current_log_path, FileAccess.WRITE_READ)
	if _log_file == null:
		push_warning("Logger: cannot open log file %s" % _current_log_path)
		return

	# 如果文件已有内容，跳到末尾追加
	var file_size := _log_file.get_length()
	if file_size > 0:
		_log_file.seek(file_size)


func _rotate_old_logs() -> void:
	var dir := DirAccess.open(LOG_DIR)
	if dir == null:
		return

	var now := Time.get_unix_time_from_system()
	var cutoff := now - (LOG_ROTATION_DAYS * 86400)

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.begins_with("intuita_") and file_name.ends_with(".log"):
			var full_path := "%s/%s" % [LOG_DIR, file_name]
			var modified := FileAccess.get_modified_time(full_path)
			if modified > 0 and modified < cutoff:
				dir.remove(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
