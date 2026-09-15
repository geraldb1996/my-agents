class_name AgentEditor
extends Control

@onready var name_edit: LineEdit = %NameEdit
@onready var model_select: OptionButton = %ModelSelect
@onready var model_custom_edit: LineEdit = %ModelCustomEdit
@onready var variant_select: OptionButton = %VariantSelect
@onready var variant_custom_edit: LineEdit = %VariantCustomEdit
@onready var opencode_agent_select: OptionButton = %OpenCodeAgentSelect
@onready var personality_edit: TextEdit = %PersonalityEdit
@onready var skills_box: VBoxContainer = %SkillsBox
@onready var skill_input: LineEdit = %SkillInput
@onready var skill_select: OptionButton = %SkillSelect
@onready var anim_box: VBoxContainer = %AnimBox
@onready var anim_dialog: FileDialog = %AnimDialog
@onready var project_path_edit: LineEdit = %ProjectPathEdit
@onready var project_dialog: FileDialog = %ProjectDialog

const FPS_OPTIONS := [4, 6, 8, 10, 12, 15, 24, 30]
const VARIANT_OPTIONS := ["", "minimal", "low", "medium", "high", "max"]

var _editing_id: String = ""
var _project_path: String = ""
var _animations: Dictionary = {}
var _anim_dialog_state: String = ""
var _selected_opencode_agent: String = ""
var _agent_request_id: int = 0
var _agent_selection_valid: bool = false


func _ready() -> void:
	%AddSkillButton.pressed.connect(_on_add_skill_pressed)
	%SaveButton.pressed.connect(_on_save_pressed)
	%CancelButton.pressed.connect(_on_cancel_pressed)
	%AgentRefreshButton.pressed.connect(_refresh_opencode_agents)
	opencode_agent_select.item_selected.connect(_on_opencode_agent_selected)
	%ProjectButton.pressed.connect(func(): project_dialog.popup_centered_ratio(0.5))
	project_dialog.dir_selected.connect(_on_project_selected)
	project_path_edit.text_submitted.connect(_on_project_path_submitted)
	%ModelRefreshButton.pressed.connect(_on_refresh_models_pressed)
	model_select.item_selected.connect(_on_model_item_selected)
	ModelCatalog.models_loaded.connect(_on_models_loaded)
	_populate_variant_items()
	variant_select.item_selected.connect(_on_variant_item_selected)
	%SkillRefreshButton.pressed.connect(_on_refresh_skills_pressed)
	skill_select.item_selected.connect(_on_skill_item_selected)
	SkillCatalog.skills_loaded.connect(_on_skills_loaded)
	anim_dialog.dir_selected.connect(_on_anim_folder_selected)
	anim_dialog.files_selected.connect(_on_anim_files_selected)


func open_new() -> void:
	_editing_id = ""
	_populate_defaults()


func open_profile(profile: AgentProfile) -> void:
	_editing_id = profile.id
	name_edit.text = profile.name
	_selected_opencode_agent = profile.opencode_agent
	personality_edit.text = profile.personality
	_project_path = profile.project
	_refresh_skills(profile.skills)
	_animations = profile.animations.duplicate(true)
	_refresh_animation_rows()
	_update_project_label()
	_ensure_catalogs()
	_select_model(profile.model)
	_select_variant(profile.model_variant)
	visible = true


func open_duplicate(profile: AgentProfile) -> void:
	open_profile(profile)
	_editing_id = ""
	name_edit.text = "%s (copy)" % profile.name
	name_edit.grab_focus()


func _populate_defaults() -> void:
	name_edit.text = ""
	_selected_opencode_agent = ""
	personality_edit.text = ""
	_project_path = ""
	_refresh_skills([])
	_animations = {}
	_refresh_animation_rows()
	_update_project_label()
	_select_model("")
	model_custom_edit.text = ""
	model_custom_edit.visible = false
	_select_variant("")
	variant_custom_edit.visible = false
	_ensure_catalogs()
	visible = true
	name_edit.grab_focus()


func _ensure_catalogs() -> void:
	if ModelCatalog.models.is_empty() and not ModelCatalog.loaded_once:
		ModelCatalog.refresh()
	if SkillCatalog.skills.is_empty() and not SkillCatalog.loaded_once:
		SkillCatalog.refresh()


func _refresh_opencode_agents() -> void:
	_agent_request_id += 1
	var request_id := _agent_request_id
	_agent_selection_valid = false
	opencode_agent_select.clear()
	opencode_agent_select.add_item("Loading agents...")
	opencode_agent_select.disabled = true
	%SaveButton.disabled = true
	%AgentStatusLabel.text = "Loading agents from OpenCode..."
	OpenCodeServer.get_agents(_project_path, _on_opencode_agents_loaded.bind(request_id))


