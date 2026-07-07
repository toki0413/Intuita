extends Node
# 教程管理器 - 新手引导系统，逐步引导玩家了解游戏机制
# 进度保存到user://tutorial_save.dat
# 支持Ch1 Wyckoff基础教程 + Ch2-Ch3各构造模式的域教程

signal tutorial_step_changed(step_index: int)
signal tutorial_completed
signal tutorial_skipped
signal domain_tutorial_started(construction_mode: String)
signal domain_tutorial_completed(construction_mode: String)

# Ch1 Wyckoff填充基础教程步骤
const STEPS := [
	{
		"key": "welcome",
		"title": "欢迎来到 Intuita",
		"text": "这是你的3D构造台。在这里，你将像搭积木一样拼出真实的晶体结构——从食盐到金刚石，每一种材料都是你要解决的谜题。",
		"highlight": "",
	},
	{
		"key": "goals_panel",
		"title": "任务清单",
		"text": "顶部是任务清单，告诉你这关要做什么。○=还没开始 ◐=进行中 ●=完成了。跟着清单走就能通关。",
		"highlight": "ObjectivePanel",
	},
	{
		"key": "wyckoff",
		"title": "放置点",
		"text": "看到那些发光的蓝色球了吗？那是原子的'卡槽'——就像拼图上的凹槽，告诉你原子该放哪里。不同颜色的卡槽需要不同的元素。",
		"highlight": "ConstructionCanvas",
	},
	{
		"key": "place_atom",
		"title": "放置原子",
		"text": "从左侧工具栏选择一个元素（先试试 Na），然后点击蓝色卡槽。原子会'咔嗒'一声落位，旁边的卡槽也会自动填上对称的原子。",
		"highlight": "ToolPanel",
	},
	{
		"key": "conservation",
		"title": "平衡指示器",
		"text": "右上角的彩色面板是你的'平衡指示器'。绿色=结构稳定，黄色=有点歪，红色=快塌了。放原子时注意看它——就像搭积木时要保持重心!",
		"highlight": "ConservationHUD",
	},
	{
		"key": "test_structure",
		"title": "测试结构",
		"text": "放完所有原子后，点任务清单里的'测试结构'按钮。这就像搭完积木后推一下看会不会倒——通过测试就通关了!",
		"highlight": "ObjectivePanel",
	},
	{
		"key": "complete",
		"title": "继续建造",
		"text": "继续填满剩下的卡槽。食盐 (NaCl) 需要把 Na 放在一组卡槽、Cl 放在另一组。全部填完后平衡指示器应该变绿。",
		"highlight": "",
	},
	{
		"key": "ask_physics",
		"title": "验证时刻",
		"text": "点击'测试结构'验证你的作品。系统会检查结构是否物理合理。通过=通关！如果失败了，看看哪里不平衡，调整后重试。",
		"highlight": "",
	},
	{
		"key": "core_economy",
		"title": "核心",
		"text": "通关会获得'核心'，这是游戏内的货币。用来驱散迷雾、购买道具、解锁新能力。越漂亮的通关（步数少、偏差小）核心越多。",
		"highlight": "ConservationHUD",
	},
	{
		"key": "proof_done",
		"title": "完成了！",
		"text": "恭喜！你刚刚建造了一个真实的晶体结构。从原子到晶体，每一步都有物理意义——这就是材料科学的乐趣。",
		"highlight": "",
	},
]

