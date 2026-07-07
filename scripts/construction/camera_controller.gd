# camera_controller.gd
# 相机轨道控制器 - 处理旋转/平移/缩放/聚焦
extends RefCounted

enum ScaleLevel { ANGSTROM, NANOMETER, MICROMETER }

const SCALE_DISTANCES: Array[float] = [18.0, 50.0, 120.0]
const SCALE_LABELS: Array[String] = ["Å", "nm", "μm"]

var camera: Camera3D
var _orbiting_left: bool = false
var _orbiting_right: bool = false
var _panning: bool = false
var _orbit_start: Vector2 = Vector2.ZERO
var _pan_start: Vector2 = Vector2.ZERO
var _camera_yaw: float = 45.0
var _camera_pitch: float = 30.0
var _camera_distance: float = 18.0
var _camera_target: Vector3 = Vector3.ZERO
var current_scale: ScaleLevel = ScaleLevel.ANGSTROM


func _init(cam: Camera3D) -> void:
	camera = cam


func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# 右键拖拽旋转视角
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_orbiting_right = true
				_orbit_start = event.position
			else:
				_orbiting_right = false

		# 中键平移
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_panning = true
				_pan_start = event.position
			else:
				_panning = false

		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera_distance = maxf(_camera_distance - 1.5, 3.0)
			update_transform()
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera_distance = minf(_camera_distance + 1.5, 200.0)
			update_transform()

	elif event is InputEventMouseMotion:
		if _orbiting_left or _orbiting_right:
			var delta: Vector2 = event.position - _orbit_start
			_camera_yaw -= delta.x * 0.2
			_camera_pitch = clampf(_camera_pitch + delta.y * 0.2, -89.0, 89.0)
			_orbit_start = event.position
			update_transform()

		if _panning:
			var delta: Vector2 = event.position - _pan_start
			var right := camera.global_basis.x
			var up := camera.global_basis.y
			_camera_target -= right * delta.x * 0.02
			_camera_target += up * delta.y * 0.02
			_pan_start = event.position
			update_transform()


func update_transform() -> void:
	if camera == null:
		return

	var yaw_rad := deg_to_rad(_camera_yaw)
	var pitch_rad := deg_to_rad(_camera_pitch)

	var offset := Vector3(
		_camera_distance * cos(pitch_rad) * sin(yaw_rad),
		_camera_distance * sin(pitch_rad),
		_camera_distance * cos(pitch_rad) * cos(yaw_rad)
	)

	camera.global_position = _camera_target + offset
	# 避免原点与目标重合时 look_at 报错
	if camera.global_position.distance_to(_camera_target) > 0.001:
		camera.look_at(_camera_target, Vector3.UP)


func cycle_scale(direction: int) -> void:
	var new_idx := current_scale + direction
	if new_idx < 0:
		new_idx = ScaleLevel.size() - 1
	elif new_idx >= ScaleLevel.size():
		new_idx = 0
	current_scale = new_idx
	_camera_distance = SCALE_DISTANCES[current_scale]
	update_transform()
	GameLogger.info("Construction", "[构造] 缩放: %s" % SCALE_LABELS[current_scale])


func focus_on(position: Vector3) -> void:
	_camera_target = position
	update_transform()


# 多视图预设 — MolGame 风格快速切换视角
# V 键循环切换: 等轴 → 正面 → 俯视 → 侧面
const VIEW_PRESETS: Array = [
	{"yaw": 45.0, "pitch": 30.0, "name": "等轴"},
	{"yaw": 0.0, "pitch": 0.0, "name": "正面"},
	{"yaw": 0.0, "pitch": 89.0, "name": "俯视"},
	{"yaw": 90.0, "pitch": 0.0, "name": "侧面"},
]
var _view_idx: int = 0

func cycle_view_preset() -> void:
	_view_idx = (_view_idx + 1) % VIEW_PRESETS.size()
	var preset = VIEW_PRESETS[_view_idx]
	_camera_yaw = preset["yaw"]
	_camera_pitch = preset["pitch"]
	update_transform()
	GameLogger.info("Construction", "[构造] 视角: %s" % preset["name"])


func set_distance(dist: float) -> void:
	_camera_distance = dist
	update_transform()


func get_distance() -> float:
	return _camera_distance


func apply_level_scale(scale_label: String, scale_range: Vector2) -> void:
	match scale_label:
		"nm":
			current_scale = ScaleLevel.NANOMETER
			_camera_distance = SCALE_DISTANCES[ScaleLevel.NANOMETER]
		"μm":
			current_scale = ScaleLevel.MICROMETER
			_camera_distance = SCALE_DISTANCES[ScaleLevel.MICROMETER]
		_:
			current_scale = ScaleLevel.ANGSTROM
			_camera_distance = SCALE_DISTANCES[ScaleLevel.ANGSTROM]

	# Guard against zero or degenerate scale_range from level data
	var min_dist: float = maxf(scale_range.x * 3.0, 3.0)
	var max_dist: float = maxf(scale_range.y * 10.0, min_dist + 5.0)
	_camera_distance = clampf(_camera_distance, min_dist, max_dist)
	update_transform()


# 公共接口：左键拖拽旋转
func start_orbit(pos: Vector2, is_left_drag: bool = false) -> void:
	if is_left_drag:
		_orbiting_left = true
	else:
		_orbiting_right = true
	_orbit_start = pos


func update_orbit(pos: Vector2) -> void:
	if not (_orbiting_left or _orbiting_right):
		return
	var delta := pos - _orbit_start
	_camera_yaw -= delta.x * 0.4
	_camera_pitch = clampf(_camera_pitch + delta.y * 0.4, -89.0, 89.0)
	_orbit_start = pos
	update_transform()


func stop_orbit(is_left_drag: bool = false) -> void:
	if is_left_drag:
		_orbiting_left = false
	else:
		_orbiting_right = false
