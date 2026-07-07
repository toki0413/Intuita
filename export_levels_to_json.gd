# export_levels_to_json.gd
# 一次性导出脚本：从 LevelData 工厂方法生成 JSON 文件
# 运行: Godot --headless -s export_levels_to_json.gd

extends SceneTree

func _initialize():
	var factories := [
		# Chapter 1
		{"c": 1, "l": 1,  "f": "create_nacl_level"},
		{"c": 1, "l": 2,  "f": "create_lifepo4_level"},
		{"c": 1, "l": 3,  "f": "create_octahedral_tilt_level"},
		{"c": 1, "l": 4,  "f": "create_oxygen_vacancy_level"},
		{"c": 1, "l": 5,  "f": "create_diamond_network_level"},
		{"c": 1, "l": 6,  "f": "create_water_molecule_level"},
		{"c": 1, "l": 7,  "f": "create_ethanol_synthesis_level"},
		{"c": 1, "l": 8,  "f": "create_perovskite_level"},
		{"c": 1, "l": 9,  "f": "create_thermal_expansion_level"},
		{"c": 1, "l": 10, "f": "create_phase_transition_level"},
		# Chapter 2
		{"c": 2, "l": 1,  "f": "create_ion_channel_level"},
		{"c": 2, "l": 2,  "f": "create_grain_boundary_level"},
		{"c": 2, "l": 3,  "f": "create_topology_transition_level"},
		{"c": 2, "l": 4,  "f": "create_multi_channel_race_level"},
		{"c": 2, "l": 5,  "f": "create_fluid_boundary_layer_level"},
		{"c": 2, "l": 6,  "f": "create_em_shielding_level"},
		{"c": 2, "l": 7,  "f": "create_heat_conduction_path_level"},
		{"c": 2, "l": 8,  "f": "create_statistical_fluctuations_level"},
		{"c": 2, "l": 9,  "f": "create_diffusion_equation_level"},
		{"c": 2, "l": 10, "f": "create_multiphysics_coupling_level"},
		# Chapter 3
		{"c": 3, "l": 1,  "f": "create_catalytic_cycle_level"},
		{"c": 3, "l": 2,  "f": "create_solid_state_battery_level"},
		{"c": 3, "l": 3,  "f": "create_unknown_material_level"},
		{"c": 3, "l": 4,  "f": "create_photocatalytic_water_splitting_level"},
		{"c": 3, "l": 5,  "f": "create_li_s_battery_level"},
		{"c": 3, "l": 6,  "f": "create_superconductor_critical_level"},
		{"c": 3, "l": 7,  "f": "create_quantum_tunneling_diode_level"},
		{"c": 3, "l": 8,  "f": "create_protein_folding_funnel_level"},
		{"c": 3, "l": 9,  "f": "create_co2_capture_level"},
		{"c": 3, "l": 10, "f": "create_universal_material_designer_level"},
		# Chapter 4
		{"c": 4, "l": 1,  "f": "create_self_assembly_level"},
		{"c": 4, "l": 2,  "f": "create_symmetry_cascade_level"},
		{"c": 4, "l": 3,  "f": "create_topological_defect_level"},
		{"c": 4, "l": 4,  "f": "create_phase_field_evolution_level"},
		{"c": 4, "l": 5,  "f": "create_open_emergence_level"},
		{"c": 4, "l": 6,  "f": "create_ca_bays_4555_level"},
		{"c": 4, "l": 7,  "f": "create_ca_oscillator_level"},
		{"c": 4, "l": 8,  "f": "create_ca_phase_transition_level"},
		# Bonus
		{"c": 0, "l": 1,  "f": "create_molecular_folding_level"},
		{"c": 0, "l": 2,  "f": "create_nanowire_assembly_level"},
		# Challenge
		{"c": -1, "l": 1, "f": "create_challenge_minimalist_level"},
		{"c": -1, "l": 2, "f": "create_challenge_blind_in_fog_level"},
		{"c": -1, "l": 3, "f": "create_challenge_conservation_purist_level"},
		{"c": -1, "l": 4, "f": "create_challenge_speed_builder_level"},
		{"c": -1, "l": 5, "f": "create_challenge_omniscient_level"},
	]

	var dir := DirAccess.open("res://data/levels")
	if dir == null:
		push_error("Cannot open data/levels")
		quit()
		return
	if not dir.dir_exists("json"):
		dir.make_dir("json")

	var exported := 0
	var failed := 0
	for entry in factories:
		var factory: String = entry["f"]
		var callable := Callable(LevelData, factory)
		var ld: LevelData = callable.call()
		if ld == null:
			push_error("Factory returned null: %s" % factory)
			failed += 1
			continue
		var json_path := "res://data/levels/json/chapter_%d_level_%d.json" % [entry["c"], entry["l"]]
		var json_str := JSON.stringify(ld.to_json(), "\t")
		var file := FileAccess.open(json_path, FileAccess.WRITE)
		if file == null:
			push_error("Cannot write %s" % json_path)
			failed += 1
			continue
		file.store_string(json_str)
		file.close()
		exported += 1
		print("Exported: %s -> %s" % [factory, json_path])

	print("Done: %d exported, %d failed" % [exported, failed])
	quit()
