extends Resource
# 关卡数据资源 - 定义单个关卡的所有配置
# 包含晶胞参数、目标、奖励等
# 支持多物理域: crystal, molecular, fluid, device, reaction, topology

class_name LevelData

# ---- 基础信息 ----
@export var chapter: int = 1
@export var level: int = 1
@export var title: String = ""
@export var description: String = ""
@export var space_group_number: int = 1
@export var space_group_symbol: String = "P1"
@export var lattice_parameters: Vector3 = Vector3(5.0, 5.0, 5.0)
@export var lattice_angles: Vector3 = Vector3(90.0, 90.0, 90.0)
@export var reward_cores: int = 1
@export var hint: String = ""
@export var elements: Array[Dictionary] = []
@export var goals: Array[Dictionary] = []

# ---- 多域扩展 ----
@export var domain: String = "crystal"  # crystal, molecular, fluid, device, reaction, topology, open
@export var construction_mode: String = "wyckoff_fill"  # wyckoff_fill, bond_build, mesh_build, path_build, assembly, free, cellular_automaton
@export var scene_config: Dictionary = {}  # 域特定配置
@export var scale_label: String = "Å"  # Å, nm, μm
@export var scale_range: Vector2 = Vector2(0.5, 10.0)  # 缩放范围 min/max
@export var available_tools: Array[String] = ["element_block", "wyckoff_snap"]  # 解锁的工具
@export var fog_zones: Array[Dictionary] = []  # 预置迷雾区域
@export var constraints: Dictionary = {}  # 关卡约束 (预算、时间等)
@export var journal_entry: String = ""  # 关卡完成时的科学手记条目


# ---- JSON 序列化 / 反序列化 ----

func to_json() -> Dictionary:
	var result := {
		"v": 1,
		"chapter": chapter,
		"level": level,
		"title": title,
		"description": description,
		"space_group_number": space_group_number,
		"space_group_symbol": space_group_symbol,
		"lattice_parameters": _vec3_to_dict(lattice_parameters),
		"lattice_angles": _vec3_to_dict(lattice_angles),
		"reward_cores": reward_cores,
		"hint": hint,
		"elements": _elements_to_json(),
		"goals": _goals_to_json(),
		"domain": domain,
		"construction_mode": construction_mode,
		"scene_config": scene_config.duplicate(true),
		"scale_label": scale_label,
		"scale_range": _vec2_to_dict(scale_range),
		"available_tools": Array(available_tools),
		"fog_zones": _fog_zones_to_json(),
		"constraints": constraints.duplicate(true),
		"journal_entry": journal_entry,
	}
	return result


func from_json(data: Dictionary) -> void:
	chapter = int(data.get("chapter", 1))
	level = int(data.get("level", 1))
	title = str(data.get("title", ""))
	description = str(data.get("description", ""))
	# 兼容 space_group 作为嵌套对象或扁平字段
	var sg = data.get("space_group", data.get("space_group_number", null))
	if sg is Dictionary:
		space_group_number = int(sg.get("number", 1))
		space_group_symbol = str(sg.get("name", sg.get("symbol", "P1")))
	else:
		space_group_number = int(data.get("space_group_number", 1))
		space_group_symbol = str(data.get("space_group_symbol", "P1"))
	# 兼容 lattice_params / lattice / lattice_parameters 多种字段名
	var lp = data.get("lattice_parameters", data.get("lattice_params", data.get("lattice", {})))
	lattice_parameters = _dict_to_vec3(lp)
	lattice_angles = _dict_to_vec3(data.get("lattice_angles", {}))
	reward_cores = int(data.get("reward_cores", 1))
	hint = str(data.get("hint", ""))
	elements = _elements_from_json(data.get("elements", []))
	goals = _goals_from_json(data.get("goals", []))
	domain = str(data.get("domain", "crystal"))
	construction_mode = str(data.get("construction_mode", "wyckoff_fill"))
	scene_config = data.get("scene_config", {}).duplicate(true) if data.get("scene_config") is Dictionary else {}
	scale_label = str(data.get("scale_label", "Å"))
	scale_range = _dict_to_vec2(data.get("scale_range", {}))
	available_tools = _str_array_from_json(data.get("available_tools", []))
	fog_zones = _fog_zones_from_json(data.get("fog_zones", []))
	constraints = data.get("constraints", {}).duplicate(true) if data.get("constraints") is Dictionary else {}
	# forbidden_tools 可以在 JSON 顶层或 constraints 内定义，统一合并到 constraints
	var ft_top: Variant = data.get("forbidden_tools", [])
	if ft_top is Array and not ft_top.is_empty() and not constraints.has("forbidden_tools"):
		constraints["forbidden_tools"] = ft_top.duplicate(true)
	journal_entry = str(data.get("journal_entry", ""))


# ---- 内部辅助方法 ----

func _vec3_to_dict(v: Vector3) -> Dictionary:
	return {"x": v.x, "y": v.y, "z": v.z}

func _dict_to_vec3(d: Variant) -> Vector3:
	if d is Vector3:
		return d
	if d is Dictionary:
		# 兼容 x/y/z 和 a/b/c 两种键名
		var x := float(d.get("x", d.get("a", 0.0)))
		var y := float(d.get("y", d.get("b", 0.0)))
		var z := float(d.get("z", d.get("c", 0.0)))
		return Vector3(x, y, z)
	return Vector3.ZERO

func _vec2_to_dict(v: Vector2) -> Dictionary:
	return {"x": v.x, "y": v.y}

func _dict_to_vec2(d: Variant) -> Vector2:
	if d is Vector2:
		return d
	if d is Dictionary:
		return Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
	return Vector2.ZERO

func _elements_to_json() -> Array:
	var out: Array = []
	for el in elements:
		var copy: Dictionary = el.duplicate(true)
		if copy.get("position") is Vector3:
			copy["position"] = _vec3_to_dict(copy["position"])
		out.append(copy)
	return out

func _elements_from_json(arr: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not arr is Array:
		return out
	for item in arr:
		if item is Dictionary:
			var copy: Dictionary = item.duplicate(true)
			if copy.get("position") is Dictionary:
				copy["position"] = _dict_to_vec3(copy["position"])
			out.append(copy)
	return out

func _goals_to_json() -> Array:
	var out: Array = []
	for g in goals:
		out.append(g.duplicate(true))
	return out

func _goals_from_json(arr: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not arr is Array:
		return out
	for item in arr:
		if item is Dictionary:
			var copy: Dictionary = item.duplicate(true)
			# Flatten nested "params" sub-dict so goal checks can access keys directly
			if copy.has("params") and copy["params"] is Dictionary:
				for key in copy["params"]:
					if not copy.has(key):
						copy[key] = copy["params"][key]
				copy.erase("params")
			out.append(copy)
	return out

func _fog_zones_to_json() -> Array:
	var out: Array = []
	for z in fog_zones:
		var copy: Dictionary = z.duplicate(true)
		if copy.get("position") is Vector3:
			copy["position"] = _vec3_to_dict(copy["position"])
		out.append(copy)
	return out

func _fog_zones_from_json(arr: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not arr is Array:
		return out
	for item in arr:
		if item is Dictionary:
			var copy: Dictionary = item.duplicate(true)
			var pos = copy.get("position")
			if pos is Dictionary:
				copy["position"] = _dict_to_vec3(pos)
			elif pos is Array and pos.size() >= 3:
				copy["position"] = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
			out.append(copy)
	return out

func _str_array_from_json(arr: Variant) -> Array[String]:
	var out: Array[String] = []
	if not arr is Array:
		return out
	for item in arr:
		out.append(str(item))
	return out





# ============================================================
# Compact tuple format (for network / large levels)
# ============================================================
# Tuple element: [x, y, z, symbol, wyckoff_label, wyckoff_multiplicity]
# Tuple goal: [type, description, element, wyckoff, required_count, max_deviation, required_layer]

func to_compact_elements() -> Array:
	var out: Array = []
	for el in elements:
		var pos = el.get("position", Vector3.ZERO)
		if pos is Vector3:
			pos = _vec3_to_dict(pos)
		var tuple := [
			float(pos.get("x", 0.0)),
			float(pos.get("y", 0.0)),
			float(pos.get("z", 0.0)),
			str(el.get("symbol", "")),
			str(el.get("wyckoff_label", "")),
			int(el.get("wyckoff_multiplicity", 1)),
		]
		out.append(tuple)
	return out


func from_compact_elements(arr: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in arr:
		if item is Array and item.size() >= 6:
			var d := {
				"position": Vector3(float(item[0]), float(item[1]), float(item[2])),
				"symbol": str(item[3]),
				"wyckoff_label": str(item[4]),
				"wyckoff_multiplicity": int(item[5]),
			}
			out.append(d)
		elif item is Dictionary:
			var copy: Dictionary = item.duplicate(true)
			if copy.get("position") is Dictionary:
				copy["position"] = _dict_to_vec3(copy["position"])
			out.append(copy)
	return out


func to_compact_goals() -> Array:
	var out: Array = []
	for g in goals:
		var tuple := [
			str(g.get("type", "")),
			str(g.get("description", "")),
			str(g.get("element", "")),
			str(g.get("wyckoff", "")),
			int(g.get("required_count", 0)) if g.get("required_count") != null else null,
			float(g.get("max_deviation", 0.0)) if g.get("max_deviation") != null else null,
			int(g.get("required_layer", 0)) if g.get("required_layer") != null else null,
		]
		out.append(tuple)
	return out


func from_compact_goals(arr: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in arr:
		if item is Array and item.size() >= 2:
			var d := {
				"type": str(item[0]),
				"description": str(item[1]),
			}
			if item.size() > 2 and item[2] != null:
				d["element"] = str(item[2])
			if item.size() > 3 and item[3] != null:
				d["wyckoff"] = str(item[3])
			if item.size() > 4 and item[4] != null:
				d["required_count"] = int(item[4])
			if item.size() > 5 and item[5] != null:
				d["max_deviation"] = float(item[5])
			if item.size() > 6 and item[6] != null:
				d["required_layer"] = int(item[6])
			out.append(d)
		elif item is Dictionary:
			out.append(item.duplicate(true))
	return out


func to_compact_json() -> Dictionary:
	var result := to_json()
	result["elements"] = to_compact_elements()
	result["goals"] = to_compact_goals()
	result["compact"] = true
	return result


func from_compact_json(data: Dictionary) -> void:
	from_json(data)
	var el_raw = data.get("elements", [])
	if el_raw is Array and el_raw.size() > 0 and el_raw[0] is Array:
		elements = from_compact_elements(el_raw)
	var g_raw = data.get("goals", [])
	if g_raw is Array and g_raw.size() > 0 and g_raw[0] is Array:
		goals = from_compact_goals(g_raw)

# ============================================================
# Chapter 1: Crystal Foundation
# ============================================================

static func create_nacl_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 1
	ld.level = 1
	ld.title = "NaCl Wyckoff填充"
	ld.description = "在Fm-3m空间群中填充Na和Cl到正确的Wyckoff位置，构建岩盐结构"
	ld.space_group_number = 225
	ld.space_group_symbol = "Fm-3m"
	ld.lattice_parameters = Vector3(5.64, 5.64, 5.64)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 3
	ld.hint = "岩盐结构中Na和Cl交替占据面心立方格位"
	ld.journal_entry = "NaCl: The simplest salt. Every kitchen has a proof of existence."
	ld.domain = "crystal"
	ld.construction_mode = "wyckoff_fill"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.5, 10.0)
	ld.available_tools = ["element_block", "wyckoff_snap"]

	ld.elements = [
		{"symbol": "Na", "wyckoff_label": "a", "wyckoff_multiplicity": 4, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "Cl", "wyckoff_label": "b", "wyckoff_multiplicity": 4, "position": Vector3(0.5, 0.5, 0.5)},
	]

	ld.goals = [
		{"type": "wyckoff_fill", "description": "将Na放置在4a位置", "element": "Na", "wyckoff": "a", "required_count": 4},
		{"type": "wyckoff_fill", "description": "将Cl放置在4b位置", "element": "Cl", "wyckoff": "b", "required_count": 4},
		{"type": "conservation_check", "description": "守恒矩阵保持健康状态", "max_deviation": 0.1},
		{"type": "verification", "description": "完成L1符号验证", "required_layer": 0},
	]

	return ld


static func create_lifepo4_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 1
	ld.level = 2
	ld.title = "LiFePO4骨架"
	ld.description = "将NaCl骨架转换为LiFePO4结构，在Pnma空间群中填充Li、Fe、P、O到正确的Wyckoff位置"
	ld.space_group_number = 62
	ld.space_group_symbol = "Pnma"
	ld.lattice_parameters = Vector3(10.33, 6.01, 4.69)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 4
	ld.hint = "LiFePO4中Li和Fe占据4c位置，P也占4c，三组O分别占不同4c位"
	ld.journal_entry = "LiFePO4: Nature's battery. The olivine structure stores more than lithium."
	ld.domain = "crystal"
	ld.construction_mode = "wyckoff_fill"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.5, 10.0)
	ld.available_tools = ["element_block", "wyckoff_snap"]

	ld.elements = [
		{"symbol": "Li", "wyckoff_label": "c", "wyckoff_multiplicity": 4, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "Fe", "wyckoff_label": "c", "wyckoff_multiplicity": 4, "position": Vector3(0.28, 0.25, 0.97)},
		{"symbol": "P",  "wyckoff_label": "c", "wyckoff_multiplicity": 4, "position": Vector3(0.09, 0.25, 0.42)},
		# 三组O合并为单一O，降低第2关的认知负担
		{"symbol": "O",  "wyckoff_label": "c", "wyckoff_multiplicity": 12, "position": Vector3(0.09, 0.25, 0.73)},
	]

	ld.goals = [
		{"type": "wyckoff_fill", "description": "将Li放置在4c位置", "element": "Li", "wyckoff": "c", "required_count": 4},
		{"type": "wyckoff_fill", "description": "将Fe放置在4c位置", "element": "Fe", "wyckoff": "c", "required_count": 4},
		{"type": "wyckoff_fill", "description": "将P放置在4c位置", "element": "P", "wyckoff": "c", "required_count": 4},
		{"type": "wyckoff_fill", "description": "将O放置在4c位置(全部氧位)", "element": "O", "wyckoff": "c", "required_count": 12},
		{"type": "conservation_check", "description": "电荷平衡验证", "max_deviation": 0.15},
		{"type": "conservation_check", "description": "Wyckoff位置填充完整性", "max_deviation": 0.1},
		{"type": "verification", "description": "完成守恒矩阵验证", "required_layer": 0},
	]

	return ld


static func create_octahedral_tilt_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 1
	ld.level = 3
	ld.title = "八面体倾斜"
	ld.description = "软模畸变: Pnma→Pna2₁对称性破缺，对八面体施加旋转操作并维持守恒"
	ld.space_group_number = 33
	ld.space_group_symbol = "Pna2₁"
	ld.lattice_parameters = Vector3(10.33, 6.01, 4.69)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 5
	ld.hint = "软模旋转会降低对称性，注意守恒矩阵中动量行的变化"
	ld.journal_entry = "Octahedral tilt: When symmetry bends but doesn't break. Soft modes whisper of phase transitions."
	ld.domain = "crystal"
	ld.construction_mode = "wyckoff_fill"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.5, 10.0)
	ld.available_tools = ["element_block", "wyckoff_snap"]

	ld.elements = [
		{"symbol": "Li", "wyckoff_label": "a", "wyckoff_multiplicity": 4, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "Fe", "wyckoff_label": "a", "wyckoff_multiplicity": 4, "position": Vector3(0.28, 0.25, 0.97)},
		{"symbol": "P",  "wyckoff_label": "a", "wyckoff_multiplicity": 4, "position": Vector3(0.09, 0.25, 0.42)},
		# 三组O合并，畸变偏移保留在位置坐标中
		{"symbol": "O",  "wyckoff_label": "a", "wyckoff_multiplicity": 12, "position": Vector3(0.09, 0.27, 0.73)},
	]

	ld.goals = [
		{"type": "wyckoff_fill", "description": "将Li放置在4a位置", "element": "Li", "wyckoff": "a", "required_count": 4},
		{"type": "wyckoff_fill", "description": "将Fe放置在4a位置", "element": "Fe", "wyckoff": "a", "required_count": 4},
		{"type": "wyckoff_fill", "description": "将P放置在4a位置", "element": "P", "wyckoff": "a", "required_count": 4},
		{"type": "wyckoff_fill", "description": "将O放置在4a位置(含畸变偏移)", "element": "O", "wyckoff": "a", "required_count": 12},
		{"type": "symmetry_check", "description": "确认空间群从Pnma降至Pna2₁", "source_sg": 62, "target_sg": 33},
		{"type": "conservation_check", "description": "软模旋转后守恒矩阵仍健康", "max_deviation": 0.2},
		{"type": "verification", "description": "完成对称性破缺验证", "required_layer": 1},
	]

	return ld


static func create_oxygen_vacancy_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 1
	ld.level = 4
	ld.title = "氧空位补偿"
	ld.description = "在Fm-3m结构中引入氧空位实现电荷补偿，维持整体电中性"
	ld.space_group_number = 225
	ld.space_group_symbol = "Fm-3m"
	ld.lattice_parameters = Vector3(5.64, 5.64, 5.64)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 6
	ld.hint = "每移除一个O²⁻需要补偿2个负电荷，考虑阳离子价态调整"
	ld.journal_entry = "Oxygen vacancy: Absence is a form of presence. The void carries charge."
	ld.domain = "crystal"
	ld.construction_mode = "wyckoff_fill"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.5, 10.0)
	ld.available_tools = ["element_block", "wyckoff_snap"]

	ld.elements = [
		{"symbol": "M",  "wyckoff_label": "a", "wyckoff_multiplicity": 4, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "O",  "wyckoff_label": "b", "wyckoff_multiplicity": 4, "position": Vector3(0.5, 0.5, 0.5)},
		{"symbol": "V_O", "wyckoff_label": "b", "wyckoff_multiplicity": 4, "position": Vector3(0.5, 0.5, 0.5)},
	]

	ld.goals = [
		{"type": "wyckoff_fill", "description": "将金属M放置在4a位置", "element": "M", "wyckoff": "a", "required_count": 4},
		{"type": "wyckoff_fill", "description": "将O放置在4b位置(部分)", "element": "O", "wyckoff": "b", "required_count": 3},
		{"type": "wyckoff_fill", "description": "在4b位置标记氧空位", "element": "V_O", "wyckoff": "b", "required_count": 1},
		{"type": "conservation_check", "description": "电荷补偿后守恒矩阵健康", "max_deviation": 0.15},
		{"type": "conservation_check", "description": "空位引入后质量守恒检查", "max_deviation": 0.2},
		{"type": "verification", "description": "完成电荷补偿验证", "required_layer": 1},
	]

	return ld


# ============================================================
# Chapter 1 Extended: Crystal + Molecular + Thermodynamics
# ============================================================

static func create_diamond_network_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 1
	ld.level = 5
	ld.title = "金刚石网络"
	ld.description = "在Fd-3m空间群中构建金刚石结构，将C填充到8a四面体位置，理解sp3杂化与四面体配位"
	ld.space_group_number = 227
	ld.space_group_symbol = "Fd-3m"
	ld.lattice_parameters = Vector3(3.57, 3.57, 3.57)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 4
	ld.hint = "金刚石中C占据8a四面体空隙，每个C与4个近邻C形成sp3共价键"
	ld.journal_entry = "Diamond: Carbon's purest proof. Four bonds, infinite network, zero compromise."
	ld.domain = "crystal"
	ld.construction_mode = "wyckoff_fill"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.5, 8.0)
	ld.available_tools = ["element_block", "wyckoff_snap", "bond_tool"]

	ld.elements = [
		{"symbol": "C", "wyckoff_label": "a", "wyckoff_multiplicity": 8, "position": Vector3(0.125, 0.125, 0.125)},
	]

	ld.goals = [
		{"type": "wyckoff_fill", "description": "将C放置在8a四面体位置", "element": "C", "wyckoff": "a", "required_count": 8},
		{"type": "bond_build", "description": "构建sp3四面体键网络", "required_bonds": 16, "bond_pairs": [["C", "C"]], "coordination": 4},
		{"type": "geometry_check", "description": "四面体键角≈109.5°", "target_angle": 109.5, "angle_tolerance": 2.0},
		{"type": "conservation_check", "description": "sp3配位守恒矩阵健康", "max_deviation": 0.1},
		{"type": "verification", "description": "完成四面体配位验证", "required_layer": 1},
	]

	return ld


