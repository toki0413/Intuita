# save_manager.gd
# 存档/读档系统 - 3个手动存档位 + 1个自动存档位
# 自动存档每120秒触发一次，关卡完成时也会触发
#
# Responsibilities:
#   - 存档/读档/删除/列出存档
#   - 自动存档定时触发
#   - JSON格式存档，带版本号用于前向兼容
#   - 损坏恢复: JSON解析失败时加载上次已知良好备份
#   - 版本迁移: 当前版本=1, 预留迁移函数
#
# Signals:
#   save_completed(slot) - 存档完成
#   save_failed(slot, error) - 存档失败
#   load_completed(slot) - 读档完成
#   load_failed(slot, error) - 读档失败
#
# Dependencies:
#   - Autoload: Logger, ErrorHandler, GameState, ConservationEngine, ProofTree,
#               SelfEvolve, TutorialManager, AIAssistant, LLMBridge, LevelManager

extends Node

const SAVE_VERSION := 1
const AUTO_SAVE_SLOT := 0
const MIN_SLOT := 0
const MAX_SLOT := 3
const AUTO_SAVE_INTERVAL := 120.0  # 秒
const SAVE_DIR := "user://saves"

# security: salt paired with OS.get_unique_id() in _derive_hmac_key() for machine-specific key
const SAVE_SIGNATURE_SALT := "intuita_v1_salt"

var _auto_save_timer: float = 0.0
var _total_playtime: float = 0.0
var _logger: Node = null

signal save_completed(slot: int)
signal save_failed(slot: int, error: String)
signal load_completed(slot: int)
signal load_failed(slot: int, error: String)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_save_dir()
	_logger = get_node_or_null("/root/GameLogger")
	if _logger:
		_logger.info("SaveManager", "Initialized, save dir: %s" % SAVE_DIR)


# security: machine-specific HMAC key prevents cross-machine save forgery
func _derive_hmac_key() -> PackedByteArray:
	var combined := (OS.get_unique_id() + SAVE_SIGNATURE_SALT).to_utf8_buffer()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(combined)
	return ctx.finish()


func _compute_signature(data: Dictionary) -> String:
	var parts: Array[String] = []
	parts.append(str(int(data.get("version", 0))))
	parts.append(str(data.get("timestamp", "")))
	parts.append(str(int(data.get("playtime_seconds", 0))))
	var gs: Dictionary = data.get("game_state", {})
	parts.append(str(int(gs.get("cores", 0))))
	parts.append(str(int(gs.get("evolve_points", 0))))
	parts.append(str(int(gs.get("current_chapter", 1))))
	parts.append(str(int(gs.get("current_level", 1))))
	var completed: Array = gs.get("levels_completed", [])
	var completed_strs: Array[String] = []
	for item in completed:
		completed_strs.append(str(item))
	parts.append(",".join(completed_strs))
	# security: include api_url in signature to prevent URL manipulation
	var settings: Dictionary = data.get("settings", {})
	var llm: Dictionary = settings.get("llm", {})
	parts.append(str(llm.get("api_url", "")))
	var payload := "|".join(parts)
	var key := _derive_hmac_key()
	var msg := payload.to_utf8_buffer()
	var hmac := Crypto.new().hmac_digest(HashingContext.HASH_SHA256, key, msg)
	return Marshalls.raw_to_base64(hmac)


# security: fail closed - reject on empty signature or any verification error
func _verify_signature(data: Dictionary, signature: String) -> bool:
	if signature.is_empty():
		return false
	var expected := _compute_signature(data)
	if expected.is_empty():
		return false
	if expected.length() != signature.length():
		return false
	var result := 0
	for i in range(expected.length()):
		result |= int(expected[i]) ^ int(signature[i])
	return result == 0


# security: reject paths containing ".." or starting with "/" to prevent traversal
func _validate_path(path: String) -> bool:
	if path.find("..") != -1:
		return false
	if path.begins_with("/"):
		return false
	return true


