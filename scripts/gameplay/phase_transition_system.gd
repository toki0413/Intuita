# phase_transition_system.gd
# 相变系统 - 温度变化导致晶体结构相变
# 玩家需要管理温度来保持结构稳定

class_name PhaseTransitionSystem
extends RefCounted

signal temperature_changed(new_temp: float, phase_name: String)
signal phase_transition_occurred(old_phase: String, new_phase: String, effects: Dictionary)
signal temperature_warning(level: String)  # "low", "optimal", "high", "critical"

var _canvas: Node3D = null
var _float_text: FloatingTextSystem = null

# 当前状态
var _current_temperature: float = 300.0  # 开尔文，室温
var _target_temperature: float = 300.0
var _ambient_temperature: float = 300.0
var _heating_rate: float = 0.0  # K/s，外部热源
var _cooling_rate: float = 0.0  # K/s，主动冷却

# 相变数据库
const PHASES: Dictionary = {
	"solid_low": {
		"temp_range": [0.0, 200.0],
		"name": "低温固相",
		"stability_mod": 1.2,
		"bond_strength_mod": 1.3,
		"atom_mobility": 0.0,
		"color": Color(0.5, 0.8, 1.0),
	},
	"solid": {
		"temp_range": [200.0, 500.0],
		"name": "标准固相",
		"stability_mod": 1.0,
		"bond_strength_mod": 1.0,
		"atom_mobility": 0.0,
		"color": Color(0.7, 0.9, 0.7),
	},
	"transition": {
		"temp_range": [500.0, 700.0],
		"name": "相变过渡区",
		"stability_mod": 0.6,
		"bond_strength_mod": 0.7,
		"atom_mobility": 0.3,
		"color": Color(1.0, 0.8, 0.3),
		"warning": true,
	},
	"liquid": {
		"temp_range": [700.0, 1000.0],
		"name": "液相",
		"stability_mod": 0.3,
		"bond_strength_mod": 0.4,
		"atom_mobility": 0.8,
		"color": Color(1.0, 0.5, 0.2),
		"warning": true,
	},
	"gas": {
		"temp_range": [1000.0, 9999.0],
		"name": "气相",
		"stability_mod": 0.0,
		"bond_strength_mod": 0.0,
		"atom_mobility": 1.0,
		"color": Color(1.0, 0.2, 0.2),
		"warning": true,
	},
}

var _current_phase: String = "solid"
var _phase_change_cooldown: float = 0.0
const PHASE_CHANGE_COOLDOWN: float = 3.0  # 相变冷却时间，防止频繁切换

# 温度HUD引用
var _temp_bar: ProgressBar = null
var _temp_label: Label = null
var _temp_panel: PanelContainer = null

func _init(canvas: Node3D, float_text: FloatingTextSystem) -> void:
	_canvas = canvas
	_float_text = float_text
	_create_temp_ui()

func _create_temp_ui() -> void:
	if _canvas == null:
		return
	
	_temp_panel = PanelContainer.new()
	_temp_panel.name = "TemperaturePanel"
	_temp_panel.anchors_preset = Control.PRESET_BOTTOM_RIGHT
	_temp_panel.offset_left = -200
	_temp_panel.offset_top = -80
	_temp_panel.offset_right = -10
	_temp_panel.offset_bottom = -10
	
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	_temp_label = Label.new()
	_temp_label.text = "温度: 300K (标准固相)"
	_temp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_temp_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_temp_label)
	
	_temp_bar = ProgressBar.new()
	_temp_bar.custom_minimum_size = Vector2(180, 16)
	_temp_bar.max_value = 1200
	_temp_bar.value = 300
	vbox.add_child(_temp_bar)
	
	# 添加温度标记线
	_temp_panel.add_child(vbox)
	_canvas.add_child(_temp_panel)

func setup_for_level(level_data: Dictionary) -> void:
	var temp_config: Dictionary = level_data.get("temperature", {})
	_ambient_temperature = temp_config.get("ambient", 300.0)
	_heating_rate = temp_config.get("heating_rate", 0.0)
	_cooling_rate = temp_config.get("cooling_rate", 0.0)
	_current_temperature = _ambient_temperature
	_target_temperature = _ambient_temperature
	_update_phase()
	_update_ui()

func process(delta: float) -> void:
	if _phase_change_cooldown > 0:
		_phase_change_cooldown -= delta
	
	# 温度自然变化
	var net_change: float = _heating_rate - _cooling_rate
	if net_change != 0.0:
		_current_temperature += net_change * delta
		_current_temperature = clampf(_current_temperature, 0.0, 1500.0)
		_update_phase()
		_update_ui()

func set_temperature(temp: float) -> void:
	_current_temperature = clampf(temp, 0.0, 1500.0)
	_update_phase()
	_update_ui()

