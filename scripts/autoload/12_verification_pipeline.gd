# verification_pipeline.gd
# 五层验证管线 - 从符号验证到Z3形式化约束验证
# 每层消耗不同数量的验证核心
#
# Responsibilities:
#   - 五层验证执行（符号/类型/逻辑/LLM语义/Z3形式化）
#   - 核心消耗管理
#   - 验证日志记录
#
# Signals:
#   verification_started(layer) - 验证开始
#   verification_completed(layer, result, confidence) - 验证完成
#
# Dependencies:
#   - Autoload: GameState（核心消耗）

extends Node

# 验证层常量 - 供外部脚本引用
const LAYER_SYMBOLIC: int = 0
const LAYER_TYPE_SYSTEM: int = 1
const LAYER_LOGIC: int = 2
const LAYER_LLM_SEMANTIC: int = 3
const LAYER_FORMAL: int = 4

enum VerificationLayer {
	SYMBOLIC,       # L1: 符号验证 - 免费
	TYPE_SYSTEM,    # L2: 类型系统检查 - 免费
	LOGIC,          # L3: 逻辑推理 - 1核心
	LLM_SEMANTIC,   # L4: LLM语义验证 - 2核心
	FORMAL,         # L5: 形式化约束验证(Z3/GDScript) - 5核心
}

const CORE_COSTS: Array[int] = [0, 0, 1, 2, 5]
const LAYER_NAMES: Array[String] = ["Symbolic", "TypeSystem", "Logic", "LLM", "Formal"]
const CORE_REWARDS: Array[int] = [0, 0, 1, 2, 5]  # 高层验证通过后返还核心

var _verification_log: Array[Dictionary] = []
var _z3_available: bool = false

signal verification_started(layer: int)
signal verification_completed(layer: int, result: bool, confidence: float)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_check_z3_availability()


func _check_z3_availability() -> void:
	var test_output: Array[String] = []
	var exit_code: int = -1

	# 先检查 z3 可执行文件是否在 PATH 中，避免 OS.execute 找不到时触发 Godot ERROR 日志
	if OS.get_name() == "Windows":
		var where_output: Array[String] = []
		var where_exit: int = OS.execute("cmd", ["/c", "where z3 >nul 2>&1"], where_output, true, true)
		if where_exit != 0:
			_z3_available = false
			return
	else:
		var which_output: Array[String] = []
		var which_exit: int = OS.execute("which", ["z3"], which_output, true, true)
		if which_exit != 0:
			_z3_available = false
			return

	exit_code = OS.execute("z3", ["--version"], test_output, true, true)
	_z3_available = (exit_code == 0)



func get_core_cost(layer: VerificationLayer) -> int:
	return CORE_COSTS[layer]


func verify(layer: VerificationLayer, statement: String, context: Dictionary = {}) -> Dictionary:
	verification_started.emit(layer)

	var cost: int = CORE_COSTS[layer]
	if cost > 0:
		if not GameState.spend_cores(cost):
			var fail_result: Dictionary = {"success": false, "confidence": 0.0, "reason": "insufficient_cores"}
			verification_completed.emit(layer, false, 0.0)
			return fail_result

	var result: Dictionary = await _run_verification(layer, statement, context)

	var log_entry: Dictionary = {
		"layer": layer,
		"layer_name": LAYER_NAMES[layer],
		"statement": statement,
		"success": result.success,
		"confidence": result.confidence,
		"timestamp": Time.get_ticks_msec(),
	}
	_verification_log.append(log_entry)

	# 高层验证通过后返还核心 — 投资回报机制
	if result.success and CORE_REWARDS[layer] > 0:
		GameState.gain_cores(CORE_REWARDS[layer])

	verification_completed.emit(layer, result.success, result.confidence)
	return result