# Ch2-Ch3 各构造模式的域教程
const DOMAIN_TUTORIALS: Dictionary = {
	"wyckoff_fill": [
		{"id": "wf_1", "text": "放置模式", "description": "发光的蓝色球是'卡槽'，告诉你原子该放哪里。点击卡槽就能放原子。", "highlight": "ConstructionCanvas", "action": "enter_wyckoff_mode"},
		{"id": "wf_2", "text": "选择元素", "description": "从左侧工具栏选一个元素，然后点击卡槽。不确定选什么？看看卡槽上的提示文字。", "highlight": "ToolPanel", "action": "select_element"},
		{"id": "wf_3", "text": "对称展开", "description": "放一个原子后，对称位置会自动填上相同的原子。就像镜像一样——放一个，得到一整组。", "highlight": "ConservationHUD", "action": "atom_placed"},
		{"id": "wf_4", "text": "平衡指示器", "description": "右上角面板显示结构是否稳定。绿色=安全，黄色=注意，红色=危险。保持绿色!", "highlight": "ConservationHUD", "action": "check_conservation"},
		{"id": "wf_5", "text": "验证结构", "description": "填完所有卡槽后，点'测试结构'按钮验证。通过验证就通关!", "highlight": "ObjectivePanel", "action": "test_structure"},
	],
	"bond_build": [
		# 模式切换引导：从wyckoff_fill进入分子构建，先讲清两种模式的区别
		{"id": "bb_switch_1", "text": "模式切换：分子构建", "description": "现在切换到分子构建模式。你不再填充晶格位置，而是自由放置原子。", "highlight": "ToolPanel", "action": "enter_bond_mode"},
		{"id": "bb_switch_2", "text": "放置自由原子", "description": "选择 atom_placer 工具，点击空白处放置原子。这里没有Wyckoff标记约束你。", "highlight": "ToolPanel", "action": "atom_placed"},
		{"id": "bb_switch_3", "text": "创建化学键", "description": "选择 bond_rotator 工具，依次点击两个原子即可在它们之间创建化学键。", "highlight": "ToolPanel", "action": "bond_created"},
		{"id": "bb_1", "text": "Bond Building Mode", "description": "In this mode, you connect atoms with chemical bonds. Select two atoms to form a bond between them.", "highlight": "ToolPanel", "action": "enter_bond_mode"},
		{"id": "bb_2", "text": "Select First Atom", "description": "Click on the first atom you want to bond. It will glow to show it's selected.", "highlight": "ConstructionCanvas", "action": "select_atom"},
		{"id": "bb_3", "text": "Select Second Atom", "description": "Now click the second atom. A bond will form between them if the valence rules allow it.", "highlight": "ConstructionCanvas", "action": "select_second_atom"},
		{"id": "bb_4", "text": "Bond Created!", "description": "The bond appears as a cylinder between atoms. Check the conservation matrix — bonding may affect it.", "highlight": "ConservationHUD", "action": "bond_created"},
		{"id": "bb_5", "text": "Complete the Structure", "description": "Continue bonding atoms until all required bonds are formed. Watch the goals panel for progress.", "highlight": "GoalsPanel", "action": "complete_bonds"},
	],
	"assembly": [
		{"id": "as_1", "text": "Assembly Mode", "description": "In this mode, you assemble components into a device. Each component is a pre-built unit.", "highlight": "ToolPanel", "action": "enter_assembly_mode"},
		{"id": "as_2", "text": "Select a Component", "description": "Click a component from the parts list, then click in the workspace to place it.", "highlight": "ToolPanel", "action": "select_component"},
		{"id": "as_3", "text": "Place the Component", "description": "Click in the 3D workspace to place the component at the cursor position.", "highlight": "ConstructionCanvas", "action": "place_component"},
		{"id": "as_4", "text": "Connect Components", "description": "Components near each other will automatically connect if they're compatible. Check the interface status.", "highlight": "ConservationHUD", "action": "connect_components"},
		{"id": "as_5", "text": "Complete Assembly", "description": "Place all required components and ensure all interfaces are stable.", "highlight": "GoalsPanel", "action": "complete_assembly"},
	],
	"path_build": [
		{"id": "pb_1", "text": "Path Building Mode", "description": "In this mode, you construct a path through a transformation. Think of it as drawing a roadmap for change.", "highlight": "ToolPanel", "action": "enter_path_mode"},
		{"id": "pb_2", "text": "Place Starting Point", "description": "Click to place the starting node of your path. This is the initial state.", "highlight": "ConstructionCanvas", "action": "place_start_node"},
		{"id": "pb_3", "text": "Add Intermediate Steps", "description": "Click along the path to add intermediate nodes. Each node is a step in the transformation.", "highlight": "ConstructionCanvas", "action": "place_path_node"},
		{"id": "pb_4", "text": "Place Ending Point", "description": "Place the final node — the target state. The path must maintain conservation at every step.", "highlight": "ConstructionCanvas", "action": "place_end_node"},
		{"id": "pb_5", "text": "Verify the Path", "description": "Use Ask Physics to verify each step of the path. Fog zones may hide parts of the path — decide whether to investigate.", "highlight": "ToolPanel", "action": "verify_path"},
	],
	"mesh_build": [
		{"id": "mb_1", "text": "Mesh Building Mode", "description": "In this mode, you define a mesh for fluid or field simulation. Set boundaries and conditions.", "highlight": "ToolPanel", "action": "enter_mesh_mode"},
		{"id": "mb_2", "text": "Define Boundaries", "description": "Click points to define the boundary of your mesh. Close the loop to complete the boundary.", "highlight": "ConstructionCanvas", "action": "define_boundary"},
		{"id": "mb_3", "text": "Set Conditions", "description": "Right-click on boundary segments to set conditions (no-slip, inflow, outflow, etc.).", "highlight": "ConstructionCanvas", "action": "set_condition"},
		{"id": "mb_4", "text": "Generate Mesh", "description": "Click Generate to create the mesh. The conservation matrix will check if your setup is physically valid.", "highlight": "ToolPanel", "action": "generate_mesh"},
	],
	"free": [
		{"id": "fr_1", "text": "Free Build Mode", "description": "No restrictions! Use any tool to build whatever you want. The only limit is conservation.", "highlight": "ToolPanel", "action": "enter_free_mode"},
		{"id": "fr_2", "text": "Choose Your Tools", "description": "All tools are unlocked. Experiment with different construction approaches.", "highlight": "ToolPanel", "action": "select_tool"},
		{"id": "fr_3", "text": "Watch Conservation", "description": "Even in free mode, the conservation matrix tracks your structure. Keep it healthy!", "highlight": "ConservationHUD", "action": "check_conservation"},
	],
	# 元胞自动机教程：进入CA模式时触发
	"cellular_automaton": [
		{"id": "ca_1", "text": "元胞自动机模式", "description": "现在你进入了3D元胞自动机世界。规则很简单：每个细胞的死活只取决于周围26个邻居的数量。", "highlight": "ConservationHUD", "action": "enter_ca_mode"},
		{"id": "ca_2", "text": "Bays'规则", "description": "规则写法B/S: B=死细胞复活需要的邻居数, S=活细胞存活需要的邻居数。例如B4555表示5邻居出生, 4或5邻居存活。", "highlight": "ObjectivePanel", "action": "rule_explained"},
		{"id": "ca_3", "text": "点击修改初始态", "description": "左键点击网格中的细胞可以切换它的死活。设计一个好的初始态是关键——很多模式会快速灭绝。", "highlight": "ConstructionCanvas", "action": "cell_toggled"},
		{"id": "ca_4", "text": "按空格演化", "description": "按空格键开始/暂停自动演化, 按N键单步前进。观察右上角的守恒矩阵如何随细胞生灭变化。", "highlight": "ToolPanel", "action": "evolution_started"},
		{"id": "ca_5", "text": "达成目标模式", "description": "任务清单会要求你演化出稳定结构、振荡器或相变。点击'测试结构'按钮验证目标是否完成。", "highlight": "ObjectivePanel", "action": "test_structure"},
	],
	# 迷雾系统教程：首次出现迷雾区域时触发（见 _on_fog_created）
	"fog": [
		{"id": "fog_1", "text": "不可判定区域", "description": "看到那片紫色的雾了吗？那是不可判定区域，物理定律在此失效，里面的内容被隐藏。", "highlight": "ConstructionCanvas", "action": "fog_intro"},
		{"id": "fog_2", "text": "切换与预览迷雾", "description": "按 F 键可以切换迷雾可见性，或花核心预览雾中内容——窥视能帮你判断是否值得驱散。", "highlight": "ToolPanel", "action": "fog_peeked"},
		{"id": "fog_3", "text": "小心独立型迷雾", "description": "独立型迷雾（暗紫色）无法被驱散，只能绕行；半可判定型（蓝色）花核心即可驱散。", "highlight": "ConstructionCanvas", "action": "fog_warning"},
	],
	# 自进化系统教程：首次获得进化点时触发（见 _on_evolve_points_changed）
	"evolution": [
		{"id": "evo_1", "text": "进化点与核心", "description": "通关关卡会同时获得核心和进化点（1 核心 = 1 进化点）。核心是货币，进化点用来创造规则。", "highlight": "ConservationHUD", "action": "evolution_intro"},
		{"id": "evo_2", "text": "打开自进化面板", "description": "在自进化面板中，花 5 进化点即可创建一条自定义物理规则。规则模板有量子隧穿、热激发等。", "highlight": "ToolPanel", "action": "evolution_open"},
		{"id": "evo_3", "text": "规则影响守恒矩阵", "description": "创建的规则会写入守恒矩阵，改变游戏的物理行为。大胆尝试——存在即被构造。", "highlight": "ConservationHUD", "action": "evolution_rule_created"},
	],
	# 证明树教程：首次打开证明面板时触发
	"proof_tree": [
		{"id": "pt_1", "text": "证明树系统", "description": "这是证明树面板。每完成一层验证，树会长出一个新节点。L1=符号验证 L2=类型验证 L3=逻辑验证 L4=语义验证 L5=形式化验证。", "highlight": "ProofPanel", "action": "proof_opened"},
		{"id": "pt_2", "text": "验证层级", "description": "低层级验证快速且免费，高层级更严格但消耗核心。L4有LLM回退，L5用Z3形式化约束求解。", "highlight": "ProofPanel", "action": "proof_explained"},
		{"id": "pt_3", "text": "存在即被构造", "description": "每个通过验证的结构都是一次数学证明。证明树记录了你的推理路径——从直觉到形式化。", "highlight": "ProofPanel", "action": "proof_completed"},
	],
	# 结构图鉴教程：首次打开图鉴时触发
	"structure_codex": [
		{"id": "sc_1", "text": "结构图鉴", "description": "这里记录你构建过的所有结构。每个结构都有基因编码，记录了它的空间群、原子构成和守恒状态。", "highlight": "StructureCodexPanel", "action": "codex_opened"},
		{"id": "sc_2", "text": "基因杂交", "description": "选择两个结构可以进行基因杂交——子结构继承父代的部分特征。这是探索新结构空间的方法。", "highlight": "StructureCodexPanel", "action": "codex_explained"},
		{"id": "sc_3", "text": "变异与进化", "description": "对结构施加变异可以产生新变体。变异后的结构如果守恒矩阵稳定，就可以保存到图鉴中。", "highlight": "StructureCodexPanel", "action": "codex_completed"},
	],
	# 进化树教程：首次打开进化树时触发
	"evolution_tree": [
		{"id": "et_1", "text": "进化树", "description": "进化树记录了你的通关路径。每个节点是一关，分支代表不同的通关策略。", "highlight": "EvolutionTreePanel", "action": "tree_opened"},
		{"id": "et_2", "text": "称号系统", "description": "随着通关数增加，你会获得称号：学徒→构造者→证明者→守恒者→演化者→直觉者。称号反映你的游戏深度。", "highlight": "EvolutionTreePanel", "action": "tree_explained"},
		{"id": "et_3", "text": "回溯与重玩", "description": "点击进化树上的节点可以回溯到该关。用不同策略通关会生成新的分支，丰富你的进化树。", "highlight": "EvolutionTreePanel", "action": "tree_completed"},
	],
	# 核心商店教程：首次打开商店时触发
	"core_shop": [
		{"id": "cs_1", "text": "核心商店", "description": "在核心商店中，你可以用验证核心购买道具和功能。核心通过通关和验证获得。", "highlight": "CoreShopPanel", "action": "shop_opened"},
		{"id": "cs_2", "text": "道具与解锁", "description": "商店提供：驱雾器（驱散迷雾）、预览器（窥视雾中内容）、皮肤（自定义外观）、AI助手提前解锁等。", "highlight": "CoreShopPanel", "action": "shop_explained"},
		{"id": "cs_3", "text": "理性消费", "description": "核心有限，优先购买对你当前关卡最有帮助的道具。部分道具在特定关卡类型中才有用。", "highlight": "CoreShopPanel", "action": "shop_completed"},
	],
	# 验证系统教程：首次运行测试结构时触发
	"verification": [
		{"id": "vf_1", "text": "测试结构", "description": "点击'测试结构'按钮触发验证管线。系统会检查你的结构是否满足守恒律和关卡目标。", "highlight": "ObjectivePanel", "action": "verification_started"},
		{"id": "vf_2", "text": "验证结果", "description": "验证通过=绿色闪光+核心返还。验证失败=红色闪光+失败原因提示。根据提示调整结构后重新测试。", "highlight": "ConservationHUD", "action": "verification_result"},
		{"id": "vf_3", "text": "验证类目标", "description": "带🔍标记的目标必须通过测试才能完成。即使你放置了所有原子，不测试就无法通关——证明需要验证。", "highlight": "ObjectivePanel", "action": "verification_completed"},
	],
}

