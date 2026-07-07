# voxel_stamp_renderer.gd
# Voxel Stamp 系统 - 将自定义形状定义渲染为 3D MeshInstance
#
# 支持: box, cylinder, sphere, cable (线/绳)
# 通过 element_data_resource.gd 中的 custom_shape 字段定义

extends MeshInstance3D
class_name VoxelStampRenderer

# 形状定义: Array[Dictionary]
# 每个 Dictionary: {"type": "box|cylinder|sphere|cable", "material": Color, "size": Vector3, "position": Vector3}
var _parts: Array[Dictionary] = []
var _stamp_material: StandardMaterial3D

func _init() -> void:
	_stamp_material = StandardMaterial3D.new()
	_stamp_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_stamp_material.metallic = 0.3
	_stamp_material.roughness = 0.5

func set_parts(parts: Array[Dictionary]) -> void:
	_parts = parts.duplicate(true)
	_rebuild_mesh()

func _rebuild_mesh() -> void:
	if _parts.is_empty():
		return

	var array_mesh := ArrayMesh.new()
	var surface_tool := SurfaceTool.new()

	for part in _parts:
		var ptype: String = part.get("type", "box")
		var ppos: Vector3 = part.get("position", Vector3.ZERO)
		var psize: Vector3 = part.get("size", Vector3.ONE)
		var pcolor: Color = part.get("color", Color.WHITE)
		var radius: float = part.get("radius", 0.5)
		var height: float = part.get("height", 1.0)

		surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		match ptype:
			"box":
				_add_box(surface_tool, ppos, psize, pcolor)
			"cylinder":
				_add_cylinder(surface_tool, ppos, radius, height, pcolor)
			"sphere":
				_add_sphere(surface_tool, ppos, radius, pcolor)
			"cable":
				_add_cable(surface_tool, ppos, part.get("end", ppos + Vector3.UP), radius, pcolor)
			_:
				_add_box(surface_tool, ppos, psize, pcolor)

		var part_mesh := surface_tool.commit()
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, part_mesh.surface_get_arrays(0))

	mesh = array_mesh
	# 一个 stamp 可能由多个 part 拼出多个 surface，全部覆盖到
	for s in range(mesh.get_surface_count()):
		set_surface_override_material(s, _stamp_material)

func _add_box(st: SurfaceTool, pos: Vector3, size: Vector3, color: Color) -> void:
	var half := size * 0.5
	var vertices := [
		pos + Vector3(-half.x, -half.y, -half.z), pos + Vector3(half.x, -half.y, -half.z), pos + Vector3(half.x, half.y, -half.z), pos + Vector3(-half.x, half.y, -half.z),
		pos + Vector3(-half.x, -half.y, half.z), pos + Vector3(half.x, -half.y, half.z), pos + Vector3(half.x, half.y, half.z), pos + Vector3(-half.x, half.y, half.z),
	]
	var normals := [
		Vector3(0, 0, -1), Vector3(0, 0, -1), Vector3(0, 0, -1), Vector3(0, 0, -1),
		Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1),
	]
	var faces := [
		[0, 1, 2], [0, 2, 3], # front
		[4, 6, 5], [4, 7, 6], # back
		[0, 5, 1], [0, 4, 5], # bottom
		[2, 6, 7], [2, 7, 3], # top
		[0, 3, 7], [0, 7, 4], # left
		[1, 6, 2], [1, 5, 6], # right
	]
	for f in faces:
		for i in f:
			st.set_color(color)
			st.set_normal(normals[i % 4])
			st.add_vertex(vertices[i])
	st.generate_normals()

func _add_cylinder(st: SurfaceTool, pos: Vector3, radius: float, height: float, color: Color) -> void:
	var segments := 16
	var half_h := height * 0.5
	for i in range(segments):
		var angle1 := float(i) / segments * TAU
		var angle2 := float(i + 1) / segments * TAU
		var p1 := pos + Vector3(cos(angle1) * radius, -half_h, sin(angle1) * radius)
		var p2 := pos + Vector3(cos(angle2) * radius, -half_h, sin(angle2) * radius)
		var p3 := pos + Vector3(cos(angle2) * radius, half_h, sin(angle2) * radius)
		var p4 := pos + Vector3(cos(angle1) * radius, half_h, sin(angle1) * radius)
		var n1 := Vector3(cos(angle1), 0, sin(angle1))
		var n2 := Vector3(cos(angle2), 0, sin(angle2))
		for p in [p1, p2, p3, p1, p3, p4]:
			st.set_color(color)
			st.set_normal(n1 if p == p1 or p == p4 else n2)
			st.add_vertex(p)
	st.generate_normals()

func _add_sphere(st: SurfaceTool, pos: Vector3, radius: float, color: Color) -> void:
	var lat := 8
	var lon := 16
	for i in range(lat):
		for j in range(lon):
			var theta1 := float(i) / lat * PI
			var theta2 := float(i + 1) / lat * PI
			var phi1 := float(j) / lon * TAU
			var phi2 := float(j + 1) / lon * TAU
			var p1 := pos + Vector3(sin(theta1) * cos(phi1), cos(theta1), sin(theta1) * sin(phi1)) * radius
			var p2 := pos + Vector3(sin(theta2) * cos(phi1), cos(theta2), sin(theta2) * sin(phi1)) * radius
			var p3 := pos + Vector3(sin(theta2) * cos(phi2), cos(theta2), sin(theta2) * sin(phi2)) * radius
			var p4 := pos + Vector3(sin(theta1) * cos(phi2), cos(theta1), sin(theta1) * sin(phi2)) * radius
			var n1 := (p1 - pos).normalized()
			var n2 := (p2 - pos).normalized()
			var n3 := (p3 - pos).normalized()
			var n4 := (p4 - pos).normalized()
			for vtx in [p1, p2, p3, p1, p3, p4]:
				var n := n1 if vtx == p1 or vtx == p4 else (n2 if vtx == p2 else n3)
				st.set_color(color)
				st.set_normal(n)
				st.add_vertex(vtx)
	st.generate_normals()

func _add_cable(st: SurfaceTool, start: Vector3, end: Vector3, radius: float, color: Color) -> void:
	var segments := 8
	var direction := (end - start).normalized()
	var length := start.distance_to(end)
	var up := Vector3.UP if abs(direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var right := direction.cross(up).normalized()
	up = right.cross(direction).normalized()
	for i in range(segments):
		var t1 := float(i) / segments
		var t2 := float(i + 1) / segments
		var c1 := start + direction * length * t1
		var c2 := start + direction * length * t2
		for j in range(4):
			var angle1 := float(j) / 4.0 * TAU
			var angle2 := float(j + 1) / 4.0 * TAU
			var r1 := right * cos(angle1) * radius + up * sin(angle1) * radius
			var r2 := right * cos(angle2) * radius + up * sin(angle2) * radius
			var p1 := c1 + r1
			var p2 := c1 + r2
			var p3 := c2 + r2
			var p4 := c2 + r1
			for vtx in [p1, p2, p3, p1, p3, p4]:
				st.set_color(color)
				st.add_vertex(vtx)
	st.generate_normals()
