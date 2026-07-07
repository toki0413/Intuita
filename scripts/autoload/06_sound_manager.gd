# sound_manager.gd
# 音效管理器 - 程序化生成所有游戏音效
# 不依赖外部音频文件，使用AudioStreamWAV实时合成
# 所有音效通过数学公式生成，确保可听
#
# Responsibilities:
#   - 程序化生成各类音效（咔哒/警告/崩解/证明完成等）
#   - 音频播放器池管理
#   - 正弦波/白噪音/和弦/扫频音合成
#   - 维护 SFX/Music 音频总线并响应设置变化
#
# Signals:
#   无
#
# Dependencies:
#   - Autoload: SettingsManager, LevelManager

extends Node

enum SoundType {
	CLICK_LOCK,        # 咔哒锁定 - 合法连接，高频短促
	SOFT_MODE_LOCK,    # 软模锁定 - 低沉咚声
	FOG_ENTER,         # 进入迷雾 - 静电白噪音
	CONSERVATION_WARN, # 守恒警告 - 高频警报
	DISINTEGRATE_START,# 崩解开始 - 玻璃碎裂感
	DISINTEGRATE_FULL, # 完全崩解 - 爆炸+低频
	PROOF_COMPLETE,    # 证明完成 - 交响乐和弦
	VERIFICATION_PASS, # 验证通过 - 清脆叮
	VERIFICATION_FAIL, # 验证失败 - 低沉嗡
	CORE_SPEND,        # 消耗核心 - 硬币声
	FOG_RESOLVE,       # 迷雾消除 - 风声消散
	ATOM_PLACE,        # 原子放置 - 短促咔，音高随放置数递增
	WYCKOFF_LOCK,      # Wyckoff锁定 - 满足感咔嗒
	ATOM_REMOVE,       # 原子移除 - 柔和反向咔
	CORE_EARNED,       # 获得核心 - 硬币叮
	EVOLVE_POINT_EARNED, # 进化点获得 - 轻柔铃声
	# G6: 迷雾3D视觉差异化新增音效
	FOG_RESOLVE_SUCCESS, # 迷雾驱散成功 - 上升和弦
	FOG_RESOLVE_FAIL,    # 迷雾驱散失败 - 低沉轰鸣
	FOG_PEEK,            # 迷雾窥视 - 柔和风声
	FOG_WHOOSH,          # 迷雾消散呼啸 - 柔和whoosh
	FOG_LIGHTNING,       # 迷雾闪电 - 电弧噼啪
	FOG_THUNDER,         # 迷雾雷声 - 低沉雷鸣
	FOG_VOID_HUM,        # 虚空低鸣 - 次低频嗡鸣
	FOG_INDEPENDENT_TOUCH, # 独立雾触碰 - 沉闷敲击
	# G8: 章节过渡
	CHAPTER_TRANSITION,  # 章节过渡 - 钢琴渐入
	JOURNAL_ENTRY,       # 手记条目 - 纸张翻动
	# Breach警示音分层递进
	BREACH_WARNING_LAYER_1, # 轻微偏离 - 单次短促高频音
	BREACH_WARNING_LAYER_2, # 中等偏离 - 快速双音重复
	BREACH_WARNING_LAYER_3, # 严重偏离 - 连续急促三音
}

enum MusicStyle {
	CRYSTAL, # 晶体域 = 纯净正弦 + 轻微和声，低频缓慢变化
	FLUID,   # 流体域 = 低频嗡鸣 + 白噪音扫频
	FOG,     # 迷雾域 = 次低频 + 随机琶音
	MENU,    # 主菜单 = 温暖和弦循环
}

var _players: Array[AudioStreamPlayer] = []
const SAMPLE_RATE := 44100.0
const MAX_PLAYERS := 8
const EXTERNAL_SOUND_DIR := "res://assets/third_party/sonniss/"

# 音乐播放器（独立，非池化，专门用于音乐）
var _music_player: AudioStreamPlayer = null
var _music_tween: Tween = null

# 环境氛围音播放器（独立，不占用池化播放器）
var _ambience_player: AudioStreamPlayer = null
var _ambience_tween: Tween = null