func _run_verification(layer: VerificationLayer, statement: String, context: Dictionary) -> Dictionary:
	# 各层验证逻辑 - 当前为简化实现
	# 后续Rust GDExtension会替换核心计算
	match layer:
		VerificationLayer.SYMBOLIC:
			return _verify_symbolic(statement, context)
		VerificationLayer.TYPE_SYSTEM:
			return _verify_type_system(statement, context)
		VerificationLayer.LOGIC:
			return _verify_logic(statement, context)
		VerificationLayer.LLM_SEMANTIC:
			return await _verify_llm(statement, context)
		VerificationLayer.FORMAL:
			return await _verify_formal(statement, context)
		_:
			return {"success": false, "confidence": 0.0, "reason": "unknown_layer"}


func _verify_symbolic(statement: String, _context: Dictionary) -> Dictionary:
	# L1: 符号验证 - 检查基本语法和符号一致性
	var is_valid := statement.length() > 0 and not statement.strip_edges().is_empty()
	var confidence := 1.0 if is_valid else 0.0
	return {"success": is_valid, "confidence": confidence}


func _verify_type_system(statement: String, _context: Dictionary) -> Dictionary:
	# L2: 类型系统检查 - 验证类型一致性
	# 简化: 检查是否有明显的类型冲突标记
	var has_type_error := statement.find("TYPE_ERROR") != -1
	var success := not has_type_error
	var confidence := 0.95 if success else 0.1
	return {"success": success, "confidence": confidence}


func _verify_logic(statement: String, context: Dictionary) -> Dictionary:
	# L3: 逻辑推理 - 检查前提和结论的逻辑一致性
	var premises: Array = []
	if context.has("premises"):
		premises = context["premises"]
	var has_contradiction := false

	# 简化检查: 前提中是否有直接矛盾
	for i in range(premises.size()):
		for j in range(i + 1, premises.size()):
			if str(premises[i]) == "NOT " + str(premises[j]) or "NOT " + str(premises[i]) == str(premises[j]):
				has_contradiction = true

	var success := not has_contradiction and statement.length() > 0
	var confidence := 0.85 if success else 0.2
	return {"success": success, "confidence": confidence}


func _verify_llm(statement: String, context: Dictionary) -> Dictionary:
	# L4: LLM语义验证 - 通过LLMBridge请求
	if not LLMBridge.has_api_key():
		# 无API Key时使用启发式回退
		var score := _heuristic_score(statement)
		return {"success": score > 0.6, "confidence": score, "reason": "no_api_key_heuristic"}

	var rid: int = LLMBridge.send_request(
		"verify_%s" % statement,
		context,
		LLMBridge.Priority.MEDIUM
	)

	# 等待LLM响应（最多3秒）
	var result: Variant = await _wait_for_llm_response(rid, 3.0)

	if result != null:
		var text: String = result.get("text", "")
		var llm_score := _parse_llm_verification(text)
		return {"success": llm_score > 0.6, "confidence": llm_score, "reason": "llm_verified"}

	# LLM超时或失败，回退到启发式
	var score := _heuristic_score(statement)
	return {"success": score > 0.6, "confidence": score, "reason": "llm_timeout_heuristic"}


func _wait_for_llm_response(rid: int, timeout_sec: float) -> Variant:
	var timer: SceneTreeTimer = get_tree().create_timer(timeout_sec)
	var received := false
	var response_text := ""

	var callable := func(_req_id: int, text: String):
		if _req_id == rid:
			response_text = text
			received = true
	LLMBridge.response_received.connect(callable)

	while not received and not timer.time_left <= 0:
		await get_tree().process_frame

	LLMBridge.response_received.disconnect(callable)

	if received:
		return {"text": response_text}
	return null


func _heuristic_score(statement: String) -> float:
	var score := 0.5
	if statement.length() > 20:
		score += 0.1
	if statement.find("therefore") != -1 or statement.find("所以") != -1:
		score += 0.15
	if statement.find("because") != -1 or statement.find("因为") != -1:
		score += 0.1
	if statement.find("conservation") != -1 or statement.find("守恒") != -1:
		score += 0.1
	return minf(score, 1.0)


