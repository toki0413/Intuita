# conservation_engine.gd
# 守恒矩阵引擎 - 4x4矩阵跟踪质量、电荷、动量、能量
# 优先使用Rust后端(nalgebra)计算特征值，GDScript作为回退
#
# Responsibilities:
#   - 维护4x4守恒矩阵（质量/电荷/动量/能量）
#   - 优先通过Rust ConservationMatrix做矩阵运算
#   - Rust不可用时回退到GDScript的Householder+QR实现
#   - 根据特征值偏离度判定守恒状态
#   - 触发瓦解级联
#
# Signals:
#   state_changed(old_state, new_state) - 守恒状态变化
#   eigenvalue_warning(index, value) - 特征值偏离警告
#   disintegration_triggered(reason) - 瓦解触发
#
# Dependencies:
#   - Autoload: 无（被其他系统依赖）
#   - Optional: Rust ConservationMatrix class

extends Node
enum State { HEALTHY, WARNING, CRITICAL, DISINTEGRATED }

# 行/列标签: 0=mass, 1=charge, 2=momentum, 3=energy
const ROW_NAMES := ["mass", "charge", "momentum", "energy"]

var matrix: Array = []  # 4x4 float array (GDScript fallback用)
var _state: State = State.HEALTHY
var _eigenvalues: Array = []  # cached eigenvalues

# Rust后端引用
var _rust_matrix: RefCounted = null

# G2: 追踪上次偏离的操作和行
var _last_operation: String = ""
var _last_deviating_row: int = -1

# G2: 安全状态快照（用于回溯）
var _safe_matrix: Array = []
var _safe_eigenvalues: Array = []

# 阈值
const WARNING_THRESHOLD := 0.3
const CRITICAL_THRESHOLD := 0.6
const DISINTEGRATE_THRESHOLD := 0.9
# 热力学稳定性对瓦解阈值的动态修正（由 ThermoSystem 设置）
# 正值=更稳定(阈值更高)，负值=更不稳定(阈值更低)
var stability_threshold_modifier: float = 0.0
const RESONANCE_MIN_ROWS := 2  # 触发共振所需的最少WARNING行数
const RESONANCE_CRASH_CHANCE := 0.3  # 共振时连锁崩溃概率
const RESONANCE_BOOST_MULT := 2.0  # 共振加成倍率

# 色盲安全配色: [正常, 红色盲, 绿色盲, 蓝色盲]
var _healthy_colors: Array[Color] = [
	Color(0.2, 0.8, 0.2),   # 正常: 绿
	Color(0.2, 0.5, 0.9),   # 红色盲: 蓝
	Color(0.2, 0.5, 0.9),   # 绿色盲: 蓝
	Color(0.9, 0.3, 0.2),   # 蓝色盲: 红
]
var _warning_colors: Array[Color] = [
	Color(0.9, 0.8, 0.1),   # 正常: 黄
	Color(0.9, 0.7, 0.2),   # 红色盲: 黄橙
	Color(0.9, 0.6, 0.1),   # 绿色盲: 橙
	Color(0.2, 0.5, 0.9),   # 蓝色盲: 蓝
]
var _critical_colors: Array[Color] = [
	Color(0.9, 0.3, 0.1),   # 正常: 红
	Color(0.6, 0.6, 0.6),   # 红色盲: 灰
	Color(0.6, 0.6, 0.6),   # 绿色盲: 灰
	Color(0.6, 0.6, 0.6),   # 蓝色盲: 灰
]
var _dead_colors: Array[Color] = [
	Color(0.5, 0.0, 0.0),   # 正常: 暗红
	Color(0.35, 0.35, 0.35), # 红色盲: 暗灰
	Color(0.35, 0.35, 0.35), # 绿色盲: 暗灰
	Color(0.35, 0.35, 0.35), # 蓝色盲: 暗灰
]

