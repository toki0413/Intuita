# construction_canvas.gd
# 构造画布主控制器 - 薄协调层
# 将具体逻辑委托给4个子管理器:
#   - CameraController: 相机轨道控制
#   - AtomPlacementManager: 原子放置/删除/成键
#   - DomainManager: 域配置
#   - EffectManager: 辉光/迷雾/瓦解
#
# Dependencies:
#   - Autoload: ConservationEngine, FogSystem, ProofTree, LevelManager, GameState, SoundManager, MorphismSystem, VerificationPipeline

extends Node3D

const CellularAutomatonEngine = preload("res://scripts/simulation/cellular_automaton_engine.gd")
const CAGridRenderer = preload("res://scripts/construction/ca_grid_renderer.gd")
const StructureSimulatorRef = preload("res://scripts/construction/structure_simulator.gd")

# ===== 游戏性增强系统 (P0-P2) =====
const FloatingTextSystem = preload("res://scripts/gameplay/floating_text_system.gd")
const ComboSystem = preload("res://scripts/gameplay/combo_system.gd")
const DiagnosticHighlighter = preload("res://scripts/gameplay/diagnostic_highlighter.gd")
const PredictiveVerifier = preload("res://scripts/gameplay/predictive_verifier.gd")
const ElementAffinity = preload("res://scripts/gameplay/element_affinity.gd")
const ToolComboSystem = preload("res://scripts/gameplay/tool_combo_system.gd")
const DynamicDifficulty = preload("res://scripts/gameplay/dynamic_difficulty.gd")
# ===== 核心玩法机制 =====
const ChemicalReactionEngine = preload("res://scripts/gameplay/chemical_reaction_engine.gd")
const PhaseTransitionSystem = preload("res://scripts/gameplay/phase_transition_system.gd")
const SymmetryWeavingSys = preload("res://scripts/gameplay/symmetry_weaving_system.gd")
const DefectMgrSys = preload("res://scripts/gameplay/defect_manager.gd")
const SpinOrderingSys = preload("res://scripts/gameplay/spin_ordering_system.gd")
const StrainFieldSys = preload("res://scripts/gameplay/strain_field_system.gd")
const ThermoStabilitySys = preload("res://scripts/gameplay/thermodynamic_stability.gd")
const PhononSpectrumSys = preload("res://scripts/gameplay/phonon_spectrum_system.gd")
const CatalystNetworkSys = preload("res://scripts/gameplay/catalyst_network_system.gd")
const QuantumTunnelingSys = preload("res://scripts/gameplay/quantum_tunneling_system.gd")
const ResonanceCascadeSys = preload("res://scripts/gameplay/resonance_cascade_system.gd")
const PlacementGuideSys = preload("res://scripts/gameplay/placement_guide_system.gd")
const ContextualHintSys = preload("res://scripts/gameplay/contextual_hint_system.gd")

signal tool_changed(tool: int)

enum Tool { PLACE, SUBSTITUTE, SOFT_MODE, INTERCALATE, DELETE, BOND_BUILD, ASSEMBLE, PATH_BUILD, CELLULAR_STEP, TUNE_MATRIX, DETONATE }

const QUICK_ELEMENTS: Array[String] = ["H", "He", "Li", "Be", "B", "C", "N", "O", "F"]

# 本地常量: 避免单独 load() 时 VerificationPipeline 常量不可见
const _LAYER_LOGIC: int = 2
const _LAYER_FORMAL: int = 4
const _CORE_COSTS: Array[int] = [0, 0, 1, 2, 3]

var current_tool: Tool = Tool.PLACE:
	set(value):
		current_tool = value
		if _atom_mgr:
			_atom_mgr.current_tool = value
var current_element_index: int = 0

# 子管理器
var _camera_ctrl: RefCounted
var _atom_mgr: RefCounted
var _domain_mgr: RefCounted
var _effect_mgr: RefCounted
var _particle_system: Node3D = null
var _sandbox_mgr: RefCounted = null
var _undo_redo_mgr: RefCounted = null
var _verification_animator: RefCounted = null
var _collapse_history: Array = []  # 受控崩溃历史，供侦探模式回溯
var _structure_sim: Node = null  # 物理模拟器（所有模式共享）

var _current_domain: String = "crystal"
var _current_construction_mode: String = "wyckoff_fill"

# 路径可视化: path_build 模式下用线段连接已放置的原子
var _path_lines: Node3D = null
# 组装区域: assembly 模式下用半透明色块标记不同区域
var _region_markers: Node3D = null
# 能量图: reaction_path 模式下显示反应坐标能量变化
var _energy_diagram: Control = null

# ===== 游戏性增强系统实例 =====
# Progressive feedback: Ch1 shows basics only, Ch2 adds conservation, Ch3+ full
var _chapter: int = 1
var _float_text: FloatingTextSystem = null
# Besiege模式: 搭建阶段放置原子，运行阶段物理接管
var _sim_running: bool = false
var _sim_settled: bool = false
var _sim_timer: float = 0.0
var _build_phase: bool = true
# 模拟模式: "strain"(默认), "thermal"(升温相变), "magnetic"(磁有序), "catalyst"(催化), "resonance"(共振)
var _sim_mode: String = "strain"
var _sim_target_temp: float = 0.0  # 热模拟目标温度
var _combo_sys: ComboSystem = null
var _diagnostic: DiagnosticHighlighter = null
var _predictive: PredictiveVerifier = null
var _affinity: ElementAffinity = null
var _tool_combo: ToolComboSystem = null
var _dyn_difficulty: DynamicDifficulty = null
# ===== 核心玩法机制实例 =====
var _reaction_engine: ChemicalReactionEngine = null
var _phase_system: PhaseTransitionSystem = null
var _weave_system: RefCounted = null
var _defect_mgr: RefCounted = null
var _spin_system: RefCounted = null
var _strain_field: RefCounted = null
var _thermo_sys: RefCounted = null
var _phonon_sys: RefCounted = null
var _catalyst_net: RefCounted = null
var _tunneling_sys: RefCounted = null
var _resonance_sys: RefCounted = null
var _guide_sys: RefCounted = null
var _context_hint: ContextualHintSys = null

# 左键拖拽检测
var _left_drag_start: Vector2 = Vector2.ZERO
var _left_dragging: bool = false
const DRAG_THRESHOLD: float = 5.0


# ESC 暂停确认弹窗
var _pause_dialog: ConfirmationDialog = null

# 节点引用
@onready var camera: Camera3D = $Camera3D
@onready var crystal_cell: Node3D = $CrystalCell
@onready var atoms_container: Node3D = $Atoms
@onready var bonds_container: Node3D = $Bonds
@onready var wyckoff_container: Node3D = $WyckoffMarkers
@onready var fog_container: Node3D = $FogVolumes
@onready var grid_floor: MeshInstance3D = $GridFloor
@onready var _performance_label: Label = $PerformanceCanvasLayer/PerformanceLabel
@onready var _performance_timer: Timer = $PerformanceTimer

# CA 模式专用
var _ca_engine: CellularAutomatonEngine = null
var _ca_renderer: CAGridRenderer = null
var _ca_container: Node3D = null


var _i18n = null


func _ready() -> void:
	add_to_group("construction_canvas")
	_i18n = Engine.get_main_loop().root.get_node_or_null("/root/I18nManager")

	_init_managers()
	_connect_autoload_signals()
	_setup_grid_floor()
	_setup_fill_light()
	_try_load_hdri()
	_camera_ctrl.update_transform()

	# 连接性能统计HUD更新
	if _performance_timer != null:
		_performance_timer.timeout.connect(_update_performance_hud)

	# P4: 拖放导入支持（如果平台支持）
	if get_tree().root.has_signal("files_dropped"):
		get_tree().root.files_dropped.connect(_on_drop_files)
		GameLogger.info("Construction", "[构造] 拖放导入已启用")

	if LevelManager.current_level_data.size() > 0:
		# 延迟到 _ready 完全结束后再加载关卡，避免节点树还在初始化时 add/remove_child 报错
		get_tree().create_timer(0.1).timeout.connect(func():
			if is_instance_valid(self) and is_inside_tree():
				_on_level_loaded(LevelManager.current_level_data)
		)
	else:
		_atom_mgr.spawn_wyckoff_markers()

	# G9: 沙盒模式初始化
	if GameState.current_mode == GameState.GameMode.SANDBOX:
		_init_sandbox_mode()

	# 实时辉光更新: 每0.3秒刷新原子辉光，反映守恒矩阵变化
	var glow_timer := Timer.new()
	glow_timer.name = "GlowUpdateTimer"
	glow_timer.wait_time = 0.3
	glow_timer.autostart = true
	glow_timer.timeout.connect(_update_atom_glows)
	call_deferred("add_child", glow_timer)


func _process(delta: float) -> void:
	# ===== Besiege模式: 运行阶段物理模拟 =====
	_process_simulation(delta)
	# ===== 相变系统温度更新 =====
	if _phase_system != null:
		_phase_system.process(delta)


func _exit_tree() -> void:
	if ConservationEngine != null and ConservationEngine.state_changed.is_connected(_on_conservation_state_changed):
		ConservationEngine.state_changed.disconnect(_on_conservation_state_changed)
	if ConservationEngine != null and ConservationEngine.disintegration_triggered.is_connected(_on_disintegration_triggered):
		ConservationEngine.disintegration_triggered.disconnect(_on_disintegration_triggered)
	if FogSystem != null and FogSystem.fog_created.is_connected(_on_fog_created):
		FogSystem.fog_created.disconnect(_on_fog_created)
	if ProofTree != null and ProofTree.node_added.is_connected(_on_proof_node_added):
		ProofTree.node_added.disconnect(_on_proof_node_added)
	if LevelManager != null and LevelManager.level_loaded.is_connected(_on_level_loaded):
		LevelManager.level_loaded.disconnect(_on_level_loaded)
	# _performance_timer is a scene node, freed automatically; just disconnect signal
	if _performance_timer != null and _performance_timer.timeout.is_connected(_update_performance_hud):
		_performance_timer.timeout.disconnect(_update_performance_hud)
	if ConservationEngine != null and ConservationEngine.atmosphere_update.is_connected(_on_atmosphere_update):
		ConservationEngine.atmosphere_update.disconnect(_on_atmosphere_update)
	if get_tree().root.has_signal("files_dropped") and get_tree().root.files_dropped.is_connected(_on_drop_files):
		get_tree().root.files_dropped.disconnect(_on_drop_files)
	# headless模式下RendererDummy不会自动释放3D资源，手动清理
	_cleanup_3d_resources()


func _cleanup_3d_resources() -> void:
	# headless模式下显式释放3D节点，让引用计数自然归零
	# 不手动调用 unreference()——那会导致共享资源提前释放
	for child in get_children():
		if child is MeshInstance3D:
			child.queue_free()
		elif child is Node3D:
			for sub in child.get_children():
				if sub is MeshInstance3D:
					sub.queue_free()


func _update_atom_glows() -> void:
	if _effect_mgr and _atom_mgr:
		_effect_mgr.update_all_atom_glows(_atom_mgr.get_atoms())


func set_tool(tool_index: int) -> void:
	if tool_index < 0 or tool_index >= Tool.size():
		push_warning("[构造] 无效的工具索引: %d" % tool_index)
		return
	# 检查关卡约束是否禁用该工具
	var tool_name: String = _tool_enum_to_name(tool_index)
	if LevelManager != null and LevelManager.is_tool_forbidden(tool_name):
		GameLogger.info("Construction", "[构造] 工具被关卡约束禁用: %s" % tool_name)
		# 给玩家明确反馈：工具被禁用
		if _float_text != null:
			_float_text.show_float_text(
				camera.global_position + Vector3(0, -1, 0),
				"该工具在本关被禁用",
				Color(1.0, 0.4, 0.3),
				2.0
			)
		return
	current_tool = tool_index as Tool
	tool_changed.emit(tool_index)
	GameLogger.info("Construction", "[构造] 工具切换为: %s" % Tool.keys()[tool_index])

	# ===== 工具组合技追踪 =====
	if _tool_combo:
		_tool_combo.on_tool_used(Tool.keys()[tool_index], Vector3.ZERO)


