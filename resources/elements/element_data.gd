extends Resource
# 元素数据资源 - 存储元素周期表前20个元素的基本信息
# 供construction_canvas加载使用

class_name ElementDataResource

@export var elements: Array[Dictionary] = []


func _init() -> void:
	if elements.is_empty():
		_build_default_data()


func _build_default_data() -> void:
	elements = [
		{"symbol": "H",  "atomic_number": 1,  "mass": 1.008,  "electronegativity": 2.20, "covalent_radius": 0.31, "color": Color(1.0, 1.0, 1.0)},
		{"symbol": "He", "atomic_number": 2,  "mass": 4.003,  "electronegativity": 0.0,  "covalent_radius": 0.28, "color": Color(0.85, 1.0, 1.0)},
		{"symbol": "Li", "atomic_number": 3,  "mass": 6.941,  "electronegativity": 0.98, "covalent_radius": 1.28, "color": Color(0.8, 0.5, 1.0)},
		{"symbol": "Be", "atomic_number": 4,  "mass": 9.012,  "electronegativity": 1.57, "covalent_radius": 0.96, "color": Color(0.0, 0.5, 0.0)},
		{"symbol": "B",  "atomic_number": 5,  "mass": 10.81,  "electronegativity": 2.04, "covalent_radius": 0.84, "color": Color(1.0, 0.71, 0.71)},
		{"symbol": "C",  "atomic_number": 6,  "mass": 12.011, "electronegativity": 2.55, "covalent_radius": 0.76, "color": Color(0.5, 0.5, 0.5)},
		{"symbol": "N",  "atomic_number": 7,  "mass": 14.007, "electronegativity": 3.04, "covalent_radius": 0.71, "color": Color(0.05, 0.05, 0.8)},
		{"symbol": "O",  "atomic_number": 8,  "mass": 15.999, "electronegativity": 3.44, "covalent_radius": 0.66, "color": Color(1.0, 0.05, 0.05)},
		{"symbol": "F",  "atomic_number": 9,  "mass": 18.998, "electronegativity": 3.98, "covalent_radius": 0.57, "color": Color(0.56, 0.88, 0.31)},
		{"symbol": "Ne", "atomic_number": 10, "mass": 20.180, "electronegativity": 0.0,  "covalent_radius": 0.58, "color": Color(0.7, 0.89, 0.96)},
		{"symbol": "Na", "atomic_number": 11, "mass": 22.990, "electronegativity": 0.93, "covalent_radius": 1.66, "color": Color(0.67, 0.36, 0.95)},
		{"symbol": "Mg", "atomic_number": 12, "mass": 24.305, "electronegativity": 1.31, "covalent_radius": 1.41, "color": Color(0.0, 0.5, 0.0)},
		{"symbol": "Al", "atomic_number": 13, "mass": 26.982, "electronegativity": 1.61, "covalent_radius": 1.21, "color": Color(0.75, 0.65, 0.65)},
		{"symbol": "Si", "atomic_number": 14, "mass": 28.086, "electronegativity": 1.90, "covalent_radius": 1.11, "color": Color(0.8, 0.65, 0.45)},
		{"symbol": "P",  "atomic_number": 15, "mass": 30.974, "electronegativity": 2.19, "covalent_radius": 1.07, "color": Color(1.0, 0.5, 0.0)},
		{"symbol": "S",  "atomic_number": 16, "mass": 32.065, "electronegativity": 2.58, "covalent_radius": 1.05, "color": Color(1.0, 1.0, 0.19)},
		{"symbol": "Cl", "atomic_number": 17, "mass": 35.453, "electronegativity": 3.16, "covalent_radius": 1.02, "color": Color(0.12, 0.94, 0.12)},
		{"symbol": "Ar", "atomic_number": 18, "mass": 39.948, "electronegativity": 0.0,  "covalent_radius": 1.06, "color": Color(0.5, 0.82, 0.89)},
		{"symbol": "K",  "atomic_number": 19, "mass": 39.098, "electronegativity": 0.82, "covalent_radius": 2.03, "color": Color(0.56, 0.0, 0.56)},
		{"symbol": "Ca", "atomic_number": 20, "mass": 40.078, "electronegativity": 1.00, "covalent_radius": 1.76, "color": Color(0.24, 0.24, 0.7)},
	]


func get_element_by_index(idx: int) -> Dictionary:
	if idx >= 0 and idx < elements.size():
		return elements[idx]
	return {}


func get_element_by_symbol(sym: String) -> Dictionary:
	for elem in elements:
		if elem.get("symbol", "") == sym:
			return elem
	return {}


func find_index_by_symbol(sym: String) -> int:
	for i in range(elements.size()):
		if elements[i].get("symbol", "") == sym:
			return i
	return -1