signal state_changed(old_state: int, new_state: int)
signal eigenvalue_warning(index: int, value: float)
signal disintegration_triggered(reason: String)
signal atmosphere_update(state: int)
signal matrix_tuned(row: int, delta: float)  # 矩阵调谐信号
signal resonance_triggered(rows: Array, effect: String)  # 共振触发信号

# 调谐冷却：防止滥用主动操控
var _tune_cooldown: float = 0.0
const TUNE_COOLDOWN_TIME: float = 2.0
const TUNE_MAX_DELTA: float = 0.1  # 单次调谐最大幅度
var _resonance_active: bool = false  # 当前是否处于共振状态
var _resonance_check_timer: float = 0.0
const RESONANCE_CHECK_INTERVAL: float = 0.5  # 共振检测间隔（秒），避免每帧分配


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_try_init_rust_backend()
	_reset_matrix()
	_check_engine_backend()


func _check_engine_backend() -> void:
	# 检查Rust加速是否可用，不可用则使用GDScript实现
	var logger_ref = get_node_or_null("/root/GameLogger")
	if is_instance_valid(ErrorHandler) and ErrorHandler.is_rust_available():
		if logger_ref: logger_ref.info("ConservationEngine", "Using Rust-accelerated backend")
	else:
		if logger_ref: logger_ref.info("ConservationEngine", "Using GDScript fallback (Rust DLL not available)")


func _try_init_rust_backend() -> void:
	if ClassDB.class_exists("ConservationMatrix"):
		_rust_matrix = ClassDB.instantiate("ConservationMatrix")
		if _rust_matrix:
			GameLogger.info("ConservationEngine", "[守恒] Rust后端已初始化")
			return
	_rust_matrix = null
	GameLogger.info("ConservationEngine", "[守恒] Rust后端不可用，使用GDScript回退")


func _reset_matrix() -> void:
	if _rust_matrix:
		_rust_matrix.reset()
	matrix.clear()
	for i in range(4):
		var row: Array = []
		for j in range(4):
			if i == j:
				row.append(1.0)
			else:
				row.append(0.0)
		matrix.append(row)
	_eigenvalues = [1.0, 1.0, 1.0, 1.0]
	_state = State.HEALTHY


func get_state() -> State:
	if _rust_matrix:
		var rust_state: int = _rust_matrix.get_state()
		return rust_state as State
	return _state


func set_entry(row: int, col: int, value: float) -> void:
	if row < 0 or row > 3 or col < 0 or col > 3:
		push_warning("Matrix index out of bounds: [%d][%d]" % [row, col])
		return
	if _rust_matrix:
		var params := {"row": row, "col": col, "delta": value - _rust_matrix.get_entry(row, col)}
		_rust_matrix.apply_operation("perturb", params)
	matrix[row][col] = value


func get_entry(row: int, col: int) -> float:
	if row < 0 or row > 3 or col < 0 or col > 3:
		push_warning("Matrix index out of bounds: [%d][%d]" % [row, col])
		return 0.0
	if _rust_matrix:
		return _rust_matrix.get_entry(row, col)
	return matrix[row][col]


func apply_perturbation(row: int, col: int, delta: float, operation: String = "") -> void:
	# 防止 NaN/Inf 导致矩阵状态异常
	if is_nan(delta) or is_inf(delta):
		push_warning("[守恒] perturbation delta 异常 (NaN/Inf)，已置零: %f" % delta)
		delta = 0.0
	# 不应用任意硬截断：调用方应保证 delta 的物理合理性。
	# 典型合理上界来自归一化质量分数 (mass / total_cell_mass * 0.05) 或 CA 单步变化
	# 若 delta 超出物理预期，应在调用方修正而非此处掩盖

	_last_operation = operation
	_last_deviating_row = row

	if _rust_matrix:
		var params := {"row": row, "col": col, "delta": delta}
		var result: PackedFloat64Array = _rust_matrix.apply_operation("perturb", params)
		_eigenvalues = []
		for v in result:
			_eigenvalues.append(v)
		# 同步更新 GDScript matrix (Rust 对称应用，这里也要)
		matrix[row][col] = matrix[row][col] + delta
		if row != col:
			matrix[col][row] = matrix[col][row] + delta
		_recompute_state_from_eigenvalues()
	else:
		# Rust 后端对称应用扰动 (matrix[(row,col)] += delta; matrix[(col,row)] += delta)
		# GDScript 回退必须保持同样行为，否则非对角扰动只改上三角，特征值不变
		set_entry(row, col, matrix[row][col] + delta)
		if row != col:
			set_entry(col, row, matrix[col][row] + delta)
		_recompute_state()
	# 矩阵变更后立即检测共振
	_check_resonance()