func _parse_lattice_params(level_data: Dictionary) -> Vector3:
	# Multiple schemas in the level JSONs:
	#   A: lattice_parameters: {x, y, z}
	#   B: lattice_parameters: {a, b, c, alpha, beta, gamma}
	#   C: lattice_params: {a, b, c, alpha, beta, gamma}
	#   D: lattice: {a, b, c, alpha, beta, gamma}
	for key in ["lattice_parameters", "lattice_params", "lattice"]:
		if not level_data.has(key):
			continue
		var entry = level_data[key]
		if entry is Vector3:
			return entry
		if entry is Dictionary:
			# Try {a, b, c} first (crystallographic notation)
			if entry.has("a"):
				return Vector3(float(entry.get("a", 5.0)), float(entry.get("b", 5.0)), float(entry.get("c", 5.0)))
			# Fall back to {x, y, z}
			return Vector3(float(entry.get("x", 5.0)), float(entry.get("y", 5.0)), float(entry.get("z", 5.0)))
	return Vector3(5.0, 5.0, 5.0)


func _parse_lattice_angles(level_data: Dictionary) -> Vector3:
	# Angles can live inside lattice_params, lattice_parameters, lattice_angles, or lattice
	for key in ["lattice_angles", "lattice_parameters", "lattice_params", "lattice"]:
		if not level_data.has(key):
			continue
		var entry = level_data[key]
		if entry is Vector3:
			return entry
		if entry is Dictionary and entry.has("alpha"):
			return Vector3(
				float(entry.get("alpha", 90.0)),
				float(entry.get("beta", 90.0)),
				float(entry.get("gamma", 90.0)))
	return Vector3(90.0, 90.0, 90.0)


func _count_required_markers(level_data: Dictionary) -> int:
	# How many placement positions does this level need?
	# Check element count first, then goal requirements.
	var elements: Array = level_data.get("elements", [])
	if not elements.is_empty():
		var total: int = 0
		for elem in elements:
			# Handle all multiplicity field names: count, multiplicity, wyckoff_multiplicity
			var mult: int = int(elem.get("count", elem.get("multiplicity", elem.get("wyckoff_multiplicity", 1))))
			total += mult
		return maxi(total, elements.size())

	# No elements — check goals for placement requirements
	for g in level_data.get("goals", []):
		if g.get("type") == "wyckoff_fill":
			return int(g.get("required_count", g.get("count", 1)))
		if g.get("type") in ["bond_build", "bond_check", "element_count", "mesh_build", "path_build"]:
			return 3  # need at least a few markers

	# Default: at least 3 markers so the player has something to click
	return 3


func _parse_space_group_number(level_data: Dictionary) -> int:
	# Handle three JSON schema formats for space group:
	# 1. space_group_number: 225 (int, preferred)
	# 2. space_group: {symbol: "P1", number: 1} (object)
	# 3. space_group: "P1 (#1)" (string with number in parens)
	if level_data.has("space_group_number") and level_data["space_group_number"] is int:
		return level_data["space_group_number"]
	if level_data.has("space_group"):
		var sg = level_data["space_group"]
		if sg is Dictionary:
			if sg.has("number") and sg["number"] is int:
				return sg["number"]
			if sg.has("symbol"):
				return _space_group_symbol_to_number(str(sg["symbol"]))
		elif sg is String:
			# Extract number from patterns like "P1 (#1)" or "Fm-3m (225)"
			var regex = RegEx.new()
			regex.compile(r"#(\d+)")
			var m = regex.search(sg)
			if m:
				return int(m.get_string(1))
			return _space_group_symbol_to_number(sg)
	# Fallback: try to extract from goals that reference space groups
	for goal in level_data.get("goals", []):
		if goal.has("source_sg"):
			return int(goal["source_sg"])
	return 1


func _space_group_symbol_to_number(symbol: String) -> int:
	# Common space group symbols -> numbers
	var clean = symbol.strip_edges().split("(")[0].strip_edges()
	var lookup = {
		"P1": 1, "P-1": 2,
		"P2": 3, "P21": 4, "C2": 5,
		"Pm": 6, "Pc": 7, "Cm": 8, "Cc": 9,
		"P2/m": 10, "P21/m": 11, "C2/m": 12,
		"P222": 16, "P212121": 19,
		"Pmm2": 25, "Pmc21": 26,
		"Pmmm": 47, "Pnnn": 48,
		"P4": 75, "P41": 76, "P42": 77,
		"P4/m": 83, "P422": 89, "P4mm": 99, "P4/nmm": 129,
		"I4/mmm": 139, "I4cm": 140,
		"P3": 143, "P3m1": 156, "P-31m": 162,
		"P6/mmm": 191,
		"Pm-3m": 221, "Pn-3m": 224, "Fm-3m": 225, "Fd-3m": 227, "Im-3m": 229,
	}
	return lookup.get(clean, 1)


func _spawn_fallback_markers(level_data: Dictionary, sg_num: int, lattice_params: Vector3 = Vector3(5.0, 5.0, 5.0)) -> void:
	# When a level has insufficient Wyckoff markers (P1, unknown domain, etc.),
	# generate placement markers from the level's element position data.
	# Three element schemas exist in the JSON files:
	#   A: {symbol, position: {x,y,z}}     — fractional coords
	#   B: {symbol, x, y, z, count}        — fractional coords + multiplicity
	#   C: {label, x, y, z, count}         — same but "label" instead of "symbol"
	var elements: Array = level_data.get("elements", [])
	var goals: Array = level_data.get("goals", [])
	var positions: Array = []

	# 1) Try element data first — exact positions the player needs
	for elem in elements:
		var sym: String = ""
		if elem.has("symbol"):
			sym = str(elem["symbol"])
		elif elem.has("label"):
			sym = str(elem["label"])
		else:
			sym = "X"

		# Use element symbol as marker label — guarantees unique mapping
		# even when multiple elements share the same Wyckoff position
		var wyckoff: String = sym

		var frac: Vector3 = Vector3.ZERO
		var has_pos: bool = false

		# Schema A: position: {x, y, z}
		if elem.has("position") and elem["position"] is Dictionary:
			var p = elem["position"]
			frac = Vector3(float(p.get("x", 0)), float(p.get("y", 0)), float(p.get("z", 0)))
			has_pos = true
		# Schema B/C: x, y, z at top level
		elif elem.has("x") and elem.has("y") and elem.has("z"):
			frac = Vector3(float(elem["x"]), float(elem["y"]), float(elem["z"]))
			has_pos = true
		# Schema A variant: position: [x, y, z] (array)
		elif elem.has("position") and elem["position"] is Array and elem["position"].size() >= 3:
			var p = elem["position"]
			frac = Vector3(float(p[0]), float(p[1]), float(p[2]))
			has_pos = true
		# Schema D: position is a Godot Vector3 (from level_data.gd)
		elif elem.has("position") and elem["position"] is Vector3:
			frac = elem["position"]
			has_pos = true

		if has_pos:
			var count: int = int(elem.get("count", elem.get("multiplicity", elem.get("wyckoff_multiplicity", 1))))
			if count <= 1:
				positions.append({"wyckoff": wyckoff, "frac": frac})
			else:
				# Spread multiple markers in a small cluster around the base position
				for i in range(count):
					var angle: float = (i * 137.5) * 0.0174533
					var offset: Vector3 = Vector3(cos(angle) * 0.08, 0, sin(angle) * 0.08)
					positions.append({"wyckoff": wyckoff, "frac": frac + offset})

	# 2) If elements had no position data, try wyckoff_fill goals
	if positions.is_empty():
		for goal in goals:
			if goal.get("type") == "wyckoff_fill":
				var count: int = int(goal.get("required_count", goal.get("count", 1)))
				var wyckoff_label: String = goal.get("wyckoff", goal.get("label", "a"))
				var goal_elem: String = goal.get("element", "")
				for i in range(count):
					var angle: float = (i * 137.5) * 0.0174533
					var radius: float = 0.2 + (i / 8) * 0.15
					positions.append({
						"wyckoff": wyckoff_label,
						"frac": Vector3(0.5 + cos(angle) * radius, 0.5, 0.5 + sin(angle) * radius)
					})

	# 3) Last resort: default 3x3 grid in fractional space
	if positions.is_empty():
		for ix in range(3):
			for iz in range(3):
				positions.append({
					"wyckoff": "a",
					"frac": Vector3(float(ix) / 3.0 + 0.167, 0.5, float(iz) / 3.0 + 0.167)
				})

	# Clear and free existing markers before spawning new ones
	if _atom_mgr:
		_atom_mgr.clear_wyckoff_markers()

	# P1 (sg=1) has no symmetry ops — fractional_to_cartesian is just (x*a, y*b, z*c)
	# The crystal_cell's fractional_to_cartesian is broken for P1 (returns sum*a on x-axis),
	# so we bypass it and multiply directly.
	var spawned: int = 0
	for entry in positions:
		var frac: Vector3 = entry["frac"]
		var cart_pos: Vector3 = Vector3(
			frac.x * lattice_params.x,
			frac.y * lattice_params.y,
			frac.z * lattice_params.z
		)

		var marker = _atom_mgr.spawn_free_marker(cart_pos, entry["wyckoff"], entry["frac"])
		if marker:
			marker.add_to_group("fallback_marker")
			spawned += 1

	GameLogger.info("Construction", "[构造] 生成了 %d 个放置标记 (来自元素数据, sg=%d)" % [spawned, sg_num])

	# Rebuild element-wyckoff map to match symbol-based labels
	# so place_atom_at_marker can correctly auto-select elements
	if _atom_mgr and elements.size() > 0:
		_atom_mgr._element_wyckoff_map.clear()
		for elem in elements:
			var s: String = ""
			if elem.has("symbol"):
				s = str(elem["symbol"])
			elif elem.has("label"):
				s = str(elem["label"])
			else:
				s = "X"
			if s != "":
				# place_atom_at_marker normalizes the marker label (strips digits),
				# so "O1"→"O". We need both raw and normalized keys to handle
				# element symbols that contain digits (e.g. O1, O2, Li1)
				_atom_mgr._element_wyckoff_map[s] = s
				var _norm = _atom_mgr._normalize_wyckoff_label(s)
				if _norm != s:
					_atom_mgr._element_wyckoff_map[_norm] = s


func _tool_enum_to_name(tool_idx: int) -> String:
	# 将 Tool 枚举映射到 JSON 中的工具名字符串，供 forbidden_tools 约束检查
	match tool_idx:
		Tool.PLACE: return "element_block"
		Tool.BOND_BUILD: return "bond_tool"
		Tool.ASSEMBLE: return "assembly"
		Tool.PATH_BUILD: return "path_builder"
		Tool.CELLULAR_STEP: return "cellular_step"
		Tool.TUNE_MATRIX: return "tune_matrix"
		Tool.SUBSTITUTE: return "substitute"
		Tool.SOFT_MODE: return "soft_mode"
		Tool.INTERCALATE: return "intercalate"
		Tool.DELETE: return "delete"
		Tool.DETONATE: return "detonate"
		_: return ""


func _get_current_element_symbol() -> String:
	# 获取当前选中元素的符号，给放置引导系统用
	if _atom_mgr != null and _atom_mgr.has_method("get_current_element_symbol"):
		return _atom_mgr.get_current_element_symbol()
	if current_element_index >= 0 and current_element_index < QUICK_ELEMENTS.size():
		return QUICK_ELEMENTS[current_element_index]
	return "H"


