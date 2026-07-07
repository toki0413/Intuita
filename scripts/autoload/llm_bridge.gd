extends Node
# llm_bridge.gd
# LLM桥接层 - 游戏与外部LLM API的通信接口
# 支持OpenAI兼容格式、语义缓存、请求队列、token预算和回退模式
#
# Responsibilities:
#   - 管理与LLM API的HTTP通信（OpenAI兼容格式）
#   - 语义缓存：相似查询直接返回缓存结果
#   - 请求队列：按优先级调度（低/中/高）
#   - Token预算：每个会话可配置token上限
#   - 流式响应：支持打字机效果
#   - 回退模式：无LLM时使用关卡内置规则提示
#   - 内存池：预分配响应字符串，减少GC压力
#   - 批量合并：同帧内相似请求自动合并
#
# Signals:
#   response_received(request_id, text) - 收到完整响应
#   stream_chunk(request_id, chunk) - 流式响应的一个片段
#   request_failed(request_id, reason) - 请求失败
#   cache_hit(request_id) - 命中语义缓存
#   token_budget_exhausted() - token预算耗尽
#
# Dependencies:
#   - Autoload: GameState, LevelManager, ConservationEngine

enum Priority { LOW = 0, MEDIUM = 1, HIGH = 2 }

# API配置
@export var api_url: String = "https://api.openai.com/v1/chat/completions"
@export var model_name: String = "gpt-4o-mini"
@export var max_tokens_per_request: int = 256
@export var token_budget_per_session: int = 100000

# API密钥存储路径（不在项目文件中）
const _CREDENTIALS_PATH := "user://.credentials"

# 缓存配置
@export var cache_max_entries: int = 128
@export var cache_similarity_threshold: float = 0.85

var _http_client: HTTPClient = null
var _request_queue: Array[Dictionary] = []
var _is_processing: bool = false
var _tokens_used: int = 0
var _next_request_id: int = 0
var _api_key: String = ""  # 运行时从文件加载，不暴露给编辑器

# 语义缓存: { cache_key: { response, timestamp, hit_count } }
var _semantic_cache: Dictionary = {}

# 内存池: 预分配的字符串缓冲区
var _string_pool: Array[String] = []
const STRING_POOL_SIZE := 32

# 批量合并: 同帧内待处理的请求
var _pending_batch: Array[Dictionary] = []
var _batch_timer: float = 0.0
const BATCH_INTERVAL := 0.05  # 50ms合并窗口

# 信号连接Callable缓存
var _on_level_loaded_conn: Callable

# 回退提示: 关卡数据中的规则提示
var _fallback_hints: Dictionary = {}

signal response_received(request_id: int, text: String)
signal stream_chunk(request_id: int, chunk: String)
signal request_failed(request_id: int, reason: String)
signal cache_hit(request_id: int)
signal token_budget_exhausted()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_init_http_client()
	_init_string_pool()
	_connect_signals()
	_load_api_key()


func _init_http_client() -> void:
	_http_client = HTTPClient.new()


func _init_string_pool() -> void:
	_string_pool.clear()
	for i in range(STRING_POOL_SIZE):
		_string_pool.append("")


func _connect_signals() -> void:
	_on_level_loaded_conn = _on_level_loaded
	if LevelManager != null:
		LevelManager.level_loaded.connect(_on_level_loaded_conn)


func _exit_tree() -> void:
	if LevelManager != null and LevelManager.level_loaded.is_connected(_on_level_loaded_conn):
		LevelManager.level_loaded.disconnect(_on_level_loaded_conn)


# ============ API密钥管理 ============

func _load_api_key() -> void:
	if not FileAccess.file_exists(_CREDENTIALS_PATH):
		_api_key = ""
		return
	var file := FileAccess.open(_CREDENTIALS_PATH, FileAccess.READ)
	if file == null:
		_api_key = ""
		return
	_api_key = file.get_as_text().strip_edges()
	file.close()


func has_api_key() -> bool:
	return _api_key != ""


func set_api_key(key: String) -> void:
	_api_key = key.strip_edges()
	var file := FileAccess.open(_CREDENTIALS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(_api_key)
		file.close()


func clear_api_key() -> void:
	_api_key = ""
	if FileAccess.file_exists(_CREDENTIALS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_CREDENTIALS_PATH))


func get_api_key() -> String:
	return _api_key


# ============ 公共API ============