func reset() -> void:
	var old := _state
	_reset_matrix()
	_safe_matrix.clear()
	_safe_eigenvalues.clear()
	_last_operation = ""
	_last_deviating_row = -1
	_tune_cooldown = 0.0
	_resonance_active = false
	_resonance_check_timer = 0.0
	if old != _state:
		state_changed.emit(old, _state)


func tune(row: int, delta: float) -> bool:
	# 主动调谐守恒矩阵：降低某行偏离（delta<0）或增加偏离（delta>0）
	# 有冷却时间防止滥用，单次幅度有上限
	if _tune_cooldown > 0.0:
		push_warning("[守恒] 调谐冷却中，剩余 %.1fs" % _tune_cooldown)
		return false
	if row < 0 or row >= 4:
		push_warning("[守恒] 调谐行号越界: %d" % row)
		return false
	# 限制单次调谐幅度
	delta = clampf(delta, -TUNE_MAX_DELTA, TUNE_MAX_DELTA)
	apply_perturbation(row, row, delta, "tune_row_%d" % row)
	_tune_cooldown = TUNE_COOLDOWN_TIME
	matrix_tuned.emit(row, delta)
	return true


func _process(delta: float) -> void:
	if _tune_cooldown > 0.0:
		_tune_cooldown = maxf(_tune_cooldown - delta, 0.0)
	# 共振检测降频到每0.5秒一次，避免每帧分配Dictionary
	_resonance_check_timer += delta
	if _resonance_check_timer >= RESONANCE_CHECK_INTERVAL:
		_resonance_check_timer = 0.0
		_check_resonance()


func _check_resonance() -> void:
	# 共振检测：当≥2行同时处于WARNING(0.1-0.3)时触发
	var dev_summary: Dictionary = get_deviation_summary()
	var warning_rows: Array = []
	for key in dev_summary:
		var dev: float = dev_summary[key]["deviation"]
		if dev > 0.1 and dev <= WARNING_THRESHOLD:
			warning_rows.append(int(key))
	if warning_rows.size() >= RESONANCE_MIN_ROWS:
		if not _resonance_active:
			_resonance_active = true
			# 触发共振效果：30%连锁崩溃，70%共振加成
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			if rng.randf() < RESONANCE_CRASH_CHANCE:
				# 连锁崩溃：偏离放大
				for row in warning_rows:
					apply_perturbation(row, row, 0.05, "resonance_crash_row_%d" % row)
				resonance_triggered.emit(warning_rows, "crash")
			else:
				# 共振加成：标记状态，让后续操作效率翻倍
				resonance_triggered.emit(warning_rows, "boost")
	else:
		_resonance_active = false


func is_resonance_active() -> bool:
	return _resonance_active


func get_resonance_boost() -> float:
	# 共振加成倍率（供操作效率计算使用）
	return RESONANCE_BOOST_MULT if _resonance_active else 1.0


func compute_eigenvalues() -> Array:
	if _rust_matrix:
		var result: PackedFloat64Array = _rust_matrix.get_eigenvalues()
		_eigenvalues = []
		for v in result:
			_eigenvalues.append(v)
		return _eigenvalues
	return _compute_eigenvalues_gdscript()


