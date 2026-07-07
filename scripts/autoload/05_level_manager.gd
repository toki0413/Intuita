# level_manager.gd
# 关卡管理器 - 加载关卡数据、追踪目标、评分
# 负责从LevelData工厂方法加载关卡配置，追踪玩家进度，计算得分
#
# Responsibilities:
#   - 加载关卡数据和胜利条件
#   - 追踪原子放置和目标进度
#   - 关卡完成评分和核心奖励
#   - 提供当前关卡的空间群和晶格参数
#   - 支持多物理域目标检查
#
# Signals:
#   level_loaded(level_data) - 关卡加载完成
#   goal_updated(goal_index, state, progress) - 目标进度更新
#   level_completed(score, cores_earned) - 关卡完成
#   level_failed(reason) - 关卡失败
#
# Dependencies:
#   - Autoload: ConservationEngine, GameState, ProofTree

extends Node

enum GoalType {
	WYCKOFF_FILL, CONSERVATION_CHECK, VERIFICATION,
	SYMMETRY_CHECK, BOND_CHECK,
	BOND_BUILD, GEOMETRY_CHECK, TRANSPORT_CHECK,
	INTERFACE_CHECK, REACTION_PATH, ASSEMBLY_CHECK, TOPOLOGY_CHECK,
	MESH_BUILD, PATH_BUILD, THERMAL_CHECK, DIFFUSION_CHECK, EM_CHECK,
	CA_PATTERN_REACH, CA_CONSERVATION_MAINTAIN, CA_PHASE_TRANSITION,
	STRUCTURE_QUALITY
}
enum GoalState { PENDING, IN_PROGRESS, COMPLETED, FAILED }

signal level_loaded(level_data: Dictionary)
signal goal_updated(goal_index: int, state: int, progress: float)
signal level_completed(score: float, cores_earned: int)
signal level_failed(reason: String)
signal constraint_updated(constraint_type: String, current: float, limit: float)
signal structure_tested(stable: bool, issues: Array)
signal elegance_scored(score: float, breakdown: Dictionary)  # 优雅度评分信号

var current_level_data: Dictionary = {}
var goals: Array[Dictionary] = []
var goal_states: Array[int] = []
var _atoms_placed: Dictionary = {}  # {wyckoff_label: {element: count}}
var _bonds_built: Array[Dictionary] = []  # [{atom_a, atom_b, type}]
var _assembled_parts: Dictionary = {}  # {component: count}
var _path_nodes: Array[Dictionary] = []  # 拓扑/反应路径节点
# CA 演化状态追踪
var _ca_step_count: int = 0
var _ca_alive_count: int = 0
var _ca_density: float = 0.0
var _ca_phase: String = "extinct"
var _ca_max_deviation: float = 0.0  # 演化过程中守恒矩阵最大偏离
var _ca_patterns_detected: Dictionary = {}  # {pattern_type: count}
var _ca_seeds_saved: int = 0  # 玩家保存的CA种子数（育种关卡使用）
var _level_completed: bool = false  # 防止 _complete_level 重复触发
var _level_failed: bool = false  # 防止重复触发失败

# 共振生存追踪：记录共振状态持续秒数
var _resonance_duration: float = 0.0
var _resonance_was_active: bool = false

# 效率追踪: 记录玩家操作数，用于计分和星级评价
var move_count: int = 0  # 总操作数（放置+删除+成键+断键+验证）
var placement_count: int = 0
var deletion_count: int = 0
var verification_count: int = 0
var _level_start_time: float = 0.0

# 运行时过程级指标容器
var _metrics: Dictionary = {}

# 优雅度评分: 多解创造模式下的结构质量评估
var _elegance_score: float = 0.0
var _elegance_breakdown: Dictionary = {}

# 约束系统: 执行关卡约束，超限触发失败
var _time_limit: float = 0.0  # 0=无限制
var _move_limit: int = 0  # 0=无限制
var _part_limit: int = 0  # 0=无限制
var _no_warning_constraint: bool = false  # 守恒洁癖: 任何警告即失败
var _max_ca_steps: int = 0  # CA演化步数上限，0=无限制
var _forbidden_tools: Array[String] = []  # 禁用的工具列表
var _max_proof_depth: int = 0  # 证明树深度上限，0=无限制
var _require_all_layers: bool = false  # 是否要求通过所有验证层
var _constraint_check_timer: Timer = null

# 结构稳定性: 连续高偏离会触发瓦解
var _instability_accumulator: float = 0.0  # 累积不稳定性
var _max_instability: float = 3.0  # 累积上限，超过则瓦解
var _instability_modifier: float = 1.0  # 动态难度系数，由 DynamicDifficulty 设置

# JSON 加载器和验证器 (使用 preload 避免 headless 模式下 class_name 未注册)
const LevelDataLoaderRef = preload("res://scripts/autoload/level_data_loader.gd")
const LevelDataValidatorRef = preload("res://scripts/autoload/level_data_validator.gd")
var _loader: Variant = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_loader = LevelDataLoaderRef.new()
	_loader._rebuild_registry()
	# 约束检查定时器: 每秒检查时间限制和稳定性
	_constraint_check_timer = Timer.new()
	_constraint_check_timer.name = "ConstraintCheckTimer"
	_constraint_check_timer.wait_time = 1.0
	_constraint_check_timer.autostart = true
	_constraint_check_timer.timeout.connect(_check_constraints)
	add_child(_constraint_check_timer)


func load_level(chapter: int, level: int) -> void:
	# 加载关卡数据 - 优先从 JSON 加载，fallback 到工厂方法
	var level_data: LevelData = null

	# 1) 尝试从 JSON 注册表加载
	if _loader != null and _loader.has_level(chapter, level):
		level_data = _loader.load_level_data(chapter, level)
		if level_data != null:
			# 运行时验证
			var json_data := level_data.to_json()
			var validation_errors: Array[String] = LevelDataValidatorRef.validate(json_data)
			if not validation_errors.is_empty():
				GameLogger.warn("LevelManager", "[关卡] JSON 验证警告 (第%d章-%d关): %s" % [chapter, level, ", ".join(validation_errors)])
			# 可达性校验：静态检查目标在约束下是否可达
			var reach_warnings: Array[String] = LevelDataValidatorRef.validate_reachability(json_data)
			if not reach_warnings.is_empty():
				GameLogger.error("LevelManager", "[关卡] 可达性警告 (第%d章-%d关): %s" % [chapter, level, "; ".join(reach_warnings)])

	# 2) Fallback: 工厂方法 (兼容旧路径 / 每日挑战)
	if level_data == null:
		level_data = _load_level_from_factory(chapter, level)

	if level_data == null:
		push_warning("关卡未找到: 第%d章-%d关" % [chapter, level])
		level_failed.emit("找不到关卡数据")
		reset_level()
		return

	# 从LevelData对象提取数据
	current_level_data = {
		"chapter": level_data.chapter,
		"level": level_data.level,
		"title": level_data.title,
		"description": level_data.description,
		"space_group_number": level_data.space_group_number,
		"space_group_symbol": level_data.space_group_symbol,
		"lattice_parameters": level_data.lattice_parameters,
		"lattice_angles": level_data.lattice_angles,
		"reward_cores": level_data.reward_cores,
		"hint": level_data.hint,
		"domain": level_data.domain,
		"construction_mode": level_data.construction_mode,
		"scene_config": level_data.scene_config,
		"scale_label": level_data.scale_label,
		"scale_range": level_data.scale_range,
		"available_tools": level_data.available_tools,
		"fog_zones": level_data.fog_zones,
		"constraints": level_data.constraints,
		"journal_entry": level_data.journal_entry,
		"elements": level_data.elements,
		"goals": level_data.goals,
	}

	# 解析胜利条件
	goals.clear()
	goal_states.clear()
	for goal in level_data.goals:
		goals.append(goal)
		goal_states.append(GoalState.PENDING)

	_atoms_placed.clear()
	_bonds_built.clear()
	_assembled_parts.clear()
	_path_nodes.clear()
	# 重置 CA 追踪
	_ca_step_count = 0
	_ca_alive_count = 0
	_ca_density = 0.0
	_ca_phase = "extinct"
	_ca_max_deviation = 0.0
	_ca_patterns_detected.clear()
	_ca_seeds_saved = 0
	# 重置共振生存追踪
	_resonance_duration = 0.0
	_resonance_was_active = false

	# 重置效率追踪
	move_count = 0
	placement_count = 0
	deletion_count = 0
	verification_count = 0
	_level_start_time = Time.get_ticks_msec() / 1000.0
	_level_failed = false
	_level_completed = false

	# 重置运行时过程级指标
	_metrics = {
		"undo_count": 0,
		"redo_count": 0,
		"hint_count": 0,
		"retry_count": 0,
		"fail_reason": "",
		"goal_completion_times": {},
		"verification_requests": 0,
	}

	# 解析关卡约束
	_parse_constraints(level_data.constraints)

	# 预置迷雾区域
	_spawn_preset_fog(level_data.fog_zones)

	# 切关时重置原子放置计数，避免音高无限累积
	# SoundManager 也会通过 level_loaded 信号再重置一次，这里提前清零保证 emit 前状态干净
	SoundManager.reset_atom_place_count()

	GameLogger.info("LevelManager", "[关卡] 已加载: 第%d章-%d关 - %s [%s]" % [chapter, level, current_level_data["title"], current_level_data["domain"]])
	level_loaded.emit(current_level_data)

	# 触发域教程（如果该构造模式有教程且玩家未看过）
	var construction_mode: String = current_level_data.get("construction_mode", "")
	if not construction_mode.is_empty():
		TutorialManager.start_domain_tutorial(construction_mode)


func _load_level_from_factory(chapter: int, level: int) -> LevelData:
	# 保留工厂方法作为 fallback，支持每日挑战和旧路径
	# 新关卡结构: Ch1(7) Ch2(7) Ch3(11) Ch4(9) Ch5(8) + Ch0(1) Ch-1(3) = 46关
	# 大部分关卡复用旧工厂方法，仅覆盖章节/关卡编号

	# ---- Chapter 1: 初见 (7关) ----
	if chapter == 1 and level == 1:
		return LevelData.create_nacl_level()
	elif chapter == 1 and level == 2:
		return LevelData.create_lifepo4_level()
	elif chapter == 1 and level == 3:
		return _create_ch1_l3_making_connections()
	elif chapter == 1 and level == 4:
		return _create_ch1_l4_the_matrix()
	elif chapter == 1 and level == 5:
		return LevelData.create_diamond_network_level()
	elif chapter == 1 and level == 6:
		return _create_ch1_l6_boss_blind_build()
	elif chapter == 1 and level == 7:
		return _reassign(LevelData.create_ethanol_synthesis_level(), 1, 7)

	# ---- Chapter 2: 破缺 (7关) ----
	elif chapter == 2 and level == 1:
		return _reassign(LevelData.create_octahedral_tilt_level(), 2, 1)
	elif chapter == 2 and level == 2:
		return _reassign(LevelData.create_thermal_expansion_level(), 2, 2)
	elif chapter == 2 and level == 3:
		return _reassign(LevelData.create_phase_transition_level(), 2, 3)
	elif chapter == 2 and level == 4:
		return _create_ch2_l4_into_the_fog()
	elif chapter == 2 and level == 5:
		return _create_ch2_l5_no_sodium_allowed()
	elif chapter == 2 and level == 6:
		return _reassign(LevelData.create_unknown_material_level(), 2, 6)
	elif chapter == 2 and level == 7:
		return _create_ch2_l7_resonance_dance()

	# ---- Chapter 3: 流动 (11关) ----
	elif chapter == 3 and level == 1:
		return _reassign(LevelData.create_ion_channel_level(), 3, 1)
	elif chapter == 3 and level == 2:
		return _reassign(LevelData.create_multi_channel_race_level(), 3, 2)
	elif chapter == 3 and level == 3:
		return _reassign(LevelData.create_grain_boundary_level(), 3, 3)
	elif chapter == 3 and level == 4:
		return _reassign(LevelData.create_topology_transition_level(), 3, 4)
	elif chapter == 3 and level == 5:
		return _reassign(LevelData.create_heat_conduction_path_level(), 3, 5)
	elif chapter == 3 and level == 6:
		return _reassign(LevelData.create_em_shielding_level(), 3, 6)
	elif chapter == 3 and level == 7:
		return _reassign(LevelData.create_multiphysics_coupling_level(), 3, 7)
	elif chapter == 3 and level == 8:
		return _reassign(LevelData.create_fluid_boundary_layer_level(), 3, 8)
	elif chapter == 3 and level == 9:
		return _reassign(LevelData.create_statistical_fluctuations_level(), 3, 9)
	elif chapter == 3 and level == 10:
		return _reassign(LevelData.create_diffusion_equation_level(), 3, 10)
	elif chapter == 3 and level == 11:
		return _reassign(LevelData.create_topological_defect_level(), 3, 11)

	# ---- Chapter 4: 制造 (9关) ----
	elif chapter == 4 and level == 1:
		return _reassign(LevelData.create_catalytic_cycle_level(), 4, 1)
	elif chapter == 4 and level == 2:
		return _reassign(LevelData.create_solid_state_battery_level(), 4, 2)
	elif chapter == 4 and level == 3:
		return _reassign(LevelData.create_photocatalytic_water_splitting_level(), 4, 3)
	elif chapter == 4 and level == 4:
		return _reassign(LevelData.create_superconductor_critical_level(), 4, 4)
	elif chapter == 4 and level == 5:
		return _reassign(LevelData.create_quantum_tunneling_diode_level(), 4, 5)
	elif chapter == 4 and level == 6:
		return _reassign(LevelData.create_protein_folding_funnel_level(), 4, 6)
	elif chapter == 4 and level == 7:
		return _reassign(LevelData.create_co2_capture_level(), 4, 7)
	elif chapter == 4 and level == 8:
		return _reassign(LevelData.create_li_s_battery_level(), 4, 8)
	elif chapter == 4 and level == 9:
		return _reassign(LevelData.create_nanowire_assembly_level(), 4, 9)

	# ---- Chapter 5: 涌现 (8关) ----
	elif chapter == 5 and level == 1:
		return _reassign(LevelData.create_self_assembly_level(), 5, 1)
	elif chapter == 5 and level == 2:
		return _reassign(LevelData.create_ca_bays_4555_level(), 5, 2)
	elif chapter == 5 and level == 3:
		return _create_ch5_l3_breeding()
	elif chapter == 5 and level == 4:
		return _reassign(LevelData.create_symmetry_cascade_level(), 5, 4)
	elif chapter == 5 and level == 5:
		return _reassign(LevelData.create_phase_field_evolution_level(), 5, 5)
	elif chapter == 5 and level == 6:
		return _create_ch5_l6_ecosystem()
	elif chapter == 5 and level == 7:
		return _reassign(LevelData.create_universal_material_designer_level(), 5, 7)
	elif chapter == 5 and level == 8:
		return _reassign(LevelData.create_open_emergence_level(), 5, 8)

	# ---- Bonus (chapter 0) ----
	elif chapter == 0 and level == 1:
		return _reassign(LevelData.create_molecular_folding_level(), 0, 1)

	# ---- Challenge (chapter -1) ----
	elif chapter == -1 and level == 1:
		return _reassign(LevelData.create_challenge_minimalist_level(), -1, 1)
	elif chapter == -1 and level == 2:
		return _reassign(LevelData.create_challenge_conservation_purist_level(), -1, 2)
	elif chapter == -1 and level == 3:
		return _reassign(LevelData.create_challenge_speed_builder_level(), -1, 3)

	# ---- Daily Challenge (chapter -2) ----
	elif chapter == -2:
		return LevelData.create_daily_challenge(level)

	return null


