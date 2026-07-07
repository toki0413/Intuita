# resonance_cascade_system.gd
# 共振级联 - 基于受迫振子的频率匹配与共振放大
# 受迫振子: x(t) = F₀/(m*sqrt((ω₀²-ω²)² + (γω)²))
# 品质因子 Q = ω₀/γ, 共振时振幅 = Q * F₀/(mω₀²)
# 玩家调频匹配声子模 → 建设性共振强化键(奖励) / 破坏性共振断裂键(风险)
# 连续共振触发级联: 每次共振放大下一次效果

extends RefCounted

signal resonance_achieved(frequency: float, mode_name: String, amplitude: float, is_constructive: bool)
signal cascade_triggered(level: int, total_bonus: float)
signal bond_resonated(atom_a: Node3D, atom_b: Node3D, effect: String)
signal structural_resonance_warning(intensity: float)

# 物理参数
const MIN_FREQUENCY: float = 1e10     # Hz, 最低可调频率
const MAX_FREQUENCY: float = 1e14     # Hz, 最高可调频率
const DEFAULT_DAMPING: float = 0.05   # 阻尼系数 γ
const RESONANCE_BANDWIDTH: float = 0.08  # 共振带宽 (相对偏差8%)
const CASCADE_THRESHOLD: int = 3      # 连续共振次数触发级联

# 共振效果
const CONSTRUCTIVE_BOND_BOOST: float = 1.5   # 建设性共振键能增强倍率
const DESTRUCTIVE_BOND_FACTOR: float = 0.3   # 破坏性共振键能保留比例
const MAX_CASCADE_BONUS: float = 20.0        # 级联上限

var _canvas: Node3D = null
var _atom_mgr = null
var _float_text = null
var _phonon_sys = null  # 联动声子系统

# 玩家当前调频
var _current_frequency: float = 5e12   # Hz, 默认THz范围
var _frequency_locked: bool = false    # 锁频模式

# 共振模数据 (从声子系统获取)
var _resonance_modes: Array = []

# 级联追踪
var _cascade_count: int = 0
var _last_resonance_time: float = 0.0
const CASCADE_WINDOW: float = 12.0

# 活跃共振效果
var _active_resonances: Dictionary = {}  # bond_id -> {freq, amplitude, effect}

func _init(canvas: Node3D, atom_mgr, float_text) -> void:
	_canvas = canvas
	_atom_mgr = atom_mgr
	_float_text = float_text

func set_phonon_system(phonon_sys) -> void:
	_phonon_sys = phonon_sys

# 玩家调频
func tune_frequency(new_freq: float) -> Dictionary:
	_current_frequency = clampf(new_freq, MIN_FREQUENCY, MAX_FREQUENCY)
	return _check_resonance()

# 相对调频 (上/下调节)
func tune_by_delta(delta_factor: float) -> Dictionary:
	# delta_factor: -1.0 到 +1.0, 对数尺度
	var log_freq: float = log(_current_frequency)
	var new_log: float = log_freq + delta_factor * 0.5  # 半个数量级
	_current_frequency = exp(new_log)
	_current_frequency = clampf(_current_frequency, MIN_FREQUENCY, MAX_FREQUENCY)
	return _check_resonance()