# ---- GDScript回退实现 ----

func _compute_eigenvalues_gdscript() -> Array:
	var a := MatrixMath.copy_matrix(matrix)
	MatrixMath.hessenberg_reduce(a)
	_eigenvalues = MatrixMath.qr_eigenvalues(a, 50)
	return _eigenvalues


# ---- 状态判定 ----

func _recompute_state() -> void:
	compute_eigenvalues()
	_recompute_state_from_eigenvalues()


func _recompute_state_from_eigenvalues() -> void:
	var old_state := _state
	var max_deviation: float = 0.0
	var worst_index: int = 0

	for i in range(4):
		var deviation: float = absf(_eigenvalues[i] - 1.0)
		if deviation > max_deviation:
			max_deviation = deviation
			worst_index = i

	for i in range(4):
		var dev: float = absf(_eigenvalues[i] - 1.0)
		if dev > WARNING_THRESHOLD:
			eigenvalue_warning.emit(i, _eigenvalues[i])

	# 热力学稳定性修正瓦解阈值：稳定结构更难瓦解
	var effective_threshold: float = DISINTEGRATE_THRESHOLD + stability_threshold_modifier
	if max_deviation > effective_threshold:
		_state = State.DISINTEGRATED
		disintegration_triggered.emit("Eigenvalue %d deviated by %.2f" % [worst_index, max_deviation])
	elif max_deviation > CRITICAL_THRESHOLD:
		_state = State.CRITICAL
	elif max_deviation > WARNING_THRESHOLD:
		_state = State.WARNING
	else:
		_state = State.HEALTHY

	if old_state != _state:
		state_changed.emit(old_state, _state)
		atmosphere_update.emit(_state)

	# 状态为HEALTHY时保存安全快照
	if _state == State.HEALTHY:
		_save_safe_state()


func get_state_color(state: int) -> Color:
	var mode: int = 0
	# 安全访问SettingsManager（autoload可能尚未就绪）
	if is_instance_valid(SettingsManager):
		mode = SettingsManager.get_setting("colorblind_mode", 0)
	mode = clampi(mode, 0, 3)
	match state:
		0: return _healthy_colors[mode]
		1: return _warning_colors[mode]
		2: return _critical_colors[mode]
		3: return _dead_colors[mode]
	return Color.WHITE


func get_deviation_summary() -> Dictionary:
	var result: Dictionary = {}
	for i in range(4):
		result[ROW_NAMES[i]] = {
			"eigenvalue": _eigenvalues[i],
			"deviation": absf(_eigenvalues[i] - 1.0)
		}
	return result


# ---- G2: 法医分析支持 ----

func get_failure_info() -> Dictionary:
	var deviation := 0.0
	if _last_deviating_row >= 0 and _last_deviating_row < _eigenvalues.size():
		deviation = absf(_eigenvalues[_last_deviating_row] - 1.0)
	return {
		"row": _last_deviating_row,
		"deviation": deviation,
		"operation": _last_operation,
	}


func _save_safe_state() -> void:
	_safe_matrix.clear()
	for i in range(4):
		var row: Array = []
		for j in range(4):
			row.append(matrix[i][j])
		_safe_matrix.append(row)
	_safe_eigenvalues = []
	for v in _eigenvalues:
		_safe_eigenvalues.append(v)


func reset_to_safe_state() -> void:
	if _safe_matrix.is_empty():
		return
	var old := _state
	matrix.clear()
	for i in range(4):
		var row: Array = []
		for j in range(4):
			row.append(_safe_matrix[i][j])
		matrix.append(row)
	_eigenvalues.clear()
	for v in _safe_eigenvalues:
		_eigenvalues.append(v)
	_state = State.HEALTHY
	_last_operation = ""
	_last_deviating_row = -1
	if old != _state:
		state_changed.emit(old, _state)
