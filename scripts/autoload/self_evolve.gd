# self_evolve.gd
# 自进化系统 - 玩家创建和分享自定义构造规则
# 对应Brouwer的"创造性主体"理论: 存在即被构造
#
# Responsibilities:
#   - 进化点数管理（完成关卡获得，1核心=1进化点）
#   - 自定义规则创建、验证、存储
#   - 规则模板提供（量子隧穿/热激发/应变工程/缺陷工程）
#   - 规则导入导出（.intuita_rule JSON文件）
#   - 规则应用时的守恒矩阵更新
#
# Signals:
#   evolve_points_changed(new_amount) - 进化点数变化
#   rule_created(rule) - 新规则创建
#   rule_validated(rule, passed) - 规则验证结果
#   rule_applied(rule) - 规则被应用
#   rule_imported(rule) - 规则被导入
#
# Dependencies:
#   - Autoload: GameState, ConservationEngine

extends Node

const MIN_EVOLVE_POINTS_TO_CREATE := 5
const RULE_FILE_EXTENSION := ".intuita_rule"

# 守恒矩阵行名: 0=mass, 1=charge, 2=momentum, 3=energy
const ROW_NAMES := ["mass", "charge", "momentum", "energy"]

var _evolve_points: int = 0
var _on_cores_changed_conn: Callable
var evolve_points: int:
	get:
		return _evolve_points
	set(v):
		_evolve_points = maxi(v, 0)
		evolve_points_changed.emit(_evolve_points)

var custom_rules: Array[Dictionary] = []
var _rule_templates: Array[Dictionary] = []

signal evolve_points_changed(new_amount: int)
signal rule_created(rule: Dictionary)
signal rule_validated(rule: Dictionary, passed: bool)
signal rule_applied(rule: Dictionary)
signal rule_imported(rule: Dictionary)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_init_templates()
	_on_cores_changed_conn = _on_cores_changed
	GameState.cores_changed.connect(_on_cores_changed_conn)

func _exit_tree() -> void:
	if GameState.cores_changed.is_connected(_on_cores_changed_conn):
		GameState.cores_changed.disconnect(_on_cores_changed_conn)


func _init_templates() -> void:
	_rule_templates.clear()

	# 量子隧穿: 原子穿越能量势垒，影响动量行
	_rule_templates.append({
		"name": "量子隧穿",
		"description": "允许原子穿越能量势垒，动量行微扰",
		"conservation_impact": {"2_2": -0.05, "2_3": 0.02},
		"cost_evolve": 3,
		"cost_cores": 1,
		"color": Color(0.3, 0.7, 1.0),
	})

	# 热激发: 热涨落影响位置，影响能量行
	_rule_templates.append({
		"name": "热激发",
		"description": "添加热涨落到原子位置，能量行微扰",
		"conservation_impact": {"3_3": -0.03, "3_0": 0.01},
		"cost_evolve": 2,
		"cost_cores": 1,
		"color": Color(1.0, 0.5, 0.2),
	})

	# 应变工程: 均匀应变影响晶格，影响质量行
	_rule_templates.append({
		"name": "应变工程",
		"description": "对晶格施加均匀应变，质量行微扰",
		"conservation_impact": {"0_0": -0.04, "0_1": 0.01},
		"cost_evolve": 4,
		"cost_cores": 2,
		"color": Color(0.2, 1.0, 0.5),
	})

	# 缺陷工程: 点缺陷+电荷补偿，影响电荷行
	_rule_templates.append({
		"name": "缺陷工程",
		"description": "引入点缺陷并进行电荷补偿，电荷行微扰",
		"conservation_impact": {"1_1": -0.06, "1_2": 0.02},
		"cost_evolve": 5,
		"cost_cores": 2,
		"color": Color(1.0, 0.3, 0.8),
	})


# ============ 进化点数 ============

func _on_cores_changed(new_count: int) -> void:
	# 核心变化时同步进化点数（关卡完成时gain_cores已经调用过了）
	pass


func gain_evolve_points(amount: int) -> void:
	evolve_points += amount


