# procedural_audio.gd
# 程序化音频引擎 - 用AudioStreamGenerator实时合成音效
# 零音频文件依赖，所有声音由数学公式生成
#
# !! 已弃用 !!
# 项目里的音效现在统一走 SoundManager（res://scripts/autoload/06_sound_manager.gd），
# 它接管了总线创建、播放器池、设置同步等所有职责。
# 这里保留 autoload 是为了不破坏 project.godot 的引用，
# 但 _ready() 已改为空操作，不再创建播放器池、不再连接信号，
# 避免和 SoundManager 重复占用音频资源。
#
# 用法: 请改用 SoundManager.play(SoundManager.SoundType.XXX)

extends Node

const MIX_RATE := 22050.0
const MAX_PLAYERS := 4

var _players: Array[AudioStreamPlayer] = []
var _volume: float = 0.7
var _muted: bool = false


var _on_setting_changed_conn: Callable

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 已弃用：所有逻辑迁移到 SoundManager，这里保持空操作避免重复占用音频总线
	pass


func _exit_tree() -> void:
	# 已弃用：_ready() 不再连接信号，这里也保持空操作
	pass


func _on_setting_changed(_key: String, _value: Variant) -> void:
	# 已弃用：音量同步由 SoundManager 负责
	pass


func set_mute(muted: bool) -> void:
	_muted = muted
	if muted:
		for p in _players:
			if p.playing:
				p.stop()


func is_muted() -> bool:
	return _muted


# --- 公开接口 ---

func play_place_tick() -> void:
	# 放置原子 - 5ms高频咔哒
	_play_sine_burst(2200.0, 0.005, 0.6)

func play_bond_snap() -> void:
	# 键合形成 - 20ms上升音
	_play_sweep(600.0, 1400.0, 0.02, 0.5)

func play_verify_success() -> void:
	# 验证通过 - 100ms大三和弦
	_play_chord([523.25, 659.25, 783.99], 0.1, 0.45)

func play_verify_fail() -> void:
	# 验证失败 - 80ms低频嗡
	_play_sine_burst(120.0, 0.08, 0.5)

func play_fog_clear() -> void:
	# 迷雾消散 - 200ms失谐正弦
	_play_detuned(440.0, 6.0, 0.2, 0.35)

func play_disintegrate() -> void:
	# 结构崩解 - 150ms噪音
	_play_noise_burst(0.15, 0.55)

func play_gold_burst() -> void:
	# L5形式化验证 - 300ms丰富谐波
	_play_rich_tone(440.0, 0.3, 0.5)

func play_ui_click() -> void:
	# UI点击 - 微弱咔
	_play_sine_burst(1800.0, 0.003, 0.25)


# --- 内部实现 ---

func _get_idle_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	return null


func _push_frames(playback: AudioStreamPlayback, frames: PackedVector2Array) -> void:
	# 分批推帧，避免一次推太多卡住
	var idx := 0
	while idx < frames.size():
		var space: int = playback.get_frames_available()
		if space <= 0:
			# 等一帧再试
			await get_tree().process_frame
			continue
		var end := mini(idx + space, frames.size())
		playback.push_buffer(frames.slice(idx, end))
		idx = end


func _make_envelope(samples: int, attack_pct: float, release_pct: float) -> PackedFloat32Array:
	# 简单的attack-release包络
	var env := PackedFloat32Array()
	env.resize(samples)
	var attack_samples := int(samples * attack_pct)
	var release_samples := int(samples * release_pct)
	for i in range(samples):
		var v := 1.0
		if i < attack_samples and attack_samples > 0:
			v = float(i) / float(attack_samples)
		elif i >= samples - release_samples and release_samples > 0:
			v = float(samples - i) / float(release_samples)
		env[i] = v
	return env


func _play_sine_burst(freq: float, duration: float, amplitude: float) -> void:
	if _muted:
		return
	var player := _get_idle_player()
	if player == null:
		return

	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	player.stream = gen
	player.volume_db = linear_to_db(_volume)
	player.play()

	var playback: AudioStreamPlayback = player.get_stream_playback()
	var total := int(MIX_RATE * duration)
	var env := _make_envelope(total, 0.1, 0.4)
	var frames := PackedVector2Array()
	frames.resize(total)
	for i in range(total):
		var t := float(i) / MIX_RATE
		var s := amplitude * env[i] * sin(2.0 * PI * freq * t)
		frames[i] = Vector2(s, s)
	_push_frames(playback, frames)


