extends Node

signal lod_changed(level: String)
signal performance_fallback_triggered(level: String)

var _lod_configs: Dictionary = {
    "high":    {"atom_segments": 24, "atom_rings": 16, "bond_segments": 12, "bond_cap": 8},
    "medium":  {"atom_segments": 16, "atom_rings": 12, "bond_segments": 8,  "bond_cap": 6},
    "low":     {"atom_segments": 8,  "atom_rings": 8,  "bond_segments": 6,  "bond_cap": 4},
    "minimal": {"atom_segments": 4,  "atom_rings": 4,  "bond_segments": 4,  "bond_cap": 2},
}

var _distance_thresholds: Dictionary = {
    "high": 10.0,
    "medium": 25.0,
    "low": 50.0,
}

var _atoms: Array[Node3D] = []
var _bonds: Array[Node3D] = []
var _camera: Camera3D = null
var _force_level: String = ""
var _current_level: String = "high"
var _frame_counter: int = 0
const REFRESH_INTERVAL := 30
var _low_fps_timer: float = 0.0
var _high_fps_timer: float = 0.0
const PERFORMANCE_FALLBACK_THRESHOLD := 3.0
const LOW_FPS_THRESHOLD := 20.0
const HIGH_FPS_THRESHOLD := 50.0
var _max_level_index: int = 3

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _find_camera()

func _process(delta: float) -> void:
    _frame_counter += 1
    if _frame_counter >= REFRESH_INTERVAL:
        _frame_counter = 0
        refresh_all()
    _check_performance_fallback(delta)

func _find_camera() -> void:
    var canvas = Engine.get_main_loop().root.get_node_or_null("ConstructionCanvas")
    if canvas:
        _camera = canvas.get_node_or_null("Camera3D") as Camera3D
    if _camera == null:
        _camera = _find_camera_recursive(Engine.get_main_loop().root)

func _find_camera_recursive(node: Node) -> Camera3D:
    if node is Camera3D:
        return node as Camera3D
    for child in node.get_children():
        var found = _find_camera_recursive(child)
        if found != null:
            return found
    return null

func register_atom(atom: Node3D) -> void:
    if atom != null and not atom in _atoms:
        _atoms.append(atom)

func unregister_atom(atom: Node3D) -> void:
    _atoms.erase(atom)

func register_bond(bond: Node3D) -> void:
    if bond != null and not bond in _bonds:
        _bonds.append(bond)

func unregister_bond(bond: Node3D) -> void:
    _bonds.erase(bond)

func _get_lod_level(distance: float) -> String:
    var level: String
    if distance < _distance_thresholds["high"]:
        level = "high"
    elif distance < _distance_thresholds["medium"]:
        level = "medium"
    elif distance < _distance_thresholds["low"]:
        level = "low"
    else:
        level = "minimal"
    var level_idx := _get_level_index(level)
    if level_idx > _max_level_index:
        level = _get_level_from_index(_max_level_index)
    return level

func _get_level_index(level: String) -> int:
    match level:
        "high": return 3
        "medium": return 2
        "low": return 1
        "minimal": return 0
    return 0

func _get_level_from_index(index: int) -> String:
    match index:
        3: return "high"
        2: return "medium"
        1: return "low"
        0: return "minimal"
    return "minimal"

func update_lod_for_atom(atom: MeshInstance3D, level: String) -> void:
    if atom == null or not is_instance_valid(atom):
        return
    if not atom is MeshInstance3D:
        return
    var mesh = atom.mesh
    if mesh is SphereMesh:
        var config = _lod_configs[level]
        mesh.radial_segments = config["atom_segments"]
        mesh.rings = config["atom_rings"]
        var glow = atom.get_node_or_null("Glow") as MeshInstance3D
        if glow and glow.mesh is SphereMesh:
            var glow_mesh = glow.mesh as SphereMesh
            glow_mesh.radial_segments = maxi(config["atom_segments"] / 2, 4)
            glow_mesh.rings = maxi(config["atom_rings"] / 2, 4)

