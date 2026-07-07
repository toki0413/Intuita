# effect_manager.gd
# 效果管理器 - 守恒辉光、迷雾、瓦解级联、验证动画
extends RefCounted

var _fog_volumes: Array[Node3D] = []
var fog_container: Node3D
var _canvas: Node3D  # 用于get_tree()和add_child

# 慢动作状态
var _slow_motion_active: bool = false
var _slow_motion_tween: Tween = null

# 验证动画引用
var _verification_anim_data: Dictionary = {}


func _init(fog: Node3D, canvas: Node3D) -> void:
	fog_container = fog
	_canvas = canvas


func get_fog_volumes() -> Array[Node3D]:
	return _fog_volumes


# ---- 守恒辉光 ----

func update_all_atom_glows(atoms: Array[Node3D]) -> void:
	var summary: Dictionary = ConservationEngine.get_deviation_summary()
	var max_dev: float = 0.0
	for key in summary:
		var dev: float = summary[key]["deviation"]
		if dev > max_dev:
			max_dev = dev

	for atom in atoms:
		if not is_instance_valid(atom):
			continue
		atom.call("update_glow_from_conservation", max_dev)

	# 同步更新所有键的应力状态
	update_all_bond_stress(max_dev)


func update_all_bond_stress(deviation: float) -> void:
	# 遍历所有键，更新守恒应力可视化
	if _canvas == null or not _canvas.is_inside_tree():
		return
	var bonds_node := _canvas.get_node_or_null("Bonds")
	if bonds_node == null:
		return
	for child in bonds_node.get_children():
		if child is MeshInstance3D and child.has_method("update_stress"):
			child.update_stress(deviation)


# ---- 迷雾 ----

func create_fog_volume(region_id: int, fog_type: int) -> void:
	var region = FogSystem.active_fog_regions.get(region_id)
	if region == null:
		return

	var fog_script := load("res://scripts/construction/fog_volume.gd")
	var fog := Node3D.new()
	fog.set_script(fog_script)
	# 用 set() 赋值避免强类型枚举属性的直接赋值报错
	fog.set("fog_type", fog_type)
	fog.set("region_id", region_id)
	fog.position = region.position
	fog.set("_fog_radius", region.radius)

	fog_container.add_child(fog)
	_fog_volumes.append(fog)


# ---- 瓦解级联 ----

func start_disintegration_cascade(atoms: Array[Node3D], failed_row: int = -1) -> void:
	# 触发慢动作
	_trigger_slow_motion()

	var sorted_atoms: Array[Node3D] = []
	for atom in atoms:
		if is_instance_valid(atom):
			sorted_atoms.append(atom)

	sorted_atoms.sort_custom(func(a, b): return a.global_position.length() > b.global_position.length())

	for i in range(sorted_atoms.size()):
		var atom := sorted_atoms[i]
		var delay := i * 0.15
		var bound_atom: Node3D = atom
		var bound_row: int = failed_row
		_canvas.get_tree().create_timer(delay).timeout.connect(
			func() -> void: _disintegrate_atom(bound_atom, bound_row)
		)


# 受控崩溃的爆炸特效（单点引爆）
func spawn_explosion(pos: Vector3) -> void:
	var effect := ParticlePool.acquire_particle(
		ParticlePool.ParticleType.DISINTEGRATION, pos)
	if effect == null:
		return
	if effect.has_method("start"):
		effect.start(null)


func _disintegrate_atom(atom: Node3D, failed_row: int = -1) -> void:
	if not is_instance_valid(atom):
		return

	var effect := ParticlePool.acquire_particle(
		ParticlePool.ParticleType.DISINTEGRATION, atom.global_position)
	if effect == null:
		return
	if effect.has_method("start"):
		effect.start(atom)

	atom.call("start_disintegration", failed_row)


# ---- 慢动作 ----