func _init_managers() -> void:
	_camera_ctrl = load("res://scripts/construction/camera_controller.gd").new(camera)
	_atom_mgr = load("res://scripts/construction/atom_placement_manager.gd").new(
		atoms_container, bonds_container, wyckoff_container, crystal_cell)
	_atom_mgr.set_callbacks(_on_atom_clicked, _on_atom_state_changed, _on_atom_placed)
	_atom_mgr.atom_substituted.connect(_on_atom_substituted)
	_atom_mgr.load_element_data()
	_atom_mgr.camera = camera
	_domain_mgr = load("res://scripts/construction/domain_manager.gd").new(_atom_mgr, crystal_cell)
	_effect_mgr = load("res://scripts/construction/effect_manager.gd").new(fog_container, self)
	var ps_script := load("res://scripts/effects/particle_system.gd")
	_particle_system = ps_script.new()
	call_deferred("add_child", _particle_system)

	# 拆分出的子管理器
	var UndoRedoManagerScript = load("res://scripts/construction/undo_redo_manager.gd")
	_undo_redo_mgr = UndoRedoManagerScript.new(_atom_mgr)
	_undo_redo_mgr.on_stack_changed = _on_undo_redo_stack_changed

	var VerificationAnimatorScript = load("res://scripts/construction/verification_animator.gd")
	_verification_animator = VerificationAnimatorScript.new(self)

	var SandboxManagerScript = load("res://scripts/construction/sandbox_manager.gd")
	_sandbox_mgr = SandboxManagerScript.new(self, _atom_mgr, _camera_ctrl)

	# ===== 初始化游戏性增强系统 =====
	_float_text = FloatingTextSystem.new(self)
	_combo_sys = ComboSystem.new(self, _float_text)
	_diagnostic = DiagnosticHighlighter.new(self, _atom_mgr, _float_text)
	_predictive = PredictiveVerifier.new(self)
	_affinity = ElementAffinity.new(_float_text)
	_tool_combo = ToolComboSystem.new(self, _float_text)
	_dyn_difficulty = DynamicDifficulty.new(LevelManager)
	# ===== 初始化核心玩法机制 =====
	_reaction_engine = ChemicalReactionEngine.new(self, _atom_mgr, _float_text)
	_phase_system = PhaseTransitionSystem.new(self, _float_text)
	_weave_system = SymmetryWeavingSys.new(self, _atom_mgr, _float_text)
	_defect_mgr = DefectMgrSys.new(self, _atom_mgr, _float_text)
	_spin_system = SpinOrderingSys.new(self, _atom_mgr, _float_text)
	_strain_field = StrainFieldSys.new(self, _atom_mgr, _float_text)
	_thermo_sys = ThermoStabilitySys.new(self, _atom_mgr, _float_text)
	_phonon_sys = PhononSpectrumSys.new(self, _atom_mgr, _float_text)
	_catalyst_net = CatalystNetworkSys.new(self, _atom_mgr, _float_text)
	_tunneling_sys = QuantumTunnelingSys.new(self, _atom_mgr, _float_text)
	_resonance_sys = ResonanceCascadeSys.new(self, _atom_mgr, _float_text)
	_guide_sys = PlacementGuideSys.new(self, _atom_mgr, _float_text)
	_guide_sys.set_subsystems(_catalyst_net, _tunneling_sys, _strain_field)
	_context_hint = ContextualHintSys.new()
	add_child(_context_hint)
	_context_hint.setup(self, _atom_mgr, camera)
	_resonance_sys.set_phonon_system(_phonon_sys)
	# 相变→磁序联动：温度超临界点时熔化磁序
	if _phase_system != null and _spin_system != null:
		_phase_system.temperature_changed.connect(
			func(temp: float, _phase: String) -> void:
				if _spin_system != null:
					_spin_system.on_temperature_changed(temp)
				if _thermo_sys != null:
					_thermo_sys.on_temperature_changed(temp)
				if _catalyst_net != null:
					_catalyst_net.set_temperature(temp)
		)
	# Strain critical → 搭建阶段只警告，运行阶段由 _process_simulation 处理弹出
	if _strain_field != null:
		_strain_field.strain_critical.connect(
			func(atom: Node3D, mag: float) -> void:
				if _build_phase:
					# 搭建阶段：红色警告，不弹出
					if _float_text != null:
						_float_text.show_float_text(atom.global_position + Vector3(0, 0.5, 0), "⚠ 应变高", Color(1.0, 0.6, 0.2), 1.5)
				else:
					# 运行阶段：弹出（双保险，_process_simulation 也会检查）
					if GameLogger != null:
						GameLogger.info("Strain", "[应变] 原子 %s 超临界: %.2f → 弹射" % [atom.get_instance_id(), mag])
					_eject_atom(atom, mag)
		)
	# 隧穿事件日志
	if _tunneling_sys != null:
		_tunneling_sys.exotic_compound_formed.connect(
			func(formula: String, bonus: int) -> void:
				if GameLogger != null:
					GameLogger.info("Quantum", "[隧穿] 奇特化合物 %s 形成, +%d核心" % [formula, bonus])
		)
		_tunneling_sys.tunneling_catastrophe.connect(
			func(atom: Node3D, reason: String) -> void:
				if GameLogger != null:
					GameLogger.info("Quantum", "[隧穿] 灾难: %s" % reason)
		)
	# 共振级联日志
	if _resonance_sys != null:
		_resonance_sys.cascade_triggered.connect(
			func(level: int, bonus: float) -> void:
				if GameLogger != null:
					GameLogger.info("Resonance", "[共振] 级联 x%d, 奖励 %.1f" % [level, bonus])
		)
	# 放置引导: 最优位置提示
	if _guide_sys != null:
		_guide_sys.optimal_placement_found.connect(
			func(pos: Vector3, reason: String, score: float) -> void:
				if _float_text != null and score > 0.5:
					_float_text.show_float_text(
						pos + Vector3(0, 0.5, 0),
						"★ %s (%.0f%%)" % [reason, score * 100.0],
						Color(0.3, 1.0, 0.5),
						2.0
					)
		)
		_guide_sys.danger_placement_warned.connect(
			func(pos: Vector3, reason: String) -> void:
				if _float_text != null:
					_float_text.show_float_text(
						pos + Vector3(0, 0.5, 0),
						"⚠ %s" % reason,
						Color(1.0, 0.3, 0.3),
						2.5
					)
		)


func _update_performance_hud() -> void:
	if _performance_label == null:
		return
	var fps := Engine.get_frames_per_second()
	var atom_count := 0
	var bond_count := 0
	if _atom_mgr != null:
		atom_count = _atom_mgr.get_atoms().size()
		var bonds = _atom_mgr.get("_bonds")
		bond_count = bonds.size() if bonds else 0
	var draw_calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var line1 := "FPS: %.1f | Atoms: %d | Bonds: %d | DC: %d" % [fps, atom_count, bond_count, draw_calls]
	# 能量遥测 — MolGame 风格实时反馈
	if _thermo_sys != null:
		var info = _thermo_sys.get_info()
		var stab = _thermo_sys.get_stability_label()
		line1 += "\nH: %.1f  S: %.4f  G: %.1f eV  T: %.0fK  %s" % [
			info.get("enthalpy", 0.0), info.get("entropy", 0.0),
			info.get("gibbs", 0.0), info.get("temperature", 300.0), stab]
	_performance_label.text = line1


func _on_undo_redo_stack_changed(undo_count: int, redo_count: int) -> void:
	# 可在HUD上显示撤销/重做步数, 当前仅打印日志
	pass


func _setup_grid_floor() -> void:
	if not grid_floor:
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2(20.0, 20.0)
	plane.subdivide_width = 20
	plane.subdivide_depth = 20

	var floor_mat := StandardMaterial3D.new()
	floor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_mat.albedo_color = Color(0.45, 0.35, 0.22, 0.35)
	floor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plane.surface_set_material(0, floor_mat)

	grid_floor.mesh = plane


func _setup_fill_light() -> void:
	# 暖色补光
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.6, 0.45, 0.3)
	fill.light_energy = 0.5
	fill.omni_range = 25.0
	fill.position = Vector3(-5.0, 6.0, -5.0)
	fill.name = "FillLight"
	call_deferred("add_child", fill)

	# 冷色边缘光（轻微对比）
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.3, 0.4, 0.55)
	rim.light_energy = 0.25
	rim.omni_range = 20.0
	rim.position = Vector3(8.0, 3.0, -8.0)
	rim.name = "RimLight"
	call_deferred("add_child", rim)


func _connect_autoload_signals() -> void:
	ConservationEngine.state_changed.connect(_on_conservation_state_changed)
	ConservationEngine.disintegration_triggered.connect(_on_disintegration_triggered)
	ConservationEngine.atmosphere_update.connect(_on_atmosphere_update)
	FogSystem.fog_created.connect(_on_fog_created)
	ProofTree.node_added.connect(_on_proof_node_added)
	LevelManager.level_loaded.connect(_on_level_loaded)


# ============ 自由放置 + 晶格吸附 ============

# Grid snap step: atoms snap to 0.5-unit grid points.
# This gives players discrete position choices (like a board game)
# instead of requiring pixel-perfect 3D mouse aiming.
const GRID_SNAP: float = 0.5

# Ghost preview atom (shown on hover)
var _ghost_preview: MeshInstance3D = null
var _ghost_label: Label3D = null

# Snap a world position to the nearest grid point on y=0 plane
func _snap_to_grid(pos: Vector3) -> Vector3:
	return Vector3(
		round(pos.x / GRID_SNAP) * GRID_SNAP,
		0.0,
		round(pos.z / GRID_SNAP) * GRID_SNAP
	)

