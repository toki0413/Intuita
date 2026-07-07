# atom_placement_manager.gd
# 原子放置管理器 - 处理原子放置/替换/删除和成键
extends RefCounted

var _element_data: Dictionary = {}
var _atoms: Array[Node3D] = []
var _bonds: Array[Node3D] = []
var _wyckoff_markers: Array[Node3D] = []
var atoms_container: Node3D
var bonds_container: Node3D
var wyckoff_container: Node3D
var crystal_cell: Node3D
var current_element_index: int = 0
var selected_atom: Node3D = null
var _current_domain: String = "crystal"
var _current_construction_mode: String = "wyckoff_fill"
var _total_cell_mass: float = 1.0  # 初始为 1.0 避免除零，关卡加载后更新为实际总质量

# Wyckoff -> element map: used for hint display on markers, NOT auto-selection
# Set _auto_select_element=true for E2E test compatibility
var _element_wyckoff_map: Dictionary = {}
var _auto_select_element: bool = false

# 对象池
var _atom_pool: RefCounted = null  # ObjectPool
var _bond_pool: RefCounted = null  # ObjectPool

# 引用回调 - 由canvas设置
var _on_atom_clicked_callback: Callable
var _on_atom_state_changed_callback: Callable
var _on_atom_placed_callback: Callable

signal atom_substituted(atom: Node3D, old_element_index: int, new_element_index: int)

# 微奖励: Wyckoff位置填充计数
var _wyckoff_fill_counts: Dictionary = {}


# 标准化 Wyckoff 标签: 去掉前导数字，使 "4a" -> "a"
# 关卡数据使用裸字母(a/b/c)，而晶体学标记常带重数前缀(4a/8b)
func _normalize_wyckoff_label(label: String) -> String:
	var result := ""
	for ch in label:
		if not ch.is_valid_int():
			result += ch
	return result

# 根据当前关卡的守恒阈值动态计算微扰系数
func _get_perturb_coeff() -> float:
	var cons_thresh: float = 0.05
	if LevelManager and LevelManager.goals.size() > 0:
		for g in LevelManager.goals:
			if g.get("type", "") == "conservation_check":
				cons_thresh = minf(cons_thresh, float(g.get("max_deviation", 0.5)))
	if cons_thresh < 0.02:
		return cons_thresh * 0.5
	return 0.02


# 微奖励: 相机引用（用于屏幕震动）
var camera: Camera3D = null

# 当前工具类型 (0=PLACE, 4=DELETE, 1=SUBSTITUTE 等)
var current_tool: int = 0


func _init(atoms: Node3D, bonds: Node3D, wyckoff: Node3D, cell: Node3D) -> void:
	atoms_container = atoms
	bonds_container = bonds
	wyckoff_container = wyckoff
	crystal_cell = cell
	_init_pools()


func _init_pools() -> void:
	var pool_script := load("res://scripts/construction/object_pool.gd")
	# 原子池 - 预热5个原子节点
	if ResourceLoader.exists("res://scenes/atom_node.tscn"):
		_atom_pool = pool_script.new("res://scenes/atom_node.tscn", atoms_container, 5)
	# 键池 - 预热8个键节点
	if ResourceLoader.exists("res://scenes/bond_renderer.tscn"):
		_bond_pool = pool_script.new("res://scenes/bond_renderer.tscn", bonds_container, 8)


func set_callbacks(atom_clicked: Callable, atom_state_changed: Callable, atom_placed: Callable = Callable()) -> void:
	_on_atom_clicked_callback = atom_clicked
	_on_atom_state_changed_callback = atom_state_changed
	_on_atom_placed_callback = atom_placed


func load_element_data() -> void:
	var elem_res: ElementDataResource
	var tres_path := "res://resources/elements/element_data.tres"
	# security: validate .tres doesn't embed GDScript before loading
	if SaveManager.validate_tres_file(tres_path):
		var loaded_res = load(tres_path)
		if loaded_res != null and loaded_res is ElementDataResource and (loaded_res as ElementDataResource).elements.size() > 0:
			elem_res = loaded_res as ElementDataResource
		else:
			elem_res = ElementDataResource.new()
			elem_res._build_default_data()
	else:
		elem_res = ElementDataResource.new()
		elem_res._build_default_data()
	for i in range(elem_res.elements.size()):
		var elem: Dictionary = elem_res.elements[i]
		_element_data[i] = {
			"symbol": elem.get("symbol", "?"),
			"atomic_number": elem.get("atomic_number", 1),
			"mass": elem.get("mass", 1.0),
			"electronegativity": elem.get("electronegativity", 0.0),
			"covalent_radius": elem.get("covalent_radius", 0.5),
			"color": elem.get("color", Color.WHITE),
		}