func _play_sweep(freq_start: float, freq_end: float, duration: float, amplitude: float) -> void:
	if _muted:
		return
	var player := _get_idle_player()
	if player == null:
		return

	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	player.stream = gen
	player.volume_db = linear_to_db(_volume)
	player.play()

	var playback: AudioStreamPlayback = player.get_stream_playback()
	var total := int(MIX_RATE * duration)
	var env := _make_envelope(total, 0.1, 0.5)
	var frames := PackedVector2Array()
	frames.resize(total)
	var phase := 0.0
	for i in range(total):
		var t := float(i) / MIX_RATE
		var freq := freq_start + (freq_end - freq_start) * (float(i) / float(total))
		phase += 2.0 * PI * freq / MIX_RATE
		var s := amplitude * env[i] * sin(phase)
		frames[i] = Vector2(s, s)
	_push_frames(playback, frames)


func _play_chord(freqs: Array, duration: float, amplitude: float) -> void:
	if _muted:
		return
	var player := _get_idle_player()
	if player == null:
		return

	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	player.stream = gen
	player.volume_db = linear_to_db(_volume)
	player.play()

	var playback: AudioStreamPlayback = player.get_stream_playback()
	var total := int(MIX_RATE * duration)
	var env := _make_envelope(total, 0.15, 0.35)
	var frames := PackedVector2Array()
	frames.resize(total)
	var count := float(freqs.size())
	for i in range(total):
		var t := float(i) / MIX_RATE
		var s := 0.0
		for freq in freqs:
			s += sin(2.0 * PI * freq * t)
		s = amplitude * env[i] * s / count
		frames[i] = Vector2(s, s)
	_push_frames(playback, frames)


func _play_detuned(base_freq: float, detune_hz: float, duration: float, amplitude: float) -> void:
	if _muted:
		return
	var player := _get_idle_player()
	if player == null:
		return

	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	player.stream = gen
	player.volume_db = linear_to_db(_volume)
	player.play()

	var playback: AudioStreamPlayback = player.get_stream_playback()
	var total := int(MIX_RATE * duration)
	var env := _make_envelope(total, 0.2, 0.4)
	var frames := PackedVector2Array()
	frames.resize(total)
	for i in range(total):
		var t := float(i) / MIX_RATE
		# 两个略微失谐的正弦波产生拍频效果
		var left := amplitude * env[i] * sin(2.0 * PI * base_freq * t)
		var right := amplitude * env[i] * sin(2.0 * PI * (base_freq + detune_hz) * t)
		frames[i] = Vector2(left, right)
	_push_frames(playback, frames)


func _play_noise_burst(duration: float, amplitude: float) -> void:
	if _muted:
		return
	var player := _get_idle_player()
	if player == null:
		return

	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	player.stream = gen
	player.volume_db = linear_to_db(_volume)
	player.play()

	var playback: AudioStreamPlayback = player.get_stream_playback()
	var total := int(MIX_RATE * duration)
	var env := _make_envelope(total, 0.02, 0.6)
	var frames := PackedVector2Array()
	frames.resize(total)
	for i in range(total):
		var s := amplitude * env[i] * (randf() * 2.0 - 1.0)
		frames[i] = Vector2(s, s)
	_push_frames(playback, frames)


func _play_rich_tone(base_freq: float, duration: float, amplitude: float) -> void:
	# 叠加1~5次谐波，模拟丰富音色
	if _muted:
		return
	var player := _get_idle_player()
	if player == null:
		return

	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	player.stream = gen
	player.volume_db = linear_to_db(_volume)
	player.play()

	var playback: AudioStreamPlayback = player.get_stream_playback()
	var total := int(MIX_RATE * duration)
	var env := _make_envelope(total, 0.1, 0.4)
	var frames := PackedVector2Array()
	frames.resize(total)
	for i in range(total):
		var t := float(i) / MIX_RATE
		var s := 0.0
		for h in range(1, 6):
			# 高次谐波衰减
			var harm_amp := 1.0 / float(h)
			s += harm_amp * sin(2.0 * PI * base_freq * float(h) * t)
		s = amplitude * env[i] * s * 0.4
		frames[i] = Vector2(s, s)
	_push_frames(playback, frames)