func _reassign(ld: LevelData, chapter: int, level: int) -> LevelData:
	# 覆盖工厂方法返回的章节/关卡编号
	ld.chapter = chapter
	ld.level = level
	return ld


# ===== 新关卡工厂方法（JSON中无对应旧方法） =====

func _create_ch1_l3_making_connections() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 1
	ld.level = 3
	ld.title = "Making Connections"
	ld.description = "Place atoms and link them with bonds. Build a water molecule: O in the center, two H's connected to it."
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(5.0, 5.0, 5.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 3
	ld.hint = "O needs 2 bonds, H needs 1 bond. The angle should be about 104.5 degrees."
	ld.journal_entry = "H2O: Two bonds, one bent truth. VSEPR predicts, nature confirms."
	ld.domain = "molecular"
	ld.construction_mode = "bond_build"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.3, 5.0)
	ld.available_tools = ["atom_placer", "bond_rotator"]
	ld.scene_config = {"target_bond_angle": 104.5, "target_bond_length": 0.96}
	ld.elements = [
		{"symbol": "O", "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.5, 0.5)},
		{"symbol": "H", "wyckoff_label": "b", "wyckoff_multiplicity": 2, "position": Vector3(0.6, 0.35, 0.5)},
	]
	ld.goals = [
		{"type": "bond_build", "description": "Build 2 O-H bonds", "required_bonds": 2, "bond_pairs": [["O", "H"]]},
		{"type": "geometry_check", "description": "O-H bond length = 0.96Å", "target_distance": 0.96, "distance_tolerance": 0.05, "check_pair": ["O", "H"]},
		{"type": "geometry_check", "description": "H-O-H angle = 104.5°", "target_angle": 104.5, "angle_tolerance": 1.5},
		{"type": "conservation_check", "description": "Molecular valence conservation", "max_deviation": 0.1},
		{"type": "verification", "description": "Verify VSEPR molecular geometry", "required_layer": 2},
	]
	return ld


func _create_ch1_l4_the_matrix() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 1
	ld.level = 4
	ld.title = "The Matrix"
	ld.description = "Fill a perovskite structure and watch the conservation matrix. Every atom you place changes the matrix - keep it green."
	ld.space_group_number = 221
	ld.space_group_symbol = "Pm-3m"
	ld.lattice_parameters = Vector3(3.91, 3.91, 3.91)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 5
	ld.hint = "Perovskite ABO3: A at corner, B at body center, O at face centers. The matrix tracks charge and mass balance."
	ld.journal_entry = "Perovskite: Named after a count. The matrix watches. Conservation is the law."
	ld.domain = "crystal"
	ld.construction_mode = "wyckoff_fill"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.5, 8.0)
	ld.available_tools = ["element_block", "wyckoff_snap"]
	ld.scene_config = {"tolerance_factor": 1.002, "r_A": 1.44, "r_B": 0.605, "r_O": 1.40}
	ld.elements = [
		{"symbol": "Sr", "wyckoff_label": "a", "wyckoff_multiplicity": 1, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "Ti", "wyckoff_label": "b", "wyckoff_multiplicity": 1, "position": Vector3(0.5, 0.5, 0.5)},
		{"symbol": "O",  "wyckoff_label": "c", "wyckoff_multiplicity": 3, "position": Vector3(0.5, 0.5, 0.0)},
	]
	ld.goals = [
		{"type": "wyckoff_fill", "description": "Place Sr at 1a (corner)", "element": "Sr", "wyckoff": "a", "required_count": 1},
		{"type": "wyckoff_fill", "description": "Place Ti at 1b (body center)", "element": "Ti", "wyckoff": "b", "required_count": 1},
		{"type": "wyckoff_fill", "description": "Place O at 3c (face centers)", "element": "O", "wyckoff": "c", "required_count": 3},
		{"type": "conservation_check", "description": "Conservation matrix must stay healthy", "max_deviation": 0.1},
		{"type": "verification", "description": "Verify perovskite structure", "required_layer": 0},
	]
	return ld


func _create_ch1_l6_boss_blind_build() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 1
	ld.level = 6
	ld.title = "Boss: Blind Build"
	ld.description = "Build NaCl in the fog. You can't see the Wyckoff markers - use the conservation matrix as your guide."
	ld.space_group_number = 225
	ld.space_group_symbol = "Fm-3m"
	ld.lattice_parameters = Vector3(5.64, 5.64, 5.64)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 6
	ld.hint = "The matrix tells you what's missing. If charge is off, you placed the wrong element. Trust the matrix, not your eyes."
	ld.journal_entry = "Blind build: The fog hides everything. The matrix sees through it. Conservation is your only compass."
	ld.domain = "crystal"
	ld.construction_mode = "wyckoff_fill"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.5, 10.0)
	ld.available_tools = ["element_block", "wyckoff_snap", "bond_build"]
	ld.fog_zones = [
		{"position": Vector3(0.5, 0.5, 0.5), "radius": 4.0, "fog_type": "semi_decidable", "label": "Blind build fog"},
	]
	ld.elements = [
		{"symbol": "Na", "wyckoff_label": "a", "wyckoff_multiplicity": 4, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "Cl", "wyckoff_label": "b", "wyckoff_multiplicity": 4, "position": Vector3(0.5, 0.5, 0.5)},
	]
	ld.goals = [
		{"type": "wyckoff_fill", "description": "Place Na at 4a positions", "element": "Na", "wyckoff": "a", "required_count": 4},
		{"type": "wyckoff_fill", "description": "Place Cl at 4b positions", "element": "Cl", "wyckoff": "b", "required_count": 4},
		{"type": "conservation_check", "description": "Conservation matrix healthy through the fog", "max_deviation": 0.1},
		{"type": "verification", "description": "Complete blind build verification", "required_layer": 0},
	]
	return ld


func _create_ch2_l4_into_the_fog() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 2
	ld.level = 4
	ld.title = "Into the Fog"
	ld.description = "Assemble a structure where parts are hidden in fog. Dispel fog by spending cores, or reason through it."
	ld.space_group_number = 62
	ld.space_group_symbol = "Pnma"
	ld.lattice_parameters = Vector3(10.33, 6.01, 4.69)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 7
	ld.hint = "Fog costs cores to clear. Try to deduce what's hidden before spending. The matrix gives clues."
	ld.journal_entry = "Into the fog: What you can't see, you must reason. Cores buy sight, but logic is free."
	ld.domain = "molecular"
	ld.construction_mode = "assembly"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.5, 10.0)
	ld.available_tools = ["element_block", "wyckoff_snap", "bond_tool", "interface_builder", "strain_tool", "channel_inspector", "molecule_builder"]
	ld.fog_zones = [
		{"position": Vector3(0.5, 0.5, 0.5), "radius": 3.0, "fog_type": "semi_decidable", "label": "Hidden structure"},
	]
	ld.elements = [
		{"symbol": "Li", "wyckoff_label": "c", "wyckoff_multiplicity": 4, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "Fe", "wyckoff_label": "c", "wyckoff_multiplicity": 4, "position": Vector3(0.28, 0.25, 0.97)},
		{"symbol": "P",  "wyckoff_label": "c", "wyckoff_multiplicity": 4, "position": Vector3(0.09, 0.25, 0.42)},
		{"symbol": "O",  "wyckoff_label": "c", "wyckoff_multiplicity": 12, "position": Vector3(0.09, 0.25, 0.73)},
	]
	ld.goals = [
		{"type": "element_count", "description": "Place at least 4 Li atoms", "symbol": "Li", "required_count": 4},
		{"type": "fog_dispel", "description": "Dispel at least 1 fog zone", "count": 1},
		{"type": "bond_count", "description": "Build at least 4 bonds", "required_bonds": 4},
		{"type": "verification", "description": "Verify the fog structure", "required_layer": 1},
	]
	return ld


func _create_ch2_l5_no_sodium_allowed() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 2
	ld.level = 5
	ld.title = "No Sodium Allowed"
	ld.description = "Build NaCl but the element_block tool is forbidden. You must use substitute and other tools instead."
	ld.space_group_number = 225
	ld.space_group_symbol = "Fm-3m"
	ld.lattice_parameters = Vector3(5.64, 5.64, 5.64)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 5
	ld.hint = "When your favorite tool is banned, find another way. Substitution and bond tools can achieve the same result."
	ld.journal_entry = "Constraint breeds creativity. When the obvious path is blocked, ingenuity emerges."
	ld.domain = "crystal"
	ld.construction_mode = "wyckoff_fill"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.5, 10.0)
	ld.available_tools = ["element_block", "wyckoff_snap", "bond_tool"]
	ld.constraints = {"forbidden_tools": ["element_block"]}
	ld.elements = [
		{"symbol": "Na", "wyckoff_label": "a", "wyckoff_multiplicity": 4, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "Cl", "wyckoff_label": "b", "wyckoff_multiplicity": 4, "position": Vector3(0.5, 0.5, 0.5)},
	]
	ld.goals = [
		{"type": "wyckoff_fill", "description": "Place Na at 4a positions", "element": "Na", "wyckoff": "a", "required_count": 4},
		{"type": "wyckoff_fill", "description": "Place Cl at 4b positions", "element": "Cl", "wyckoff": "b", "required_count": 4},
		{"type": "conservation_check", "description": "Conservation matrix healthy without element_block", "max_deviation": 0.1},
		{"type": "verification", "description": "Verify constrained build", "required_layer": 0},
	]
	return ld


func _create_ch2_l7_resonance_dance() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 2
	ld.level = 7
	ld.title = "Resonance Dance"
	ld.description = "Keep the conservation matrix in resonance for 10 seconds. Any deviation breaks the dance."
	ld.space_group_number = 225
	ld.space_group_symbol = "Fm-3m"
	ld.lattice_parameters = Vector3(5.64, 5.64, 5.64)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 8
	ld.hint = "Resonance means the matrix is perfectly balanced. Place atoms carefully and don't disturb the balance."
	ld.journal_entry = "Resonance: The matrix hums when everything is perfectly balanced. Hold it. Dance with it."
	ld.domain = "crystal"
	ld.construction_mode = "wyckoff_fill"
	ld.scale_label = "Å"
	ld.scale_range = Vector2(0.5, 10.0)
	ld.available_tools = ["element_block", "wyckoff_snap", "bond_build", "tune_matrix"]
	ld.elements = [
		{"symbol": "Na", "wyckoff_label": "a", "wyckoff_multiplicity": 4, "position": Vector3(0.0, 0.0, 0.0)},
		{"symbol": "Cl", "wyckoff_label": "b", "wyckoff_multiplicity": 4, "position": Vector3(0.5, 0.5, 0.5)},
	]
	ld.goals = [
		{"type": "wyckoff_fill", "description": "Place Na at 4a positions", "element": "Na", "wyckoff": "a", "required_count": 4},
		{"type": "fuzzy_check", "description": "Maintain resonance for 10 seconds", "metric": "resonance_duration", "operator": ">=", "threshold": 10.0},
		{"type": "verification", "description": "Verify resonance stability", "required_layer": 1},
	]
	return ld


func _create_ch5_l3_breeding() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 5
	ld.level = 3
	ld.title = "Breeding"
	ld.description = "Evolve a CA pattern, save good seeds, load them back and evolve further. Breed better patterns through selection."
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(10.0, 10.0, 10.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 20
	ld.hint = "Save seeds when you see interesting patterns. Load them and evolve more. Selection + variation = breeding."
	ld.journal_entry = "Breeding: Save the good, discard the bad. Evolution is just selection with memory."
	ld.domain = "topology"
	ld.construction_mode = "cellular_automaton"
	ld.scale_label = "nm"
	ld.scale_range = Vector2(0.5, 20.0)
	ld.available_tools = ["element_block", "cellular_step", "ca_seed_save", "ca_seed_load"]
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
		{"type": "ca_pattern_reach", "description": "Evolve a non-extinct stable structure", "target_pattern": "stable", "min_steps": 10},
		{"type": "fuzzy_check", "description": "Save at least 3 seeds during evolution", "metric": "seed_count", "operator": ">=", "threshold": 3.0},
		{"type": "ca_step_count", "description": "Run at least 30 evolution steps", "min_steps": 30},
		{"type": "verification", "description": "Verify breeding evolution", "required_layer": 2},
	]
	return ld


func _create_ch5_l6_ecosystem() -> LevelData:
	var ld := LevelData.new()
	ld.chapter = 5
	ld.level = 6
	ld.title = "Ecosystem"
	ld.description = "Create a CA ecosystem where multiple species coexist. Export your best seeds and import others' to compete."
	ld.space_group_number = 1
	ld.space_group_symbol = "P1"
	ld.lattice_parameters = Vector3(12.0, 12.0, 12.0)
	ld.lattice_angles = Vector3(90.0, 90.0, 90.0)
	ld.reward_cores = 25
	ld.hint = "Multiple species means multiple stable patterns coexisting. Balance competition and cooperation."
	ld.journal_entry = "Ecosystem: Many species, one lattice. Coexistence is the ultimate emergence."
	ld.domain = "topology"
	ld.construction_mode = "cellular_automaton"
	ld.scale_label = "nm"
	ld.scale_range = Vector2(0.5, 20.0)
	ld.available_tools = ["element_block", "cellular_step", "ca_seed_save", "ca_seed_load", "ca_seed_export", "ca_seed_import"]
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
	ld.fog_zones = [
		{"position": Vector3(0.5, 0.5, 0.5), "radius": 5.0, "fog_type": "independent", "label": "Emergence zone"},
	]
	ld.goals = [
		{"type": "ca_pattern_reach", "description": "Evolve a multi-species ecosystem", "target_pattern": "stable", "min_steps": 15},
		{"type": "fuzzy_check", "description": "Save at least 5 seeds", "metric": "seed_count", "operator": ">=", "threshold": 5.0},
		{"type": "ca_step_count", "description": "Run at least 50 evolution steps", "min_steps": 50},
		{"type": "verification", "description": "Verify ecosystem emergence", "required_layer": 3},
	]
	return ld