func get_element_data() -> Dictionary:
	return _element_data


func get_atoms() -> Array[Node3D]:
	return _atoms


func get_bonds() -> Array[Node3D]:
	return _bonds


func get_wyckoff_markers() -> Array[Node3D]:
	return _wyckoff_markers


func set_domain(domain: String, mode: String) -> void:
	_current_domain = domain
	_current_construction_mode = mode


# 设置关卡元素数据并计算单元总质量，用于守恒矩阵归一化扰动
func set_level_elements(elements: Array) -> void:
	_total_cell_mass = 0.0
	_element_wyckoff_map.clear()
	for el in elements:
		if not el is Dictionary:
			continue
		var symbol: String = el.get("symbol", el.get("label", ""))
		var mult: int = el.get("wyckoff_multiplicity", el.get("multiplicity", el.get("count", 1)))
		var mass: float = 0.0
		var found_in_table: bool = false
		for i in _element_data:
			if _element_data[i]["symbol"] == symbol:
				mass = _element_data[i]["mass"]
				found_in_table = true
				break
		if not found_in_table and symbol != "":
			# Non-standard labels (PHASE_A, CA, etc.) — register them so
			# the auto-element-selection can still find them
			var new_idx: int = _element_data.size()
			_element_data[new_idx] = {
				"symbol": symbol,
				"atomic_number": 200 + new_idx,
				"mass": 1.0,
				"electronegativity": 0.0,
				"covalent_radius": 0.5,
				"color": Color.from_hsv(new_idx * 0.18, 0.7, 0.9),
			}
			mass = 1.0
		if mass == 0.0:
			mass = 1.0
		_total_cell_mass += mass * mult
		# Build Wyckoff→element map so we can auto-select the right element
		# Some level schemas use "wyckoff_label" instead of "wyckoff"
		var wyckoff: String = el.get("wyckoff", el.get("wyckoff_label", ""))
		if wyckoff != "" and symbol != "":
			var wnorm: String = _normalize_wyckoff_label(wyckoff)
			_element_wyckoff_map[wnorm] = symbol
	if _total_cell_mass == 0.0:
		_total_cell_mass = 1.0
	GameLogger.info("Conservation", "关卡单元总质量: %.4f (元素-Wyckoff映射: %d)" % [_total_cell_mass, _element_wyckoff_map.size()])


# 从 crystal_cell 获取晶格参数向量（a, b, c）
func _get_lattice_vector() -> Vector3:
	if crystal_cell and crystal_cell.has_method("get_lattice_params"):
		var lp: Dictionary = crystal_cell.get_lattice_params()
		return Vector3(float(lp.get("a", 5.0)), float(lp.get("b", 5.0)), float(lp.get("c", 5.0)))
	return Vector3(5.0, 5.0, 5.0)


# ---- Wyckoff标记 ----

func spawn_wyckoff_markers() -> void:
	clear_wyckoff_markers()

	if crystal_cell == null:
		return

	var raw = crystal_cell.call("get_wyckoff_positions")
	if raw == null or not (raw is Array):
		push_warning("crystal_cell 缺少 get_wyckoff_positions 方法或返回类型错误")
		return
	var wyckoff_positions := raw as Array

	for wp in wyckoff_positions:
		if not wp is Dictionary or not wp.has("positions"):
			continue
		var label: String = str(wp.get("label", ""))
		for raw_pos in wp["positions"]:
			if raw_pos is Array and raw_pos.size() >= 3:
				var frac_pos := Vector3(float(raw_pos[0]), float(raw_pos[1]), float(raw_pos[2]))
				# 直接用晶格参数转换，绕过有缺陷的 fractional_to_cartesian
				var cart_pos: Vector3 = frac_pos * _get_lattice_vector()

				var marker_scene := load("res://scripts/construction/wyckoff_marker.gd")
				var marker := MeshInstance3D.new()
				marker.set_script(marker_scene)
				marker.wyckoff_label = label
				# Show suggested element on marker as a hint for the player
				if _element_wyckoff_map.has(label):
					marker.element_hint = _element_wyckoff_map[label]
				elif _element_wyckoff_map.has(_normalize_wyckoff_label(label)):
					marker.element_hint = _element_wyckoff_map[_normalize_wyckoff_label(label)]
				marker.fractional_pos = frac_pos
				marker.position = cart_pos
				marker.marker_clicked.connect(_on_wyckoff_marker_clicked)
				marker.marker_hovered.connect(_on_wyckoff_marker_hovered)

				wyckoff_container.add_child(marker)
				_wyckoff_markers.append(marker)