func _on_opencode_agents_loaded(code: int, data: Variant, request_id: int) -> void:
	if request_id != _agent_request_id:
		return
	opencode_agent_select.clear()
	opencode_agent_select.add_item("Default (auto)")
	opencode_agent_select.set_item_metadata(0, "")
	var names: Array[String] = []
	var loaded := code == 200 and data is Array
	if loaded:
		for entry in data:
			if entry is Dictionary:
				var agent_name := str(entry.get("name", "")).strip_edges()
				if not agent_name.is_empty() and not names.has(agent_name):
					names.append(agent_name)
	names.sort()
	for agent_name in names:
		opencode_agent_select.add_item(agent_name)
		opencode_agent_select.set_item_metadata(opencode_agent_select.item_count - 1, agent_name)
	var selected := names.find(_selected_opencode_agent) + 1
	_agent_selection_valid = _selected_opencode_agent.is_empty() or selected > 0
	%AgentStatusLabel.text = "" if loaded else "Could not load agents. Retry Refresh or choose Default (auto)."
	if not _agent_selection_valid:
		selected = opencode_agent_select.item_count
		opencode_agent_select.add_item("Unavailable: " + _selected_opencode_agent)
		opencode_agent_select.set_item_disabled(selected, true)
		if loaded:
			%AgentStatusLabel.text = "Saved agent no longer exists. Select an available agent or Default (auto)."
	opencode_agent_select.select(selected)
	opencode_agent_select.disabled = false
	%SaveButton.disabled = not _agent_selection_valid


func _on_opencode_agent_selected(index: int) -> void:
	if index < 0 or opencode_agent_select.is_item_disabled(index):
		return
	_selected_opencode_agent = str(opencode_agent_select.get_item_metadata(index))
	_agent_selection_valid = true
	%SaveButton.disabled = false


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
	if model_select.item_count == 0:
		return
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


func _populate_variant_items() -> void:
	variant_select.clear()
	variant_select.add_item("Default (none)", 0)
	for v in VARIANT_OPTIONS:
		if v.is_empty():
			continue
		variant_select.add_item(v)
	variant_select.add_item("Custom...", -1)


func _select_variant(variant: String) -> void:
	if variant_select.item_count == 0:
		_populate_variant_items()
	variant_custom_edit.text = variant
	if variant.is_empty():
		variant_select.select(0)
		variant_custom_edit.visible = false
		return
	for i in range(1, variant_select.item_count - 1):
		if variant_select.get_item_text(i) == variant:
			variant_select.select(i)
			variant_custom_edit.visible = false
			return
	var custom_idx := variant_select.item_count - 1
	variant_select.select(custom_idx)
	variant_custom_edit.visible = true
	variant_custom_edit.text = variant


func _get_selected_variant() -> String:
	if variant_select.selected < 0:
		return variant_custom_edit.text.strip_edges()
	if variant_select.selected == 0:
		return ""
	var custom_idx := variant_select.item_count - 1
	if variant_select.selected == custom_idx:
		return variant_custom_edit.text.strip_edges()
	return variant_select.get_item_text(variant_select.selected)


func _on_variant_item_selected(index: int) -> void:
	var custom_idx := variant_select.item_count - 1
	variant_custom_edit.visible = index == custom_idx
	if index == custom_idx:
		variant_custom_edit.grab_focus()


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
	var skill := _get_selected_skill()
	if skill.is_empty():
		return
	_add_skill_row(skill)
	skill_input.clear()


func _get_selected_skill() -> String:
	if skill_select.selected <= 0:
		return skill_input.text.strip_edges()
	var custom_idx := SkillCatalog.skills.size() + 1
	if skill_select.selected == custom_idx:
		return skill_input.text.strip_edges()
	return skill_select.get_item_text(skill_select.selected)


func _on_skill_item_selected(index: int) -> void:
	var custom_idx := SkillCatalog.skills.size() + 1
	if index == custom_idx:
		skill_input.visible = true
		skill_input.grab_focus()
		return
	if index > 0:
		_add_skill_row(skill_select.get_item_text(index))
		skill_select.select(0)


func _on_refresh_skills_pressed() -> void:
	SkillCatalog.refresh(_project_path)


func _on_skills_loaded() -> void:
	var previous := skill_select.selected
	skill_select.clear()
	skill_select.add_item("Pick a skill...", 0)
	for s in SkillCatalog.skills:
		skill_select.add_item(s)
	skill_select.add_item("Custom...", -1)
	if previous > 0:
		skill_select.select(previous)


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


func _refresh_animation_rows() -> void:
	for child in anim_box.get_children():
		child.queue_free()
	for state in AgentProfile.ANIMATION_STATES:
		anim_box.add_child(_build_anim_row(state))