func _spawn_preset_fog(fog_zones: Array[Dictionary]) -> void:
	# 根据关卡预置的迷雾配置生成迷雾区域
	for zone in fog_zones:
		var pos_raw: Variant = zone.get("position", Vector3.ZERO)
		var pos: Vector3 = Vector3.ZERO
		if pos_raw is Vector3:
			pos = pos_raw
		elif pos_raw is Array and pos_raw.size() >= 3:
			pos = Vector3(float(pos_raw[0]), float(pos_raw[1]), float(pos_raw[2]))
		var radius: float = float(zone.get("radius", 1.5))
		var fog_type_str: String = zone.get("fog_type", "semi_decidable")
		var label: String = zone.get("label", "")

		var fog_type: int = FogSystem.FogType.SEMI_DECIDABLE
		match fog_type_str:
			"semi_decidable":
				fog_type = FogSystem.FogType.SEMI_DECIDABLE
			"undecidable":
				fog_type = FogSystem.FogType.UNDECIDABLE
			"independent":
				fog_type = FogSystem.FogType.INDEPENDENT

		FogSystem.create_fog(fog_type, pos, radius, {"label": label, "preset": true})
		GameLogger.info("LevelManager", "[关卡] 预置迷雾: %s (%s) at %s" % [label, fog_type_str, str(pos)])


# ===== 约束系统 =====

func _parse_constraints(constraints: Dictionary) -> void:
	# 从关卡约束字典解析出可执行的约束
	_time_limit = float(constraints.get("time_limit_seconds", 0))
	_move_limit = int(constraints.get("max_moves", 0))
	_part_limit = int(constraints.get("max_parts", 0))
	_no_warning_constraint = bool(constraints.get("no_warning_ever", false))
	_max_ca_steps = int(constraints.get("max_steps", 0))
	_max_proof_depth = int(constraints.get("max_proof_depth", 0))
	_require_all_layers = bool(constraints.get("all_verification_layers", false))
	_forbidden_tools.clear()
	var ft: Array = constraints.get("forbidden_tools", [])
	for tool in ft:
		_forbidden_tools.append(String(tool))
	_instability_accumulator = 0.0
	_instability_modifier = 1.0

	if _time_limit > 0:
		GameLogger.info("LevelManager", "[关卡] 约束: %ds时间限制" % int(_time_limit))
	if _move_limit > 0:
		GameLogger.info("LevelManager", "[关卡] 约束: %d步操作限制" % _move_limit)
	if _part_limit > 0:
		GameLogger.info("LevelManager", "[关卡] 约束: %d部件限制" % _part_limit)
	if _no_warning_constraint:
		GameLogger.info("LevelManager", "[关卡] 约束: 零警告模式")
	if _max_ca_steps > 0:
		GameLogger.info("LevelManager", "[关卡] 约束: CA最多%d步" % _max_ca_steps)
	if not _forbidden_tools.is_empty():
		GameLogger.info("LevelManager", "[关卡] 约束: 禁用工具 %s" % str(_forbidden_tools))
	if _max_proof_depth > 0:
		GameLogger.info("LevelManager", "[关卡] 约束: 证明深度≤%d" % _max_proof_depth)
	if _require_all_layers:
		GameLogger.info("LevelManager", "[关卡] 约束: 需通过所有验证层")


func _check_constraints() -> void:
	if _level_completed or _level_failed:
		return
	if current_level_data.is_empty():
		return

	# 时间限制检查
	if _time_limit > 0:
		var elapsed := (Time.get_ticks_msec() / 1000.0) - _level_start_time
		constraint_updated.emit("time", elapsed, _time_limit)
		if elapsed >= _time_limit:
			_fail_level("时间耗尽! %ds限制已超时" % int(_time_limit))
			return

	# 操作数限制检查
	if _move_limit > 0:
		constraint_updated.emit("moves", float(move_count), float(_move_limit))
		if move_count >= _move_limit:
			# 检查是否所有目标已完成，否则失败
			var all_done := true
			for gs in goal_states:
				if gs != GoalState.COMPLETED:
					all_done = false
					break
			if not all_done:
				_fail_level("操作次数耗尽! %d步限制已用完" % _move_limit)
				return

	# 部件数限制检查 (max_parts 限定原子数，键不计入：键是原子间关系而非独立部件)
	if _part_limit > 0:
		var total_parts := _count_total_atoms()
		constraint_updated.emit("parts", float(total_parts), float(_part_limit))
		if total_parts > _part_limit:
			_fail_level("部件数超限! %d>%d" % [total_parts, _part_limit])
			return

	# 守恒洁癖: 检查是否有任何警告
	if _no_warning_constraint:
		var dev_summary: Dictionary = ConservationEngine.get_deviation_summary()
		for key in dev_summary:
			if dev_summary[key]["deviation"] > 0.05:
				_fail_level("守恒洁癖失败: %s偏离%.3f" % [key, dev_summary[key]["deviation"]])
				return

	# 共振生存追踪：每秒更新共振持续时间
	var resonance_now: bool = ConservationEngine.is_resonance_active()
	if resonance_now:
		_resonance_duration += 1.0  # _check_constraints 每秒调用一次
	_resonance_was_active = resonance_now

	# 结构稳定性累积: 高偏离会逐渐累积不稳定性
	var dev_summary2: Dictionary = ConservationEngine.get_deviation_summary()
	var max_dev := 0.0
	for key in dev_summary2:
		max_dev = maxf(max_dev, dev_summary2[key]["deviation"])
	if max_dev > 0.3:
		_instability_accumulator += (max_dev - 0.3) * 2.0 * _instability_modifier
		if _instability_accumulator >= _max_instability:
			_fail_level("结构不稳定! 守恒偏离持续过高，结构瓦解")
			return
	else:
		# 低偏离时缓慢恢复稳定性
		_instability_accumulator = maxf(_instability_accumulator - 0.5, 0.0)

	# CA步数上限检查
	if _max_ca_steps > 0 and _ca_step_count > _max_ca_steps:
		_fail_level("CA演化步数超限! %d>%d" % [_ca_step_count, _max_ca_steps])
		return

	# 证明树深度上限检查
	if _max_proof_depth > 0 and ProofTree != null:
		var current_depth: int = ProofTree.get_tree_depth()
		if current_depth > _max_proof_depth:
			_fail_level("证明树深度超限! %d>%d" % [current_depth, _max_proof_depth])
			return


func _fail_level(reason: String) -> void:
	if _level_failed or _level_completed:
		return
	_level_failed = true
	_metrics["fail_reason"] = reason
	GameLogger.info("LevelManager", "[关卡] 失败: %s" % reason)
	level_failed.emit(reason)


func is_tool_forbidden(tool_name: String) -> bool:
	# 检查某工具是否被关卡约束禁用，供 construction_canvas 调用
	return _forbidden_tools.has(tool_name)


func get_forbidden_tools() -> Array[String]:
	return _forbidden_tools.duplicate()


# 主动测试结构稳定性 - 玩家点击"测试"按钮触发
func test_structure() -> Dictionary:
	# Besiege模式: 有 sim 类目标时，启动物理模拟而非静态检查
	var sim_mode := ""
	var target_temp := 0.0
	var has_sim_goal := false
	for g in goals:
		var gt: String = g.get("type", "")
		if gt == "survives_simulation":
			has_sim_goal = true
			sim_mode = g.get("sim_mode", "strain")
			target_temp = float(g.get("target_temp", 0.0))
		elif gt == "survives_phase_transition":
			has_sim_goal = true
			sim_mode = "thermal"
			target_temp = float(g.get("target_temp", 500.0))
		elif gt == "magnetic_order_check":
			has_sim_goal = true
			sim_mode = "magnetic"
			target_temp = float(g.get("target_temp", 0.0))
		elif gt == "catalyst_efficiency_check":
			has_sim_goal = true
			sim_mode = "catalyst"
		elif gt == "resonance_check":
			has_sim_goal = true
			sim_mode = "resonance"
		elif gt in ["stability_target", "energy_target", "strain_target"]:
			has_sim_goal = true
			sim_mode = g.get("sim_mode", "strain")
			target_temp = float(g.get("target_temp", 0.0))
	if has_sim_goal:
		var canvas = _get_construction_canvas()
		if canvas != null and canvas.has_method("start_simulation"):
			canvas.start_simulation(sim_mode, target_temp)
			structure_tested.emit(true, ["物理模拟运行中..."])
			return {"stable": true, "issues": [], "max_deviation": 0.0, "simulating": true}

	# 常规模式: 静态守恒检查
	var issues: Array[String] = []
	var stable := true

	var dev_summary: Dictionary = ConservationEngine.get_deviation_summary()
	var max_dev := 0.0
	var worst_key := ""
	for key in dev_summary:
		var dev: float = dev_summary[key]["deviation"]
		if dev > max_dev:
			max_dev = dev
			worst_key = key

	if max_dev > 0.2:
		stable = false
		issues.append("守恒偏离过高: %s = %.3f" % [worst_key, max_dev])
	elif max_dev > 0.1:
		issues.append("守恒偏离警告: %s = %.3f" % [worst_key, max_dev])

	# 检查原子放置完整性
	var total_atoms := _count_total_atoms()
	if total_atoms == 0:
		stable = false
		issues.append("未放置任何原子")
	elif total_atoms < goals.size():
		issues.append("原子数偏少，结构可能不完整")

	# 检查目标完成情况
	var pending_goals := 0
	for gs in goal_states:
		if gs != GoalState.COMPLETED:
			pending_goals += 1
	if pending_goals > 0:
		issues.append("还有 %d 个目标未完成" % pending_goals)

	structure_tested.emit(stable, issues)
	GameLogger.info("LevelManager", "[关卡] 结构测试: %s, 问题: %s" % ["稳定" if stable else "不稳定", str(issues)])

	# 如果结构基本稳定，验证所有验证类目标
	if stable or max_dev < 0.3:
		verify_goals()

	return {"stable": stable, "issues": issues, "max_deviation": max_dev}


func get_constraint_status() -> Dictionary:
	# 给UI显示约束状态
	var elapsed := (Time.get_ticks_msec() / 1000.0) - _level_start_time
	return {
		"time_limit": _time_limit,
		"time_elapsed": elapsed,
		"move_limit": _move_limit,
		"move_count": move_count,
		"part_limit": _part_limit,
		"part_count": _count_total_atoms() + _bonds_built.size(),
		"no_warning": _no_warning_constraint,
		"instability": _instability_accumulator,
		"max_instability": _max_instability,
	}


# construction_canvas放置原子时调用这个
func register_atom_placement(element: String, wyckoff_label: String) -> void:
	if element == "" or wyckoff_label == "":
		push_warning("[关卡] register_atom_placement: 忽略空参数 element=%s wyckoff=%s" % [element, wyckoff_label])
		return
	if not _atoms_placed.has(wyckoff_label):
		_atoms_placed[wyckoff_label] = {}
	if not _atoms_placed[wyckoff_label].has(element):
		_atoms_placed[wyckoff_label][element] = 0
	_atoms_placed[wyckoff_label][element] += 1
	placement_count += 1
	move_count += 1
	_check_goals()


# construction_canvas删除原子时调用这个
func unregister_atom_placement(element: String, wyckoff_label: String) -> void:
	if _atoms_placed.has(wyckoff_label) and _atoms_placed[wyckoff_label].has(element):
		_atoms_placed[wyckoff_label][element] -= 1
		if _atoms_placed[wyckoff_label][element] <= 0:
			_atoms_placed[wyckoff_label].erase(element)
	deletion_count += 1
	move_count += 1
	_check_goals()


# 成键时调用
func register_bond(element_a: String, element_b: String) -> void:
	if element_a == "" or element_b == "":
		push_warning("[关卡] register_bond: 忽略空参数 a=%s b=%s" % [element_a, element_b])
		return
	_bonds_built.append({"a": element_a, "b": element_b})
	_check_goals()


# 组装部件时调用
func register_assembly(component: String) -> void:
	if not _assembled_parts.has(component):
		_assembled_parts[component] = 0
	_assembled_parts[component] += 1
	_check_goals()


# 路径节点添加时调用
func register_path_node(node_data: Dictionary) -> void:
	if node_data == null or not node_data is Dictionary:
		return
	if not node_data.has("element") or not node_data.has("position"):
		push_warning("[关卡] register_path_node: 节点数据缺少 element 或 position")
		return
	_path_nodes.append(node_data)
	_check_goals()


# CA 演化步进时调用，更新 CA 状态并检查目标
func register_ca_step(stats: Dictionary) -> void:
	_ca_step_count = int(stats.get("step", 0))
	_ca_alive_count = int(stats.get("alive", 0))
	_ca_density = float(stats.get("density", 0.0))
	_ca_phase = String(stats.get("phase", "unknown"))
	# 记录检测到的模式
	var pattern: String = String(stats.get("pattern", ""))
	if not pattern.is_empty():
		_ca_patterns_detected[pattern] = _ca_patterns_detected.get(pattern, 0) + 1
	# 追踪守恒偏离
	var dev_summary: Dictionary = ConservationEngine.get_deviation_summary()
	for key in dev_summary:
		_ca_max_deviation = maxf(_ca_max_deviation, dev_summary[key]["deviation"])
	_check_goals()


func register_ca_seed_save() -> void:
	# 玩家保存CA种子时调用，用于育种关卡目标计数
	_ca_seeds_saved += 1
	_check_goals()


# Called by ConstructionCanvas when physics simulation settles
func on_simulation_settled() -> void:
	_check_goals()


# Helper to find the ConstructionCanvas node in the scene tree
func _get_construction_canvas() -> Node:
	var tree = get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("construction_canvas")


