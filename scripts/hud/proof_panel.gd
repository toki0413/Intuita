# proof_panel.gd
# 证明面板 - 交互式证明树显示
# 使用Tree控件替代RichTextLabel，支持分叉/嫁接/回溯操作
#
# Responsibilities:
#   - 五层验证清单（CheckBox状态）
#   - 证明树层级显示（Tree控件）
#   - 右键上下文菜单（分叉/嫁接/回溯/验证/设为活跃）
#   - 工具栏（新分支/撤销/深度/核心数）
#
# Dependencies:
#   - Autoload: VerificationPipeline, ProofTree, GameState

extends PanelContainer

const HudUtils = preload("res://scripts/hud/hud_utils.gd")

var _i18n = null
var _check1: CheckBox = null
var _check2: CheckBox = null
var _check3: CheckBox = null
var _check4: CheckBox = null
var _check5: CheckBox = null
var _tree_display: Tree = null
var _checks: Array[CheckBox] = []

# 工具栏
var _toolbar: HBoxContainer = null
var _new_branch_btn: Button = null
var _undo_btn: Button = null
var _depth_label: Label = null
var _cores_label: Label = null

# 右键菜单
var _context_menu: PopupMenu = null

# 活跃分支追踪
var _active_branch_ids: Array[int] = []

# 撤销栈
var _undo_stack: Array[Dictionary] = []

# 折叠
var _collapse_btn: Button = null
var _content_wrapper: Control = null
var _is_collapsed: bool = true  # 默认折叠


func _ready() -> void:
	_i18n = Engine.get_main_loop().root.get_node_or_null("/root/I18nManager")
	if _i18n != null and _i18n.has_signal("language_changed"):
		_i18n.language_changed.connect(_on_language_changed)
	if get_child_count() > 0:
		_assign_scene_nodes()
	else:
		_build_ui()
	UiAnimator.style_panel(self)

	# 让非交互子节点不拦截鼠标
	HudUtils.set_passthrough(self)

	# 给标题Label添加点击折叠功能
	_setup_collapse()

	UiAnimator.style_all_buttons(self, ["NewBranchBtn"])
	UiAnimator.attach_button_helpers(self)
	UiAnimator.animate_in(self)
	_checks = [_check1, _check2, _check3, _check4, _check5]
	_setup_proof_tooltips()
	var vp := get_node_or_null("/root/VerificationPipeline")
	if vp:
		vp.verification_completed.connect(_on_verification_completed)
	ProofTree.node_added.connect(_on_node_added)
	ProofTree.node_verified.connect(_on_node_verified)

	# 默认折叠
	if _is_collapsed:
		_apply_collapse(true)


func _setup_collapse() -> void:
	var title_label: Label = get_node_or_null("MarginContainer/VBox/Title")
	if title_label:
		title_label.mouse_filter = Control.MOUSE_FILTER_STOP
		title_label.gui_input.connect(_on_title_input)


func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_is_collapsed = not _is_collapsed
		_apply_collapse(_is_collapsed)


func _apply_collapse(collapsed: bool) -> void:
	var vbox: VBoxContainer = get_node_or_null("MarginContainer/VBox")
	if vbox == null:
		return
	for i in range(vbox.get_child_count()):
		var child: Node = vbox.get_child(i)
		if child is Label and child.name == "Title":
			if collapsed:
				child.text = "▶ " + (_i18n.translate("hud.proof.title") if _i18n != null else "Proof")
			else:
				child.text = "▼ " + (_i18n.translate("hud.proof.title") if _i18n != null else "Proof")
			continue
		if child is Control:
			child.visible = not collapsed
	_refresh_text()
	_rebuild_tree_display()


func _setup_proof_tooltips() -> void:
	tooltip_text = _i18n.translate("hud.proof.tooltip") if _i18n != null else ""
	var layer_desc := [
		"L1 符号验证\n检查元素符号、Wyckoff 标记是否合法\n最基础的语法层检查",
		"L2 类型检查\n检查原子类型、键类型是否匹配\n确保结构类型一致",
		"L3 逻辑推理\n检查空间群对称性、守恒律约束\n结构是否满足物理定律",
		"L4 语义验证\n检查结构是否有科学意义\n如键长、键角是否合理",
		"L5 形式化证明\n数学严格证明结构正确性\n最高级别验证，消耗核心",
	]
	for i in range(_checks.size()):
		if _checks[i]:
			_checks[i].tooltip_text = layer_desc[i]
	if _new_branch_btn:
		_new_branch_btn.tooltip_text = _i18n.translate("hud.proof.new_branch_tooltip") if _i18n != null else ""
	if _undo_btn:
		_undo_btn.tooltip_text = _i18n.translate("hud.undo_tooltip") if _i18n != null else ""
	if _depth_label:
		_depth_label.tooltip_text = _i18n.translate("hud.proof.depth_tooltip") if _i18n != null else ""
	if _cores_label:
		_cores_label.tooltip_text = _i18n.translate("hud.proof.cores_tooltip") if _i18n != null else ""


