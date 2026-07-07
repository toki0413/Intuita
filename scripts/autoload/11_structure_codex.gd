# structure_codex.gd
# 结构图鉴系统 - 本地导入导出 + 基因编码
# 玩家在沙盒中创造的结构可以序列化为"基因码"，导入导出分享

extends Node

signal structure_saved(gene_code: String)
signal structure_loaded(gene_code: String)

const CODEX_DIR: String = "user://structure_codex/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(CODEX_DIR)


# ---- 结构序列化 ----

func serialize_structure(atoms: Array, bonds: Array, metadata: Dictionary = {}) -> Dictionary:
	# 将3D结构序列化为紧凑字典
	var atom_data: Array = []
	for atom in atoms:
		if atom == null or not is_instance_valid(atom):
			continue
		atom_data.append({
			"pos": [atom.global_position.x, atom.global_position.y, atom.global_position.z],
			"elem": atom.get_meta("element_symbol", "?"),
			"wyckoff": atom.get_meta("wyckoff_label", ""),
		})
	var bond_data: Array = []
	for bond in bonds:
		bond_data.append({
			"a": bond.get("a", ""),
			"b": bond.get("b", ""),
			"type": bond.get("type", "single"),
		})
	return {
		"atoms": atom_data,
		"bonds": bond_data,
		"metadata": metadata,
		"timestamp": Time.get_unix_time_from_system(),
	}


func compute_gene_code(structure: Dictionary) -> String:
	# 计算结构的基因码（哈希短码）
	var json_str: String = JSON.stringify(structure["atoms"])
	var hash_val: int = json_str.hash()
	# 转为6位16进制短码，加INT前缀
	return "INT-" + ("%06X" % (hash_val & 0xFFFFFF))


# ---- 保存/加载 ----

func save_structure(atoms: Array, bonds: Array, name: String, metadata: Dictionary = {}) -> String:
	# 保存结构到本地图鉴，返回基因码
	var structure: Dictionary = serialize_structure(atoms, bonds, metadata)
	var gene_code: String = compute_gene_code(structure)
	structure["gene_code"] = gene_code
	structure["name"] = name

	var path: String = CODEX_DIR + gene_code + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[图鉴] 无法保存结构: %s" % path)
		return ""
	file.store_string(JSON.stringify(structure, "\t"))
	file.close()

	GameLogger.info("StructureCodex", "[图鉴] 结构已保存: %s (%s), 原子数=%d" % [name, gene_code, structure["atoms"].size()])
	structure_saved.emit(gene_code)
	return gene_code


func load_structure(gene_code: String) -> Dictionary:
	# 从基因码加载结构
	var path: String = CODEX_DIR + gene_code + ".json"
	if not FileAccess.file_exists(path):
		push_warning("[图鉴] 结构不存在: %s" % gene_code)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var raw: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(raw) != OK:
		return {}
	structure_loaded.emit(gene_code)
	return json.data