func _check_goals() -> void:
	# 主动检查目标: 放置类目标自动完成，验证类目标只更新进度不自动完成
	# 验证类目标(conservation/geometry/transport等)需要玩家主动点击"测试结构"
	var all_completed := true
	for i in range(goals.size()):
		var goal: Dictionary = goals[i]
		# Ch5 schema nests fields in "params" — unwrap for uniform handling
		if goal.has("params") and goal["params"] is Dictionary:
			var _uw: Dictionary = goal["params"].duplicate()
			_uw["type"] = goals[i]["type"]
			goal = _uw
		var progress := 0.0
		var completed := false
		var requires_verification := _goal_requires_verification(goal["type"])

		match goal["type"]:
			"wyckoff_fill":
				var wyckoff_label: String = _normalize_wyckoff(goal.get("wyckoff", ""))
				# 兼容多种 schema: element / symbol / targets[0]
				var element_sym: String = goal.get("element", goal.get("symbol", ""))
				if element_sym == "":
					var targets_arr: Array = goal.get("targets", [])
					if targets_arr.size() > 0:
						element_sym = str(targets_arr[0])
				var required: int = int(goal.get("required_count", goal.get("count", 1)))
				var placed: int = 0
				if wyckoff_label != "":
					# 指定了 Wyckoff 位置，精确匹配
					placed = _atoms_placed.get(wyckoff_label, {}).get(element_sym, 0)
				# Fallback: 精确匹配为0时按元素跨所有位置计数
				# (fallback markers use element symbols as labels, not Wyckoff letters)
				if placed == 0 and element_sym != "":
					for wkey in _atoms_placed:
						placed += _atoms_placed[wkey].get(element_sym, 0)
				progress = minf(float(placed) / float(maxf(required, 1)), 1.0)
				completed = placed >= required

			"conservation_check":
				var dev_summary: Dictionary = ConservationEngine.get_deviation_summary()
				var max_dev := 0.0
				for key in dev_summary:
					max_dev = maxf(max_dev, dev_summary[key].get("deviation", 0.0))
				var max_deviation_thresh: float = float(goal.get("max_deviation", goal.get("max_dev", 0.5)))
				progress = maxf(1.0 - max_dev / maxf(max_deviation_thresh, 0.001), 0.0)
				completed = max_dev <= max_deviation_thresh

			"verification":
				progress = 0.5 if goal_states[i] == GoalState.IN_PROGRESS else 0.0
				completed = goal_states[i] == GoalState.COMPLETED

			"symmetry_check":
				var _sym_params: Dictionary = goal.get("params", {})
				var source_sg: int = int(goal.get("source_sg", _sym_params.get("source_sg", 0)))
				var target_sg: int = int(goal.get("target_sg", _sym_params.get("target_sg", 0)))
				var required_count_sym: int = int(goal.get("required_count", _sym_params.get("required_count", 1)))
				var total_atoms_sym: int = _count_total_atoms()
				if total_atoms_sym == 0:
					progress = 0.0
					completed = false
				else:
					var atom_ratio: float = minf(float(total_atoms_sym) / float(maxf(required_count_sym, 1)), 1.0)
					var sym_score: float = _evaluate_symmetry_lowering(source_sg, target_sg)
					progress = atom_ratio * 0.3 + sym_score * 0.7
					completed = total_atoms_sym >= required_count_sym and sym_score >= 0.8

			"bond_check":
				var element_a: String = goal.get("element_a", "")
				var element_b: String = goal.get("element_b", "")
				var required_count: int = goal.get("required_count", 0)
				var matching_bonds: int = 0
				for bond in _bonds_built:
					var a_elem = bond.get("a", "")
					var b_elem = bond.get("b", "")
					if (_bond_element_match(a_elem, element_a) and _bond_element_match(b_elem, element_b)) or \
				   (_bond_element_match(a_elem, element_b) and _bond_element_match(b_elem, element_a)):
						matching_bonds += 1
				progress = minf(float(matching_bonds) / float(maxf(required_count, 1)), 1.0)
				completed = matching_bonds >= required_count

			"bond_build":
				var required_bonds: int = int(goal.get("required_bonds", goal.get("count", 0)))
				var bond_pairs: Array = goal.get("bond_pairs", [])
				# Ch4 schema: targets array + count instead of bond_pairs + required_bonds
				if bond_pairs.is_empty():
					var _bp_targets: Array = goal.get("targets", [])
					if _bp_targets.size() >= 2:
						# Handle both element pairs ["C","O"] and bond-type strings ["C-O","H-O"]
						for t in _bp_targets:
							var ts: String = str(t)
							if "-" in ts:
								var parts: PackedStringArray = ts.split("-")
								if parts.size() >= 2:
									bond_pairs.append([parts[0], parts[1]])
							else:
								if bond_pairs.is_empty():
									bond_pairs.append([ts, ts])  # same-element placeholder
								else:
									bond_pairs[0][1] = ts  # second element of first pair
					elif _bp_targets.size() == 1 and required_bonds == 0:
						# Special case: single non-element target like "validate_molecules" — any bonds = pass
						required_bonds = 1
						bond_pairs = []  # empty = count all bonds
				var matching_count := 0
				for bond in _bonds_built:
					for pair in bond_pairs:
						if pair.size() >= 2:
							if pair[1] == "":
								# Wildcard: any bond with element matching pair[0]
								if _bond_element_match(bond["a"], pair[0]) or _bond_element_match(bond["b"], pair[0]):
									matching_count += 1
									break
							elif (_bond_element_match(bond["a"], pair[0]) and _bond_element_match(bond["b"], pair[1])) or \
						   (_bond_element_match(bond["a"], pair[1]) and _bond_element_match(bond["b"], pair[0])):
								matching_count += 1
								break
				# If no specific pairs but bonds exist, count all
				if bond_pairs.is_empty() and _bonds_built.size() > 0:
					matching_count = _bonds_built.size()
				progress = minf(float(matching_count) / float(maxf(required_bonds, 1)), 1.0)
				completed = matching_count >= required_bonds

			"geometry_check":
				var tol: float = float(goal.get("tolerance", 0.1))
				var atoms_data: Array = _get_atom_positions()
				var dev_summary: Dictionary = ConservationEngine.get_deviation_summary()
				var cons_max_dev: float = 0.0
				for key in dev_summary:
					cons_max_dev = maxf(cons_max_dev, dev_summary[key]["deviation"])

				if goal.has("target_angle"):
					var target_angle: float = float(goal["target_angle"])
					var angle_tol: float = float(goal.get("angle_tolerance", tol))
					if atoms_data.is_empty():
						progress = maxf(1.0 - cons_max_dev, 0.0)
						completed = false
					else:
						var best_angle: float = _find_closest_bond_angle(atoms_data, target_angle)
						if best_angle < 0.0:
							progress = 0.0
							completed = false
						else:
							var angle_diff: float = absf(best_angle - target_angle)
							progress = maxf(1.0 - angle_diff / maxf(angle_tol, 0.001), 0.0)
							completed = angle_diff <= angle_tol

				elif goal.has("target_distance") or goal.has("target_length"):
					var target_dist: float = float(goal.get("target_distance", goal.get("target_length", 0.0)))
					var dist_tol: float = float(goal.get("distance_tolerance", tol))
					var check_pair: Array = goal.get("check_pair", [])
					if atoms_data.is_empty():
						progress = maxf(1.0 - cons_max_dev, 0.0)
						completed = false
					else:
						var best_dist: float = _find_closest_bond_length(atoms_data, target_dist, check_pair)
						if best_dist < 0.0:
							progress = 0.0
							completed = false
						else:
							var dist_diff: float = absf(best_dist - target_dist)
							progress = maxf(1.0 - dist_diff / maxf(dist_tol, 0.001), 0.0)
							completed = dist_diff <= dist_tol

				elif goal.has("target_lattice"):
					var target_lat: float = float(goal["target_lattice"])
					var lat_tol: float = float(goal.get("lattice_tolerance", tol))
					var lattice: Vector3 = current_level_data.get("lattice_parameters", Vector3.ZERO)
					var actual_lat: float = lattice.x
					var lat_diff: float = absf(actual_lat - target_lat)
					progress = maxf(1.0 - lat_diff / maxf(lat_tol, 0.001), 0.0)
					completed = lat_diff <= lat_tol and _has_any_atoms()

				elif goal.has("target_ca_ratio"):
					var target_ca: float = float(goal["target_ca_ratio"])
					var ca_tol: float = float(goal.get("ca_tolerance", tol))
					var min_ca: float = float(goal.get("min_ca", target_ca))
					var lattice_ca: Vector3 = current_level_data.get("lattice_parameters", Vector3.ONE)
					var actual_ca: float = lattice_ca.z / maxf(lattice_ca.x, 0.001)
					var ca_diff: float = absf(actual_ca - target_ca)
					progress = maxf(1.0 - ca_diff / maxf(ca_tol, 0.001), 0.0)
					completed = actual_ca >= min_ca and _has_any_atoms()

				elif goal.has("target_value") and goal.get("check_type", "") == "tolerance_factor":
					var target_val: float = float(goal["target_value"])
					var val_tol: float = float(goal.get("value_tolerance", tol))
					var scene_cfg: Dictionary = current_level_data.get("scene_config", {})
					var r_a: float = float(scene_cfg.get("r_A", 0.0))
					var r_b: float = float(scene_cfg.get("r_B", 0.0))
					var r_o: float = float(scene_cfg.get("r_O", 0.0))
					if r_a > 0.0 and r_b > 0.0 and r_o > 0.0:
						var t_factor: float = (r_a + r_o) / (sqrt(2.0) * (r_b + r_o))
						var val_diff: float = absf(t_factor - target_val)
						progress = maxf(1.0 - val_diff / maxf(val_tol, 0.001), 0.0)
						completed = val_diff <= val_tol and _has_any_atoms()
					else:
						progress = maxf(1.0 - cons_max_dev, 0.0)
						completed = false

				elif goal.has("target_tolerance"):
					var target_tol_val: float = float(goal["target_tolerance"])
					var scene_cfg_tol: Dictionary = current_level_data.get("scene_config", {})
					var r_a_tol: float = float(scene_cfg_tol.get("r_A", 0.0))
					var r_b_tol: float = float(scene_cfg_tol.get("r_B", 0.0))
					var r_o_tol: float = float(scene_cfg_tol.get("r_O", 0.0))
					if r_a_tol > 0.0 and r_b_tol > 0.0 and r_o_tol > 0.0:
						var t_factor_tol: float = (r_a_tol + r_o_tol) / (sqrt(2.0) * (r_b_tol + r_o_tol))
						var tol_diff: float = absf(t_factor_tol - target_tol_val)
						progress = maxf(1.0 - tol_diff / maxf(tol, 0.001), 0.0)
						completed = tol_diff <= tol and _has_any_atoms()
					else:
						progress = maxf(1.0 - cons_max_dev, 0.0)
						completed = false

				elif goal.has("max_deviation"):
					var max_allowed: float = float(goal.get("max_deviation", 0.3))
					progress = maxf(1.0 - cons_max_dev / maxf(max_allowed, 0.001), 0.0)
					completed = cons_max_dev < max_allowed

				elif goal.has("min_distance"):
					progress = maxf(1.0 - cons_max_dev, 0.0)
					completed = cons_max_dev < 0.3

				elif goal.has("energy_downhill"):
					# 反应路径能量下降：检查路径节点数 + 守恒健康
					var min_path: int = int(goal.get("min_steps", 2))
					var path_ok: int = _path_nodes.size()
					progress = minf(float(path_ok) / float(maxi(min_path, 1)), 1.0) * 0.6 + maxf(1.0 - cons_max_dev, 0.0) * 0.4
					completed = path_ok >= min_path and cons_max_dev < 0.2

				elif goal.has("has_channel"):
					# 通道存在：检查路径节点连通性
					var channel_min: int = int(goal.get("min_length", 3))
					var connected: int = _count_connected_path_nodes(goal.get("max_segment_length", 1.5))
					progress = minf(float(connected) / float(maxi(channel_min, 1)), 1.0) * 0.7 + maxf(1.0 - cons_max_dev, 0.0) * 0.3
					completed = connected >= channel_min and cons_max_dev < 0.2

				elif goal.has("strain_field"):
					# 应变场：检查原子放置 + 守恒健康
					var strain_atoms: int = _count_total_atoms()
					var strain_min: int = int(goal.get("min_atoms", 2))
					progress = minf(float(strain_atoms) / float(maxi(strain_min, 1)), 1.0) * 0.5 + maxf(1.0 - cons_max_dev, 0.0) * 0.5
					completed = strain_atoms >= strain_min and cons_max_dev < 0.2

				elif goal.has("reynolds_number") or goal.has("velocity_profile"):
					# 流体力学：检查路径节点（流线）+ 守恒健康
					var flow_min: int = int(goal.get("min_flow_nodes", 3))
					var flow_nodes: int = _path_nodes.size()
					progress = minf(float(flow_nodes) / float(maxi(flow_min, 1)), 1.0) * 0.6 + maxf(1.0 - cons_max_dev, 0.0) * 0.4
					completed = flow_nodes >= flow_min and cons_max_dev < 0.2

				elif goal.has("max_distance"):
					# 最大原子间距约束：检查所有原子对的最大距离
					var max_dist_limit: float = float(goal["max_distance"])
					if atoms_data.size() < 2:
						progress = 0.0
						completed = false
					else:
						var actual_max_dist: float = 0.0
						for ai in range(atoms_data.size()):
							for bi in range(ai + 1, atoms_data.size()):
								var d: float = atoms_data[ai]["position"].distance_to(atoms_data[bi]["position"])
								actual_max_dist = maxf(actual_max_dist, d)
						progress = clampf(1.0 - (actual_max_dist - max_dist_limit) / maxf(max_dist_limit, 0.001), 0.0, 1.0)
						completed = actual_max_dist <= max_dist_limit and cons_max_dev < 0.2

				elif goal.has("check_all_pairs"):
					# 检查所有原子对满足目标属性（复用 target_angle/target_distance 逻辑）
					if goal.has("target_angle"):
						var cap_target: float = float(goal["target_angle"])
						var cap_tol: float = float(goal.get("angle_tolerance", tol))
						var all_ok: bool = true
						var pair_count: int = 0
						for ai in range(atoms_data.size()):
							for bi in range(ai + 1, atoms_data.size()):
								pair_count += 1
								# 简化：用距离差作为代理
								var d: float = atoms_data[ai]["position"].distance_to(atoms_data[bi]["position"])
								if absf(d - cap_target) > cap_tol:
									all_ok = false
						progress = maxf(1.0 - cons_max_dev, 0.0) if pair_count == 0 else (1.0 if all_ok else 0.5)
						completed = all_ok and pair_count > 0 and cons_max_dev < 0.2
					elif goal.has("property") and goal.has("value"):
						# Property-value check (e.g. bandgap >= 1.5 eV) — proxy via atom count
						var prop_min: int = int(goal.get("min_atoms", 2))
						var prop_atoms: int = _count_total_atoms()
						progress = minf(float(prop_atoms) / float(maxi(prop_min, 1)), 1.0) * 0.6 + maxf(1.0 - cons_max_dev, 0.0) * 0.4
						completed = prop_atoms >= prop_min and cons_max_dev < 0.3
					elif goal.has("property"):
						# Bare property (e.g. "doping_in_superconducting_zone") — just need atoms placed
						progress = maxf(1.0 - cons_max_dev, 0.0)
						completed = _count_total_atoms() >= 2 and cons_max_dev < 0.3
					else:
						progress = maxf(1.0 - cons_max_dev, 0.0)
						completed = cons_max_dev < 0.2

			"transport_check":
				# 输运检查：守恒健康 + 路径节点存在（代表输运通道）
				var dev_summary: Dictionary = ConservationEngine.get_deviation_summary()
				var max_dev: float = 0.0
				for key in dev_summary:
					max_dev = maxf(max_dev, dev_summary[key]["deviation"])
				var transport_has_path: bool = _path_nodes.size() > 0 or _count_total_atoms() > 0
				progress = maxf(1.0 - max_dev, 0.0) * (0.7 if transport_has_path else 0.3)
				completed = max_dev < 0.15 and transport_has_path

			"interface_check":
				# 界面检查：守恒健康 + 多种元素存在（代表界面两侧不同相）
				var dev_summary: Dictionary = ConservationEngine.get_deviation_summary()
				var max_dev: float = 0.0
				for key in dev_summary:
					max_dev = maxf(max_dev, dev_summary[key]["deviation"])
				var max_mismatch: float = goal.get("max_mismatch", 0.2)
				var elem_types: int = 0
				for wyckoff_label in _atoms_placed:
					elem_types += _atoms_placed[wyckoff_label].size()
				var has_interface: bool = elem_types >= 2 or _count_total_atoms() > 0
				progress = maxf(1.0 - max_dev / max_mismatch, 0.0) * (0.7 if has_interface else 0.3)
				completed = max_dev < max_mismatch and has_interface

			"reaction_path":
				var reaction_steps: Array = goal.get("reaction_steps", goal.get("steps", []))
				var rp_result: Dictionary = _evaluate_reaction_path(reaction_steps)
				progress = rp_result["progress"]
				completed = rp_result["completed"]

			"assembly_check":
				# 兼容三种 schema: code用 component/required_parts, JSON用 targets/count, C5用 params嵌套
				var assem_goal: Dictionary = goal.get("params", goal)
				var component: String = assem_goal.get("component", assem_goal.get("target", ""))
				var required_parts = assem_goal.get("required_parts", assem_goal.get("count", assem_goal.get("min_cells", 1)))
				var placed_parts: int = 0
				var total_required: int = 0
				if required_parts is Dictionary:
					for part in required_parts:
						total_required += int(required_parts[part])
						placed_parts += _assembled_parts.get(part, 0)
				elif component != "":
					total_required = int(required_parts)
					placed_parts = _assembled_parts.get(component, 0)
				else:
					# JSON schema: targets 是数组
					var targets: Array = assem_goal.get("targets", [])
					total_required = int(required_parts)
					for t in targets:
						placed_parts += _assembled_parts.get(t, 0)
				# 如果没有匹配到任何组装部件，用原子总数作为 fallback
				if placed_parts == 0 and total_required > 0:
					placed_parts = _count_total_atoms()
				progress = minf(float(placed_parts) / float(maxf(total_required, 1)), 1.0)
				completed = placed_parts >= total_required

			"topology_check":
				var topology_type: String = goal.get("topology_type", "chain")
				var min_nodes: int = goal.get("min_nodes", 3)
				var topo_result: Dictionary = _evaluate_topology(topology_type, min_nodes)
				progress = topo_result["progress"]
				completed = topo_result["completed"]

			"mesh_build":
				var required_atoms: int = int(goal.get("required_atoms", goal.get("req_atoms", 0)))
				var total_atoms: int = 0
				for wyckoff_label in _atoms_placed:
					for elem in _atoms_placed[wyckoff_label]:
						total_atoms += _atoms_placed[wyckoff_label][elem]
				progress = minf(float(total_atoms) / float(maxf(required_atoms, 1)), 1.0)
				completed = total_atoms >= required_atoms

			"path_build":
				var pb_required: int = goal.get("path_nodes_required", 3)
				var pb_connected: int = _count_connected_path_nodes(goal.get("max_segment_length", 1.5))
				progress = minf(float(pb_connected) / float(maxf(pb_required, 1)), 1.0)
				completed = pb_connected >= pb_required

			"thermal_check":
				# 热学检查：守恒健康 + 足够原子（代表热容/热传导介质）
				var dev_summary: Dictionary = ConservationEngine.get_deviation_summary()
				var max_dev: float = 0.0
				for key in dev_summary:
					max_dev = maxf(max_dev, dev_summary[key]["deviation"])
				var thermal_has_mass: bool = _count_total_atoms() > 0
				progress = maxf(1.0 - max_dev * 2.0, 0.0) * (0.7 if thermal_has_mass else 0.3)
				completed = max_dev < 0.1 and thermal_has_mass

			"diffusion_check":
				# 兼容多种 JSON schema: required_steps / required_paths / req_paths / min_nodes
				var required_steps: int = int(goal.get("required_steps", goal.get("required_paths", goal.get("req_paths", goal.get("min_nodes", 5)))))
				var current_steps: int = _path_nodes.size()
				progress = minf(float(current_steps) / float(maxf(required_steps, 1)), 1.0)
				completed = current_steps >= required_steps

			"em_check":
				# 电磁检查：守恒健康 + 键存在（代表导电通路）
				var em_summary: Dictionary = ConservationEngine.get_deviation_summary()
				var em_max_dev: float = 0.0
				for key in em_summary:
					em_max_dev = maxf(em_max_dev, em_summary[key]["deviation"])
				var em_has_conductance: bool = _bonds_built.size() > 0 or _count_total_atoms() > 0
				progress = maxf(1.0 - em_max_dev, 0.0) * (0.7 if em_has_conductance else 0.3)
				completed = em_max_dev <= goal.get("max_deviation", 0.15) and em_has_conductance

			"ca_pattern_reach":
				# CA 达到特定模式: 检测振荡器/稳定态/滑翔机/特定密度
				# 兼容 "pattern" (JSON) 和 "target_pattern" (旧代码)
				var target_pattern: String = goal.get("pattern", goal.get("target_pattern", "stable"))
				var min_steps: int = goal.get("min_steps", 5)
				if _ca_step_count >= min_steps:
					match target_pattern:
						"stable":
							completed = _ca_phase == "stable"
							progress = 0.5 if _ca_phase != "extinct" else 0.0
						"oscillator":
							completed = _ca_patterns_detected.has("oscillator")
							progress = 0.5 if _ca_step_count >= min_steps else 0.0
						"glider":
							completed = _ca_patterns_detected.has("glider")
							progress = 0.5 if _ca_step_count >= min_steps else 0.0
						_:
							completed = _ca_phase != "extinct" and _ca_alive_count > 0
							progress = minf(float(_ca_step_count) / float(maxi(min_steps, 1)), 1.0)
				else:
					progress = minf(float(_ca_step_count) / float(maxi(min_steps, 1)), 0.8)

			"ca_conservation_maintain":
				# CA 演化过程中守恒矩阵保持健康
				# 检查当前偏离而非历史最大值，允许玩家从暂时偏离中恢复
				var ca_max_dev: float = float(goal.get("max_dev", goal.get("max_deviation", 0.2)))
				var ca_min_steps: int = goal.get("min_steps", 10)
				var ca_current_dev: float = 0.0
				var ca_dev_summary: Dictionary = ConservationEngine.get_deviation_summary()
				for ca_key in ca_dev_summary:
					ca_current_dev = maxf(ca_current_dev, ca_dev_summary[ca_key]["deviation"])
				if _ca_step_count >= ca_min_steps:
					completed = ca_current_dev <= ca_max_dev
					progress = maxf(1.0 - ca_current_dev / ca_max_dev, 0.0)
				else:
					progress = minf(float(_ca_step_count) / float(maxi(ca_min_steps, 1)), 0.8)

			"ca_phase_transition":
				# CA 发生相变 (如从混沌到有序)
				var target_phase: String = goal.get("target_phase", "stable")
				var ca_min_steps_pt: int = goal.get("min_steps", 8)
				if _ca_step_count >= ca_min_steps_pt:
					completed = _ca_phase == target_phase
					progress = 0.6 if _ca_phase != "extinct" else 0.0
				else:
					progress = minf(float(_ca_step_count) / float(maxi(ca_min_steps_pt, 1)), 0.7)

			"fuzzy_check":
				# 模糊目标：支持 density/energy/atom_count/bond_count/max_deviation 等条件
				# 允许多解，玩家可以用不同结构达成同一目标
				# 兼容三种 schema: metric/threshold (flat), property/threshold, field-name-as-metric
				var metric: String = goal.get("metric", goal.get("property", ""))
				var operator: String = goal.get("operator", goal.get("comparison", ">="))
				var threshold: float = float(goal.get("threshold", 0.0))
				# 当 metric 为空时，尝试从字段名推断 (如 seed_count: 2)
				if metric == "":
					for fk in goal.keys():
						if fk in ["atom_count", "bond_count", "density", "max_deviation",
								"element_diversity", "resonance_duration", "seed_count",
								"order_parameter"]:
							metric = fk
							threshold = float(goal[fk])
							break
				var current_val: float = _evaluate_fuzzy_metric(metric)
				match operator:
					">=": completed = current_val >= threshold
					"<=": completed = current_val <= threshold
					">": completed = current_val > threshold
					"<": completed = current_val < threshold
					"==": completed = absf(current_val - threshold) < 0.01
				# 进度按接近程度计算
				if threshold != 0.0:
					match operator:
						"<=", "<":
							# 越小越好：progress = 1 - current/threshold
							progress = clampf(1.0 - current_val / threshold, 0.0, 1.0)
						_:
							progress = clampf(current_val / threshold, 0.0, 1.0)
				else:
					progress = 1.0 if completed else 0.0

			"ca_step_count":
				# CA 演化步数达标
				var min_steps: int = int(goal.get("min_steps", 10))
				completed = _ca_step_count >= min_steps
				progress = minf(float(_ca_step_count) / float(maxi(min_steps, 1)), 1.0)

			"element_count":
				# 指定元素数量达标
				# JSON 用 "symbol" 字段，兼容旧字段 "element"
				var target_elem: String = goal.get("symbol", goal.get("element", ""))
				var required: int = int(goal.get("required_count", goal.get("count", 1)))
				var actual: int = 0
				# _atoms_placed 结构: {wyckoff_label: {element: count}}
				for wyckoff_data in _atoms_placed.values():
					if wyckoff_data is Dictionary and wyckoff_data.has(target_elem):
						actual += int(wyckoff_data[target_elem])
				completed = actual >= required
				progress = clampf(float(actual) / float(maxi(required, 1)), 0.0, 1.0)

			"survives_simulation":
				# Besiege模式: 模拟收敛后结构存活（原子数 >= min_atoms）
				var canvas = _get_construction_canvas()
				if canvas != null and canvas._sim_settled:
					var min_atoms: int = int(goal.get("min_atoms", 1))
					var actual_atoms: int = _count_total_atoms()
					completed = actual_atoms >= min_atoms
				else:
					completed = false
				progress = 1.0 if completed else 0.0

			"survives_phase_transition":
				# 热模拟: 升温后结构仍保留足够原子（相变应力可能导致部分原子弹出）
				var canvas_pt = _get_construction_canvas()
				if canvas_pt != null and canvas_pt._sim_settled:
					var min_atoms_pt: int = int(goal.get("min_atoms", 1))
					var actual_atoms_pt: int = _count_total_atoms()
					completed = actual_atoms_pt >= min_atoms_pt
				else:
					completed = false
				progress = 1.0 if completed else 0.0

			"magnetic_order_check":
				# 磁有序检测: 模拟后磁序类型匹配期望
				var canvas_mag = _get_construction_canvas()
				if canvas_mag != null and canvas_mag._sim_settled:
					var required_order: String = goal.get("required_order", "ferromagnetic")
					var actual_order: String = "paramagnetic"
					if canvas_mag._spin_system != null:
						actual_order = canvas_mag._spin_system.get_current_order()
					completed = actual_order == required_order
				else:
					completed = false
				progress = 1.0 if completed else 0.0

			"catalyst_efficiency_check":
				# 催化效率: 模拟后催化链数达标
				var canvas_cat = _get_construction_canvas()
				if canvas_cat != null and canvas_cat._sim_settled:
					var min_chains: int = int(goal.get("min_chains", 1))
					var actual_chains: int = 0
					if canvas_cat._catalyst_net != null:
						actual_chains = canvas_cat._catalyst_net.get_chain_count()
					completed = actual_chains >= min_chains
				else:
					completed = false
				progress = 1.0 if completed else 0.0

			"resonance_check":
				# 共振检测: 模拟后级联次数达标
				var canvas_res = _get_construction_canvas()
				if canvas_res != null and canvas_res._sim_settled:
					var min_cascades: int = int(goal.get("min_cascades", 1))
					var actual_cascades: int = 0
					if canvas_res._resonance_sys != null:
						actual_cascades = canvas_res._resonance_sys.get_cascade_info().get("cascade_count", 0)
					completed = actual_cascades >= min_cascades
				else:
					completed = false
				progress = 1.0 if completed else 0.0

			"stability_target":
				# 涌现目标: 模拟后热力学稳定性等级达标
				# 0=不稳定, 1=亚稳态, 2=稳定, 3=基态
				var canvas_stb = _get_construction_canvas()
				if canvas_stb != null and canvas_stb._sim_settled:
					var min_stability: int = int(goal.get("min_stability", 2))
					var actual_stability: int = 0
					if canvas_stb._thermo_sys != null:
						actual_stability = canvas_stb._thermo_sys.get_current_stability()
					completed = actual_stability >= min_stability
				else:
					completed = false
				progress = 1.0 if completed else 0.0

			"energy_target":
				# 涌现目标: 模拟后每原子Gibbs自由能低于阈值
				var canvas_en = _get_construction_canvas()
				if canvas_en != null and canvas_en._sim_settled:
					var max_energy: float = float(goal.get("max_energy_per_atom", -1.0))
					var atom_count_en: int = _count_total_atoms()
					var actual_energy: float = 999.0
					if canvas_en._thermo_sys != null and atom_count_en > 0:
						actual_energy = canvas_en._thermo_sys.get_gibbs_energy() / float(atom_count_en)
					completed = actual_energy <= max_energy
				else:
					completed = false
				progress = 1.0 if completed else 0.0

			"strain_target":
				# 涌现目标: 模拟后平均应变低于阈值（结构足够松弛）
				var canvas_st = _get_construction_canvas()
				if canvas_st != null and canvas_st._sim_settled:
					var max_strain: float = float(goal.get("max_avg_strain", 0.3))
					var actual_strain: float = 1.0
					if canvas_st._strain_field != null:
						actual_strain = float(canvas_st._strain_field.get_strain_info().get("avg_strain", 1.0))
					completed = actual_strain <= max_strain
				else:
					completed = false
				progress = 1.0 if completed else 0.0

			"fog_dispel":
				# 驱散指定数量的迷雾区域
				var required_dispel: int = int(goal.get("count", 1))
				var actual_dispel: int = 0
				if FogSystem != null:
					actual_dispel = FogSystem.get_dispelled_count()
				completed = actual_dispel >= required_dispel
				progress = clampf(float(actual_dispel) / float(maxi(required_dispel, 1)), 0.0, 1.0)

			"bond_count":
				# 键数量达标（作为独立 goal type，区别于 fuzzy_check 的 metric）
				# 兼容 "required_bonds" / "required_count" / "count"
				var required_bonds: int = int(goal.get("required_bonds", goal.get("required_count", goal.get("count", 1))))
				var actual_bonds: int = _bonds_built.size()
				completed = actual_bonds >= required_bonds
				progress = clampf(float(actual_bonds) / float(maxf(required_bonds, 1)), 0.0, 1.0)

			"structure_quality":
				# 约束式结构质量评估 — 多解创造核心
				# 不检查"放在了哪里"，只检查"结构是否满足物理约束"
				# 约束列表: conservation, charge_balance, symmetry, stability, min_atoms
				var sq_result: Dictionary = _evaluate_structure_quality(goal)
				progress = sq_result["progress"]
				completed = sq_result["completed"]

			_:
				progress = 0.0
				completed = false

		# 状态机转换
		# 验证类目标(conservation/geometry等)不自动完成，需要主动验证
		if requires_verification and goal_states[i] != GoalState.COMPLETED:
			# 只更新进度，不自动标记完成
			if progress > 0.01 and goal_states[i] == GoalState.PENDING:
				goal_states[i] = GoalState.IN_PROGRESS
				goal_updated.emit(i, GoalState.IN_PROGRESS, progress)
			elif goal_states[i] == GoalState.IN_PROGRESS:
				goal_updated.emit(i, GoalState.IN_PROGRESS, progress)
			all_completed = false
		elif completed and goal_states[i] != GoalState.COMPLETED:
			goal_states[i] = GoalState.COMPLETED
			goal_updated.emit(i, GoalState.COMPLETED, 1.0)
		elif progress > 0.01 and goal_states[i] == GoalState.PENDING:
			goal_states[i] = GoalState.IN_PROGRESS
			goal_updated.emit(i, GoalState.IN_PROGRESS, progress)

		if not completed and not requires_verification:
			all_completed = false
		elif requires_verification and goal_states[i] != GoalState.COMPLETED:
			all_completed = false

	# 所有目标都完成了？
	if all_completed and goals.size() > 0:
		_complete_level()


