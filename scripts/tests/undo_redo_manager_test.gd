# undo_redo_manager_test.gd
# GdUnit4 测试: UndoRedoManager 撤销/重做逻辑

extends GdUnitTestSuite

const __source = "res://scripts/construction/undo_redo_manager.gd"

var _mgr = null

func before() -> void:
	_mgr = load(__source).new(null)
	_mgr.set_max_steps(10)

func after() -> void:
	if _mgr != null:
		_mgr = null

func test_push_and_undo() -> void:
	assert_bool(_mgr.can_undo()).is_false()
	_mgr.push({"type": "test_action", "data": "a"})
	assert_bool(_mgr.can_undo()).is_true()
	assert_bool(_mgr.can_redo()).is_false()
	var result: Dictionary = _mgr.undo()
	assert_str(result.get("type", "")).is_equal("test_action")
	assert_bool(_mgr.can_undo()).is_false()
	assert_bool(_mgr.can_redo()).is_true()

func test_redo() -> void:
	_mgr.push({"type": "test_action", "data": "b"})
	_mgr.undo()
	assert_bool(_mgr.can_redo()).is_true()
	var result: Dictionary = _mgr.redo()
	assert_str(result.get("type", "")).is_equal("test_action")
	assert_bool(_mgr.can_redo()).is_false()

func test_max_steps_overflow() -> void:
	_mgr.set_max_steps(3)
	for i in range(5):
		_mgr.push({"type": "test_action", "idx": i})
	assert_int(_mgr.get_undo_count()).is_equal(3)

func test_clear() -> void:
	_mgr.push({"type": "test_action"})
	_mgr.clear()
	assert_bool(_mgr.can_undo()).is_false()
	assert_bool(_mgr.can_redo()).is_false()

func test_redo_on_empty_returns_empty() -> void:
	var result: Dictionary = _mgr.redo()
	assert_dict(result).is_empty()

func test_undo_on_empty_returns_empty() -> void:
	var result: Dictionary = _mgr.undo()
	assert_dict(result).is_empty()

func test_is_applying_blocks_push() -> void:
	_mgr.push({"type": "test_action"})
	assert_int(_mgr.get_undo_count()).is_equal(1)
	_mgr.undo()
	assert_int(_mgr.get_undo_count()).is_equal(0)