# security: validate .tres files don't embed GDScript or reference Script resources before loading
func validate_tres_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var content := file.get_as_text()
	file.close()
	# .tres is text format; reject if it embeds or references executable scripts
	if content.find("GDScript") != -1:
		return false
	if content.find('type="Script"') != -1:
		return false
	return true


func _process(delta: float) -> void:
	_total_playtime += delta
	_auto_save_timer += delta
	if _auto_save_timer >= AUTO_SAVE_INTERVAL:
		_auto_save_timer = 0.0
		call_deferred("save_game", AUTO_SAVE_SLOT)


# ============ 公共API ============

func save_game(slot: int = 0) -> bool:
	if slot < MIN_SLOT or slot > MAX_SLOT:
		if _logger: _logger.warn("SaveManager", "Invalid slot: %d" % slot)
		save_failed.emit(slot, "Invalid slot")
		return false

	var start_time := Time.get_ticks_msec()
	var data := _collect_save_data()
	data["signature"] = _compute_signature(data)
	var json_str := JSON.stringify(data, "\t")

	var file_path := _slot_path(slot)
	var backup_path := _slot_backup_path(slot)
	# security: validate paths to prevent traversal
	if not _validate_path(file_path) or not _validate_path(backup_path):
		save_failed.emit(slot, "Invalid path")
		return false
	if FileAccess.file_exists(file_path):
		var rename_ok := _rename_file(file_path, backup_path)
		if not rename_ok:
			if _logger: _logger.warn("SaveManager", "Failed to backup existing save for slot %d" % slot)

	# 写入新存档
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		if _logger: _logger.error("SaveManager", "Cannot open save file: %s" % file_path)
		# 尝试恢复备份
		if FileAccess.file_exists(backup_path):
			_rename_file(backup_path, file_path)
		save_failed.emit(slot, "File write error")
		return false

	file.store_string(json_str)
	file.close()

	var elapsed := Time.get_ticks_msec() - start_time
	if _logger: _logger.info("SaveManager", "Saved to slot %d (%dms)" % [slot, elapsed])
	if _logger: _logger.perf("SaveManager", "save_game", float(elapsed))

	save_completed.emit(slot)
	return true


func load_game(slot: int) -> bool:
	if slot < MIN_SLOT or slot > MAX_SLOT:
		if _logger: _logger.warn("SaveManager", "Invalid slot: %d" % slot)
		load_failed.emit(slot, "Invalid slot")
		return false

	var start_time := Time.get_ticks_msec()
	var file_path := _slot_path(slot)
	# security: validate path to prevent traversal
	if not _validate_path(file_path):
		load_failed.emit(slot, "Invalid path")
		return false

	if not FileAccess.file_exists(file_path):
		if _logger: _logger.warn("SaveManager", "Save file not found: %s" % file_path)
		load_failed.emit(slot, "File not found")
		return false

	var raw: String = ""
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		if _logger: _logger.error("SaveManager", "Cannot open save file: %s" % file_path)
		_try_load_backup(slot)
		return false

	raw = file.get_as_text()
	file.close()

	# JSON解析 - 带损坏恢复
	var json := JSON.new()
	var err := json.parse(raw)
	if err != OK:
		if _logger: _logger.error("SaveManager", "JSON parse error in slot %d, trying backup" % slot)
		ErrorHandler.report_error("ERROR", "Save file corrupted in slot %d" % slot, {"slot": slot})
		return _try_load_backup(slot)

	var data: Dictionary = json.data
	if not data.has("version"):
		if _logger: _logger.error("SaveManager", "Save file missing version field in slot %d" % slot)
		load_failed.emit(slot, "Invalid save format")
		return false

	# 签名验证（兼容旧存档：无 signature 字段则跳过）
	if data.has("signature"):
		var sig: String = str(data.get("signature", ""))
		var sig_valid := _verify_signature(data, sig)
		if not sig_valid:
			if _logger: _logger.error("SaveManager", "Signature verification failed for slot %d, trying backup" % slot)
			ErrorHandler.report_error("ERROR", "Save file tampered in slot %d" % slot, {"slot": slot})
			return _try_load_backup(slot)
	else:
		if _logger: _logger.warn("SaveManager", "Slot %d has no signature (legacy save), skipping verification" % slot)

	# 版本迁移
	data = _migrate_save(data)

	# 应用存档数据
	var apply_ok := _apply_save_data(data)
	if not apply_ok:
		if _logger: _logger.error("SaveManager", "Failed to apply save data from slot %d" % slot)
		load_failed.emit(slot, "Apply failed")
		return false

	var elapsed := Time.get_ticks_msec() - start_time
	if _logger: _logger.info("SaveManager", "Loaded slot %d (%dms)" % [slot, elapsed])
	if _logger: _logger.perf("SaveManager", "load_game", float(elapsed))

	load_completed.emit(slot)
	return true


