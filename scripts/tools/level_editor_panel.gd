extends PanelContainer

var _i18n = null
# Level Editor UI Panel
# Binds UI controls to LevelEditor data model

const LEVEL_EDITOR_SCRIPT := "res://scripts/tools/level_editor.gd"

@onready var _level_editor = null

# Title bar
@onready var _title_edit: LineEdit = %TitleEdit
@onready var _chapter_spin: SpinBox = %ChapterSpin
@onready var _level_spin: SpinBox = %LevelSpin

# Basic info
@onready var _description_edit: TextEdit = %DescriptionEdit
@onready var _domain_option: OptionButton = %DomainOption
@onready var _construction_mode_option: OptionButton = %ConstructionModeOption
@onready var _space_group_number_spin: SpinBox = %SpaceGroupNumberSpin
@onready var _space_group_symbol_edit: LineEdit = %SpaceGroupSymbolEdit

# Lattice
@onready var _lattice_x: SpinBox = %LatticeX
@onready var _lattice_y: SpinBox = %LatticeY
@onready var _lattice_z: SpinBox = %LatticeZ
@onready var _angle_x: SpinBox = %AngleX
@onready var _angle_y: SpinBox = %AngleY
@onready var _angle_z: SpinBox = %AngleZ

# Elements
@onready var _elements_list: ItemList = %ElementsList
@onready var _element_symbol_edit: LineEdit = %ElementSymbolEdit
@onready var _element_wyckoff_edit: LineEdit = %ElementWyckoffEdit
@onready var _element_multiplicity_spin: SpinBox = %ElementMultiplicitySpin
@onready var _element_pos_x: SpinBox = %ElementPosX
@onready var _element_pos_y: SpinBox = %ElementPosY
@onready var _element_pos_z: SpinBox = %ElementPosZ
@onready var _add_element_btn: Button = %AddElementBtn
@onready var _remove_element_btn: Button = %RemoveElementBtn

# Goals
@onready var _goals_list: ItemList = %GoalsList
@onready var _goal_type_option: OptionButton = %GoalTypeOption
@onready var _goal_description_edit: TextEdit = %GoalDescriptionEdit
@onready var _add_goal_btn: Button = %AddGoalBtn
@onready var _remove_goal_btn: Button = %RemoveGoalBtn

# Toolbar
@onready var _save_btn: Button = %SaveBtn
@onready var _load_btn: Button = %LoadBtn
@onready var _new_btn: Button = %NewBtn
@onready var _validate_btn: Button = %ValidateBtn

# Misc
@onready var _reward_cores_spin: SpinBox = %RewardCoresSpin
@onready var _hint_edit: LineEdit = %HintEdit
@onready var _journal_edit: TextEdit = %JournalEdit
@onready var _scale_label_edit: LineEdit = %ScaleLabelEdit
@onready var _scale_min: SpinBox = %ScaleMin
@onready var _scale_max: SpinBox = %ScaleMax

var _updating_ui := false

func _ready() -> void:
	_i18n = Engine.get_main_loop().root.get_node_or_null("/root/I18nManager")
	if _i18n != null and _i18n.has_signal("language_changed"):
		_i18n.language_changed.connect(_on_language_changed)
	_level_editor = load(LEVEL_EDITOR_SCRIPT).new()
	_setup_domain_options()
	_setup_construction_mode_options()
	_setup_goal_type_options()
	_connect_signals()
	_refresh_text()
	_level_editor.new_level(1, 1)

func _setup_domain_options() -> void:
	var domains := ["crystal", "molecular", "fluid", "device", "reaction", "topology", "open"]
	_domain_option.clear()
	for d in domains:
		_domain_option.add_item(d)

func _setup_construction_mode_options() -> void:
	var modes := ["wyckoff_fill", "bond_build", "mesh_build", "path_build", "assembly", "free", "cellular_automaton"]
	_construction_mode_option.clear()
	for m in modes:
		_construction_mode_option.add_item(m)

func _setup_goal_type_options() -> void:
	_goal_type_option.clear()
	var validator_script = load("res://scripts/autoload/level_data_validator.gd")
	for t in validator_script.VALID_GOAL_TYPES:
		_goal_type_option.add_item(t)