func _trigger_slow_motion() -> void:
	if _slow_motion_active:
		return
	if not is_instance_valid(_canvas) or not _canvas.is_inside_tree():
		return
	_slow_motion_active = true
	Engine.time_scale = 0.3

	# 1.5秒后逐渐恢复到1.0，绑定到 canvas 生命周期
	var tree := _canvas.get_tree()
	if tree:
		tree.create_timer(1.5).timeout.connect(_recover_from_slow_motion)


func _recover_from_slow_motion() -> void:
	# 渐进恢复时间缩放
	if not is_instance_valid(_canvas) or not _canvas.is_inside_tree():
		Engine.time_scale = 1.0
		_slow_motion_active = false
		return

	var tree := _canvas.get_tree()
	if not tree:
		Engine.time_scale = 1.0
		_slow_motion_active = false
		return

	# 用Tween做平滑恢复（通过canvas创建tween）
	var tween := _canvas.create_tween()
	tween.tween_method(_set_time_scale, 0.3, 1.0, 0.5)
	tween.tween_callback(func():
		_slow_motion_active = false
		Engine.time_scale = 1.0  # 确保最终值
	)


func cleanup() -> void:
	# 确保退出时恢复时间缩放（RefCounted 不会自动调用 _exit_tree）
	if _slow_motion_active:
		Engine.time_scale = 1.0
		_slow_motion_active = false


func _set_time_scale(val: float) -> void:
	Engine.time_scale = val


# ---- 验证动画 ----

func play_verification_animation(layer: int, passed: bool) -> void:
	# 由construction_canvas调用，触发验证层的视觉反馈
	_verification_anim_data = {
		"layer": layer,
		"passed": passed,
		"timestamp": Time.get_ticks_msec(),
	}

	# 获取所有原子和键
	var atoms: Array[Node3D] = []
	var bonds: Array[Node3D] = []
	if _canvas.has_method("get_node_or_null"):
		var atoms_node := _canvas.get_node_or_null("Atoms")
		var bonds_node := _canvas.get_node_or_null("Bonds")
		if atoms_node:
			for child in atoms_node.get_children():
				if child is MeshInstance3D:
					atoms.append(child)
		if bonds_node:
			for child in bonds_node.get_children():
				if child is MeshInstance3D:
					bonds.append(child)

	match layer:
		0: _animate_l1_symbolic(atoms, passed)
		1: _animate_l2_type(bonds, passed)
		2: _animate_l3_logic(passed)


func _animate_l1_symbolic(atoms: Array[Node3D], passed: bool) -> void:
	# L1: 原子标签逐个闪白
	for i in range(atoms.size()):
		var atom := atoms[i]
		if not is_instance_valid(atom):
			continue
		var delay := i * 0.05
		var tree := _canvas.get_tree()
		if tree:
			tree.create_timer(delay).timeout.connect(func():
				if not is_instance_valid(atom):
					return
				var mat := atom.surface_get_material(0) as StandardMaterial3D
				if mat:
					mat.emission_enabled = true
					mat.emission = Color.WHITE
					mat.emission_energy = 1.5
					var t := atom.create_tween()
					t.tween_property(mat, "emission_energy_multiplier", 0.0, 0.15)
				SoundManager.play(SoundManager.SoundType.VERIFICATION_PASS)
			)

	# 最终结果
	if not passed:
		var tree := _canvas.get_tree()
		if tree:
			tree.create_timer(atoms.size() * 0.05 + 0.1).timeout.connect(func():
				_flash_all_atoms(atoms, Color(1.0, 0.2, 0.2))
				SoundManager.play(SoundManager.SoundType.VERIFICATION_FAIL)
			)


func _animate_l2_type(bonds: Array[Node3D], passed: bool) -> void:
	# L2: 键逐个闪青色
	for i in range(bonds.size()):
		var bond := bonds[i]
		if not is_instance_valid(bond):
			continue
		var delay := i * 0.05
		var tree := _canvas.get_tree()
		if tree:
			tree.create_timer(delay).timeout.connect(func():
				if not is_instance_valid(bond):
					return
				var mat := bond.surface_get_material(0) as StandardMaterial3D
				if mat:
					mat.emission_enabled = true
					mat.emission = Color(0.0, 0.9, 0.9)
					mat.emission_energy = 1.5
					var t := bond.create_tween()
					t.tween_property(mat, "emission_energy_multiplier", 0.0, 0.15)
			)

	if not passed:
		var tree := _canvas.get_tree()
		if tree:
			tree.create_timer(bonds.size() * 0.05 + 0.1).timeout.connect(func():
				SoundManager.play(SoundManager.SoundType.VERIFICATION_FAIL)
			)