# Strip leading digits from Wyckoff labels: "4a" -> "a", "8b" -> "b"
# JSON level data uses full crystallographic notation, but atom_placement_manager
# normalizes labels before registering in _atoms_placed
func _normalize_wyckoff(label: String) -> String:
	var result := ""
	for ch in label:
		if not ch.is_valid_int():
			result += ch
	return result


func _goal_requires_verification(goal_type: String) -> bool:
	# 这些目标类型需要玩家主动点击"测试结构"才能完成
	# 放置类目标(wyckoff_fill/bond_build等)自动完成，验证类目标需要主动验证
	match goal_type:
		"conservation_check", "geometry_check", "transport_check", \
		"interface_check", "thermal_check", "em_check", "symmetry_check", \
		"ca_conservation_maintain", "structure_quality":
			return true
		_:
			return false


func _evaluate_fuzzy_metric(metric: String) -> float:
	# 模糊目标度量值计算，支持多种物理量
	var total_atoms: int = _count_total_atoms()
	match metric:
		"atom_count":
			return float(total_atoms)
		"bond_count":
			return float(_bonds_built.size())
		"density":
			if total_atoms == 0:
				return 0.0
			# 晶胞体积 = a*b*c（正交晶系），原子数密度 = 原子数 / 体积
			var lattice: Vector3 = current_level_data.get("lattice_parameters", Vector3(5,5,5))
			var vol: float = lattice.x * lattice.y * lattice.z
			return float(total_atoms) / maxf(vol, 0.001)
		"max_deviation":
			var dev_summary: Dictionary = ConservationEngine.get_deviation_summary()
			var max_dev: float = 0.0
			for key in dev_summary:
				max_dev = maxf(max_dev, dev_summary[key]["deviation"])
			return max_dev
		"element_diversity":
			var elems: Dictionary = {}
			for atom in _atoms_placed.values():
				for elem in atom.keys():
					elems[elem] = true
			return float(elems.size())
		"resonance_duration":
			# 共振状态累计秒数（供Boss关"共振生存"使用）
			return _resonance_duration
		"seed_count":
			# CA育种关卡：玩家保存的种子数
			return float(_ca_seeds_saved)
		"order_parameter":
			# 有序度: 键数/原子数 (连接性代表结构有序程度)
			if total_atoms == 0:
				return 0.0
			return clampf(float(_bonds_built.size()) / float(total_atoms), 0.0, 1.0)
		_:
			return 0.0


