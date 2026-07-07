# neighbor_visuals_test.gd
# GdUnit4 测试: AtomNode 邻接感知渲染

extends GdUnitTestSuite

const __source = "res://scripts/construction/atom_node.gd"

var _atom = null

func before() -> void:
	_atom = load(__source).new()
	# 需要添加到场景树才能调用 global_position
	add_child(_atom)

func after() -> void:
	if _atom != null:
		remove_child(_atom)
		_atom.free()
		_atom = null

func test_no_neighbors_resets_emission() -> void:
	var empty_neighbors: Array[Node3D] = []
	_atom.update_neighbor_visuals(empty_neighbors)
	var mat = _atom.get_surface_override_material(0)
	if mat is StandardMaterial3D:
		assert_bool(mat.emission_enabled).is_false()

func test_bonding_neighbor_enables_emission() -> void:
	var neighbor = load(__source).new()
	add_child(neighbor)
	neighbor.position = Vector3(0.1, 0, 0)  # 极近距离，在 bonding 阈值内
	_atom.position = Vector3.ZERO
	var neighbors1: Array[Node3D] = [neighbor]
	_atom.update_neighbor_visuals(neighbors1)
	var mat = _atom.get_surface_override_material(0)
	if mat is StandardMaterial3D:
		assert_bool(mat.emission_enabled).is_true()
	remove_child(neighbor)
	neighbor.free()

func test_distant_neighbor_no_bonding() -> void:
	var neighbor = load(__source).new()
	add_child(neighbor)
	neighbor.position = Vector3(10.0, 0, 0)  # 极远距离
	_atom.position = Vector3.ZERO
	var neighbors1: Array[Node3D] = [neighbor]
	_atom.update_neighbor_visuals(neighbors1)
	var mat = _atom.get_surface_override_material(0)
	if mat is StandardMaterial3D:
		assert_bool(mat.emission_enabled).is_false()
	remove_child(neighbor)
	neighbor.free()