# 检查当前频率是否匹配任何共振模
func _check_resonance() -> Dictionary:
	_resonance_modes = _get_available_modes()
	
	var best_mode: Dictionary = {}
	var best_deviation: float = RESONANCE_BANDWIDTH + 1.0
	
	for mode in _resonance_modes:
		if mode["frequency"] <= 0.0:
			continue
		var rel_dev: float = absf(_current_frequency - mode["frequency"]) / mode["frequency"]
		if rel_dev < best_deviation:
			best_deviation = rel_dev
			best_mode = mode
	
	if best_mode.is_empty() or best_deviation > RESONANCE_BANDWIDTH:
		# 无共振
		return {
			"resonance": false,
			"frequency": _current_frequency,
			"deviation": best_deviation,
		}
	
	# 共振! 计算振幅
	# A = F₀ / (m * sqrt((ω₀²-ω²)² + (γω)²))
	# 共振时 A_max = F₀ / (m * γ * ω₀) = Q * F₀/(mω₀²)
	var omega_0: float = best_mode["frequency"] * 2.0 * PI
	var omega: float = _current_frequency * 2.0 * PI
	var gamma: float = DEFAULT_DAMPING * omega_0
	var quality_factor: float = omega_0 / gamma  # Q值
	
	# 振幅 (归一化)
	var denom: float = sqrt(pow(omega_0 * omega_0 - omega * omega, 2.0) + pow(gamma * omega, 2.0))
	var amplitude: float = omega_0 * omega_0 / maxf(denom, 1e-10)
	
	# 判断建设性还是破坏性
	# 模的分支决定: 声学模(低频) → 建设性, 光学模(高频) → 可破坏
	var is_constructive: bool = not best_mode.get("is_optical", false)
	
	# 软化状态影响: 如果该模已软化, 破坏性概率增加
	if best_mode.has("softening_ratio") and best_mode["softening_ratio"] < 0.5:
		is_constructive = false
	
	# 触发共振效果
	_trigger_resonance(best_mode, amplitude, is_constructive, quality_factor)
	
	return {
		"resonance": true,
		"frequency": _current_frequency,
		"mode": best_mode,
		"amplitude": amplitude,
		"quality_factor": quality_factor,
		"is_constructive": is_constructive,
		"deviation": best_deviation,
	}

# 触发共振效果
func _trigger_resonance(mode: Dictionary, amplitude: float, is_constructive: bool, q_factor: float) -> void:
	var mode_name: String = mode.get("name", "未知模")
	var cascade_level: int = 0
	
	# 级联追踪
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_resonance_time < CASCADE_WINDOW:
		_cascade_count += 1
	else:
		_cascade_count = 1
	_last_resonance_time = now
	
	if _cascade_count >= CASCADE_THRESHOLD:
		cascade_level = _cascade_count - CASCADE_THRESHOLD + 1
		_cascade_bonus(cascade_level, amplitude, is_constructive)
	
	# 对键的影响
	_apply_resonance_to_bonds(amplitude, is_constructive, mode_name)
	
	# 视觉反馈
	if _float_text != null:
		var pos: Vector3 = _get_structure_center()
		var effect_text: String = "★ 建设性共振" if is_constructive else "✖ 破坏性共振"
		var color: Color = Color(0.2, 1.0, 0.5) if is_constructive else Color(1.0, 0.3, 0.3)
		_float_text.show_float_text(
			pos + Vector3(0, 2.5, 0),
			"%s: %s" % [effect_text, mode_name],
			color,
			2.5
		)
		_float_text.show_float_text(
			pos + Vector3(0, 3.0, 0),
			"Q=%.1f A=%.2f" % [q_factor, amplitude],
			Color(0.8, 0.9, 1.0),
			2.0
		)
		if cascade_level > 0:
			_float_text.show_float_text(
				pos + Vector3(0, 3.5, 0),
				"级联 x%d!" % cascade_level,
				Color(1.0, 0.85, 0.0),
				3.0
			)
	
	resonance_achieved.emit(_current_frequency, mode_name, amplitude, is_constructive)

# 级联奖励
func _cascade_bonus(level: int, amplitude: float, is_constructive: bool) -> void:
	var bonus: float = level * amplitude * (1.0 if is_constructive else -0.5)
	bonus = clampf(bonus, -MAX_CASCADE_BONUS, MAX_CASCADE_BONUS)
	
	if is_constructive and bonus > 0.0:
		var core_bonus: int = int(bonus)
		GameState.gain_cores(core_bonus)
		cascade_triggered.emit(level, bonus)
	elif not is_constructive and bonus < 0.0:
		# 破坏性级联: 结构共振警告
		structural_resonance_warning.emit(absf(bonus))

# 对键施加共振效果
func _apply_resonance_to_bonds(amplitude: float, is_constructive: bool, mode_name: String) -> void:
	if _atom_mgr == null or not _atom_mgr.has_method("get_atoms"):
		return
	
	var atoms: Array = _atom_mgr.get_atoms()
	if atoms.size() < 2:
		return
	
	# 影响随机一部分键
	var affected_count: int = max(1, atoms.size() / 3)
	for i in range(affected_count):
		if i + 1 >= atoms.size():
			break
		var atom_a: Node3D = atoms[i]
		var atom_b: Node3D = atoms[i + 1]
		if not is_instance_valid(atom_a) or not is_instance_valid(atom_b):
			continue
		
		var effect: String = "strengthen" if is_constructive else "weaken"
		bond_resonated.emit(atom_a, atom_b, effect)
	
	# 如果是破坏性共振且振幅很高，可能触发瓦解
	if not is_constructive and amplitude > 3.0:
		if ConservationEngine != null:
			ConservationEngine.apply_perturbation(2, 2, amplitude * 0.05, "resonance_cascade")

