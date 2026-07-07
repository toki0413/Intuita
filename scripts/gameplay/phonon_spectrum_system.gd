# phonon_spectrum_system.gd
# 声子谱系统 - 基于Debye模型的晶格振动分析
# 简化弹簧-质量模型: ω² = k/m, 声子态密度 g(ω) = 3ω²/ω_D³
# Debye温度 θ_D = ℏω_D/k_B 决定比热容行为
# 连接: 应变场→弹性常数→声速→Debye温度; 热力学→振动熵; 相变→声子软化

extends RefCounted

signal phonon_mode_softened(mode_name: String, frequency: float)
signal debye_temperature_changed(old_temp: float, new_temp: float)
signal phonon_instability_detected(branch: String, softening_ratio: float)

# 物理常数
const HBAR: float = 6.582e-16       # eV·s
const K_B: float = 8.617e-5         # eV/K
const A_TO_M: float = 1.660e-27     # kg (原子质量单位)

# Debye模型参数
const DEBYE_CUTOFF_FACTOR: float = 1.0
const SOFTENING_THRESHOLD: float = 0.3   # 软模阈值: ω/ω₀ < 0.3 时触发不稳定
const MAX_PHONON_FREQ: float = 1e14      # Hz, 上限截断

var _canvas: Node3D = null
var _atom_mgr = null
var _float_text = null

# 每个原子的振动数据
# atom_id -> {mass, spring_k, position, neighbors: [atom_id, distance, k]}
var _phonon_data: Dictionary = {}

# 累积量: 总原子数、总键能、平均声速
var _total_atoms: int = 0
var _total_bonds: int = 0
var _avg_sound_velocity: float = 5000.0  # m/s, 默认声速
var _debye_temp: float = 300.0           # K
var _last_debye_temp: float = 300.0

# 声子分支软化追踪
var _branch_softening: Dictionary = {
	"LA": 1.0,   # 纵声学
	"TA1": 1.0,  # 横声学1
	"TA2": 1.0,  # 横声学2
	"LO": 1.0,   # 纵光学
	"TO": 1.0,   # 横光学
}

# 元素质量（原子质量单位）
const ATOMIC_MASSES: Dictionary = {
	"H": 1.0, "He": 4.0, "Li": 7.0, "Be": 9.0, "B": 11.0,
	"C": 12.0, "N": 14.0, "O": 16.0, "F": 19.0,
	"Na": 23.0, "Mg": 24.0, "Al": 27.0, "Si": 28.0,
	"P": 31.0, "S": 32.0, "Cl": 35.5,
	"Fe": 56.0, "Cu": 64.0, "Zn": 65.0, "Mn": 55.0, "Ni": 59.0, "Co": 59.0,
}

# 元素弹簧常数（简化: N/m, 基于共价半径和电负性）
const SPRING_CONSTANTS: Dictionary = {
	"H": 500.0, "C": 800.0, "N": 700.0, "O": 900.0,
	"F": 600.0, "Na": 80.0, "Mg": 150.0, "Al": 200.0,
	"Si": 300.0, "P": 350.0, "S": 300.0, "Cl": 250.0,
	"Fe": 400.0, "Cu": 350.0, "Zn": 300.0,
}

func _init(canvas: Node3D, atom_mgr, float_text) -> void:
	_canvas = canvas
	_atom_mgr = atom_mgr
	_float_text = float_text

# 原子放置时注册声子数据
func on_atom_placed(atom: Node3D) -> void:
	if atom == null or not is_instance_valid(atom):
		return
	var symbol: String = _get_atom_symbol(atom)
	var mass: float = ATOMIC_MASSES.get(symbol, 30.0) * A_TO_M
	var spring_k: float = SPRING_CONSTANTS.get(symbol, 300.0)
	var a_id: int = atom.get_instance_id()
	_phonon_data[a_id] = {
		"mass": mass,
		"spring_k": spring_k,
		"position": atom.global_position,
		"symbol": symbol,
		"node": atom,
	}
	_total_atoms += 1
	_recompute_debye_temperature()

# 原子移除时注销
func on_atom_removed(atom: Node3D) -> void:
	if atom == null:
		return
	var a_id: int = atom.get_instance_id()
	if _phonon_data.has(a_id):
		_phonon_data.erase(a_id)
		_total_atoms = max(0, _total_atoms - 1)
		_recompute_debye_temperature()

# 键形成时更新弹簧网络
func on_bond_formed(atom_a: Node3D, atom_b: Node3D, bond_energy: float) -> void:
	if atom_a == null or atom_b == null:
		return
	_total_bonds += 1
	# 键能越强，弹簧常数越大
	var k_factor: float = maxf(0.1, bond_energy / 4.0)
	var a_id: int = atom_a.get_instance_id()
	var b_id: int = atom_b.get_instance_id()
	if _phonon_data.has(a_id):
		_phonon_data[a_id]["spring_k"] += k_factor * 100.0
	if _phonon_data.has(b_id):
		_phonon_data[b_id]["spring_k"] += k_factor * 100.0
	_recompute_debye_temperature()