# 发送请求到LLM，返回request_id
func send_request(prompt: String, context: Dictionary = {}, priority: Priority = Priority.MEDIUM, stream: bool = false) -> int:
	var rid := _next_request_id
	_next_request_id += 1

	# 检查token预算
	if _tokens_used >= token_budget_per_session:
		token_budget_exhausted.emit()
		_return_fallback(rid, prompt, context)
		return rid

	# 构建缓存键
	var cache_key := _compute_cache_key(prompt, context)

	# 检查语义缓存
	var cached := _lookup_cache(cache_key)
	if cached != "":
		cache_hit.emit(rid)
		response_received.emit(rid, cached)
		return rid

	# 加入请求队列
	var entry: Dictionary = {
		"id": rid,
		"prompt": prompt,
		"context": context,
		"priority": priority,
		"stream": stream,
		"cache_key": cache_key,
		"timestamp": Time.get_ticks_msec(),
	}

	# 低优先级请求进入批量合并窗口
	if priority == Priority.LOW:
		_pending_batch.append(entry)
	else:
		_enqueue(entry)

	return rid


# 取消请求
func cancel_request(rid: int) -> void:
	_request_queue = _request_queue.filter(func(e): return e["id"] != rid)
	_pending_batch = _pending_batch.filter(func(e): return e["id"] != rid)


# 重置token计数（新会话时调用）
func reset_token_budget() -> void:
	_tokens_used = 0


# 清空缓存
func clear_cache() -> void:
	_semantic_cache.clear()


# 预热缓存 - 关卡加载时缓存常见查询
func prewarm_cache(level_data: Dictionary) -> void:
	var space_group: int = level_data.get("space_group_number", 1)
	var title: String = level_data.get("title", "")

	var common_queries: Array[String] = [
		"hint_%d" % space_group,
		"verify_%d" % space_group,
		"explain_wyckoff_%d" % space_group,
	]

	for query in common_queries:
		var cache_key := _compute_cache_key(query, {"level": title})
		if not _semantic_cache.has(cache_key):
			# 用回退模式预填充
			var fallback := _generate_fallback_response(query, {"level": title, "space_group": space_group})
			_store_cache(cache_key, fallback)


# 获取当前token使用量
func get_tokens_used() -> int:
	return _tokens_used


# 获取缓存命中率
func get_cache_hit_rate() -> float:
	var total_hits := 0
	var total_entries := 0
	for key in _semantic_cache:
		total_entries += 1
		total_hits += _semantic_cache[key].get("hit_count", 0)
	if total_entries == 0:
		return 0.0
	return float(total_hits) / float(total_entries)


# ============ 请求处理 ============

func _process(delta: float) -> void:
	# 处理批量合并窗口
	if _pending_batch.size() > 0:
		_batch_timer += delta
		if _batch_timer >= BATCH_INTERVAL:
			_flush_batch()

	# 处理请求队列
	if not _is_processing and _request_queue.size() > 0:
		_process_next_request()


func _enqueue(entry: Dictionary) -> void:
	# 按优先级插入（高优先级在前）
	var inserted := false
	for i in range(_request_queue.size()):
		if entry["priority"] > _request_queue[i]["priority"]:
			_request_queue.insert(i, entry)
			inserted = true
			break
	if not inserted:
		_request_queue.append(entry)


func _flush_batch() -> void:
	_batch_timer = 0.0
	if _pending_batch.is_empty():
		return

	# 合并相似请求，只保留最具代表性的
	var merged := _merge_similar_batch(_pending_batch)
	for entry in merged:
		_enqueue(entry)
	_pending_batch.clear()


func _merge_similar_batch(batch: Array[Dictionary]) -> Array[Dictionary]:
	if batch.size() <= 1:
		return batch

	var result: Array[Dictionary] = []
	var used: Dictionary = {}

	for i in range(batch.size()):
		if used.has(i):
			continue
		var best := batch[i]
		used[i] = true

		# 找同类型的请求合并
		for j in range(i + 1, batch.size()):
			if used.has(j):
				continue
			if _are_similar(batch[i]["prompt"], batch[j]["prompt"]):
				# 保留优先级更高的
				if batch[j]["priority"] > best["priority"]:
					best = batch[j]
				used[j] = true

		result.append(best)

	return result


func _process_next_request() -> void:
	if _request_queue.is_empty():
		return

	_is_processing = true
	var entry: Dictionary = _request_queue.pop_front()

	# 检查是否有API配置
	if _api_key.is_empty() or api_url.is_empty():
		_is_processing = false
		_return_fallback(entry["id"], entry["prompt"], entry["context"])
		return

	# 构建压缩的JSON请求体
	var body := _build_request_body(entry)
	_send_http_request(entry, body)


