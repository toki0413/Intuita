# level_data_test.gd
# gdUnit4 单元测试：关卡数据完整性

extends GdUnitTestSuite


const __source = "res://data/levels/level_data.gd"

# 所有关卡工厂方法，按章节排列
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


func test_all_45_levels_created() -> void:
	assert_int(_created_levels.size()).is_equal(45)
	for i in range(_created_levels.size()):
		var entry = _created_levels[i]
		assert_object(entry["data"]).is_not_null()


func test_each_level_has_required_fields() -> void:
	for entry in _created_levels:
		var ld: LevelData = entry["data"]
		var label: String = entry["info"]["factory"]

		assert_str(ld.title).is_not_empty().override_failure_message("%s: title should not be empty" % label)
		assert_str(ld.description).is_not_empty().override_failure_message("%s: description should not be empty" % label)
		assert_int(ld.goals.size()).is_greater(0).override_failure_message("%s: goals should not be empty" % label)
		# 开放域/自由建造关卡（如未知材料悬赏）允许从空画布开始
		if ld.construction_mode != "free":
			assert_int(ld.elements.size()).is_greater(0).override_failure_message("%s: elements should not be empty" % label)


func test_each_level_has_at_least_one_goal() -> void:
	for entry in _created_levels:
		var label: String = entry["info"]["factory"]
		assert_int(entry["data"].goals.size()).is_greater_equal(1).override_failure_message("%s: should have at least 1 goal" % label)


func test_reward_cores_positive() -> void:
	for entry in _created_levels:
		var label: String = entry["info"]["factory"]
		assert_int(entry["data"].reward_cores).is_greater(0).override_failure_message("%s: reward_cores should be > 0" % label)