var _current_step: int = -1
var _is_active: bool = false
var _completed: bool = false
var _overlay: Control = null

# 域教程状态
var _domain_active: bool = false
var _domain_mode: String = ""
var _domain_step: int = -1
var _seen_tutorials: Dictionary = {}  # construction_mode -> bool

# 步骤完成检测的观察标记
var _atom_placed_this_step: bool = false
var _verification_done_this_step: bool = false
var _domain_action_flags: Dictionary = {}  # action -> bool

# 被推迟的域教程：迷雾/进化教程触发时若已有教程在播，先挂起，等当前教程结束再补播
var _fog_tutorial_pending: bool = false
var _evolution_tutorial_pending: bool = false

# JSON 加载的教程数据 (fallback 到硬编码 const)
var _steps: Array[Dictionary] = []
var _domain_tutorials: Dictionary = {}
const TUTORIAL_DATA_PATH := "res://data/tutorials/tutorial_data.json"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_tutorial_data()
	_load_progress()
	_load_domain_progress()
	# 延后一帧再连信号，确保 FogSystem / SelfEvolve 等后注册的 autoload 都已就绪
	call_deferred("_connect_system_signals")


func _exit_tree() -> void:
	if FogSystem != null and FogSystem.is_connected("fog_created", _on_fog_created):
		FogSystem.fog_created.disconnect(_on_fog_created)
	if SelfEvolve != null and SelfEvolve.is_connected("evolve_points_changed", _on_evolve_points_changed):
		SelfEvolve.evolve_points_changed.disconnect(_on_evolve_points_changed)