func _on_wyckoff_marker_clicked(marker: Node) -> void:
	# 只在PLACE相关工具下放置原子
	match current_tool:
		0, 2, 5, 6, 7:  # PLACE, SOFT_MODE, BOND_BUILD, ASSEMBLE, PATH_BUILD
			place_atom_at_marker(marker)


func _on_wyckoff_marker_hovered(_marker: Node) -> void:
	pass


func on_wyckoff_marker_clicked(marker: Node, tool_type: int) -> void:
	match tool_type:
		0, 2, 5, 6, 7:  # PLACE, SOFT_MODE, BOND_BUILD, ASSEMBLE, PATH_BUILD
			place_atom_at_marker(marker)


# ---- 自由放置 (不依赖标记) ----

func place_atom_free(world_pos: Vector3) -> Node3D:
	if current_element_index >= _element_data.size():
		return null
	var elem: Dictionary = _element_data[current_element_index]

	# Check forbidden elements
	var forbidden: Array = LevelManager.current_level_data.get("forbidden_elements", [])
	if elem.get("symbol", "") in forbidden:
		SoundManager.play(SoundManager.SoundType.VERIFICATION_FAIL)
		return null

	# Compute fractional coords for the crystal cell
	var frac_pos: Vector3 = Vector3.ZERO
	if crystal_cell and crystal_cell.has_method("cartesian_to_fractional"):
		var raw = crystal_cell.call("cartesian_to_fractional", world_pos)
		if raw is Vector3:
			frac_pos = raw as Vector3
		else:
			frac_pos = world_pos / 5.0
	else:
		frac_pos = world_pos / 5.0

	var atom := _create_atom_node(elem, world_pos, frac_pos, "free")
	if atom == null:
		return null

	# Shared registration logic
	_register_atom(atom, elem, world_pos, "free")

	return atom


# Shared post-creation registration for both marker and free placement
func _register_atom(atom: Node3D, elem: Dictionary, cart_pos: Vector3, wyckoff_label: String) -> void:
	LevelManager.register_atom_placement(elem["symbol"], _normalize_wyckoff_label(wyckoff_label))
	TutorialManager.notify_action("atom_placed")

	# Sound: pitch rises with each placement
	var pitch := 0.8 + 0.05 * _atoms.size()
	if SoundManager.has_method("play_sfx"):
		SoundManager.play_sfx("atom_place", pitch)

	# Screen shake
	if camera and camera.has_method("shake"):
		camera.call("shake", 0.05, 0.05)

	# Conservation perturbation
	var mass_val: float = elem["mass"]
	var delta: float = mass_val / _total_cell_mass * _get_perturb_coeff()
	ConservationEngine.apply_perturbation(0, 0, delta, "place_%s_at_%s" % [elem["symbol"], wyckoff_label])

	ProofTree.add_node("place_%s_at_%s" % [elem["symbol"], wyckoff_label], null, {
		"element": elem["symbol"],
		"wyckoff": wyckoff_label,
		"mass": mass_val,
	})

	_check_fog_generation(atom)
	_try_auto_bond(atom)

	# Domain-specific registration
	if _current_domain == "device" or _current_construction_mode == "assembly":
		# 用元素符号作为组件名，让 assembly_check 目标可以直接用元素符号匹配
		LevelManager.register_assembly(elem["symbol"])
	elif _current_domain == "topology" or _current_construction_mode == "path_build":
		LevelManager.register_path_node({"element": elem["symbol"], "position": atom.get_meta("frac_pos", Vector3.ZERO)})
	elif _current_domain == "reaction":
		LevelManager.register_path_node({"element": elem["symbol"], "position": atom.get_meta("frac_pos", Vector3.ZERO), "wyckoff": wyckoff_label})

	MorphismSystem.apply_operation(
		MorphismSystem.MorphismCategory.MONOMORPHISM,
		["atom_count", "element_type"],
		[],
		["new_atom_%s" % elem["symbol"]]
	)

	# Notify construction canvas (triggers strain field, goal check, etc.)
	if _on_atom_placed_callback.is_valid():
		_on_atom_placed_callback.call(atom)

	atom.call("update_neighbor_visuals", _atoms)


# ---- 原子操作 ----