# 主动验证目标: 玩家点击"测试结构"时调用，检查所有验证类目标
func verify_goals() -> void:
	# Besiege风格: 主动测试结构，验证所有守恒/几何目标
	var all_completed := true
	for i in range(goals.size()):
		var goal := goals[i]
		# Ch5 schema nests fields in "params" — unwrap for uniform handling
		if goal.has("params") and goal["params"] is Dictionary:
			var _uw: Dictionary = goal["params"].duplicate()
			_uw["type"] = goals[i]["type"]
			goal = _uw
		if not _goal_requires_verification(goal["type"]):
			continue
		if goal_states[i] == GoalState.COMPLETED:
			continue

		var progress := 0.0
		var completed := false

		match goal["type"]:
			"conservation_check":
				var dev_summary: Dictionary = ConservationEngine.get_deviation_summary()
				var max_dev := 0.0
				for key in dev_summary:
					max_dev = maxf(max_dev, dev_summary[key].get("deviation", 0.0))
				var max_dev_thresh: float = float(goal.get("max_deviation", goal.get("max_dev", 0.5)))
				progress = maxf(1.0 - max_dev / maxf(max_dev_thresh, 0.001), 0.0)
				completed = max_dev <= max_dev_thresh

			"geometry_check":
				# 复用_check_goals中的geometry_check逻辑
				var result := _evaluate_geometry_goal(goal)
				progress = result.progress
				completed = result.completed

			"transport_check":
				var dev_summary: Dictionary = ConservationEngine.get_deviation_summary()
				var max_dev: float = 0.0
				for key in dev_summary:
					max_dev = maxf(max_dev, dev_summary[key]["deviation"])
				progress = maxf(1.0 - max_dev, 0.0)
				completed = max_dev < 0.15

			"interface_check":
				var dev_summary: Dictionary = ConservationEngine.get_deviation_summary()
				var max_dev: float = 0.0
				for key in dev_summary:
					max_dev = maxf(max_dev, dev_summary[key]["deviation"])
				var max_mismatch: float = goal.get("max_mismatch", 0.2)
				progress = maxf(1.0 - max_dev / max_mismatch, 0.0)
				completed = max_dev < max_mismatch

			"thermal_check":
				var dev_summary: Dictionary = ConservationEngine.get_deviation_summary()
				var max_dev: float = 0.0
				for key in dev_summary:
					max_dev = maxf(max_dev, dev_summary[key]["deviation"])
				progress = maxf(1.0 - max_dev * 2.0, 0.0)
				completed = max_dev < 0.1

			"em_check":
				var em_summary: Dictionary = ConservationEngine.get_deviation_summary()
				var em_max_dev: float = 0.0
				for key in em_summary:
					em_max_dev = maxf(em_max_dev, em_summary[key]["deviation"])
				progress = maxf(1.0 - em_max_dev / goal.get("max_deviation", 0.15), 0.0)
				completed = em_max_dev <= goal.get("max_deviation", 0.15)

			"symmetry_check":
				var _sym_params_v: Dictionary = goal.get("params", {})
				var source_sg: int = int(goal.get("source_sg", _sym_params_v.get("source_sg", 0)))
				var target_sg: int = int(goal.get("target_sg", _sym_params_v.get("target_sg", 0)))
				var required_count_sym: int = int(goal.get("required_count", _sym_params_v.get("required_count", 1)))
				var total_atoms_sym: int = _count_total_atoms()
				if total_atoms_sym == 0:
					progress = 0.0
					completed = false
				else:
					var atom_ratio: float = minf(float(total_atoms_sym) / float(maxf(required_count_sym, 1)), 1.0)
					var sym_score: float = _evaluate_symmetry_lowering(source_sg, target_sg)
					progress = atom_ratio * 0.3 + sym_score * 0.7
					completed = total_atoms_sym >= required_count_sym and sym_score >= 0.8

			"ca_conservation_maintain":
				# CA 演化守恒维持：检查当前偏离（非历史最大值）
				var v_ca_max_dev: float = goal.get("max_deviation", goal.get("max_dev", 0.2))
				var v_ca_min_steps: int = goal.get("min_steps", 10)
				var v_ca_dev: float = 0.0
				var v_ca_summary: Dictionary = ConservationEngine.get_deviation_summary()
				for v_key in v_ca_summary:
					v_ca_dev = maxf(v_ca_dev, v_ca_summary[v_key]["deviation"])
				if _ca_step_count >= v_ca_min_steps:
					completed = v_ca_dev <= v_ca_max_dev
					progress = maxf(1.0 - v_ca_dev / v_ca_max_dev, 0.0)
				else:
					progress = minf(float(_ca_step_count) / float(maxi(v_ca_min_steps, 1)), 0.8)
					completed = false

			"structure_quality":
				var sq_result_v: Dictionary = _evaluate_structure_quality(goal)
				progress = sq_result_v["progress"]
				completed = sq_result_v["completed"]

			"fuzzy_check":
				# 与 _check_goals 中的 fuzzy_check 逻辑保持一致
				var fc_metric: String = goal.get("metric", goal.get("property", ""))
				var fc_operator: String = goal.get("operator", goal.get("comparison", ">="))
				var fc_threshold: float = float(goal.get("threshold", 0.0))
				if fc_metric == "":
					for fk in goal.keys():
						if fk in ["atom_count", "bond_count", "density", "max_deviation",
								"element_diversity", "resonance_duration", "seed_count",
								"order_parameter"]:
							fc_metric = fk
							fc_threshold = float(goal[fk])
							break
				var fc_val: float = _evaluate_fuzzy_metric(fc_metric)
				match fc_operator:
					">=": completed = fc_val >= fc_threshold
					"<=": completed = fc_val <= fc_threshold
					">": completed = fc_val > fc_threshold
					"<": completed = fc_val < fc_threshold
					"==": completed = absf(fc_val - fc_threshold) < 0.01
				if fc_threshold != 0.0:
					match fc_operator:
						"<=", "<":
							progress = clampf(1.0 - fc_val / fc_threshold, 0.0, 1.0)
						_:
							progress = clampf(fc_val / fc_threshold, 0.0, 1.0)
				else:
					progress = 1.0 if completed else 0.0

		if completed and goal_states[i] != GoalState.COMPLETED:
			goal_states[i] = GoalState.COMPLETED
			goal_updated.emit(i, GoalState.COMPLETED, 1.0)
			GameLogger.info("LevelManager", "[关卡] 验证通过: %s" % goal.get("description", goal["type"]))
		else:
			goal_updated.emit(i, GoalState.IN_PROGRESS, progress)
			if not completed:
				all_completed = false

	# 验证类目标: 当所有其他目标都完成时自动标记完成
	# (不受 all_completed 限制 — verification 自身会令 all_completed 为 false)
	var others_done := true
	for i in range(goals.size()):
		if goals[i]["type"] == "verification":
			continue
		if goal_states[i] != GoalState.COMPLETED:
			others_done = false
			break
	if others_done and goals.size() > 0:
		mark_verification_done(99)

	# 重新检查是否全部完成
	var truly_all_done := true
	for gs in goal_states:
		if gs != GoalState.COMPLETED:
			truly_all_done = false
			break
	if truly_all_done and goals.size() > 0:
		_complete_level()