func spend_evolve_points(amount: int) -> bool:
	if evolve_points < amount:
		return false
	evolve_points -= amount
	return true


# ============ 规则创建 ============

func create_rule(name: String, description: String, conservation_impact: Dictionary, cost_evolve: int, cost_cores: int, color: Color) -> Dictionary:
	var rule := _build_rule(name, description, conservation_impact, cost_evolve, cost_cores, color)

	# 验证规则
	var validation := validate_rule(rule)
	rule.validated = validation.passed
	rule.validation_proof = validation.proof

	if not validation.passed:
		rule_validated.emit(rule, false)
		return rule

	# 检查进化点数
	if evolve_points < MIN_EVOLVE_POINTS_TO_CREATE:
		push_warning("进化点数不足，至少需要%d点" % MIN_EVOLVE_POINTS_TO_CREATE)
		rule.validated = false
		rule_validated.emit(rule, false)
		return rule

	# 扣除创建费用
	spend_evolve_points(MIN_EVOLVE_POINTS_TO_CREATE)

	custom_rules.append(rule)
	rule_created.emit(rule)
	rule_validated.emit(rule, true)

	GameLogger.info("SelfEvolve", "[自进化] 规则已创建: %s (消耗%d进化点)" % [name, MIN_EVOLVE_POINTS_TO_CREATE])
	return rule


func create_rule_from_template(template_index: int, custom_name: String, custom_impact_mods: Dictionary = {}) -> Dictionary:
	if template_index < 0 or template_index >= _rule_templates.size():
		push_warning("模板索引越界: %d" % template_index)
		return {}

	var template: Dictionary = _rule_templates[template_index]

	# 合并模板影响和自定义修改
	var impact: Dictionary = {}
	for key in template.conservation_impact:
		impact[key] = template.conservation_impact[key]
	for key in custom_impact_mods:
		impact[key] = impact.get(key, 0.0) + custom_impact_mods[key]

	var rule := create_rule(
		custom_name if custom_name != "" else template.name,
		template.description,
		impact,
		template.cost_evolve,
		template.cost_cores,
		template.color,
	)

	return rule


func _build_rule(name: String, description: String, conservation_impact: Dictionary, cost_evolve: int, cost_cores: int, color: Color) -> Dictionary:
	return {
		"id": _generate_uuid(),
		"name": name,
		"description": description,
		"creator": "Player",
		"created_at": Time.get_unix_time_from_system(),
		"conservation_impact": conservation_impact,
		"cost_evolve": cost_evolve,
		"cost_cores": cost_cores,
		"color": color,
		"validated": false,
		"validation_proof": {},
	}


func _generate_uuid() -> String:
	# 简单UUID生成，不依赖外部库
	var rng := RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_usec()
	var hex := "0123456789abcdef"
	var uuid := ""
	for i in range(32):
		if i == 8 or i == 12 or i == 16 or i == 20:
			uuid += "-"
		uuid += hex[rng.randi() % 16]
	return uuid


# ============ 规则验证 ============

func validate_rule(rule: Dictionary) -> Dictionary:
	var impact: Dictionary = rule.get("conservation_impact", {})
	var result := _check_conservation_impact(impact)

	var proof := {
		"timestamp": Time.get_unix_time_from_system(),
		"impact_entries": impact.size(),
		"max_eigenvalue_deviation": result.max_deviation,
		"has_negative_eigenvalue": result.has_negative,
		"borderline": result.borderline,
		"passed": result.passed,
	}

	return {"passed": result.passed, "proof": proof}


func validate_impact(conservation_impact: Dictionary) -> Dictionary:
	# 实时验证接口，给UI滑条用
	return _check_conservation_impact(conservation_impact)