func place_atom_at_marker(marker: Node) -> Node3D:
	# In play mode, players choose elements themselves.
	# The _element_wyckoff_map is used for hint display only.
	# E2E test sets _auto_select_element=true for backward compat.
	var raw_label: String = marker.wyckoff_label
	var norm_label: String = _normalize_wyckoff_label(raw_label)
	if _auto_select_element:
		var target_sym: String = ""
		if _element_wyckoff_map.has(raw_label):
			target_sym = _element_wyckoff_map[raw_label]
		elif _element_wyckoff_map.has(norm_label):
			target_sym = _element_wyckoff_map[norm_label]
		if target_sym != "":
			for i in _element_data:
				if _element_data[i]["symbol"] == target_sym:
					current_element_index = i
					break

	if current_element_index >= _element_data.size():
		return null

	var elem: Dictionary = _element_data[current_element_index]

	# 约束反转：检查当前元素是否被禁止
	var forbidden: Array = LevelManager.current_level_data.get("forbidden_elements", [])
	if elem.get("symbol", "") in forbidden:
		SoundManager.play(SoundManager.SoundType.VERIFICATION_FAIL)
		GameLogger.warning("AtomPlacement", "元素 %s 在本关被禁止" % elem.get("symbol", ""))
		return null

	var cart_pos: Vector3 = marker.global_position
	var frac_pos: Vector3 = marker.fractional_pos

	var atom := _create_atom_node(elem, cart_pos, frac_pos, marker.wyckoff_label)

	# Marker-specific: lock the marker
	marker.call("play_lock_animation")
	marker.call("set_filled", true)

	# Track Wyckoff fill count for lock animation
	var wlabel: String = marker.wyckoff_label
	if not _wyckoff_fill_counts.has(wlabel):
		_wyckoff_fill_counts[wlabel] = 0
	_wyckoff_fill_counts[wlabel] += 1

	# Soft mode uses different sound
	if current_tool == 2 and SoundManager.has_method("play_sfx"):
		SoundManager.play_sfx("soft_mode_lock", 0.8 + 0.05 * _wyckoff_fill_counts[wlabel])

	# Shared registration (conservation, bonds, goals, etc.)
	_register_atom(atom, elem, cart_pos, wlabel)

	_check_wyckoff_lock(marker.wyckoff_label)

	atom.call("update_neighbor_visuals", _atoms)

	return atom


func _create_atom_node(elem: Dictionary, cart_pos: Vector3, frac_pos: Vector3, wyckoff_label: String) -> Node3D:
	var atom_script := load("res://scripts/construction/atom_node.gd")
	var atom: MeshInstance3D
	var from_pool := false
	if _atom_pool != null and is_instance_valid(_atom_pool) and _atom_pool.get_pool_size() > 0:
		atom = _atom_pool.acquire() as MeshInstance3D
		from_pool = true
	else:
		atom = MeshInstance3D.new()

	# Always detach from current parent before re-adding
	if atom.get_parent() != null:
		atom.get_parent().remove_child(atom)

	# 只有新节点才设置脚本和连接信号, 避免对象池节点重复连接
	if not from_pool:
		atom.set_script(atom_script)
		atom.atom_clicked.connect(_on_atom_clicked_callback)
		atom.atom_state_changed.connect(_on_atom_state_changed_callback)
	elif atom.atom_clicked.get_connections().is_empty():
		atom.atom_clicked.connect(_on_atom_clicked_callback)
		atom.atom_state_changed.connect(_on_atom_state_changed_callback)

	atom.element_symbol = elem["symbol"]
	atom.atomic_number = elem["atomic_number"]
	atom.fractional_position = frac_pos
	atom.wyckoff_label = wyckoff_label
	atom.position = cart_pos

	atoms_container.add_child(atom)

	var radius := elem["covalent_radius"] as float
	var visual_radius := maxf(radius * 0.5, 0.15)
	atom.call("set_element", elem["symbol"], elem["atomic_number"], elem["color"], visual_radius)

	# 微奖励: 播放弹入动画
	atom.call("play_spawn_animation")

	_atoms.append(atom)
	return atom


func substitute_atom(atom: Node) -> Dictionary:
	if current_element_index >= _element_data.size():
		return {}

	var old_symbol: String = atom.element_symbol
	var new_elem: Dictionary = _element_data[current_element_index]
	var old_idx: int = _find_element_index(old_symbol)
	var result := _substitute_atom_to(atom, new_elem)
	atom_substituted.emit(atom, old_idx, current_element_index)
	return {
		"old_symbol": old_symbol,
		"old_element_index": old_idx,
		"new_element_index": current_element_index,
		"mass_delta": result.get("mass_delta", 0.0),
	}