func _assign_scene_nodes() -> void:
	var margin = get_node_or_null("MarginContainer")
	var vbox = margin.get_node("VBox")
	var checklist = vbox.get_node("Checklist")
	_check1 = checklist.get_node("Check1")
	_check2 = checklist.get_node("Check2")
	_check3 = checklist.get_node("Check3")
	_check4 = checklist.get_node("Check4")
	_check5 = checklist.get_node("Check5")
	# 这些 CheckBox 仅用于显示验证状态，禁用用户交互
	for cb in [_check1, _check2, _check3, _check4, _check5]:
		if cb:
			cb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toolbar = vbox.get_node("Toolbar")
	_new_branch_btn = _toolbar.get_node("NewBranchBtn")
	_undo_btn = _toolbar.get_node("UndoBtn")
	_depth_label = _toolbar.get_node("DepthLabel")
	_cores_label = _toolbar.get_node("CoresLabel")
	_tree_display = vbox.get_node("TreeDisplay")
	_context_menu = get_node_or_null("ContextMenu")
	# wire signals
	_new_branch_btn.pressed.connect(_on_new_branch)
	_undo_btn.pressed.connect(_on_undo)
	_tree_display.item_selected.connect(_on_item_selected)
	_tree_display.item_mouse_selected.connect(_on_item_mouse_selected)
	_context_menu.add_item("Fork from here", 0)
	_context_menu.add_item("Graft subtree", 1)
	_context_menu.add_item("Backtrack", 2)
	_context_menu.add_separator()
	_context_menu.add_item("Verify", 3)
	_context_menu.add_item("Set as active", 4)
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	_update_toolbar_info()


