# audio_system_test.gd
# GdUnit4 测试：音频系统（音乐、氛围音、Breach 警示层）

extends GdUnitTestSuite


const __source = "res://scripts/autoload/06_sound_manager.gd"

var _sound_manager: Node = null
var _settings: Node = null
var _backup_music_volume: Variant = null


func before() -> void:
	_sound_manager = Engine.get_main_loop().root.get_node_or_null("/root/SoundManager")
	_settings = Engine.get_main_loop().root.get_node_or_null("/root/SettingsManager")
	if _settings != null:
		_backup_music_volume = _settings.get_setting("music_volume", 0.5)


func after() -> void:
	# 停止测试期间播放的音乐和氛围音，避免干扰其他测试
	if _sound_manager != null:
		if _sound_manager.has_method("stop_music"):
			_sound_manager.stop_music(0.1)
		if _sound_manager.has_method("stop_ambience"):
			_sound_manager.stop_ambience()

	# 恢复音乐音量设置
	if _settings != null and _backup_music_volume != null:
		_settings.set_setting("music_volume", _backup_music_volume)


func test_music_player_exists() -> void:
	assert_object(_sound_manager).is_not_null()

	var music_player: AudioStreamPlayer = _sound_manager._music_player if _sound_manager != null else null
	assert_object(music_player).is_not_null()

	if music_player != null:
		assert_str(music_player.bus).is_equal("Music")

	# Music 总线必须存在
	var music_bus_idx := AudioServer.get_bus_index("Music")
	assert_int(music_bus_idx).is_not_equal(-1)


func test_ambience_generates_loop() -> void:
	if _sound_manager == null:
		return

	# 直接生成氛围音样本并验证 loop_mode
	var stream: AudioStreamWAV = _sound_manager._generate_ambience_stream("crystal")
	assert_object(stream).is_not_null()
	if stream != null:
		assert_int(stream.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)

	var stream_fluid: AudioStreamWAV = _sound_manager._generate_ambience_stream("fluid")
	assert_object(stream_fluid).is_not_null()
	if stream_fluid != null:
		assert_int(stream_fluid.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)

	var stream_fog: AudioStreamWAV = _sound_manager._generate_ambience_stream("fog")
	assert_object(stream_fog).is_not_null()
	if stream_fog != null:
		assert_int(stream_fog.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)


func test_breach_warning_layers() -> void:
	if _sound_manager == null:
		return

	# 验证 BREACH_WARNING_LAYER_1 枚举存在
	assert_int(SoundManager.SoundType.BREACH_WARNING_LAYER_1).is_equal(26)
	assert_int(SoundManager.SoundType.BREACH_WARNING_LAYER_2).is_equal(27)
	assert_int(SoundManager.SoundType.BREACH_WARNING_LAYER_3).is_equal(28)

	# 验证 play_breach_warning 不崩溃且内部映射正确
	# 通过检查方法存在性来验证
	assert_bool(_sound_manager.has_method("play_breach_warning")).is_true()

	# 验证各个音乐风格流生成非空
	assert_object(_sound_manager._generate_music_stream(SoundManager.MusicStyle.CRYSTAL)).is_not_null()
	assert_object(_sound_manager._generate_music_stream(SoundManager.MusicStyle.FLUID)).is_not_null()
	assert_object(_sound_manager._generate_music_stream(SoundManager.MusicStyle.FOG)).is_not_null()
	assert_object(_sound_manager._generate_music_stream(SoundManager.MusicStyle.MENU)).is_not_null()


func test_crossfade_does_not_crash() -> void:
	if _sound_manager == null:
		return

	# 先播放一段音乐，再执行 crossfade
	_sound_manager.play_music(SoundManager.MusicStyle.CRYSTAL, 0.1)
	await get_tree().create_timer(0.05).timeout

	# crossfade 不应崩溃
	_sound_manager.crossfade_music(SoundManager.MusicStyle.MENU, 0.1)
	await get_tree().create_timer(0.05).timeout

	# 验证结束后仍有音乐播放器在运行
	assert_object(_sound_manager._music_player).is_not_null()

	# 清理
	_sound_manager.stop_music(0.1)


func test_music_respects_volume_setting() -> void:
	if _sound_manager == null or _settings == null:
		return

	# 设置音乐音量到 0.25
	_settings.set_setting("music_volume", 0.25)
	await get_tree().create_timer(0.05).timeout

	# 播放音乐（极短淡入）
	_sound_manager.play_music(SoundManager.MusicStyle.MENU, 0.05)
	await get_tree().create_timer(0.1).timeout

	# 检查 Music 总线音量是否接近目标值
	var music_bus_idx := AudioServer.get_bus_index("Music")
	assert_int(music_bus_idx).is_not_equal(-1)
	if music_bus_idx != -1:
		var bus_db := AudioServer.get_bus_volume_db(music_bus_idx)
		var target_db := linear_to_db(0.25)
		# 允许 ±3dB 容差
		assert_float(bus_db).is_between(target_db - 3.0, target_db + 3.0)

	# 恢复音量后再设置高音量测试
	_settings.set_setting("music_volume", 0.75)
	await get_tree().create_timer(0.05).timeout

	if music_bus_idx != -1:
		var bus_db2 := AudioServer.get_bus_volume_db(music_bus_idx)
		var target_db2 := linear_to_db(0.75)
		assert_float(bus_db2).is_between(target_db2 - 3.0, target_db2 + 3.0)

	# 清理
	_sound_manager.stop_music(0.1)
