# combo_system.gd
# 连击奖励系统 - 追踪连续正确放置，提供奖励

class_name ComboSystem
extends RefCounted

signal combo_changed(combo_count: int, max_combo: int)
signal combo_reward_activated(reward_type: String, description: String)

var _canvas: Node3D = null
var _float_text: FloatingTextSystem = null

var current_combo: int = 0
var max_combo: int = 0
var _last_placement_was_good: bool = false
var _consecutive_good_placements: int = 0

# 奖励阈值
const REWARD_THRESHOLDS: Dictionary = {
	3: {"type": "free_verify", "desc": "下次验证免费!", "cores_saved": 1},
	5: {"type": "core_bonus", "desc": "+2 核心奖励!", "cores": 2},
	7: {"type": "perfect_mode", "desc": "完美模式: 验证跳过 L1-L2!", "skip_layers": 2},
	10: {"type": "mega_bonus", "desc": "MEGA BONUS: +5 核心 + 免费验证!", "cores": 5, "free_verify": true},
}

var _active_rewards: Dictionary = {}
var _pending_free_verify: bool = false
var _pending_skip_layers: int = 0

func _init(canvas: Node3D, float_text: FloatingTextSystem) -> void:
	_canvas = canvas
	_float_text = float_text

func on_atom_placed(atom: Node3D, deviation_before: float, deviation_after: float) -> void:
	var is_good: bool = deviation_after <= deviation_before
	if is_good:
		current_combo += 1
		if current_combo > max_combo:
			max_combo = current_combo
		_consecutive_good_placements = current_combo
		_check_rewards(atom)
	else:
		if current_combo > 0:
			# 连击中断，显示提示
			if _float_text != null and atom != null:
				_float_text.show_float_text(atom.global_position, "COMBO BROKEN", Color(0.7, 0.7, 0.7), 1.0)
		current_combo = 0
		_consecutive_good_placements = 0
		_clear_rewards()
	
	combo_changed.emit(current_combo, max_combo)

func _check_rewards(atom: Node3D) -> void:
	for threshold in REWARD_THRESHOLDS:
		if current_combo == threshold:
			var reward: Dictionary = REWARD_THRESHOLDS[threshold]
			_apply_reward(reward)
			combo_reward_activated.emit(reward["type"], reward["desc"])
			if _float_text != null and atom != null:
				_float_text.show_combo_text(atom.global_position, current_combo)

func _apply_reward(reward: Dictionary) -> void:
	match reward["type"]:
		"free_verify":
			_pending_free_verify = true
		"core_bonus":
			if LevelManager != null:
				GameState.gain_cores(reward["cores"])
		"perfect_mode":
			_pending_skip_layers = reward["skip_layers"]
		"mega_bonus":
			if LevelManager != null:
				GameState.gain_cores(reward["cores"])
			_pending_free_verify = true

func _clear_rewards() -> void:
	_pending_free_verify = false
	_pending_skip_layers = 0
	_active_rewards.clear()

func get_verify_cost_discount() -> int:
	# 返回验证成本减免
	if _pending_free_verify:
		_pending_free_verify = false
		return 999  # 完全免费
	return 0

func get_skip_layers() -> int:
	var layers: int = _pending_skip_layers
	_pending_skip_layers = 0
	return layers

func on_level_reset() -> void:
	current_combo = 0
	max_combo = 0
	_consecutive_good_placements = 0
	_clear_rewards()

func get_combo_multiplier() -> float:
	# 得分倍率
	if current_combo >= 10:
		return 3.0
	elif current_combo >= 7:
		return 2.5
	elif current_combo >= 5:
		return 2.0
	elif current_combo >= 3:
		return 1.5
	return 1.0