func has_save(slot: int) -> bool:
	return not _load_raw_data(slot, _slot_path(slot)).is_empty()


func delete_save(slot: int) -> bool:
	var file_path := _slot_path(slot)
	var backup_path := _slot_backup_path(slot)

	var deleted := false
	if FileAccess.file_exists(file_path):
		var dir := DirAccess.open(SAVE_DIR)
		if dir:
			dir.remove(file_path)
			deleted = true
	if FileAccess.file_exists(backup_path):
		var dir := DirAccess.open(SAVE_DIR)
		if dir:
			dir.remove(backup_path)
			deleted = true

	if deleted:
		if _logger: _logger.info("SaveManager", "Deleted save in slot %d" % slot)
	return deleted


func _load_raw_data(slot: int, path: String) -> Dictionary:
	# 辅助函数：从文件路径加载并解析存档数据，包含签名验证
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var raw := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(raw) != OK:
		return {}
	var data: Dictionary = json.data
	if not data.has("version"):
		return {}
	if data.has("signature"):
		var sig: String = str(data.get("signature", ""))
		if not _verify_signature(data, sig):
			if _logger: _logger.error("SaveManager", "Signature verification failed for %s" % path)
			return {}
	return data


func get_save_info(slot: int) -> Dictionary:
	var data := _load_raw_data(slot, _slot_path(slot))
	if data.is_empty():
		return {}

	var game_state: Dictionary = data.get("game_state", {})
	var result := {
		"timestamp": data.get("timestamp", ""),
		"playtime": data.get("playtime_seconds", 0),
		"level": "%d-%d" % [game_state.get("current_chapter", 1), game_state.get("current_level", 1)],
		"chapter": game_state.get("current_chapter", 1),
		"cores": game_state.get("cores", 0),
		"version": data.get("version", 0),
	}
	# 标记签名状态
	if data.has("signature"):
		result["verified"] = true
	else:
		result["legacy"] = true
	return result


func list_saves() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot in range(MIN_SLOT, MAX_SLOT + 1):
		var info := get_save_info(slot)
		if not info.is_empty():
			info["slot"] = slot
			result.append(info)
	return result


func get_playtime() -> float:
	return _total_playtime


# 关卡完成时由外部调用触发自动存档
func on_level_completed() -> void:
	save_game(AUTO_SAVE_SLOT)


# ============ 存档数据收集 ============

func _collect_save_data() -> Dictionary:
	var data := {
		"version": SAVE_VERSION,
		"timestamp": Time.get_datetime_string_from_system(),
		"playtime_seconds": int(_total_playtime),
	}

	# 游戏状态
	data["game_state"] = _collect_game_state()

	# 关卡进度
	data["level_progress"] = _collect_level_progress()

	# 守恒矩阵
	data["conservation_matrix"] = _collect_conservation_matrix()

	# 证明树
	data["proof_tree"] = _collect_proof_tree()

	# 自定义规则
	data["custom_rules"] = _collect_custom_rules()

	# 设置
	data["settings"] = _collect_settings()

	return data