# Ray-cast from screen to y=0 plane, snap to grid, place atom.
# The snap makes execution easy (pick a grid cell) while preserving
# decision depth (which cell to pick matters for strain/bonds).
func _try_free_place(screen_pos: Vector2) -> void:
	if _atom_mgr == null:
		return
	var tool: int = _atom_mgr.current_tool
	if tool != 0 and tool != 6:  # PLACE or ASSEMBLE
		return
	# Skip in test mode — E2E test uses markers directly
	if _atom_mgr._auto_select_element:
		return

	var world_pos := _screen_to_floor(screen_pos)
	if world_pos == Vector3.INF:
		return

	# Snap to grid — discrete position choice, not pixel precision
	world_pos = _snap_to_grid(world_pos)

	# Check minimum distance to existing atoms (friendly, not punishing)
	var min_dist: float = 0.45
	var nearest_atom: Node3D = null
	var nearest_dist: float = 999.0
	for atom in _atom_mgr.get_atoms():
		if not is_instance_valid(atom):
			continue
		var d: float = world_pos.distance_to(atom.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest_atom = atom
		if d < min_dist:
			# Too close — show friendly hint, not harsh punishment
			if _float_text != null:
				_float_text.show_float_text(world_pos + Vector3(0, 0.5, 0),
					"间距不足", Color(1, 0.6, 0.2), 1.0)
			SoundManager.play(SoundManager.SoundType.VERIFICATION_FAIL)
			return

	# Place the atom at the snapped position
	_atom_mgr.place_atom_free(world_pos)

# Convert screen coordinates to world position on the y=0 floor plane
func _screen_to_floor(screen_pos: Vector2) -> Vector3:
	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
	if absf(ray_dir.y) < 0.001:
		return Vector3.INF
	var t: float = -ray_origin.y / ray_dir.y
	if t < 0:
		return Vector3.INF
	var world_pos: Vector3 = ray_origin + ray_dir * t

	# Constrain to crystal cell bounds
	var cell_radius: float = 5.0
	if crystal_cell and crystal_cell.has_method("get_lattice_params"):
		var lp: Dictionary = crystal_cell.get_lattice_params()
		cell_radius = maxf(float(lp.get("a", 5.0)), float(lp.get("b", 5.0))) * 0.5
	world_pos.x = clampf(world_pos.x, -cell_radius, cell_radius)
	world_pos.z = clampf(world_pos.z, -cell_radius, cell_radius)
	return world_pos

# Update ghost preview on mouse move

# 从关卡数据提取晶格参数向量
func _get_lattice_vector_from_data(level_data: Dictionary) -> Vector3:
	var lp = level_data.get("lattice_params", level_data.get("lattice_parameters", {}))
	if lp is Dictionary:
		return Vector3(
			float(lp.get("a", float(lp.get("x", 5.0)))),
			float(lp.get("b", float(lp.get("y", 5.0)))),
			float(lp.get("c", float(lp.get("z", 5.0))))
		)
	return Vector3(5.0, 5.0, 5.0)

# Update ghost preview on mouse move (original)
func _update_ghost_preview(screen_pos: Vector2) -> void:
	if _atom_mgr == null or _atom_mgr._auto_select_element:
		_hide_ghost_preview()
		return
	var tool: int = _atom_mgr.current_tool
	if tool != 0 and tool != 6:
		_hide_ghost_preview()
		return

	var world_pos := _screen_to_floor(screen_pos)
	if world_pos == Vector3.INF:
		_hide_ghost_preview()
		return

	world_pos = _snap_to_grid(world_pos)

	# Check if too close to existing atom
	var too_close: bool = false
	var strain_safe: bool = true
	for atom in _atom_mgr.get_atoms():
		if not is_instance_valid(atom):
			continue
		if world_pos.distance_to(atom.global_position) < 0.45:
			too_close = true
			break

	# Show/update ghost
	if _ghost_preview == null:
		_ghost_preview = MeshInstance3D.new()
		_ghost_preview.mesh = SphereMesh.new()
		_ghost_preview.mesh.radius = 0.2
		_ghost_preview.mesh.height = 0.4
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_preview.material_override = mat
		add_child(_ghost_preview)

	# Color: green=safe, yellow=close, red=too close
	var ghost_color: Color
	if too_close:
		ghost_color = Color(1, 0.2, 0.2, 0.4)
	elif not strain_safe:
		ghost_color = Color(1, 0.8, 0.2, 0.4)
	else:
		ghost_color = Color(0.3, 1, 0.4, 0.4)

	var mat2 := _ghost_preview.material_override as StandardMaterial3D
	if mat2:
		mat2.albedo_color = ghost_color
	_ghost_preview.global_position = world_pos
	_ghost_preview.visible = true

func _hide_ghost_preview() -> void:
	if _ghost_preview:
		_ghost_preview.visible = false

func _input(event: InputEvent) -> void:
	if _verification_animator and _verification_animator.is_animating():
		return

	# Ghost preview on mouse move
	if event is InputEventMouseMotion:
		_update_ghost_preview(event.position)

	# ESC弹出暂停确认弹窗
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_show_pause_dialog()
		get_viewport().set_input_as_handled()
		return

	# G9: 沙盒模式右键菜单（必须在相机 handle_input 之前检查）
	if GameState.current_mode == GameState.GameMode.SANDBOX:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if _sandbox_mgr:
				_sandbox_mgr.show_context_menu()
				get_viewport().set_input_as_handled()
				_camera_ctrl.stop_orbit()
				return

	# 相机旋转用右键
	_camera_ctrl.handle_input(event)

	# 左键拖拽检测：只在拖拽时旋转，单击交给marker/atom的input_event
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_left_drag_start = event.position
			_left_dragging = false
		else:
			if not _left_dragging:
				# Click (not drag) on empty space → free-place atom at mouse position
				_try_free_place(event.position)
			if _left_dragging:
				_camera_ctrl.stop_orbit(true)
			_left_dragging = false

	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var dist: float = event.position.distance_to(_left_drag_start)
		if dist > DRAG_THRESHOLD:
			if not _left_dragging:
				_left_dragging = true
				# 开始拖拽时通知相机接管
				_camera_ctrl.start_orbit(event.position, true)

	# 拖拽中更新相机
	if event is InputEventMouseMotion and _left_dragging:
		_camera_ctrl.update_orbit(event.position)

	if event is InputEventKey and event.pressed:
		var key_code: int = event.keycode
		if key_code >= KEY_1 and key_code <= KEY_9 and not event.ctrl_pressed:
			var idx: int = key_code - KEY_1
			var elem_data: Dictionary = _atom_mgr.get_element_data()
			if idx < elem_data.size():
				current_element_index = idx
				_atom_mgr.current_element_index = idx
				GameLogger.info("Construction", "[构造] 选择元素: %s" % elem_data[idx]["symbol"])
				get_viewport().set_input_as_handled()

		if event.ctrl_pressed and key_code == KEY_Z:
			if event.shift_pressed:
				_undo_redo_mgr.redo()
			else:
				_undo_redo_mgr.undo()
			# ===== 动态难度: 撤销追踪 =====
			if _dyn_difficulty != null:
				_dyn_difficulty.on_undo()
			if _combo_sys != null:
				_combo_sys.on_atom_placed(null, 1.0, 0.0)  # 撤销打断连击
			get_viewport().set_input_as_handled()
		elif event.ctrl_pressed and key_code == KEY_Y:
			_undo_redo_mgr.redo()
			get_viewport().set_input_as_handled()

		if key_code == KEY_P:
			set_tool(Tool.PLACE)
			get_viewport().set_input_as_handled()
		elif key_code == KEY_S and not event.ctrl_pressed:
			set_tool(Tool.SUBSTITUTE)
			get_viewport().set_input_as_handled()
		elif key_code == KEY_D and not event.ctrl_pressed:
			set_tool(Tool.DELETE)
			get_viewport().set_input_as_handled()
		elif key_code == KEY_SPACE:
			# CA 模式: 空格键切换自动演化 / 单步演化
			if _current_construction_mode == "cellular_automaton" and _ca_renderer:
				var running := _ca_renderer.toggle_auto_evolve()
				GameLogger.info("Construction", "[构造] CA 自动演化: " + ("开启" if running else "暂停"))
				get_viewport().set_input_as_handled()
		elif key_code == KEY_N:
			# CA 模式: N 键单步演化
			if _current_construction_mode == "cellular_automaton" and _ca_renderer:
				_ca_renderer.evolve_step()
				get_viewport().set_input_as_handled()
		elif key_code == KEY_T and not event.ctrl_pressed:
			# T键: 触发测试结构 (键盘快捷键，等价于点击"测试结构"按钮)
			LevelManager.test_structure()
			get_viewport().set_input_as_handled()
		if key_code == KEY_BRACKETLEFT:
			_camera_ctrl.cycle_scale(-1)
			get_viewport().set_input_as_handled()
		elif key_code == KEY_BRACKETRIGHT:
			_camera_ctrl.cycle_scale(1)
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _verification_animator and _verification_animator.is_animating():
		return
	if event.is_action_pressed("ask_physics"):
		_ask_physics()
	# V 键切换视角预设
	if event is InputEventKey and event.pressed and event.keycode == KEY_V:
		_camera_ctrl.cycle_view_preset()


# ============ 暂停弹窗 ============

func _show_pause_dialog() -> void:
	if _pause_dialog == null:
		_pause_dialog = ConfirmationDialog.new()
		_pause_dialog.title = _i18n.translate("hud.pause_title") if _i18n != null else "Paused"
		_pause_dialog.dialog_text = _i18n.translate("hud.pause_confirm") if _i18n != null else "Return to main menu? Unsaved progress will be lost."
		_pause_dialog.ok_button_text = _i18n.translate("hud.pause_ok") if _i18n != null else "Return to Menu"
		_pause_dialog.cancel_button_text = _i18n.translate("hud.pause_cancel") if _i18n != null else "Continue Game"
		# 确保弹窗在 3D 场景之上渲染
		var layer := CanvasLayer.new()
		layer.name = "PauseDialogLayer"
		layer.layer = 100
		add_child(layer)
		layer.add_child(_pause_dialog)
		_pause_dialog.confirmed.connect(_on_pause_confirmed)
	_pause_dialog.popup_centered()


func _on_pause_confirmed() -> void:
	UiAnimator.fade_change_scene("res://scenes/main_menu.tscn")


# ============ 原子事件 ============

func _on_atom_clicked(atom: Node) -> void:
	match current_tool:
		Tool.SUBSTITUTE:
			_atom_mgr.substitute_atom(atom)
		Tool.DELETE:
			# 先通知各子系统移除源，原子尚有效
			if atom is Node3D:
				if _strain_field != null:
					_strain_field.on_atom_removed(atom as Node3D)
				if _phonon_sys != null:
					_phonon_sys.on_atom_removed(atom as Node3D)
				if _catalyst_net != null:
					_catalyst_net.unregister_catalyst(atom as Node3D)
			var deleted_info: Dictionary = _atom_mgr.delete_atom(atom)
			if not deleted_info.is_empty():
				_undo_redo_mgr.push({
					"type": "delete_atom",
					"atom_data": deleted_info,
				})
		Tool.BOND_BUILD:
			# 成键工具: 选中两个原子后自动成键
			_try_manual_bond(atom)
		_:
			_atom_mgr.select_atom(atom)


func _try_manual_bond(atom: Node) -> void:
	# 如果还没有选中原子，选中当前点击的
	if _atom_mgr.selected_atom == null or not is_instance_valid(_atom_mgr.selected_atom):
		_atom_mgr.select_atom(atom)
		if _float_text != null and atom is Node3D:
			_float_text.show_float_text(
				atom.global_position + Vector3(0, 0.8, 0),
				"选中: %s → 点击另一个原子成键" % str(atom.get("element_symbol")),
				Color(0.5, 0.8, 1.0),
				2.0
			)
		return
	
	# 如果点击的是同一个原子，取消选中
	if _atom_mgr.selected_atom == atom:
		atom.call("set_state", 0)  # IDLE
		_atom_mgr.selected_atom = null
		return
	
	# 选中了第二个原子 → 尝试成键
	var atom_a: Node3D = _atom_mgr.selected_atom
	var atom_b: Node3D = atom as Node3D
	
	# 检查是否已有键
	for bond in _atom_mgr._bonds:
		if not is_instance_valid(bond):
			continue
		var ba: Node3D = bond.atom_a
		var bb: Node3D = bond.atom_b
		if (ba == atom_a and bb == atom_b) or (ba == atom_b and bb == atom_a):
			# 已有键 → 断键
			bond.bond_broken.emit(bond)
			_atom_mgr._bonds.erase(bond)
			bond.queue_free()
			if _float_text != null:
				_float_text.show_float_text(
					(atom_a.global_position + atom_b.global_position) / 2.0 + Vector3(0, 0.5, 0),
					"键已断开",
					Color(1.0, 0.4, 0.3),
					1.5
				)
			atom_a.call("set_state", 0)
			_atom_mgr.selected_atom = null
			return
	
	# 创建新键
	var bond_node: Node3D = _atom_mgr._create_bond(atom_a, atom_b, 0)
	if bond_node != null:
		if _float_text != null:
			var mid: Vector3 = (atom_a.global_position + atom_b.global_position) / 2.0
			_float_text.show_float_text(
				mid + Vector3(0, 0.5, 0),
				"%s-%s 键已形成" % [str(atom_a.get("element_symbol")), str(atom_b.get("element_symbol"))],
				Color(0.3, 1.0, 0.5),
				2.0
			)
		# 撤销栈
		_undo_redo_mgr.push({
			"type": "create_bond",
			"atom_a": atom_a,
			"atom_b": atom_b,
		})
	
	# 清除选中状态
	atom_a.call("set_state", 0)
	_atom_mgr.selected_atom = null


func _on_atom_state_changed(_atom: Node, _new_state: int) -> void:
	pass


var _last_goal_states: Array = []


func _check_goal_progress_feedback(pos: Vector3) -> void:
	# Show floating text when a goal transitions to IN_PROGRESS or COMPLETED
	if LevelManager == null or LevelManager.goals.is_empty():
		return
	# Ensure tracking array is right size
	while _last_goal_states.size() < LevelManager.goals.size():
		_last_goal_states.append(LevelManager.GoalState.PENDING)

	for i in range(LevelManager.goals.size()):
		var current_state: int = LevelManager.goal_states[i] if i < LevelManager.goal_states.size() else 0
		var prev_state: int = _last_goal_states[i]

		if current_state != prev_state:
			var goal: Dictionary = LevelManager.goals[i]
			var goal_type: String = goal.get("type", "")
			var goal_desc: String = goal.get("description", goal_type)

			if current_state == LevelManager.GoalState.COMPLETED:
				if _float_text != null:
					_float_text.show_float_text(
						pos + Vector3(0, 1.0, 0),
						"目标完成: %s" % goal_desc,
						Color(0.3, 1.0, 0.4),
						2.0
					)
			elif current_state == LevelManager.GoalState.IN_PROGRESS and prev_state == LevelManager.GoalState.PENDING:
				if _float_text != null:
					_float_text.show_float_text(
						pos + Vector3(0, 0.8, 0),
						"进行中: %s" % goal_desc,
						Color(1.0, 0.85, 0.3),
						1.5
					)

			_last_goal_states[i] = current_state


func _on_atom_placed(atom: Node) -> void:
	if _undo_redo_mgr and _undo_redo_mgr.is_applying():
		return
	_undo_redo_mgr.push({
		"type": "place_atom",
		"atom_ref": atom,
	})

	# ===== 游戏性增强反馈 =====
	if atom != null and atom is Node3D:
		var atom3d: Node3D = atom as Node3D
		var pos: Vector3 = atom3d.global_position
		var elem_data: Dictionary = _atom_mgr.get_element_data()
		var symbol: String = ""
		if _atom_mgr.current_element_index in elem_data:
			symbol = elem_data[_atom_mgr.current_element_index].get("symbol", "")

		# 0. Goal progress feedback — let player know what they achieved
		_check_goal_progress_feedback(pos)

		# 1. 浮字: 守恒变化
		if _float_text != null:
			var dev_summary: Dictionary = ConservationEngine.get_deviation_summary()
			for key in dev_summary:
				var dev: float = dev_summary[key].get("deviation", 0.0)
				if dev > 0.001:
					_float_text.show_float_text(
						pos + Vector3(randf() * 0.4 - 0.2, 0.3, randf() * 0.4 - 0.2),
						"%s: %.3f" % [key, dev],
						Color(0.8, 0.8, 0.8) if dev < 0.1 else Color(1.0, 0.6, 0.2),
						0.8
					)

		# 2-14. Advanced physics subsystems (all chapters now)
		# Strain field + conservation are the core gameplay, not decoration
		if true:
			# 2. 元素亲和度
			if _affinity != null and symbol != "":
				_affinity.on_atom_placed(atom3d, symbol)

			# 3. 连击系统
			if _combo_sys != null:
				var dev_summary2: Dictionary = ConservationEngine.get_deviation_summary()
				var max_dev: float = 0.0
				for key in dev_summary2:
					max_dev = maxf(max_dev, dev_summary2[key].get("deviation", 0.0))
				_combo_sys.on_atom_placed(atom3d, max_dev, max_dev)

			# 4. 动态难度
			if _dyn_difficulty != null:
				_dyn_difficulty.on_atom_placed()

			# 5. 化学反应引擎
			if _reaction_engine != null and atom3d != null:
				_reaction_engine.on_atom_placed(atom3d)

			# 6. 相变系统: 放置原子释放热量
			if _phase_system != null:
				_phase_system.add_heat(5.0)

			# 7. 更新预判验证
			if _predictive != null:
				_predictive.update_prediction()

			# 8. 磁序系统: 磁性原子自动分配自旋
			if _spin_system != null and atom3d != null:
				_spin_system.on_atom_placed(atom3d)

			# 9. 应变场系统: 注册应变源
			if _strain_field != null and atom3d != null:
				_strain_field.on_atom_placed(atom3d)

			# 10. 热力学稳定性: 重新计算Gibbs自由能
			if _thermo_sys != null:
				var atom_count: int = _atom_mgr.get_atoms().size()
				var bond_count: int = _atom_mgr._bonds.size()
				var defect_count: int = 0
				if _defect_mgr != null:
					defect_count = _defect_mgr.get_defect_count()
				var strain_info: Dictionary = {}
				if _strain_field != null:
					strain_info = _strain_field.get_strain_info()
				_thermo_sys.recalculate(atom_count, bond_count, defect_count, strain_info)
			# 接通死代码：热力学稳定性修正瓦解阈值
			ConservationEngine.stability_threshold_modifier = _thermo_sys.get_disintegration_threshold_modifier()

			# 11. 声子谱系统: 注册振动源 + 软模检测
			if _phonon_sys != null and atom3d != null:
				_phonon_sys.on_atom_placed(atom3d)
				if _strain_field != null and _defect_mgr != null:
					var s_info: Dictionary = _strain_field.get_strain_info()
					_phonon_sys.check_phonon_softening(s_info, _defect_mgr.get_defect_count())

			# 12. 催化剂网络: 检测催化剂原子
			if _catalyst_net != null and atom3d != null:
				_catalyst_net.register_catalyst(atom3d)
				_catalyst_net.try_reaction_chain(atom3d.global_position)

			# 13. 量子隧穿: 检测近距离放置
			if _tunneling_sys != null and atom3d != null:
				var nearby: Array = _tunneling_sys._get_nearby_atoms(atom3d, 1.5)
				if nearby.size() > 0:
					_tunneling_sys.check_tunneling_on_placement(atom3d, nearby)

			# 14. 放置引导: 刷新建议
			if _guide_sys != null and atom3d != null:
				_guide_sys.generate_suggestions(atom3d.global_position, _get_current_element_symbol())

		# 15. 应变松弛: 让原子受应变场驱动微调位置
		if _strain_field != null and atom3d != null:
			atom3d.set_strain_field(_strain_field, _atom_mgr)

	# 16. 路径+能量图可视化刷新
	_update_path_visualization()
	_update_energy_diagram()


func _on_atom_substituted(atom: Node3D, old_element_index: int, new_element_index: int) -> void:
	if _undo_redo_mgr and _undo_redo_mgr.is_applying():
		return
	_undo_redo_mgr.push({
		"type": "substitute_atom",
		"atom_ref": atom,
		"old_element_index": old_element_index,
		"new_element_index": new_element_index,
	})


# ============ 守恒/效果事件 ============

func _on_conservation_state_changed(old_state: int, new_state: int) -> void:
	match new_state:
		1:
			SoundManager.play(SoundManager.SoundType.CONSERVATION_WARN)
		2:
			# CRITICAL: 相机微震，让玩家"感觉"结构在颤抖
			SoundManager.play(SoundManager.SoundType.DISINTEGRATE_START)
			_trigger_camera_shake(0.15, 0.08)
		3:
			# DISINTEGRATED: 更强的相机震动
			SoundManager.play(SoundManager.SoundType.DISINTEGRATE_START)
			_trigger_camera_shake(0.3, 0.15)
	_effect_mgr.update_all_atom_glows(_atom_mgr.get_atoms())


func _trigger_camera_shake(duration: float, intensity: float) -> void:
	# 守恒偏离时相机微震，模拟结构不稳定
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	# 减少闪烁模式下跳过相机震动
	if UiAnimator != null and UiAnimator.is_flashing_reduced():
		return
	# 优先走 camera_shake 的 h/v_offset 抖动，直接改 position 会和相机控制器打架
	if camera.has_method("shake"):
		camera.shake(intensity, duration)
		return
	var orig_pos := camera.position
	var shake_tween := create_tween()
	for i in range(int(duration / 0.03)):
		var offset := Vector3(
			randf_range(-intensity, intensity),
			randf_range(-intensity, intensity),
			randf_range(-intensity * 0.3, intensity * 0.3)
		)
		shake_tween.tween_property(camera, "position", orig_pos + offset, 0.03)
	shake_tween.tween_property(camera, "position", orig_pos, 0.05)


func _on_atmosphere_update(state: int) -> void:
	if _particle_system:
		_particle_system.update_atmosphere(state)


# Eject an atom due to strain overload — the core failure risk
# This makes placement order and spacing matter: too close → strain builds → atom flies out
func _eject_atom(atom: Node3D, mag: float) -> void:
	if atom == null or not is_instance_valid(atom):
		return
	# Prevent double-ejection during tween animation
	if atom.has_meta("_ejecting"):
		return
	atom.set_meta("_ejecting", true)
	# Skip ejection in E2E test mode during build phase
	# During simulation (_sim_running) ejection is allowed even in test mode
	if _atom_mgr and _atom_mgr._auto_select_element and not _sim_running:
		return
	# Visual: atom flies upward and fades out
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	var start_pos := atom.global_position
	var eject_dir := Vector3(randf_range(-0.3, 0.3), 1.0, randf_range(-0.3, 0.3)).normalized()
	tween.tween_property(atom, "global_position", start_pos + eject_dir * 3.0, 0.8)
	tween.parallel().tween_property(atom, "scale", Vector3.ZERO, 0.8)
	# Fade material alpha
	if atom is MeshInstance3D:
		var mat = atom.get_active_material(0)
		if mat is StandardMaterial3D:
			var smat: StandardMaterial3D = mat
			var orig_a: float = smat.albedo_color.a
			tween.parallel().tween_method(
				func(a: float): smat.albedo_color = Color(smat.albedo_color.r, smat.albedo_color.g, smat.albedo_color.b, a),
				orig_a, 0.0, 0.8
			)
	# Sound
	if SoundManager.has_method("play_sfx"):
		SoundManager.play_sfx("atom_eject", 1.5)
	# Camera shake — bigger strain = bigger shake
	if camera and camera.has_method("shake"):
		camera.call("shake", 0.1 + mag * 0.05, 0.3)
	# Float text
	if _float_text != null:
		_float_text.show_float_text(start_pos + Vector3(0, 0.5, 0), "弹射! %.1f" % mag, Color(1, 0.2, 0.2), 2.0)
	# Remove after animation
	tween.tween_callback(func():
		if is_instance_valid(atom):
			_atom_mgr.delete_atom(atom)
	)


func _on_disintegration_triggered(reason: String) -> void:
	# 螺旋磁护盾：免疫一次瓦解
	if _spin_system != null and _spin_system.consume_helical_immunity():
		GameLogger.info("Construction", "[构造] 螺旋磁护盾激活，免疫瓦解: %s" % reason)
		return
	
	GameLogger.info("Construction", "[构造] 瓦解触发: %s" % reason)
	SoundManager.play(SoundManager.SoundType.DISINTEGRATE_FULL)
	_effect_mgr.start_disintegration_cascade(_atom_mgr.get_atoms())
	# 延迟3秒触发关卡失败，让玩家看清瓦解动画
	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(self) and is_inside_tree():
			LevelManager.level_failed.emit("守恒矩阵瓦解: %s" % reason)
	)