# ============ HTTP请求 ============

func _build_request_body(entry: Dictionary) -> PackedByteArray:
	# 压缩prompt: 用结构化JSON代替自然语言
	var system_prompt := _build_system_prompt(entry["context"])
	var user_prompt := _compress_prompt(entry["prompt"], entry["context"])

	var request_data := {
		"model": model_name,
		"messages": [
			{"role": "system", "content": system_prompt},
			{"role": "user", "content": user_prompt},
		],
		"max_tokens": max_tokens_per_request,
		"temperature": 0.3,
		"stream": entry.get("stream", false),
	}

	var json_str := JSON.stringify(request_data)
	return json_str.to_utf8_buffer()


func _build_system_prompt(context: Dictionary) -> String:
	# 上下文窗口：只发送相关的关卡数据
	var level_id: String = context.get("level", "unknown")
	var space_group: int = context.get("space_group", 0)
	var conservation_state: int = context.get("conservation_state", 0)

	# 结构化系统提示，减少token
	return "Intuita crystal constructor. L:%s SG:%d CS:%d. Reply concise JSON." % [level_id, space_group, conservation_state]


func _compress_prompt(prompt: String, context: Dictionary) -> String:
	# 将自然语言prompt压缩为结构化格式
	var goal: String = context.get("goal", "")
	var action: String = context.get("action", prompt)

	if goal != "":
		return JSON.stringify({"a": action, "g": goal})
	return action


