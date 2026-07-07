# predictive_verifier.gd
# 预判验证 - 验证前显示预估成功率

class_name PredictiveVerifier
extends RefCounted

var _canvas: Node3D = null

# 预估成功率显示节点
var _prediction_bar: ProgressBar = null
var _prediction_label: Label = null
var _prediction_panel: PanelContainer = null

func _init(canvas: Node3D) -> void:
	_canvas = canvas
	_create_ui()

func _create_ui() -> void:
	if _canvas == null:
		return
	
	# 创建预判面板（放在屏幕底部中央）
	_prediction_panel = PanelContainer.new()
	_prediction_panel.name = "PredictionPanel"
	_prediction_panel.anchors_preset = Control.PRESET_CENTER_BOTTOM
	_prediction_panel.offset_left = -150
	_prediction_panel.offset_top = -60
	_prediction_panel.offset_right = 150
	_prediction_panel.offset_bottom = -20
	_prediction_panel.visible = false
	
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	_prediction_label = Label.new()
	_prediction_label.text = "预估成功率"
	_prediction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prediction_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_prediction_label)
	
	_prediction_bar = ProgressBar.new()
	_prediction_bar.custom_minimum_size = Vector2(280, 16)
	_prediction_bar.max_value = 100
	_prediction_bar.value = 0
	vbox.add_child(_prediction_bar)
	
	_prediction_panel.add_child(vbox)
	_canvas.add_child(_prediction_panel)

func update_prediction() -> void:
	var prediction: float = _calculate_prediction()
	
	_prediction_bar.value = prediction * 100
	
	# 根据成功率变色
	var color: Color
	if prediction >= 0.8:
		color = Color(0.2, 0.9, 0.3)
		_prediction_label.text = "验证通过概率: 高"
	elif prediction >= 0.5:
		color = Color(0.9, 0.8, 0.2)
		_prediction_label.text = "验证通过概率: 中"
	else:
		color = Color(0.9, 0.3, 0.2)
		_prediction_label.text = "验证通过概率: 低"
	
	_prediction_bar.add_theme_color_override("fill", color)
	_prediction_panel.visible = true

func hide_prediction() -> void:
	if _prediction_panel != null:
		_prediction_panel.visible = false

func _calculate_prediction() -> float:
	# 基于当前守恒状态的简单预测
	var summary: Dictionary = ConservationEngine.get_deviation_summary()
	if summary.size() == 0:
		return 0.0
	
	var total_dev: float = 0.0
	var max_dev: float = 0.0
	for key in summary:
		var dev: float = summary[key].get("deviation", 0.0)
		total_dev += dev
		max_dev = maxf(max_dev, dev)
	
	var avg_dev: float = total_dev / maxi(summary.size(), 1)
	
	# 预测公式: 成功率 = clamp(1.0 - max_dev * 2, 0, 1)
	var prediction: float = 1.0 - max_dev * 2.0
	prediction = clampf(prediction, 0.0, 1.0)
	
	# 额外惩罚: 如果有任何一项偏离>0.3
	if max_dev > 0.3:
		prediction *= 0.5
	
	return prediction