func update_lod_for_bond(bond: MeshInstance3D, level: String) -> void:
    if bond == null or not is_instance_valid(bond):
        return
    if not bond is MeshInstance3D:
        return
    var mesh = bond.mesh
    if mesh is CylinderMesh:
        var config = _lod_configs[level]
        mesh.radial_segments = config["bond_segments"]
    for child in bond.get_children():
        if child is MeshInstance3D and child.mesh is CylinderMesh:
            var config = _lod_configs[level]
            child.mesh.radial_segments = maxi(config["bond_segments"] / 2, 3)

func refresh_all() -> void:
    if _camera == null:
        _find_camera()
    if _camera == null:
        return
    var cam_pos := _camera.global_position
    var new_level := ""
    for atom in _atoms:
        if not is_instance_valid(atom):
            continue
        var level: String
        if _force_level != "":
            level = _force_level
        else:
            level = _get_lod_level(atom.global_position.distance_to(cam_pos))
        update_lod_for_atom(atom, level)
        if new_level == "" or _get_level_index(level) < _get_level_index(new_level):
            new_level = level
    for bond in _bonds:
        if not is_instance_valid(bond):
            continue
        var level: String
        if _force_level != "":
            level = _force_level
        else:
            level = _get_lod_level(bond.global_position.distance_to(cam_pos))
        update_lod_for_bond(bond, level)
        if new_level == "" or _get_level_index(level) < _get_level_index(new_level):
            new_level = level
    if new_level != "" and new_level != _current_level:
        _current_level = new_level
        lod_changed.emit(_current_level)

func _check_performance_fallback(delta: float, simulated_fps: float = -1.0) -> void:
    if _force_level != "":
        return
    var fps := Engine.get_frames_per_second() if simulated_fps < 0.0 else simulated_fps
    if fps < LOW_FPS_THRESHOLD:
        _low_fps_timer += delta
        _high_fps_timer = 0.0
        if _low_fps_timer >= PERFORMANCE_FALLBACK_THRESHOLD:
            if _max_level_index > 0:
                _max_level_index -= 1
                var new_level = _get_level_from_index(_max_level_index)
                if new_level != _current_level:
                    _current_level = new_level
                    performance_fallback_triggered.emit(new_level)
                    var logger = Engine.get_main_loop().root.get_node_or_null("/root/GameLogger")
                    if logger:
                        logger.warn("LODManager", "Performance fallback triggered: %s" % new_level)
            _low_fps_timer = 0.0
    elif fps > HIGH_FPS_THRESHOLD:
        _high_fps_timer += delta
        _low_fps_timer = 0.0
        if _high_fps_timer >= PERFORMANCE_FALLBACK_THRESHOLD:
            if _max_level_index < 3:
                _max_level_index += 1
                var new_level = _get_level_from_index(_max_level_index)
                if new_level != _current_level:
                    _current_level = new_level
                    var logger = Engine.get_main_loop().root.get_node_or_null("/root/GameLogger")
                    if logger:
                        logger.info("LODManager", "Performance recovered: %s" % new_level)
            _high_fps_timer = 0.0
    else:
        _low_fps_timer = 0.0
        _high_fps_timer = 0.0

func set_force_lod(level: String) -> void:
    if _lod_configs.has(level):
        _force_level = level
        _current_level = level
        refresh_all()
    else:
        push_warning("LODManager: invalid LOD level '%s'" % level)

func clear_force_lod() -> void:
    _force_level = ""
    _current_level = "high"
    refresh_all()

func get_current_level() -> String:
    return _current_level if _force_level == "" else _force_level

func set_distance_thresholds(high: float, medium: float, low: float) -> void:
    _distance_thresholds["high"] = high
    _distance_thresholds["medium"] = medium
    _distance_thresholds["low"] = low
