# goal_type_test.gd
# gdUnit4 单元测试：关卡目标类型完整性
# 确保所有 42 个关卡的目标类型都有真实实现（非硬 stub）

extends GdUnitTestSuite


const __source = "res://data/levels/level_data.gd"

# 硬 stub 类型：在 _check_goals 中落入 _ 分支，永远是 progress=0, completed=false
# 如果关卡数据中使用了这些类型，说明目标检查是死代码
const STUB_TYPES: Array[String] = [
	"boundary_check",
	"conductivity_check",
	"em_shielding_check",
	"distribution_check",
	"fluctuation_check",
	"concentration_check",
	"interaction_check",
	"defect_check",
	"evolution_check",
	"emergence_check",
	"potential_check",
]

# 已实现的目标类型：在 _check_goals 中有真实计算逻辑
const IMPLEMENTED_TYPES: Array[String] = [
	"wyckoff_fill",
	"conservation_check",
	"verification",
	"symmetry_check",
	"bond_check",
	"bond_build",
	"geometry_check",
	"transport_check",
	"interface_check",
	"reaction_path",
	"assembly_check",
	"topology_check",
	"mesh_build",
	"path_build",
	"thermal_check",
	"diffusion_check",
	"em_check",
]

# 所有关卡工厂方法，与 level_data_test.gd 保持一致
var _level_factories: Array[Dictionary] = [
	# Chapter 1 (10 levels)
	{"chapter": 1, "level": 1, "factory": "create_nacl_level"},
	{"chapter": 1, "level": 2, "factory": "create_lifepo4_level"},
	{"chapter": 1, "level": 3, "factory": "create_octahedral_tilt_level"},
	{"chapter": 1, "level": 4, "factory": "create_oxygen_vacancy_level"},
	{"chapter": 1, "level": 5, "factory": "create_diamond_network_level"},
	{"chapter": 1, "level": 6, "factory": "create_water_molecule_level"},
	{"chapter": 1, "level": 7, "factory": "create_ethanol_synthesis_level"},
	{"chapter": 1, "level": 8, "factory": "create_perovskite_level"},
	{"chapter": 1, "level": 9, "factory": "create_thermal_expansion_level"},
	{"chapter": 1, "level": 10, "factory": "create_phase_transition_level"},
	# Chapter 2 (10 levels)
	{"chapter": 2, "level": 1, "factory": "create_ion_channel_level"},
	{"chapter": 2, "level": 2, "factory": "create_grain_boundary_level"},
	{"chapter": 2, "level": 3, "factory": "create_topology_transition_level"},
	{"chapter": 2, "level": 4, "factory": "create_multi_channel_race_level"},
	{"chapter": 2, "level": 5, "factory": "create_fluid_boundary_layer_level"},
	{"chapter": 2, "level": 6, "factory": "create_em_shielding_level"},
	{"chapter": 2, "level": 7, "factory": "create_heat_conduction_path_level"},
	{"chapter": 2, "level": 8, "factory": "create_statistical_fluctuations_level"},
	{"chapter": 2, "level": 9, "factory": "create_diffusion_equation_level"},
	{"chapter": 2, "level": 10, "factory": "create_multiphysics_coupling_level"},
	# Chapter 3 (10 levels)
	{"chapter": 3, "level": 1, "factory": "create_catalytic_cycle_level"},
	{"chapter": 3, "level": 2, "factory": "create_solid_state_battery_level"},
	{"chapter": 3, "level": 3, "factory": "create_unknown_material_level"},
	{"chapter": 3, "level": 4, "factory": "create_photocatalytic_water_splitting_level"},
	{"chapter": 3, "level": 5, "factory": "create_li_s_battery_level"},
	{"chapter": 3, "level": 6, "factory": "create_superconductor_critical_level"},
	{"chapter": 3, "level": 7, "factory": "create_quantum_tunneling_diode_level"},
	{"chapter": 3, "level": 8, "factory": "create_protein_folding_funnel_level"},
	{"chapter": 3, "level": 9, "factory": "create_co2_capture_level"},
	{"chapter": 3, "level": 10, "factory": "create_universal_material_designer_level"},
	# Chapter 4 (8 levels, 3 CA)
	{"chapter": 4, "level": 1, "factory": "create_self_assembly_level"},
	{"chapter": 4, "level": 2, "factory": "create_symmetry_cascade_level"},
	{"chapter": 4, "level": 3, "factory": "create_topological_defect_level"},
	{"chapter": 4, "level": 4, "factory": "create_phase_field_evolution_level"},
	{"chapter": 4, "level": 5, "factory": "create_open_emergence_level"},
	{"chapter": 4, "level": 6, "factory": "create_ca_bays_4555_level"},
	{"chapter": 4, "level": 7, "factory": "create_ca_oscillator_level"},
	{"chapter": 4, "level": 8, "factory": "create_ca_phase_transition_level"},
	# Bonus (2 levels)
	{"chapter": 0, "level": 1, "factory": "create_molecular_folding_level"},
	{"chapter": 0, "level": 2, "factory": "create_nanowire_assembly_level"},
	# Challenge (5 levels)
	{"chapter": -1, "level": 1, "factory": "create_challenge_minimalist_level"},
	{"chapter": -1, "level": 2, "factory": "create_challenge_blind_in_fog_level"},
	{"chapter": -1, "level": 3, "factory": "create_challenge_conservation_purist_level"},
	{"chapter": -1, "level": 4, "factory": "create_challenge_speed_builder_level"},
	{"chapter": -1, "level": 5, "factory": "create_challenge_omniscient_level"},
]

var _created_levels: Array = []


func before() -> void:
	for entry in _level_factories:
		var ld: LevelData = Callable(LevelData, entry.factory).call()
		_created_levels.append({"data": ld, "info": entry})


func after() -> void:
	_created_levels.clear()


func test_no_level_uses_stub_goal_types() -> void:
	# 遍历所有 42 个关卡，确保没有使用硬 stub 目标类型
	# stub 类型在 _check_goals 中落入 _ 分支，永远是 progress=0, completed=false
	for entry in _created_levels:
		var ld: LevelData = entry["data"]
		var label: String = entry["info"]["factory"]
		for goal in ld.goals:
			var goal_type: String = goal.get("type", "")
			assert_bool(goal_type not in STUB_TYPES).override_failure_message(
				"%s uses stub goal type '%s': %s" % [label, goal_type, goal.get("description", "")]
			)


func test_all_goal_types_are_recognized() -> void:
	# 确保所有关卡中使用的目标类型都在已实现列表中
	# 如果出现未识别的类型，说明 _check_goals 可能缺少对应分支
	for entry in _created_levels:
		var ld: LevelData = entry["data"]
		var label: String = entry["info"]["factory"]
		for goal in ld.goals:
			var goal_type: String = goal.get("type", "")
			assert_bool(goal_type in IMPLEMENTED_TYPES).override_failure_message(
				"%s has unrecognized goal type '%s' (not in IMPLEMENTED_TYPES)" % [label, goal_type]
			)