func _animate_l3_logic(passed: bool) -> void:
	# L3: 守恒矩阵行逐个亮起（通过HUD的flash_row）
	var hud := _canvas.get_node_or_null("../HUD/ConservationHUD")
	if hud and hud.has_method("flash_row"):
		for i in range(4):
			var delay := i * 0.12
			var tree := _canvas.get_tree()
			if tree:
				tree.create_timer(delay).timeout.connect(func():
					hud.call("flash_row", i)
				)

	if passed:
		var tree := _canvas.get_tree()
		if tree:
			tree.create_timer(0.6).timeout.connect(func():
				SoundManager.play(SoundManager.SoundType.VERIFICATION_PASS)
			)


func _flash_all_atoms(atoms: Array[Node3D], color: Color) -> void:
	# 减少闪烁模式下跳过原子集体闪烁
	if UiAnimator != null and UiAnimator.is_flashing_reduced():
		return
	for atom in atoms:
		if not is_instance_valid(atom):
			continue
		var mat := atom.surface_get_material(0) as StandardMaterial3D
		if mat:
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy = 1.5
			var t := atom.create_tween()
			t.tween_property(mat, "emission_energy_multiplier", 0.0, UiAnimator.safe_flash_duration(0.3))


func clear_fog() -> void:
	for fog in _fog_volumes:
		if is_instance_valid(fog):
			fog.queue_free()
	_fog_volumes.clear()


# ---- G2: 法医分析报告 ----

var _forensics_popup: PanelContainer = null