static func create_water_molecule_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 1
	ld.level = 6
	ld.title = "水分子"
	ld.description = "构建H₂O分子，键角104.5°，O-H键长0.96Å，理解VSEPR理论与分子几何"
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(5.0, 5.0, 5.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 3
	ld.hint = "水分子VSEPR: O有2个孤对电子，挤压H-O-H键角至104.5°(小于109.5°)"
	ld.journal_entry = "H₂O: Two lone pairs, one bent truth. VSEPR predicts, nature confirms."
	ld.domain = "molecular"
	ld.construction_mode = "bond_build"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.3, 5.0)
	# L6只引入atom_placer和bond_rotator，angle_adjuster推迟到L7
	ld.available_tools = ["atom_placer", "bond_rotator"]

	ld.scene_config = {
		"target_bond_angle": 104.5,
		"target_bond_length": 0.96,
		"vsepr_pairs": 2,
		"bonding_pairs": 2,
	}

	ld.elements = [
		{"symbol": "O", "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.5, 0.5)},
		{"symbol": "H", "wyckoff_label": "b", "wyckoff_multiplicity": 2, "position": Vector3(0.6, 0.35, 0.5)},
	]

	ld.goals = [
		{"type": "bond_build", "description": "构建2条O-H键", "required_bonds": 2, "bond_pairs": [["O", "H"]]},
		{"type": "geometry_check", "description": "O-H键长=0.96Å", "target_distance": 0.96, "distance_tolerance": 0.05, "check_pair": ["O", "H"]},
		{"type": "geometry_check", "description": "H-O-H键角=104.5°", "target_angle": 104.5, "angle_tolerance": 1.5},
		{"type": "conservation_check", "description": "分子价键守恒", "max_deviation": 0.1},
		{"type": "verification", "description": "完成VSEPR分子几何验证", "required_layer": 2},
	]

	return ld


static func create_ethanol_synthesis_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 1
	ld.level = 7
	ld.title = "乙醇合成"
	ld.description = "从原子出发构建C₂H₅OH，满足所有原子价键，理解有机化学官能团与C-C/C-O键"
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(8.0, 8.0, 8.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 4
	ld.hint = "乙醇: C-C骨架 + O-H羟基，C需4键、O需2键、H需1键"
	ld.journal_entry = "C₂H₅OH: The spirit of organic chemistry. Valence is the law, bonds are the proof."
	ld.domain = "molecular"
	ld.construction_mode = "bond_build"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.3, 6.0)
	ld.available_tools = ["atom_placer", "bond_rotator", "angle_adjuster"]

	ld.scene_config = {
		"target_molecule": "C2H5OH",
		"valence_rules": {"C": 4, "O": 2, "H": 1},
		"functional_groups": ["hydroxyl"],
	}

	ld.elements = [
		{"symbol": "C", "wyckoff_label": "a", "wyckoff_multiplicity": 2, "position": Vector3(0.4, 0.5, 0.5)},
		{"symbol": "O", "wyckoff_label": "b", "wyckoff_multiplicity": 1, "position": Vector3(0.6, 0.5, 0.5)},
		{"symbol": "H", "wyckoff_label": "c", "wyckoff_multiplicity": 6, "position": Vector3(0.3, 0.4, 0.5)},
	]

	ld.goals = [
		{"type": "bond_build", "description": "构建C-C键", "required_bonds": 1, "bond_pairs": [["C", "C"]]},
		{"type": "bond_build", "description": "构建C-O键", "required_bonds": 1, "bond_pairs": [["C", "O"]]},
		{"type": "bond_build", "description": "构建O-H键(羟基)", "required_bonds": 1, "bond_pairs": [["O", "H"]]},
		{"type": "bond_build", "description": "构建C-H键(5条)", "required_bonds": 5, "bond_pairs": [["C", "H"]]},
		{"type": "bond_build", "description": "满足所有原子价键", "required_bonds": 8, "bond_pairs": [["C", "C"], ["C", "O"], ["O", "H"], ["C", "H"]], "per_atom_valence": {"C": 4, "O": 2, "H": 1}},
		{"type": "conservation_check", "description": "价键守恒矩阵健康", "max_deviation": 0.1},
		{"type": "verification", "description": "完成有机分子价键验证", "required_layer": 2},
	]

	return ld


static func create_perovskite_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 1
	ld.level = 8
	ld.title = "钙钛矿"
	ld.description = "构建SrTiO₃钙钛矿结构(A=Sr 1a, B=Ti 1b, O=3c)，理解容忍因子与Goldschmidt规则"
	ld.space_group_number = 221
	ld.space_group_symbol = "Pm-3m"
	ld.lattice_parameters = Vector3(3.91, 3.91, 3.91)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 5
	ld.hint = "钙钛矿ABO₃: A位大离子占角顶1a，B位小离子占体心1b，O占面心3c，容忍因子t≈1.0时结构稳定"
	ld.journal_entry = "Perovskite: Named after a count. Tolerance is its law. t≈1.0 and the structure stands."
	ld.domain = "crystal"
	ld.construction_mode = "wyckoff_fill"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.5, 8.0)
	ld.available_tools = ["element_block", "wyckoff_snap", "bond_tool"]

	ld.scene_config = {
		"tolerance_factor": 1.002,
		"r_A": 1.44,
		"r_B": 0.605,
		"r_O": 1.40,
	}

	ld.elements = [
		{"symbol": "Sr", "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "Ti", "wyckoff_label": "b", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.5, 0.5)},
		{"symbol": "O",  "wyckoff_label": "c", "wyckoff_multiplicity": 3, "position": Vector3(0.5, 0.5, 0.0)},
	]

	# 迷雾系统推迟到L9引入，L8专注钙钛矿结构本身
	ld.goals = [
		{"type": "wyckoff_fill", "description": "将Sr放置在1a位置(角顶)", "element": "Sr", "wyckoff": "a", "required_count": 1},
		{"type": "wyckoff_fill", "description": "将Ti放置在1b位置(体心)", "element": "Ti", "wyckoff": "b", "required_count": 1},
		{"type": "wyckoff_fill", "description": "将O放置在3c位置(面心)", "element": "O", "wyckoff": "c", "required_count": 3},
		{"type": "bond_build", "description": "构建TiO₆八面体键网络", "required_bonds": 6, "bond_pairs": [["Ti", "O"]], "coordination": 6},
		{"type": "geometry_check", "description": "容忍因子t≈1.0(0.8-1.05)", "target_value": 1.002, "value_tolerance": 0.2, "check_type": "tolerance_factor"},
		{"type": "conservation_check", "description": "钙钛矿守恒矩阵健康", "max_deviation": 0.1},
		{"type": "verification", "description": "完成钙钛矿结构验证", "required_layer": 2},
	]

	return ld


static func create_thermal_expansion_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 1
	ld.level = 9
	ld.title = "热膨胀"
	ld.description = "对钙钛矿施加热应变(晶格膨胀1%)，维持守恒矩阵健康，理解热应变与晶格参数调整"
	ld.space_group_number = 221
	ld.space_group_symbol = "Pm-3m"
	ld.lattice_parameters = Vector3(3.95, 3.95, 3.95)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 5
	ld.hint = "热膨胀: 晶格参数a增加1%(3.91→3.95Å)，原子位置不变但键长拉伸，守恒矩阵需保持健康"
	ld.journal_entry = "Thermal expansion: Atoms stretch but don't break. The lattice breathes. Conservation endures."
	ld.domain = "crystal"
	ld.construction_mode = "wyckoff_fill"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.5, 8.0)
	ld.available_tools = ["element_block", "wyckoff_snap", "bond_tool", "strain_tool"]

	ld.scene_config = {
		"base_lattice": 3.91,
		"thermal_strain": 0.01,
		"target_lattice": 3.95,
		"temperature_delta": 100,
	}

	ld.elements = [
		{"symbol": "Sr", "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "Ti", "wyckoff_label": "b", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.5, 0.5)},
		{"symbol": "O",  "wyckoff_label": "c", "wyckoff_multiplicity": 3, "position": Vector3(0.5, 0.5, 0.0)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.5, 0.5, 0.25), "radius": 1.2, "fog_type": "semi_decidable", "label": "高应变区"},
	]

	ld.goals = [
		{"type": "wyckoff_fill", "description": "将Sr放置在1a位置", "element": "Sr", "wyckoff": "a", "required_count": 1},
		{"type": "wyckoff_fill", "description": "将Ti放置在1b位置", "element": "Ti", "wyckoff": "b", "required_count": 1},
		{"type": "wyckoff_fill", "description": "将O放置在3c位置", "element": "O", "wyckoff": "c", "required_count": 3},
		{"type": "geometry_check", "description": "晶格参数膨胀至3.95Å(≈1%应变)", "target_lattice": 3.95, "lattice_tolerance": 0.02},
		{"type": "conservation_check", "description": "热应变后守恒矩阵仍健康", "max_deviation": 0.15},
		{"type": "conservation_check", "description": "热膨胀过程质量守恒", "max_deviation": 0.1},
		{"type": "verification", "description": "完成热应变守恒验证", "required_layer": 2},
	]

	return ld


