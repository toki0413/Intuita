# thermodynamic_stability.gd
# 热力学稳定性引擎 - 统一能量框架
# Gibbs自由能: G = H - T*S
# H(焓) = 键能 + 缺陷能 + 应变能
# S(熵) = 配置熵 + 振动熵(简化)
# 稳定性判定影响: 验证层折扣、核心奖励倍率、瓦解阈值

extends RefCounted

signal stability_changed(stability_class: String, gibbs_energy: float)
signal metastable_detected(energy_barrier: float)
signal ground_state_achieved(bonus: int)

# 稳定性等级
enum Stability { UNSTABLE, METASTABLE, STABLE, GROUND_STATE }

const STABILITY_LABELS: Dictionary = {
	Stability.UNSTABLE: "不稳定",
	Stability.METASTABLE: "亚稳态",
	Stability.STABLE: "稳定",
	Stability.GROUND_STATE: "基态",
}

const STABILITY_COLORS: Dictionary = {
	Stability.UNSTABLE: Color(1.0, 0.2, 0.2),
	Stability.METASTABLE: Color(1.0, 0.6, 0.2),
	Stability.STABLE: Color(0.3, 0.8, 0.4),
	Stability.GROUND_STATE: Color(0.2, 0.5, 1.0),
}

# 键能参数（简化：eV/键）
const BOND_ENERGIES: Dictionary = {
	"H-H": 4.52, "H-O": 4.78, "H-C": 4.36, "H-N": 4.05,
	"C-C": 3.61, "C=C": 6.14, "C≡C": 8.39,
	"C-O": 3.74, "C=O": 7.45, "C-N": 3.05,
	"O-O": 1.51, "O=O": 5.02,
	"N-N": 1.63, "N≡N": 9.45,
	"Na-Cl": 4.26, "Na-O": 2.62,
	"Fe-O": 4.03, "Fe-Fe": 1.68,
	"Cu-O": 2.81, "Cu-Cu": 1.34,
	"default": 2.5,
}

# 元素原子质量（简化）
const ATOMIC_MASSES: Dictionary = {
	"H": 1.0, "He": 4.0, "Li": 7.0, "Be": 9.0, "B": 11.0,
	"C": 12.0, "N": 14.0, "O": 16.0, "F": 19.0,
	"Na": 23.0, "Mg": 24.0, "Al": 27.0, "Si": 28.0,
	"P": 31.0, "S": 32.0, "Cl": 35.5,
	"Fe": 56.0, "Cu": 64.0, "Zn": 65.0, "Mn": 55.0, "Ni": 59.0, "Co": 59.0,
}

# Boltzmann常数（eV/K）
const K_B: float = 8.617e-5

var _canvas: Node3D = null
var _atom_mgr = null
var _float_text = null

var _current_stability: int = Stability.STABLE
var _gibbs_energy: float = 0.0
var _enthalpy: float = 0.0
var _entropy: float = 0.0
var _temperature: float = 300.0
var _last_stability: int = Stability.STABLE

func _init(canvas: Node3D, atom_mgr, float_text) -> void:
	_canvas = canvas
	_atom_mgr = atom_mgr
	_float_text = float_text

# 主计算：重新计算Gibbs自由能
func recalculate(atom_count: int, bond_count: int, defect_count: int, strain_info: Dictionary) -> void:
	_enthalpy = _compute_enthalpy(atom_count, bond_count, defect_count, strain_info)
	_entropy = _compute_entropy(atom_count, defect_count)
	_gibbs_energy = _enthalpy - _temperature * _entropy
	
	var new_stability: int = _classify_stability(_gibbs_energy, atom_count)
	
	if new_stability != _current_stability:
		_last_stability = _current_stability
		_current_stability = new_stability
		stability_changed.emit(STABILITY_LABELS[new_stability], _gibbs_energy)
		_on_stability_transition(new_stability)

# 计算焓 H
func _compute_enthalpy(atom_count: int, bond_count: int, defect_count: int, strain_info: Dictionary) -> float:
	# 键能贡献：按键类型查表，没找到用默认值
	var bond_energy: float = 0.0
	if _atom_mgr != null:
		var bonds = _atom_mgr.get("_bonds")
		if bonds:
			for bond in bonds:
				if not is_instance_valid(bond):
					continue
				var a = bond.get("atom_a")
				var b = bond.get("atom_b")
				if a == null or b == null or not is_instance_valid(a) or not is_instance_valid(b):
					continue
				var sym_a = a.get("element_symbol")
				var sym_b = b.get("element_symbol")
				var key = _bond_key(sym_a, sym_b)
				bond_energy += BOND_ENERGIES.get(key, BOND_ENERGIES["default"]) * -1.0
	else:
		bond_energy = float(bond_count) * BOND_ENERGIES["default"] * -1.0

	# 缺陷能：每个缺陷约+1.5 eV（正=不稳定）
	var defect_energy: float = float(defect_count) * 1.5

	# 应变能：来自应变场系统
	var strain_mag: float = strain_info.get("avg_strain", 0.0)
	var strain_energy: float = strain_mag * float(atom_count) * 0.5

	return bond_energy + defect_energy + strain_energy

func _bond_key(a: String, b: String) -> String:
	if a < b:
		return "%s-%s" % [a, b]
	return "%s-%s" % [b, a]