func substitute_atom_to(atom: Node, target_element_index: int) -> Dictionary:
	if target_element_index < 0 or target_element_index >= _element_data.size():
		return {}
	var old_symbol: String = atom.element_symbol
	var target_elem: Dictionary = _element_data[target_element_index]
	var old_idx: int = _find_element_index(old_symbol)
	var result := _substitute_atom_to(atom, target_elem)
	atom_substituted.emit(atom, old_idx, target_element_index)
	return {
		"old_symbol": old_symbol,
		"old_element_index": old_idx,
		"new_element_index": target_element_index,
		"mass_delta": result.get("mass_delta", 0.0),
	}


func _find_element_index(symbol: String) -> int:
	for i in _element_data:
		if _element_data[i]["symbol"] == symbol:
			return i
	return -1


func _substitute_atom_to(atom: Node, new_elem: Dictionary) -> Dictionary:
	var old_symbol: String = atom.element_symbol
	var old_elem_idx: int = _find_element_index(old_symbol)
	var old_mass: float = float(_element_data.get(old_elem_idx, {}).get("mass", 0.0))

	var mass_delta: float = (float(new_elem["mass"]) - old_mass) / _total_cell_mass * _get_perturb_coeff()
	ConservationEngine.apply_perturbation(0, 0, mass_delta, "substitute_%s_to_%s" % [old_symbol, new_elem["symbol"]])

	var radius: float = float(new_elem["covalent_radius"])
	var visual_radius := maxf(radius * 0.5, 0.15)
	atom.call("set_element", new_elem["symbol"], new_elem["atomic_number"], new_elem["color"], visual_radius)

	SoundManager.play(SoundManager.SoundType.CLICK_LOCK)

	var kept: Array[String] = ["position", "wyckoff"]
	var lost: Array[String] = []
	var introduced: Array[String] = ["element_%s" % new_elem["symbol"]]

	if old_mass != new_elem["mass"]:
		lost.append("mass_conservation")

	MorphismSystem.apply_operation(
		MorphismSystem.MorphismCategory.HOMOMORPHISM,
		kept, lost, introduced
	)

	ProofTree.add_node("substitute_%s_to_%s" % [old_symbol, new_elem["symbol"]], null, {
		"old": old_symbol,
		"new": new_elem["symbol"],
		"mass_delta": mass_delta,
	})

	return {"mass_delta": mass_delta}


func delete_atom(atom: Node) -> Dictionary:
	var elem_symbol: String = atom.element_symbol
	var wyckoff_lbl: String = atom.wyckoff_label
	var frac_pos: Vector3 = atom.fractional_position
	var element_index: int = _find_element_index(elem_symbol)

	SoundManager.play(SoundManager.SoundType.ATOM_REMOVE)
	LevelManager.unregister_atom_placement(elem_symbol, _normalize_wyckoff_label(wyckoff_lbl))

	var mass: float = 0.0
	for i in _element_data:
		if _element_data[i]["symbol"] == elem_symbol:
			mass = _element_data[i]["mass"]
			break

	ConservationEngine.apply_perturbation(0, 0, -mass / _total_cell_mass * _get_perturb_coeff(), "delete_%s" % elem_symbol)
	_remove_bonds_for_atom(atom)
	_restore_wyckoff_marker(atom.fractional_position)

	MorphismSystem.apply_operation(
		MorphismSystem.MorphismCategory.EPIMORPHISM,
		["structure"],
		["element_%s" % elem_symbol],
		[]
	)

	ProofTree.add_node("delete_%s" % elem_symbol, null, {
		"element": elem_symbol,
	})

	_atoms.erase(atom)
	if selected_atom == atom:
		selected_atom = null

	if _atom_pool != null and is_instance_valid(_atom_pool):
		_atom_pool.release(atom)
	else:
		atom.queue_free()

	return {
		"element_symbol": elem_symbol,
		"element_index": element_index,
		"wyckoff_label": wyckoff_lbl,
		"fractional_position": frac_pos,
		"mass": mass,
	}