static func create_phase_transition_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 1
	ld.level = 10
	ld.title = "相变临界"
	ld.description = "驱动钙钛矿立方→四方相变(Pm-3m→P4mm)，调整c/a比越过临界点，理解序参量与临界行为"
	ld.space_group_number = 99
	ld.space_group_symbol = "P4mm"
	ld.lattice_parameters = Vector3(3.95, 3.95, 4.10)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 7
	ld.hint = "相变临界: c/a从1.0增大至>1.04时结构从立方变为四方，越过临界点完成相变"
	ld.journal_entry = "Phase transition: At the critical point, symmetry hesitates. The lattice chooses a new order."
	ld.domain = "crystal"
	ld.construction_mode = "wyckoff_fill"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.5, 10.0)
	ld.available_tools = ["element_block", "wyckoff_snap", "bond_tool", "strain_tool"]

	ld.scene_config = {
		"initial_sg": 221,
		"target_sg": 99,
		"initial_lattice": [3.91, 3.91, 3.91],
		"target_lattice": [3.95, 3.95, 4.10],
		"critical_ca_ratio": 1.04,
		"order_parameter": 0.0,
	}

	ld.elements = [
		{"symbol": "Sr", "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "Ti", "wyckoff_label": "b", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.5, 0.52)},
		{"symbol": "O1", "wyckoff_label": "c", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.5, 0.02)},
		{"symbol": "O2", "wyckoff_label": "d", "wyckoff_multiplicity": 2, "position": Vector3(0.5, 0.0, 0.52)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.5, 0.5, 0.5), "radius": 2.0, "fog_type": "independent", "label": "相变临界点"},
	]

	ld.goals = [
		{"type": "wyckoff_fill", "description": "将Sr放置在1a位置", "element": "Sr", "wyckoff": "a", "required_count": 1},
		{"type": "wyckoff_fill", "description": "将Ti放置在1b位置(含c轴偏移)", "element": "Ti", "wyckoff": "b", "required_count": 1},
		{"type": "wyckoff_fill", "description": "将O1放置在1c位置(顶点氧)", "element": "O1", "wyckoff": "c", "required_count": 1},
		{"type": "wyckoff_fill", "description": "将O2放置在2d位置(面心氧)", "element": "O2", "wyckoff": "d", "required_count": 2},
		{"type": "symmetry_check", "description": "确认c/a>1.04且空间群从Pm-3m降至P4mm", "source_sg": 221, "target_sg": 99, "min_ca_ratio": 1.04},
		{"type": "conservation_check", "description": "相变过程守恒矩阵连续", "max_deviation": 0.25},
		{"type": "verification", "description": "完成相变临界验证", "required_layer": 2},
	]

	return ld


# ============================================================
# Chapter 2: Flow and Interface
# ============================================================

static func create_ion_channel_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 2
	ld.level = 1
	ld.title = "锂离子通道"
	ld.description = "在晶体骨架中构建Li+迁移通道，瓶颈需>1.6Å让离子通过，过宽则结构坍塌"
	ld.space_group_number = 62
	ld.space_group_symbol = "Pnma"
	ld.lattice_parameters = Vector3(10.33, 6.01, 4.69)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 7
	ld.hint = "通道瓶颈决定离子能否通过，1.6Å是Li+的临界尺寸"
	ld.journal_entry = "Li⁺ channel: The bottleneck decides. 1.6Å is the gate between flow and frustration."
	ld.domain = "molecular"
	ld.construction_mode = "bond_build"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.5, 8.0)
	ld.available_tools = ["element_block", "bond_tool", "channel_inspector"]

	ld.scene_config = {
		"bottleneck_min": 1.6,
		"bottleneck_max": 3.0,
		"ion_species": "Li+",
		"framework_elements": ["O", "P", "Fe"],
	}

	ld.elements = [
		{"symbol": "Li", "wyckoff_label": "c", "wyckoff_multiplicity": 4, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "O1", "wyckoff_label": "c", "wyckoff_multiplicity": 4, "position": Vector3(0.09, 0.25, 0.73)},
		{"symbol": "O2", "wyckoff_label": "c", "wyckoff_multiplicity": 4, "position": Vector3(0.46, 0.25, 0.20)},
		{"symbol": "O3", "wyckoff_label": "c", "wyckoff_multiplicity": 4, "position": Vector3(0.30, 0.25, 0.42)},
		{"symbol": "P",  "wyckoff_label": "c", "wyckoff_multiplicity": 4, "position": Vector3(0.09, 0.25, 0.42)},
		{"symbol": "Fe", "wyckoff_label": "c", "wyckoff_multiplicity": 4, "position": Vector3(0.28, 0.25, 0.97)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.25, 0.25, 0.5), "radius": 1.5, "fog_type": "semi_decidable", "label": "通道瓶颈区"},
	]

	ld.goals = [
		{"type": "bond_build", "description": "构建Li-O骨架键网络", "required_bonds": 6, "bond_pairs": [["Li", "O1"], ["Li", "O2"], ["Li", "O3"]]},
		{"type": "geometry_check", "description": "通道瓶颈≥1.6Å", "min_distance": 1.6, "check_pair": ["O1", "O2"], "axis": "b"},
		{"type": "geometry_check", "description": "通道不过宽(≤3.0Å)", "max_distance": 3.0, "check_pair": ["O1", "O2"], "axis": "b"},
		{"type": "transport_check", "description": "Li+可通过通道", "species": "Li+", "min_bottleneck": 1.6},
		{"type": "conservation_check", "description": "通道结构守恒矩阵健康", "max_deviation": 0.15},
		{"type": "verification", "description": "完成离子通道验证", "required_layer": 1},
	]

	return ld


static func create_grain_boundary_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 2
	ld.level = 2
	ld.title = "晶界桥接"
	ld.description = "连接LiCoO2正极与LLZO电解质的晶界，构建过渡层使界面兼容"
	ld.space_group_number = 166
	ld.space_group_symbol = "R-3m"
	ld.lattice_parameters = Vector3(2.82, 2.82, 14.05)
	ld.lattice_angles = Vector3(90.0, 90.0, 120.0)
	ld.reward_cores = 8
	ld.hint = "晶格失配需要在界面处构建过渡层，守恒矩阵必须跨界面连续"
	ld.journal_entry = "Grain boundary: Where two crystals meet, mismatch becomes interface. Continuity is the bridge."
	ld.domain = "crystal"
	ld.construction_mode = "assembly"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(1.0, 15.0)
	ld.available_tools = ["element_block", "interface_builder", "strain_tool"]

	ld.scene_config = {
		"grain_a": {"material": "LiCoO2", "space_group": 166, "lattice": [2.82, 2.82, 14.05]},
		"grain_b": {"material": "LLZO", "space_group": 227, "lattice": [9.73, 9.73, 9.73]},
		"max_mismatch": 0.15,
	}

	ld.elements = [
		{"symbol": "Li", "wyckoff_label": "a", "wyckoff_multiplicity": 3, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "Co", "wyckoff_label": "b", "wyckoff_multiplicity": 3, "position": Vector3(0.0, 0.0, 0.5)},
		{"symbol": "O",  "wyckoff_label": "c", "wyckoff_multiplicity": 6, "position": Vector3(0.0, 0.0, 0.24)},
		{"symbol": "Zr", "wyckoff_label": "d", "wyckoff_multiplicity": 4, "position": Vector3(0.125, 0.125, 0.125)},
		{"symbol": "La", "wyckoff_label": "e", "wyckoff_multiplicity": 4, "position": Vector3(0.375, 0.375, 0.375)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.5, 0.5, 0.5), "radius": 2.0, "fog_type": "undecidable", "label": "界面区域"},
	]

	ld.goals = [
		{"type": "wyckoff_fill", "description": "填充LiCoO2侧Li到3a位", "element": "Li", "wyckoff": "a", "required_count": 3},
		{"type": "wyckoff_fill", "description": "填充Co到3b位", "element": "Co", "wyckoff": "b", "required_count": 3},
		{"type": "wyckoff_fill", "description": "填充O到6c位", "element": "O", "wyckoff": "c", "required_count": 6},
		{"type": "interface_check", "description": "界面晶格失配≤15%", "max_mismatch": 0.15},
		{"type": "conservation_check", "description": "跨界面守恒矩阵连续", "max_deviation": 0.2},
		{"type": "verification", "description": "完成界面兼容性验证", "required_layer": 2},
	]

	return ld


static func create_topology_transition_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 2
	ld.level = 3
	ld.title = "拓扑相变"
	ld.description = "引导结构穿越拓扑相变，在不可判定区域维持守恒，构建安全过渡路径"
	ld.space_group_number = 225
	ld.space_group_symbol = "Fm-3m"
	ld.lattice_parameters = Vector3(5.64, 5.64, 5.64)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 10
	ld.hint = "拓扑相变经过不可判定区域，只能绕行或尝试穿透"
	ld.journal_entry = "Topology transition: Paths through the undecidable. You cannot prove the path exists — you must walk it."
	ld.domain = "topology"
	ld.construction_mode = "path_build"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.5, 12.0)
	ld.available_tools = ["element_block", "topology_tool", "path_builder"]

	ld.scene_config = {
		"initial_phase": "cubic",
		"target_phase": "tetragonal",
		"transition_order_parameter": 0.0,
	}

	ld.elements = [
		{"symbol": "M", "wyckoff_label": "a", "wyckoff_multiplicity": 4, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "O", "wyckoff_label": "b", "wyckoff_multiplicity": 4, "position": Vector3(0.5, 0.5, 0.5)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.5, 0.5, 0.5), "radius": 3.0, "fog_type": "independent", "label": "相变过渡区"},
	]

	ld.goals = [
		{"type": "wyckoff_fill", "description": "初始相: 填充M到4a位", "element": "M", "wyckoff": "a", "required_count": 4},
		{"type": "wyckoff_fill", "description": "初始相: 填充O到4b位", "element": "O", "wyckoff": "b", "required_count": 4},
		{"type": "symmetry_check", "description": "构建相变过渡路径", "source_sg": 225, "target_sg": 139},
		{"type": "conservation_check", "description": "相变过程守恒矩阵连续", "max_deviation": 0.25},
		{"type": "symmetry_check", "description": "确认对称性从Fm-3m降至I4/mmm", "source_sg": 225, "target_sg": 139},
		{"type": "verification", "description": "完成拓扑相变验证", "required_layer": 2},
	]

	return ld


# ============================================================
# Chapter 2 Extended: Flow + Interface + Fluid + EM + Thermo + StatMech
# ============================================================

static func create_multi_channel_race_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 2
	ld.level = 4
	ld.title = "多通道竞速"
	ld.description = "构建3条平行Li+通道，所有通道必须同时导通——通道间存在干涉效应，需协调瓶颈尺寸"
	ld.space_group_number = 62
	ld.space_group_symbol = "Pnma"
	ld.lattice_parameters = Vector3(10.33, 6.01, 4.69)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 8
	ld.hint = "平行通道之间存在静电干涉，调一条通道的瓶颈会影响相邻通道的通过性"
	ld.journal_entry = "Multi-channel: Three paths, one constraint. Interference is the price of parallelism."
	ld.domain = "molecular"
	ld.construction_mode = "bond_build"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.5, 10.0)
	ld.available_tools = ["element_block", "bond_tool", "channel_inspector"]

	ld.scene_config = {
		"channel_count": 3,
		"bottleneck_min": 1.6,
		"bottleneck_max": 3.0,
		"ion_species": "Li+",
		"framework_elements": ["O", "P", "Fe"],
		"parallel_transport": true,
		"channel_interference": true,
	}

	ld.elements = [
		{"symbol": "Li1", "wyckoff_label": "c", "wyckoff_multiplicity": 4, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "Li2", "wyckoff_label": "c", "wyckoff_multiplicity": 4, "position": Vector3(0.0, 0.5, 0.0)},
		{"symbol": "Li3", "wyckoff_label": "c", "wyckoff_multiplicity": 4, "position": Vector3(0.0, 0.0, 0.5)},
		{"symbol": "O1", "wyckoff_label": "c", "wyckoff_multiplicity": 4, "position": Vector3(0.09, 0.25, 0.73)},
		{"symbol": "O2", "wyckoff_label": "c", "wyckoff_multiplicity": 4, "position": Vector3(0.46, 0.25, 0.20)},
		{"symbol": "O3", "wyckoff_label": "c", "wyckoff_multiplicity": 4, "position": Vector3(0.30, 0.25, 0.42)},
		{"symbol": "P",  "wyckoff_label": "c", "wyckoff_multiplicity": 4, "position": Vector3(0.09, 0.25, 0.42)},
		{"symbol": "Fe", "wyckoff_label": "c", "wyckoff_multiplicity": 4, "position": Vector3(0.28, 0.25, 0.97)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.25, 0.25, 0.5), "radius": 1.8, "fog_type": "semi_decidable", "label": "通道间干涉区"},
	]

	ld.goals = [
		{"type": "bond_build", "description": "构建通道1的Li-O键网络", "required_bonds": 6, "bond_pairs": [["Li1", "O1"], ["Li1", "O2"], ["Li1", "O3"]]},
		{"type": "bond_build", "description": "构建通道2的Li-O键网络", "required_bonds": 6, "bond_pairs": [["Li2", "O1"], ["Li2", "O2"], ["Li2", "O3"]]},
		{"type": "bond_build", "description": "构建通道3的Li-O键网络", "required_bonds": 6, "bond_pairs": [["Li3", "O1"], ["Li3", "O2"], ["Li3", "O3"]]},
		{"type": "geometry_check", "description": "通道1瓶颈≥1.6Å", "min_distance": 1.6, "check_pair": ["O1", "O2"], "axis": "b"},
		{"type": "geometry_check", "description": "通道2瓶颈≥1.6Å", "min_distance": 1.6, "check_pair": ["O1", "O3"], "axis": "b"},
		{"type": "geometry_check", "description": "通道3瓶颈≥1.6Å", "min_distance": 1.6, "check_pair": ["O2", "O3"], "axis": "b"},
		{"type": "transport_check", "description": "3条通道同时导通Li+", "species": "Li+", "min_bottleneck": 1.6, "parallel_channels": 3},
		{"type": "conservation_check", "description": "多通道结构守恒矩阵健康", "max_deviation": 0.15},
		{"type": "verification", "description": "完成多通道竞速验证", "required_layer": 2},
	]

	return ld