func show_forensics_report(failed_row: int, deviation: float, operation: String) -> void:
	# 创建守恒违约报告弹窗
	if _forensics_popup and is_instance_valid(_forensics_popup):
		_forensics_popup.queue_free()

	var popup := PanelContainer.new()
	popup.name = "ForensicsReport"
	popup.anchors_preset = Control.PRESET_CENTER
	popup.offset_left = -250
	popup.offset_top = -180
	popup.offset_right = 250
	popup.offset_bottom = 180

	# 获取 I18nManager
	var _i18n = null
	if _canvas != null and _canvas.is_inside_tree():
		_i18n = _canvas.get_tree().root.get_node_or_null("/root/I18nManager")

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)

	# 标题
	var title := Label.new()
	title.text = _i18n.translate("hud.breach.title") if _i18n != null else "Conservation Breach Report"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title_font := SystemFont.new()
	title_font.font_names = PackedStringArray(["Arial", "Segoe UI"])
	title.add_theme_font_override("font", title_font)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", ConservationEngine.get_state_color(2))
	vbox.add_child(title)

	# 违反的守恒律
	var law_names := []
	if _i18n != null:
		law_names = [
			_i18n.translate("hud.breach.law_mass"),
			_i18n.translate("hud.breach.law_charge"),
			_i18n.translate("hud.breach.law_momentum"),
			_i18n.translate("hud.breach.law_energy")
		]
	else:
		law_names = ["Mass Conservation", "Charge Conservation", "Momentum Conservation", "Energy Conservation"]
	var law_label := Label.new()
	law_label.text = (_i18n.translate("hud.breach.violated", {"law": law_names[clampi(failed_row, 0, 3)]}) if _i18n != null else "Violated: " + law_names[clampi(failed_row, 0, 3)])
	law_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var law_font := SystemFont.new()
	law_font.font_names = PackedStringArray(["Arial", "Segoe UI"])
	law_label.add_theme_font_override("font", law_font)
	law_label.add_theme_font_size_override("font_size", 20)
	law_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	vbox.add_child(law_label)

	# 偏离度可视化条
	var bar_container := HBoxContainer.new()
	bar_container.alignment = BoxContainer.ALIGNMENT_CENTER

	var bar_label := Label.new()
	bar_label.text = _i18n.translate("hud.breach.deviation") if _i18n != null else "Deviation:"
	var bar_label_font := SystemFont.new()
	bar_label_font.font_names = PackedStringArray(["Arial", "Segoe UI"])
	bar_label.add_theme_font_override("font", bar_label_font)
	bar_label.add_theme_font_size_override("font_size", 20)
	bar_container.add_child(bar_label)

	var bar_bg := PanelContainer.new()
	bar_bg.custom_minimum_size = Vector2(200, 24)
	var bar_fill := ColorRect.new()
	bar_fill.color = ConservationEngine.get_state_color(2)
	bar_fill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var fill_width := clampf(deviation, 0.0, 1.0) * 200.0
	bar_fill.custom_minimum_size = Vector2(fill_width, 24)
	bar_bg.add_child(bar_fill)
	bar_container.add_child(bar_bg)

	var dev_val := Label.new()
	dev_val.text = "%.2f" % deviation
	var dev_font := SystemFont.new()
	dev_font.font_names = PackedStringArray(["Cascadia Code"])
	dev_val.add_theme_font_override("font", dev_font)
	dev_val.add_theme_font_size_override("font_size", 20)
	dev_val.add_theme_color_override("font_color", ConservationEngine.get_state_color(2))
	bar_container.add_child(dev_val)
	vbox.add_child(bar_container)

	# 操作来源
	var op_label := Label.new()
	op_label.text = (_i18n.translate("hud.breach.caused_by", {"operation": operation}) if _i18n != null else "Caused by: " + operation)
	op_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var op_font := SystemFont.new()
	op_font.font_names = PackedStringArray(["Cascadia Code"])
	op_label.add_theme_font_override("font", op_font)
	op_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(op_label)

	# 按钮区
	var btn_container := HBoxContainer.new()
	btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_container.add_theme_constant_override("separation", 20)

	var backtrack_btn := Button.new()
	backtrack_btn.text = _i18n.translate("hud.breach.backtrack") if _i18n != null else "Backtrack to Safe State (2 cores)"
	backtrack_btn.pressed.connect(_on_backtrack_pressed)
	btn_container.add_child(backtrack_btn)

	var retry_btn := Button.new()
	retry_btn.text = _i18n.translate("hud.breach.retry") if _i18n != null else "Retry Level"
	retry_btn.pressed.connect(_on_forensics_retry_pressed)
	btn_container.add_child(retry_btn)

	vbox.add_child(btn_container)
	popup.add_child(vbox)

	# 添加到场景树
	var parent := _canvas.get_parent()
	if parent:
		var hud := parent.get_node_or_null("HUD")
		if hud:
			hud.add_child(popup)
		else:
			parent.add_child(popup)
	else:
		_canvas.get_tree().root.add_child(popup)

	_forensics_popup = popup
	SoundManager.play(SoundManager.SoundType.VERIFICATION_FAIL)


func _on_backtrack_pressed() -> void:
	if _forensics_popup and is_instance_valid(_forensics_popup):
		_forensics_popup.visible = false
		_forensics_popup.queue_free()
		_forensics_popup = null

	# 花费2核心回溯
	if GameState.spend_cores(2):
		ConservationEngine.reset_to_safe_state()
		SoundManager.play(SoundManager.SoundType.CORE_SPEND)
		# 不重启关卡，继续当前关卡
	else:
		# 核心不够，只能重试
		_on_forensics_retry_pressed()


func _on_forensics_retry_pressed() -> void:
	if _forensics_popup and is_instance_valid(_forensics_popup):
		_forensics_popup.visible = false
		_forensics_popup.queue_free()
		_forensics_popup = null

	# 重启当前关卡
	var chapter: int = LevelManager.current_level_data.get("chapter", 1)
	var level: int = LevelManager.current_level_data.get("level", 1)
	LevelManager.load_level(chapter, level)