# 获取可用共振模 (从声子系统)
func _get_available_modes() -> Array:
	var modes: Array = []
	
	if _phonon_sys != null and _phonon_sys.has_method("get_phonon_info"):
		var info: Dictionary = _phonon_sys.get_phonon_info()
		var softening: Dictionary = info.get("branch_softening", {})
		var debye_temp: float = info.get("debye_temp", 300.0)
		
		# 从Debye温度推算特征频率
		# ω_D = k_B * θ_D / ℏ
		var K_B: float = 8.617e-5  # eV/K
		var HBAR_EV: float = 6.582e-16  # eV·s
		var omega_D: float = K_B * debye_temp / HBAR_EV  # rad/s
		var freq_D: float = omega_D / (2.0 * PI)  # Hz
		
		# 声学模 (约0.3*freq_D)
		for branch in ["LA", "TA1", "TA2"]:
			var ratio: float = softening.get(branch, 1.0)
			modes.append({
				"name": "%s声学模" % branch,
				"frequency": freq_D * 0.3 * ratio,
				"is_optical": false,
				"softening_ratio": ratio,
			})
		
		# 光学模 (约0.8*freq_D)
		for branch in ["LO", "TO"]:
			var ratio: float = softening.get(branch, 1.0)
			modes.append({
				"name": "%s光学模" % branch,
				"frequency": freq_D * 0.8 * ratio,
				"is_optical": true,
				"softening_ratio": ratio,
			})
	
	# 如果没有声子系统，提供默认模
	if modes.is_empty():
		modes = [
			{"name": "LA声学模", "frequency": 3e12, "is_optical": false, "softening_ratio": 1.0},
			{"name": "TA横声学模", "frequency": 2e12, "is_optical": false, "softening_ratio": 1.0},
			{"name": "LO光学模", "frequency": 8e12, "is_optical": true, "softening_ratio": 1.0},
			{"name": "TO光学模", "frequency": 6e12, "is_optical": true, "softening_ratio": 1.0},
		]
	
	return modes

# 获取结构中心位置
func _get_structure_center() -> Vector3:
	if _atom_mgr == null or not _atom_mgr.has_method("get_atoms"):
		return Vector3.ZERO
	var atoms: Array = _atom_mgr.get_atoms()
	if atoms.is_empty():
		return Vector3.ZERO
	var center: Vector3 = Vector3.ZERO
	var count: int = 0
	for atom in atoms:
		if is_instance_valid(atom):
			center += atom.global_position
			count += 1
	if count > 0:
		center /= count
	return center

# 获取当前频率
func get_current_frequency() -> float:
	return _current_frequency

# 获取共振模列表 (给UI显示)
func get_resonance_modes() -> Array:
	return _get_available_modes()

# 获取级联信息
func get_cascade_info() -> Dictionary:
	return {
		"cascade_count": _cascade_count,
		"current_frequency": _current_frequency,
		"modes_available": _resonance_modes.size(),
		"resonance_bandwidth": RESONANCE_BANDWIDTH,
	}

# 预测某频率的共振效果 (给放置引导系统用)
func predict_resonance(freq: float) -> Dictionary:
	var modes: Array = _get_available_modes()
	var best: Dictionary = {}
	var best_dev: float = 999.0
	
	for mode in modes:
		if mode["frequency"] <= 0.0:
			continue
		var dev: float = absf(freq - mode["frequency"]) / mode["frequency"]
		if dev < best_dev:
			best_dev = dev
			best = mode
	
	if best_dev > RESONANCE_BANDWIDTH:
		return {"will_resonate": false, "deviation": best_dev}
	
	return {
		"will_resonate": true,
		"mode": best,
		"deviation": best_dev,
		"is_constructive": not best.get("is_optical", false),
	}

func on_level_reset() -> void:
	_current_frequency = 5e12
	_frequency_locked = false
	_cascade_count = 0
	_last_resonance_time = 0.0
	_resonance_modes.clear()
	_active_resonances.clear()