func _on_fog_created(region_id: int, fog_type: int) -> void:
	_effect_mgr.create_fog_volume(region_id, fog_type)


func _on_proof_node_added(_node: RefCounted) -> void:
	pass


# ============ 验证 ============

func _ask_physics() -> void:
	if _verification_animator and _verification_animator.is_animating() or not is_instance_valid(self) or not self.is_inside_tree():
		return
	var vp := get_node("/root/VerificationPipeline")

	var result_l1: Dictionary = await vp.verify(
		0,  # LAYER_SYMBOLIC
		"structure_integrity",
		{"atoms": _atom_mgr.get_atoms().size()}
	)
	if not is_instance_valid(self) or not self.is_inside_tree():
		return

	var l1_passed: bool = result_l1.get("success", false)
	if _verification_animator:
		_verification_animator.play(0, l1_passed)

	var result_l2: Dictionary = await vp.verify(
		1,  # LAYER_TYPE_SYSTEM
		"type_consistency",
		{"structure": "current"}
	)
	if not is_instance_valid(self) or not self.is_inside_tree():
		return

	var l2_passed: bool = result_l2.get("success", false)
	if _verification_animator:
		_verification_animator.play(1, l2_passed)

	var quick_ok := l1_passed and l2_passed
	var confidence: float = minf(
		float(result_l1.get("confidence", 0.0)),
		float(result_l2.get("confidence", 0.0))
	)

	if not quick_ok:
		GameLogger.debug("General", "[验证] L1-L2发现问题, 置信度: %.1f%%" % (confidence * 100.0))
		if _dyn_difficulty != null:
			_dyn_difficulty.on_verify(true, false)
		if _diagnostic != null:
			_diagnostic.trigger_diagnostic("mass", 0.1)
		return

	# L1-L2通过，标记基础验证完成
	GameLogger.debug("General", "[验证] L1-L2通过, 置信度: %.1f%%" % (confidence * 100.0))
	LevelManager.mark_verification_done(1)

	# 继续L3-L5验证（消耗核心，L4有LLM回退，L5有Z3/守恒矩阵回退）
	var layer_statements: Array[String] = [
		"logic_consistency",
		"semantic_coherence",
		"conservation_law",
	]
	var _cores_spent_this_session: int = 0
	for layer in range(_LAYER_LOGIC, _LAYER_FORMAL + 1):
		if not is_instance_valid(self) or not self.is_inside_tree():
			# 场景切换中断验证，退还本次已消耗的核心
			if _cores_spent_this_session > 0:
				GameState.gain_cores(_cores_spent_this_session)
				GameLogger.debug("General", "[验证] 场景切换，退还%d核心" % _cores_spent_this_session)
			return
		# 核心不足时直接停下，不启动验证
		var cost: int = _CORE_COSTS[layer]
		if cost > 0 and GameState.verification_cores < cost:
			SoundManager.play(SoundManager.SoundType.VERIFICATION_FAIL)
			GameLogger.debug("General", "[验证] 核心不足，停在L%d" % (layer + 1))
			break
		var ctx: Dictionary = {}
		if layer == _LAYER_FORMAL:
			ctx["matrix"] = _flatten_conservation_matrix()
		var result: Dictionary = await vp.verify(layer, layer_statements[layer - 2], ctx)
		if cost > 0:
			_cores_spent_this_session += cost
		if not is_instance_valid(self) or not self.is_inside_tree():
			# 场景切换中断验证，退还本次已消耗的核心
			if _cores_spent_this_session > 0:
				GameState.gain_cores(_cores_spent_this_session)
				GameLogger.debug("General", "[验证] 场景切换，退还%d核心" % _cores_spent_this_session)
			return
		var passed: bool = result.get("success", false)
		if _verification_animator:
			_verification_animator.play(layer, passed)
		if not passed:
			GameLogger.debug("General", "[验证] L%d发现问题: %s" % [layer + 1, result.get("reason", "")])
			if _dyn_difficulty != null:
				_dyn_difficulty.on_verify(true, false)
			if _diagnostic != null:
				_diagnostic.trigger_diagnostic("mass", 0.1)
			break
		LevelManager.mark_verification_done(layer)
		GameLogger.debug("General", "[验证] L%d通过" % (layer + 1))
	
	# 验证全部通过
	if _dyn_difficulty != null:
		_dyn_difficulty.on_verify(true, true)
	if _predictive != null:
		_predictive.hide_prediction()