# 外部音效缓存: SoundType -> AudioStream
var _external_sounds: Dictionary = {}
# 是否已扫描外部目录
var _external_scanned: bool = false
# 关键词映射: SoundType -> [搜索关键词, ...]
var _sound_keywords: Dictionary = {
	SoundType.CLICK_LOCK: ["click", "tap", "button", "ui"],
	SoundType.SOFT_MODE_LOCK: ["soft", "gentle", "light", "plop"],
	SoundType.FOG_ENTER: ["fog", "mist", "ambient", "wind"],
	SoundType.CONSERVATION_WARN: ["warning", "alert", "buzz", "alarm"],
	SoundType.DISINTEGRATE_START: ["break", "shatter", "crack", "glass"],
	SoundType.DISINTEGRATE_FULL: ["explosion", "boom", "destroy", "blast"],
	SoundType.PROOF_COMPLETE: ["success", "chime", "positive", "win"],
	SoundType.VERIFICATION_PASS: ["ding", "bell", "correct", "pass"],
	SoundType.VERIFICATION_FAIL: ["error", "fail", "wrong", "buzz"],
	SoundType.CORE_SPEND: ["coin", "spend", "purchase", "money"],
	SoundType.FOG_RESOLVE: ["resolve", "clear", "whoosh", "swish"],
	SoundType.ATOM_PLACE: ["place", "drop", "snap", "tick"],
	SoundType.WYCKOFF_LOCK: ["lock", "click", "satisfy", "snap"],
	SoundType.ATOM_REMOVE: ["remove", "undo", "reverse", "suck"],
	SoundType.CORE_EARNED: ["earn", "collect", "coin", "treasure"],
	SoundType.EVOLVE_POINT_EARNED: ["evolve", "levelup", "ring", "chime"],
	SoundType.FOG_RESOLVE_SUCCESS: ["success", "ascend", "rise", "bright"],
	SoundType.FOG_RESOLVE_FAIL: ["fail", "rumble", "dark", "heavy"],
	SoundType.FOG_PEEK: ["peek", "whisper", "soft", "wind"],
	SoundType.FOG_WHOOSH: ["whoosh", "swish", "swoosh", "wind"],
	SoundType.FOG_LIGHTNING: ["lightning", "spark", "electric", "zap"],
	SoundType.FOG_THUNDER: ["thunder", "rumble", "storm", "heavy"],
	SoundType.FOG_VOID_HUM: ["void", "hum", "drone", "low"],
	SoundType.FOG_INDEPENDENT_TOUCH: ["touch", "knock", "thud", "dull"],
	SoundType.CHAPTER_TRANSITION: ["transition", "piano", "music", "theme"],
	SoundType.JOURNAL_ENTRY: ["paper", "page", "book", "scroll"],
}

# 原子放置计数器 - 用于音高递增
var _atom_place_count: int = 0

# 缓存设置变更回调，方便断开
var _on_setting_changed_conn: Callable
var _on_level_loaded_conn: Callable


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 创建 SFX / Music 总线（项目默认只有 Master）
	_ensure_audio_buses()

	# 预创建播放器池，全部挂到 SFX 总线
	for i in range(MAX_PLAYERS):
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_players.append(player)

	# 创建独立音乐播放器，挂载到 Music 总线
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = "Music"
	add_child(_music_player)

	# 创建独立环境氛围音播放器，挂载到 SFX 总线（不占用池化播放器）
	_ambience_player = AudioStreamPlayer.new()
	_ambience_player.name = "AmbiencePlayer"
	_ambience_player.bus = "SFX"
	add_child(_ambience_player)

	# 应用一次当前音量设置，避免启动后滑条失同步
	_apply_volumes_from_settings()

	# 监听设置变化，实时更新 SFX / Music 总线音量
	_on_setting_changed_conn = _on_setting_changed
	SettingsManager.setting_changed.connect(_on_setting_changed_conn)

	# 新关卡加载时重置原子放置计数，避免跨关卡音高无限递增
	_on_level_loaded_conn = _on_level_loaded
	if LevelManager != null:
		LevelManager.level_loaded.connect(_on_level_loaded_conn)

	# 异步扫描外部音效（不阻塞启动）
	call_deferred("_scan_external_sounds")


func _exit_tree() -> void:
	if SettingsManager != null and _on_setting_changed_conn.is_valid() \
			and SettingsManager.setting_changed.is_connected(_on_setting_changed_conn):
		SettingsManager.setting_changed.disconnect(_on_setting_changed_conn)
	if LevelManager != null and _on_level_loaded_conn.is_valid() \
			and LevelManager.level_loaded.is_connected(_on_level_loaded_conn):
		LevelManager.level_loaded.disconnect(_on_level_loaded_conn)