func _build_ui() -> void:
	# 主容器
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# 标题
	var title := Label.new()
	title.text = "证明树"
	title.add_theme_font_override("font", UiAnimator.make_ui_font(22, true))
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.82, 0.35))
	vbox.add_child(title)

	# 验证清单
	var checklist := VBoxContainer.new()
	checklist.add_theme_constant_override("separation", 6)
	vbox.add_child(checklist)

	_check1 = CheckBox.new()
	_check1.text = _i18n.translate("hud.proof.l1")
	_check1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_check1.add_theme_font_override("font", UiAnimator.make_ui_font(20, false))
	_check1.add_theme_font_size_override("font_size", 20)
	checklist.add_child(_check1)

	_check2 = CheckBox.new()
	_check2.text = _i18n.translate("hud.proof.l2")
	_check2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_check2.add_theme_font_override("font", UiAnimator.make_ui_font(20, false))
	_check2.add_theme_font_size_override("font_size", 20)
	checklist.add_child(_check2)

	_check3 = CheckBox.new()
	_check3.text = _i18n.translate("hud.proof.l3")
	_check3.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_check3.add_theme_font_override("font", UiAnimator.make_ui_font(20, false))
	_check3.add_theme_font_size_override("font_size", 20)
	checklist.add_child(_check3)

	_check4 = CheckBox.new()
	_check4.text = _i18n.translate("hud.proof.l4")
	_check4.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_check4.add_theme_font_override("font", UiAnimator.make_ui_font(20, false))
	_check4.add_theme_font_size_override("font_size", 20)
	checklist.add_child(_check4)

	_check5 = CheckBox.new()
	_check5.text = _i18n.translate("hud.proof.l5")
	_check5.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_check5.add_theme_font_override("font", UiAnimator.make_ui_font(20, false))
	_check5.add_theme_font_size_override("font_size", 20)
	checklist.add_child(_check5)

	# 分隔线
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# 工具栏
	_toolbar = HBoxContainer.new()
	_toolbar.add_theme_constant_override("separation", 10)
	vbox.add_child(_toolbar)

	_new_branch_btn = Button.new()
	_new_branch_btn.text = _i18n.translate("hud.proof.new_branch")
	_new_branch_btn.add_theme_font_override("font", UiAnimator.make_ui_font(20, true))
	_new_branch_btn.add_theme_font_size_override("font_size", 20)
	_new_branch_btn.pressed.connect(_on_new_branch)
	_toolbar.add_child(_new_branch_btn)

	_undo_btn = Button.new()
	_undo_btn.text = _i18n.translate("hud.undo")
	_undo_btn.add_theme_font_override("font", UiAnimator.make_ui_font(20, true))
	_undo_btn.add_theme_font_size_override("font_size", 20)
	_undo_btn.pressed.connect(_on_undo)
	_toolbar.add_child(_undo_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toolbar.add_child(spacer)

	_depth_label = Label.new()
	_depth_label.text = "Depth: 0"
	_depth_label.add_theme_font_override("font", UiAnimator.make_ui_font(20, false))
	_depth_label.add_theme_font_size_override("font_size", 20)
	_depth_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	_toolbar.add_child(_depth_label)

	_cores_label = Label.new()
	_cores_label.text = "Cores: 0"
	_cores_label.add_theme_font_override("font", UiAnimator.make_ui_font(20, false))
	_cores_label.add_theme_font_size_override("font_size", 20)
	_cores_label.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
	_toolbar.add_child(_cores_label)

	# 证明树 (Tree控件)
	_tree_display = Tree.new()
	_tree_display.custom_minimum_size = Vector2(0, 200)
	_tree_display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree_display.hide_root = false
	_tree_display.allow_rmb_select = true
	_tree_display.item_selected.connect(_on_item_selected)
	_tree_display.item_mouse_selected.connect(_on_item_mouse_selected)
	vbox.add_child(_tree_display)

	# 右键上下文菜单
	_context_menu = PopupMenu.new()
	_context_menu.add_item("Fork from here", 0)
	_context_menu.add_item("Graft subtree", 1)
	_context_menu.add_item("Backtrack", 2)
	_context_menu.add_separator()
	_context_menu.add_item("Verify", 3)
	_context_menu.add_item("Set as active", 4)
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	add_child(_context_menu)

	_update_toolbar_info()


func _make_code_font(size: int, bold: bool = false) -> Font:
	var sys_font := SystemFont.new()
	sys_font.font_names = PackedStringArray(["JetBrains Mono", "Cascadia Code", "Consolas", "Menlo", "Courier New"])
	sys_font.font_weight = 700 if bold else 400
	sys_font.font_stretch = 100
	# 同上，用 FontVariation 包一层
	var fv := FontVariation.new()
	fv.base_font = sys_font
	fv.variation_embolden = 0.6 if bold else 0.0
	return fv


func _on_verification_completed(layer: int, result: bool, confidence: float) -> void:
	if layer >= 0 and layer < _checks.size():
		_checks[layer].button_pressed = result
		if result:
			_checks[layer].add_theme_color_override("font_color", ConservationEngine.get_state_color(0))
		else:
			_checks[layer].add_theme_color_override("font_color", ConservationEngine.get_state_color(2))
	# G5: 播放验证结果动画
	animate_layer_result(layer, result)


func _on_node_added(node: RefCounted) -> void:
	_rebuild_tree_display()


func _on_node_verified(node: RefCounted, level: int) -> void:
	_rebuild_tree_display()


func _rebuild_tree_display() -> void:
	_tree_display.clear()
	var root_node := ProofTree.get_root()
	if root_node == null:
		var root_item := _tree_display.create_item()
		root_item.set_text(0, "证明树将在此显示...")
		return

	# 创建根节点
	var root_item := _tree_display.create_item()
	_populate_tree_item(root_item, root_node)

	_update_toolbar_info()


func _populate_tree_item(tree_item: TreeItem, proof_node: RefCounted) -> void:
	# 操作图标和名称
	var op_name: String = proof_node.operation
	var icon_text: String = ""
	var icon_color: Color = Color.GRAY

	# 根据验证状态设置图标颜色
	if proof_node.is_golden:
		icon_text = "★"
		icon_color = UiAnimator.AMBER
	elif proof_node.invariants.size() > 0:
		# 有不变量数据 = 已验证
		var all_ok := true
		for key in proof_node.invariants:
			var invariant_value = proof_node.invariants[key]
			var invariant_float: float = float(invariant_value) if invariant_value is String else float(invariant_value)
			if absf(invariant_float) > 0.1:
				all_ok = false
				break
		if all_ok:
			icon_text = "●"
			icon_color = ConservationEngine.get_state_color(0)
		else:
			icon_text = "●"
			icon_color = ConservationEngine.get_state_color(2)
	else:
		icon_text = "○"
		icon_color = UiAnimator.AMBER

	# 检查是否在活跃分支上
	var is_active := _is_node_in_active_branch(proof_node)

	# 设置文本
	var display_text := "%s [id:%d] %s" % [icon_text, proof_node.id, op_name]
	tree_item.set_text(0, display_text)

	# 设置颜色
	if is_active:
		tree_item.set_custom_color(0, UiAnimator.PAPER)
	else:
		tree_item.set_custom_color(0, UiAnimator.MUTED)

	# 存储节点ID用于后续操作
	tree_item.set_metadata(0, proof_node.id)

	# L5黄金标记
	if proof_node.is_golden:
		tree_item.set_text(1, "★")
		tree_item.set_custom_color(1, UiAnimator.AMBER)

	# 递归添加子节点
	for child in proof_node.children:
		var child_item := _tree_display.create_item(tree_item)
		_populate_tree_item(child_item, child)


func _is_node_in_active_branch(proof_node: RefCounted) -> bool:
	if _active_branch_ids.is_empty():
		return true  # 没有分支时全部高亮
	return proof_node.id in _active_branch_ids


func _on_item_selected() -> void:
	var selected := _tree_display.get_selected()
	if selected:
		var node_id_raw: Variant = selected.get_metadata(0)
		if node_id_raw == null:
			return
		var node_id: int = int(node_id_raw)
		var node := ProofTree.get_node_by_id(node_id)
		if node:
			# 高亮选中节点的不变量
			pass


func _on_item_mouse_selected(position: Vector2, mouse_button: int) -> void:
	if mouse_button != MOUSE_BUTTON_RIGHT:
		return
	var selected := _tree_display.get_selected()
	if not selected:
		return
	_context_menu.position = DisplayServer.mouse_get_position()
	_context_menu.reset_size()
	_context_menu.popup()


func _on_context_menu_id_pressed(id: int) -> void:
	var selected := _tree_display.get_selected()
	if not selected:
		return
	var node_id: int = selected.get_metadata(0)
	var node := ProofTree.get_node_by_id(node_id)
	if node == null:
		return

	match id:
		0:  # Fork from here
			_do_fork(node)
		1:  # Graft subtree
			_do_graft(node)
		2:  # Backtrack
			_do_backtrack(node)
		3:  # Verify
			_do_verify(node)
		4:  # Set as active
			_set_active_branch(node)


func _do_fork(node: RefCounted) -> void:
	var new_node := ProofTree.fork(node, "Fork from #%d" % node.id)
	if new_node:
		_undo_stack.append({"action": "fork", "node_id": new_node.id, "parent_id": node.id})
		# 标记新分支为活跃
		_update_active_branch(new_node)
		_rebuild_tree_display()


func _do_graft(node: RefCounted) -> void:
	# 嫁接需要两个节点: 先选源，再选目标
	# 简化实现: 将选中节点嫁接到根节点下
	var root := ProofTree.get_root()
	if root and node != root:
		var success := ProofTree.graft(root, node)
		if success:
			_undo_stack.append({"action": "graft", "node_id": node.id})
			_rebuild_tree_display()


func _do_backtrack(node: RefCounted) -> void:
	_undo_stack.append({"action": "backtrack", "node_id": node.id, "operation": node.operation})
	ProofTree.backtrack(node)
	_rebuild_tree_display()


func _do_verify(node: RefCounted) -> void:
	# 从该节点开始验证 - 使用L1符号验证作为起点
	var statement: String = node.operation
	var vp := get_node_or_null("/root/VerificationPipeline")
	if vp == null:
		push_warning("证明面板: VerificationPipeline 未找到，无法验证")
		return
	await vp.verify(0, statement, {"node_id": node.id})


func _set_active_branch(node: RefCounted) -> void:
	_update_active_branch(node)
	_rebuild_tree_display()


func _update_active_branch(node: RefCounted) -> void:
	_active_branch_ids.clear()
	var current = node
	while current != null:
		_active_branch_ids.append(current.id)
		current = current.parent
	# 也添加该节点的所有后代
	_collect_descendant_ids(node)


func _collect_descendant_ids(node: RefCounted) -> void:
	for child in node.children:
		_active_branch_ids.append(child.id)
		_collect_descendant_ids(child)


func _on_new_branch() -> void:
	var root := ProofTree.get_root()
	if root:
		_do_fork(root)
	else:
		# 没有根节点，创建一个
		ProofTree.add_node("Root")


func _on_undo() -> void:
	if _undo_stack.is_empty():
		return
	var last: Dictionary = _undo_stack.pop_back()
	match last.get("action", ""):
		"fork":
			var node := ProofTree.get_node_by_id(last["node_id"])
			if node:
				ProofTree.backtrack(node)
		"backtrack":
			# 重建被回溯的节点
			var parent_id: int = last.get("parent_id", -1)
			var parent := ProofTree.get_node_by_id(parent_id)
			if parent:
				ProofTree.add_node(last.get("operation", "Restored"), parent)
	_rebuild_tree_display()


func _update_toolbar_info() -> void:
	var depth := ProofTree.get_tree_depth()
	_depth_label.text = _i18n.translate("hud.proof.depth", {"d": depth})
	_cores_label.text = _i18n.translate("hud.proof.cores", {"n": GameState.verification_cores})


# ---- G5: 验证结果动画 ----

func animate_layer_result(layer: int, passed: bool) -> void:
	if layer < 0 or layer >= _checks.size():
		return

	var check := _checks[layer]

	if passed:
		# 缩放 1.0 → 1.3 → 1.0 (0.3s)
		var tween := create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_BACK)
		tween.tween_property(check, "scale", Vector2(1.3, 1.3), 0.15)
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.set_trans(Tween.TRANS_SINE)
		tween.tween_property(check, "scale", Vector2.ONE, 0.15)

		# 绿色闪光
		var flash := ColorRect.new()
		flash.color = Color(ConservationEngine.get_state_color(0), 0.4)
		flash.size = check.size
		flash.position = check.position
		check.add_child(flash)
		var flash_tween := create_tween()
		flash_tween.tween_property(flash, "color:a", 0.0, 0.3)
		flash_tween.tween_callback(flash.queue_free)

		# 叮声，音高随层级递增
		SoundManager.play(SoundManager.SoundType.VERIFICATION_PASS, 0.8 + layer * 0.15)
	else:
		# 失败: 红色抖动
		var tween := create_tween()
		var orig_pos := check.position
		tween.tween_property(check, "position", orig_pos + Vector2(-3, 0), 0.05)
		tween.tween_property(check, "position", orig_pos + Vector2(3, 0), 0.05)
		tween.tween_property(check, "position", orig_pos + Vector2(-2, 0), 0.05)
		tween.tween_property(check, "position", orig_pos, 0.05)

	# 检查是否所有层都通过 → 同步脉冲
	_check_all_layers_pulse()