func _load_tutorial_data() -> void:
	# 优先从 JSON 加载教程数据
	if FileAccess.file_exists(TUTORIAL_DATA_PATH):
		var file := FileAccess.open(TUTORIAL_DATA_PATH, FileAccess.READ)
		if file != null:
			var raw := file.get_as_text()
			file.close()
			var json := JSON.new()
			if json.parse(raw) == OK:
				var data: Dictionary = json.data
				if data.get("steps") is Array:
					var raw_steps: Array = data["steps"]
					for step in raw_steps:
						_steps.append(step)
				if data.get("domain_tutorials") is Dictionary:
					_domain_tutorials = data["domain_tutorials"]
				GameLogger.info("TutorialManager", "Loaded tutorial data from JSON: %d steps, %d domains" % [_steps.size(), _domain_tutorials.size()])
				return
	# Fallback: 使用硬编码常量
	_steps = STEPS.duplicate(true)
	_domain_tutorials = DOMAIN_TUTORIALS.duplicate(true)
	GameLogger.info("TutorialManager", "Using hardcoded tutorial data (JSON not available)")


func start_tutorial() -> void:
	if _completed:
		return
	_is_active = true
	_current_step = -1
	_advance_step()


func is_active() -> bool:
	return _is_active


func is_completed() -> bool:
	return _completed