func _collect_game_state() -> Dictionary:
	var levels_completed: Array[String] = []
	if is_instance_valid(GameState):
		levels_completed = GameState.completed_levels.duplicate()

	var gs_cores: int = 0
	var gs_evolve: int = 0
	var gs_chapter: int = 1
	var gs_level: int = 1
	var gs_mode: int = 0
	if is_instance_valid(GameState):
		gs_cores = GameState.verification_cores
		gs_evolve = GameState.evolve_points
		gs_chapter = GameState.current_chapter
		gs_level = GameState.current_level
		gs_mode = GameState.current_mode
	return {
		"cores": gs_cores,
		"evolve_points": gs_evolve,
		"total_playtime": int(_total_playtime),
		"levels_completed": levels_completed,
		"current_chapter": gs_chapter,
		"current_level": gs_level,
		"current_mode": gs_mode,
		"ai_assistant_unlocked": AIAssistant.is_unlocked() if is_instance_valid(AIAssistant) else false,
		"tutorial_step": TutorialManager.get_current_step() if is_instance_valid(TutorialManager) else -1,
		"tutorial_completed": TutorialManager.is_completed() if is_instance_valid(TutorialManager) else false,
	}


func _collect_level_progress() -> Dictionary:
	var progress := {}
	if is_instance_valid(LevelManager):
		progress = {
			"atoms_placed": LevelManager.get_atoms_placed() if LevelManager.has_method("get_atoms_placed") else {},
			"bonds_built": LevelManager.get_bonds_built() if LevelManager.has_method("get_bonds_built") else [],
			"assembled_parts": LevelManager.get_assembled_parts() if LevelManager.has_method("get_assembled_parts") else {},
			"path_nodes": LevelManager.get_path_nodes() if LevelManager.has_method("get_path_nodes") else [],
			"goal_states": LevelManager.goal_states.duplicate(true),
		}
	return progress


func _collect_conservation_matrix() -> Array:
	# 4x4矩阵展平为16个float，行优先
	var flat: Array = []
	if is_instance_valid(ConservationEngine):
		for i in range(4):
			for j in range(4):
				flat.append(ConservationEngine.get_entry(i, j))
	else:
		# 默认单位矩阵
		for i in range(4):
			for j in range(4):
				flat.append(1.0 if i == j else 0.0)
	return flat


func _collect_proof_tree() -> Dictionary:
	var result := {"nodes": [], "current_node_id": -1}
	if not is_instance_valid(ProofTree):
		return result

	var all_nodes := ProofTree.get_all_nodes()
	var nodes_arr: Array[Dictionary] = []

	for id in all_nodes:
		var node = all_nodes[id]
		var parent_id: int = -1
		if node.parent != null:
			parent_id = node.parent.id

		var children_ids: Array[int] = []
		for child in node.children:
			children_ids.append(child.id)

		nodes_arr.append({
			"id": node.id,
			"operation": node.operation,
			"parent_id": parent_id,
			"children_ids": children_ids,
			"invariants": node.invariants.duplicate(true),
			"is_golden": node.is_golden,
			"depth": node.depth,
		})

	result["nodes"] = nodes_arr
	return result


func _collect_custom_rules() -> Array:
	if not is_instance_valid(SelfEvolve):
		return []
	var rules: Array = []
	for rule in SelfEvolve.custom_rules:
		var rule_copy := rule.duplicate(true)
		# Color不能直接序列化，转为数组
		if rule_copy.has("color") and rule_copy["color"] is Color:
			var c: Color = rule_copy["color"]
			rule_copy["color"] = [c.r, c.g, c.b, c.a]
		rules.append(rule_copy)
	return rules


func _collect_settings() -> Dictionary:
	var settings := {}

	# LLM配置（只保存endpoint，不保存key）
	if is_instance_valid(LLMBridge):
		settings["llm"] = {
			"api_url": LLMBridge.api_url,
			"model_name": LLMBridge.model_name,
			"token_budget": LLMBridge.token_budget_per_session,
		}

	return settings