func add_heat(amount: float) -> void:
	_current_temperature += amount
	_current_temperature = clampf(_current_temperature, 0.0, 1500.0)
	_update_phase()
	_update_ui()
	
	if _float_text != null and _canvas != null:
		_float_text.show_float_text(
			_canvas.global_position + Vector3(2, 1, 0),
			"+%.0fK" % amount,
			Color(1.0, 0.4, 0.2),
			1.0
		)

func add_cooling(amount: float) -> void:
	_current_temperature -= amount
	_current_temperature = clampf(_current_temperature, 0.0, 1500.0)
	_update_phase()
	_update_ui()
	
	if _float_text != null and _canvas != null:
		_float_text.show_float_text(
			_canvas.global_position + Vector3(2, 1, 0),
			"-%.0fK" % amount,
			Color(0.3, 0.6, 1.0),
			1.0
		)

func _update_phase() -> void:
	var new_phase: String = _get_phase_for_temp(_current_temperature)
	if new_phase != _current_phase and _phase_change_cooldown <= 0:
		_trigger_phase_transition(_current_phase, new_phase)
		_current_phase = new_phase

func _get_phase_for_temp(temp: float) -> String:
	for phase_key in PHASES:
		var phase: Dictionary = PHASES[phase_key]
		var range: Array = phase["temp_range"]
		if temp >= range[0] and temp < range[1]:
			return phase_key
	return "solid"

func _trigger_phase_transition(old_phase: String, new_phase: String) -> void:
	_phase_change_cooldown = PHASE_CHANGE_COOLDOWN
	
	var old_data: Dictionary = PHASES.get(old_phase, {})
	var new_data: Dictionary = PHASES.get(new_phase, {})
	
	# 应用相变效果
	var effects := {
		"stability_mod": new_data.get("stability_mod", 1.0),
		"bond_strength_mod": new_data.get("bond_strength_mod", 1.0),
		"atom_mobility": new_data.get("atom_mobility", 0.0),
	}
	
	# 通知守恒引擎（通过日志）
	if GameLogger != null:
		GameLogger.info("Phase", "[相变] %s -> %s, 稳定性倍率: %.1f" % [old_phase, new_phase, effects["stability_mod"]])
	
	# 视觉反馈
	if _float_text != null and _canvas != null:
		var color: Color = new_data.get("color", Color.WHITE)
		var name: String = new_data.get("name", "?")
		_float_text.show_float_text(
			_canvas.global_position + Vector3(0, 2, 0),
			"相变: %s!" % name,
			color,
			3.0
		)
		
		if new_data.get("warning", false):
			_float_text.show_float_text(
				_canvas.global_position + Vector3(0, 2.5, 0),
				"警告: 结构不稳定!",
				Color(1.0, 0.2, 0.2),
				2.0
			)
	
	# 音效
	if SoundManager != null:
		if new_data.get("warning", false):
			SoundManager.play(SoundManager.SoundType.CONSERVATION_WARN)
		else:
			SoundManager.play(SoundManager.SoundType.VERIFICATION_PASS)
	
	phase_transition_occurred.emit(old_phase, new_phase, effects)

func _update_ui() -> void:
	if _temp_bar == null or _temp_label == null:
		return
	
	_temp_bar.value = _current_temperature
	
	var phase_data: Dictionary = PHASES.get(_current_phase, {})
	var phase_name: String = phase_data.get("name", "?")
	var color: Color = phase_data.get("color", Color.WHITE)
	
	_temp_label.text = "温度: %.0fK (%s)" % [_current_temperature, phase_name]
	_temp_label.add_theme_color_override("font_color", color)
	_temp_bar.add_theme_color_override("fill", color)
	
	temperature_changed.emit(_current_temperature, phase_name)
	
	# 温度警告
	if _current_temperature > 800:
		temperature_warning.emit("critical")
	elif _current_temperature > 600:
		temperature_warning.emit("high")
	elif _current_temperature > 400:
		temperature_warning.emit("optimal")
	else:
		temperature_warning.emit("low")

func get_temperature() -> float:
	return _current_temperature

func get_phase() -> String:
	return _current_phase

func get_phase_effects() -> Dictionary:
	var data: Dictionary = PHASES.get(_current_phase, {})
	return {
		"stability_mod": data.get("stability_mod", 1.0),
		"bond_strength_mod": data.get("bond_strength_mod", 1.0),
		"atom_mobility": data.get("atom_mobility", 0.0),
	}

func is_stable() -> bool:
	return _current_phase == "solid" or _current_phase == "solid_low"

func on_level_reset() -> void:
	_current_temperature = 300.0
	_target_temperature = 300.0
	_current_phase = "solid"
	_heating_rate = 0.0
	_cooling_rate = 0.0
	_phase_change_cooldown = 0.0
	_update_ui()
