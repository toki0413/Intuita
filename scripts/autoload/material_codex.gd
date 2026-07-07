extends Node
# 材料图鉴系统 - 收集关卡中构建的真实材料
# 每个材料对应一张图鉴卡片，包含物理属性和科学背景
# 进度保存到user://codex.dat

signal codex_updated(entry_id: String)
signal codex_entry_unlocked(entry_id: String)

# 稀有度颜色
const RARITY_COLORS: Dictionary = {
	"common": Color(0.6, 0.6, 0.6),
	"uncommon": Color(0.2, 0.5, 0.9),
	"rare": Color(0.6, 0.2, 0.9),
	"legendary": Color(1.0, 0.75, 0.1),
}

# 全部30个材料条目，覆盖所有关卡
const CODEX_ENTRIES: Array[Dictionary] = [
	# Ch1: Crystal Foundation (10)
	{
		"id": "nacl", "name": "Sodium Chloride", "formula": "NaCl", "rarity": "common",
		"space_group": "Fm-3m",
		"properties": {"lattice_parameter": "5.64 Å", "density": "2.16 g/cm³", "melting_point": "801 °C", "crystal_system": "Cubic"},
		"backstory": "Common table salt. One of the simplest ionic crystals, NaCl structure is the archetype for understanding ionic bonding and Wyckoff positions.",
		"chapter": 1, "level": 1,
	},
	{
		"id": "lifepo4", "name": "Lithium Iron Phosphate", "formula": "LiFePO₄", "rarity": "uncommon",
		"space_group": "Pnma",
		"properties": {"lattice_parameter": "10.33×6.01×4.69 Å", "density": "3.51 g/cm³", "melting_point": ">300 °C (decomp.)", "crystal_system": "Orthorhombic"},
		"backstory": "The workhorse cathode of electric vehicles. LiFePO₄'s olivine structure provides exceptional thermal stability and cycle life, trading energy density for safety.",
		"chapter": 1, "level": 2,
	},
	{
		"id": "tilt_pnma", "name": "Tilted Perovskite", "formula": "ABO₃ (Pnma)", "rarity": "uncommon",
		"space_group": "Pna2₁",
		"properties": {"lattice_parameter": "10.33×6.01×4.69 Å", "density": "~3.5 g/cm³", "melting_point": ">1000 °C", "crystal_system": "Orthorhombic"},
		"backstory": "When octahedra tilt, symmetry breaks. The Pnma→Pna2₁ transition is a classic soft-mode distortion — the lattice 'breathes' into a lower symmetry while conserving charge.",
		"chapter": 1, "level": 3,
	},
	{
		"id": "oxygen_vacancy", "name": "Oxygen-Deficient Oxide", "formula": "MO₃₋ₓ", "rarity": "uncommon",
		"space_group": "Fm-3m",
		"properties": {"lattice_parameter": "5.64 Å", "density": "~5.0 g/cm³", "melting_point": ">1500 °C", "crystal_system": "Cubic"},
		"backstory": "Remove an oxygen, break the lattice — but charge compensates. Oxygen vacancies are the most common defect in oxides, enabling ionic conductivity and catalysis.",
		"chapter": 1, "level": 4,
	},
	{
		"id": "diamond", "name": "Diamond", "formula": "C", "rarity": "rare",
		"space_group": "Fd-3m",
		"properties": {"lattice_parameter": "3.57 Å", "density": "3.51 g/cm³", "melting_point": "3550 °C", "crystal_system": "Cubic"},
		"backstory": "Each carbon bonds to four neighbors in perfect tetrahedral symmetry. Diamond's sp³ network makes it the hardest known natural material and the best thermal conductor.",
		"chapter": 1, "level": 5,
	},
	{
		"id": "water", "name": "Water", "formula": "H₂O", "rarity": "common",
		"space_group": "P1 (molecule)",
		"properties": {"bond_length": "0.96 Å", "bond_angle": "104.5°", "density": "1.00 g/cm³", "boiling_point": "100 °C"},
		"backstory": "Two lone pairs squeeze the H-O-H angle below the tetrahedral ideal. VSEPR theory in a nutshell — electron pairs repel, geometry follows.",
		"chapter": 1, "level": 6,
	},
	{
		"id": "ethanol", "name": "Ethanol", "formula": "C₂H₅OH", "rarity": "common",
		"space_group": "P1 (molecule)",
		"properties": {"molecular_weight": "46.07 g/mol", "boiling_point": "78.4 °C", "density": "0.789 g/cm³", "functional_group": "Hydroxyl (-OH)"},
		"backstory": "A C-C backbone with a hydroxyl tail. Ethanol is where organic chemistry begins — valence rules, functional groups, and the art of satisfying every bond.",
		"chapter": 1, "level": 7,
	},
	{
		"id": "srto3", "name": "Strontium Titanate", "formula": "SrTiO₃", "rarity": "uncommon",
		"space_group": "Pm-3m",
		"properties": {"lattice_parameter": "3.91 Å", "density": "5.12 g/cm³", "melting_point": "2080 °C", "crystal_system": "Cubic"},
		"backstory": "The textbook perovskite. SrTiO₃ sits at tolerance factor t≈1.0 — the Goldschmidt sweet spot where A-site and B-site ions fit perfectly into the oxygen cage.",
		"chapter": 1, "level": 8,
	},
	{
		"id": "thermal_sto", "name": "Thermally Strained SrTiO₃", "formula": "SrTiO₃ (heated)", "rarity": "rare",
		"space_group": "Pm-3m",
		"properties": {"lattice_parameter": "3.95 Å (+1%)", "density": "5.07 g/cm³", "thermal_expansion": "10⁻⁵ /K", "crystal_system": "Cubic"},
		"backstory": "Heat it up, the lattice swells. A 1% thermal strain stretches every bond, but the conservation matrix must stay healthy — energy is conserved even as the crystal breathes.",
		"chapter": 1, "level": 9,
	},
	{
		"id": "p4mm", "name": "Tetragonal Perovskite", "formula": "ABO₃ (P4mm)", "rarity": "rare",
		"space_group": "P4mm",
		"properties": {"lattice_parameter": "3.95×3.95×4.10 Å", "c/a_ratio": "1.04", "density": "~5.0 g/cm³", "crystal_system": "Tetragonal"},
		"backstory": "Cross the critical c/a ratio and symmetry shatters. The cubic→tetragonal transition is a paradigm of spontaneous symmetry breaking — order emerges from disorder.",
		"chapter": 1, "level": 10,
	},
	# Ch2: Flow and Interface (10)
	{
		"id": "ion_channel", "name": "LiFePO₄ Ion Channel", "formula": "LiFePO₄ (channel)", "rarity": "uncommon",
		"space_group": "Pnma",
		"properties": {"bottleneck": "1.6-3.0 Å", "ion_species": "Li⁺", "conductivity": "~10⁻⁴ S/cm", "activation_energy": "0.55 eV"},
		"backstory": "Lithium ions squeeze through bottlenecks in the olivine framework. Too narrow and they're stuck; too wide and the structure collapses. Engineering the bottleneck is everything.",
		"chapter": 2, "level": 1,
	},
	{
		"id": "licoo2_llzo", "name": "LiCoO₂/LLZO Interface", "formula": "LiCoO₂ + Li₇La₃Zr₂O₁₂", "rarity": "rare",
		"space_group": "R-3m / Ia-3d",
		"properties": {"mismatch": "<15%", "interface_type": "Cathode-Electrolyte", "conductivity": "10⁻³ S/cm", "stability": "Electrochemically stable"},
		"backstory": "Two different crystal structures meet at an interface. Grain boundary engineering is the key to solid-state batteries — the interface must conduct ions without reacting.",
		"chapter": 2, "level": 2,
	},
	{
		"id": "topology_transition", "name": "Topological Phase Transition", "formula": "MO (Fm-3m→I4/mmm)", "rarity": "rare",
		"space_group": "Fm-3m → I4/mmm",
		"properties": {"initial_phase": "Cubic", "target_phase": "Tetragonal", "order_parameter": "c/a ratio", "critical_point": "Undecidable"},
		"backstory": "A topological phase transition passes through a region where the outcome cannot be predicted — Gödel's shadow on physics. You must navigate the fog of undecidability.",
		"chapter": 2, "level": 3,
	},
	{
		"id": "multi_channel", "name": "Parallel Ion Channels", "formula": "LiFePO₄ (3× channel)", "rarity": "rare",
		"space_group": "Pnma",
		"properties": {"channel_count": "3", "interference": "Electrostatic", "parallel_conductivity": "3× single", "bottleneck": "1.6 Å each"},
		"backstory": "Three channels in parallel — but they interfere. Adjusting one bottleneck shifts the electrostatic potential of its neighbors. Coordination is the challenge.",
		"chapter": 2, "level": 4,
	},
	{
		"id": "boundary_layer", "name": "Fluid Boundary Layer", "formula": "Navier-Stokes Flow", "rarity": "uncommon",
		"space_group": "P1 (continuum)",
		"properties": {"reynolds_number": "100", "boundary_type": "No-slip", "layer_thickness": "2.0 nm", "flow_regime": "Laminar"},
		"backstory": "At the wall, velocity vanishes. The boundary layer is where viscosity dominates — a thin region where the no-slip condition creates the velocity gradient that drives drag.",
		"chapter": 2, "level": 5,
	},
	{
		"id": "faraday_cage", "name": "Faraday Cage", "formula": "Cu Enclosure", "rarity": "uncommon",
		"space_group": "P1 (device)",
		"properties": {"material": "Copper", "skin_depth": "2.0 μm", "shielding": ">60 dB", "frequency": "1 GHz"},
		"backstory": "Six copper panels, zero gaps. A Faraday cage works because conductors redistribute charge to cancel internal fields — but any seam is a leak. Perfection or nothing.",
		"chapter": 2, "level": 6,
	},
	{
		"id": "heat_path", "name": "Thermal Conduction Path", "formula": "Cu/diamond/Al Stack", "rarity": "uncommon",
		"space_group": "P1 (device)",
		"properties": {"hot_temp": "500 K", "cold_temp": "300 K", "best_conductor": "Diamond (2200 W/mK)", "interface_resistance": "Critical"},
		"backstory": "Heat flows downhill — from hot to cold. Fourier's law governs, but interfaces are the bottleneck. Diamond conducts best, but only if you can bond it without thermal resistance.",
		"chapter": 2, "level": 7,
	},
	{
		"id": "boltzmann_ensemble", "name": "Boltzmann Ensemble", "formula": "100-Particle System", "rarity": "uncommon",
		"space_group": "P1 (statistical)",
		"properties": {"particle_count": "100", "temperature": "300 K", "distribution": "Boltzmann", "ensemble": "Canonical (NVT)"},
		"backstory": "P(E) ∝ exp(-E/kT). The Boltzmann distribution is the equilibrium of statistical mechanics. Fluctuations are not noise — they are the physics of finite systems.",
		"chapter": 2, "level": 8,
	},
	{
		"id": "fick_diffusion", "name": "Fickian Diffusion Field", "formula": "Concentration Gradient", "rarity": "uncommon",
		"space_group": "P1 (continuum)",
		"properties": {"diffusion_coeff": "10⁻⁹ m²/s", "initial_condition": "Step function", "governing_law": "Fick's 2nd Law", "conservation": "Mass"},
		"backstory": "J = -D∇c. Concentration gradients drive diffusion. The sharp front is undecidable — you cannot predict exactly where the boundary lies, only that mass is conserved.",
		"chapter": 2, "level": 9,
	},
	{
		"id": "thermoelectric", "name": "Thermoelectric Generator", "formula": "Bi₂Te₃/Sb₂Te₃ Couple", "rarity": "rare",
		"space_group": "P1 (device)",
		"properties": {"seebeck_coeff": "200 μV/K", "delta_T": "200 K", "emf": "~40 mV", "coupling": "Thermo-electric"},
		"backstory": "Seebeck effect: ΔV = S·ΔT. Heat drives electrons through a thermocouple, converting thermal gradients to electrical potential. Three conservation laws meet at one junction.",
		"chapter": 2, "level": 10,
	},
	# Ch3: Fire and Path (10)
	{
		"id": "sabatier", "name": "Sabatier Catalyst Cycle", "formula": "CO₂ + 4H₂ → CH₄ + 2H₂O", "rarity": "rare",
		"space_group": "P1 (reaction)",
		"properties": {"catalyst": "Ni", "max_intermediates": "5", "temperature": "300-400 °C", "selectivity": ">95%"},
		"backstory": "Carbon dioxide becomes methane through a catalytic dance. Each step conserves mass and charge — the path through reaction space is a proof that transformation is possible.",
		"chapter": 3, "level": 1,
	},
	{
		"id": "solid_state_battery", "name": "All-Solid-State Battery", "formula": "LiCoO₂|LLZO|Li", "rarity": "rare",
		"space_group": "R-3m | Ia-3d | Im-3m",
		"properties": {"cathode": "LiCoO₂", "electrolyte": "Li₇La₃Zr₂O₁₂", "anode": "Li metal", "voltage": "~3.7 V"},
		"backstory": "Cathode supplies Li⁺, electrolyte conducts Li⁺, anode receives Li⁺. The solid-state battery is a complete ionic circuit — every interface must be stable, every path must conduct.",
		"chapter": 3, "level": 2,
	},
	{
		"id": "unknown_material", "name": "Unknown Material X", "formula": "???", "rarity": "legendary",
		"space_group": "???",
		"properties": {"ionic_conductivity": ">10⁻³ S/cm", "electronic_conductivity": "<10⁻⁶ S/cm", "stability": "High", "discovery": "Community"},
		"backstory": "A material that doesn't exist yet — or does it? The unknown material challenge is pure exploration. No fixed answer, only the constraint that conservation must hold.",
		"chapter": 3, "level": 3,
	},
	{
		"id": "tio2_photocatalyst", "name": "TiO₂ Photocatalyst", "formula": "TiO₂", "rarity": "rare",
		"space_group": "I4₁/amd",
		"properties": {"band_gap": "3.2 eV", "cb_potential": "-0.5 V", "vb_potential": "+2.7 V", "light_absorption": "UV"},
		"backstory": "Ultraviolet photons excite electrons across TiO₂'s band gap. The conduction band reduces H⁺ to H₂, the valence band oxidizes H₂O to O₂. Sunlight splits water.",
		"chapter": 3, "level": 4,
	},
	{
		"id": "li_s_battery", "name": "Lithium-Sulfur Battery", "formula": "Li-S (with interceptor)", "rarity": "rare",
		"space_group": "P1 (device)",
		"properties": {"anode": "Li metal", "cathode": "S₈", "energy_density": "~400 Wh/kg", "challenge": "Polysulfide shuttle"},
		"backstory": "Sulfur promises 5× the energy of LiCoO₂, but polysulfides dissolve and shuttle between electrodes. The interceptor layer is the key — block the shuttle, keep the capacity.",
		"chapter": 3, "level": 5,
	},
	{
		"id": "ybco", "name": "YBCO Superconductor", "formula": "YBa₂Cu₃O₇₋ₓ", "rarity": "legendary",
		"space_group": "P4mm",
		"properties": {"lattice_parameter": "3.78×3.78×11.68 Å", "tc": "93 K", "cooper_pair": "d-wave", "doping": "δ ≈ 0"},
		"backstory": "Above liquid nitrogen temperature, resistance vanishes. YBCO's Cu-O planes host Cooper pairs with d-wave symmetry — the first high-Tc superconductor broke every rule.",
		"chapter": 3, "level": 6,
	},
	{
		"id": "rt_diode", "name": "Resonant Tunneling Diode", "formula": "AlGaAs/GaAs/AlGaAs", "rarity": "rare",
		"space_group": "P1 (device)",
		"properties": {"barrier": "AlGaAs (2 nm)", "well": "GaAs (5 nm)", "mechanism": "Quantum tunneling", "feature": "Negative differential resistance"},
		"backstory": "Two barriers, one quantum well. When the incident electron energy matches a well state, tunneling probability peaks — then drops as bias shifts away. Negative resistance from quantum mechanics.",
		"chapter": 3, "level": 7,
	},
	{
		"id": "protein_fold", "name": "Protein Folding Funnel", "formula": "Polypeptide Chain", "rarity": "rare",
		"space_group": "P1 (molecular)",
		"properties": {"residues": "12", "native_energy": "-42 kJ/mol", "kinetic_traps": "3", "folding_time": "μs-ms"},
		"backstory": "From a random coil to a unique native state through a funnel of decreasing energy. Kinetic traps are local minima — dead ends that look stable but aren't the destination.",
		"chapter": 3, "level": 8,
	},
	{
		"id": "mof_cubtc", "name": "Cu-BTC Metal-Organic Framework", "formula": "Cu₃(BTC)₂", "rarity": "legendary",
		"space_group": "Fm-3m",
		"properties": {"lattice_parameter": "12.0 Å", "pore_size": "~9 Å", "co2_uptake": ">3 mmol/g", "selectivity": "CO₂/N₂ > 10"},
		"backstory": "Copper nodes linked by organic struts form a crystalline sponge. MOFs have the highest surface areas known — a gram of Cu-BTC has the area of a football field.",
		"chapter": 3, "level": 9,
	},
	{
		"id": "universal_designer", "name": "Universal Material", "formula": "Custom", "rarity": "legendary",
		"space_group": "P1",
		"properties": {"optimization": "Pareto front", "constraints": "3 random", "community": "Ranked", "evolution": "Self-evolving"},
		"backstory": "No single optimum exists when objectives conflict. The Pareto front is the set of all materials where improving one property necessarily worsens another. Design is choice.",
		"chapter": 3, "level": 10,
	},
]