func _evaluate_geometry_goal(goal: Dictionary) -> Dictionary:
	# 从_check_goals提取的geometry_check逻辑，供verify_goals复用
	var tol: float = float(goal.get("tolerance", 0.1))
	var atoms_data: Array = _get_atom_positions()
	var dev_summary: Dictionary = ConservationEngine.get_deviation_summary()
	var cons_max_dev: float = 0.0
	for key in dev_summary:
		cons_max_dev = maxf(cons_max_dev, dev_summary[key]["deviation"])

	var progress := 0.0
	var completed := false

	if goal.has("target_angle"):
		var target_angle: float = float(goal["target_angle"])
		var angle_tol: float = float(goal.get("angle_tolerance", tol))
		if atoms_data.is_empty():
			progress = maxf(1.0 - cons_max_dev, 0.0)
			completed = false
		else:
			var best_angle: float = _find_closest_bond_angle(atoms_data, target_angle)
			if best_angle < 0.0:
				progress = 0.0
				completed = false
			else:
				var angle_diff: float = absf(best_angle - target_angle)
				progress = maxf(1.0 - angle_diff / maxf(angle_tol, 0.001), 0.0)
				completed = angle_diff <= angle_tol

	elif goal.has("target_distance") or goal.has("target_length"):
		var target_dist: float = float(goal.get("target_distance", goal.get("target_length", 0.0)))
		var dist_tol: float = float(goal.get("distance_tolerance", tol))
		var check_pair: Array = goal.get("check_pair", [])
		if atoms_data.is_empty():
			progress = maxf(1.0 - cons_max_dev, 0.0)
			completed = false
		else:
			var best_dist: float = _find_closest_bond_length(atoms_data, target_dist, check_pair)
			if best_dist < 0.0:
				progress = 0.0
				completed = false
			else:
				var dist_diff: float = absf(best_dist - target_dist)
				progress = maxf(1.0 - dist_diff / maxf(dist_tol, 0.001), 0.0)
				completed = dist_diff <= dist_tol

	elif goal.has("target_lattice"):
		var target_lat: float = float(goal["target_lattice"])
		var lat_tol: float = float(goal.get("lattice_tolerance", tol))
		var lattice: Vector3 = current_level_data.get("lattice_parameters", Vector3.ZERO)
		var actual_lat: float = lattice.x
		var lat_diff: float = absf(actual_lat - target_lat)
		progress = maxf(1.0 - lat_diff / maxf(lat_tol, 0.001), 0.0)
		completed = lat_diff <= lat_tol and _has_any_atoms()

	elif goal.has("target_ca_ratio"):
		var target_ca: float = float(goal["target_ca_ratio"])
		var ca_tol: float = float(goal.get("ca_tolerance", tol))
		var min_ca: float = float(goal.get("min_ca", target_ca))
		var lattice_ca: Vector3 = current_level_data.get("lattice_parameters", Vector3.ONE)
		var actual_ca: float = lattice_ca.z / maxf(lattice_ca.x, 0.001)
		var ca_diff: float = absf(actual_ca - target_ca)
		progress = maxf(1.0 - ca_diff / maxf(ca_tol, 0.001), 0.0)
		completed = actual_ca >= min_ca and _has_any_atoms()

	elif goal.has("target_value") and goal.get("check_type", "") == "tolerance_factor":
		var target_val: float = float(goal["target_value"])
		var val_tol: float = float(goal.get("value_tolerance", tol))
		var scene_cfg: Dictionary = current_level_data.get("scene_config", {})
		var r_a: float = float(scene_cfg.get("r_A", 0.0))
		var r_b: float = float(scene_cfg.get("r_B", 0.0))
		var r_o: float = float(scene_cfg.get("r_O", 0.0))
		if r_a > 0.0 and r_b > 0.0 and r_o > 0.0:
			var t_factor: float = (r_a + r_o) / (sqrt(2.0) * (r_b + r_o))
			var val_diff: float = absf(t_factor - target_val)
			progress = maxf(1.0 - val_diff / maxf(val_tol, 0.001), 0.0)
			completed = val_diff <= val_tol and _has_any_atoms()
		else:
			progress = maxf(1.0 - cons_max_dev, 0.0)
			completed = false

	elif goal.has("max_deviation"):
		var max_allowed: float = float(goal.get("max_deviation", 0.3))
		progress = maxf(1.0 - cons_max_dev / maxf(max_allowed, 0.001), 0.0)
		completed = cons_max_dev < max_allowed

	elif goal.has("min_distance"):
		progress = maxf(1.0 - cons_max_dev, 0.0)
		completed = cons_max_dev < 0.3

	else:
		progress = maxf(1.0 - cons_max_dev, 0.0)
		completed = cons_max_dev < 0.2

	return {"progress": progress, "completed": completed}


func mark_verification_done(layer: int) -> void:
	# 验证管道跑完后标记对应层级的验证目标为完成
	for i in range(goals.size()):
		if goals[i]["type"] == "verification" and goals[i].get("required_layer", 0) <= layer:
			goal_states[i] = GoalState.COMPLETED
			goal_updated.emit(i, GoalState.COMPLETED, 1.0)
	_check_goals()


func _complete_level() -> void:
	if _level_completed:
		return
	_level_completed = true

	# 综合计分: 基础分 + 守恒质量 + 效率 + 时间 + 证明深度
	# 权重重平衡: 守恒质量从50→100(占比43%), 效率50→40, 时间30→20, 基础100→80
	var base_score := 80.0
	var proof_depth := ProofTree.get_tree_depth()

	# 守恒质量分: 偏离越小分越高（权重翻倍，强调"构造即证明"理念）
	var dev_summary: Dictionary = ConservationEngine.get_deviation_summary()
	var max_dev: float = 0.0
	for key in dev_summary:
		max_dev = maxf(max_dev, dev_summary[key]["deviation"])
	var conservation_bonus := maxf(100.0 - max_dev * 200.0, 0.0)

	# 效率分: 操作越少分越高（par = 目标数的2倍）
	var total_goals := goals.size()
	var par_moves := maxf(float(total_goals * 2), 4.0)
	var efficiency_bonus := maxf(40.0 - (move_count - par_moves) * 4.0, 0.0)

	# 时间分: 60秒内完成有额外奖励
	var elapsed := (Time.get_ticks_msec() / 1000.0) - _level_start_time
	var time_bonus := maxf(20.0 - elapsed * 0.3, 0.0)

	# 证明深度奖励: 每层证明树深度+10分，鼓励玩家做深层验证
	var proof_bonus := float(proof_depth) * 10.0

	var score := base_score + conservation_bonus + efficiency_bonus + time_bonus + proof_bonus
	score = maxf(score, 10.0)

	# 星级评价: 3星=高效+低偏离+有证明深度, 2星=正常, 1星=勉强通过
	var stars := 1
	if score >= 200.0 and max_dev < 0.1 and proof_depth >= 2:
		stars = 3
	elif score >= 150.0:
		stars = 2

	var cores_earned: int = current_level_data.get("reward_cores", 1)
	# 星级加成: 3星双倍核心, 2星1.5倍
	cores_earned = int(float(cores_earned) * (1.0 + 0.5 * (stars - 1)))
	GameState.gain_cores(cores_earned)
	if cores_earned > 0:
		SoundManager.play(SoundManager.SoundType.CORE_EARNED)

	# 同步进化点数: 1核心 = 1进化点
	SelfEvolve.gain_evolve_points(cores_earned)
	if cores_earned > 0:
		SoundManager.play(SoundManager.SoundType.EVOLVE_POINT_EARNED)

	# 解锁材料图鉴
	var chapter: int = current_level_data.get("chapter", 0)
	var level: int = current_level_data.get("level", 0)
	MaterialCodex.check_level_completion(chapter, level, score)

	# 记录已通关关卡到GameState，供存档系统使用
	GameState.mark_level_completed(chapter, level)

	# 关卡完成时自动存档，防止崩溃丢失进度
	SaveManager.save_game()
	GameLogger.info("LevelManager", "[存档] 关卡完成自动保存")

	# 将运行时指标附加到关卡数据，供信号监听者读取
	current_level_data["_metrics_snapshot"] = _metrics.duplicate(true)

	# 计算优雅度评分（多解创造模式）
	_elegance_score = calculate_elegance_score()
	current_level_data["_elegance_score"] = _elegance_score
	current_level_data["_elegance_breakdown"] = _elegance_breakdown.duplicate(true)
	elegance_scored.emit(_elegance_score, _elegance_breakdown)

	GameLogger.info("LevelManager", "[关卡] 完成! 得分: %.1f, 星级: %d★, 优雅度: %.1f, 操作: %d, 偏离: %.3f, 用时: %.1fs, 证明深度: %d, 获得%d核心, undo=%d, hint=%d, retry=%d" % [score, stars, _elegance_score, move_count, max_dev, elapsed, proof_depth, cores_earned, _metrics.get("undo_count", 0), _metrics.get("hint_count", 0), _metrics.get("retry_count", 0)])
	level_completed.emit(score, cores_earned)


func get_goal_progress() -> Dictionary:
	# 返回所有目标的当前状态，给HUD用
	var result: Dictionary = {}
	for i in range(goals.size()):
		result[str(i)] = {
			"goal": goals[i],
			"state": goal_states[i],
		}
	return result


func get_current_space_group() -> int:
	return current_level_data.get("space_group_number", 1)


func get_lattice_params() -> Vector3:
	return current_level_data.get("lattice_parameters", Vector3(5.0, 5.0, 5.0))


func get_current_domain() -> String:
	return current_level_data.get("domain", "crystal")


func get_construction_mode() -> String:
	return current_level_data.get("construction_mode", "wyckoff_fill")


func get_available_tools() -> Array:
	return current_level_data.get("available_tools", ["element_block", "wyckoff_snap"])


func get_scale_label() -> String:
	return current_level_data.get("scale_label", "Å")


func get_scale_range() -> Vector2:
	return current_level_data.get("scale_range", Vector2(0.5, 10.0))


func get_constraints() -> Dictionary:
	return current_level_data.get("constraints", {})


func get_atoms_placed() -> Dictionary:
	return _atoms_placed.duplicate(true)

func get_bonds_built() -> Array:
	return _bonds_built.duplicate(true)

func get_assembled_parts() -> Dictionary:
	return _assembled_parts.duplicate(true)

func get_path_nodes() -> Array:
	return _path_nodes.duplicate(true)

func set_atoms_placed(data: Dictionary) -> void:
	_atoms_placed = data.duplicate(true)

func set_bonds_built(data: Array) -> void:
	_bonds_built.clear()
	for b in data:
		_bonds_built.append(b.duplicate(true) if b is Dictionary else b)

func set_assembled_parts(data: Dictionary) -> void:
	_assembled_parts = data.duplicate(true)

func set_path_nodes(data: Array) -> void:
	_path_nodes.clear()
	for p in data:
		_path_nodes.append(p.duplicate(true) if p is Dictionary else p)


func increment_metric(key: String) -> void:
	if _metrics.has(key):
		var current = _metrics[key]
		if current is int:
			_metrics[key] = current + 1
		elif current is float:
			_metrics[key] = current + 1.0


func set_metric(key: String, value: Variant) -> void:
	_metrics[key] = value


func get_metrics() -> Dictionary:
	return _metrics.duplicate(true)


func reset_level() -> void:
	current_level_data.clear()
	goals.clear()
	goal_states.clear()
	_atoms_placed.clear()
	_bonds_built.clear()
	_assembled_parts.clear()
	_path_nodes.clear()
	_ca_step_count = 0
	_ca_alive_count = 0
	_ca_density = 0.0
	_ca_phase = "extinct"
	_ca_max_deviation = 0.0
	_ca_patterns_detected.clear()
	_level_completed = false
	_level_failed = false
	_metrics.clear()
	_time_limit = 0.0
	_move_limit = 0
	_part_limit = 0
	_no_warning_constraint = false
	_instability_accumulator = 0.0
	_instability_modifier = 1.0


# ===== 路径、反应与拓扑检查辅助方法 =====

func _count_connected_path_nodes(max_segment_length: float) -> int:
	# Union-Find 计算最大连通分量节点数
	if _path_nodes.size() == 0:
		return 0

	var n: int = _path_nodes.size()
	var parent: Array[int] = []
	parent.resize(n)
	for i in range(n):
		parent[i] = i

	# 内联 Union-Find，避免嵌套函数的 lambda 警告
	for i in range(n):
		var pos_i: Vector3 = _path_nodes[i].get("position", Vector3.ZERO)
		for j in range(i + 1, n):
			if pos_i.distance_to(_path_nodes[j].get("position", Vector3.ZERO)) <= max_segment_length:
				# union(i, j) - 路径压缩
				var ri: int = i
				while parent[ri] != ri:
					parent[ri] = parent[parent[ri]]
					ri = parent[ri]
				var rj: int = j
				while parent[rj] != rj:
					parent[rj] = parent[parent[rj]]
					rj = parent[rj]
				if ri != rj:
					parent[ri] = rj

	var counts: Dictionary = {}
	for i in range(n):
		# find(i) - 路径压缩
		var root: int = i
		while parent[root] != root:
			parent[root] = parent[parent[root]]
			root = parent[root]
		counts[root] = counts.get(root, 0) + 1

	var max_count: int = 0
	for r in counts:
		max_count = maxi(max_count, counts[r])
	return max_count


func _evaluate_reaction_path(reaction_steps: Array) -> Dictionary:
	# 检查路径节点是否按顺序包含了反应中间体
	# reaction_steps: [["元素A", "元素B"], ...] 或 ["H2O", "OH+H", ...]
	if reaction_steps.is_empty() or _path_nodes.is_empty():
		return {"progress": 0.0, "completed": false}

	var completed_steps: int = 0
	var node_index: int = 0
	for step in reaction_steps:
		if step is Array and step.size() >= 2:
			# 元素对模式：查找相邻的 from -> to 节点
			var from_elem: String = str(step[0])
			var to_elem: String = str(step[1])
			while node_index < _path_nodes.size() - 1:
				var elem_a: String = str(_path_nodes[node_index].get("element", ""))
				var elem_b: String = str(_path_nodes[node_index + 1].get("element", ""))
				if (elem_a == from_elem and elem_b == to_elem) or \
						(elem_a == to_elem and elem_b == from_elem):
					completed_steps += 1
					node_index += 2
					break
				node_index += 1
		elif step is String:
			# 字符串模式：查找匹配的节点（支持前缀匹配）
			var step_str: String = str(step)
			while node_index < _path_nodes.size():
				var elem: String = str(_path_nodes[node_index].get("element", ""))
				if elem == step_str or elem.begins_with(step_str) or step_str.begins_with(elem):
					completed_steps += 1
					node_index += 1
					break
				node_index += 1

	var progress: float = minf(float(completed_steps) / float(maxf(reaction_steps.size(), 1)), 1.0)
	return {"progress": progress, "completed": completed_steps >= reaction_steps.size()}