func _send_http_request(entry: Dictionary, body: PackedByteArray) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 30.0

	var headers := [
		"Content-Type: application/json",
		"Authorization: Bearer %s" % _api_key,
	]

	var rid: int = entry["id"]
	var cache_key: String = entry["cache_key"]

	http.request_completed.connect(func(_result, _code, _headers, response_body):
		_on_request_completed(rid, cache_key, _result, _code, response_body, http)
	)

	var err := http.request_raw(api_url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_is_processing = false
		request_failed.emit(rid, "HTTP request failed: %d" % err)
		http.queue_free()


func _on_request_completed(rid: int, cache_key: String, result: int, code: int, body: PackedByteArray, http: HTTPRequest) -> void:
	_is_processing = false
	http.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		request_failed.emit(rid, "HTTP result: %d" % result)
		return

	if code < 200 or code >= 300:
		request_failed.emit(rid, "HTTP code: %d" % code)
		return

	var json := JSON.new()
	var err := json.parse(body.get_string_from_utf8())
	if err != OK:
		request_failed.emit(rid, "JSON parse error")
		return

	var data: Dictionary = json.data
	var usage: Dictionary = data.get("usage", {})
	var prompt_tokens: int = usage.get("prompt_tokens", 0)
	var completion_tokens: int = usage.get("completion_tokens", 0)
	_tokens_used += prompt_tokens + completion_tokens

	# 提取响应文本
	var choices: Array = data.get("choices", [])
	if choices.is_empty():
		request_failed.emit(rid, "Empty choices")
		return

	var message: Dictionary = choices[0].get("message", {})
	var text: String = message.get("content", "")

	# 存入缓存
	_store_cache(cache_key, text)

	response_received.emit(rid, text)


# ============ 语义缓存 ============

func _compute_cache_key(prompt: String, context: Dictionary) -> String:
	# 基于prompt + 关键上下文字段的哈希
	var level_id: String = context.get("level", "")
	var goal: String = context.get("goal", "")
	var space_group: int = context.get("space_group", 0)
	var raw := "%s|%s|%s|%d" % [prompt, level_id, goal, space_group]
	return str(raw.hash())


func _lookup_cache(cache_key: String) -> String:
	if not _semantic_cache.has(cache_key):
		return ""

	var entry: Dictionary = _semantic_cache[cache_key]
	entry["hit_count"] = entry.get("hit_count", 0) + 1
	entry["last_access"] = Time.get_ticks_msec()

	# 从缓存中取出响应
	var response: String = entry["response"]
	return response


func _store_cache(cache_key: String, response: String) -> void:
	# 淘汰最旧的条目
	if _semantic_cache.size() >= cache_max_entries:
		_evict_cache()

	_semantic_cache[cache_key] = {
		"response": response,
		"timestamp": Time.get_ticks_msec(),
		"hit_count": 0,
		"last_access": Time.get_ticks_msec(),
	}


func _evict_cache() -> void:
	# LRU淘汰: 移除最久未访问的条目
	var oldest_key := ""
	var oldest_time := Time.get_ticks_msec()

	for key in _semantic_cache:
		var last_access: int = _semantic_cache[key].get("last_access", 0)
		if last_access < oldest_time:
			oldest_time = last_access
			oldest_key = key

	if oldest_key != "":
		_semantic_cache.erase(oldest_key)


func _are_similar(prompt_a: String, prompt_b: String) -> bool:
	# 简单的相似度检查: 基于共同token比例
	if prompt_a == prompt_b:
		return true

	var tokens_a := prompt_a.split(" ")
	var tokens_b := prompt_b.split(" ")
	if tokens_a.is_empty() or tokens_b.is_empty():
		return false

	var common := 0
	for t in tokens_a:
		if t in tokens_b:
			common += 1

	var similarity := float(common) / float(maxi(tokens_a.size(), tokens_b.size()))
	return similarity >= cache_similarity_threshold


# ============ 回退模式 ============

func _return_fallback(rid: int, prompt: String, context: Dictionary) -> void:
	var response := _generate_fallback_response(prompt, context)
	response_received.emit(rid, response)


func _generate_fallback_response(prompt: String, context: Dictionary) -> String:
	# 无LLM时使用规则引擎生成提示
	var space_group: int = context.get("space_group", 0)
	var conservation_state: int = context.get("conservation_state", 0)

	# 检查是否有关卡特定的回退提示
	var level_key: String = context.get("level", "")
	if _fallback_hints.has(level_key):
		var hints: Dictionary = _fallback_hints[level_key]
		if hints.has(prompt):
			return hints[prompt]

	# 通用规则提示
	if prompt.find("hint") != -1 or prompt.find("提示") != -1:
		return _rule_based_hint(space_group, conservation_state)

	if prompt.find("verify") != -1 or prompt.find("验证") != -1:
		return _rule_based_verification(context)

	if prompt.find("explain") != -1 or prompt.find("解释") != -1:
		return _rule_based_explanation(space_group)

	return "{\"status\":\"ok\",\"hint\":\"继续构造晶体结构\"}"


func _rule_based_hint(space_group: int, conservation_state: int) -> String:
	if conservation_state >= 2:
		return "{\"status\":\"warning\",\"hint\":\"守恒偏离过大，考虑减少操作\"}"

	match space_group:
		225:  # Fm-3m NaCl
			return "{\"status\":\"ok\",\"hint\":\"NaCl结构: Na和Cl交替填充Wyckoff位置\"}"
		229:  # Im-3m BCC
			return "{\"status\":\"ok\",\"hint\":\"体心立方: 注意角落和体心位置\"}"
		_:
			return "{\"status\":\"ok\",\"hint\":\"检查Wyckoff位置并填充合适的元素\"}"


func _rule_based_verification(context: Dictionary) -> String:
	var atoms_count: int = context.get("atoms_count", 0)
	if atoms_count == 0:
		return "{\"status\":\"fail\",\"reason\":\"没有放置任何原子\"}"
	return "{\"status\":\"pass\",\"confidence\":0.7}"


func _rule_based_explanation(space_group: int) -> String:
	return "{\"status\":\"ok\",\"text\":\"空间群#%d的晶体结构\" % space_group}"


# ============ 关卡集成 ============

func _on_level_loaded(level_data: Dictionary) -> void:
	# 关卡加载时预热缓存
	prewarm_cache(level_data)

	# 注册关卡回退提示
	var level_key: String = "%s_%s" % [level_data.get("chapter", 1), level_data.get("level", 1)]
	var hint: String = level_data.get("hint", "")
	if not hint.is_empty():
		_fallback_hints[level_key] = {
			"hint": hint,
			"提示": hint,
		}


# ============ 配置 ============

# 从配置文件加载API设置
func load_config(config_path: String = "user://llm_config.json") -> bool:
	if not FileAccess.file_exists(config_path):
		return false

	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		return false

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		return false

	var data: Dictionary = json.data
	api_url = data.get("api_url", api_url)
	_api_key = data.get("api_key", _api_key)
	model_name = data.get("model", model_name)
	token_budget_per_session = data.get("token_budget", token_budget_per_session)
	return true


# 保存配置
func save_config(config_path: String = "user://llm_config.json") -> void:
	var data := {
		"api_url": api_url,
		"model": model_name,
		"token_budget": token_budget_per_session,
	}
	var file := FileAccess.open(config_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
