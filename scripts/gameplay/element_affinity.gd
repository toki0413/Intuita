# element_affinity.gd
# 元素亲和度系统 - 每个关卡有主题元素和相克元素

class_name ElementAffinity
extends RefCounted

var _float_text: FloatingTextSystem = null

# 当前关卡亲和度配置
var _favored_element: String = ""
var _disfavored_element: String = ""
var _favored_multiplier: float = 2.0
var _disfavored_penalty: float = 1.5

func _init(float_text: FloatingTextSystem) -> void:
	_float_text = float_text

func setup_for_level(level_data: Dictionary) -> void:
	# 从关卡数据中读取亲和度配置，如果没有则根据域自动生成
	var affinity: Dictionary = level_data.get("element_affinity", {})
	if affinity.size() > 0:
		_favored_element = affinity.get("favored", "")
		_disfavored_element = affinity.get("disfavored", "")
		_favored_multiplier = affinity.get("favored_multiplier", 2.0)
		_disfavored_penalty = affinity.get("disfavored_penalty", 1.5)
	else:
		_generate_affinity_from_domain(level_data.get("domain", "crystal"))

func _generate_affinity_from_domain(domain: String) -> void:
	# 根据域自动生成主题元素
	var domain_elements: Dictionary = {
		"crystal": {"favored": "Na", "disfavored": "Li"},
		"molecular": {"favored": "O", "disfavored": "Fe"},
		"thermodynamics": {"favored": "Fe", "disfavored": "F"},
		"optics": {"favored": "Cl", "disfavored": "Na"},
		"surface": {"favored": "Li", "disfavored": "Cl"},
		"open": {"favored": "H", "disfavored": "Fe"},
	}
	var config: Dictionary = domain_elements.get(domain, {"favored": "", "disfavored": ""})
	_favored_element = config["favored"]
	_disfavored_element = config["disfavored"]

func on_atom_placed(atom: Node3D, element_symbol: String) -> Dictionary:
	var result := {"score_multiplier": 1.0, "unstable_boost": 0.0, "message": ""}
	
	if element_symbol == _favored_element and _favored_element != "":
		result["score_multiplier"] = _favored_multiplier
		result["message"] = "%s 亲和加成!" % _favored_element
		if _float_text != null and atom != null:
			_float_text.show_affinity_bonus(atom.global_position, _favored_element, _favored_multiplier)
		# 主题元素减缓瓦解速度
		result["unstable_boost"] = -0.1
		
	elif element_symbol == _disfavored_element and _disfavored_element != "":
		result["score_multiplier"] = 1.0 / _disfavored_penalty
		result["message"] = "%s 相克惩罚!" % _disfavored_element
		if _float_text != null and atom != null:
			_float_text.show_float_text(
				atom.global_position,
				"%s 相克! 瓦解加速!" % _disfavored_element,
				Color(0.8, 0.2, 0.2),
				1.5
			)
		# 相克元素加速瓦解
		result["unstable_boost"] = 0.15
	
	return result

func get_affinity_info() -> Dictionary:
	return {
		"favored": _favored_element,
		"disfavored": _disfavored_element,
		"favored_multiplier": _favored_multiplier,
		"disfavored_penalty": _disfavored_penalty,
	}

func get_favored_element() -> String:
	return _favored_element

func get_disfavored_element() -> String:
	return _disfavored_element
