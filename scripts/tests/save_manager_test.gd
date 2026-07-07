# save_manager_test.gd
# GdUnit4 测试：SaveManager 存档系统
# 包括保存/加载/签名验证/备份恢复

extends GdUnitTestSuite


const __source = "res://scripts/autoload/save_manager.gd"

var _save_manager: Node = null


func before() -> void:
	_save_manager = Engine.get_main_loop().root.get_node_or_null("/root/SaveManager")


func after() -> void:
	# 清理测试存档，避免污染
	if _save_manager != null:
		for slot in range(0, 4):
			_save_manager.delete_save(slot)


func test_autoload_exists() -> void:
	assert_object(_save_manager).is_not_null()


func test_signature_self_consistency() -> void:
	if _save_manager == null:
		return

	var data: Dictionary = _save_manager._collect_save_data()
	var sig: String = _save_manager._compute_signature(data)
	assert_str(sig).is_not_empty()

	data["signature"] = sig
	var valid: bool = _save_manager._verify_signature(data, sig)
	assert_bool(valid).is_true()


func test_save_and_load_roundtrip() -> void:
	if _save_manager == null:
		return

	var slot = 2
	assert_bool(_save_manager.has_save(slot)).is_false()

	var ok: bool = _save_manager.save_game(slot)
	assert_bool(ok).is_true()
	assert_bool(_save_manager.has_save(slot)).is_true()

	var info: Dictionary = _save_manager.get_save_info(slot)
	assert_dict(info).is_not_empty()
	assert_int(int(info.get("version", 0))).is_greater_equal(1)
	assert_bool(info.has("verified")).is_true()

	var load_ok: bool = _save_manager.load_game(slot)
	assert_bool(load_ok).is_true()


func test_delete_save_removes_file() -> void:
	if _save_manager == null:
		return

	var slot = 1
	_save_manager.save_game(slot)
	assert_bool(_save_manager.has_save(slot)).is_true()

	var deleted: bool = _save_manager.delete_save(slot)
	assert_bool(deleted).is_true()
	assert_bool(_save_manager.has_save(slot)).is_false()


func test_invalid_slot_rejected() -> void:
	if _save_manager == null:
		return

	assert_bool(_save_manager.save_game(-1)).is_false()
	assert_bool(_save_manager.save_game(99)).is_false()
	assert_bool(_save_manager.load_game(-1)).is_false()
	assert_bool(_save_manager.load_game(99)).is_false()


func test_tampered_save_rejected() -> void:
	if _save_manager == null:
		return

	var slot = 3
	_save_manager.save_game(slot)
	# 第二次保存以创建备份
	_save_manager.save_game(slot)

	# 篡改存档文件：修改核心数为 9999
	var path = "user://saves/slot_%d.json" % slot
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var raw: String = file.get_as_text()
	file.close()

	var json = JSON.new()
	json.parse(raw)
	var data: Dictionary = json.data
	var gs: Dictionary = data.get("game_state", {})
	gs["cores"] = 9999
	data["game_state"] = gs

	var tampered: String = JSON.stringify(data, "\t")
	var fw = FileAccess.open(path, FileAccess.WRITE)
	if fw:
		fw.store_string(tampered)
		fw.close()

	# 篡改后的存档应被拒绝，回退到备份（备份是合法签名的）
	var load_ok: bool = _save_manager.load_game(slot)
	assert_bool(load_ok).is_true()

	# 验证加载的是备份数据（cores 不是 9999）
	var info: Dictionary = _save_manager.get_save_info(slot)
	var gs_loaded: Dictionary = info.get("game_state", {})
	assert_int(int(gs_loaded.get("cores", 0))).is_not_equal(9999)


func test_save_info_returns_empty_for_missing() -> void:
	if _save_manager == null:
		return

	var info: Dictionary = _save_manager.get_save_info(999)
	assert_dict(info).is_empty()


func test_list_saves_excludes_empty_slots() -> void:
	if _save_manager == null:
		return

	# 先清理
	for slot in range(0, 4):
		_save_manager.delete_save(slot)

	_save_manager.save_game(1)
	_save_manager.save_game(3)

	var saves: Array = _save_manager.list_saves()
	assert_array(saves).has_size(2)

	var slots_found: Array[int] = []
	for s in saves:
		slots_found.append(s.get("slot", -1))
	assert_array(slots_found).contains([1, 3])


func test_signature_present_on_new_save() -> void:
	if _save_manager == null:
		return

	var slot = 0
	_save_manager.save_game(slot)

	var path = "user://saves/slot_%d.json" % slot
	var file = FileAccess.open(path, FileAccess.READ)
	assert_object(file).is_not_null()
	var raw: String = file.get_as_text()
	file.close()

	var json = JSON.new()
	assert_int(json.parse(raw)).is_equal(OK)
	var data: Dictionary = json.data
	assert_bool(data.has("signature")).is_true()
	assert_str(str(data.get("signature", ""))).is_not_empty()