func _build_anim_row(state: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 32)

	var state_label := Label.new()
	state_label.text = state
	state_label.custom_minimum_size = Vector2(90, 0)
	state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(state_label)

	var frames_option := OptionButton.new()
	frames_option.name = "FramesOption"
	frames_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frames_option.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(frames_option)

	var add_button := Button.new()
	add_button.text = "+"
	add_button.custom_minimum_size = Vector2(30, 0)
	add_button.pressed.connect(_on_anim_add_pressed.bind(state))
	row.add_child(add_button)

	var fps_option := OptionButton.new()
	fps_option.name = "FpsOption"
	fps_option.custom_minimum_size = Vector2(56, 0)
	for fps in FPS_OPTIONS:
		fps_option.add_item("%d fps" % fps)
	fps_option.item_selected.connect(_on_anim_fps_selected.bind(state))
	row.add_child(fps_option)

	var clear_button := Button.new()
	clear_button.text = "x"
	clear_button.custom_minimum_size = Vector2(28, 0)
	clear_button.pressed.connect(_on_anim_clear_pressed.bind(state))
	row.add_child(clear_button)

	var spec: Dictionary = _animations.get(state, {})
	var frames: Array = spec.get("frames", [])
	if frames.is_empty():
		frames_option.add_item("placeholder (no frames)", 0)
		frames_option.disabled = true
	else:
		for i in frames.size():
			var file_name := String(frames[i]).get_file()
			frames_option.add_item("Frame %d: %s" % [i + 1, file_name], i)
	fps_option.select(maxi(0, FPS_OPTIONS.find(int(spec.get("fps", 8.0)))))
	return row


func _on_anim_add_pressed(state: String) -> void:
	_anim_dialog_state = state
	anim_dialog.popup_centered_ratio(0.6)


func _on_anim_clear_pressed(state: String) -> void:
	_animations.erase(state)
	_refresh_animation_rows()


func _on_anim_fps_selected(index: int, state: String) -> void:
	var spec: Dictionary = _animations.get(state, {})
	spec["fps"] = float(FPS_OPTIONS[index])
	_animations[state] = spec


func _on_anim_folder_selected(path: String) -> void:
	var state := _anim_dialog_state
	if state.is_empty():
		return
	var spec: Dictionary = _animations.get(state, {"fps": 8.0})
	var files := _collect_image_files(path)
	for f in files:
		_append_frame(spec, f)
	_animations[state] = spec
	_refresh_animation_rows()


func _on_anim_files_selected(paths: PackedStringArray) -> void:
	var state := _anim_dialog_state
	if state.is_empty():
		return
	var spec: Dictionary = _animations.get(state, {"fps": 8.0})
	for f in paths:
		_append_frame(spec, f)
	_animations[state] = spec
	_refresh_animation_rows()


func _append_frame(spec: Dictionary, path: String) -> void:
	var frames: Array = spec.get("frames", [])
	if not frames.has(path):
		frames.append(path)
	spec["frames"] = frames


func _collect_image_files(path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	var files := dir.get_files()
	files.sort()
	for f in files:
		if f.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
			out.append(path.path_join(f))
	return out


func _on_project_selected(path: String) -> void:
	_project_path = path
	_update_project_label()


func _on_project_path_submitted(text: String) -> void:
	var path := text.strip_edges()
	if path.is_empty():
		_project_path = ""
		_update_project_label()
		return
	var expanded := path
	if path.begins_with("~"):
		expanded = OS.get_environment("HOME").path_join(path.substr(1).trim_prefix("/"))
	if not expanded.begins_with("res://") and not DirAccess.dir_exists_absolute(expanded):
		push_warning("Invalid folder path: %s" % path)
		return
	_project_path = path
	_update_project_label()


func _update_project_label() -> void:
	project_path_edit.text = _project_path
	project_path_edit.tooltip_text = _project_path
	_refresh_opencode_agents()


func _on_save_pressed() -> void:
	if not _agent_selection_valid:
		return
	var agent_name: String = name_edit.text.strip_edges()
	if agent_name.is_empty():
		EventBus.agent_output.emit("", "[error] Agent name is required")
		name_edit.grab_focus()
		return
	var model := _get_selected_model()
	var variant := _get_selected_variant()
	var profile: AgentProfile
	if not _editing_id.is_empty() and ProfileStore.profiles.has(_editing_id):
		profile = ProfileStore.profiles[_editing_id]
		profile.name = agent_name
		profile.model = model
		profile.model_variant = variant
		profile.opencode_agent = _selected_opencode_agent
		profile.personality = personality_edit.text
		profile.skills = _collect_skills()
		profile.project = _project_path
		profile.animations = _animations.duplicate(true)
	else:
		profile = AgentProfile.new()
		profile.ensure_id()
		profile.name = agent_name
		profile.model = model
		profile.model_variant = variant
		profile.opencode_agent = _selected_opencode_agent
		profile.personality = personality_edit.text
		profile.skills = _collect_skills()
		profile.project = _project_path
		profile.animations = _animations.duplicate(true)
		profile.created_at = Time.get_unix_time_from_system()
	ProfileStore.save_profile(profile)
	EventBus.profile_saved.emit(profile)
	visible = false


func _on_cancel_pressed() -> void:
	visible = false