# 确保 SFX / Music 总线存在，挂到 Master 下
func _ensure_audio_buses() -> void:
	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "SFX")
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Music")
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")


# 从 SettingsManager 读取音量并应用到总线
func _apply_volumes_from_settings() -> void:
	var sfx_idx := AudioServer.get_bus_index("SFX")
	var music_idx := AudioServer.get_bus_index("Music")
	var master_idx := AudioServer.get_bus_index("Master")

	var master: float = float(SettingsManager.get_setting("master_volume", 0.8))
	var sfx: float = float(SettingsManager.get_setting("sfx_volume", 1.0))
	var music: float = float(SettingsManager.get_setting("music_volume", 0.5))

	if master_idx != -1:
		AudioServer.set_bus_volume_db(master_idx, linear_to_db(master))
	if sfx_idx != -1:
		AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(sfx))
	if music_idx != -1:
		AudioServer.set_bus_volume_db(music_idx, linear_to_db(music))


func _on_setting_changed(key: String, _value: Variant) -> void:
	# 只处理音量相关键，其他设置不影响音频总线
	match key:
		"master_volume", "sfx_volume", "music_volume":
			_apply_volumes_from_settings()


func _on_level_loaded(_level_data: Dictionary) -> void:
	# 切关时把原子放置计数清零，避免音高无限累积
	reset_atom_place_count()


func _scan_external_sounds() -> void:
	if _external_scanned:
		return
	_external_scanned = true

	var dir := DirAccess.open(EXTERNAL_SOUND_DIR)
	if dir == null:
		# 外部音效目录不存在时回退到程序化生成，无需 warning
		return

	# 递归收集所有 .wav 文件
	var all_wavs: Array[String] = []
	_collect_wav_files(dir, EXTERNAL_SOUND_DIR, all_wavs)

	if all_wavs.is_empty():
		# 无外部文件时完全使用程序化音效，属于正常配置
		return

	GameLogger.info("SoundManager", "SoundManager: 发现 %d 个外部 WAV 文件" % all_wavs.size())

	# 为每个 SoundType 尝试匹配最佳 WAV
	for sound_type in _sound_keywords.keys():
		var keywords: Array = _sound_keywords[sound_type]
		var best_match := _find_best_match(keywords, all_wavs)
		if best_match != "":
			var stream := _load_wav_file(best_match)
			if stream != null:
				_external_sounds[sound_type] = stream
				GameLogger.info("SoundManager", "SoundManager: 已注册外部音效 [%s] -> %s" % [SoundType.keys()[sound_type], best_match])


func _collect_wav_files(dir: DirAccess, base_path: String, out_files: Array[String]) -> void:
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		var full_path := base_path + file_name
		if dir.current_is_dir():
			var sub_dir := DirAccess.open(full_path)
			if sub_dir != null:
				_collect_wav_files(sub_dir, full_path + "/", out_files)
		elif file_name.to_lower().ends_with(".wav"):
			out_files.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()


func _find_best_match(keywords: Array, files: Array[String]) -> String:
	var best_file := ""
	var best_score := 0

	for file_path in files:
		var file_lower := file_path.to_lower()
		var score := 0
		for kw in keywords:
			var kw_lower := str(kw).to_lower()
			# 文件名匹配权重更高
			if kw_lower in file_lower.get_file():
				score += 10
			# 目录名匹配
			elif kw_lower in file_lower:
				score += 3
		if score > best_score:
			best_score = score
			best_file = file_path

	return best_file if best_score >= 10 else ""


