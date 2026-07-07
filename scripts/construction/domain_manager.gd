# domain_manager.gd
# 域管理器 - 处理不同物理域的场景配置
extends RefCounted

var _atom_manager: RefCounted  # AtomPlacementManager
var crystal_cell: Node3D


func _init(atom_manager: RefCounted, cell: Node3D) -> void:
	_atom_manager = atom_manager
	crystal_cell = cell


func setup_domain(domain: String, sg_num: int, lattice_params: Vector3, lattice_angles: Vector3) -> void:
	match domain:
		"crystal":
			_setup_crystal_domain(sg_num, lattice_params, lattice_angles)
		"molecular":
			_setup_molecular_domain(sg_num, lattice_params, lattice_angles)
		"fluid":
			_setup_fluid_domain(sg_num, lattice_params, lattice_angles)
		"device":
			_setup_device_domain(sg_num, lattice_params, lattice_angles)
		"reaction":
			_setup_reaction_domain(sg_num, lattice_params, lattice_angles)
		"topology":
			_setup_topology_domain(sg_num, lattice_params, lattice_angles)
		"open":
			_setup_open_domain(sg_num, lattice_params, lattice_angles)
		_:
			_setup_crystal_domain(sg_num, lattice_params, lattice_angles)


func _setup_crystal_domain(sg_num: int, lattice_params: Vector3, lattice_angles: Vector3) -> void:
	if crystal_cell:
		crystal_cell.call("set_space_group", sg_num)
		crystal_cell.call("set_lattice_params",
			lattice_params.x, lattice_params.y, lattice_params.z,
			lattice_angles.x, lattice_angles.y, lattice_angles.z)
		_atom_manager.spawn_wyckoff_markers()


func _setup_molecular_domain(sg_num: int, lattice_params: Vector3, lattice_angles: Vector3) -> void:
	if crystal_cell:
		crystal_cell.call("set_space_group", sg_num)
		crystal_cell.call("set_lattice_params",
			lattice_params.x, lattice_params.y, lattice_params.z,
			lattice_angles.x, lattice_angles.y, lattice_angles.z)
	# 分子域不在这里建标记 — 让 construction_canvas 的 fallback 逻辑
	# 从 elements 数据生成带正确 wyckoff 标签的标记


func _setup_fluid_domain(sg_num: int, lattice_params: Vector3, lattice_angles: Vector3) -> void:
	if crystal_cell:
		crystal_cell.call("set_space_group", sg_num)
		crystal_cell.call("set_lattice_params",
			lattice_params.x, lattice_params.y, lattice_params.z,
			lattice_angles.x, lattice_angles.y, lattice_angles.z)
	_atom_manager.spawn_mesh_grid(lattice_params)


func _setup_device_domain(sg_num: int, lattice_params: Vector3, lattice_angles: Vector3) -> void:
	if crystal_cell:
		crystal_cell.call("set_space_group", sg_num)
		crystal_cell.call("set_lattice_params",
			lattice_params.x, lattice_params.y, lattice_params.z,
			lattice_angles.x, lattice_angles.y, lattice_angles.z)
		_atom_manager.spawn_wyckoff_markers()


func _setup_reaction_domain(sg_num: int, lattice_params: Vector3, lattice_angles: Vector3) -> void:
	if crystal_cell:
		crystal_cell.call("set_space_group", sg_num)
		crystal_cell.call("set_lattice_params",
			lattice_params.x, lattice_params.y, lattice_params.z,
			lattice_angles.x, lattice_angles.y, lattice_angles.z)
	_atom_manager.spawn_reaction_workspace(lattice_params)


func _setup_topology_domain(sg_num: int, lattice_params: Vector3, lattice_angles: Vector3) -> void:
	if crystal_cell:
		crystal_cell.call("set_space_group", sg_num)
		crystal_cell.call("set_lattice_params",
			lattice_params.x, lattice_params.y, lattice_params.z,
			lattice_angles.x, lattice_angles.y, lattice_angles.z)
		_atom_manager.spawn_wyckoff_markers()


func _setup_open_domain(sg_num: int, lattice_params: Vector3, lattice_angles: Vector3) -> void:
	if crystal_cell:
		crystal_cell.call("set_space_group", sg_num)
		crystal_cell.call("set_lattice_params",
			lattice_params.x, lattice_params.y, lattice_params.z,
			lattice_angles.x, lattice_angles.y, lattice_angles.z)
		_atom_manager.spawn_wyckoff_markers()
