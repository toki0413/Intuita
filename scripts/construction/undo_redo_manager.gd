# undo_redo_manager.gd
# 撤销/重做管理器 - 从 construction_canvas.gd 拆分
#
# 负责：
#   - 操作历史栈 (undo/redo)
#   - 支持操作类型: place_atom, delete_atom, substitute_atom
#   - 最大步数限制与溢出处理

class_name UndoRedoManager
extends RefCounted

var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _max_steps: int = 50
var _applying: bool = false

var _atom_mgr: Object = null

# 回调：当栈状态变化时通知宿主更新 HUD
var on_stack_changed: Callable = Callable()

func _init(atom_mgr: Object = null) -> void:
	_atom_mgr = atom_mgr

func set_max_steps(n: int) -> void:
	_max_steps = maxi(n, 1)

func clear() -> void:
	_undo_stack.clear()
	_redo_stack.clear()

func can_undo() -> bool:
	return not _undo_stack.is_empty()

func can_redo() -> bool:
	return not _redo_stack.is_empty()

func is_applying() -> bool:
	return _applying

func push(action: Dictionary) -> void:
	if _applying:
		return
	_undo_stack.append(action)
	if _undo_stack.size() > _max_steps:
		_undo_stack.remove_at(0)
	_redo_stack.clear()
	_on_stack_changed()

func undo() -> Dictionary:
	if _undo_stack.is_empty():
		return {}
	_applying = true
	var action: Dictionary = _undo_stack.pop_back()
	_redo_stack.append(action)

	var result := _execute_undo(action)

	_applying = false
	_on_stack_changed()
	if LevelManager != null and LevelManager.has_method("increment_metric"):
		LevelManager.increment_metric("undo_count")
	return result

func redo() -> Dictionary:
	if _redo_stack.is_empty():
		return {}
	_applying = true
	var action: Dictionary = _redo_stack.pop_back()
	_undo_stack.append(action)

	var result := _execute_redo(action)

	_applying = false
	_on_stack_changed()
	if LevelManager != null and LevelManager.has_method("increment_metric"):
		LevelManager.increment_metric("redo_count")
	return result

func _execute_undo(action: Dictionary) -> Dictionary:
	match action.get("type", ""):
		"place_atom":
			return _undo_place_atom(action)
		"delete_atom":
			return _undo_delete_atom(action)
		"substitute_atom":
			return _undo_substitute_atom(action)
		_:
			push_warning("[撤销] 未知操作类型: %s" % action.get("type", ""))
			return action

func _execute_redo(action: Dictionary) -> Dictionary:
	match action.get("type", ""):
		"place_atom":
			return _redo_place_atom(action)
		"delete_atom":
			return _redo_delete_atom(action)
		"substitute_atom":
			return _redo_substitute_atom(action)
		_:
			push_warning("[重做] 未知操作类型: %s" % action.get("type", ""))
			return action

func _undo_place_atom(action: Dictionary) -> Dictionary:
	var atom: Node = action.get("atom_ref", null)
	if not is_instance_valid(atom):
		return {}
	var deleted_info: Dictionary = _atom_mgr.delete_atom(atom)
	action["atom_data"] = deleted_info
	return action

func _redo_place_atom(action: Dictionary) -> Dictionary:
	var atom_data: Dictionary = action.get("atom_data", {})
	if atom_data.is_empty():
		return {}
	var restored: Node3D = _atom_mgr.restore_atom(atom_data)
	if restored:
		action["atom_ref"] = restored
	return action

func _undo_delete_atom(action: Dictionary) -> Dictionary:
	var atom_data: Dictionary = action.get("atom_data", {})
	if atom_data.is_empty():
		return {}
	var restored: Node3D = _atom_mgr.restore_atom(atom_data)
	if restored:
		action["atom_ref"] = restored
	return action

func _redo_delete_atom(action: Dictionary) -> Dictionary:
	var atom: Node = action.get("atom_ref", null)
	if not is_instance_valid(atom):
		return {}
	var deleted_info: Dictionary = _atom_mgr.delete_atom(atom)
	action["atom_data"] = deleted_info
	return action

func _undo_substitute_atom(action: Dictionary) -> Dictionary:
	var atom: Node = action.get("atom_ref", null)
	var old_idx: int = action.get("old_element_index", -1)
	if not is_instance_valid(atom) or old_idx < 0:
		return {}
	_atom_mgr.substitute_atom_to(atom, old_idx)
	return action

func _redo_substitute_atom(action: Dictionary) -> Dictionary:
	var atom: Node = action.get("atom_ref", null)
	var new_idx: int = action.get("new_element_index", -1)
	if not is_instance_valid(atom) or new_idx < 0:
		return {}
	_atom_mgr.substitute_atom_to(atom, new_idx)
	return action

func _on_stack_changed() -> void:
	if on_stack_changed.is_valid():
		on_stack_changed.call(_undo_stack.size(), _redo_stack.size())

func get_undo_count() -> int:
	return _undo_stack.size()

func get_redo_count() -> int:
	return _redo_stack.size()