func _check_conservation_impact(impact: Dictionary) -> Dictionary:
	# 将impact应用到当前矩阵的副本上，检查特征值
	var test_matrix := _copy_current_matrix()

	for key in impact:
		var parts: PackedStringArray = key.split("_")
		if parts.size() != 2:
			continue
		var row := int(parts[0])
		var col := int(parts[1])
		var delta: float = impact[key]
		if row >= 0 and row < 4 and col >= 0 and col < 4:
			test_matrix[row][col] += delta

	# 用ConservationEngine的方法计算特征值
	var eigenvalues := _compute_test_eigenvalues(test_matrix)

	var max_deviation := 0.0
	var has_negative := false
	var borderline := false

	for ev in eigenvalues:
		var dev := absf(ev - 1.0)
		if dev > max_deviation:
			max_deviation = dev
		if ev < 0.0:
			has_negative = true
		if dev > 0.25 and dev <= 0.3:
			borderline = true

	# 负特征值 → 验证失败
	# 偏离过大 → 也失败
	var passed := not has_negative and max_deviation <= 0.3

	return {
		"passed": passed,
		"max_deviation": max_deviation,
		"has_negative": has_negative,
		"borderline": borderline,
		"eigenvalues": eigenvalues,
	}


func _copy_current_matrix() -> Array:
	var copy: Array = []
	for i in range(4):
		var row: Array = []
		for j in range(4):
			row.append(ConservationEngine.get_entry(i, j))
		copy.append(row)
	return copy


func _compute_test_eigenvalues(a: Array) -> Array:
	# 复用ConservationEngine的特征值计算逻辑
	# Householder + QR迭代
	MatrixMath.hessenberg_reduce(a)
	return MatrixMath.qr_eigenvalues(a, 50)


# ============ 规则应用 ============

func apply_rule(rule_id: String) -> bool:
	var rule := _find_rule_by_id(rule_id)
	if rule.is_empty():
		push_warning("规则未找到: %s" % rule_id)
		return false

	if not rule.validated:
		push_warning("规则未通过验证: %s" % rule.name)
		return false

	# 检查进化点数和核心
	if evolve_points < rule.cost_evolve:
		push_warning("进化点数不足: 需要%d，当前%d" % [rule.cost_evolve, evolve_points])
		return false

	if not GameState.spend_cores(rule.cost_cores):
		push_warning("验证核心不足: 需要%d" % rule.cost_cores)
		return false

	spend_evolve_points(rule.cost_evolve)

	# 应用守恒矩阵影响
	var impact: Dictionary = rule.conservation_impact
	for key in impact:
		var parts: PackedStringArray = key.split("_")
		if parts.size() != 2:
			continue
		var row := int(parts[0])
		var col := int(parts[1])
		var delta: float = impact[key]
		ConservationEngine.apply_perturbation(row, col, delta)

	rule_applied.emit(rule)
	GameLogger.info("SelfEvolve", "[自进化] 规则已应用: %s" % rule.name)
	return true


func _find_rule_by_id(rule_id: String) -> Dictionary:
	for rule in custom_rules:
		if rule.id == rule_id:
			return rule
	return {}


# ============ 导入导出 ============

func export_rule(rule_id: String, file_path: String = "") -> bool:
	var rule := _find_rule_by_id(rule_id)
	if rule.is_empty():
		return false

	if file_path == "":
		file_path = "user://rules/%s%s" % [rule.name, RULE_FILE_EXTENSION]

	var dir := DirAccess.open("user://")
	if dir and not dir.dir_exists("rules"):
		dir.make_dir("rules")

	var export_data := {
		"format_version": 1,
		"rule": {
			"id": rule.id,
			"name": rule.name,
			"description": rule.description,
			"creator": rule.creator,
			"created_at": rule.created_at,
			"conservation_impact": rule.conservation_impact,
			"cost_evolve": rule.cost_evolve,
			"cost_cores": rule.cost_cores,
			"color": [rule.color.r, rule.color.g, rule.color.b, rule.color.a],
			"validated": rule.validated,
			"validation_proof": rule.validation_proof,
		},
	}

	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_warning("无法写入规则文件: %s" % file_path)
		return false

	file.store_string(JSON.stringify(export_data, "\t"))
	GameLogger.info("SelfEvolve", "[自进化] 规则已导出: %s → %s" % [rule.name, file_path])
	return true