func restore_atom(atom_data: Dictionary) -> Node3D:
	var element_index: int = atom_data.get("element_index", -1)
	if element_index < 0 or element_index >= _element_data.size():
		return null

	var elem: Dictionary = _element_data[element_index]
	var wyckoff_lbl: String = atom_data.get("wyckoff_label", "")
	var frac_pos: Vector3 = atom_data.get("fractional_position", Vector3.ZERO)
	var cart_pos: Vector3 = Vector3.ZERO
	if crystal_cell != null:
		var raw_cart = crystal_cell.call("fractional_to_cartesian", frac_pos)
		if raw_cart is Vector3:
			cart_pos = raw_cart

	var atom := _create_atom_node(elem, cart_pos, frac_pos, wyckoff_lbl)

	# 找到对应 marker 并标记为已填充
	for marker in _wyckoff_markers:
		if not is_instance_valid(marker):
			continue
		if marker.wyckoff_label == wyckoff_lbl and marker.fractional_pos.distance_to(frac_pos) < 0.01:
			marker.call("set_filled", true)
			break

	# 更新填充计数
	if not _wyckoff_fill_counts.has(wyckoff_lbl):
		_wyckoff_fill_counts[wyckoff_lbl] = 0
	_wyckoff_fill_counts[wyckoff_lbl] += 1

	LevelManager.register_atom_placement(elem["symbol"], _normalize_wyckoff_label(wyckoff_lbl))
	ConservationEngine.apply_perturbation(0, 0, elem["mass"] / _total_cell_mass * _get_perturb_coeff(), "restore_%s_at_%s" % [elem["symbol"], wyckoff_lbl])
	_try_auto_bond(atom)

	atom.call("update_neighbor_visuals", _atoms)

	return atom


func select_atom(atom: Node) -> void:
	if selected_atom and is_instance_valid(selected_atom):
		selected_atom.call("set_state", 0)
	selected_atom = atom
	atom.call("set_state", 1)
	# 通知教程系统玩家选择了原子
	TutorialManager.notify_action("select_atom")


# ---- Wyckoff锁定检查 ----

func _check_wyckoff_lock(wyckoff_label: String) -> void:
	# 检查该Wyckoff位置的所有等效点是否都已填满
	var marker_count := 0
	var filled_count := 0
	var atoms_in_position: Array[Node3D] = []
	var markers_in_position: Array[Node3D] = []

	for marker in _wyckoff_markers:
		if not is_instance_valid(marker):
			continue
		if marker.wyckoff_label == wyckoff_label:
			marker_count += 1
			markers_in_position.append(marker)
			if marker.is_filled:
				filled_count += 1

	# 收集该Wyckoff位置上的原子
	for atom in _atoms:
		if is_instance_valid(atom) and atom.wyckoff_label == wyckoff_label:
			atoms_in_position.append(atom)

	# 所有等效点都填满时触发锁定动画
	if marker_count > 0 and filled_count >= marker_count:
		for atom in atoms_in_position:
			atom.call("play_lock_animation")
		# 标记锁定动画: 缩小+淡出+粒子
		for marker in markers_in_position:
			marker.call("play_lock_animation")


# ---- 键管理 ----

func _try_auto_bond(atom: Node) -> void:
	# bond_build 模式需要玩家手动成键，自动成键会干扰目标验证
	if _current_construction_mode == "bond_build":
		return
	var atom_pos: Vector3 = atom.global_position
	var elem_data: Dictionary = _get_element_data_for_atom(atom)
	if elem_data.is_empty():
		return

	# 只与最近的4个邻居成键，避免高密度结构产生海量键
	var candidates: Array = []
	for other_atom in _atoms:
		if other_atom == atom or not is_instance_valid(other_atom):
			continue
		var dist: float = atom_pos.distance_to(other_atom.global_position)
		if dist < 2.5 and dist > 0.3:
			candidates.append({"atom": other_atom, "dist": dist})

	# 按距离排序，只取最近的4个
	candidates.sort_custom(func(a, b): return a["dist"] < b["dist"])
	var max_bonds: int = mini(candidates.size(), 4)
	for i in range(max_bonds):
		_create_bond(atom, candidates[i]["atom"])


func _create_bond(atom_a: Node3D, atom_b: Node3D, type: int = 0) -> Node3D:
	var bond_script := load("res://scripts/construction/bond_renderer.gd")
	var bond: MeshInstance3D
	if _bond_pool != null and is_instance_valid(_bond_pool) and _bond_pool.get_pool_size() > 0:
		bond = _bond_pool.acquire() as MeshInstance3D
	else:
		bond = MeshInstance3D.new()
	bond.set_script(bond_script)
	bond.call("set_atoms", atom_a, atom_b, type)
	if bond.has_signal("bond_broken") and not bond.bond_broken.is_connected(_on_bond_broken):
		bond.bond_broken.connect(_on_bond_broken)

	# Pool-acquired bonds may still have a parent from a previous life cycle
	if bond.get_parent() != null:
		bond.get_parent().remove_child(bond)
	bonds_container.add_child(bond)
	_bonds.append(bond)

	# Always register bonds with LevelManager — goal checking needs them
	# regardless of construction mode (bond_check/bond_build goals exist in many modes)
	var sym_a: String = atom_a.get("element_symbol") if atom_a.get("element_symbol") != null else ""
	var sym_b: String = atom_b.get("element_symbol") if atom_b.get("element_symbol") != null else ""
	if sym_a != "" and sym_b != "":
		LevelManager.register_bond(sym_a, sym_b)

	# 通知教程系统玩家完成了成键动作
	TutorialManager.notify_action("bond_created")

	return bond