func _connect_signals() -> void:
	_level_editor.level_loaded.connect(_on_level_loaded)
	_level_editor.data_changed.connect(_on_data_changed)

	_title_edit.text_changed.connect(_on_title_changed)
	_description_edit.text_changed.connect(_on_description_changed)
	_domain_option.item_selected.connect(_on_domain_selected)
	_construction_mode_option.item_selected.connect(_on_construction_mode_selected)
	_space_group_number_spin.value_changed.connect(_on_space_group_number_changed)
	_space_group_symbol_edit.text_changed.connect(_on_space_group_symbol_changed)
	_lattice_x.value_changed.connect(_on_lattice_changed)
	_lattice_y.value_changed.connect(_on_lattice_changed)
	_lattice_z.value_changed.connect(_on_lattice_changed)
	_angle_x.value_changed.connect(_on_angles_changed)
	_angle_y.value_changed.connect(_on_angles_changed)
	_angle_z.value_changed.connect(_on_angles_changed)
	_reward_cores_spin.value_changed.connect(_on_reward_cores_changed)
	_hint_edit.text_changed.connect(_on_hint_changed)
	_journal_edit.text_changed.connect(_on_journal_changed)
	_scale_label_edit.text_changed.connect(_on_scale_label_changed)
	_scale_min.value_changed.connect(_on_scale_range_changed)
	_scale_max.value_changed.connect(_on_scale_range_changed)

	_add_element_btn.pressed.connect(_on_add_element_pressed)
	_remove_element_btn.pressed.connect(_on_remove_element_pressed)
	_elements_list.item_selected.connect(_on_element_selected)

	_add_goal_btn.pressed.connect(_on_add_goal_pressed)
	_remove_goal_btn.pressed.connect(_on_remove_goal_pressed)
	_goals_list.item_selected.connect(_on_goal_selected)

	_save_btn.pressed.connect(_on_save_pressed)
	_load_btn.pressed.connect(_on_load_pressed)
	_new_btn.pressed.connect(_on_new_pressed)
	_validate_btn.pressed.connect(_on_validate_pressed)

	_element_symbol_edit.text_changed.connect(_on_element_field_changed)
	_element_wyckoff_edit.text_changed.connect(_on_element_field_changed)
	_element_multiplicity_spin.value_changed.connect(_on_element_field_changed)
	_element_pos_x.value_changed.connect(_on_element_field_changed)
	_element_pos_y.value_changed.connect(_on_element_field_changed)
	_element_pos_z.value_changed.connect(_on_element_field_changed)

	_goal_type_option.item_selected.connect(_on_goal_field_changed)
	_goal_description_edit.text_changed.connect(_on_goal_field_changed)

func _on_level_loaded(data: LevelData) -> void:
	_refresh_ui()

func _on_data_changed() -> void:
	_refresh_ui()

func _refresh_ui() -> void:
	if _level_editor == null:
		return
	var data: Variant = _level_editor.get_current_data()
	if data == null:
		return

	_updating_ui = true

	_chapter_spin.value = data.chapter
	_level_spin.value = data.level
	_title_edit.text = data.title
	_description_edit.text = data.description

	_select_option_by_text(_domain_option, data.domain)
	_select_option_by_text(_construction_mode_option, data.construction_mode)

	_space_group_number_spin.value = data.space_group_number
	_space_group_symbol_edit.text = data.space_group_symbol

	_lattice_x.value = data.lattice_parameters.x
	_lattice_y.value = data.lattice_parameters.y
	_lattice_z.value = data.lattice_parameters.z
	_angle_x.value = data.lattice_angles.x
	_angle_y.value = data.lattice_angles.y
	_angle_z.value = data.lattice_angles.z

	_reward_cores_spin.value = data.reward_cores
	_hint_edit.text = data.hint
	_journal_edit.text = data.journal_entry
	_scale_label_edit.text = data.scale_label
	_scale_min.value = data.scale_range.x
	_scale_max.value = data.scale_range.y

	_elements_list.clear()
	for el in data.elements:
		var symbol := str(el.get("symbol", "?"))
		_elements_list.add_item(symbol)

	_goals_list.clear()
	for g in data.goals:
		var type_str := str(g.get("type", "?"))
		_goals_list.add_item(type_str)

	_updating_ui = false

func _select_option_by_text(option: OptionButton, text: String) -> void:
	for i in range(option.item_count):
		if option.get_item_text(i) == text:
			option.select(i)
			return

func _on_title_changed(text: String) -> void:
	if _updating_ui or _level_editor == null:
		return
	_level_editor.set_title(text)

func _on_description_changed() -> void:
	if _updating_ui or _level_editor == null:
		return
	_level_editor.set_description(_description_edit.text)

func _on_domain_selected(index: int) -> void:
	if _updating_ui or _level_editor == null:
		return
	_level_editor.set_domain(_domain_option.get_item_text(index))

func _on_construction_mode_selected(index: int) -> void:
	if _updating_ui or _level_editor == null:
		return
	_level_editor.set_construction_mode(_construction_mode_option.get_item_text(index))

func _on_space_group_number_changed(value: float) -> void:
	if _updating_ui or _level_editor == null:
		return
	_level_editor.set_space_group_number(int(value))

func _on_space_group_symbol_changed(text: String) -> void:
	if _updating_ui or _level_editor == null:
		return
	_level_editor.set_space_group_symbol(text)

func _on_lattice_changed(_value: float) -> void:
	if _updating_ui or _level_editor == null:
		return
	_level_editor.set_lattice_parameters(Vector3(_lattice_x.value, _lattice_y.value, _lattice_z.value))

func _on_angles_changed(_value: float) -> void:
	if _updating_ui or _level_editor == null:
		return
	_level_editor.set_lattice_angles(Vector3(_angle_x.value, _angle_y.value, _angle_z.value))

func _on_reward_cores_changed(value: float) -> void:
	if _updating_ui or _level_editor == null:
		return
	_level_editor.set_reward_cores(int(value))

func _on_hint_changed(text: String) -> void:
	if _updating_ui or _level_editor == null:
		return
	_level_editor.set_hint(text)