func import_rule(file_path: String) -> Dictionary:
	# 路径遍历检查
	if file_path.find("..") != -1:
		push_warning("规则文件路径不合法: %s" % file_path)
		return {}

	if not FileAccess.file_exists(file_path):
		push_warning("规则文件不存在: %s" % file_path)
		return {}

	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_warning("无法读取规则文件: %s" % file_path)
		return {}

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_warning("规则文件JSON解析失败: %s" % file_path)
		return {}

	var data: Dictionary = json.data
	var rule_data: Dictionary = data.get("rule", {})

	if rule_data.is_empty():
		push_warning("规则文件缺少rule字段: %s" % file_path)
		return {}

	# 结构验证: 必须包含必要字段
	var required_fields := ["id", "name", "description", "conservation_impact"]
	for field in required_fields:
		if not rule_data.has(field):
			push_warning("规则缺少必要字段: %s" % field)
			return {}

	# 名称长度限制
	var rule_name: String = str(rule_data.get("name", ""))
	if rule_name.length() > 50:
		push_warning("规则名称过长（最多50字符）: %d" % rule_name.length())
		return {}

	# 描述长度限制
	var rule_desc: String = str(rule_data.get("description", ""))
	if rule_desc.length() > 200:
		push_warning("规则描述过长（最多200字符）: %d" % rule_desc.length())
		return {}

	# conservation_impact值验证
	var impact: Dictionary = rule_data.get("conservation_impact", {})
	for key in impact:
		var val = impact[key]
		if not val is float and not val is int:
			push_warning("conservation_impact值必须是数字: %s" % key)
			return {}
		var num_val: float = float(val)
		if num_val < -10.0 or num_val > 10.0:
			push_warning("conservation_impact值超出范围(-10~10): %s=%f" % [key, num_val])
			return {}

	# 清理控制字符
	rule_name = _sanitize_string(rule_name)
	rule_desc = _sanitize_string(rule_desc)

	# 重建Color
	var color_arr: Array = rule_data.get("color", [1.0, 1.0, 1.0, 1.0])
	var color := Color(
		color_arr[0] if color_arr.size() > 0 else 1.0,
		color_arr[1] if color_arr.size() > 1 else 1.0,
		color_arr[2] if color_arr.size() > 2 else 1.0,
		color_arr[3] if color_arr.size() > 3 else 1.0,
	)

	var rule := {
		"id": rule_data.get("id", _generate_uuid()),
		"name": rule_name,
		"description": rule_desc,
		"creator": rule_data.get("creator", "Unknown"),
		"created_at": rule_data.get("created_at", 0),
		"conservation_impact": impact,
		"cost_evolve": rule_data.get("cost_evolve", 3),
		"cost_cores": rule_data.get("cost_cores", 1),
		"color": color,
		"validated": false,
		"validation_proof": rule_data.get("validation_proof", {}),
	}

	# 重新验证导入的规则
	var validation := validate_rule(rule)
	rule.validated = validation.passed
	rule.validation_proof = validation.proof

	custom_rules.append(rule)
	rule_imported.emit(rule)
	GameLogger.info("SelfEvolve", "[自进化] 规则已导入: %s (来自%s)" % [rule.name, rule.creator])
	return rule


func _sanitize_string(text: String) -> String:
	# 移除控制字符（保留换行和制表符）
	var result := ""
	for ch in text:
		var code: int = ch.unicode_at(0)
		if code >= 0x20 or code == 0x09 or code == 0x0A or code == 0x0D:
			result += ch
	return result


# ============ 查询 ============

func get_templates() -> Array[Dictionary]:
	return _rule_templates


func get_all_rules() -> Array[Dictionary]:
	return custom_rules


func get_rule_by_name(name: String) -> Dictionary:
	for rule in custom_rules:
		if rule.name == name:
			return rule
	return {}


func is_chapter1_complete() -> bool:
	# 第一章全部10关完成后才解锁自进化，确保玩家充分理解守恒矩阵
	return GameState.current_chapter > 1