func _remove_bonds_for_atom(atom: Node3D) -> void:
	var to_remove: Array[Node3D] = []
	for bond in _bonds:
		if not is_instance_valid(bond):
			continue
		var a = bond.atom_a
		var b = bond.atom_b
		if a == atom or b == atom:
			to_remove.append(bond)

	for bond in to_remove:
		_bonds.erase(bond)
		# Return to pool if available, otherwise free
		if _bond_pool != null and is_instance_valid(_bond_pool):
			if bond.has_signal("bond_broken") and bond.bond_broken.is_connected(_on_bond_broken):
				bond.bond_broken.disconnect(_on_bond_broken)
			bond.call("set_atoms", null, null, 0) if bond.has_method("set_atoms") else null
			_bond_pool.release(bond)
		else:
			bond.queue_free()


func _on_bond_broken(bond: Node) -> void:
	_bonds.erase(bond)


func _get_element_data_for_atom(atom: Node) -> Dictionary:
	var sym: String = atom.element_symbol
	for i in _element_data:
		if _element_data[i]["symbol"] == sym:
			return _element_data[i]
	return {}


func _restore_wyckoff_marker(frac_pos: Vector3) -> void:
	for marker in _wyckoff_markers:
		if not is_instance_valid(marker):
			continue
		var marker_frac: Vector3 = marker.fractional_pos
		if marker_frac.distance_to(frac_pos) < 0.01:
			marker.call("set_filled", false)
			break


func _check_fog_generation(atom: Node) -> void:
	var dev_summary: Dictionary = ConservationEngine.get_deviation_summary()
	var charge_dev: float = dev_summary.get("charge", {}).get("deviation", 0.0)

	if charge_dev > 0.2 and randf() < 0.3:
		var fog_type := FogSystem.FogType.SEMI_DECIDABLE
		if charge_dev > 0.5:
			fog_type = FogSystem.FogType.UNDECIDABLE
		FogSystem.create_fog(fog_type, atom.global_position, 1.5, {"source": "charge_deviation"})


func _get_component_for_position(frac_pos: Vector3) -> String:
	if frac_pos.x < 0.33:
		return "cathode"
	elif frac_pos.x < 0.66:
		return "electrolyte"
	else:
		return "anode"


func clear_structure() -> void:
	# 回收到对象池或直接释放
	if _atom_pool != null and is_instance_valid(_atom_pool):
		for atom in _atoms:
			if is_instance_valid(atom):
				_atom_pool.release(atom)
	else:
		for atom in _atoms:
			if is_instance_valid(atom):
				atom.queue_free()
	_atoms.clear()

	if _bond_pool != null and is_instance_valid(_bond_pool):
		for bond in _bonds:
			if is_instance_valid(bond):
				_bond_pool.release(bond)
	else:
		for bond in _bonds:
			if is_instance_valid(bond):
				bond.queue_free()
	_bonds.clear()

	# Free all wyckoff markers — they'll be regenerated for the new level
	clear_wyckoff_markers()

	ConservationEngine.reset()


func clear_wyckoff_markers() -> void:
	# Remove all placement markers. Uses queue_free for safety —
	# the fallback check in construction_canvas filters with is_queued_for_deletion().
	for m in _wyckoff_markers:
		if m != null and is_instance_valid(m):
			# Disconnect signals to prevent callbacks on a dying node
			if m.has_signal("marker_clicked") and m.marker_clicked.is_connected(_on_wyckoff_marker_clicked):
				m.marker_clicked.disconnect(_on_wyckoff_marker_clicked)
			if m.has_signal("marker_hovered") and m.marker_hovered.is_connected(_on_wyckoff_marker_hovered):
				m.marker_hovered.disconnect(_on_wyckoff_marker_hovered)
			m.queue_free()
	_wyckoff_markers.clear()


func spawn_free_placement_grid(lattice_params: Vector3) -> void:
	clear_wyckoff_markers()

	if crystal_cell == null:
		return

	var grid_size := 3
	for ix in range(grid_size):
		for iy in range(grid_size):
			for iz in range(grid_size):
				var frac_pos := Vector3(
					float(ix) / float(grid_size),
					float(iy) / float(grid_size),
					float(iz) / float(grid_size)
				)
				var cart_pos: Vector3 = crystal_cell.call("fractional_to_cartesian", frac_pos)

				var marker_scene := load("res://scripts/construction/wyckoff_marker.gd")
				var marker := MeshInstance3D.new()
				marker.set_script(marker_scene)
				marker.wyckoff_label = "free_%d_%d_%d" % [ix, iy, iz]
				marker.fractional_pos = frac_pos
				marker.position = cart_pos
				marker.marker_clicked.connect(_on_wyckoff_marker_clicked)
				marker.marker_hovered.connect(_on_wyckoff_marker_hovered)

				wyckoff_container.add_child(marker)
				_wyckoff_markers.append(marker)


