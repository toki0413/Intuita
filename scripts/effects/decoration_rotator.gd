extends Node3D

@export var rotation_speed: Vector3 = Vector3(0, 30, 0)

func _process(delta: float) -> void:
	rotate_y(deg_to_rad(rotation_speed.y * delta))