static func create_fluid_boundary_layer_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 2
	ld.level = 5
	ld.title = "流体边界层"
	ld.description = "构建壁面附近流体流动的网格，满足无滑移边界条件，观察边界层内速度梯度"
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(20.0, 20.0, 20.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 6
	ld.hint = "无滑移条件: 壁面处流速为零，边界层厚度与雷诺数相关"
	ld.journal_entry = "Boundary layer: Where fluid meets wall, velocity surrenders to zero. No-slip is the law."
	ld.domain = "fluid"
	ld.construction_mode = "mesh_build"
	ld.scale_label = "nm"
	ld.scale_range = Vector2(0.1, 50.0)
	ld.available_tools = ["mesh_builder", "boundary_setter", "flow_visualizer"]

	ld.scene_config = {
		"boundary_type": "no_slip",
		"reynolds_number": 100.0,
		"flow_direction": [1, 0, 0],
		"wall_position": 0.0,
		"boundary_layer_thickness": 2.0,
	}

	ld.elements = [
		{"symbol": "FLUID", "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.5, 0.5)},
		{"symbol": "WALL",  "wyckoff_label": "b", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.0, 0.5)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.5, 0.1, 0.5), "radius": 2.5, "fog_type": "undecidable", "label": "分离点区域"},
	]

	ld.goals = [
		{"type": "mesh_build", "description": "构建壁面附近流体网格", "mesh_density": "high_near_wall", "required_atoms": 20},
		{"type": "conservation_check", "description": "流体边界层连续", "max_deviation": 0.15},
		{"type": "geometry_check", "description": "边界层内速度梯度正确", "velocity_profile": "boundary_layer", "reynolds_number": 100.0},
		{"type": "conservation_check", "description": "流体质量守恒(连续性方程)", "max_deviation": 0.1},
		{"type": "conservation_check", "description": "动量守恒(Navier-Stokes)", "max_deviation": 0.15},
		{"type": "verification", "description": "完成流体边界层验证", "required_layer": 2},
	]

	return ld


