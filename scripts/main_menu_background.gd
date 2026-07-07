# main_menu_background.gd
# 主菜单 3D 背景控制器
# 驱动旋转装饰、相机缓慢移动和粒子效果
#
# Responsibilities:
#   - 装饰物持续旋转（各轴不同速度）
#   - 相机缓慢轨道运动
#   - 动态环境光调整
#
# Dependencies:
#   - Scene: main_menu_background.tscn
#   - Assets: coin.glb (Kenney)

extends Node3D

@onready var decorations: Node3D = $Decorations
@onready var camera: Camera3D = $Camera3D
@onready var env: WorldEnvironment = $WorldEnvironment

const CAM_ORBIT_RADIUS := 8.0
const CAM_ORBIT_SPEED := 0.15  # rad/s
const CAM_HEIGHT := 5.0

var _time: float = 0.0
var _decoration_data: Array[Dictionary] = []


func _ready() -> void:
    # 为每个装饰物初始化随机旋转速度和轨道参数
    for child in decorations.get_children():
        if child is Node3D:
            _decoration_data.append({
                "node": child,
                "rot_speed": Vector3(
                    randf_range(0.3, 1.5),
                    randf_range(0.3, 1.5),
                    randf_range(0.3, 1.5)
                ),
                "orbit_radius": randf_range(2.0, 6.0),
                "orbit_speed": randf_range(0.1, 0.4),
                "orbit_phase": randf_range(0.0, TAU),
                "orbit_axis": Vector3.UP,
            })
    
    # 初始相机位置
    _update_camera(0.0)


func _process(delta: float) -> void:
    _time += delta

    # 降频：装饰物动画每2帧更新一次
    if Engine.get_process_frames() % 2 != 0:
        return

    # 旋转装饰物
    for data in _decoration_data:
        var node: Node3D = data["node"]
        var speed: Vector3 = data["rot_speed"]
        node.rotate_x(speed.x * delta)
        node.rotate_y(speed.y * delta)
        node.rotate_z(speed.z * delta)
        
        # 缓慢轨道漂移
        var radius: float = data["orbit_radius"]
        var spd: float = data["orbit_speed"]
        var phase: float = data["orbit_phase"]
        var axis: Vector3 = data["orbit_axis"]
        var offset := Vector3(
            cos(_time * spd + phase) * radius,
            sin(_time * spd * 0.7 + phase) * radius * 0.3,
            sin(_time * spd + phase) * radius
        )
        # 保持原始位置的偏移
        var base_pos: Vector3 = node.get_meta("base_position", node.position)
        if not node.has_meta("base_position"):
            node.set_meta("base_position", node.position)
            base_pos = node.position
        node.position = base_pos + offset
    
    # 相机轨道运动
    _update_camera(delta)
    
    # 动态环境光微调
    if env and env.environment:
        var env_ref: Environment = env.environment
        var ambient_energy := 0.8 + sin(_time * 0.2) * 0.1
        env_ref.ambient_light_energy = ambient_energy


func _update_camera(delta: float) -> void:
    var angle := _time * CAM_ORBIT_SPEED
    var x := cos(angle) * CAM_ORBIT_RADIUS
    var z := sin(angle) * CAM_ORBIT_RADIUS
    camera.position = Vector3(x, CAM_HEIGHT, z)
    camera.look_at(Vector3.ZERO, Vector3.UP)