# 计算熵 S
func _compute_entropy(atom_count: int, defect_count: int) -> float:
	if atom_count <= 0:
		return 0.0
	
	# 配置熵: S_config = k_B * ln(W)
	# W = C(n, d) = n! / (d! * (n-d)!)
	# 简化: S ≈ k_B * n * H(p) where p = d/n, H = -p*ln(p) - (1-p)*ln(1-p)
	var p_defect: float = float(defect_count) / float(atom_count) if atom_count > 0 else 0.0
	p_defect = clampf(p_defect, 0.001, 0.999)
	var config_entropy: float = K_B * float(atom_count) * (
		-p_defect * log(p_defect) - (1.0 - p_defect) * log(1.0 - p_defect)
	)
	
	# 振动熵（简化）：每个原子贡献k_B的常数熵
	var vib_entropy: float = K_B * float(atom_count) * 1.5
	
	return config_entropy + vib_entropy

# 稳定性分级
func _classify_stability(gibbs: float, atom_count: int) -> int:
	# 按原子数归一化
	var per_atom: float = gibbs / maxf(1.0, float(atom_count))
	
	if per_atom < -3.0:
		return Stability.GROUND_STATE
	elif per_atom < -1.0:
		return Stability.STABLE
	elif per_atom < 0.5:
		return Stability.METASTABLE
	else:
		return Stability.UNSTABLE

# 稳定性转换事件
func _on_stability_transition(new_stability: int) -> void:
	var label: String = STABILITY_LABELS.get(new_stability, "")
	var color: Color = STABILITY_COLORS.get(new_stability, Color.WHITE)
	
	if _float_text != null:
		_float_text.show_float_text(
			Vector3(0, 3, 0),
			"热力学: %s (G=%.2f)" % [label, _gibbs_energy],
			color,
			3.0
		)
	
	match new_stability:
		Stability.GROUND_STATE:
			# 基态奖励
			var bonus: int = 3
			ground_state_achieved.emit(bonus)
			if GameState != null:
				GameState.gain_cores(bonus)
			if SoundManager != null:
				SoundManager.play(SoundManager.SoundType.PROOF_COMPLETE)
		Stability.STABLE:
			if SoundManager != null:
				SoundManager.play(SoundManager.SoundType.VERIFICATION_PASS)
		Stability.METASTABLE:
			metastable_detected.emit(absf(_gibbs_energy))
			if SoundManager != null:
				SoundManager.play(SoundManager.SoundType.CONSERVATION_WARN)
		Stability.UNSTABLE:
			if SoundManager != null:
				SoundManager.play(SoundManager.SoundType.DISINTEGRATE_START)
	
	if GameLogger != null:
		GameLogger.info("Thermo", "[热力学] %s | H=%.2f, S=%.6f, G=%.2f, T=%.0fK" % [
			label, _enthalpy, _entropy, _gibbs_energy, _temperature
		])

# 温度更新
func on_temperature_changed(temp: float) -> void:
	_temperature = temp

# 获取验证层折扣（稳定结构验证更便宜）
func get_verification_discount() -> float:
	match _current_stability:
		Stability.GROUND_STATE:
			return 0.5  # 50%折扣
		Stability.STABLE:
			return 0.8  # 20%折扣
		Stability.METASTABLE:
			return 1.0  # 无折扣
		Stability.UNSTABLE:
			return 1.5  # 50%加价
		_:
			return 1.0

# 获取核心奖励倍率
func get_core_multiplier() -> float:
	match _current_stability:
		Stability.GROUND_STATE:
			return 1.5
		Stability.STABLE:
			return 1.2
		Stability.METASTABLE:
			return 1.0
		Stability.UNSTABLE:
			return 0.7
		_:
			return 1.0

# 获取瓦解阈值修正
func get_disintegration_threshold_modifier() -> float:
	# 越稳定，瓦解阈值越高（越不容易瓦解）
	# ponytail: 幅度收小避免过早瓦解，下限 -0.05 防止跌破 CRITICAL_THRESHOLD
	match _current_stability:
		Stability.GROUND_STATE:
			return 0.1  # +10%阈值
		Stability.STABLE:
			return 0.05
		Stability.METASTABLE:
			return 0.0
		Stability.UNSTABLE:
			return -0.05  # -5%阈值，不再大幅降低
		_:
			return 0.0

func get_current_stability() -> int:
	return _current_stability

func get_stability_label() -> String:
	return STABILITY_LABELS.get(_current_stability, "未知")

func get_stability_color() -> Color:
	return STABILITY_COLORS.get(_current_stability, Color.WHITE)

func get_gibbs_energy() -> float:
	return _gibbs_energy

func get_enthalpy() -> float:
	return _enthalpy

func get_entropy() -> float:
	return _entropy

func get_info() -> Dictionary:
	return {
		"stability": STABILITY_LABELS.get(_current_stability, ""),
		"gibbs": _gibbs_energy,
		"enthalpy": _enthalpy,
		"entropy": _entropy,
		"temperature": _temperature,
		"verification_discount": get_verification_discount(),
		"core_multiplier": get_core_multiplier(),
		"disintegration_modifier": get_disintegration_threshold_modifier(),
	}

func on_level_reset() -> void:
	_current_stability = Stability.STABLE
	_last_stability = Stability.STABLE
	_gibbs_energy = 0.0
	_enthalpy = 0.0
	_entropy = 0.0
	_temperature = 300.0
