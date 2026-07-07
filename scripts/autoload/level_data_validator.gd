# level_data_validator.gd
# 关卡数据运行时验证器 - 校验 JSON 关卡数据的完整性和有效性
#
# 验证规则:
#   - 必填字段: chapter, level, title, description, goals
#   - goals 非空且每个 goal 有 type 和 description
#   - 支持的目标类型白名单
#   - chapter/level 为正整数 (挑战/额外关卡允许负值/零)
#   - reward_cores > 0
#   - elements 在 construction_mode != "free" 时必须非空
#   - scene_config 键类型检查
#   - lattice_parameters 各分量 > 0

extends RefCounted
class_name LevelDataValidator

const VALID_GOAL_TYPES: Array[String] = [
	"wyckoff_fill", "conservation_check", "verification",
	"symmetry_check", "bond_check", "bond_build", "geometry_check",
	"transport_check", "interface_check", "reaction_path", "assembly_check",
	"topology_check", "mesh_build", "path_build", "thermal_check",
	"diffusion_check", "em_check", "ca_pattern_reach",
	"ca_conservation_maintain", "ca_phase_transition",
	"fuzzy_check", "ca_step_count", "element_count", "fog_dispel", "bond_count",
	"structure_quality", "survives_simulation",
	"survives_phase_transition", "magnetic_order_check",
	"catalyst_efficiency_check", "resonance_check",
	"stability_target", "energy_target", "strain_target",
]

const VALID_CONSTRUCTION_MODES: Array[String] = [
	"wyckoff_fill", "bond_build", "mesh_build", "path_build",
	"assembly", "free", "cellular_automaton",
]

const VALID_DOMAINS: Array[String] = [
	"crystal", "molecular", "fluid", "device", "reaction", "topology", "open",
	"electromagnetics", "thermodynamics", "statistical_mechanics", "multiphysics",
]