func set_completed(value: bool) -> void:
	_completed = value
	if _completed:
		_is_active = false


func reset_tutorial_progress() -> void:
	# 重置教程进度，允许玩家重新查看教程
	_completed = false
	_current_step = 0
	_is_active = false
	_save_progress()
	GameLogger.info("TutorialManager", "教程进度已重置")


func replay_tutorial() -> void:
	# 从头开始播放教程
	reset_tutorial_progress()
	start_tutorial()

func set_current_step(step: int) -> void:
	_current_step = step

func get_current_step() -> int:
	return _current_step


func get_current_step_data() -> Dictionary:
	if _current_step < 0 or _current_step >= _steps.size():
		return {}
	return _steps[_current_step]


func advance() -> void:
	if not _is_active:
		return
	_advance_step()


func skip() -> void:
	_is_active = false
	_completed = true
	_save_progress()
	tutorial_skipped.emit()
	if _overlay:
		_overlay.hide()
	# 跳过后补播被推迟的迷雾/进化教程
	call_deferred("_flush_pending_tutorials")


func set_overlay(overlay: Control) -> void:
	_overlay = overlay


func clear_overlay() -> void:
	_overlay = null



# 供外部系统调用，标记玩家完成了某个动作
func notify_action(action: String) -> void:
	# 域教程动作检测
	if _domain_active:
		_domain_action_flags[action] = true
		_check_domain_step_completion()
		return

	# Ch1基础教程动作检测
	if not _is_active:
		return
	match action:
		"atom_placed":
			_atom_placed_this_step = true
		"verification_done":
			_verification_done_this_step = true
	_check_step_completion()


