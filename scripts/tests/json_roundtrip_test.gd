# json_roundtrip_test.gd
# GdUnit4 测试: LevelData JSON 序列化 / 反序列化一致性

extends GdUnitTestSuite

const __source = "res://data/levels/level_data.gd"

func test_nacl_roundtrip() -> void:
	var ld: LevelData = LevelData.create_nacl_level()
	var json_dict: Dictionary = ld.to_json()

	var ld2 := LevelData.new()
	ld2.from_json(json_dict)

	assert_int(ld2.chapter).is_equal(ld.chapter)
	assert_int(ld2.level).is_equal(ld.level)
	assert_str(ld2.title).is_equal(ld.title)
	assert_str(ld2.description).is_equal(ld.description)
	assert_int(ld2.space_group_number).is_equal(ld.space_group_number)
	assert_str(ld2.space_group_symbol).is_equal(ld.space_group_symbol)
	assert_int(ld2.reward_cores).is_equal(ld.reward_cores)
	assert_str(ld2.hint).is_equal(ld.hint)
	assert_str(ld2.domain).is_equal(ld.domain)
	assert_str(ld2.construction_mode).is_equal(ld.construction_mode)
	assert_str(ld2.scale_label).is_equal(ld.scale_label)
	assert_str(ld2.journal_entry).is_equal(ld.journal_entry)
	assert_int(ld2.goals.size()).is_equal(ld.goals.size())
	assert_int(ld2.elements.size()).is_equal(ld.elements.size())
	assert_int(ld2.available_tools.size()).is_equal(ld.available_tools.size())

	# Vector3 序列化检查
	assert_float(ld2.lattice_parameters.x).is_equal_approx(ld.lattice_parameters.x, 0.0001)
	assert_float(ld2.lattice_parameters.y).is_equal_approx(ld.lattice_parameters.y, 0.0001)
	assert_float(ld2.lattice_parameters.z).is_equal_approx(ld.lattice_parameters.z, 0.0001)

	# Vector2 序列化检查
	assert_float(ld2.scale_range.x).is_equal_approx(ld.scale_range.x, 0.0001)
	assert_float(ld2.scale_range.y).is_equal_approx(ld.scale_range.y, 0.0001)


func test_all_45_levels_roundtrip() -> void:
	var factories := [
		LevelData.create_nacl_level, LevelData.create_lifepo4_level,
		LevelData.create_octahedral_tilt_level, LevelData.create_oxygen_vacancy_level,
		LevelData.create_diamond_network_level, LevelData.create_water_molecule_level,
		LevelData.create_ethanol_synthesis_level, LevelData.create_perovskite_level,
		LevelData.create_thermal_expansion_level, LevelData.create_phase_transition_level,
		LevelData.create_ion_channel_level, LevelData.create_grain_boundary_level,
		LevelData.create_topology_transition_level, LevelData.create_multi_channel_race_level,
		LevelData.create_fluid_boundary_layer_level, LevelData.create_em_shielding_level,
		LevelData.create_heat_conduction_path_level, LevelData.create_statistical_fluctuations_level,
		LevelData.create_diffusion_equation_level, LevelData.create_multiphysics_coupling_level,
		LevelData.create_catalytic_cycle_level, LevelData.create_solid_state_battery_level,
		LevelData.create_unknown_material_level, LevelData.create_photocatalytic_water_splitting_level,
		LevelData.create_li_s_battery_level, LevelData.create_superconductor_critical_level,
		LevelData.create_quantum_tunneling_diode_level, LevelData.create_protein_folding_funnel_level,
		LevelData.create_co2_capture_level, LevelData.create_universal_material_designer_level,
		LevelData.create_self_assembly_level, LevelData.create_symmetry_cascade_level,
		LevelData.create_topological_defect_level, LevelData.create_phase_field_evolution_level,
		LevelData.create_open_emergence_level, LevelData.create_ca_bays_4555_level,
		LevelData.create_ca_oscillator_level, LevelData.create_ca_phase_transition_level,
		LevelData.create_molecular_folding_level, LevelData.create_nanowire_assembly_level,
		LevelData.create_challenge_minimalist_level, LevelData.create_challenge_blind_in_fog_level,
		LevelData.create_challenge_conservation_purist_level, LevelData.create_challenge_speed_builder_level,
		LevelData.create_challenge_omniscient_level,
	]
	for factory in factories:
		var ld: LevelData = factory.call()
		assert_object(ld).is_not_null()
		var json_dict: Dictionary = ld.to_json()
		var ld2 := LevelData.new()
		ld2.from_json(json_dict)
		assert_str(ld2.title).is_equal(ld.title)
		assert_int(ld2.goals.size()).is_equal(ld.goals.size())
		assert_int(ld2.elements.size()).is_equal(ld.elements.size())


func test_json_file_matches_roundtrip() -> void:
	var file := FileAccess.open("res://data/levels/json/chapter_1_level_1.json", FileAccess.READ)
	assert_object(file).is_not_null()
	var raw := file.get_as_text()
	file.close()

	var json := JSON.new()
	assert_int(json.parse(raw)).is_equal(OK)
	var data: Dictionary = json.data

	var ld := LevelData.new()
	ld.from_json(data)
	assert_str(ld.title).is_equal("First Experiment")
	assert_int(ld.space_group_number).is_equal(225)

func test_empty_json_loads_defaults() -> void:
	var ld := LevelData.new()
	ld.from_json({})
	assert_str(ld.title).is_equal("")
	assert_int(ld.chapter).is_equal(1)
	assert_int(ld.level).is_equal(1)
	assert_int(ld.space_group_number).is_equal(1)
	assert_str(ld.space_group_symbol).is_equal("P1")
	assert_int(ld.reward_cores).is_equal(1)
	assert_str(ld.domain).is_equal("crystal")
	assert_str(ld.construction_mode).is_equal("wyckoff_fill")
	assert_str(ld.scale_label).is_equal("Å")
	assert_int(ld.goals.size()).is_equal(0)
	assert_int(ld.elements.size()).is_equal(0)
