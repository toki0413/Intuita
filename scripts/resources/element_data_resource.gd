class_name ElementDataResource extends Resource

# 元素数据资源 - 存储元素周期表前20种元素的基础数据
# 被 atom_placement_manager.gd 加载以获取原子颜色、半径等信息

@export var elements: Array[Dictionary] = []

func _init() -> void:
    pass

func _build_default_data() -> void:
    # 如果 elements 为空，填充默认数据
    if elements.size() > 0:
        return
    elements = [
        {"symbol": "H", "name": "Hydrogen", "atomic_number": 1, "mass": 1.008, "covalent_radius": 0.31, "vdw_radius": 1.2, "color": Color(1.0, 1.0, 1.0, 1.0)},
        {"symbol": "He", "name": "Helium", "atomic_number": 2, "mass": 4.003, "covalent_radius": 0.28, "vdw_radius": 1.4, "color": Color(0.85, 1.0, 1.0, 1.0)},
        {"symbol": "Li", "name": "Lithium", "atomic_number": 3, "mass": 6.94, "covalent_radius": 1.28, "vdw_radius": 1.82, "color": Color(0.8, 0.5, 1.0, 1.0)},
        {"symbol": "Be", "name": "Beryllium", "atomic_number": 4, "mass": 9.012, "covalent_radius": 0.96, "vdw_radius": 1.53, "color": Color(0.76, 1.0, 0.0, 1.0)},
        {"symbol": "B", "name": "Boron", "atomic_number": 5, "mass": 10.81, "covalent_radius": 0.84, "vdw_radius": 1.92, "color": Color(1.0, 0.71, 0.71, 1.0)},
        {"symbol": "C", "name": "Carbon", "atomic_number": 6, "mass": 12.01, "covalent_radius": 0.76, "vdw_radius": 1.7, "color": Color(0.56, 0.56, 0.56, 1.0)},
        {"symbol": "N", "name": "Nitrogen", "atomic_number": 7, "mass": 14.01, "covalent_radius": 0.71, "vdw_radius": 1.55, "color": Color(0.19, 0.31, 0.97, 1.0)},
        {"symbol": "O", "name": "Oxygen", "atomic_number": 8, "mass": 16.00, "covalent_radius": 0.66, "vdw_radius": 1.52, "color": Color(1.0, 0.05, 0.05, 1.0)},
        {"symbol": "F", "name": "Fluorine", "atomic_number": 9, "mass": 19.00, "covalent_radius": 0.57, "vdw_radius": 1.47, "color": Color(0.56, 0.88, 0.31, 1.0)},
        {"symbol": "Ne", "name": "Neon", "atomic_number": 10, "mass": 20.18, "covalent_radius": 0.58, "vdw_radius": 1.54, "color": Color(1.0, 0.08, 0.58, 1.0)},
        {"symbol": "Na", "name": "Sodium", "atomic_number": 11, "mass": 22.99, "covalent_radius": 1.66, "vdw_radius": 2.27, "color": Color(0.67, 0.36, 0.95, 1.0)},
        {"symbol": "Mg", "name": "Magnesium", "atomic_number": 12, "mass": 24.31, "covalent_radius": 1.41, "vdw_radius": 1.73, "color": Color(0.54, 1.0, 0.0, 1.0)},
        {"symbol": "Al", "name": "Aluminium", "atomic_number": 13, "mass": 26.98, "covalent_radius": 1.21, "vdw_radius": 1.84, "color": Color(0.75, 0.65, 0.65, 1.0)},
        {"symbol": "Si", "name": "Silicon", "atomic_number": 14, "mass": 28.09, "covalent_radius": 1.11, "vdw_radius": 2.1, "color": Color(0.94, 0.78, 0.63, 1.0)},
        {"symbol": "P", "name": "Phosphorus", "atomic_number": 15, "mass": 30.97, "covalent_radius": 1.07, "vdw_radius": 1.8, "color": Color(1.0, 0.5, 0.0, 1.0)},
        {"symbol": "S", "name": "Sulfur", "atomic_number": 16, "mass": 32.06, "covalent_radius": 1.05, "vdw_radius": 1.8, "color": Color(1.0, 1.0, 0.19, 1.0)},
        {"symbol": "Cl", "name": "Chlorine", "atomic_number": 17, "mass": 35.45, "covalent_radius": 1.02, "vdw_radius": 1.75, "color": Color(0.12, 0.94, 0.12, 1.0)},
        {"symbol": "Ar", "name": "Argon", "atomic_number": 18, "mass": 39.95, "covalent_radius": 0.71, "vdw_radius": 1.88, "color": Color(0.5, 1.0, 1.0, 1.0)},
        {"symbol": "K", "name": "Potassium", "atomic_number": 19, "mass": 39.10, "covalent_radius": 2.03, "vdw_radius": 2.75, "color": Color(0.56, 0.25, 0.83, 1.0)},
        {"symbol": "Ca", "name": "Calcium", "atomic_number": 20, "mass": 40.08, "covalent_radius": 1.76, "vdw_radius": 2.31, "color": Color(0.24, 1.0, 0.0, 1.0)},
    ]