func _flatten_conservation_matrix() -> Array:
	# 把4x4守恒矩阵展平成16元素数组，供L5形式化验证用
	var flat: Array = []
	var mat: Array = ConservationEngine.matrix
	for i in range(4):
		for j in range(4):
			flat.append(float(mat[i][j]))
	return flat


# ============ 关卡集成 ============

func _on_level_loaded(level_data: Dictionary) -> void:
	# 新关卡清空操作历史
	_chapter = level_data.get("chapter", 1)
	_build_phase = true
	_sim_running = false
	_sim_settled = false
	current_element_index = 0
	_collapse_history.clear()
	if _undo_redo_mgr:
		_undo_redo_mgr.clear()
	_last_goal_states.clear()
	FogSystem.reset()

	# Clean up any leftover CA state from the previous level
	_cleanup_ca()

	# ===== 重置游戏性增强系统 =====
	if _combo_sys:
		_combo_sys.on_level_reset()
	if _tool_combo:
		_tool_combo.on_level_reset()
	if _diagnostic:
		_diagnostic.clear_diagnostic()
	if _affinity:
		_affinity.setup_for_level(level_data)
	if _dyn_difficulty:
		_dyn_difficulty.on_level_start()
	if _predictive:
		_predictive.hide_prediction()
	# ===== 重置核心玩法机制 =====
	if _reaction_engine:
		_reaction_engine.on_level_reset()
	if _phase_system:
		_phase_system.setup_for_level(level_data)
	if _weave_system:
		_weave_system.on_level_reset()
	if _defect_mgr:
		_defect_mgr.setup_for_level(level_data)
	if _spin_system:
		_spin_system.on_level_reset()
	if _strain_field:
		_strain_field.on_level_reset()
	if _thermo_sys:
		_thermo_sys.on_level_reset()
	if _phonon_sys:
		_phonon_sys.on_level_reset()
	if _catalyst_net:
		_catalyst_net.on_level_reset()
	if _tunneling_sys:
		_tunneling_sys.on_level_reset()
	if _resonance_sys:
		_resonance_sys.on_level_reset()
	if _guide_sys:
		_guide_sys.on_level_reset()

	# Parse space group number — handle multiple JSON schema formats
	var sg_num: int = _parse_space_group_number(level_data)
	var lattice_params: Vector3 = _parse_lattice_params(level_data)
	var lattice_angles: Vector3 = _parse_lattice_angles(level_data)
	_current_domain = level_data.get("domain", "crystal")
	_current_construction_mode = level_data.get("construction_mode", "wyckoff_fill")

	_atom_mgr.clear_structure()
	_effect_mgr.clear_fog()
	_atom_mgr.set_domain(_current_domain, _current_construction_mode)
	# 传递关卡元素数据以计算归一化总质量，用于守恒矩阵扰动
	_atom_mgr.set_level_elements(level_data.get("elements", []))

	# CA 模式单独处理: 完全退出当前调用栈后再初始化,
	# 避免父节点被判定为 busy setting up children
	if _current_construction_mode == "cellular_automaton":
		call_deferred("_setup_cellular_automaton_mode", level_data)
		return

	# 非CA模式: 显示常规构造元素, 隐藏CA容器
	atoms_container.visible = true
	bonds_container.visible = true
	wyckoff_container.visible = true
	if _ca_container:
		_ca_container.visible = false
	if _ca_renderer:
		_ca_renderer.visible = false

	# 设置工具
	match _current_domain:
		"crystal", "fog":
			set_tool(Tool.PLACE)
		"molecular":
			set_tool(Tool.BOND_BUILD)
		"device":
			set_tool(Tool.ASSEMBLE)
		"reaction", "topology":
			set_tool(Tool.PATH_BUILD)
		"fluid":
			set_tool(Tool.PLACE)
		"thermodynamics", "electromagnetics", "multiphysics":
			set_tool(Tool.PLACE)
	match _current_construction_mode:
		"mesh_build", "path_build":
			set_tool(Tool.PATH_BUILD)

	_domain_mgr.setup_domain(_current_domain, sg_num, lattice_params, lattice_angles)

	# Check if we have enough markers for the level's element count.
	# P1 space group only generates 1 marker, but levels may need 5-6.
	var valid_markers: int = 0
	if _atom_mgr and _atom_mgr.get("_wyckoff_markers"):
		for m in _atom_mgr._wyckoff_markers:
			if m != null and is_instance_valid(m) and m.visible and not m.is_queued_for_deletion():
				valid_markers += 1

	# Count how many placement positions the level needs
	var required_markers: int = _count_required_markers(level_data)
	if valid_markers < required_markers:
		print("[Markers] have=%d need=%d mode=%s domain=%s sg=%d — generating from element data" % [
			valid_markers, required_markers, _current_construction_mode, _current_domain, sg_num])
		_spawn_fallback_markers(level_data, sg_num, lattice_params)

	var scale_label: String = level_data.get("scale_label", "Å")
	var scale_range: Vector2 = level_data.get("scale_range", Vector2(0.5, 10.0))
	_camera_ctrl.apply_level_scale(scale_label, scale_range)

	GameLogger.info("Construction", "[构造] 关卡已配置: 域=%s, 空间群#%d, 晶格参数(%s)" % [_current_domain, sg_num, str(lattice_params)])

	# 初始化粒子氛围系统
	if _particle_system:
		_particle_system.setup(_current_domain)

	# 初始化物理模拟器（所有模式共享，通过scene_config控制行为）
	_setup_structure_simulator(level_data)

	# 路径/组装/能量可视化
	_setup_path_visualization()
	_setup_region_markers(level_data)
	_setup_energy_diagram(level_data)


# ============ 路径可视化 ============

func _setup_path_visualization() -> void:
	# 清理旧的
	if _path_lines != null and is_instance_valid(_path_lines):
		_path_lines.queue_free()
	_path_lines = Node3D.new()
	_path_lines.name = "PathLines"
	add_child(_path_lines)
	_path_lines.visible = (_current_construction_mode == "path_build" or _current_domain == "reaction" or _current_domain == "topology")


func _update_path_visualization() -> void:
	if _path_lines == null or not is_instance_valid(_path_lines):
		return
	# 清理旧线段
	for child in _path_lines.get_children():
		child.queue_free()
	# 只在 path_build / reaction / topology 模式下显示
	if not (_current_construction_mode == "path_build" or _current_domain == "reaction" or _current_domain == "topology"):
		return
	var atoms = _atom_mgr.get_atoms()
	if atoms.size() < 2:
		return
	# 按放置顺序连接原子
	for i in range(atoms.size() - 1):
		var a = atoms[i]
		var b = atoms[i + 1]
		if not is_instance_valid(a) or not is_instance_valid(b):
			continue
		var line = _create_path_segment(a.global_position, b.global_position)
		_path_lines.add_child(line)


func _create_path_segment(start: Vector3, end: Vector3) -> MeshInstance3D:
	var mid := (start + end) * 0.5
	var dir := end - start
	var length := dir.length()
	if length < 0.01:
		length = 0.01
	var mesh := CylinderMesh.new()
	mesh.radius = 0.05
	mesh.height = length
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.global_position = mid
	# 对齐圆柱方向
	mi.look_at(end, Vector3.UP)
	mi.rotate_x(PI / 2.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.9, 1.0, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.9, 1.0, 0.4)
	mat.emission_energy_multiplier = 0.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	return mi


# ============ 组装区域可视化 ============

func _setup_region_markers(level_data: Dictionary) -> void:
	if _region_markers != null and is_instance_valid(_region_markers):
		_region_markers.queue_free()
	_region_markers = Node3D.new()
	_region_markers.name = "RegionMarkers"
	add_child(_region_markers)
	_region_markers.visible = (_current_construction_mode == "assembly" or _current_domain == "device")

	if not _region_markers.visible:
		return

	# 从关卡 elements 中提取元素符号作为区域标签
	var elements: Array = level_data.get("elements", [])
	if elements.is_empty():
		return

	# 为每种元素创建一个半透明色块
	var lattice: Vector3 = _get_lattice_vector_from_data(level_data)
	var colors := [Color(1.0, 0.3, 0.3, 0.15), Color(0.3, 1.0, 0.3, 0.15), Color(0.3, 0.3, 1.0, 0.15),
		Color(1.0, 1.0, 0.3, 0.15), Color(1.0, 0.3, 1.0, 0.15), Color(0.3, 1.0, 1.0, 0.15)]
	var i: int = 0
	for elem in elements:
		if not elem is Dictionary:
			continue
		var sym: String = elem.get("symbol", elem.get("label", ""))
		if sym == "":
			continue
		var pos_data = elem.get("position", {})
		var pos := Vector3.ZERO
		if pos_data is Dictionary:
			pos = Vector3(float(pos_data.get("x", 0.5)), float(pos_data.get("y", 0.5)), float(pos_data.get("z", 0.5))) * lattice
		elif pos_data is Array and pos_data.size() >= 3:
			pos = Vector3(float(pos_data[0]), float(pos_data[1]), float(pos_data[2])) * lattice
		var col: Color = colors[i % colors.size()]
		var box := _create_region_marker(pos, col, sym)
		_region_markers.add_child(box)
		i += 1


func _create_region_marker(pos: Vector3, color: Color, label_text: String) -> Node3D:
	var box := BoxMesh.new()
	box.size = Vector3(1.5, 1.5, 1.5)
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	# 加个标签
	var label := Label3D.new()
	label.text = label_text
	label.position = Vector3(0, 1.0, 0)
	label.font_size = 48
	label.modulate = Color(color.r + 0.5, color.g + 0.5, color.b + 0.5, 1.0)
	mi.add_child(label)
	return mi


# ============ 能量图 HUD ============

func _setup_energy_diagram(level_data: Dictionary) -> void:
	# 清理旧的
	if _energy_diagram != null and is_instance_valid(_energy_diagram):
		_energy_diagram.queue_free()
	# 只在有 reaction_path 目标时显示
	var has_reaction := false
	for g in level_data.get("goals", []):
		if g is Dictionary and g.get("type", "") == "reaction_path":
			has_reaction = true
			break
	if not has_reaction:
		_energy_diagram = null
		return

	_energy_diagram = Control.new()
	_energy_diagram.name = "EnergyDiagram"
	_energy_diagram.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_energy_diagram.offset_left = -260
	_energy_diagram.offset_top = -160
	_energy_diagram.offset_right = -10
	_energy_diagram.offset_bottom = -10
	# 找 CanvasLayer 挂载
	var canvas_layer = get_node_or_null("PerformanceCanvasLayer")
	if canvas_layer != null:
		canvas_layer.add_child(_energy_diagram)
	else:
		add_child(_energy_diagram)
	_energy_diagram.visible = true
	_update_energy_diagram()


func _update_energy_diagram() -> void:
	if _energy_diagram == null or not is_instance_valid(_energy_diagram):
		return
	for child in _energy_diagram.get_children():
		child.queue_free()

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.12, 0.85)
	sb.border_color = Color(0.3, 0.6, 0.9, 0.6)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 8
	sb.content_margin_top = 8
	sb.content_margin_right = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	_energy_diagram.add_child(panel)

	var title := Label.new()
	title.text = "反应路径"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	panel.add_child(title)

	# 显示已放置的路径节点
	var path_nodes: Array = LevelManager._path_nodes if LevelManager != null else []
	if path_nodes.is_empty():
		var hint := Label.new()
		hint.text = "放置原子构建反应路径"
		hint.position = Vector2(0, 24)
		hint.add_theme_font_size_override("font_size", 13)
		hint.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7))
		panel.add_child(hint)
		return

	# 每个节点显示元素符号 + 能量估计
	var y_off: int = 28
	for i in range(path_nodes.size()):
		var node: Dictionary = path_nodes[i]
		var elem: String = node.get("element", "?")
		var lbl := Label.new()
		var energy: float = 0.0
		if _thermo_sys != null:
			energy = _thermo_sys.get_gibbs_energy() / float(maxi(i + 1, 1))
		var arrow: String = " → " if i > 0 else ""
		lbl.text = "%s%s  [%.2f eV/atom]" % [arrow, elem, energy]
		lbl.position = Vector2(10 + i * 60, y_off)
		lbl.add_theme_font_size_override("font_size", 14)
		var col := Color(0.4, 0.9, 0.4) if energy < 0 else Color(0.9, 0.5, 0.3)
		lbl.add_theme_color_override("font_color", col)
		panel.add_child(lbl)
		y_off += 0  # 同一行，横向排列