# 计算Debye温度: θ_D = ℏω_D/k_B
# ω_D = v_s * k_D, k_D = (6π²n)^(1/3), n = 原子数密度
func _recompute_debye_temperature() -> void:
	if _total_atoms == 0:
		_debye_temp = 300.0
		return
	
	# 计算平均声速: v_s = sqrt(K/ρ), K=体弹模量, ρ=密度
	# 简化: v_s ∝ sqrt(平均弹簧常数/平均质量)
	var total_k: float = 0.0
	var total_m: float = 0.0
	for a_id in _phonon_data:
		total_k += _phonon_data[a_id]["spring_k"]
		total_m += _phonon_data[a_id]["mass"]
	
	if total_m <= 0.0:
		return
	
	var avg_k: float = total_k / float(_total_atoms)
	var avg_m: float = total_m / float(_total_atoms)
	# v_s = sqrt(k/m), 单位换算后约为 m/s
	_avg_sound_velocity = sqrt(avg_k / avg_m) * 1e5  # 缩放到合理范围
	_avg_sound_velocity = clampf(_avg_sound_velocity, 1000.0, 15000.0)
	
	# 原子数密度（简化: 假设立方排列，间距约2.5Å）
	var n_density: float = float(_total_atoms) / pow(2.5e-10, 3)
	var k_D: float = pow(6.0 * PI * PI * n_density, 1.0 / 3.0)
	var omega_D: float = _avg_sound_velocity * k_D
	
	_last_debye_temp = _debye_temp
	_debye_temp = HBAR * omega_D / K_B
	
	# 合理范围: 50K - 2000K
	_debye_temp = clampf(_debye_temp, 50.0, 2000.0)
	
	if absf(_debye_temp - _last_debye_temp) > 10.0:
		debye_temperature_changed.emit(_last_debye_temp, _debye_temp)

# Debye比热容: C_v = 9Nk_B(T/θ_D)³ ∫₀^(θ_D/T) x⁴eˣ/(eˣ-1)² dx
# 简化数值积分
func compute_heat_capacity(temperature: float) -> float:
	if _total_atoms == 0 or _debye_temp <= 0.0:
		return 0.0
	
	var ratio: float = _debye_temp / max(1.0, temperature)
	# 高温极限 (T >> θ_D): C_v → 3Nk_B (Dulong-Petit)
	if ratio < 0.1:
		return 3.0 * float(_total_atoms) * K_B
	
	# 低温极限 (T << θ_D): C_v → (12π⁴/5)Nk_B(T/θ_D)³
	if ratio > 20.0:
		var t_ratio: float = temperature / _debye_temp
		return (12.0 * pow(PI, 4.0) / 5.0) * float(_total_atoms) * K_B * pow(t_ratio, 3.0)
	
	# 中间区域: 数值积分（梯形法）
	var integral: float = _debye_integral(ratio)
	return 9.0 * float(_total_atoms) * K_B * pow(1.0 / ratio, 3.0) * integral

# Debye积分: ∫₀^x x⁴eˣ/(eˣ-1)² dx
func _debye_integral(x_max: float) -> float:
	var n_steps: int = 50
	var dx: float = x_max / float(n_steps)
	var total: float = 0.0
	
	for i in range(n_steps):
		var x: float = (float(i) + 0.5) * dx
		if x < 0.01:
			continue
		var exp_x: float = exp(x)
		var denom: float = pow(exp_x - 1.0, 2.0)
		if denom < 1e-30:
			continue
		total += (x * x * x * x) * exp_x / denom * dx
	
	return total

# 声子态密度 (Debye模型): g(ω) = 3ω²/ω_D³
func phonon_dos(omega: float) -> float:
	if _total_atoms == 0:
		return 0.0
	var n_density: float = float(_total_atoms) / pow(2.5e-10, 3)
	var k_D: float = pow(6.0 * PI * PI * n_density, 1.0 / 3.0)
	var omega_D: float = _avg_sound_velocity * k_D
	if omega_D <= 0.0:
		return 0.0
	if omega > omega_D:
		return 0.0
	return 3.0 * omega * omega / pow(omega_D, 3.0)