func spawn_mesh_grid(lattice_params: Vector3) -> void:
	clear_wyckoff_markers()

	if crystal_cell == null:
		return

	var grid_size := 4
	for ix in range(grid_size):
		for iy in range(grid_size):
			for iz in range(grid_size):
				var frac_pos := Vector3(
					float(ix) / float(grid_size),
					float(iy) / float(grid_size),
					float(iz) / float(grid_size)
				)
				var cart_pos: Vector3 = crystal_cell.call("fractional_to_cartesian", frac_pos)

				var marker_scene := load("res://scripts/construction/wyckoff_marker.gd")
				var marker := MeshInstance3D.new()
				marker.set_script(marker_scene)
				marker.wyckoff_label = "mesh_%d_%d_%d" % [ix, iy, iz]
				marker.fractional_pos = frac_pos
				marker.position = cart_pos
				marker.marker_clicked.connect(_on_wyckoff_marker_clicked)
				marker.marker_hovered.connect(_on_wyckoff_marker_hovered)

				wyckoff_container.add_child(marker)
				_wyckoff_markers.append(marker)


func spawn_free_marker(world_pos: Vector3, label: String, frac_pos: Vector3 = Vector3.ZERO) -> Node:
	# Spawn a single placement marker at a world position.
	# Used as fallback when a level has no Wyckoff data.
	var marker_scene := load("res://scripts/construction/wyckoff_marker.gd")
	var marker := MeshInstance3D.new()
	marker.set_script(marker_scene)
	marker.wyckoff_label = label
	marker.fractional_pos = frac_pos
	marker.position = world_pos
	marker.marker_clicked.connect(_on_wyckoff_marker_clicked)
	marker.marker_hovered.connect(_on_wyckoff_marker_hovered)
	wyckoff_container.add_child(marker)
	_wyckoff_markers.append(marker)
	return marker


func spawn_reaction_workspace(lattice_params: Vector3) -> void:
	clear_wyckoff_markers()

	if crystal_cell == null:
		return

	var reactant_positions := [
		Vector3(0.2, 0.5, 0.5),
		Vector3(0.3, 0.5, 0.5),
	]
	var product_positions := [
		Vector3(0.7, 0.5, 0.5),
		Vector3(0.8, 0.5, 0.5),
	]
	var intermediate_positions := [
		Vector3(0.4, 0.5, 0.5),
		Vector3(0.5, 0.5, 0.5),
		Vector3(0.6, 0.5, 0.5),
	]

	var all_positions: Array[Vector3] = []
	all_positions.append_array(reactant_positions)
	all_positions.append_array(product_positions)
	all_positions.append_array(intermediate_positions)

	for idx in range(all_positions.size()):
		var frac_pos := all_positions[idx]
		var cart_pos: Vector3 = crystal_cell.call("fractional_to_cartesian", frac_pos)

		var marker_scene := load("res://scripts/construction/wyckoff_marker.gd")
		var marker := MeshInstance3D.new()
		marker.set_script(marker_scene)
		marker.wyckoff_label = "rxn_%d" % idx
		marker.fractional_pos = frac_pos
		marker.position = cart_pos
		marker.marker_clicked.connect(_on_wyckoff_marker_clicked)
		marker.marker_hovered.connect(_on_wyckoff_marker_hovered)

		wyckoff_container.add_child(marker)
		_wyckoff_markers.append(marker)


# ---- 微奖励: 屏幕震动 ----

func _screen_shake(amplitude: float, duration: float) -> void:
	if camera == null:
		return
	var orig_h := camera.h_offset
	var orig_v := camera.v_offset
	var shake_tween := camera.create_tween()
	shake_tween.tween_property(camera, "h_offset", orig_h + randf_range(-amplitude, amplitude), duration * 0.5)
	shake_tween.tween_property(camera, "h_offset", orig_h, duration * 0.5)
	var shake_tween_v := camera.create_tween()
	shake_tween_v.tween_property(camera, "v_offset", orig_v + randf_range(-amplitude, amplitude), duration * 0.5)
	shake_tween_v.tween_property(camera, "v_offset", orig_v, duration * 0.5)