# ============ Besiege模式: 运行模拟 ============

# 启动物理模拟 — 搭建结束，应变场接管
func start_simulation(mode: String = "strain", target_temp: float = 0.0) -> void:
	if _sim_running:
		return
	_build_phase = false
	_sim_running = true
	_sim_settled = false
	_sim_timer = 0.0
	_sim_mode = mode
	_sim_target_temp = target_temp
	var atoms = _atom_mgr.get_atoms()
	if GameLogger != null:
		GameLogger.info("Sim", "[模拟] 启动 mode=%s, 原子数=%d" % [mode, atoms.size()])
	if _float_text != null:
		var label: String = "▶ 运行模拟"
		match mode:
			"thermal":
				label = "▶ 升温模拟 → %dK" % int(target_temp)
			"magnetic":
				label = "▶ 磁有序检测"
			"catalyst":
				label = "▶ 催化反应运行"
			"resonance":
				label = "▶ 共振扫描"
		_float_text.show_float_text(Vector3(0, 2, 0), label, Color(0.3, 0.9, 1.0), 2.0)

# 停止模拟，回到搭建阶段
func stop_simulation() -> void:
	_sim_running = false
	_build_phase = true
	_sim_settled = false

# _process中调用：渐进式弛豫 + 模式特有物理
func _process_simulation(delta: float) -> void:
	if not _sim_running:
		return
	_sim_timer += delta
	_strain_field._cache_dirty = true
	var atoms = _atom_mgr.get_atoms()
	if atoms.is_empty():
		_sim_running = false
		_sim_settled = true
		return

	# --- 模式特有物理驱动 ---
	match _sim_mode:
		"thermal":
			# 逐步升温到目标温度，观察相变和结构稳定性
			if _phase_system != null and _sim_target_temp > 0.0:
				var current_t: float = _phase_system.get_temperature()
				var ramp: float = (_sim_target_temp - 300.0) / 3.0 * delta
				_phase_system.set_temperature(current_t + ramp)
				# 接近目标温度时停止升温
				if absf(_phase_system.get_temperature() - _sim_target_temp) < 5.0:
					_phase_system.set_temperature(_sim_target_temp)
		"magnetic":
			# 自旋系统在放置时已自动分类，这里触发温度变化看磁序是否熔化
			if _phase_system != null and _sim_target_temp > 0.0:
				var current_t: float = _phase_system.get_temperature()
				var ramp: float = (_sim_target_temp - 300.0) / 3.0 * delta
				_phase_system.set_temperature(current_t + ramp)
		"catalyst":
			# 催化剂在放置时已注册，这里触发反应链
			if _catalyst_net != null and _sim_timer < 2.0:
				for atom in atoms:
					if is_instance_valid(atom):
						_catalyst_net.try_reaction_chain(atom.global_position)
		"resonance":
			# 扫描频率范围，寻找共振峰
			if _resonance_sys != null and _sim_timer < 3.0:
				var scan_freq: float = 1e12 + _sim_timer * 5e12
				_resonance_sys.tune_frequency(scan_freq)

	# --- 共有：应变弛豫 + 弹出 ---
	# 大结构应变自然累积更高，15+原子时禁用弹出，只做弛豫
	# ponytail: 粗粒度切换，升级路径是k近邻应变+动态阈值
	var max_strain: float = 0.0
	var any_moved: bool = false
	var can_eject: bool = _sim_timer > 1.0 and atoms.size() < 15
	for atom in atoms:
		if not is_instance_valid(atom):
			continue
		var strain = _strain_field.get_atom_strain(atom)
		var mag: float = strain.get("magnitude", 0.0)
		max_strain = maxf(max_strain, mag)
		# 应变热力图：实时着色给玩家受力反馈
		if atom.has_method("set_strain_visual"):
			atom.set_strain_visual(mag)
		if can_eject and mag > _strain_field.STRAIN_THRESHOLD:
			_eject_atom(atom, mag)
			any_moved = true
			continue
		# 用弛豫力推动原子微调位置
		var force: Vector3 = _strain_field.compute_relaxation_force(atom, atoms)
		if force.length() > 0.0001:
			var old_pos: Vector3 = atom.global_position
			atom.global_position += force * delta * 500.0
			# 网格吸附到0.5单位
			atom.global_position.x = round(atom.global_position.x * 2.0) / 2.0
			atom.global_position.y = round(atom.global_position.y * 2.0) / 2.0
			atom.global_position.z = round(atom.global_position.z * 2.0) / 2.0
			# 只在实际移动时标记，避免微小力导致永远不收敛
			if atom.global_position != old_pos:
				any_moved = true

	# 收敛条件：2秒后且没有原子移动，或超过8秒强制收敛
	if _sim_timer > 2.0 and not any_moved or _sim_timer > 8.0:
		_sim_running = false
		_sim_settled = true
		# 收敛后重置原子颜色到基础色
		for atom in _atom_mgr.get_atoms():
			if is_instance_valid(atom) and atom.has_method("set_strain_visual"):
				atom.set_strain_visual(0.0)
		if GameLogger != null:
			GameLogger.info("Sim", "[模拟] 收敛 mode=%s, 最大应变=%.3f, 剩余原子=%d" % [_sim_mode, max_strain, _atom_mgr.get_atoms().size()])
		if _float_text != null:
			var atoms_left: int = _atom_mgr.get_atoms().size()
			if atoms_left > 0:
				_float_text.show_float_text(Vector3(0, 2, 0), "✓ 结构稳定", Color(0.3, 1.0, 0.4), 3.0)
			else:
				_float_text.show_float_text(Vector3(0, 2, 0), "✗ 结构瓦解", Color(1.0, 0.3, 0.3), 3.0)
		# 通知LevelManager检查目标
		LevelManager.on_simulation_settled()


func _setup_structure_simulator(level_data: Dictionary) -> void:
	# 根据scene_config配置物理模拟器
	# 所有现有模式都可以通过scene_config启用物理模拟的不同特性
	var scene_config: Dictionary = level_data.get("scene_config", {})

	# 清理旧模拟器
	if _structure_sim != null and is_instance_valid(_structure_sim):
		_structure_sim.stop_simulation()
		remove_child(_structure_sim)
		_structure_sim.queue_free()
		_structure_sim = null

	# 物理模拟默认启用，关卡可通过 simulation_disabled: true 关闭
	var sim_disabled: bool = scene_config.get("simulation_disabled", false)
	if sim_disabled:
		return

	_structure_sim = StructureSimulatorRef.new()
	_structure_sim.name = "StructureSimulator"
	add_child(_structure_sim)

	# 从scene_config读取模拟参数
	_structure_sim.temperature = float(scene_config.get("temperature", 0.0))
	_structure_sim.growth_rate = float(scene_config.get("growth_rate", 0.0))
	_structure_sim.simulation_speed = float(scene_config.get("simulation_speed", 1.0))
	_structure_sim.damping = float(scene_config.get("damping", 0.85))
	_structure_sim.bond_form_distance = float(scene_config.get("bond_form_distance", 2.0))
	_structure_sim.bond_break_distance = float(scene_config.get("bond_break_distance", 3.5))
	_structure_sim.auto_bond_formation = bool(scene_config.get("auto_bond_formation", false))

	# 连接信号
	_structure_sim.atom_auto_placed.connect(_on_sim_atom_auto_placed)
	_structure_sim.bond_auto_formed.connect(_on_sim_bond_auto_formed)
	_structure_sim.bond_auto_broken.connect(_on_sim_bond_auto_broken)
	_structure_sim.cascade_triggered.connect(_on_sim_cascade_triggered)

	# 如果有预置缺陷（物理诊断），延迟注入
	var defects: Array = scene_config.get("preplaced_defects", [])
	if not defects.is_empty():
		call_deferred("_inject_defects", defects)

	# 如果有生长位置，设置生长队列
	var growth_positions: Array = scene_config.get("growth_positions", [])
	if not growth_positions.is_empty():
		_structure_sim.set_growth_positions(growth_positions)

	_structure_sim.start_simulation()
	GameLogger.info("Construction", "[构造] 物理模拟器已启动: temp=%.2f, growth=%.2f" % [_structure_sim.temperature, _structure_sim.growth_rate])


func _on_sim_atom_auto_placed(ghost: Node3D) -> void:
	# 模拟器自动放置原子 → 通知AtomPlacementManager创建实际原子
	if not is_instance_valid(ghost):
		return
	var element: String = ghost.get_meta("element", "X")
	var pos: Vector3 = ghost.global_position
	ghost.queue_free()
	# 通过atom_mgr在指定位置放置原子
	if _atom_mgr:
		_atom_mgr.place_atom_at_position(element, pos)


func _on_sim_bond_auto_formed(a: Node3D, b: Node3D) -> void:
	# 模拟器自动成键 → 通知BondRenderer创建键
	if _atom_mgr:
		_atom_mgr.create_bond(a, b)


func _on_sim_bond_auto_broken(a: Node3D, b: Node3D) -> void:
	# 模拟器自动断键 → 通知BondRenderer移除键
	if _atom_mgr:
		_atom_mgr.break_bond_between(a, b)


func _on_sim_cascade_triggered(source: Node3D, affected: Array[Node3D]) -> void:
	# 连锁反应触发 → 视觉+音效反馈
	SoundManager.play(SoundManager.SoundType.DISINTEGRATE_START)
	GameLogger.info("Construction", "[构造] 连锁反应: %d个原子受影响" % affected.size())


func _inject_defects(defects: Array) -> void:
	# 注入预置缺陷（物理诊断关卡用）
	# 等待原子放置完成后再注入
	await get_tree().create_timer(0.5).timeout
	var atoms: Array[Node3D] = _atom_mgr.get_atoms()
	if _structure_sim and is_instance_valid(_structure_sim):
		_structure_sim.set_atoms(atoms)
		for defect in defects:
			var idx: int = int(defect.get("index", 0))
			if idx < atoms.size():
				_structure_sim.inject_defect(atoms[idx], defect.get("type", "displacement"))


# ============ 公共接口 ============

func get_current_element_info() -> Dictionary:
	var elem_data: Dictionary = _atom_mgr.get_element_data()
	if current_element_index in elem_data:
		return elem_data[current_element_index]
	return {}


func set_space_group(num: int) -> void:
	if crystal_cell:
		crystal_cell.call("set_space_group", num)
		_atom_mgr.spawn_wyckoff_markers()


func clear_structure() -> void:
	_atom_mgr.clear_structure()
	_effect_mgr.clear_fog()
	if _ca_engine:
		_ca_engine.clear()
		_ca_engine.load_pattern("random_medium")
		if _ca_renderer:
			_ca_renderer._update_visuals()


# Tear down all CA state so it doesn't leak into the next level
func _cleanup_ca() -> void:
	if _ca_renderer and is_instance_valid(_ca_renderer):
		if _ca_renderer.has_signal("cell_toggled") and _ca_renderer.cell_toggled.is_connected(_on_ca_cell_toggled):
			_ca_renderer.cell_toggled.disconnect(_on_ca_cell_toggled)
		_ca_renderer.queue_free()
	_ca_renderer = null
	if _ca_container and is_instance_valid(_ca_container):
		_ca_container.queue_free()
	_ca_container = null
	_ca_engine = null