# ============ 存档数据应用 ============

func _apply_save_data(data: Dictionary) -> bool:
	var game_state: Dictionary = data.get("game_state", {})
	_apply_game_state(game_state)

	var level_progress: Dictionary = data.get("level_progress", {})
	_apply_level_progress(level_progress)

	var matrix_flat: Array = data.get("conservation_matrix", [])
	_apply_conservation_matrix(matrix_flat)

	var proof_tree: Dictionary = data.get("proof_tree", {})
	_apply_proof_tree(proof_tree)

	var custom_rules: Array = data.get("custom_rules", [])
	_apply_custom_rules(custom_rules)

	var settings: Dictionary = data.get("settings", {})
	_apply_settings(settings)

	# 恢复游玩时间
	_total_playtime = float(data.get("playtime_seconds", 0))

	return true


func _apply_game_state(gs: Dictionary) -> void:
	if gs.is_empty():
		return

	if is_instance_valid(GameState):
		GameState.verification_cores = int(gs.get("cores", 10))
		GameState.evolve_points = int(gs.get("evolve_points", 0))
		GameState.set_chapter(int(gs.get("current_chapter", 1)))
		GameState.set_level(int(gs.get("current_level", 1)))
		GameState.current_mode = int(gs.get("current_mode", 0))
		# 恢复已通关关卡列表
		GameState.completed_levels.clear()
		for key in gs.get("levels_completed", []):
			GameState.completed_levels.append(str(key))

	# AI助手状态
	var ai_unlocked: bool = gs.get("ai_assistant_unlocked", false)
	if ai_unlocked and is_instance_valid(AIAssistant):
		# 直接设置解锁状态（绕过时间检查）
		if AIAssistant.has_method("set_unlocked"):
			AIAssistant.set_unlocked(true)
		AIAssistant.assistant_unlocked.emit()

	# 教程状态
	var tutorial_step: int = int(gs.get("tutorial_step", -1))
	var tutorial_completed: bool = gs.get("tutorial_completed", false)
	if is_instance_valid(TutorialManager):
		if tutorial_completed:
			if TutorialManager.has_method("set_completed"):
				TutorialManager.set_completed(true)
		elif tutorial_step >= 0:
			if TutorialManager.has_method("set_current_step"):
				TutorialManager.set_current_step(tutorial_step)


func _apply_level_progress(lp: Dictionary) -> void:
	if lp.is_empty():
		return

	if is_instance_valid(LevelManager):
		var atoms: Dictionary = lp.get("atoms_placed", {})
		if LevelManager.has_method("set_atoms_placed"):
			LevelManager.set_atoms_placed(atoms)

		var bonds: Array = lp.get("bonds_built", [])
		if LevelManager.has_method("set_bonds_built"):
			LevelManager.set_bonds_built(bonds)

		var assembled: Dictionary = lp.get("assembled_parts", {})
		if LevelManager.has_method("set_assembled_parts"):
			LevelManager.set_assembled_parts(assembled)

		var path_nodes: Array = lp.get("path_nodes", [])
		if LevelManager.has_method("set_path_nodes"):
			LevelManager.set_path_nodes(path_nodes)

		var goal_states: Array = lp.get("goal_states", [])
		LevelManager.goal_states.clear()
		for s in goal_states:
			LevelManager.goal_states.append(int(s))


func _apply_conservation_matrix(flat: Array) -> void:
	if flat.size() != 16:
		if _logger: _logger.warn("SaveManager", "Conservation matrix has %d entries, expected 16" % flat.size())
		return

	if not is_instance_valid(ConservationEngine):
		return

	for i in range(4):
		for j in range(4):
			var idx := i * 4 + j
			if idx < flat.size():
				ConservationEngine.set_entry(i, j, float(flat[idx]))


