# tool_combo_system.gd
# 工具组合技 - 连续使用不同工具触发组合效果

class_name ToolComboSystem
extends RefCounted

signal combo_triggered(combo_name: String, description: String, bonus_cores: int)

var _canvas: Node3D = null
var _float_text: FloatingTextSystem = null

var _tool_history: Array = []  # 最近使用的工具序列
const HISTORY_MAX: int = 3

# 组合技定义: [工具序列] -> {名称, 描述, 效果}
const COMBOS: Dictionary = {
	"place_bond": {
		"sequence": ["PLACE", "BOND_BUILD"],
		"name": "键能加成",
		"desc": "放置后立即成键 → 键能+20%",
		"bonus_cores": 1,
	},
	"delete_place": {
		"sequence": ["DELETE", "PLACE"],
		"name": "位置记忆",
		"desc": "删除后重放 → 自动推荐最佳元素",
		"bonus_cores": 1,
	},
	"tune_verify": {
		"sequence": ["TUNE", "VERIFY"],
		"name": "精准验证",
		"desc": "调谐后验证 → 验证成本减半",
		"bonus_cores": 2,
	},
	"place_place_place": {
		"sequence": ["PLACE", "PLACE", "PLACE"],
		"name": "三连击",
		"desc": "连续放置3个原子 → +1 核心",
		"bonus_cores": 1,
	},
	"bond_bond": {
		"sequence": ["BOND_BUILD", "BOND_BUILD"],
		"name": "双键共振",
		"desc": "连续成键 → 结构稳定性+10%",
		"bonus_cores": 1,
	},
}

var _pending_effects: Dictionary = {}

func _init(canvas: Node3D, float_text: FloatingTextSystem) -> void:
	_canvas = canvas
	_float_text = float_text

func on_tool_used(tool_name: String, tool_pos: Vector3) -> void:
	_tool_history.append(tool_name)
	if _tool_history.size() > HISTORY_MAX:
		_tool_history.pop_front()
	
	_check_combos(tool_pos)

func _check_combos(tool_pos: Vector3) -> void:
	for combo_key in COMBOS:
		var combo: Dictionary = COMBOS[combo_key]
		var seq: Array = combo["sequence"]
		if _matches_sequence(seq):
			_apply_combo(combo, tool_pos)

func _matches_sequence(seq: Array) -> bool:
	if _tool_history.size() < seq.size():
		return false
	var start: int = _tool_history.size() - seq.size()
	for i in range(seq.size()):
		if _tool_history[start + i] != seq[i]:
			return false
	return true

func _apply_combo(combo: Dictionary, tool_pos: Vector3) -> void:
	var name: String = combo["name"]
	var desc: String = combo["desc"]
	var bonus: int = combo["bonus_cores"]
	
	# 应用效果
	_pending_effects[combo["sequence"][-1]] = combo
	
	# 奖励核心
	if LevelManager != null and bonus > 0:
		GameState.gain_cores(bonus)
	
	# 显示浮字
	if _float_text != null:
		_float_text.show_tool_combo(tool_pos, name)
	
	combo_triggered.emit(name, desc, bonus)

func get_effect_for_tool(tool_name: String) -> Dictionary:
	return _pending_effects.get(tool_name, {})

func clear_pending_effect(tool_name: String) -> void:
	_pending_effects.erase(tool_name)

func on_level_reset() -> void:
	_tool_history.clear()
	_pending_effects.clear()