func _setup_cellular_automaton_mode(level_data: Dictionary) -> void:
	# 隐藏常规构造元素
	atoms_container.visible = false
	bonds_container.visible = false
	wyckoff_container.visible = false

	# 解析 scene_config
	var cfg: Dictionary = level_data.get("scene_config", {})
	var grid_size: Array = cfg.get("grid_size", [8, 8, 8])
	var rule: String = cfg.get("ca_rule", "bays_4555")
	var initial: String = cfg.get("initial_pattern", "random_medium")
	var auto_interval: float = cfg.get("auto_evolve_interval", 0.4)

	# 创建引擎
	_ca_engine = CellularAutomatonEngine.new(grid_size[0], grid_size[1], grid_size[2])
	_ca_engine.set_rule_by_name(rule)
	_ca_engine.load_pattern(initial)

	# 创建渲染器: 先在节点外初始化网格
	var renderer_script := load("res://scripts/construction/ca_grid_renderer.gd")
	var new_renderer: Node = renderer_script.new()
	new_renderer.name = "CAGridRenderer"
	new_renderer.initialize(_ca_engine, 1.0)
	new_renderer.set_auto_evolve_interval(auto_interval)

	# 等当前函数完全退出后再挂到场景树, 避免父节点 busy
	get_tree().create_timer(0.0).timeout.connect(
		func() -> void:
			if not is_instance_valid(self):
				return
			# 清理旧的 CA 渲染器
			if _ca_renderer and is_instance_valid(_ca_renderer):
				_ca_renderer.queue_free()
			_ca_renderer = new_renderer

			# 创建/复用 CA 容器
			if _ca_container == null or not is_instance_valid(_ca_container):
				_ca_container = Node3D.new()
				_ca_container.name = "CAContainer"
				add_child(_ca_container)
			_ca_container.visible = true

			# 添加渲染器
			_ca_container.add_child(_ca_renderer)
			_ca_renderer.cell_toggled.connect(_on_ca_cell_toggled)
			_ca_renderer.engine.step_completed.connect(_on_ca_step_completed)
			_ca_renderer.engine.pattern_detected.connect(_on_ca_pattern_detected)

			# 设置默认工具为 CA 单步
			set_tool(Tool.CELLULAR_STEP)
			_camera_ctrl.update_transform()
			GameLogger.info("Construction", "[构造] CA 模式已初始化: %dx%dx%d, 规则=%s" % [grid_size[0], grid_size[1], grid_size[2], rule])
	)


func _on_ca_cell_toggled(_x: int, _y: int, _z: int, _alive: int) -> void:
	# 点击细胞也算一次操作
	LevelManager.move_count += 1


func _on_ca_step_completed(step: int, alive: int) -> void:
	if _ca_engine == null:
		return
	LevelManager.register_ca_step({
		"step": step,
		"alive": alive,
		"density": _ca_engine.get_density(),
		"phase": _ca_engine._phase_state,
		"pattern": "",
	})


func _on_ca_pattern_detected(pattern_type: String, details: Dictionary) -> void:
	if _ca_engine == null:
		return
	var stats := {
		"step": details.get("step", _ca_engine.get_step_count()),
		"alive": details.get("alive", _ca_engine.get_alive_count()),
		"density": _ca_engine.get_density(),
		"phase": _ca_engine._phase_state,
		"pattern": pattern_type,
	}
	LevelManager.register_ca_step(stats)


# ---- CA 育种系统 ----

func save_ca_seed(seed_name: String = "") -> String:
	# 保存当前CA状态为种子，返回种子文件路径
	if _ca_engine == null:
		push_warning("[CA] 无法保存种子：引擎未初始化")
		return ""
	if seed_name == "":
		seed_name = "seed_%d" % Time.get_ticks_msec()
	var cells: PackedByteArray = _ca_engine.get_cells()
	var data := {
		"name": seed_name,
		"rule": _ca_engine.birth_rules,
		"survival": _ca_engine.survival_rules,
		"size": [_ca_engine.size_x, _ca_engine.size_y, _ca_engine.size_z],
		"step": _ca_engine.get_step_count(),
		"cells": cells,
		"timestamp": Time.get_unix_time_from_system(),
	}
	var path: String = "user://ca_seeds/%s.json" % seed_name
	DirAccess.make_dir_recursive_absolute("user://ca_seeds/")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()
		GameLogger.info("ConstructionCanvas", "[CA育种] 种子已保存: %s (步数=%d, 存活=%d)" % [seed_name, _ca_engine.get_step_count(), _ca_engine.get_alive_count()])
	# 通知 LevelManager 计数，用于育种关卡目标
	LevelManager.register_ca_seed_save()
	return path


func load_ca_seed(seed_name: String) -> bool:
	# 从种子文件加载CA状态
	var path: String = "user://ca_seeds/%s.json" % seed_name
	if not FileAccess.file_exists(path):
		push_warning("[CA] 种子文件不存在: %s" % seed_name)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return false
	var raw: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(raw) != OK:
		return false
	var data: Dictionary = json.data
	if _ca_engine == null:
		return false
	# 恢复细胞状态（JSON 反序列化后 cells 是 base64 字符串，需要解码）
	var cells_raw: Variant = data.get("cells", PackedByteArray())
	var cells: PackedByteArray
	if cells_raw is PackedByteArray:
		cells = cells_raw
	elif cells_raw is String:
		cells = Marshalls.base64_to_raw(cells_raw)
	else:
		cells = PackedByteArray()
	_ca_engine.set_cells(cells)
	_ca_engine._step_count = int(data.get("step", 0))
	if _ca_renderer:
		_ca_renderer._update_visuals()
	GameLogger.info("ConstructionCanvas", "[CA育种] 种子已加载: %s" % seed_name)
	return true


func list_ca_seeds() -> Array[String]:
	# 列出所有已保存的种子
	var seeds: Array[String] = []
	var dir := DirAccess.open("user://ca_seeds/")
	if dir == null:
		return seeds
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			seeds.append(file_name.get_basename())
		file_name = dir.get_next()
	return seeds


func export_ca_seed(path: String) -> bool:
	# 导出种子到指定路径（用于分享）
	if _ca_engine == null:
		return false
	var cells: PackedByteArray = _ca_engine.get_cells()
	var data := {
		"rule": _ca_engine.birth_rules,
		"survival": _ca_engine.survival_rules,
		"size": [_ca_engine.size_x, _ca_engine.size_y, _ca_engine.size_z],
		"step": _ca_engine.get_step_count(),
		"cells": cells,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()
		return true
	return false


func import_ca_seed(path: String) -> bool:
	# 从指定路径导入种子
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return false
	var raw: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(raw) != OK:
		return false
	var data: Dictionary = json.data
	if _ca_engine == null:
		return false
	# 恢复细胞状态（JSON 反序列化后 cells 是 base64 字符串，需要解码）
	var cells_raw: Variant = data.get("cells", PackedByteArray())
	var cells: PackedByteArray
	if cells_raw is PackedByteArray:
		cells = cells_raw
	elif cells_raw is String:
		cells = Marshalls.base64_to_raw(cells_raw)
	else:
		cells = PackedByteArray()
	_ca_engine.set_cells(cells)
	_ca_engine._step_count = int(data.get("step", 0))
	if _ca_renderer:
		_ca_renderer._update_visuals()
	return true


func get_effect_manager() -> RefCounted:
	return _effect_mgr


# ===== 深层玩法系统公开API =====

func get_weave_system() -> RefCounted:
	return _weave_system

func get_defect_manager() -> RefCounted:
	return _defect_mgr

func get_spin_system() -> RefCounted:
	return _spin_system

func get_thermo_sys() -> RefCounted:
	return _thermo_sys

func get_phonon_sys() -> RefCounted:
	return _phonon_sys

func get_strain_field() -> RefCounted:
	return _strain_field


# 触发对称编织
func weave_symmetry(seed_atom: Node3D, op_id: String) -> Dictionary:
	if _weave_system != null and seed_atom != null:
		return _weave_system.weave(seed_atom, op_id)
	return {"success": false, "reason": "system_unavailable"}

# 创建缺陷
func create_defect(defect_type: String, atom_or_pos: Variant, element: String = "") -> Dictionary:
	if _defect_mgr == null:
		return {"success": false, "reason": "system_unavailable"}
	match defect_type:
		"vacancy":
			if atom_or_pos is Node3D:
				return _defect_mgr.create_vacancy(atom_or_pos)
		"interstitial":
			if atom_or_pos is Vector3:
				return _defect_mgr.create_interstitial(atom_or_pos, element)
		"substitutional":
			if atom_or_pos is Node3D:
				return _defect_mgr.create_substitution(atom_or_pos, element)
	return {"success": false, "reason": "invalid_args"}

# 设置原子自旋方向
func set_atom_spin(atom: Node3D, direction: Vector3) -> void:
	if _spin_system != null:
		_spin_system.set_spin(atom, direction)


# ---- 矩阵主动操控 ----

func tune_matrix_row(row: int, delta: float) -> bool:
	# 主动调谐守恒矩阵某一行
	# delta < 0: 降低该行偏离（更稳定），delta > 0: 增加偏离（换取其他收益）
	var success: bool = ConservationEngine.tune(row, delta)
	if success:
		SoundManager.play(SoundManager.SoundType.CORE_EARNED)
		GameLogger.info("ConstructionCanvas", "[调谐] 行=%d, delta=%.3f" % [row, delta])
	return success


# ---- 受控崩溃 ----

func detonate_atom(atom: Node3D) -> void:
	# 主动删除一个原子并观察连锁反应（教学/实验用）
	if atom == null or not is_instance_valid(atom):
		return
	var elem_symbol: String = atom.get_meta("element_symbol", "?")
	var pos: Vector3 = atom.global_position
	# 记录崩溃前的矩阵状态供侦探模式分析
	_record_pre_collapse_state()
	# 删除原子
	_atom_mgr.delete_atom(atom)
	# 触发视觉效果
	if _effect_mgr:
		_effect_mgr.spawn_explosion(pos)
	GameLogger.info("ConstructionCanvas", "[受控崩溃] 引爆 %s @ %s" % [elem_symbol, pos])


func _record_pre_collapse_state() -> void:
	# 记录当前矩阵状态和原子布局，供侦探模式回溯
	var snapshot := {
		"timestamp": Time.get_ticks_msec(),
		"matrix": ConservationEngine.matrix.duplicate(true),
		"state": ConservationEngine.get_state(),
		"atom_count": _count_atoms(),
	}
	_collapse_history.append(snapshot)
	if _collapse_history.size() > 20:
		_collapse_history.pop_front()


func get_collapse_history() -> Array:
	return _collapse_history


# ---- 结构图鉴接口 ----

func get_atoms_for_codex() -> Array:
	# 返回当前画布上的原子数组，供 StructureCodex 序列化
	if _atom_mgr == null:
		return []
	return _atom_mgr.get_atoms()


func get_bonds_for_codex() -> Array:
	# 返回当前画布上的键数组
	if _atom_mgr == null:
		return []
	if _atom_mgr.has_method("get_bonds"):
		return _atom_mgr.get_bonds()
	return []


func _count_atoms() -> int:
	if _atom_mgr == null:
		return 0
	return _atom_mgr.get_atoms().size()


func _check_level_goals() -> void:
	# 沙盒模式下跳过目标检查
	if GameState.current_mode == GameState.GameMode.SANDBOX:
		return
	LevelManager._check_goals()


# ============ G9: 沙盒模式 ============

func _init_sandbox_mode() -> void:
	# 应用沙盒配置到晶胞
	_domain_mgr.setup_domain(
		"crystal",
		GameState.sandbox_selected_space_group,
		GameState.sandbox_lattice_params,
		GameState.sandbox_lattice_angles
	)
	_atom_mgr.spawn_wyckoff_markers()

	# 构建沙盒UI
	if _sandbox_mgr:
		_sandbox_mgr.build_ui()



# ============ Drag & Drop Import (P4) ============

func _on_drop_files(files: PackedStringArray) -> void:
	var loader_script := load("res://scripts/autoload/level_data_loader.gd")
	for path in files:
		var ext := path.get_extension().to_lower()
		match ext:
			"json":
				var ld = loader_script.load_level_data_from_path(path)
				if ld != null:
					GameLogger.info("Construction", "[构造] 拖放导入关卡: %s" % path)
					_on_level_loaded(ld.to_json())
				else:
					push_warning("拖放导入关卡失败: %s" % path)
			"tres":
				var res = load(path)
				if res is ElementDataResource:
					GameLogger.info("Construction", "[构造] 拖放导入元素数据: %s" % path)
					_atom_mgr.load_element_data()
				else:
					push_warning("拖放导入元素数据失败: %s" % path)
			"png", "jpg", "jpeg", "hdr":
				GameLogger.info("Construction", "[构造] 拖放导入背景纹理: %s" % path)
				_try_load_hdri(path)
			_:
				push_warning("拖放导入不支持的文件类型: %s" % ext)


# ============ HDRI 环境加载 ============

func _try_load_hdri(custom_path: String = "") -> void:
	var world_env := get_node_or_null("WorldEnvironment")
	if not world_env:
		return
	var env: Environment = world_env.environment
	if not env:
		return
	var hdri_path := custom_path if custom_path != "" else "res://assets/third_party/polyhaven/studio_small_03_2k.hdr"
	if ResourceLoader.exists(hdri_path) and HDRILoader.load_hdri_into_environment(env, hdri_path):
		GameLogger.info("Construction", "[构造] HDRI 已加载: %s" % hdri_path)
	else:
		# HDRI 文件不存在时静默回退到 ProceduralSky，不打印警告
		pass