func _evaluate_topology(topology_type: String, min_nodes: int) -> Dictionary:
	# 简化拓扑检查：统计最大连通分量，并根据环数判断拓扑类型
	if _path_nodes.size() < min_nodes:
		return {"progress": float(_path_nodes.size()) / float(maxf(min_nodes, 1)), "completed": false}

	var connected: int = _count_connected_path_nodes(1.5)
	if connected < min_nodes:
		return {"progress": minf(float(connected) / float(maxf(min_nodes, 1)), 1.0), "completed": false}

	# 计算最大连通分量的边数，粗略判断是否有环
	var n: int = _path_nodes.size()
	var edge_count: int = 0
	for i in range(n):
		var pos_i: Vector3 = _path_nodes[i].get("position", Vector3.ZERO)
		for j in range(i + 1, n):
			var pos_j: Vector3 = _path_nodes[j].get("position", Vector3.ZERO)
			if pos_i.distance_to(pos_j) <= 1.5:
				edge_count += 1

	# 树：边数 = 节点数 - 1；链：边数 = 节点数 - 1 且最大度为 2；环：边数 = 节点数
	var is_ring: bool = edge_count >= connected
	var is_tree_or_chain: bool = edge_count >= connected - 1

	var type_ok: bool = false
	match topology_type:
		"ring":
			type_ok = is_ring
		"tree", "chain":
			type_ok = is_tree_or_chain
		_:
			type_ok = true

	return {"progress": 1.0, "completed": type_ok}


# ===== 几何与对称性检查辅助方法 =====

func _find_construction_canvas() -> Node:
	# LevelManager是autoload，需要从场景树查找ConstructionCanvas
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	# 先在当前场景中查找
	var scene: Node = tree.current_scene
	if scene != null:
		var canvas: Node = scene.find_child("ConstructionCanvas", true, false)
		if canvas != null:
			return canvas
	# 再从根节点查找
	var root: Node = tree.root
	if root != null:
		return root.find_child("ConstructionCanvas", true, false)
	return null


func _get_atom_positions() -> Array:
	# 从ConstructionCanvas获取所有已放置原子的位置和元素信息
	# 返回 [{element: String, position: Vector3, fractional: Vector3}, ...]
	var canvas: Node = _find_construction_canvas()
	if canvas == null:
		return []
	var atom_mgr = canvas.get("_atom_mgr")
	if atom_mgr == null or not is_instance_valid(atom_mgr):
		return []
	if not atom_mgr.has_method("get_atoms"):
		return []
	var positions: Array = []
	for atom in atom_mgr.get_atoms():
		if not is_instance_valid(atom):
			continue
		positions.append({
			"element": atom.element_symbol,
			"position": atom.position,
			"fractional": atom.fractional_position,
		})
	return positions


func _count_total_atoms() -> int:
	# 统计已放置原子总数(从_atoms_placed字典)
	var total: int = 0
	for wyckoff_label in _atoms_placed:
		for elem in _atoms_placed[wyckoff_label]:
			total += int(_atoms_placed[wyckoff_label][elem])
	return total


func _has_any_atoms() -> bool:
	return _count_total_atoms() > 0


func _find_closest_bond_angle(atoms_data: Array, target_angle: float) -> float:
	# 在所有三原子组A-B-C(B为中心)中找最接近目标值的角度
	# 只考虑近邻原子(距离<3.0Å)，返回-1.0表示原子不足
	if atoms_data.size() < 3:
		return -1.0
	var best_angle: float = -1.0
	var best_diff: float = INF
	for j in range(atoms_data.size()):
		var pos_j: Vector3 = atoms_data[j]["position"]
		# 找j的近邻原子
		var neighbors: Array[int] = []
		for i in range(atoms_data.size()):
			if i == j:
				continue
			var dist: float = pos_j.distance_to(atoms_data[i]["position"])
			if dist > 0.1 and dist < 3.0:
				neighbors.append(i)
		# 对每对近邻计算以j为中心的角度
		for a in range(neighbors.size()):
			for b in range(a + 1, neighbors.size()):
				var va: Vector3 = atoms_data[neighbors[a]]["position"] - pos_j
				var vb: Vector3 = atoms_data[neighbors[b]]["position"] - pos_j
				var len_a: float = va.length()
				var len_b: float = vb.length()
				if len_a < 0.001 or len_b < 0.001:
					continue
				var cos_angle: float = clampf(va.dot(vb) / (len_a * len_b), -1.0, 1.0)
				var angle: float = rad_to_deg(acos(cos_angle))
				var diff: float = absf(angle - target_angle)
				if diff < best_diff:
					best_diff = diff
					best_angle = angle
	return best_angle


func _find_closest_bond_length(atoms_data: Array, target_dist: float, check_pair: Array) -> float:
	# 在所有两原子组中找最接近目标值的距离
	# 如果指定了check_pair，只考虑匹配元素对的距离
	# 返回-1.0表示没有符合条件的原子对
	if atoms_data.size() < 2:
		return -1.0
	var best_dist: float = -1.0
	var best_diff: float = INF
	for i in range(atoms_data.size()):
		for j in range(i + 1, atoms_data.size()):
			var elem_i: String = atoms_data[i]["element"]
			var elem_j: String = atoms_data[j]["element"]
			# 如果指定了元素对，只检查匹配的
			if check_pair.size() >= 2:
				var p0: String = str(check_pair[0])
				var p1: String = str(check_pair[1])
				if not ((elem_i == p0 and elem_j == p1) or (elem_i == p1 and elem_j == p0)):
					continue
			var dist: float = atoms_data[i]["position"].distance_to(atoms_data[j]["position"])
			# 只考虑合理的键长范围
			if dist < 0.1 or dist > 5.0:
				continue
			var diff: float = absf(dist - target_dist)
			if diff < best_diff:
				best_diff = diff
				best_dist = dist
	return best_dist


# Prefix matching for bond element pairs: "O" matches "O1", "O2", etc.
# Handles levels where atoms have numbered suffixes but goals use base symbols
func _bond_element_match(atom_sym: String, pair_elem: String) -> bool:
	if atom_sym == pair_elem:
		return true
	return atom_sym.begins_with(pair_elem)


func _evaluate_symmetry_lowering(source_sg: int, target_sg: int) -> float:
	# 简化的对称性降低评估
	# 检查结构是否从高对称源空间群降低到低对称目标空间群
	# 返回0.0~1.0，1.0表示完全达到目标对称性
	var lattice: Vector3 = current_level_data.get("lattice_parameters", Vector3(5.0, 5.0, 5.0))
	var current_sg: int = int(current_level_data.get("space_group_number", 1))
	var score: float = 0.0

	# 1. 当前空间群匹配目标空间群，或已降低到目标以下（更多对称性破缺也算达成）
	if target_sg > 0 and current_sg > 0 and current_sg <= target_sg:
		score += 0.5

	# 2. 检查晶格是否偏离源对称性
	var a: float = lattice.x
	var b: float = lattice.y
	var c: float = lattice.z

	# 立方空间群: a=b=c (Pm-3m=221, Fm-3m=225, Im-3m=229等)
	var is_cubic_source: bool = (source_sg == 221 or source_sg == 225 or source_sg == 229 or source_sg == 200 or source_sg == 202 or source_sg == 215 or source_sg == 223)
	if is_cubic_source:
		# 源是立方晶系，检查是否偏离立方(a≠b或a≠c)
		var ab_dev: float = absf(a - b) / maxf(a, 0.001)
		var ac_dev: float = absf(a - c) / maxf(a, 0.001)
		var max_lat_dev: float = maxf(ab_dev, ac_dev)
		# 偏离立方越多，对称性降低越多
		score += minf(max_lat_dev * 15.0, 0.5)
	else:
		# 非立方源(如正交Pnma=62→Pna2_1=33)
		# 空间群序号降低表示对称性降低
		if target_sg > 0 and target_sg < source_sg:
			score += 0.3
		# 有原子放置说明结构已构建
		if _has_any_atoms():
			score += 0.2

	return clampf(score, 0.0, 1.0)


func _evaluate_structure_quality(goal: Dictionary) -> Dictionary:
	# 约束式结构质量评估 — 多解创造核心
	# 不检查"放在了哪里"，只检查"结构是否满足物理约束"
	# goal 中可指定约束:
	#   constraints: ["conservation", "charge_balance", "min_atoms"]
	#   max_deviation: 0.15 (守恒偏离上限)
	#   min_atoms: 4 (最少原子数)
	#   required_elements: ["Na", "Cl"] (必须包含的元素)
	#   charge_tolerance: 0.1 (电荷平衡容差)
	var result := {"progress": 0.0, "completed": false}
	var constraints: Array = goal.get("constraints", ["conservation", "min_atoms"])
	var max_dev_limit: float = float(goal.get("max_deviation", 0.15))
	var min_atoms: int = int(goal.get("min_atoms", 1))
	var required_elements: Array = goal.get("required_elements", [])
	var charge_tolerance: float = float(goal.get("charge_tolerance", 0.1))

	var total_atoms: int = _count_total_atoms()
	var checks_passed: int = 0
	var total_checks: int = constraints.size()

	# 守恒约束
	if "conservation" in constraints:
		var dev_summary: Dictionary = ConservationEngine.get_deviation_summary()
		var max_dev: float = 0.0
		for key in dev_summary:
			max_dev = maxf(max_dev, dev_summary[key]["deviation"])
		if max_dev <= max_dev_limit:
			checks_passed += 1

	# 最少原子数约束
	if "min_atoms" in constraints:
		if total_atoms >= min_atoms:
			checks_passed += 1

	# 电荷平衡约束
	if "charge_balance" in constraints:
		var charge_imbalance: float = _calculate_charge_imbalance()
		if absf(charge_imbalance) <= charge_tolerance:
			checks_passed += 1

	# 必须包含特定元素
	if "required_elements" in constraints and not required_elements.is_empty():
		var has_all := true
		for elem in required_elements:
			var found := false
			for wyckoff_data in _atoms_placed.values():
				if wyckoff_data is Dictionary and wyckoff_data.has(elem):
					if wyckoff_data[elem] > 0:
						found = true
						break
			if not found:
				has_all = false
				break
		if has_all:
			checks_passed += 1

	# 稳定性约束（守恒状态不是DISINTEGRATED）
	if "stability" in constraints:
		var state: int = ConservationEngine.get_state()
		if state < 3:  # 非瓦解状态
			checks_passed += 1

	result["progress"] = float(checks_passed) / float(maxi(total_checks, 1))
	result["completed"] = checks_passed >= total_checks and total_checks > 0
	return result


func _calculate_charge_imbalance() -> float:
	# 计算当前结构的电荷不平衡度
	# 元素电荷表（简化版，覆盖常见元素）
	var charges: Dictionary = {
		"Na": 1, "K": 1, "Li": 1, "Ag": 1,
		"Ca": 2, "Mg": 2, "Ba": 2, "Sr": 2, "Fe": 2,
		"Al": 3, "Fe3": 3,
		"Cl": -1, "F": -1, "Br": -1, "I": -1, "OH": -1,
		"O": -2, "S": -2, "Se": -2,
		"N": -3, "P": -3,
		"C": 4, "Si": 4, "Ti": 4,
		"H": 1,
	}
	var total_charge: float = 0.0
	for wyckoff_data in _atoms_placed.values():
		if wyckoff_data is Dictionary:
			for elem in wyckoff_data:
				var count: int = wyckoff_data[elem]
				var q: float = float(charges.get(elem, 0.0))
				total_charge += q * count
	return total_charge


func calculate_elegance_score() -> float:
	# 优雅度评分: 评估玩家解法的质量，而非正确性
	# 适用于多解创造模式——不同解法获得不同评分
	# 四个维度各0-25分，总分0-100:
	#   1. 守恒质量 (0-25): 偏离越小越高分
	#   2. 原子效率 (0-25): 用更少原子达成约束=更优雅
	#   3. 操作效率 (0-25): 用更少操作=更优雅
	#   4. 对称质量 (0-25): 结构对称性越好=更优雅
	_elegance_breakdown = {}

	# 1. 守恒质量
	var dev_summary: Dictionary = ConservationEngine.get_deviation_summary()
	var max_dev: float = 0.0
	for key in dev_summary:
		max_dev = maxf(max_dev, dev_summary[key]["deviation"])
	var conservation_score := maxf(25.0 - max_dev * 80.0, 0.0)
	_elegance_breakdown["conservation"] = conservation_score

	# 2. 原子效率: 与目标原子数比较
	var total_atoms: int = _count_total_atoms()
	var target_atoms: int = 0
	for elem_data in current_level_data.get("elements", []):
		target_atoms += int(elem_data.get("wyckoff_multiplicity", 1))
	if target_atoms > 0:
		var atom_ratio := float(total_atoms) / float(target_atoms)
		# 比率1.0=完美, >1.0=多余原子, <1.0=不足
		var atom_efficiency: float = 25.0
		if atom_ratio > 1.0:
			atom_efficiency = maxf(25.0 - (atom_ratio - 1.0) * 25.0, 0.0)
		elif atom_ratio < 1.0:
			atom_efficiency = atom_ratio * 25.0
		_elegance_breakdown["atom_efficiency"] = atom_efficiency
	else:
		# 无目标原子数时，按守恒质量给分
		_elegance_breakdown["atom_efficiency"] = conservation_score

	# 3. 操作效率: 与par比较
	var par_moves := maxf(float(goals.size() * 2), 4.0)
	var move_efficiency: float = 25.0
	if move_count > par_moves:
		move_efficiency = maxf(25.0 - (float(move_count) - par_moves) * 2.0, 0.0)
	_elegance_breakdown["move_efficiency"] = move_efficiency

	# 4. 对称质量: 检查结构是否保持空间群对称性
	var symmetry_score: float = 15.0  # 基础分
	var sg: int = current_level_data.get("space_group_number", 1)
	if sg > 1 and total_atoms > 0:
		# 简化评估：检查晶格参数是否符合对称性要求
		var lattice: Vector3 = current_level_data.get("lattice_parameters", Vector3.ONE)
		var is_cubic: bool = (sg >= 195 and sg <= 230)
		if is_cubic:
			var ab_dev: float = absf(lattice.x - lattice.y) / maxf(lattice.x, 0.001)
			var ac_dev: float = absf(lattice.x - lattice.z) / maxf(lattice.x, 0.001)
			var max_lat_dev: float = maxf(ab_dev, ac_dev)
			symmetry_score = maxf(25.0 - max_lat_dev * 50.0, 5.0)
		else:
			symmetry_score = 20.0  # 非立方给基础分
	_elegance_breakdown["symmetry"] = symmetry_score

	_elegance_score = conservation_score + _elegance_breakdown.get("atom_efficiency", 0.0) + move_efficiency + symmetry_score
	_elegance_score = clampf(_elegance_score, 0.0, 100.0)
	return _elegance_score