static func validate(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []

	# Schema version check (optional for backward compatibility)
	if not data.has("v"):
		# Silently allow missing 'v' for legacy data; warn in debug mode
		pass
	else:
		var v = data.get("v", 0)
		if v != 1:
			errors.append("Unsupported schema version: %d (expected 1)" % v)

	# 必填字段
	var required := ["chapter", "level", "title", "description", "goals"]
	for key in required:
		if not data.has(key):
			errors.append("Missing required field: %s" % key)

	if not data.has("goals"):
		return errors

	var goals: Array = data.get("goals", [])
	if goals.is_empty():
		errors.append("Goals array is empty")
	else:
		for i in range(goals.size()):
			var g = goals[i]
			if not g is Dictionary:
				errors.append("Goal[%d] is not a Dictionary" % i)
				continue
			if not g.has("type"):
				errors.append("Goal[%d] missing 'type'" % i)
			else:
				var gt: String = str(g.get("type", ""))
				if not VALID_GOAL_TYPES.has(gt):
					errors.append("Goal[%d] has invalid type: '%s'" % [i, gt])
			if not g.has("description"):
				errors.append("Goal[%d] missing 'description'" % i)

	# chapter/level 类型检查
	if data.has("chapter") and not (data["chapter"] is int):
		errors.append("Field 'chapter' must be int, got %s" % typeof(data["chapter"]))
	if data.has("level") and not (data["level"] is int):
		errors.append("Field 'level' must be int, got %s" % typeof(data["level"]))

	# reward_cores
	var reward_cores: int = int(data.get("reward_cores", 0))
	if reward_cores <= 0:
		errors.append("reward_cores must be > 0, got %d" % reward_cores)

	# construction_mode 白名单
	var cm: String = str(data.get("construction_mode", "wyckoff_fill"))
	if not VALID_CONSTRUCTION_MODES.has(cm):
		errors.append("Invalid construction_mode: '%s'" % cm)

	# domain 白名单
	var domain: String = str(data.get("domain", "crystal"))
	if not VALID_DOMAINS.has(domain):
		errors.append("Invalid domain: '%s'" % domain)

	# elements 非空检查 (free 模式允许空)
	if cm != "free":
		var elements: Array = data.get("elements", [])
		if elements.is_empty():
			errors.append("elements array is empty for non-free mode '%s'" % cm)
		else:
			for i in range(elements.size()):
				var el = elements[i]
				if not el is Dictionary:
					errors.append("Element[%d] is not a Dictionary" % i)
					continue
				if not el.has("symbol"):
					errors.append("Element[%d] missing 'symbol'" % i)

	# lattice_parameters 有效性（兼容多种字段名）
	var lp = data.get("lattice_parameters", data.get("lattice_params", data.get("lattice", {})))
	if lp is Dictionary:
		var lx: float = float(lp.get("x", lp.get("a", 0.0)))
		var ly: float = float(lp.get("y", lp.get("b", 0.0)))
		var lz: float = float(lp.get("z", lp.get("c", 0.0)))
		if lx <= 0.0 or ly <= 0.0 or lz <= 0.0:
			errors.append("lattice_parameters must all be > 0, got (%.3f, %.3f, %.3f)" % [lx, ly, lz])
	elif lp is Vector3:
		if lp.x <= 0.0 or lp.y <= 0.0 or lp.z <= 0.0:
			errors.append("lattice_parameters must all be > 0, got %s" % str(lp))
	else:
		errors.append("lattice_parameters must be Dictionary or Vector3")

	# scene_config 键检查 (只检查类型，不检查内容)
	var sc = data.get("scene_config", {})
	if sc != null and not sc is Dictionary:
		errors.append("scene_config must be a Dictionary")

	# constraints 类型检查
	var constraints = data.get("constraints", {})
	if constraints != null and not constraints is Dictionary:
		errors.append("constraints must be a Dictionary")

	# fog_zones 类型检查
	var fog_zones: Array = data.get("fog_zones", [])
	for i in range(fog_zones.size()):
		var zone = fog_zones[i]
		if not zone is Dictionary:
			errors.append("FogZone[%d] is not a Dictionary" % i)

	# available_tools 类型检查
	var tools: Array = data.get("available_tools", [])
	if not tools.is_empty() and tools.size() > 0:
		if not (tools[0] is String):
			errors.append("available_tools must be Array[String]")

	return errors


static func is_valid(data: Dictionary) -> bool:
	return validate(data).is_empty()


# 关卡可达性校验：静态证明目标在给定约束下可达
# 返回 Array[String] 为可达性警告（非致命，用于开发期发现问题）
static func validate_reachability(data: Dictionary) -> Array[String]:
	var warnings: Array[String] = []
	var goals: Array = data.get("goals", [])
	var constraints: Dictionary = data.get("constraints", {})
	var construction_mode: String = str(data.get("construction_mode", "wyckoff_fill"))
	var elements: Array = data.get("elements", [])
	var available_tools: Array = data.get("available_tools", [])
	var forbidden_tools: Array = data.get("forbidden_tools", [])
	var lattice = data.get("lattice_parameters", {})

	# 1. max_parts 约束 vs 目标所需原子数
	var max_parts: int = int(constraints.get("max_parts", 0))
	if max_parts > 0:
		var total_atoms_required := 0
		for g in goals:
			if not g is Dictionary:
				continue
			match str(g.get("type", "")):
				"element_count", "wyckoff_fill":
					total_atoms_required += int(g.get("required_count", 1))
				"mesh_build":
					total_atoms_required += int(g.get("required_atoms", g.get("required_count", 1)))
				"fuzzy_check":
					if str(g.get("metric", "")) == "atom_count":
						total_atoms_required += int(ceil(float(g.get("threshold", 0))))
				"symmetry_check":
					total_atoms_required += int(g.get("required_count", 1))
		if total_atoms_required > max_parts:
			warnings.append("REACHABILITY: max_parts=%d 但目标共需 %d 原子（不可通关）" % [max_parts, total_atoms_required])

	# 2. forbidden_tools vs 目标类型矛盾
	var has_bond_goal := false
	var has_path_goal := false
	for g in goals:
		if not g is Dictionary:
			continue
		var gt: String = str(g.get("type", ""))
		if gt in ["bond_check", "bond_build", "bond_count"]:
			has_bond_goal = true
		if gt in ["path_build", "topology_check", "diffusion_check", "reaction_path"]:
			has_path_goal = true
	if has_bond_goal and forbidden_tools.has("bond_tool") and "bond_tool" in available_tools:
		# bond_tool 被禁但目标要求键 → 需要assembly模式自动成键或移除目标
		if construction_mode != "assembly":
			warnings.append("REACHABILITY: bond_tool 被禁用且非 assembly 模式，但目标要求成键")
	if has_path_goal and forbidden_tools.has("path_builder"):
		warnings.append("REACHABILITY: path_builder 被禁用，但目标要求路径构建")

	# 3. symmetry_check 可行性：立方晶格无法降低对称性
	for g in goals:
		if not g is Dictionary:
			continue
		if str(g.get("type", "")) == "symmetry_check":
			var source_sg: int = int(g.get("source_sg", 0))
			var target_sg: int = int(g.get("target_sg", 0))
			if source_sg != target_sg and source_sg > 0:
				# 检查晶格是否为立方（a=b=c）
				if lattice is Dictionary:
					var lx: float = float(lattice.get("x", 0))
					var ly: float = float(lattice.get("y", 0))
					var lz: float = float(lattice.get("z", 0))
					var is_cubic: bool = absf(lx - ly) < 0.001 and absf(ly - lz) < 0.001
					var is_cubic_sg: bool = source_sg in [195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230]
					if is_cubic and is_cubic_sg:
						warnings.append("REACHABILITY: symmetry_check 立方晶格(a=b=c)无法降低对称性 sg %d→%d" % [source_sg, target_sg])

	# 4. CA 目标需要 cellular_automaton 模式
	var has_ca_goal := false
	for g in goals:
		if not g is Dictionary:
			continue
		var gt: String = str(g.get("type", ""))
		if gt.begins_with("ca_"):
			has_ca_goal = true
	if has_ca_goal and construction_mode != "cellular_automaton":
		warnings.append("REACHABILITY: CA 目标需要 construction_mode='cellular_automaton'，当前为 '%s'" % construction_mode)

	# 5. element_count 目标引用的元素必须在 elements 列表中
	var available_symbols: Array[String] = []
	for el in elements:
		if el is Dictionary and el.has("symbol"):
			available_symbols.append(str(el["symbol"]))
	for g in goals:
		if not g is Dictionary:
			continue
		if str(g.get("type", "")) == "element_count":
			var sym: String = str(g.get("symbol", g.get("element", "")))
			if sym != "" and not available_symbols.has(sym) and not available_symbols.is_empty():
				warnings.append("REACHABILITY: element_count 目标要求 '%s' 但该元素不在 elements 列表中" % sym)

	# 6. reward_cores 单调性检查（同章节内奖励不应倒挂）
	# 此项需要跨关卡数据，留作扩展

	return warnings