func list_structures() -> Array[Dictionary]:
	# 列出所有已保存的结构
	var result: Array[Dictionary] = []
	var dir := DirAccess.open(CODEX_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var file := FileAccess.open(CODEX_DIR + file_name, FileAccess.READ)
			if file:
				var raw: String = file.get_as_text()
				file.close()
				var json := JSON.new()
				if json.parse(raw) == OK:
					var data: Dictionary = json.data
					result.append({
						"gene_code": data.get("gene_code", ""),
						"name": data.get("name", "Unknown"),
						"atoms": data.get("atoms", []).size(),
						"timestamp": data.get("timestamp", 0),
					})
		file_name = dir.get_next()
	return result


func delete_structure(gene_code: String) -> bool:
	var path: String = CODEX_DIR + gene_code + ".json"
	return DirAccess.remove_absolute(path) == OK


# ---- 导入/导出 ----

func export_structure(gene_code: String, export_path: String) -> bool:
	# 导出结构到指定路径（.intuita_struct文件）
	var structure: Dictionary = load_structure(gene_code)
	if structure.is_empty():
		return false
	var file := FileAccess.open(export_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(structure, "\t"))
	file.close()
	return true


func import_structure(import_path: String) -> String:
	# 从指定路径导入结构，返回基因码
	if not FileAccess.file_exists(import_path):
		return ""
	var file := FileAccess.open(import_path, FileAccess.READ)
	if file == null:
		return ""
	var raw: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(raw) != OK:
		return ""
	var structure: Dictionary = json.data
	var gene_code: String = compute_gene_code(structure)
	structure["gene_code"] = gene_code
	# 保存到图鉴
	var save_path: String = CODEX_DIR + gene_code + ".json"
	var save_file := FileAccess.open(save_path, FileAccess.WRITE)
	if save_file:
		save_file.store_string(JSON.stringify(structure, "\t"))
		save_file.close()
	return gene_code


# ---- 基因杂交 ----

func hybridize(gene_a: String, gene_b: String) -> String:
	# 杂交两个结构：取A的骨架+B的元素
	var struct_a: Dictionary = load_structure(gene_a)
	var struct_b: Dictionary = load_structure(gene_b)
	if struct_a.is_empty() or struct_b.is_empty():
		return ""
	var atoms_a: Array = struct_a.get("atoms", [])
	var atoms_b: Array = struct_b.get("atoms", [])
	if atoms_a.is_empty() or atoms_b.is_empty():
		return ""
	# 取A的位置骨架，用B的元素替换
	var hybrid_atoms: Array = []
	var b_idx: int = 0
	for atom in atoms_a:
		var elem: String = atoms_b[b_idx % atoms_b.size()].get("elem", "C")
		hybrid_atoms.append({
			"pos": atom["pos"],
			"elem": elem,
			"wyckoff": atom.get("wyckoff", ""),
		})
		b_idx += 1
	var hybrid: Dictionary = {
		"atoms": hybrid_atoms,
		"bonds": struct_a.get("bonds", []),
		"metadata": {"type": "hybrid", "parents": [gene_a, gene_b]},
		"name": "Hybrid_%s_%s" % [gene_a, gene_b],
	}
	var gene_code: String = compute_gene_code(hybrid)
	hybrid["gene_code"] = gene_code
	var path: String = CODEX_DIR + gene_code + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(hybrid, "\t"))
		file.close()
	GameLogger.info("StructureCodex", "[图鉴] 杂交结构: %s × %s → %s" % [gene_a, gene_b, gene_code])
	return gene_code


# ---- 基因变异 ----

func mutate(gene_code: String, mutation_rate: float = 0.1) -> String:
	# 对结构施加随机扰动：移位/替换/删除原子
	var structure: Dictionary = load_structure(gene_code)
	if structure.is_empty():
		return ""
	var atoms: Array = structure.get("atoms", [])
	if atoms.is_empty():
		return ""
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var mutated_atoms: Array = []
	for atom in atoms:
		if rng.randf() < mutation_rate:
			# 10%概率跳过该原子（删除变异）
			continue
		var new_atom: Dictionary = atom.duplicate()
		if rng.randf() < mutation_rate:
			# 位置微移
			new_atom["pos"] = [
				atom["pos"][0] + rng.randf_range(-0.2, 0.2),
				atom["pos"][1] + rng.randf_range(-0.2, 0.2),
				atom["pos"][2] + rng.randf_range(-0.2, 0.2),
			]
		if rng.randf() < mutation_rate:
			# 元素替换
			var elems: Array[String] = ["H", "C", "N", "O", "F", "Na", "Cl", "K"]
			new_atom["elem"] = elems[rng.randi() % elems.size()]
		mutated_atoms.append(new_atom)
	var mutated: Dictionary = {
		"atoms": mutated_atoms,
		"bonds": structure.get("bonds", []),
		"metadata": {"type": "mutant", "parent": gene_code, "rate": mutation_rate},
		"name": "Mutant_%s" % gene_code,
	}
	var new_gene: String = compute_gene_code(mutated)
	mutated["gene_code"] = new_gene
	var path: String = CODEX_DIR + new_gene + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(mutated, "\t"))
		file.close()
	return new_gene