# 计算振动熵: S_vib = k_B ∫ g(ω) [(n+1)ln(n+1) - n ln(n)] dω
# n = 1/(e^(ℏω/k_BT) - 1) (Bose-Einstein分布)
func compute_vibrational_entropy(temperature: float) -> float:
	if _total_atoms == 0 or temperature <= 0.0:
		return 0.0
	
	var n_density: float = float(_total_atoms) / pow(2.5e-10, 3)
	var k_D: float = pow(6.0 * PI * PI * n_density, 1.0 / 3.0)
	var omega_D: float = _avg_sound_velocity * k_D
	
	# 数值积分
	var n_steps: int = 30
	var d_omega: float = omega_D / float(n_steps)
	var entropy: float = 0.0
	
	for i in range(n_steps):
		var omega: float = (float(i) + 0.5) * d_omega
		var x: float = HBAR * omega / (K_B * temperature)
		if x < 0.01:
			continue
		var n_be: float = 1.0 / (exp(x) - 1.0)  # Bose-Einstein占据数
		var integrand: float = (n_be + 1.0) * log(n_be + 1.0) - n_be * log(n_be)
		entropy += phonon_dos(omega) * integrand * d_omega
	
	return float(_total_atoms) * K_B * entropy

# 声子模软化检测: 检查某分支的频率是否大幅下降
# 软模相变前兆: ω² → 0 表示结构失稳
func check_phonon_softening(strain_info: Dictionary, defect_count: int) -> Dictionary:
	var avg_strain: float = strain_info.get("avg_strain", 0.0)
	var result: Dictionary = {"soft_modes": [], "is_stable": true}
	
	# 应变导致声学模软化: ω' = ω₀(1 - α*ε)
	var strain_factor: float = clampf(1.0 - avg_strain * 2.0, 0.0, 2.0)
	
	# 缺陷导致光学模软化: 每个缺陷降低5%频率
	var defect_factor: float = clampf(1.0 - float(defect_count) * 0.05, 0.0, 2.0)
	
	_branch_softening["LA"] = strain_factor
	_branch_softening["TA1"] = strain_factor * 0.9
	_branch_softening["TA2"] = strain_factor * 0.85
	_branch_softening["LO"] = defect_factor
	_branch_softening["TO"] = defect_factor * 0.95
	
	for branch in _branch_softening:
		var ratio: float = _branch_softening[branch]
		if ratio < SOFTENING_THRESHOLD:
			result["soft_modes"].append(branch)
			result["is_stable"] = false
			phonon_instability_detected.emit(branch, ratio)
			if _float_text != null:
				_float_text.show_float_text(
					Vector3(0, 2.5, 0),
					"软模: %s (%.0f%%)" % [branch, ratio * 100.0],
					Color(1.0, 0.3, 0.5),
					3.0
				)
		elif ratio < 0.5:
			phonon_mode_softened.emit(branch, ratio)
	
	return result

# 获取Debye温度
func get_debye_temperature() -> float:
	return _debye_temp

# 获取声速
func get_sound_velocity() -> float:
	return _avg_sound_velocity

# 获取分支软化状态
func get_branch_softening() -> Dictionary:
	return _branch_softening.duplicate()

# 热导率简化估计: κ = (1/3)C_v v_s l (l=声子平均自由程)
func estimate_thermal_conductivity(temperature: float) -> float:
	var c_v: float = compute_heat_capacity(temperature)
	# 简化: 声子平均自由程随温度降低 (Umklapp散射)
	var mean_free_path: float = 1e-9 / max(0.1, temperature / 300.0)
	return (1.0 / 3.0) * c_v * _avg_sound_velocity * mean_free_path

# 拉曼活性模预测（简化）
func predict_raman_active_modes() -> Array:
	var modes: Array = []
	if _total_atoms == 0:
		return modes
	
	# 简化: 光学模中对称性允许的为拉曼活性
	for branch in ["LO", "TO"]:
		var ratio: float = _branch_softening.get(branch, 1.0)
		var omega_D: float = _debye_temp * K_B / HBAR
		var omega: float = omega_D * ratio * 0.8  # 光学模约在0.8 ω_D
		modes.append({
			"branch": branch,
			"frequency": omega,
			"intensity": ratio,  # 软化越严重强度越低
			"raman_active": ratio > 0.2,
		})
	return modes

# 获取声子谱摘要
func get_phonon_info() -> Dictionary:
	return {
		"debye_temp": _debye_temp,
		"sound_velocity": _avg_sound_velocity,
		"total_atoms": _total_atoms,
		"total_bonds": _total_bonds,
		"branch_softening": _branch_softening.duplicate(),
		"heat_capacity_300k": compute_heat_capacity(300.0),
		"vib_entropy_300k": compute_vibrational_entropy(300.0),
		"thermal_conductivity_300k": estimate_thermal_conductivity(300.0),
	}

func on_level_reset() -> void:
	_phonon_data.clear()
	_total_atoms = 0
	_total_bonds = 0
	_debye_temp = 300.0
	_last_debye_temp = 300.0
	_avg_sound_velocity = 5000.0
	_branch_softening = {
		"LA": 1.0, "TA1": 1.0, "TA2": 1.0, "LO": 1.0, "TO": 1.0,
	}

func _get_atom_symbol(atom: Node3D) -> String:
	if atom == null:
		return ""
	var sym: Variant = atom.get("element_symbol")
	if sym == null:
		return ""
	return str(sym)