func _parse_llm_verification(text: String) -> float:
	# 解析LLM返回的验证结果
	text = text.to_lower()
	if text.find("verified") != -1 or text.find("confirmed") != -1 or text.find("验证通过") != -1:
		return 0.9
	if text.find("likely correct") != -1 or text.find("可能正确") != -1:
		return 0.75
	if text.find("incorrect") != -1 or text.find("不正确") != -1 or text.find("invalid") != -1:
		return 0.2
	if text.find("uncertain") != -1 or text.find("不确定") != -1:
		return 0.5
	return 0.6


func _verify_formal(statement: String, context: Dictionary) -> Dictionary:
	# L5: 形式化约束验证 - 使用Z3 SMT Solver
	#
	# 为什么用Z3而不是证明助手（如Lean4）：
	# - 证明助手需要构造完整证明，Z3只需声明约束并检查可满足性
	# - 守恒矩阵验证本质是"这组约束是否可满足"，Z3直接回答这个问题
	# - SMT2格式简单：`(assert (= M_ii 1.0))` vs 证明助手需要形式化整个框架
	# - Z3有Rust crate可直接集成，也可通过命令行调用
	#
	# 三级回退：Z3命令行 → Rust ConservationEngine → GDScript对角检查

	# 1. 尝试Z3 SMT2验证（仅当Z3可用时）
	if _z3_available:
		var smt2_code: String = _generate_smt2(statement, context)
		if not smt2_code.is_empty():
			var z3_result: Variant = await _run_z3(smt2_code)
			if z3_result != null:
				return z3_result

	# 2. 回退到Rust守恒矩阵特征值验证
	return _verify_conservation_fallback(context)


# security: sanitize user-provided formulas before embedding in SMT2 to prevent injection
func _sanitize_formula(formula: String) -> String:
	# reject dangerous keywords that could invoke commands
	if formula.find("exec") != -1:
		return ""
	# only allow alphanumeric, basic math operators, and spaces — no parens, semicolons, or newlines
	var regex := RegEx.new()
	regex.compile("^[a-zA-Z0-9 +*/=<>-]*$")
	if not regex.search(formula):
		return ""
	return formula


func _generate_smt2(statement: String, context: Dictionary) -> String:
	# 从守恒矩阵生成SMT2约束
	# 核心验证：4×4守恒矩阵是否满足守恒律
	# 使用 declare-const + assert 绑定实际值，让Z3真正做约束求解
	# 而非简单常量代入（define-fun 会让Z3退化为算术计算器）
	var matrix_data: Array = []
	if context.has("matrix"):
		matrix_data = context["matrix"]
	if matrix_data.size() != 16:
		return ""

	var rows: Array[String] = ["M", "Q", "P", "E"]
	var code: String = "; Intuita Conservation Verification (SMT2/Z3)\n"
	# security: sanitize statement before embedding in SMT2 comment to prevent injection
	code += "; Statement: %s\n\n" % _sanitize_formula(statement)
	code += "(set-logic QF_NRA)\n"

	# 声明16个实数变量代表矩阵元素
	code += "\n; 守恒矩阵变量\n"
	for i in range(4):
		for j in range(4):
			code += "(declare-const %s_%s Real)\n" % [rows[i], rows[j]]

	# 绑定变量到实际矩阵值
	code += "\n; 绑定到实际矩阵值\n"
	for i in range(4):
		for j in range(4):
			var idx: int = i * 4 + j
			var val: float = float(matrix_data[idx])
			code += "(assert (= %s_%s %.6f))\n" % [rows[i], rows[j], val]

	# 守恒律约束：对角元素应接近1.0（自守恒）
	code += "\n; 守恒律：对角元素 ≈ 1.0\n"
	var tolerance: float = 0.05
	for i in range(4):
		code += "(assert (< (abs (- %s_%s 1.0)) %.4f))\n" % [rows[i], rows[i], tolerance]

	# 非对角元素应接近0.0（交叉守恒弱耦合）
	code += "\n; 守恒律：非对角元素 ≈ 0.0\n"
	for i in range(4):
		for j in range(4):
			if i != j:
				var idx: int = i * 4 + j
				var val: float = absf(float(matrix_data[idx]))
				if val > 0.01:
					code += "(assert (< (abs %s_%s) 0.5))\n" % [rows[i], rows[j]]

	# 行列式约束：守恒矩阵行列式应接近1.0（体积守恒）
	# det(M) = M_00*(M_11*(M_22*M_33 - M_23*M_32) - M_12*(M_21*M_33 - M_23*M_31) + M_13*(M_21*M_32 - M_22*M_31))
	# 对4x4完整行列式太复杂，这里用对角行列式近似
	code += "\n; 行列式约束：det ≈ 1.0（体积守恒）\n"
	code += "(assert (< (abs (- (* %s_%s %s_%s %s_%s %s_%s) 1.0)) 0.3))\n" % [
		rows[0], rows[0], rows[1], rows[1], rows[2], rows[2], rows[3], rows[3]]

	code += "\n(check-sat)\n"
	return code