var _entries: Dictionary = {}  # id -> entry dict (with runtime state)
var _unlocked_count: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_init_entries()
	_load_codex()


func _init_entries() -> void:
	for entry in CODEX_ENTRIES:
		var id: String = entry["id"]
		_entries[id] = {
			"id": id,
			"name": entry.get("name", ""),
			"formula": entry.get("formula", ""),
			"rarity": entry.get("rarity", "common"),
			"space_group": entry.get("space_group", ""),
			"properties": entry.get("properties", {}),
			"backstory": entry.get("backstory", ""),
			"chapter": entry.get("chapter", 0),
			"level": entry.get("level", 0),
			"unlocked": false,
			"best_score": 0,
			"unlocked_at": "",
		}


func get_entry(id: String) -> Dictionary:
	return _entries.get(id, {})


func get_all_entries() -> Dictionary:
	return _entries


func get_unlocked_count() -> int:
	return _unlocked_count


func get_total_count() -> int:
	return _entries.size()


func unlock_entry(id: String, score: float = 0.0) -> void:
	if not _entries.has(id):
		return
	var entry: Dictionary = _entries[id]
	if entry["unlocked"]:
		# 更新最高分
		if score > entry["best_score"]:
			entry["best_score"] = score
			codex_updated.emit(id)
		return

	entry["unlocked"] = true
	entry["best_score"] = score
	entry["unlocked_at"] = Time.get_datetime_string_from_system()
	_unlocked_count += 1

	codex_entry_unlocked.emit(id)
	codex_updated.emit(id)
	_save_codex()