func _load_wav_file(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var res := load(path)
	if res is AudioStream:
		return res as AudioStream
	return null


func play(sound_type: SoundType, pitch: float = 1.0) -> void:
	var player := _get_idle_player()
	if player == null:
		return  # 没有空闲播放器就跳过

	# 优先使用外部音效（如果可用且未加载失败）
	if _external_sounds.has(sound_type):
		var ext_stream: AudioStream = _external_sounds[sound_type]
		player.stream = ext_stream
		player.pitch_scale = pitch
		player.volume_db = 0.0
		player.play()
		return

	# 回退到程序化生成
	match sound_type:
		SoundType.CLICK_LOCK:
			_play_tone(player, 1200.0 * pitch, 0.06, -8.0)  # 高频短促咔哒
		SoundType.SOFT_MODE_LOCK:
			_play_tone(player, 150.0 * pitch, 0.25, -6.0)   # 低沉咚声
		SoundType.FOG_ENTER:
			_play_noise(player, 0.4, -12.0)          # 白噪音
		SoundType.CONSERVATION_WARN:
			_play_tone(player, 1800.0 * pitch, 0.12, -5.0)  # 高频警报
		SoundType.DISINTEGRATE_START:
			_play_noise(player, 0.25, -4.0)          # 碎裂感
		SoundType.DISINTEGRATE_FULL:
			_play_noise(player, 0.8, -2.0)           # 爆炸
		SoundType.PROOF_COMPLETE:
			_play_chord(player, [523.25 * pitch, 659.25 * pitch, 783.99 * pitch, 1046.5 * pitch], 1.2, -6.0)  # C大七和弦
		SoundType.VERIFICATION_PASS:
			_play_tone(player, 1500.0 * pitch, 0.08, -8.0)  # 清脆叮
		SoundType.VERIFICATION_FAIL:
			_play_tone(player, 200.0 * pitch, 0.35, -6.0)   # 低沉嗡
		SoundType.CORE_SPEND:
			_play_tone(player, 800.0 * pitch, 0.07, -7.0)   # 硬币声
		SoundType.FOG_RESOLVE:
			_play_sweep(player, 1000.0 * pitch, 200.0 * pitch, 0.45, -10.0)  # 下降风声
		SoundType.ATOM_PLACE:
			_atom_place_count += 1
			var pitch_mult := 1.0 + (_atom_place_count - 1) * 0.08  # 每次放置音高递增
			_play_tone(player, 900.0 * pitch * pitch_mult, 0.05, -7.0)
		SoundType.WYCKOFF_LOCK:
			_play_chord(player, [440.0 * pitch, 554.37 * pitch, 659.25 * pitch], 0.2, -6.0)  # A小三和弦短促
		SoundType.ATOM_REMOVE:
			_play_sweep(player, 900.0 * pitch, 400.0 * pitch, 0.08, -9.0)  # 柔和下降
		SoundType.CORE_EARNED:
			_play_chord(player, [1046.5 * pitch, 1318.5 * pitch], 0.15, -5.0)  # 高八度双音叮
		SoundType.EVOLVE_POINT_EARNED:
			_play_chord(player, [783.99 * pitch, 987.77 * pitch, 1174.66 * pitch], 0.3, -8.0)  # 轻柔三音铃声
		# G6: 迷雾3D视觉差异化音效
		SoundType.FOG_RESOLVE_SUCCESS:
			_play_chord(player, [523.25, 659.25, 783.99], 0.6, -6.0)  # 上升三和弦
		SoundType.FOG_RESOLVE_FAIL:
			_play_tone(player, 80.0, 0.5, -4.0)  # 低沉轰鸣
		SoundType.FOG_PEEK:
			_play_sweep(player, 600.0, 400.0, 0.3, -10.0)  # 柔和风声
		SoundType.FOG_WHOOSH:
			_play_sweep(player, 800.0, 200.0, 0.5, -8.0)  # 呼啸下降
		SoundType.FOG_LIGHTNING:
			_play_noise(player, 0.15, -3.0)  # 短促电弧
		SoundType.FOG_THUNDER:
			_play_tone(player, 50.0, 0.8, -4.0)  # 低沉雷鸣
		SoundType.FOG_VOID_HUM:
			_play_tone(player, 35.0, 1.5, -6.0)  # 次低频嗡鸣
		SoundType.FOG_INDEPENDENT_TOUCH:
			_play_tone(player, 100.0, 0.2, -5.0)  # 沉闷敲击
		# G8: 章节过渡音效
		SoundType.CHAPTER_TRANSITION:
			_play_chord(player, [261.63, 329.63, 392.0, 523.25], 2.0, -5.0)  # C大调渐入
		SoundType.JOURNAL_ENTRY:
			_play_noise(player, 0.08, -12.0)  # 纸张翻动
		# Breach警示音分层递进
		SoundType.BREACH_WARNING_LAYER_1:
			_play_tone(player, 2000.0 * pitch, 0.08, -10.0)  # 单次短促高频音
		SoundType.BREACH_WARNING_LAYER_2:
			_play_chord(player, [1000.0 * pitch, 1500.0 * pitch], 0.1, -8.0)  # 快速双音重复
		SoundType.BREACH_WARNING_LAYER_3:
			_play_chord(player, [800.0 * pitch, 1200.0 * pitch, 1600.0 * pitch], 0.08, -6.0)  # 连续急促三音


func _get_idle_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	return null


# 生成单音 - 正弦波 + ADSR包络
func _play_tone(player: AudioStreamPlayer, freq: float, duration: float, volume_db: float) -> void:
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)  # 16位单声道

	var attack_time := 0.005  # 5ms起音
	var decay_time := duration * 0.3

	for i in range(samples):
		var t := float(i) / SAMPLE_RATE
		var envelope := 1.0

		# ADSR包络
		if t < attack_time:
			envelope = t / attack_time
		elif t < attack_time + decay_time:
			envelope = 1.0 - (t - attack_time) / decay_time * 0.3
		else:
			envelope = 0.7 * exp(-4.0 * (t - attack_time - decay_time) / (duration - attack_time - decay_time))

		# 正弦波
		var sample := envelope * sin(2.0 * PI * freq * t)
		var int_sample := int(sample * 32767.0)
		int_sample = clampi(int_sample, -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = int(SAMPLE_RATE)
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED

	player.stream = stream
	player.volume_db = volume_db
	player.play()


# 生成白噪音 - 随机波形 + 快速衰减
func _play_noise(player: AudioStreamPlayer, duration: float, volume_db: float) -> void:
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)

	for i in range(samples):
		var t := float(i) / SAMPLE_RATE
		# 快速衰减包络
		var envelope := exp(-3.5 * t / duration)

		# 白噪音 = 随机值
		var sample := envelope * (randf() * 2.0 - 1.0) * 0.6
		var int_sample := int(sample * 32767.0)
		int_sample = clampi(int_sample, -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = int(SAMPLE_RATE)
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED

	player.stream = stream
	player.volume_db = volume_db
	player.play()


# 生成和弦 - 多个频率叠加
func _play_chord(player: AudioStreamPlayer, freqs: Array, duration: float, volume_db: float) -> void:
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)

	var attack := 0.08
	var release_start := duration - 0.4

	for i in range(samples):
		var t := float(i) / SAMPLE_RATE
		var envelope := 1.0

		# 起音 + 释放
		if t < attack:
			envelope = t / attack
		elif t > release_start:
			envelope = (duration - t) / 0.4
		else:
			envelope = 1.0

		# 多个正弦波叠加
		var sample := 0.0
		for freq in freqs:
			sample += sin(2.0 * PI * freq * t)
		sample = sample / freqs.size() * envelope * 0.5

		var int_sample := int(sample * 32767.0)
		int_sample = clampi(int_sample, -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = int(SAMPLE_RATE)
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED

	player.stream = stream
	player.volume_db = volume_db
	player.play()


# 生成扫频音 - 频率从高到低变化
func _play_sweep(player: AudioStreamPlayer, freq_start: float, freq_end: float, duration: float, volume_db: float) -> void:
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)

	var phase := 0.0
	for i in range(samples):
		var t := float(i) / SAMPLE_RATE
		# 线性衰减包络
		var envelope := 1.0 - t / duration

		# 频率线性下降
		var freq := freq_start + (freq_end - freq_start) * t / duration
		phase += 2.0 * PI * freq / SAMPLE_RATE

		var sample := envelope * sin(phase) * 0.4
		var int_sample := int(sample * 32767.0)
		int_sample = clampi(int_sample, -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = int(SAMPLE_RATE)
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED

	player.stream = stream
	player.volume_db = volume_db
	player.play()


# 停止所有正在播放的音效
func stop_all() -> void:
	for p in _players:
		if p.playing:
			p.stop()


# 重置原子放置计数器（新关卡时调用）
func reset_atom_place_count() -> void:
	_atom_place_count = 0


# 通过名称播放音效，方便脚本中字符串调用
func play_sfx(sound_name: String, pitch: float = 1.0) -> void:
	match sound_name:
		"atom_place":
			play(SoundType.ATOM_PLACE, pitch)
		"atom_remove":
			play(SoundType.ATOM_REMOVE, pitch)
		"click", "click_lock":
			play(SoundType.CLICK_LOCK, pitch)
		"soft_mode_lock":
			play(SoundType.SOFT_MODE_LOCK, pitch)
		"verify_pass":
			play(SoundType.VERIFICATION_PASS, pitch)
		"verify_fail":
			play(SoundType.VERIFICATION_FAIL, pitch)
		"proof_complete":
			play(SoundType.PROOF_COMPLETE, pitch)
		"core_spend":
			play(SoundType.CORE_SPEND, pitch)
		"core_earned":
			play(SoundType.CORE_EARNED, pitch)
		"wyckoff_lock":
			play(SoundType.WYCKOFF_LOCK, pitch)
		"disintegrate", "disintegrate_full":
			play(SoundType.DISINTEGRATE_FULL, pitch)
		"disintegrate_start":
			play(SoundType.DISINTEGRATE_START, pitch)
		"conservation_warn":
			play(SoundType.CONSERVATION_WARN, pitch)
		"fog_enter":
			play(SoundType.FOG_ENTER, pitch)
		_:
			push_warning("SoundManager: 未知音效名称: %s" % sound_name)


# ========== 背景音乐系统 ==========

func play_music(style: MusicStyle, fade_in: float = 2.0) -> void:
	if _music_player == null:
		return

	var stream := _generate_music_stream(style)
	if stream == null:
		return

	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_music_player.stream = stream
	_music_player.volume_db = -80.0
	_music_player.play()

	var target_db := linear_to_db(SettingsManager.get_setting("music_volume", 0.5))
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", target_db, fade_in)


func stop_music(fade_out: float = 1.0) -> void:
	if _music_player == null or not _music_player.playing:
		return

	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", -80.0, fade_out)
	_music_tween.finished.connect(_music_player.stop)


func crossfade_music(style: MusicStyle, duration: float = 2.0) -> void:
	if _music_player == null:
		return

	var new_player := AudioStreamPlayer.new()
	new_player.name = "MusicPlayerCrossfade_%d" % Time.get_ticks_msec()
	new_player.bus = "Music"
	add_child(new_player)

	var stream := _generate_music_stream(style)
	if stream == null:
		new_player.queue_free()
		return

	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	new_player.stream = stream
	new_player.volume_db = -80.0
	new_player.play()

	var target_db := linear_to_db(SettingsManager.get_setting("music_volume", 0.5))
	var fade_tween := create_tween()
	fade_tween.set_parallel(true)
	# 新播放器淡入
	fade_tween.tween_property(new_player, "volume_db", target_db, duration)
	# 旧播放器淡出
	var old_player := _music_player
	if old_player.playing:
		fade_tween.tween_property(old_player, "volume_db", -80.0, duration)
	fade_tween.finished.connect(func() -> void:
		if old_player != null and old_player.playing:
			old_player.stop()
		# 将主引用切换为新播放器
		_music_player = new_player
		# 停止所有旧的音乐节点（包括 crossfade 和旧主播放器），并清理已停止的 crossfade 节点
		for child in get_children():
			if child is AudioStreamPlayer and child != new_player and child != _ambience_player:
				if child.playing:
					child.stop()
				# 清理 crossfade 临时节点；保留主播放器节点 "MusicPlayer"
				if child.name.begins_with("MusicPlayerCrossfade_"):
					child.queue_free()
	)


func _generate_music_stream(style: MusicStyle) -> AudioStreamWAV:
	match style:
		MusicStyle.CRYSTAL:
			return _generate_crystal_music()
		MusicStyle.FLUID:
			return _generate_fluid_music()
		MusicStyle.FOG:
			return _generate_fog_music()
		MusicStyle.MENU:
			return _generate_menu_music()
	return null


func _generate_crystal_music() -> AudioStreamWAV:
	var duration := 12.0
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)

	var base_freq := 110.0
	var lfo_rate := 0.15  # LFO 频率 Hz

	for i in range(samples):
		var t := float(i) / SAMPLE_RATE
		var lfo := sin(2.0 * PI * lfo_rate * t) * 2.0  # ±2Hz 调制
		var f1 := base_freq + lfo
		var f2 := 220.0 + lfo * 0.5  # 纯五度
		var f3 := 330.0 + lfo * 0.3  # 大三度

		var sample := 0.0
		sample += sin(2.0 * PI * f1 * t) * 0.5
		sample += sin(2.0 * PI * f2 * t) * 0.3
		sample += sin(2.0 * PI * f3 * t) * 0.2

		# 极轻微包络变化（缓慢起伏）
		var envelope := 1.0 + 0.05 * sin(2.0 * PI * 0.05 * t)
		sample *= envelope

		# 总音量 -15dB ≈ 0.178 线性
		sample *= 0.178

		var int_sample := int(sample * 32767.0)
		int_sample = clampi(int_sample, -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = int(SAMPLE_RATE)
	stream.data = data
	return stream


func _generate_fluid_music() -> AudioStreamWAV:
	var duration := 10.0
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)

	var base_freq := 60.0
	var sub_freq := 120.0

	for i in range(samples):
		var t := float(i) / SAMPLE_RATE
		var sample := 0.0

		# 基础低频嗡鸣
		sample += sin(2.0 * PI * base_freq * t) * 0.5
		# 次谐波
		sample += sin(2.0 * PI * sub_freq * t) * 0.3

		# 白噪音通过低通滤波模拟（用积分累加实现一阶低通）
		var noise := (randf() * 2.0 - 1.0) * 0.15
		# 使用扫频模拟低通效果：高频随时间衰减
		var noise_env := exp(-2.0 * t / duration)
		sample += noise * noise_env

		# 总音量 -18dB ≈ 0.126 线性
		sample *= 0.126

		var int_sample := int(sample * 32767.0)
		int_sample = clampi(int_sample, -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = int(SAMPLE_RATE)
	stream.data = data
	return stream


func _generate_fog_music() -> AudioStreamWAV:
	var duration := 16.0
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)

	var base_freq := 40.0
	var next_arpeg_time := 0.0
	var arpeg_freq := 200.0 + randf() * 400.0  # 200-600Hz 随机
	var arpeg_duration := 0.3
	var arpeg_amp := 0.0

	for i in range(samples):
		var t := float(i) / SAMPLE_RATE
		var sample := 0.0

		# 基础次低频嗡鸣
		sample += sin(2.0 * PI * base_freq * t) * 0.6

		# 随机琶音触发
		if t >= next_arpeg_time:
			arpeg_freq = 200.0 + randf() * 400.0
			arpeg_amp = 1.0
			next_arpeg_time = t + 2.0 + randf() * 2.0  # 每 2-4 秒

		# 琶音衰减
		if arpeg_amp > 0.0:
			arpeg_amp -= 1.0 / (SAMPLE_RATE * arpeg_duration)
			if arpeg_amp < 0.0:
				arpeg_amp = 0.0

		var arpeg_env := maxf(0.0, arpeg_amp)
		sample += sin(2.0 * PI * arpeg_freq * t) * arpeg_env * 0.3

		# 总音量 -20dB ≈ 0.1 线性
		sample *= 0.1

		var int_sample := int(sample * 32767.0)
		int_sample = clampi(int_sample, -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = int(SAMPLE_RATE)
	stream.data = data
	return stream


func _generate_menu_music() -> AudioStreamWAV:
	var duration := 8.0
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)

	# C 大调琶音: C4=261.63, E4=329.63, G4=392.0, C5=523.25
	var freqs := [261.63, 329.63, 392.0, 523.25]
	var note_duration := 2.0  # 每个音符 2 秒

	for i in range(samples):
		var t := float(i) / SAMPLE_RATE
		var sample := 0.0

		var note_index := int(t / note_duration) % 4
		var local_t := fmod(t, note_duration)
		var freq: float = freqs[note_index]

		# 柔和起音 ADSR
		var envelope := 1.0
		var attack := 0.3
		var release := 0.5
		if local_t < attack:
			envelope = local_t / attack
		elif local_t > note_duration - release:
			envelope = (note_duration - local_t) / release

		sample += sin(2.0 * PI * freq * t) * envelope * 0.4
		# 添加轻微和声
		sample += sin(2.0 * PI * freq * 2.0 * t) * envelope * 0.1

		# 总音量 -12dB ≈ 0.251 线性
		sample *= 0.251

		var int_sample := int(sample * 32767.0)
		int_sample = clampi(int_sample, -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = int(SAMPLE_RATE)
	stream.data = data
	return stream


# 降低当前音乐音量（用于胜利余韵等场景）
func lower_music_volume(offset_db: float = -20.0, duration: float = 2.0) -> void:
	if _music_player == null or not _music_player.playing:
		return
	var current_db := _music_player.volume_db
	var target_db := maxf(current_db + offset_db, -80.0)
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", target_db, duration)


# 恢复音乐音量到正常设置值
func restore_music_volume(duration: float = 1.0) -> void:
	if _music_player == null:
		return
	var music_vol: float = float(SettingsManager.get_setting("music_volume", 0.5))
	var target_db := linear_to_db(music_vol)
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", target_db, duration)


# ========== 环境氛围音系统 ==========

func play_ambience(domain: String) -> void:
	if _ambience_player == null:
		return

	var stream := _generate_ambience_stream(domain)
	if stream == null:
		return

	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_ambience_player.stream = stream
	_ambience_player.volume_db = -80.0
	_ambience_player.play()

	var target_db := _get_ambience_target_db(domain)
	if _ambience_tween != null and _ambience_tween.is_valid():
		_ambience_tween.kill()
	_ambience_tween = create_tween()
	_ambience_tween.tween_property(_ambience_player, "volume_db", target_db, 1.5)


func stop_ambience() -> void:
	if _ambience_player == null or not _ambience_player.playing:
		return

	if _ambience_tween != null and _ambience_tween.is_valid():
		_ambience_tween.kill()
	_ambience_tween = create_tween()
	_ambience_tween.tween_property(_ambience_player, "volume_db", -80.0, 1.0)
	_ambience_tween.finished.connect(_ambience_player.stop)


func _get_ambience_target_db(domain: String) -> float:
	match domain:
		"crystal":
			return -25.0
		"fluid":
			return -22.0
		"fog":
			return -28.0
	return -30.0


func _generate_ambience_stream(domain: String) -> AudioStreamWAV:
	match domain:
		"crystal":
			var stream := _generate_crystal_ambience()
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			return stream
		"fluid":
			var stream := _generate_fluid_ambience()
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			return stream
		"fog":
			var stream := _generate_fog_ambience()
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			return stream
	return null


func _generate_crystal_ambience() -> AudioStreamWAV:
	var duration := 4.0
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)

	for i in range(samples):
		var t := float(i) / SAMPLE_RATE
		# 极轻微白噪音
		var sample := (randf() * 2.0 - 1.0) * 0.056  # -25dB
		var int_sample := int(sample * 32767.0)
		int_sample = clampi(int_sample, -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = int(SAMPLE_RATE)
	stream.data = data
	return stream


func _generate_fluid_ambience() -> AudioStreamWAV:
	var duration := 4.0
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)

	var phase := 0.0
	for i in range(samples):
		var t := float(i) / SAMPLE_RATE
		# 低频扫频循环（50-100Hz）
		var freq := 50.0 + 50.0 * sin(2.0 * PI * 0.25 * t)  # 0.25Hz 周期 = 4秒
		phase += 2.0 * PI * freq / SAMPLE_RATE
		var sample := sin(phase) * 0.079  # -22dB
		var int_sample := int(sample * 32767.0)
		int_sample = clampi(int_sample, -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = int(SAMPLE_RATE)
	stream.data = data
	return stream


func _generate_fog_ambience() -> AudioStreamWAV:
	var duration := 4.0
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)

	for i in range(samples):
		var t := float(i) / SAMPLE_RATE
		# 极低频嗡鸣 30Hz + 轻微噪声
		var sample := sin(2.0 * PI * 30.0 * t) * 0.04  # 主体
		sample += (randf() * 2.0 - 1.0) * 0.01  # 轻微噪声
		sample *= 0.04  # -28dB ≈ 0.04 线性
		var int_sample := int(sample * 32767.0)
		int_sample = clampi(int_sample, -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = int(SAMPLE_RATE)
	stream.data = data
	return stream


# ========== Breach警示音公共接口 ==========

func play_breach_warning(layer: int) -> void:
	match layer:
		1:
			play(SoundType.BREACH_WARNING_LAYER_1)
		2:
			play(SoundType.BREACH_WARNING_LAYER_2)
		3:
			play(SoundType.BREACH_WARNING_LAYER_3)
		_:
			push_warning("SoundManager: 未知 breach warning layer: %d" % layer)


# ========== 音乐音量实时响应设置变化 ==========

func _on_music_volume_changed() -> void:
	if _music_player != null and _music_player.playing:
		var music_vol: float = float(SettingsManager.get_setting("music_volume", 0.5))
		var target_db := linear_to_db(music_vol)
		if _music_tween != null and _music_tween.is_valid():
			_music_tween.kill()
		_music_tween = create_tween()
		_music_tween.tween_property(_music_player, "volume_db", target_db, 0.5)

	if _ambience_player != null and _ambience_player.playing:
		# 氛围音跟随 SFX 总线音量，但这里也可以单独处理
		pass