func _on_journal_changed() -> void:
	if _updating_ui or _level_editor == null:
		return
	_level_editor.set_journal_entry(_journal_edit.text)

func _on_scale_label_changed(text: String) -> void:
	if _updating_ui or _level_editor == null:
		return
	_level_editor.set_scale_label(text)

func _on_scale_range_changed(_value: float) -> void:
	if _updating_ui or _level_editor == null:
		return
	_level_editor.set_scale_range(Vector2(_scale_min.value, _scale_max.value))

func _on_add_element_pressed() -> void:
	if _level_editor == null:
		return
	var el := {
		"symbol": _element_symbol_edit.text,
		"wyckoff_label": _element_wyckoff_edit.text,
		"wyckoff_multiplicity": int(_element_multiplicity_spin.value),
		"position": Vector3(_element_pos_x.value, _element_pos_y.value, _element_pos_z.value),
	}
	_level_editor.add_element(el)

func _on_remove_element_pressed() -> void:
	if _level_editor == null:
		return
	var selected := _elements_list.get_selected_items()
	if selected.size() > 0:
		_level_editor.remove_element(selected[0])

func _on_element_selected(index: int) -> void:
	if _level_editor == null:
		return
	var data: Variant = _level_editor.get_current_data()
	if index < 0 or index >= data.elements.size():
		return
	var el := data.elements[index]
	_element_symbol_edit.text = str(el.get("symbol", ""))
	_element_wyckoff_edit.text = str(el.get("wyckoff_label", ""))
	_element_multiplicity_spin.value = int(el.get("wyckoff_multiplicity", 1))
	var pos = el.get("position", Vector3.ZERO)
	if pos is Vector3:
		_element_pos_x.value = pos.x
		_element_pos_y.value = pos.y
		_element_pos_z.value = pos.z
	elif pos is Dictionary:
		_element_pos_x.value = float(pos.get("x", 0.0))
		_element_pos_y.value = float(pos.get("y", 0.0))
		_element_pos_z.value = float(pos.get("z", 0.0))

func _on_element_field_changed() -> void:
	if _updating_ui or _level_editor == null:
		return
	var selected := _elements_list.get_selected_items()
	if selected.size() > 0:
		var el := {
			"symbol": _element_symbol_edit.text,
			"wyckoff_label": _element_wyckoff_edit.text,
			"wyckoff_multiplicity": int(_element_multiplicity_spin.value),
			"position": Vector3(_element_pos_x.value, _element_pos_y.value, _element_pos_z.value),
		}
		_level_editor.update_element(selected[0], el)

func _on_add_goal_pressed() -> void:
	if _level_editor == null:
		return
	var g := {
		"type": _goal_type_option.get_item_text(_goal_type_option.selected),
		"description": _goal_description_edit.text,
	}
	_level_editor.add_goal(g)

func _on_remove_goal_pressed() -> void:
	if _level_editor == null:
		return
	var selected := _goals_list.get_selected_items()
	if selected.size() > 0:
		_level_editor.remove_goal(selected[0])

func _on_goal_selected(index: int) -> void:
	if _level_editor == null:
		return
	var data: Variant = _level_editor.get_current_data()
	if index < 0 or index >= data.goals.size():
		return
	var g: Dictionary = data.goals[index]
	_select_option_by_text(_goal_type_option, str(g.get("type", "")))
	_goal_description_edit.text = str(g.get("description", ""))

func _on_goal_field_changed() -> void:
	if _updating_ui or _level_editor == null:
		return
	var selected := _goals_list.get_selected_items()
	if selected.size() > 0:
		var g := {
			"type": _goal_type_option.get_item_text(_goal_type_option.selected),
			"description": _goal_description_edit.text,
		}
		_level_editor.update_goal(selected[0], g)

func _on_save_pressed() -> void:
	if _level_editor == null:
		return
	var success: bool = _level_editor.save_level()
	if not success:
		push_error("LevelEditorPanel: save failed")

func _on_load_pressed() -> void:
	if _level_editor == null:
		return
	var chapter := int(_chapter_spin.value)
	var level := int(_level_spin.value)
	var success: bool = _level_editor.load_level(chapter, level)
	if not success:
		push_error("LevelEditorPanel: load failed for %d-%d" % [chapter, level])

func _on_new_pressed() -> void:
	if _level_editor == null:
		return
	var chapter := int(_chapter_spin.value)
	var level := int(_level_spin.value)
	_level_editor.new_level(chapter, level)

func _on_validate_pressed() -> void:
	if _level_editor == null:
		return
	var data: Variant = _level_editor.get_current_data()
	if data == null:
		return
	var validator_script = load("res://scripts/autoload/level_data_validator.gd")
	var errors: Array[String] = validator_script.validate(data.to_json())
	if errors.is_empty():
		print("LevelEditorPanel: Validation passed")
	else:
		push_error("LevelEditorPanel: Validation failed: %s" % ", ".join(errors))

func _on_language_changed(_locale: String) -> void:
	_refresh_text()

func _refresh_text() -> void:
	if _i18n == null:
		return

