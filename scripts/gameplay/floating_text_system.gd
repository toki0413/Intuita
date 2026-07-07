# floating_text_system.gd
# 浮字反馈系统 - 放置原子时显示对守恒矩阵的具体影响
# 在3D空间中显示 "+0.02 mass" / "-0.05 charge" 等即时反馈

class_name FloatingTextSystem
extends RefCounted

var _canvas: Node3D = null
var _label_scene: PackedScene = null

func _init(canvas: Node3D) -> void:
	_canvas = canvas
	_label_scene = _create_label_scene()

func _create_label_scene() -> PackedScene:
	# 创建基础 Label3D 场景模板
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 32
	label.outline_size = 4
	label.outline_modulate = Color.BLACK
	label.modulate = Color.WHITE
	label.no_depth_test = true
	label.double_sided = true
	var scene := PackedScene.new()
	scene.pack(label)
	return scene

func show_float_text(world_pos: Vector3, text: String, color: Color, duration: float = 1.5) -> void:
	if _canvas == null or not is_instance_valid(_canvas):
		return
	var tree := _canvas.get_tree()
	if tree == null:
		return
	
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 28
	label.outline_size = 3
	label.outline_modulate = Color.BLACK
	label.modulate = color
	label.no_depth_test = true
	label.double_sided = true
	label.position = world_pos + Vector3(0, 0.5, 0)
	_canvas.add_child(label)
	
	# 创建Tween: 上浮 + 淡出
	var tween := tree.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", world_pos.y + 1.5, duration)
	tween.tween_property(label, "modulate:a", 0.0, duration * 0.7).set_delay(duration * 0.3)
	tween.chain().tween_callback(func():
		if is_instance_valid(label):
			label.queue_free()
	)

func show_conservation_delta(world_pos: Vector3, old_deviation: float, new_deviation: float, property_name: String) -> void:
	var delta: float = new_deviation - old_deviation
	var abs_delta: float = absf(delta)
	if abs_delta < 0.001:
		return
	
	var text: String
	var color: Color
	if delta < 0:
		# 偏离减少 = 好事
		text = "-%s %s" % [_format_delta(abs_delta), property_name]
		color = Color(0.2, 1.0, 0.4)  # 绿色
	else:
		# 偏离增加 = 坏事
		text = "+%s %s" % [_format_delta(abs_delta), property_name]
		color = Color(1.0, 0.3, 0.2)  # 红色
	
	show_float_text(world_pos, text, color, 1.2)

func show_combo_text(world_pos: Vector3, combo_count: int) -> void:
	var text: String = "x%d COMBO!" % combo_count
	var color := Color(1.0, 0.85, 0.0)  # 金色
	if combo_count >= 10:
		color = Color(1.0, 0.2, 0.8)  # 紫色
		text = "PERFECT x%d!" % combo_count
	elif combo_count >= 5:
		color = Color(0.2, 0.7, 1.0)  # 蓝色
		text = "GREAT x%d!" % combo_count
	show_float_text(world_pos, text, color, 2.0)

func show_affinity_bonus(world_pos: Vector3, element: String, multiplier: float) -> void:
	var text := "%s 2x BONUS!" % element
	var color := Color(1.0, 0.6, 0.0)  # 橙色
	show_float_text(world_pos, text, color, 1.5)

func show_tool_combo(world_pos: Vector3, combo_name: String) -> void:
	var text := "COMBO: %s!" % combo_name
	var color := Color(0.8, 0.3, 1.0)  # 紫色
	show_float_text(world_pos, text, color, 2.0)

func _format_delta(value: float) -> String:
	if value >= 0.1:
		return "%.2f" % value
	elif value >= 0.01:
		return "%.3f" % value
	else:
		return "%.4f" % value
