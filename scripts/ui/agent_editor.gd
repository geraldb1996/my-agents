class_name AgentEditor
extends Control

@onready var name_edit: LineEdit = %NameEdit
@onready var model_select: OptionButton = %ModelSelect
@onready var model_custom_edit: LineEdit = %ModelCustomEdit
@onready var opencode_agent_edit: LineEdit = %OpenCodeAgentEdit
@onready var personality_edit: TextEdit = %PersonalityEdit
@onready var skills_box: VBoxContainer = %SkillsBox
@onready var skill_input: LineEdit = %SkillInput
@onready var character_preview: TextureRect = %CharacterPreview
@onready var character_dialog: FileDialog = %CharacterDialog
@onready var project_label: Label = %ProjectLabel
@onready var project_dialog: FileDialog = %ProjectDialog

var _editing_id: String = ""
var _character_path: String = "res://images/agent1/agent.png"
var _project_path: String = ""


func _ready() -> void:
	%AddSkillButton.pressed.connect(_on_add_skill_pressed)
	%SaveButton.pressed.connect(_on_save_pressed)
	%CancelButton.pressed.connect(_on_cancel_pressed)
	%CharacterButton.pressed.connect(func(): character_dialog.popup_centered_ratio(0.5))
	%ProjectButton.pressed.connect(func(): project_dialog.popup_centered_ratio(0.5))
	character_dialog.file_selected.connect(_on_character_selected)
	project_dialog.dir_selected.connect(_on_project_selected)
	%ModelRefreshButton.pressed.connect(_on_refresh_models_pressed)
	model_select.item_selected.connect(_on_model_item_selected)
	ModelCatalog.models_loaded.connect(_on_models_loaded)


func open_new() -> void:
	_editing_id = ""
	_populate_defaults()
	_ensure_catalog()


func open_profile(profile: AgentProfile) -> void:
	_editing_id = profile.id
	name_edit.text = profile.name
	opencode_agent_edit.text = profile.opencode_agent
	personality_edit.text = profile.personality
	_character_path = profile.character if not profile.character.is_empty() else "res://images/agent1/agent.png"
	_project_path = profile.project
	_refresh_skills(profile.skills)
	_update_character_preview()
	_update_project_label()
	_ensure_catalog()
	_select_model(profile.model)
	visible = true


func _populate_defaults() -> void:
	name_edit.text = ""
	opencode_agent_edit.text = ""
	personality_edit.text = ""
	_character_path = "res://images/agent1/agent.png"
	_project_path = ""
	_refresh_skills([])
	_update_character_preview()
	_update_project_label()
	_select_model("")
	model_custom_edit.text = ""
	model_custom_edit.visible = false
	visible = true
	name_edit.grab_focus()


func _ensure_catalog() -> void:
	if ModelCatalog.models.is_empty() and not ModelCatalog.loaded_once:
		ModelCatalog.refresh()


func _on_models_loaded() -> void:
	if not visible:
		return
	var current := _get_selected_model()
	_populate_model_items()
	_select_model(current)


func _populate_model_items() -> void:
	var previous := _get_selected_model()
	model_select.clear()
	model_select.add_item("Default (auto)", 0)
	for m in ModelCatalog.models:
		model_select.add_item(m)
	model_select.add_item("Custom model...", -1)
	_select_model(previous)


func _select_model(model: String) -> void:
	model_custom_edit.text = model
	if model.is_empty():
		model_select.select(0)
		model_custom_edit.visible = false
		return
	for i in range(1, ModelCatalog.models.size() + 1):
		if model_select.get_item_text(i) == model:
			model_select.select(i)
			model_custom_edit.visible = false
			return
	var custom_idx := ModelCatalog.models.size() + 1
	model_select.select(custom_idx)
	model_custom_edit.visible = true
	model_custom_edit.text = model


func _get_selected_model() -> String:
	if model_select.selected < 0:
		return model_custom_edit.text.strip_edges()
	if model_select.selected == 0:
		return ""
	var custom_idx := ModelCatalog.models.size() + 1
	if model_select.selected == custom_idx:
		return model_custom_edit.text.strip_edges()
	return model_select.get_item_text(model_select.selected)


func _on_model_item_selected(index: int) -> void:
	var custom_idx := ModelCatalog.models.size() + 1
	model_custom_edit.visible = index == custom_idx
	if index == custom_idx:
		model_custom_edit.grab_focus()


func _on_refresh_models_pressed() -> void:
	ModelCatalog.refresh()


func _refresh_skills(skills: Array) -> void:
	for child in skills_box.get_children():
		child.queue_free()
	for skill in skills:
		_add_skill_row(str(skill))


func _add_skill_row(skill: String) -> void:
	var row := HBoxContainer.new()
	var edit := LineEdit.new()
	edit.text = skill
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	var remove := Button.new()
	remove.text = "x"
	remove.pressed.connect(row.queue_free)
	row.add_child(remove)
	skills_box.add_child(row)


func _on_add_skill_pressed() -> void:
	var skill := skill_input.text.strip_edges()
	if skill.is_empty():
		return
	_add_skill_row(skill)
	skill_input.clear()
	skill_input.grab_focus()


func _collect_skills() -> Array[String]:
	var skills: Array[String] = []
	for child in skills_box.get_children():
		if child is HBoxContainer and child.get_child_count() > 0:
			var edit := child.get_child(0) as LineEdit
			if edit != null:
				var text: String = edit.text.strip_edges()
				if not text.is_empty() and not skills.has(text):
					skills.append(text)
	return skills


func _on_character_selected(path: String) -> void:
	_character_path = path
	_update_character_preview()


func _on_project_selected(path: String) -> void:
	_project_path = path
	_update_project_label()


func _update_character_preview() -> void:
	if FileAccess.file_exists(_character_path):
		character_preview.texture = load(_character_path)
	else:
		character_preview.texture = null
	character_preview.tooltip_text = _character_path


func _update_project_label() -> void:
	project_label.text = _project_path if not _project_path.is_empty() else "--"
	project_label.tooltip_text = _project_path


func _on_save_pressed() -> void:
	var agent_name: String = name_edit.text.strip_edges()
	if agent_name.is_empty():
		EventBus.agent_output.emit("", "[error] Agent name is required")
		name_edit.grab_focus()
		return
	var model := _get_selected_model()
	var profile: AgentProfile
	if not _editing_id.is_empty() and ProfileStore.profiles.has(_editing_id):
		profile = ProfileStore.profiles[_editing_id]
		profile.name = agent_name
		profile.model = model
		profile.opencode_agent = opencode_agent_edit.text.strip_edges()
		profile.personality = personality_edit.text
		profile.skills = _collect_skills()
		profile.character = _character_path
		profile.project = _project_path
	else:
		profile = AgentProfile.new()
		profile.ensure_id()
		profile.name = agent_name
		profile.model = model
		profile.opencode_agent = opencode_agent_edit.text.strip_edges()
		profile.personality = personality_edit.text
		profile.skills = _collect_skills()
		profile.character = _character_path
		profile.project = _project_path
		profile.created_at = Time.get_unix_time_from_system()
	ProfileStore.save_profile(profile)
	EventBus.profile_saved.emit(profile)
	visible = false


func _on_cancel_pressed() -> void:
	visible = false