func _apply_proof_tree(pt: Dictionary) -> void:
	if not is_instance_valid(ProofTree):
		return

	ProofTree.clear()

	var nodes: Array = pt.get("nodes", [])
	if nodes.is_empty():
		return

	# 先创建所有节点（不带parent连接）
	var id_to_node: Dictionary = {}
	for node_data in nodes:
		var nid: int = int(node_data.get("id", 0))
		var operation: String = str(node_data.get("operation", ""))
		var node = ProofTree.add_node(operation, null, node_data.get("invariants", {}))
		# add_node会分配新id，我们需要映射旧id到新节点
		id_to_node[nid] = node
		node.is_golden = node_data.get("is_golden", false)
		node.depth = int(node_data.get("depth", 0))

	# 重建父子关系
	for node_data in nodes:
		var old_id: int = int(node_data.get("id", 0))
		var parent_id: int = int(node_data.get("parent_id", -1))
		if parent_id >= 0 and id_to_node.has(parent_id) and id_to_node.has(old_id):
			var parent_node = id_to_node[parent_id]
			var child_node = id_to_node[old_id]
			if child_node.parent == null:
				parent_node.add_child(child_node)


func _apply_custom_rules(rules: Array) -> void:
	if not is_instance_valid(SelfEvolve):
		return

	SelfEvolve.custom_rules.clear()
	for rule_data in rules:
		var rule: Dictionary = rule_data.duplicate(true)
		# Color从数组恢复
		if rule.has("color") and rule["color"] is Array:
			var c: Array = rule["color"]
			rule["color"] = Color(
				float(c[0]) if c.size() > 0 else 1.0,
				float(c[1]) if c.size() > 1 else 1.0,
				float(c[2]) if c.size() > 2 else 1.0,
				float(c[3]) if c.size() > 3 else 1.0,
			)
		SelfEvolve.custom_rules.append(rule)


func _apply_settings(settings: Dictionary) -> void:
	var llm: Dictionary = settings.get("llm", {})
	if not llm.is_empty() and is_instance_valid(LLMBridge):
		LLMBridge.api_url = str(llm.get("api_url", LLMBridge.api_url))
		LLMBridge.model_name = str(llm.get("model_name", LLMBridge.model_name))
		LLMBridge.token_budget_per_session = int(llm.get("token_budget", LLMBridge.token_budget_per_session))


# ============ 版本迁移 ============

func _migrate_save(data: Dictionary) -> Dictionary:
	var version: int = data.get("version", 1)

	# 从旧版本逐步迁移到最新版本
	while version < SAVE_VERSION:
		version += 1
		match version:
			1:
				pass  # 当前版本，无需迁移
			_:
				if _logger: _logger.warn("SaveManager", "Unknown save version: %d" % version)
				break

	data["version"] = SAVE_VERSION
	return data


# ============ 损坏恢复 ============

func _try_load_backup(slot: int) -> bool:
	var backup_path := _slot_backup_path(slot)
	var data := _load_raw_data(slot, backup_path)
	if data.is_empty():
		if _logger: _logger.error("SaveManager", "No valid backup available for slot %d" % slot)
		load_failed.emit(slot, "No valid backup available")
		return false

	if _logger: _logger.info("SaveManager", "Loaded backup for slot %d" % slot)

	data = _migrate_save(data)
	var apply_ok := _apply_save_data(data)

	if apply_ok:
		load_completed.emit(slot)
		# 把备份恢复为主存档
		_rename_file(backup_path, _slot_path(slot))
	else:
		load_failed.emit(slot, "Failed to apply backup data")

	return apply_ok


# ============ 工具方法 ============

func _ensure_save_dir() -> void:
	var dir := DirAccess.open("user://")
	if dir and not dir.dir_exists("saves"):
		dir.make_dir("saves")


func _slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]


func _slot_backup_path(slot: int) -> String:
	return "%s/slot_%d.bak" % [SAVE_DIR, slot]


func _rename_file(from: String, to: String) -> bool:
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return false
	# 如果目标已存在，先删除
	if FileAccess.file_exists(to):
		dir.remove(to.get_file())
	var err := dir.rename(from.get_file(), to.get_file())
	return err == OK