func _advance_step() -> void:
	_current_step += 1
	_atom_placed_this_step = false
	_verification_done_this_step = false

	if _current_step >= _steps.size():
		_is_active = false
		_completed = true
		_save_progress()
		tutorial_completed.emit()
		if _overlay:
			_overlay.hide()
		# Ch1教程结束，补播被推迟的迷雾/进化教程
		call_deferred("_flush_pending_tutorials")
		return

	tutorial_step_changed.emit(_current_step)


func _check_step_completion() -> void:
	if not _is_active or _current_step < 0:
		return

	var step_key: String = _steps[_current_step]["key"]
	var should_advance := false

	match step_key:
		"welcome", "goals_panel", "wyckoff", "conservation", "test_structure", \
		"complete", "core_economy", "proof_done":
			# 这些步骤由玩家点击Next推进
			pass
		"place_atom":
			should_advance = _atom_placed_this_step
		"ask_physics":
			should_advance = _verification_done_this_step

	if should_advance and _overlay:
		_overlay.mark_step_complete()


func _save_progress() -> void:
	var data := {
		"completed": _completed,
		"last_step": _current_step,
	}
	var file := FileAccess.open("user://tutorial_save.dat", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()


func _load_progress() -> void:
	if not FileAccess.file_exists("user://tutorial_save.dat"):
		return
	var file := FileAccess.open("user://tutorial_save.dat", FileAccess.READ)
	if not file:
		return
	var raw := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(raw) != OK:
		return
	var data: Dictionary = json.data
	if data.get("completed", false):
		_completed = true
		_is_active = false


# ============================================================
# 系统信号接入：迷雾/进化教程的自动触发
# ============================================================

func _connect_system_signals() -> void:
	# 监听迷雾创建：首次出现迷雾时引导玩家认识不可判定区域
	if FogSystem != null and FogSystem.has_signal("fog_created"):
		if not FogSystem.fog_created.is_connected(_on_fog_created):
			FogSystem.fog_created.connect(_on_fog_created)
	# 监听进化点变化：首次拿到进化点时引导玩家使用自进化面板
	if SelfEvolve != null and SelfEvolve.has_signal("evolve_points_changed"):
		if not SelfEvolve.evolve_points_changed.is_connected(_on_evolve_points_changed):
			SelfEvolve.evolve_points_changed.connect(_on_evolve_points_changed)


func _on_fog_created(_region_id: int, _fog_type: int) -> void:
	# 只在第一次见到迷雾时触发，已看过则跳过
	if has_seen_tutorial("fog"):
		return
	# 当前有教程在播就先挂起，避免覆盖正在进行的引导
	if _domain_active or _is_active:
		_fog_tutorial_pending = true
		return
	start_domain_tutorial("fog")


func _on_evolve_points_changed(new_amount: int) -> void:
	# 进化点首次进账（>0）时触发，引导玩家认识自进化系统
	if new_amount <= 0:
		return
	if has_seen_tutorial("evolution"):
		return
	if _domain_active or _is_active:
		_evolution_tutorial_pending = true
		return
	start_domain_tutorial("evolution")


# 当前教程结束后补播被推迟的迷雾/进化教程
func _flush_pending_tutorials() -> void:
	if _domain_active or _is_active:
		return
	if _fog_tutorial_pending and not has_seen_tutorial("fog"):
		_fog_tutorial_pending = false
		start_domain_tutorial("fog")
		return
	if _evolution_tutorial_pending and not has_seen_tutorial("evolution"):
		_evolution_tutorial_pending = false
		start_domain_tutorial("evolution")
		return


# ============================================================
# 域教程 (Ch2-Ch3各构造模式)
# ============================================================

func start_domain_tutorial(construction_mode: String) -> void:
	if not _domain_tutorials.has(construction_mode):
		return
	if has_seen_tutorial(construction_mode):
		return
	# 如果Ch1教程还在进行中，先跳过
	if _is_active:
		skip()

	_domain_active = true
	_domain_mode = construction_mode
	_domain_step = -1
	_domain_action_flags.clear()
	_advance_domain_step()
	domain_tutorial_started.emit(construction_mode)


func has_seen_tutorial(construction_mode: String) -> bool:
	return _seen_tutorials.get(construction_mode, false)


func is_domain_active() -> bool:
	return _domain_active


func get_domain_mode() -> String:
	return _domain_mode


func get_domain_step() -> int:
	return _domain_step


func get_domain_step_data() -> Dictionary:
	if not _domain_active:
		return {}
	var steps: Array = _domain_tutorials.get(_domain_mode, [])
	if _domain_step < 0 or _domain_step >= steps.size():
		return {}
	return steps[_domain_step]


func advance_domain() -> void:
	if not _domain_active:
		return
	_advance_domain_step()


func skip_domain() -> void:
	_domain_active = false
	_seen_tutorials[_domain_mode] = true
	_save_domain_progress()
	domain_tutorial_completed.emit(_domain_mode)
	_domain_mode = ""
	if _overlay:
		_overlay.hide()
	# 跳过后同样补播被推迟的迷雾/进化教程
	call_deferred("_flush_pending_tutorials")


func _advance_domain_step() -> void:
	_domain_step += 1
	_domain_action_flags.clear()

	var steps: Array = _domain_tutorials.get(_domain_mode, [])
	if _domain_step >= steps.size():
		_domain_active = false
		_seen_tutorials[_domain_mode] = true
		_save_domain_progress()
		domain_tutorial_completed.emit(_domain_mode)
		_domain_mode = ""
		if _overlay:
			_overlay.hide()
		# 当前域教程结束，补播被推迟的迷雾/进化教程
		call_deferred("_flush_pending_tutorials")
		return

	tutorial_step_changed.emit(_domain_step)


func _check_domain_step_completion() -> void:
	if not _domain_active or _domain_step < 0:
		return

	var steps: Array = _domain_tutorials.get(_domain_mode, [])
	if _domain_step >= steps.size():
		return

	var step_data: Dictionary = steps[_domain_step]
	var action: String = step_data.get("action", "")

	# 首步(进入模式)自动完成，其余需要对应动作触发
	if action.ends_with("_mode") or action == "enter_free_mode":
		if _overlay:
			_overlay.mark_step_complete()
		return

	if _domain_action_flags.get(action, false):
		if _overlay:
			_overlay.mark_step_complete()


func _save_domain_progress() -> void:
	var data := {
		"seen_tutorials": _seen_tutorials,
	}
	var file := FileAccess.open("user://tutorial_progress.dat", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()


func _load_domain_progress() -> void:
	if not FileAccess.file_exists("user://tutorial_progress.dat"):
		return
	var file := FileAccess.open("user://tutorial_progress.dat", FileAccess.READ)
	if not file:
		return
	var raw := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(raw) != OK:
		return
	var data: Dictionary = json.data
	_seen_tutorials = data.get("seen_tutorials", {})