func _check_all_layers_pulse() -> void:
	var all_passed := true
	for check in _checks:
		if not check.button_pressed:
			all_passed = false
			break

	if all_passed and _checks.size() > 0:
		# 所有层通过 → 同步脉冲
		for i in range(_checks.size()):
			var check := _checks[i]
			var delay := i * 0.08
			get_tree().create_timer(delay).timeout.connect(func():
				if not is_instance_valid(check):
					return
				var pulse := create_tween()
				pulse.set_ease(Tween.EASE_OUT)
				pulse.set_trans(Tween.TRANS_BACK)
				pulse.tween_property(check, "scale", Vector2(1.25, 1.25), 0.1)
				pulse.set_ease(Tween.EASE_IN_OUT)
				pulse.set_trans(Tween.TRANS_SINE)
				pulse.tween_property(check, "scale", Vector2.ONE, 0.1)
			)

func _exit_tree() -> void:
	if _i18n != null and _i18n.is_connected("language_changed", _on_language_changed):
		_i18n.language_changed.disconnect(_on_language_changed)
	var vp := get_node_or_null("/root/VerificationPipeline")
	if vp != null and vp.verification_completed.is_connected(_on_verification_completed):
		vp.verification_completed.disconnect(_on_verification_completed)
	if ProofTree != null and ProofTree.node_added.is_connected(_on_node_added):
		ProofTree.node_added.disconnect(_on_node_added)
	if ProofTree != null and ProofTree.node_verified.is_connected(_on_node_verified):
		ProofTree.node_verified.disconnect(_on_node_verified)

func _on_language_changed(_locale: String) -> void:
	_refresh_text()

func _refresh_text() -> void:
	if _i18n == null:
		return
	var title = get_node_or_null("MarginContainer/VBox/Title")
	if title:
		title.text = _i18n.translate("hud.proof.title")
	_setup_proof_tooltips()
	_update_toolbar_info()