static func create_em_shielding_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 2
	ld.level = 6
	ld.title = "电磁屏蔽"
	ld.description = "用导电面板组装法拉第笼，必须屏蔽外部电磁波——笼体任何间隙都会导致泄漏"
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(15.0, 15.0, 15.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 7
	ld.hint = "趋肤深度决定导体厚度需求，间隙是屏蔽失败的主要原因"
	ld.journal_entry = "Faraday cage: Every gap is a leak. Skin depth is the measure of security."
	ld.domain = "electromagnetics"
	ld.construction_mode = "assembly"
	ld.scale_label = "μm"
	ld.scale_range = Vector2(0.1, 30.0)
	ld.available_tools = ["panel_placer", "conductivity_checker", "em_tester"]

	ld.scene_config = {
		"cage_type": "faraday",
		"skin_depth_nm": 2.0,
		"em_frequency_ghz": 1.0,
		"min_conductivity": 1e6,
		"panel_material": "Cu",
	}

	ld.elements = [
		{"symbol": "Cu_panel_top",    "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 1.0, 0.5)},
		{"symbol": "Cu_panel_bottom", "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.0, 0.5)},
		{"symbol": "Cu_panel_front",  "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.5, 0.0)},
		{"symbol": "Cu_panel_back",   "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.5, 1.0)},
		{"symbol": "Cu_panel_left",   "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.0, 0.5, 0.5)},
		{"symbol": "Cu_panel_right",  "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(1.0, 0.5, 0.5)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.5, 0.5, 0.5), "radius": 1.5, "fog_type": "semi_decidable", "label": "笼体间隙区"},
	]

	ld.goals = [
		{"type": "assembly_check", "description": "组装6面法拉第笼", "component": "faraday_cage", "required_parts": 6},
		{"type": "geometry_check", "description": "面板间无间隙(间隙<趋肤深度)", "max_gap": 2.0, "check_all_seams": true},
		{"type": "conservation_check", "description": "面板电导率≥10⁶ S/m", "max_deviation": 0.12},
		{"type": "geometry_check", "description": "屏蔽结构几何匹配", "target_lattice": 1.0, "lattice_tolerance": 0.1},
		{"type": "conservation_check", "description": "Maxwell方程守恒检查", "max_deviation": 0.15},
		{"type": "verification", "description": "完成电磁屏蔽验证", "required_layer": 2},
	]

	return ld


static func create_heat_conduction_path_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 2
	ld.level = 7
	ld.title = "热传导路径"
	ld.description = "构建从热源到冷源的热传导路径，最小化热阻——材料界面是热阻瓶颈"
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(12.0, 12.0, 12.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 6
	ld.hint = "Fourier定律: 热流密度正比于温度梯度，界面热阻取决于材料匹配"
	ld.journal_entry = "Heat path: Fourier's law is the compass. Interfaces are the mountains. Diamond is the shortcut."
	ld.domain = "thermodynamics"
	ld.construction_mode = "path_build"
	ld.scale_label = "nm"
	ld.scale_range = Vector2(0.1, 30.0)
	ld.available_tools = ["material_placer", "thermal_connector", "temperature_probe"]

	ld.scene_config = {
		"hot_source_temp": 500.0,
		"cold_sink_temp": 300.0,
		"available_materials": ["Cu", "Al", "SiO2", "diamond"],
		"thermal_conductivities": {"Cu": 400.0, "Al": 237.0, "SiO2": 1.4, "diamond": 2200.0},
	}

	ld.elements = [
		{"symbol": "HOT",    "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.0, 0.5, 0.5)},
		{"symbol": "COLD",   "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(1.0, 0.5, 0.5)},
		{"symbol": "Cu",     "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.25, 0.5, 0.5)},
		{"symbol": "diamond","wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.5, 0.5)},
		{"symbol": "Al",     "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.75, 0.5, 0.5)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.375, 0.5, 0.5), "radius": 1.5, "fog_type": "semi_decidable", "label": "材料界面区"},
		{"position": Vector3(0.625, 0.5, 0.5), "radius": 1.5, "fog_type": "semi_decidable", "label": "材料界面区"},
	]

	ld.goals = [
		{"type": "assembly_check", "description": "构建热传导路径", "required_parts": {"热桥": 1}},
		{"type": "thermal_check", "description": "热流从高温流向低温", "hot_temp": 500.0, "cold_temp": 300.0},
		{"type": "geometry_check", "description": "路径热阻最小化", "max_thermal_resistance": 0.05},
		{"type": "interface_check", "description": "材料界面热阻可控", "max_interface_resistance": 0.01},
		{"type": "conservation_check", "description": "Fourier定律能量守恒", "max_deviation": 0.1},
		{"type": "verification", "description": "完成热传导路径验证", "required_layer": 2},
	]

	return ld


static func create_statistical_fluctuations_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 2
	ld.level = 8
	ld.title = "统计涨落"
	ld.description = "构建100个粒子的系综，在给定温度下维持正确的Boltzmann分布——涨落是物理的，不是误差"
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(10.0, 10.0, 10.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 8
	ld.hint = "Boltzmann分布: P(E)∝exp(-E/kT)，尾部涨落最大但不可忽略"
	ld.journal_entry = "Boltzmann: The tail is real. Fluctuations are not errors — they are physics."
	ld.domain = "statistical_mechanics"
	ld.construction_mode = "assembly"
	ld.scale_label = "nm"
	ld.scale_range = Vector2(0.1, 20.0)
	ld.available_tools = ["particle_spawner", "thermostat", "distribution_checker"]

	ld.scene_config = {
		"particle_count": 100,
		"temperature_k": 300.0,
		"ensemble_type": "canonical",
		"target_distribution": "boltzmann",
		"energy_bins": 20,
	}

	ld.elements = [
		{"symbol": "PARTICLE", "wyckoff_label": "a", "wyckoff_multiplicity": 100, "position": Vector3(0.5, 0.5, 0.5)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.9, 0.5, 0.5), "radius": 2.0, "fog_type": "semi_decidable", "label": "分布尾部涨落区"},
	]

	ld.goals = [
		{"type": "assembly_check", "description": "生成100个粒子的系综", "component": "ensemble", "required_count": 100},
		{"type": "conservation_check", "description": "能量分布符合Boltzmann分布", "max_deviation": 0.1},
		{"type": "thermal_check", "description": "系统温度稳定在300K", "target_temp": 300.0, "tolerance": 5.0},
		{"type": "conservation_check", "description": "系综总能量守恒", "max_deviation": 0.1},
		{"type": "geometry_check", "description": "涨落幅度在统计允许范围内", "target_value": 0.0, "check_type": "tolerance_factor", "tolerance": 0.15},
		{"type": "verification", "description": "完成统计涨落验证", "required_layer": 2},
	]

	return ld


static func create_diffusion_equation_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 2
	ld.level = 9
	ld.title = "扩散方程"
	ld.description = "设置Fick扩散的初始条件，观察浓度随时间正确演化——浓度梯度驱动扩散流"
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(15.0, 15.0, 15.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 7
	ld.hint = "Fick第一定律: J=-D∇c，浓度梯度越大扩散越快，尖锐前沿不可判定"
	ld.journal_entry = "Fick's law: Gradients drive the world. Sharp fronts hide in the undecidable fog."
	ld.domain = "fluid"
	ld.construction_mode = "mesh_build"
	ld.scale_label = "nm"
	ld.scale_range = Vector2(0.1, 40.0)
	ld.available_tools = ["mesh_builder", "concentration_setter", "diffusion_watcher"]

	ld.scene_config = {
		"diffusion_coefficient": 1e-9,
		"initial_condition": "step_function",
		"observation_time_s": 10.0,
		"mesh_resolution": "adaptive",
	}

	ld.elements = [
		{"symbol": "SOLUTE",  "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.25, 0.5, 0.5)},
		{"symbol": "SOLVENT", "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.75, 0.5, 0.5)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.5, 0.5, 0.5), "radius": 2.0, "fog_type": "undecidable", "label": "浓度尖锐前沿区"},
	]

	ld.goals = [
		{"type": "mesh_build", "description": "构建扩散区域网格", "mesh_density": "adaptive", "required_atoms": 30},
		{"type": "diffusion_check", "description": "扩散路径完整", "required_paths": 3, "min_nodes": 4},
		{"type": "diffusion_check", "description": "浓度演化符合Fick第二定律", "diffusion_coefficient": 1e-9, "max_deviation": 0.1},
		{"type": "conservation_check", "description": "扩散过程物质守恒", "max_deviation": 0.05},
		{"type": "geometry_check", "description": "浓度梯度方向正确(高→低)", "gradient_direction": "correct"},
		{"type": "verification", "description": "完成扩散方程验证", "required_layer": 2},
	]

	return ld


static func create_multiphysics_coupling_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 2
	ld.level = 10
	ld.title = "多物理场耦合"
	ld.description = "构建热电发电机(Seebeck效应): 热流→电动势→电流，三物理场在耦合点交汇"
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(20.0, 20.0, 20.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 12
	ld.hint = "Seebeck效应: ΔV=S·ΔT，热-电耦合系数决定转换效率，Peltier效应是逆过程"
	ld.journal_entry = "Thermoelectric: Heat becomes voltage. Three fields converge at one point. Coupling is creation."
	ld.domain = "multiphysics"
	ld.construction_mode = "assembly"
	ld.scale_label = "μm"
	ld.scale_range = Vector2(0.1, 50.0)
	ld.available_tools = ["element_block", "wyckoff_snap", "bond_tool", "interface_builder", "strain_tool", "channel_inspector", "molecule_builder", "reaction_arrow", "energy_diagram", "topology_tool", "path_builder", "mesh_builder", "boundary_setter", "flow_visualizer", "panel_placer", "conductivity_checker", "em_tester", "material_placer", "thermal_connector", "temperature_probe", "particle_spawner", "thermostat", "distribution_checker", "concentration_setter", "diffusion_watcher"]

	ld.scene_config = {
		"seebeck_coefficient_uv_per_k": 200.0,
		"hot_temp": 500.0,
		"cold_temp": 300.0,
		"coupling_type": "thermoelectric",
		"p_type_material": "Bi2Te3",
		"n_type_material": "Sb2Te3",
	}

	ld.constraints = {"max_parts": 8}

	ld.elements = [
		{"symbol": "HOT_SIDE",  "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.0, 0.5, 0.5)},
		{"symbol": "COLD_SIDE", "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(1.0, 0.5, 0.5)},
		{"symbol": "P_LEG",     "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.7, 0.5)},
		{"symbol": "N_LEG",     "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.3, 0.5)},
		{"symbol": "METAL_TOP", "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 1.0, 0.5)},
		{"symbol": "METAL_BOT", "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.0, 0.5)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.5, 0.5, 0.5), "radius": 3.0, "fog_type": "independent", "label": "热力学极限耦合点"},
	]

	ld.goals = [
		{"type": "assembly_check", "description": "组装P型热电臂(Bi2Te3)", "component": "p_leg", "required_parts": 1},
		{"type": "assembly_check", "description": "组装N型热电臂(Sb2Te3)", "component": "n_leg", "required_parts": 1},
		{"type": "assembly_check", "description": "连接金属电极", "component": "metal_contact", "required_parts": 2},
		{"type": "thermal_check", "description": "建立温度梯度(ΔT=200K)", "hot_temp": 500.0, "cold_temp": 300.0},
		{"type": "transport_check", "description": "多物理场输运平衡", "min_conductivity": 0.0, "max_deviation": 0.2},
		{"type": "transport_check", "description": "回路电流导通", "species": "e-", "circuit_closed": true},
		{"type": "conservation_check", "description": "热-电耦合能量守恒", "max_deviation": 0.15},
		{"type": "verification", "description": "完成多物理场耦合验证", "required_layer": 3},
	]

	return ld


# ============================================================
# Chapter 3: Fire and Path
# ============================================================

static func create_catalytic_cycle_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 3
	ld.level = 1
	ld.title = "催化循环"
	ld.description = "设计CO2→CH4催化循环，最多5个中间体，每步质量电荷守恒"
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(10.0, 10.0, 10.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 12
	ld.hint = "Sabatier反应: CO2 + 4H2 → CH4 + 2H2O，注意每步的电荷和质量平衡"
	ld.journal_entry = "Catalytic cycle: CO₂ becomes CH₄. The catalyst is unchanged — a constructive proof of turnover."
	ld.domain = "reaction"
	ld.construction_mode = "path_build"
	ld.scale_label = "nm"
	ld.scale_range = Vector2(0.1, 5.0)
	ld.available_tools = ["molecule_builder", "reaction_arrow", "energy_diagram"]

	ld.scene_config = {
		"reactant": "CO2",
		"product": "CH4",
		"catalyst": "Ni",
		"max_intermediates": 5,
	}

	ld.constraints = {"max_intermediates": 5}

	ld.elements = [
		{"symbol": "C", "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "O", "wyckoff_label": "b", "wyckoff_multiplicity": 2, "position": Vector3(0.5, 0.5, 0.0)},
		{"symbol": "H", "wyckoff_label": "c", "wyckoff_multiplicity": 8, "position": Vector3(0.25, 0.25, 0.25)},
		{"symbol": "Ni", "wyckoff_label": "d", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.0, 0.5)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.5, 0.5, 0.5), "radius": 2.0, "fog_type": "semi_decidable", "label": "过渡态区域"},
	]

	ld.goals = [
		{"type": "bond_build", "description": "催化反应键网络", "bond_pairs": [["C", "O"], ["H", "O"]], "required_bonds": 4},
		{"type": "bond_build", "description": "每个中间体必须是有效分子结构", "validate_molecules": true},
		{"type": "conservation_check", "description": "每步质量守恒", "max_deviation": 0.05, "per_step": true},
		{"type": "conservation_check", "description": "每步电荷守恒", "max_deviation": 0.05, "per_step": true},
		{"type": "geometry_check", "description": "整体反应能量下坡", "energy_downhill": true},
		{"type": "verification", "description": "完成催化循环验证", "required_layer": 2},
	]

	return ld


static func create_solid_state_battery_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 3
	ld.level = 2
	ld.title = "全固态电池"
	ld.description = "组装完整固态电池: 正极+电解质+负极+界面，满足离子/电子输运和界面稳定"
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(15.0, 10.0, 10.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 15
	ld.hint = "正极供Li+，电解质导Li+，负极收Li+，界面必须稳定"
	ld.journal_entry = "Solid-state battery: Cathode gives, electrolyte guides, anode receives. Interfaces are the frontier."
	ld.domain = "device"
	ld.construction_mode = "assembly"
	ld.scale_label = "μm"
	ld.scale_range = Vector2(0.1, 20.0)
	ld.available_tools = ["element_block", "bond_tool", "interface_builder", "strain_tool", "channel_inspector", "molecule_builder", "reaction_arrow", "energy_diagram", "topology_tool", "path_builder"]

	ld.scene_config = {
		"components": ["cathode", "electrolyte", "anode", "interface_ce", "interface_ae"],
		"cathode_material": "LiCoO2",
		"electrolyte_material": "LLZO",
		"anode_material": "Li_metal",
	}

	ld.constraints = {"max_parts": 10, "budget_cores": 15}

	ld.elements = [
		{"symbol": "Li", "wyckoff_label": "a", "wyckoff_multiplicity": 4, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "Co", "wyckoff_label": "b", "wyckoff_multiplicity": 2, "position": Vector3(0.33, 0.0, 0.0)},
		{"symbol": "O",  "wyckoff_label": "c", "wyckoff_multiplicity": 6, "position": Vector3(0.33, 0.5, 0.0)},
		{"symbol": "Zr", "wyckoff_label": "d", "wyckoff_multiplicity": 2, "position": Vector3(0.66, 0.0, 0.0)},
		{"symbol": "La", "wyckoff_label": "e", "wyckoff_multiplicity": 2, "position": Vector3(0.66, 0.5, 0.0)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.66, 0.5, 0.5), "radius": 2.5, "fog_type": "undecidable", "label": "负极-电解质界面"},
	]

	ld.goals = [
		{"type": "assembly_check", "description": "组装正极(LiCoO2)", "component": "cathode", "required_parts": 2},
		{"type": "assembly_check", "description": "组装电解质(LLZO)", "component": "electrolyte", "required_parts": 2},
		{"type": "assembly_check", "description": "组装负极(Li金属)", "component": "anode", "required_parts": 1},
		{"type": "interface_check", "description": "正极-电解质界面稳定", "interface": "cathode_electrolyte", "max_mismatch": 0.2},
		{"type": "interface_check", "description": "负极-电解质界面稳定", "interface": "anode_electrolyte", "max_mismatch": 0.2},
		{"type": "transport_check", "description": "Li+可通过电解质", "species": "Li+", "min_conductivity": 1e-3},
		{"type": "conservation_check", "description": "全电池守恒矩阵健康", "max_deviation": 0.2},
		{"type": "verification", "description": "完成全固态电池验证", "required_layer": 2},
	]

	return ld


static func create_unknown_material_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 3
	ld.level = 3
	ld.title = "未知材料悬赏"
	ld.description = "发现满足指定性能的新型材料，无固定答案，社区竞赛排名"
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(10.0, 10.0, 10.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 20
	ld.hint = "自由探索! 目标: 离子电导率>10⁻³ S/cm的材料"
	ld.journal_entry = "Unknown material: No answer key exists. You are the proof. The community is the judge."
	ld.domain = "open"
	ld.construction_mode = "free"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.5, 50.0)
	ld.available_tools = ["element_block", "wyckoff_snap", "bond_tool", "interface_builder", "strain_tool", "channel_inspector", "molecule_builder", "reaction_arrow", "energy_diagram", "topology_tool", "path_builder"]

	ld.scene_config = {
		"target_properties": {
			"ionic_conductivity_min": 1e-3,
			"electronic_conductivity_max": 1e-6,
			"stability_threshold": 0.1,
		},
		"community_ranking": true,
	}

	ld.fog_zones = [
		{"position": Vector3(0.5, 0.5, 0.5), "radius": 5.0, "fog_type": "semi_decidable", "label": "未知结构区"},
	]

	ld.goals = [
		{"type": "transport_check", "description": "离子电导率>10⁻³ S/cm", "species": "Li+", "min_conductivity": 1e-3},
		{"type": "conservation_check", "description": "结构守恒矩阵健康", "max_deviation": 0.15},
		{"type": "geometry_check", "description": "结构具有离子传输通道", "has_channel": true},
		{"type": "verification", "description": "完成材料性能验证", "required_layer": 2},
	]

	return ld


static func create_photocatalytic_water_splitting_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 3
	ld.level = 4
	ld.title = "光催化分解水"
	ld.description = "设计TiO2基光催化剂，吸收紫外光分解H2O为H2和O2，需对齐带隙与氧化还原电位"
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(12.0, 12.0, 12.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 10
	ld.hint = "TiO2带隙~3.2eV吸收UV，导带需高于H+/H2电位，价带需低于O2/H2O电位"
	ld.journal_entry = "Photocatalysis: Sunlight splits water. Band alignment is the alignment of possibility."
	ld.domain = "reaction"
	ld.construction_mode = "path_build"
	ld.scale_label = "nm"
	ld.scale_range = Vector2(0.1, 5.0)
	ld.available_tools = ["molecule_builder", "reaction_arrow", "energy_diagram", "band_gap_tool"]

	ld.scene_config = {
		"photocatalyst": "TiO2",
		"band_gap_ev": 3.2,
		"cb_potential": -0.5,
		"vb_potential": 2.7,
		"h2_potential": 0.0,
		"o2_potential": 1.23,
	}

	ld.constraints = {"band_gap_min_ev": 1.23, "redox_aligned": true}

	ld.elements = [
		{"symbol": "Ti", "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "O", "wyckoff_label": "b", "wyckoff_multiplicity": 2, "position": Vector3(0.5, 0.5, 0.0)},
		{"symbol": "H", "wyckoff_label": "c", "wyckoff_multiplicity": 2, "position": Vector3(0.25, 0.25, 0.25)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.5, 0.5, 0.5), "radius": 2.5, "fog_type": "semi_decidable", "label": "带隙对齐区"},
	]

	ld.goals = [
		{"type": "reaction_path", "description": "光催化分解水: H₂O→OH+H→O+2H→2H₂+O₂", "reaction_steps": [["O", "H"], ["O", "O"], ["H", "H"]]},
		{"type": "bond_build", "description": "构建TiO2光催化剂结构", "required_bonds": 4, "bond_pairs": [["Ti", "O"]]},
		{"type": "conservation_check", "description": "每步质量守恒", "max_deviation": 0.05, "per_step": true},
		{"type": "conservation_check", "description": "每步电荷守恒", "max_deviation": 0.05, "per_step": true},
		{"type": "geometry_check", "description": "带隙≥1.23eV满足水分解热力学", "energy_downhill": true},
		{"type": "verification", "description": "完成光催化分解水验证", "required_layer": 2},
	]

	return ld


static func create_li_s_battery_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 3
	ld.level = 5
	ld.title = "锂硫电池"
	ld.description = "构建锂硫电池并管理多硫化物穿梭效应，控制容量衰减"
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(15.0, 15.0, 15.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 11
	ld.hint = "多硫化物Li2Sn(n=4-8)溶于电解质造成穿梭，需设计拦截层或吸附剂"
	ld.journal_entry = "Li-S battery: The shuttle is the enemy. Intercept the polysulfide, save the capacity."
	ld.domain = "device"
	ld.construction_mode = "assembly"
	ld.scale_label = "μm"
	ld.scale_range = Vector2(0.1, 20.0)
	ld.available_tools = ["element_block", "bond_tool", "interface_builder", "strain_tool", "channel_inspector", "molecule_builder", "reaction_arrow", "energy_diagram", "topology_tool", "path_builder"]

	ld.scene_config = {
		"components": ["anode", "cathode", "electrolyte", "shuttle_interceptor", "separator"],
		"anode_material": "Li_metal",
		"cathode_material": "S8",
		"polysulfide_species": ["Li2S8", "Li2S6", "Li2S4", "Li2S2"],
	}

	ld.constraints = {"max_parts": 8}

	ld.elements = [
		{"symbol": "Li", "wyckoff_label": "a", "wyckoff_multiplicity": 2, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "S", "wyckoff_label": "b", "wyckoff_multiplicity": 8, "position": Vector3(0.5, 0.5, 0.0)},
		{"symbol": "C", "wyckoff_label": "c", "wyckoff_multiplicity": 4, "position": Vector3(0.33, 0.0, 0.5)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.5, 0.5, 0.5), "radius": 3.0, "fog_type": "undecidable", "label": "多硫化物溶解区"},
	]

	ld.goals = [
		{"type": "assembly_check", "description": "组装锂负极", "component": "anode", "required_parts": 1},
		{"type": "assembly_check", "description": "组装硫正极", "component": "cathode", "required_parts": 1},
		{"type": "assembly_check", "description": "组装电解质", "component": "electrolyte", "required_parts": 1},
		{"type": "assembly_check", "description": "组装穿梭拦截层", "component": "shuttle_interceptor", "required_parts": 1},
		{"type": "interface_check", "description": "拦截层-电解质界面兼容", "interface": "interceptor_electrolyte", "max_mismatch": 0.2},
		{"type": "conservation_check", "description": "全电池守恒矩阵健康", "max_deviation": 0.2},
		{"type": "verification", "description": "完成锂硫电池验证", "required_layer": 2},
	]

	return ld


static func create_superconductor_critical_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 3
	ld.level = 6
	ld.title = "超导临界"
	ld.description = "构建YBCO类结构，找到超导转变的掺杂临界点，探索Cooper配对与临界温度"
	ld.space_group_number = 99
	ld.space_group_symbol = "P4mm"
	ld.lattice_parameters = Vector3(3.78, 3.78, 8.67)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 12
	ld.hint = "YBa2Cu3O7-δ的δ≈0时Tc最高，掺杂改变氧空位浓度调控超导性"
	ld.journal_entry = "Superconductor: At the critical doping, resistance vanishes. Cooper pairs dance in the void."
	ld.domain = "crystal"
	ld.construction_mode = "wyckoff_fill"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.5, 10.0)
	ld.available_tools = ["element_block", "wyckoff_snap", "bond_tool", "strain_tool", "doping_tool"]

	ld.scene_config = {
		"base_structure": "YBa2Cu3O7",
		"critical_doping_range": [0.0, 0.2],
		"tc_max_k": 93,
		"cooper_pair_symmetry": "d_wave",
	}

	ld.elements = [
		{"symbol": "Y", "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.5, 0.5)},
		{"symbol": "Ba", "wyckoff_label": "b", "wyckoff_multiplicity": 2, "position": Vector3(0.5, 0.5, 0.19)},
		{"symbol": "Cu1", "wyckoff_label": "c", "wyckoff_multiplicity": 1, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "Cu2", "wyckoff_label": "d", "wyckoff_multiplicity": 2, "position": Vector3(0.0, 0.0, 0.36)},
		{"symbol": "O1", "wyckoff_label": "e", "wyckoff_multiplicity": 2, "position": Vector3(0.5, 0.0, 0.38)},
		{"symbol": "O2", "wyckoff_label": "f", "wyckoff_multiplicity": 2, "position": Vector3(0.0, 0.5, 0.38)},
		{"symbol": "O3", "wyckoff_label": "g", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.0, 0.0)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.5, 0.5, 0.36), "radius": 2.0, "fog_type": "independent", "label": "Tc临界区"},
	]

	ld.goals = [
		{"type": "wyckoff_fill", "description": "将Y放置在1a位置", "element": "Y", "wyckoff": "a", "required_count": 1},
		{"type": "wyckoff_fill", "description": "将Ba放置在2b位置", "element": "Ba", "wyckoff": "b", "required_count": 2},
		{"type": "wyckoff_fill", "description": "将Cu1放置在1c位置", "element": "Cu1", "wyckoff": "c", "required_count": 1},
		{"type": "wyckoff_fill", "description": "将Cu2放置在2d位置", "element": "Cu2", "wyckoff": "d", "required_count": 2},
		{"type": "wyckoff_fill", "description": "将O1放置在2e位置", "element": "O1", "wyckoff": "e", "required_count": 2},
		{"type": "wyckoff_fill", "description": "将O2放置在2f位置", "element": "O2", "wyckoff": "f", "required_count": 2},
		{"type": "wyckoff_fill", "description": "将O3放置在1g位置(链氧)", "element": "O3", "wyckoff": "g", "required_count": 1},
		{"type": "conservation_check", "description": "掺杂后电荷守恒", "max_deviation": 0.15},
		{"type": "geometry_check", "description": "掺杂水平在超导相区内", "energy_downhill": true},
		{"type": "verification", "description": "完成超导临界点验证", "required_layer": 3},
	]

	return ld


static func create_quantum_tunneling_diode_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 3
	ld.level = 7
	ld.title = "量子隧穿二极管"
	ld.description = "构建双势垒共振隧穿二极管，利用量子隧穿实现负微分电阻"
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(10.0, 10.0, 10.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 10
	ld.hint = "双势垒结构: 势垒-量子阱-势垒，共振时隧穿概率最大，偏压偏离共振后电流反而下降"
	ld.journal_entry = "Quantum tunneling: Barriers are suggestions. At resonance, probability peaks. Negative resistance is the signature."
	ld.domain = "device"
	ld.construction_mode = "assembly"
	ld.scale_label = "nm"
	ld.scale_range = Vector2(0.1, 10.0)
	ld.available_tools = ["layer_builder", "barrier_setter", "iv_curve_tool"]

	ld.scene_config = {
		"layers": ["emitter", "barrier_1", "quantum_well", "barrier_2", "collector"],
		"barrier_material": "AlGaAs",
		"well_material": "GaAs",
		"barrier_width_nm": 2.0,
		"well_width_nm": 5.0,
	}

	ld.constraints = {"max_parts": 5}

	ld.elements = [
		{"symbol": "Ga", "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "As", "wyckoff_label": "b", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.5, 0.0)},
		{"symbol": "Al", "wyckoff_label": "c", "wyckoff_multiplicity": 1, "position": Vector3(0.0, 0.0, 0.5)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.5, 0.5, 0.5), "radius": 2.0, "fog_type": "semi_decidable", "label": "隧穿势垒区"},
	]

	ld.goals = [
		{"type": "assembly_check", "description": "组装发射极层", "component": "emitter", "required_parts": 1},
		{"type": "assembly_check", "description": "组装第一势垒层(AlGaAs)", "component": "barrier_1", "required_parts": 1},
		{"type": "assembly_check", "description": "组装量子阱层(GaAs)", "component": "quantum_well", "required_parts": 1},
		{"type": "assembly_check", "description": "组装第二势垒层(AlGaAs)", "component": "barrier_2", "required_parts": 1},
		{"type": "assembly_check", "description": "组装集电极层", "component": "collector", "required_parts": 1},
		{"type": "conservation_check", "description": "层间界面守恒矩阵健康", "max_deviation": 0.15},
		{"type": "verification", "description": "完成共振隧穿二极管验证", "required_layer": 2},
	]

	return ld


static func create_protein_folding_funnel_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 3
	ld.level = 8
	ld.title = "蛋白质折叠漏斗"
	ld.description = "引导简化蛋白质穿越折叠漏斗到达天然态，避开动力学陷阱"
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(15.0, 15.0, 15.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 11
	ld.hint = "折叠漏斗: 高能展开态→低能天然态，局部极小是动力学陷阱，需找到全局极小"
	ld.journal_entry = "Protein folding: The funnel guides. Traps deceive. The native state waits at the bottom."
	ld.domain = "molecular"
	ld.construction_mode = "path_build"
	ld.scale_label = "nm"
	ld.scale_range = Vector2(0.1, 5.0)
	ld.available_tools = ["atom_placer", "bond_rotator", "energy_landscape_navigator"]

	ld.scene_config = {
		"protein_length": 12,
		"residue_types": ["hydrophobic", "polar"],
		"native_state_energy": -42.0,
		"kinetic_trap_count": 3,
	}

	ld.constraints = {"max_intermediates": 8}

	ld.elements = [
		{"symbol": "N", "wyckoff_label": "a", "wyckoff_multiplicity": 12, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "C", "wyckoff_label": "b", "wyckoff_multiplicity": 12, "position": Vector3(0.5, 0.5, 0.0)},
		{"symbol": "O", "wyckoff_label": "c", "wyckoff_multiplicity": 12, "position": Vector3(0.25, 0.25, 0.25)},
		{"symbol": "H", "wyckoff_label": "d", "wyckoff_multiplicity": 24, "position": Vector3(0.75, 0.75, 0.75)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.5, 0.5, 0.5), "radius": 3.0, "fog_type": "undecidable", "label": "动力学陷阱区"},
	]

	ld.goals = [
		{"type": "bond_build", "description": "折叠关键氢键", "bond_pairs": [["C", "N"], ["C", "O"], ["N", "H"]], "required_bonds": 6},
		{"type": "bond_build", "description": "构建蛋白质骨架键", "required_bonds": 11, "bond_pairs": [["N", "C"]]},
		{"type": "geometry_check", "description": "到达天然态能量极小", "energy_downhill": true},
		{"type": "conservation_check", "description": "折叠过程质量守恒", "max_deviation": 0.05, "per_step": true},
		{"type": "conservation_check", "description": "折叠过程电荷守恒", "max_deviation": 0.05, "per_step": true},
		{"type": "verification", "description": "完成蛋白质折叠漏斗验证", "required_layer": 2},
	]

	return ld


static func create_co2_capture_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 3
	ld.level = 9
	ld.title = "CO2捕获材料"
	ld.description = "设计MOF材料实现最优CO2吸附位点，兼顾选择性与吸附容量"
	ld.space_group_number = 225
	ld.space_group_symbol = "Fm-3m"
	ld.lattice_parameters = Vector3(12.0, 12.0, 12.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 13
	ld.hint = "MOF由金属节点和有机连接体构成，孔径和开放金属位点决定CO2选择性"
	ld.journal_entry = "MOF for CO₂: Metal nodes, organic bridges, infinite pores. Selectivity is architecture."
	ld.domain = "crystal"
	ld.construction_mode = "wyckoff_fill"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.5, 15.0)
	ld.available_tools = ["element_block", "wyckoff_snap", "bond_tool", "adsorption_tester"]

	ld.scene_config = {
		"mof_type": "Cu-BTC",
		"target_gas": "CO2",
		"competitor_gas": "N2",
		"selectivity_threshold": 10.0,
		"uptake_min_mmol_g": 3.0,
	}

	ld.elements = [
		{"symbol": "Cu", "wyckoff_label": "a", "wyckoff_multiplicity": 4, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "C", "wyckoff_label": "b", "wyckoff_multiplicity": 4, "position": Vector3(0.5, 0.5, 0.5)},
		{"symbol": "O", "wyckoff_label": "c", "wyckoff_multiplicity": 8, "position": Vector3(0.25, 0.25, 0.25)},
		{"symbol": "H", "wyckoff_label": "d", "wyckoff_multiplicity": 4, "position": Vector3(0.75, 0.75, 0.75)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.5, 0.5, 0.5), "radius": 2.5, "fog_type": "semi_decidable", "label": "孔口开合区"},
	]

	ld.goals = [
		{"type": "wyckoff_fill", "description": "将Cu放置在4a位(金属节点)", "element": "Cu", "wyckoff": "a", "required_count": 4},
		{"type": "wyckoff_fill", "description": "将C放置在4b位(有机连接体)", "element": "C", "wyckoff": "b", "required_count": 4},
		{"type": "wyckoff_fill", "description": "将O放置在8c位(配位氧)", "element": "O", "wyckoff": "c", "required_count": 8},
		{"type": "wyckoff_fill", "description": "将H放置在4d位(连接体氢)", "element": "H", "wyckoff": "d", "required_count": 4},
		{"type": "conservation_check", "description": "MOF骨架守恒矩阵健康", "max_deviation": 0.15},
		{"type": "geometry_check", "description": "孔径适合CO2吸附", "has_channel": true},
		{"type": "verification", "description": "完成CO2捕获材料验证", "required_layer": 3},
	]

	return ld


static func create_universal_material_designer_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 3
	ld.level = 10
	ld.title = "通用材料设计师"
	ld.description = "设计满足随机生成的3项性能约束的材料，探索多目标Pareto前沿"
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(10.0, 10.0, 10.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 18
	ld.hint = "多目标优化中不存在单一最优解，Pareto前沿上的解都是可接受的"
	ld.journal_entry = "Universal designer: Three constraints, no single optimum. The Pareto front is where truth lives."
	ld.domain = "open"
	ld.construction_mode = "free"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.5, 50.0)
	ld.available_tools = ["element_block", "wyckoff_snap", "bond_tool", "interface_builder", "strain_tool", "channel_inspector", "molecule_builder", "reaction_arrow", "energy_diagram", "topology_tool", "path_builder", "self-evolve"]

	ld.scene_config = {
		"target_properties": {
			"property_1": "randomly_generated",
			"property_2": "randomly_generated",
			"property_3": "randomly_generated",
		},
		"pareto_optimization": true,
		"community_ranking": true,
	}

	ld.constraints = {"randomly_generated": true}

	ld.elements = [
		{"symbol": "X", "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "Y", "wyckoff_label": "b", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.5, 0.0)},
		{"symbol": "Z", "wyckoff_label": "c", "wyckoff_multiplicity": 1, "position": Vector3(0.25, 0.25, 0.25)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.5, 0.5, 0.5), "radius": 5.0, "fog_type": "independent", "label": "最优解不可达区"},
	]

	ld.goals = [
		{"type": "conservation_check", "description": "结构守恒矩阵健康", "max_deviation": 0.15},
		{"type": "geometry_check", "description": "满足性能约束1", "energy_downhill": true},
		{"type": "geometry_check", "description": "满足性能约束2", "has_channel": true},
		{"type": "transport_check", "description": "满足性能约束3", "species": "X", "min_conductivity": 1e-3},
		{"type": "verification", "description": "完成通用材料设计验证", "required_layer": 3},
	]

	return ld


# ============================================================
# Bonus Levels
# ============================================================

static func create_molecular_folding_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 0  # bonus关卡用chapter 0标记
	ld.level = 1
	ld.title = "分子折叠"
	ld.description = "将线性碳链折叠为稳定3D分子，满足价键规则、无空间位阻、最低能量构象"
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(8.0, 8.0, 8.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 5
	ld.hint = "碳的4个价键需要全部满足，注意避免原子重叠"
	ld.journal_entry = "Molecular folding: Carbon's four hands must all shake. Sterics are the geometry of refusal."
	ld.domain = "molecular"
	ld.construction_mode = "bond_build"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.3, 5.0)
	ld.available_tools = ["atom_placer", "bond_rotator", "angle_adjuster"]

	ld.scene_config = {
		"chain_length": 6,
		"chain_type": "carbon",
		"target_valence": 4,
	}

	ld.elements = [
		{"symbol": "C", "wyckoff_label": "a", "wyckoff_multiplicity": 6, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "H", "wyckoff_label": "b", "wyckoff_multiplicity": 14, "position": Vector3(0.5, 0.5, 0.5)},
	]

	ld.goals = [
		{"type": "bond_build", "description": "构建碳骨架键", "required_bonds": 5, "bond_pairs": [["C", "C"]]},
		{"type": "bond_build", "description": "满足碳价键(4键/原子)", "required_bonds": 24, "bond_pairs": [["C", "C"], ["C", "H"]], "per_atom_valence": {"C": 4}},
		{"type": "geometry_check", "description": "无空间位阻(原子间距>0.8Å)", "min_distance": 0.8, "check_all_pairs": true},
		{"type": "conservation_check", "description": "分子能量最低构象", "max_deviation": 0.1},
		{"type": "verification", "description": "完成分子折叠验证", "required_layer": 1},
	]

	return ld


static func create_nanowire_assembly_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 0
	ld.level = 2
	ld.title = "纳米线组装"
	ld.description = "通过组装晶胞构建导电纳米线，沿轴线方向保持电子通路"
	ld.space_group_number = 225
	ld.space_group_symbol = "Fm-3m"
	ld.lattice_parameters = Vector3(3.61, 3.61, 3.61)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 6
	ld.hint = "铜纳米线: 沿[110]方向重复Fm-3m晶胞，保持导电通路"
	ld.journal_entry = "Nanowire: One axis, infinite repetition. The electron highway has no traffic lights."
	ld.domain = "device"
	ld.construction_mode = "assembly"
	ld.scale_label = "nm"
	ld.scale_range = Vector2(0.5, 20.0)
	ld.available_tools = ["cell_replicator", "defect_placer", "conductivity_checker"]

	ld.scene_config = {
		"wire_axis": [1, 1, 0],
		"min_cells": 4,
		"conductive_element": "Cu",
	}

	ld.elements = [
		{"symbol": "Cu", "wyckoff_label": "a", "wyckoff_multiplicity": 4, "position": Vector3(0.0, 0.0, 0.0)},
	]

	ld.goals = [
		{"type": "wyckoff_fill", "description": "填充Cu到4a位(基础晶胞)", "element": "Cu", "wyckoff": "a", "required_count": 4},
		{"type": "assembly_check", "description": "沿[110]方向组装≥4个晶胞", "component": "nanowire", "min_cells": 4},
		{"type": "transport_check", "description": "沿轴线方向导电", "species": "e-", "axis": [1, 1, 0]},
		{"type": "conservation_check", "description": "纳米线守恒矩阵健康", "max_deviation": 0.1},
		{"type": "verification", "description": "完成纳米线验证", "required_layer": 1},
	]

	return ld


# ============================================================
# Challenge Levels (chapter -1)
# ============================================================

static func create_challenge_minimalist_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = -1
	ld.level = 1
	ld.title = "极简主义"
	ld.description = "用最少步骤构建NaCl，证明树深度≤4"
	ld.space_group_number = 225
	ld.space_group_symbol = "Fm-3m"
	ld.lattice_parameters = Vector3(5.64, 5.64, 5.64)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 8
	ld.hint = "每一步都要高效，减少不必要的操作，4步内完成"
	ld.journal_entry = "Minimalist: Every step must justify itself. Proof depth ≤ 4. Elegance is efficiency."
	ld.domain = "crystal"
	ld.construction_mode = "wyckoff_fill"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.5, 10.0)
	ld.available_tools = ["element_block", "wyckoff_snap"]

	ld.constraints = {"max_proof_depth": 4}

	ld.elements = [
		{"symbol": "Na", "wyckoff_label": "a", "wyckoff_multiplicity": 4, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "Cl", "wyckoff_label": "b", "wyckoff_multiplicity": 4, "position": Vector3(0.5, 0.5, 0.5)},
	]

	ld.goals = [
		{"type": "wyckoff_fill", "description": "将Na放置在4a位置", "element": "Na", "wyckoff": "a", "required_count": 4},
		{"type": "wyckoff_fill", "description": "将Cl放置在4b位置", "element": "Cl", "wyckoff": "b", "required_count": 4},
		{"type": "conservation_check", "description": "守恒矩阵保持健康状态", "max_deviation": 0.1},
		{"type": "verification", "description": "完成极简构建验证", "required_layer": 0},
	]

	return ld


static func create_challenge_blind_in_fog_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = -1
	ld.level = 2
	ld.title = "迷雾盲行"
	ld.description = "在完全不使用迷雾清除核心的情况下完成拓扑相变"
	ld.space_group_number = 225
	ld.space_group_symbol = "Fm-3m"
	ld.lattice_parameters = Vector3(5.64, 5.64, 5.64)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 10
	ld.hint = "不能花核心清雾，只能凭推理和直觉穿越不可判定区域"
	ld.journal_entry = "Blind in fog: No cores to spend. Only intuition walks through the undecidable."
	ld.domain = "topology"
	ld.construction_mode = "path_build"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.5, 12.0)
	ld.available_tools = ["element_block", "topology_tool", "path_builder"]

	ld.scene_config = {
		"initial_phase": "cubic",
		"target_phase": "tetragonal",
		"transition_order_parameter": 0.0,
	}

	ld.constraints = {"no_fog_clear": true}

	ld.elements = [
		{"symbol": "M", "wyckoff_label": "a", "wyckoff_multiplicity": 4, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "O", "wyckoff_label": "b", "wyckoff_multiplicity": 4, "position": Vector3(0.5, 0.5, 0.5)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.5, 0.5, 0.5), "radius": 4.0, "fog_type": "independent", "label": "盲行迷雾区"},
	]

	ld.goals = [
		{"type": "wyckoff_fill", "description": "填充M到4a位", "element": "M", "wyckoff": "a", "required_count": 4},
		{"type": "wyckoff_fill", "description": "填充O到4b位", "element": "O", "wyckoff": "b", "required_count": 4},
		{"type": "topology_check", "description": "迷雾中构建连续拓扑路径", "topology_type": "chain", "min_nodes": 3},
		{"type": "conservation_check", "description": "相变过程守恒矩阵连续", "max_deviation": 0.25},
		{"type": "verification", "description": "完成迷雾盲行验证", "required_layer": 2},
	]

	return ld


static func create_challenge_conservation_purist_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = -1
	ld.level = 3
	ld.title = "守恒洁癖"
	ld.description = "构建乙醇分子，全程不允许任何守恒矩阵警告"
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(8.0, 8.0, 8.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 12
	ld.hint = "每一步都必须完美守恒，任何偏差都会触发警告导致失败"
	ld.journal_entry = "Conservation purist: Zero warnings. The matrix must be pristine. Perfection or nothing."
	ld.domain = "molecular"
	ld.construction_mode = "bond_build"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.3, 5.0)
	ld.available_tools = ["atom_placer", "bond_rotator", "angle_adjuster"]

	ld.scene_config = {
		"target_molecule": "C2H5OH",
		"strict_conservation": true,
	}

	ld.constraints = {"no_warning_ever": true}

	ld.elements = [
		{"symbol": "C", "wyckoff_label": "a", "wyckoff_multiplicity": 2, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "O", "wyckoff_label": "b", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.5, 0.0)},
		{"symbol": "H", "wyckoff_label": "c", "wyckoff_multiplicity": 6, "position": Vector3(0.25, 0.25, 0.25)},
	]

	ld.goals = [
		{"type": "bond_build", "description": "构建C-C骨架键", "required_bonds": 1, "bond_pairs": [["C", "C"]]},
		{"type": "bond_build", "description": "构建C-O键", "required_bonds": 1, "bond_pairs": [["C", "O"]]},
		{"type": "bond_build", "description": "构建C-H键(6个)", "required_bonds": 6, "bond_pairs": [["C", "H"]]},
		{"type": "bond_build", "description": "构建O-H键", "required_bonds": 1, "bond_pairs": [["O", "H"]]},
		{"type": "conservation_check", "description": "全程零警告守恒", "max_deviation": 0.01},
		{"type": "verification", "description": "完成守恒洁癖验证", "required_layer": 1},
	]

	return ld


static func create_challenge_speed_builder_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = -1
	ld.level = 4
	ld.title = "速度构造"
	ld.description = "60秒内构建钙钛矿结构，时间就是一切"
	ld.space_group_number = 221
	ld.space_group_symbol = "Pm-3m"
	ld.lattice_parameters = Vector3(3.91, 3.91, 3.91)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 8
	ld.hint = "ABO3钙钛矿: A在角，B在体心，O在面心，快速填充别犹豫"
	ld.journal_entry = "Speed builder: 60 seconds. No time for doubt. Muscle memory meets crystal structure."
	ld.domain = "crystal"
	ld.construction_mode = "wyckoff_fill"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.5, 10.0)
	ld.available_tools = ["element_block", "wyckoff_snap"]

	ld.scene_config = {
		"perovskite_type": "ABO3",
		"a_site": "Ca",
		"b_site": "Ti",
	}

	ld.constraints = {"time_limit_seconds": 60}

	ld.elements = [
		{"symbol": "Ca", "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "Ti", "wyckoff_label": "b", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.5, 0.5)},
		{"symbol": "O", "wyckoff_label": "c", "wyckoff_multiplicity": 3, "position": Vector3(0.5, 0.5, 0.0)},
	]

	ld.goals = [
		{"type": "wyckoff_fill", "description": "将Ca放置在1a位(A位)", "element": "Ca", "wyckoff": "a", "required_count": 1},
		{"type": "wyckoff_fill", "description": "将Ti放置在1b位(B位)", "element": "Ti", "wyckoff": "b", "required_count": 1},
		{"type": "wyckoff_fill", "description": "将O放置在3c位", "element": "O", "wyckoff": "c", "required_count": 3},
		{"type": "conservation_check", "description": "钙钛矿守恒矩阵健康", "max_deviation": 0.1},
		{"type": "verification", "description": "完成速度构造验证", "required_layer": 0},
	]

	return ld


static func create_challenge_omniscient_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = -1
	ld.level = 5
	ld.title = "全知全能"
	ld.description = "在任意结构上完成全部验证层(L0-L4)，证明你的构造无懈可击"
	ld.space_group_number = 225
	ld.space_group_symbol = "Fm-3m"
	ld.lattice_parameters = Vector3(5.64, 5.64, 5.64)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 20
	ld.hint = "L0符号→L1守恒→L2几何→L3输运→L4拓扑，全部通过才算完成"
	ld.journal_entry = "Omniscient: All five layers. From symbol to topology. Complete verification is complete proof."
	ld.domain = "open"
	ld.construction_mode = "free"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.5, 50.0)
	ld.available_tools = ["element_block", "wyckoff_snap", "bond_tool", "interface_builder", "strain_tool", "channel_inspector", "molecule_builder", "reaction_arrow", "energy_diagram", "topology_tool", "path_builder"]

	ld.scene_config = {
		"required_verification_layers": [0, 1, 2, 3, 4],
	}

	ld.constraints = {"all_verification_layers": true}

	ld.elements = [
		{"symbol": "M", "wyckoff_label": "a", "wyckoff_multiplicity": 4, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "O", "wyckoff_label": "b", "wyckoff_multiplicity": 4, "position": Vector3(0.5, 0.5, 0.5)},
	]

	ld.goals = [
		{"type": "wyckoff_fill", "description": "构建基础结构", "element": "M", "wyckoff": "a", "required_count": 4},
		{"type": "wyckoff_fill", "description": "完成结构填充", "element": "O", "wyckoff": "b", "required_count": 4},
		{"type": "conservation_check", "description": "L0符号验证通过", "max_deviation": 0.05},
		{"type": "conservation_check", "description": "L1守恒验证通过", "max_deviation": 0.05},
		{"type": "verification", "description": "L2几何验证通过", "required_layer": 2},
		{"type": "verification", "description": "L3输运验证通过", "required_layer": 3},
		{"type": "verification", "description": "L4拓扑验证通过", "required_layer": 4},
	]

	return ld


# ============================================================
# Chapter 4: Emergence
# ============================================================

static func create_self_assembly_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 4
	ld.level = 1
	ld.title = "自组装"
	ld.description = "设计分子间相互作用使胶体粒子自发组装为目标结构——你只能设定规则，不能直接放置"
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(20.0, 20.0, 20.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 12
	ld.hint = "自组装的关键是相互作用规则而非位置，让热力学替你工作"
	ld.journal_entry = "Self-assembly: Set the rules, let thermodynamics build. The structure emerges from the law."
	ld.domain = "molecular"
	ld.construction_mode = "assembly"
	ld.scale_label = "nm"
	ld.scale_range = Vector2(0.5, 30.0)
	ld.available_tools = ["interaction_designer", "potential_setter", "assembly_watcher"]

	ld.scene_config = {
		"particle_count": 50,
		"interaction_types": ["attractive", "repulsive", "directional"],
		"target_structure": "cubic_lattice",
		"temperature_k": 300.0,
		"assembly_steps": 1000,
	}

	ld.constraints = {"indirect_control_only": true, "max_interaction_rules": 4}

	ld.elements = [
		{"symbol": "A", "wyckoff_label": "a", "wyckoff_multiplicity": 25, "position": Vector3(0.3, 0.3, 0.3)},
		{"symbol": "B", "wyckoff_label": "b", "wyckoff_multiplicity": 25, "position": Vector3(0.7, 0.7, 0.7)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.5, 0.5, 0.5), "radius": 4.0, "fog_type": "semi_decidable", "label": "组装路径不确定性区"},
	]

	ld.goals = [
		{"type": "assembly_check", "description": "自组装簇", "required_parts": {"单体簇": 3}},
		{"type": "conservation_check", "description": "自组装守恒", "max_deviation": 0.1},
		{"type": "assembly_check", "description": "粒子自发组装为目标结构", "component": "self_assembled", "target_order": 0.8},
		{"type": "conservation_check", "description": "组装过程能量守恒", "max_deviation": 0.1},
		{"type": "conservation_check", "description": "组装过程粒子数守恒", "max_deviation": 0.05},
		{"type": "verification", "description": "完成自组装验证", "required_layer": 2},
	]

	return ld


static func create_symmetry_cascade_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 4
	ld.level = 2
	ld.title = "对称性破缺级联"
	ld.description = "驱动结构经历三级对称性破缺(Pm-3m→P4mm→Amm2→P1)，每级破缺需维持守恒连续"
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(4.0, 4.2, 4.5)
	ld.lattice_angles = Vector3(89.0, 91.0, 90.5)
	ld.reward_cores = 15
	ld.hint = "每级破缺降低一个对称操作，守恒矩阵必须在整个级联中保持连续"
	ld.journal_entry = "Symmetry cascade: Three breaks, one chain. Each descent costs symmetry but preserves conservation."
	ld.domain = "crystal"
	ld.construction_mode = "wyckoff_fill"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.5, 10.0)
	ld.available_tools = ["element_block", "wyckoff_snap", "symmetry_breaker", "strain_tool"]

	ld.scene_config = {
		"cascade_stages": [
			{"from_sg": 221, "to_sg": 99, "order_param": "c/a_ratio"},
			{"from_sg": 99, "to_sg": 38, "order_param": "beta_angle"},
			{"from_sg": 38, "to_sg": 1, "order_param": "all_angles"},
		],
	}

	ld.elements = [
		{"symbol": "A", "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "B", "wyckoff_label": "b", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.5, 0.5)},
		{"symbol": "O1", "wyckoff_label": "c", "wyckoff_multiplicity": 3, "position": Vector3(0.5, 0.5, 0.0)},
		{"symbol": "O2", "wyckoff_label": "d", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.0, 0.52)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.5, 0.5, 0.5), "radius": 3.0, "fog_type": "independent", "label": "对称性破缺临界区"},
	]

	ld.goals = [
		{"type": "symmetry_check", "description": "完成第一级破缺(Pm-3m→P4mm)", "source_sg": 221, "target_sg": 99},
		{"type": "symmetry_check", "description": "完成第二级破缺(P4mm→Amm2)", "source_sg": 99, "target_sg": 38},
		{"type": "symmetry_check", "description": "完成第三级破缺(Amm2→P1)", "source_sg": 38, "target_sg": 1},
		{"type": "conservation_check", "description": "级联全程守恒矩阵连续", "max_deviation": 0.2},
		{"type": "conservation_check", "description": "每级破缺后质量守恒", "max_deviation": 0.1},
		{"type": "verification", "description": "完成对称性破缺级联验证", "required_layer": 3},
	]

	return ld


static func create_topological_defect_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 4
	ld.level = 3
	ld.title = "拓扑缺陷"
	ld.description = "在二维晶格中引入位错和向错缺陷，理解Burgers矢量与拓扑荷——缺陷不可连续消除"
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(15.0, 15.0, 5.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 10
	ld.hint = "位错的Burgers矢量是拓扑不变量，无法通过连续形变消除——只能与反号位错湮灭"
	ld.journal_entry = "Topological defect: The Burgers vector is a knot in the lattice. Continuous deformation cannot untie it."
	ld.domain = "topology"
	ld.construction_mode = "mesh_build"
	ld.scale_label = "nm"
	ld.scale_range = Vector2(0.1, 20.0)
	ld.available_tools = ["mesh_builder", "defect_placer", "burgers_calculator"]

	ld.scene_config = {
		"lattice_type": "2d_triangular",
		"defect_types": ["edge_dislocation", "screw_dislocation", "disclination"],
		"burgers_vectors": [[1, 0], [0, 1], [1, 1]],
	}

	ld.elements = [
		{"symbol": "ATOM", "wyckoff_label": "a", "wyckoff_multiplicity": 100, "position": Vector3(0.5, 0.5, 0.5)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.5, 0.5, 0.5), "radius": 3.0, "fog_type": "undecidable", "label": "位错核心区"},
	]

	ld.goals = [
		{"type": "mesh_build", "description": "构建二维三角晶格", "mesh_density": "uniform", "required_atoms": 50},
		{"type": "conservation_check", "description": "缺陷处守恒", "max_deviation": 0.15},
		{"type": "topology_check", "description": "缺陷诱导拓扑结构变化", "topology_type": "ring", "min_nodes": 5},
		{"type": "conservation_check", "description": "缺陷引入后守恒矩阵健康", "max_deviation": 0.2},
		{"type": "geometry_check", "description": "位错核心应变场正确", "strain_field": "1/r"},
		{"type": "verification", "description": "完成拓扑缺陷验证", "required_layer": 2},
	]

	return ld


static func create_phase_field_evolution_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 4
	ld.level = 4
	ld.title = "相场演化"
	ld.description = "设定Allen-Cahn相场方程的初始条件，驱动微结构演化至目标形貌——控制自由能泛函的梯度项"
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(20.0, 20.0, 20.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 14
	ld.hint = "Allen-Cahn方程: ∂φ/∂t = -δF/δφ，梯度项κ控制界面宽度，双势阱决定两相"
	ld.journal_entry = "Phase field: The free energy functional writes the script. The gradient term directs the play."
	ld.domain = "thermodynamics"
	ld.construction_mode = "mesh_build"
	ld.scale_label = "nm"
	ld.scale_range = Vector2(0.1, 50.0)
	ld.available_tools = ["mesh_builder", "potential_designer", "gradient_setter", "evolution_watcher"]

	ld.scene_config = {
		"equation": "allen_cahn",
		"kappa": 0.5,
		"double_well_depth": 1.0,
		"initial_condition": "random_nucleation",
		"evolution_steps": 500,
		"target_morphology": "lamellar",
	}

	ld.constraints = {"max_kappa_adjustments": 3}

	ld.elements = [
		{"symbol": "PHASE_A", "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.3, 0.5, 0.5)},
		{"symbol": "PHASE_B", "wyckoff_label": "b", "wyckoff_multiplicity": 1, "position": Vector3(0.7, 0.5, 0.5)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.5, 0.5, 0.5), "radius": 4.0, "fog_type": "semi_decidable", "label": "相界面演化区"},
	]

	ld.goals = [
		{"type": "mesh_build", "description": "构建相场计算网格", "mesh_density": "uniform", "required_atoms": 40},
		{"type": "conservation_check", "description": "相场势守恒", "max_deviation": 0.1},
		{"type": "geometry_check", "description": "相场几何演化", "target_lattice": 3.0, "lattice_tolerance": 0.2},
		{"type": "conservation_check", "description": "相场演化自由能单调递减", "max_deviation": 0.05},
		{"type": "conservation_check", "description": "演化过程总质量守恒", "max_deviation": 0.1},
		{"type": "verification", "description": "完成相场演化验证", "required_layer": 3},
	]

	return ld


static func create_open_emergence_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 4
	ld.level = 5
	ld.title = "开放涌现"
	ld.description = "在沙盒中创造涌现现象——从简单规则中产生不可预测的复杂行为，证明涌现即不可判定性"
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(30.0, 30.0, 30.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 25
	ld.hint = "涌现 = 简单规则 + 不可预测的结果。你无法从规则预测行为——这就是Gödel的影子"
	ld.journal_entry = "Open emergence: Simple rules, complex outcomes. Undecidability is not a bug — it is the game."
	ld.domain = "open"
	ld.construction_mode = "free"
	ld.scale_label = "nm"
	ld.scale_range = Vector2(0.1, 100.0)
	ld.available_tools = ["interaction_designer", "potential_setter", "assembly_watcher", "mesh_builder", "potential_designer", "gradient_setter", "evolution_watcher", "defect_placer", "burgers_calculator", "symmetry_breaker", "self-evolve"]

	ld.scene_config = {
		"emergence_targets": [
			"spontaneous_symmetry_breaking",
			"pattern_formation",
			"self_organized_criticality",
		],
		"verification_depth": "deepest_possible",
		"community_ranking": true,
	}

	ld.constraints = {"emergence_required": true}

	ld.elements = [
		{"symbol": "X", "wyckoff_label": "a", "wyckoff_multiplicity": 50, "position": Vector3(0.5, 0.5, 0.5)},
		{"symbol": "Y", "wyckoff_label": "b", "wyckoff_multiplicity": 50, "position": Vector3(0.3, 0.7, 0.5)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.5, 0.5, 0.5), "radius": 8.0, "fog_type": "independent", "label": "涌现不可判定区"},
	]

	ld.goals = [
		{"type": "conservation_check", "description": "涌现结构守恒", "max_deviation": 0.08},
		{"type": "geometry_check", "description": "涌现结构各向异性", "target_ca_ratio": 1.02, "ca_tolerance": 0.05, "min_ca": 1.0},
		{"type": "conservation_check", "description": "涌现过程守恒矩阵健康", "max_deviation": 0.2},
		{"type": "geometry_check", "description": "产生可观测的有序结构", "has_channel": true},
		{"type": "verification", "description": "完成最深验证层(涌现=不可判定)", "required_layer": 4},
	]

	return ld


# ============================================================
# Chapter 4-E: Cellular Automata (元胞自动机)
# ============================================================

static func create_ca_bays_4555_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 4
	ld.level = 6
	ld.title = "Bays' 3D 生命游戏"
	ld.description = "在3D Moore邻域中构造一个能稳定生存的结构。简单规则(B4555)下的细胞集群会涌现出不可预测的3D形态。"
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(10.0, 10.0, 10.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 18
	ld.hint = "B4555规则: 死细胞有5个邻居时出生, 活细胞有4或5个邻居时存活。试试中心十字形初始态。"
	ld.journal_entry = "Bays' 3D life: In a cubic lattice of 26 neighbors, survival is a narrow window. Order emerges from the edge of chaos."
	ld.domain = "open"
	ld.construction_mode = "cellular_automaton"
	ld.scale_label = "nm"
	ld.scale_range = Vector2(0.5, 20.0)
	ld.available_tools = ["ca_placer", "ca_step", "ca_run", "ca_reset"]

	ld.scene_config = {
		"ca_rule": "bays_4555",
		"grid_size": [8, 8, 8],
		"initial_pattern": "center_seed",
		"evolution_steps": 50,
		"auto_evolve_interval": 0.3,
	}

	ld.constraints = {"max_steps": 50, "max_edits": 20}

	ld.elements = [
		{"symbol": "CA", "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.5, 0.5)},
	]

	ld.goals = [
		{"type": "ca_pattern_reach", "description": "演化出非灭绝的稳定结构", "target_pattern": "stable", "min_steps": 10},
		{"type": "ca_conservation_maintain", "description": "演化中守恒矩阵保持健康", "max_deviation": 0.25, "min_steps": 15},
		{"type": "verification", "description": "完成CA演化验证", "required_layer": 2},
	]

	return ld


static func create_ca_oscillator_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 4
	ld.level = 7
	ld.title = "3D 振荡器"
	ld.description = "设计初始态使元胞自动机进入周期振荡。周期模式是3D生命中稀少的数学宝石。"
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(12.0, 12.0, 12.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 22
	ld.hint = "B5766规则更容易产生滑翔机和振荡器。从小的对称团块开始, 观察它是否周期性重复。"
	ld.journal_entry = "An oscillator in 3D is a clock made of nothing but neighbor counts. Time crystallized."
	ld.domain = "open"
	ld.construction_mode = "cellular_automaton"
	ld.scale_label = "nm"
	ld.scale_range = Vector2(0.5, 20.0)
	ld.available_tools = ["ca_placer", "ca_step", "ca_run", "ca_reset"]

	ld.scene_config = {
		"ca_rule": "bays_5766",
		"grid_size": [10, 10, 10],
		"initial_pattern": "random_sparse",
		"evolution_steps": 80,
		"auto_evolve_interval": 0.25,
	}

	ld.constraints = {"max_steps": 80, "max_edits": 30}

	ld.elements = [
		{"symbol": "CA", "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.5, 0.5)},
	]

	ld.goals = [
		{"type": "ca_pattern_reach", "description": "演化出周期振荡器", "target_pattern": "oscillator", "min_steps": 12},
		{"type": "ca_conservation_maintain", "description": "保持守恒矩阵在警告以下", "max_deviation": 0.3, "min_steps": 20},
		{"type": "verification", "description": "完成CA周期验证", "required_layer": 2},
	]

	return ld


static func create_ca_phase_transition_level() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 4
	ld.level = 8
	ld.title = "相变临界点"
	ld.description = "通过调整初始密度观察元胞自动机从混沌到有序的相变。找到临界密度附近, 让系统自发组织成稳定结构。"
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(16.0, 16.0, 16.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 26
	ld.hint = "随机初始密度约0.2-0.3时最容易发生相变。反复重置直到找到临界区, 然后运行足够步数。"
	ld.journal_entry = "At the critical density, randomness forgets itself and order appears. This is how universality begins."
	ld.domain = "open"
	ld.construction_mode = "cellular_automaton"
	ld.scale_label = "nm"
	ld.scale_range = Vector2(0.5, 20.0)
	ld.available_tools = ["ca_placer", "ca_step", "ca_run", "ca_reset"]

	ld.scene_config = {
		"ca_rule": "bays_4555",
		"grid_size": [12, 12, 12],
		"initial_pattern": "random_medium",
		"evolution_steps": 100,
		"auto_evolve_interval": 0.15,
	}

	ld.constraints = {"max_steps": 100, "max_edits": 15}

	ld.elements = [
		{"symbol": "CA", "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.5, 0.5)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.5, 0.5, 0.5), "radius": 5.0, "fog_type": "semi_decidable", "label": "临界涨落区"},
	]

	ld.goals = [
		{"type": "ca_phase_transition", "description": "从混沌演化到稳定相态", "target_phase": "stable", "min_steps": 25},
		{"type": "ca_conservation_maintain", "description": "相变过程守恒矩阵健康", "max_deviation": 0.35, "min_steps": 30},
		{"type": "verification", "description": "完成相变验证", "required_layer": 3},
	]

	return ld


# ============================================================
# Daily Challenge Factory
# ============================================================

static func create_daily_challenge(day_seed: int) -> LevelData:
	var rng := RandomNumberGenerator.new()
	rng.seed = day_seed

	var domains := ["crystal", "molecular", "fluid", "device", "reaction", "topology"]
	var domain: String = domains[rng.randi_range(0, domains.size() - 1)]

	var constraint_pool := [
		{"max_proof_depth": 5},
		{"time_limit_seconds": 90},
		{"max_parts": 6},
		{"no_fog_clear": true},
		{"no_warning_ever": true},
	]
	var chosen_constraint: Dictionary = constraint_pool[rng.randi_range(0, constraint_pool.size() - 1)]

	var property_pool := [
		{"ionic_conductivity_min": 1e-3},
		{"band_gap_range": [1.0, 3.0]},
		{"stability_threshold": 0.1},
		{"selectivity_threshold": 5.0},
		{"thermal_conductivity_max": 2.0},
	]
	var target_property: Dictionary = property_pool[rng.randi_range(0, property_pool.size() - 1)]

	# 难度决定核心奖励
	var difficulty: int = rng.randi_range(1, 3)
	var reward: int = 5 + difficulty * 5  # 5, 10, 15

	var construction_modes := {
		"crystal": "wyckoff_fill",
		"molecular": "bond_build",
		"fluid": "mesh_build",
		"device": "assembly",
		"reaction": "path_build",
		"topology": "path_build",
	}

	var ld := LevelData.new()
	ld.chapter = -2
	ld.level = day_seed
	ld.title = "每日挑战 #%d" % day_seed
	ld.description = "今日挑战: 在%s域中完成特殊约束任务" % domain
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(10.0, 10.0, 10.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = reward
	ld.hint = "每日挑战 - 全服同题，争取最高分!"
	ld.domain = domain
	ld.construction_mode = construction_modes.get(domain, "wyckoff_fill")
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.5, 20.0)
	ld.available_tools = ["element_block", "wyckoff_snap", "bond_tool"]

	ld.scene_config = {
		"target_property": target_property,
		"difficulty": difficulty,
		"daily_seed": day_seed,
	}

	ld.constraints = chosen_constraint

	ld.elements = [
		{"symbol": "X", "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "Y", "wyckoff_label": "b", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.5, 0.0)},
	]

	ld.fog_zones = [
		{"position": Vector3(0.5, 0.5, 0.5), "radius": 2.0, "fog_type": "semi_decidable", "label": "每日挑战迷雾"},
	]

	ld.goals = [
		{"type": "conservation_check", "description": "结构守恒矩阵健康", "max_deviation": 0.15},
		{"type": "geometry_check", "description": "满足目标性能约束", "energy_downhill": true},
		{"type": "verification", "description": "完成每日挑战验证", "required_layer": 1},
	]

	return ld