func check_level_completion(chapter: int, level: int, score: float) -> void:
	for id in _entries:
		var entry: Dictionary = _entries[id]
		if entry["chapter"] == chapter and entry["level"] == level:
			unlock_entry(id, score)


func get_entries_by_rarity(rarity: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _entries.values():
		if entry["rarity"] == rarity:
			result.append(entry)
	return result


func get_entries_by_element(element: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _entries.values():
		if entry["formula"].find(element) >= 0:
			result.append(entry)
	return result


func get_entries_by_space_group(sg: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _entries.values():
		if entry["space_group"] == sg:
			result.append(entry)
	return result


func get_rarity_color(rarity: String) -> Color:
	return RARITY_COLORS.get(rarity, Color.GRAY)


func _save_codex() -> void:
	var save_data: Dictionary = {}
	for id in _entries:
		var entry: Dictionary = _entries[id]
		save_data[id] = {
			"unlocked": entry["unlocked"],
			"best_score": entry["best_score"],
			"unlocked_at": entry["unlocked_at"],
		}
	var file := FileAccess.open("user://codex.dat", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data))
		file.close()


func _load_codex() -> void:
	if not FileAccess.file_exists("user://codex.dat"):
		return
	var file := FileAccess.open("user://codex.dat", FileAccess.READ)
	if not file:
		return
	var raw := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(raw) != OK:
		return
	var data: Dictionary = json.data

	_unlocked_count = 0
	for id in data:
		if not _entries.has(id):
			continue
		var saved: Dictionary = data[id]
		_entries[id]["unlocked"] = saved.get("unlocked", false)
		_entries[id]["best_score"] = saved.get("best_score", 0.0)
		_entries[id]["unlocked_at"] = saved.get("unlocked_at", "")
		if _entries[id]["unlocked"]:
			_unlocked_count += 1