func _run_z3(smt2_code: String) -> Variant:
	# 通过命令行调用Z3验证SMT2约束
	# 如果Z3不可用，直接返回null以触发回退
	if not _z3_available:
		return null

	var tmp_dir := "user://smt2_tmp/"
	if not DirAccess.dir_exists_absolute(tmp_dir):
		DirAccess.make_dir_recursive_absolute(tmp_dir)

	var tmp_filename := "verify_%d.smt2" % Time.get_ticks_msec()
	var tmp_path := tmp_dir + tmp_filename

	var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return null
	file.store_string(smt2_code)
	file.close()

	await get_tree().process_frame

	var output: Array[String] = []
	var exit_code: int = OS.execute("z3", ["-smt2", tmp_path], output, true)

	# 清理临时文件
	if FileAccess.file_exists(tmp_path):
		DirAccess.remove_absolute(tmp_path)

	if exit_code == -1:
		return null  # Z3执行失败

	var combined: String = "".join(output).strip_edges()

	if combined == "unsat":
		# 约束不可满足 = 守恒律被违反
		return {"success": false, "confidence": 0.95, "reason": "z3_unsat_conservation_violated"}

	if combined == "sat":
		# 约束可满足 = 守恒律成立
		return {"success": true, "confidence": 0.95, "reason": "z3_sat_conservation_verified"}

	if combined == "unknown":
		return {"success": false, "confidence": 0.3, "reason": "z3_unknown"}

	return {"success": false, "confidence": 0.1, "reason": "z3_unexpected_output", "output": combined}


func _verify_conservation_fallback(context: Dictionary) -> Dictionary:
	# 回退验证：使用守恒矩阵特征值检查
	# 与Z3形式化验证的数学内容等价，但用GDScript实现
	var matrix_data: Array = []
	if context.has("matrix"):
		matrix_data = context["matrix"]
	if matrix_data.size() != 16:
		return {"success": false, "confidence": 0.0, "reason": "no_matrix_data"}

	# 检查对角元素（自守恒量）
	var diag_indices: Array[int] = [0, 5, 10, 15]
	var labels: Array[String] = ["mass", "charge", "momentum", "energy"]
	var max_deviation: float = 0.0
	var worst_row: String = ""

	for i in range(4):
		var val: float = absf(float(matrix_data[diag_indices[i]]) - 1.0)
		if val > max_deviation:
			max_deviation = val
			worst_row = labels[i]

	# 使用ConservationEngine的特征值结果（如果可用）
	if is_instance_valid(ConservationEngine):
		var state: int = ConservationEngine.get_state()
		if state == 0:  # HEALTHY
			return {"success": true, "confidence": 0.9, "reason": "conservation_eigenvalue_verified"}
		elif state == 1:  # WARNING
			return {"success": false, "confidence": 0.4, "reason": "conservation_warning_%s" % worst_row}
		else:
			return {"success": false, "confidence": 0.1, "reason": "conservation_violation_%s" % worst_row}

	# 简单对角检查回退
	if max_deviation < 0.05:
		return {"success": true, "confidence": 0.85, "reason": "diagonal_conservation_verified"}
	return {"success": false, "confidence": 0.2, "reason": "diagonal_conservation_failed_%s" % worst_row}



func get_verification_log() -> Array[Dictionary]:
	return _verification_log


func clear_log() -> void:
	_verification_log.clear()
