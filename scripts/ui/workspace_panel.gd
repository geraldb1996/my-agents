class_name WorkspacePanel
extends PanelContainer

@onready var project_path_edit: LineEdit = %ProjectPathEdit
@onready var task_edit: LineEdit = %TaskEdit
@onready var start_stop_button: Button = %StartStopButton
@onready var state_label: Label = %StateLabel
@onready var character_view: CharacterView = %CharacterView
@onready var files_label: RichTextLabel = %FilesLabel
@onready var git_label: Label = %GitLabel
@onready var output_log: RichTextLabel = %OutputLog
@onready var output_dialog: Window = %OutputDialog
@onready var expanded_output_log: RichTextLabel = %ExpandedOutputLog
@onready var temp_skill_select: OptionButton = %TempSkillSelect
@onready var temp_skills_box: VBoxContainer = %TempSkillsBox
@onready var temp_skill_dialog: TempSkillDialog = %TempSkillDialog
@onready var project_dialog: FileDialog = %ProjectDialog
@onready var agent_name_label: Label = %AgentNameLabel
@onready var skill_source_option: OptionButton = %SkillSourceOption

var _current_id: String = ""
var _skills_project: String = ""
var _last_git_files: Array = []


func _ready() -> void:
	%ExpandOutputButton.pressed.connect(_on_expand_output)
	output_dialog.close_requested.connect(output_dialog.hide)
	EventBus.agent_output_updated.connect(_on_output_updated)
	%SendButton.pressed.connect(_on_send_pressed)
	%SelectProjectButton.pressed.connect(_on_select_project_pressed)
	%StartStopButton.pressed.connect(_on_start_stop_pressed)
	%TempSkillButton.pressed.connect(_on_temp_skill_pressed)
	%ClearTempSkillsButton.pressed.connect(_on_clear_temp_skills_pressed)
	project_dialog.dir_selected.connect(_on_project_selected)
	project_path_edit.text_submitted.connect(_on_project_path_submitted)
	EventBus.agent_selected.connect(_on_agent_selected)
	EventBus.agent_state_changed.connect(_on_state_changed)
	EventBus.agent_output.connect(_on_output)
	EventBus.agent_files_changed.connect(_on_files_changed)
	EventBus.agent_files_status.connect(_on_files_status)
	EventBus.agent_git_status.connect(_on_git_status)
	EventBus.profile_deleted.connect(_on_profile_deleted)
	EventBus.temp_skills_changed.connect(_on_temp_skills_changed)
	skill_source_option.item_selected.connect(_on_skill_source_selected)
	temp_skill_select.item_selected.connect(_on_temp_skill_selected)
	temp_skill_dialog.skill_added.connect(_on_temp_skill_added)
	SkillCatalog.skills_loaded.connect(_on_skills_loaded)
	_populate_skill_source_options()
	clear()


func clear() -> void:
	_current_id = ""
	_last_git_files = []
	agent_name_label.text = "No agent selected"
	project_path_edit.text = ""
	state_label.text = "--"
	git_label.text = "--"
	files_label.text = "--"
	task_edit.text = ""
	output_log.text = ""
	expanded_output_log.text = ""
	output_dialog.hide()
	start_stop_button.text = "Start"
	start_stop_button.disabled = true
	%SendButton.disabled = true
	%SelectProjectButton.disabled = true
	character_view.set_profile(null)
	character_view.set_state("offline")
	_clear_temp_skill_rows()


func _on_agent_selected(profile: AgentProfile) -> void:
	_current_id = profile.id
	agent_name_label.text = profile.name
	project_path_edit.text = profile.project
	project_path_edit.tooltip_text = profile.project
	character_view.set_profile(profile)
	start_stop_button.disabled = false
	%SelectProjectButton.disabled = false
	%SendButton.disabled = profile.project.is_empty()
	var session := AgentManager.get_session(profile.id)
	state_label.text = str(session.get("state", "offline")).capitalize()
	output_log.text = ""
	expanded_output_log.text = ""
	output_dialog.title = "Output — " + profile.name
	var file_status := AgentManager.get_file_status(profile.id)
	if not file_status.is_empty():
		_render_files_status(file_status)
	for line in AgentManager.get_output_history(profile.id):
		_append_output(str(line))
	var project := profile.project
	if _skills_project != project:
		_skills_project = project
		SkillCatalog.refresh(project)
	else:
		_populate_temp_skill_select()
	_refresh_temp_skills()
	AgentManager.queue_git_refresh(profile.id, 0.3)


func _on_state_changed(agent_id: String, state: String) -> void:
	if agent_id != _current_id:
		return
	state_label.text = state.capitalize()
	state_label.modulate = CharacterAvatar.STATE_COLORS.get(state, Color.WHITE).lerp(Color(1, 1, 1), 0.4)
	character_view.set_state(state)
	var active := state in ["thinking", "working", "reading", "coding", "terminal", "searching", "question", "approval", "success"]
	start_stop_button.text = "Stop" if active else "Start"
	start_stop_button.disabled = false


func _on_output(agent_id: String, line: String) -> void:
	if agent_id != _current_id:
		return
	_append_output(line)
	if AgentManager.get_output_history(_current_id).size() == 400:
		_on_output_updated(_current_id)


func _append_output(line: String) -> void:
	for log_view in [output_log, expanded_output_log]:
		log_view.add_text(line + "\n")


func _on_output_updated(agent_id: String) -> void:
	if agent_id != _current_id:
		return
	var text := "\n".join(AgentManager.get_output_history(agent_id)) + "\n"
	for log_view in [output_log, expanded_output_log]:
		var bar: VScrollBar = log_view.get_v_scroll_bar()
		var position := bar.value
		var following := position >= bar.max_value - bar.page - 1.0
		log_view.text = text
		_restore_output_scroll.call_deferred(log_view, position, following)


func _restore_output_scroll(log_view: RichTextLabel, position: float, following: bool) -> void:
	var bar := log_view.get_v_scroll_bar()
	bar.value = bar.max_value if following else position


func _on_expand_output() -> void:
	output_dialog.popup_centered_ratio(0.85)


func _on_files_changed(agent_id: String, files: Array) -> void:
	if agent_id != _current_id:
		return
	_last_git_files = files
	if not AgentManager.get_file_status(agent_id).is_empty():
		return
	if files.is_empty():
		files_label.text = "No modified files"
	else:
		files_label.text = "\n".join(files)


func _on_files_status(agent_id: String, files: Dictionary) -> void:
	if agent_id != _current_id:
		return
	_render_files_status(files)


func _render_files_status(files: Dictionary) -> void:
	if files.is_empty():
		files_label.text = "No files touched"
		return
	var lines: Array[String] = []
	for path in files:
		var op := str(files[path])
		var color: Color = AgentManager._file_op_colors.get(op, Color.WHITE)
		lines.append("[color=#%s]%s[/color] %s" % [color.to_html(false), op, path])
	files_label.text = "\n".join(lines)
	files_label.tooltip_text = _status_legend()


func _status_legend() -> String:
	return "R (white): read - D (red): deleted - C (blue): created - M (yellow): modified"


func _on_git_status(agent_id: String, branch: String, status: String) -> void:
	if agent_id != _current_id:
		return
	git_label.text = "Branch: %s" % branch if not branch.is_empty() else "Not a git repo"
	git_label.tooltip_text = status


func _on_profile_deleted(agent_id: String) -> void:
	if agent_id == _current_id:
		clear()


func _on_send_pressed() -> void:
	if _current_id.is_empty():
		return
	var task := task_edit.text.strip_edges()
	if task.is_empty():
		return
	if AgentManager.send_task(_current_id, task) == AgentManager.TASK_OK:
		task_edit.clear()


func _on_start_stop_pressed() -> void:
	if _current_id.is_empty():
		return
	var state := str(AgentManager.get_session(_current_id).get("state", "offline"))
	if state in ["offline", "idle", "error"]:
		AgentManager.start_agent(_current_id)
	else:
		AgentManager.stop_agent(_current_id)


func _on_select_project_pressed() -> void:
	if _current_id.is_empty():
		return
	project_dialog.popup_centered_ratio(0.5)


func _on_project_selected(path: String) -> void:
	project_path_edit.text = path
	_apply_project(path)


func _on_project_path_submitted(text: String) -> void:
	_apply_project(text.strip_edges())


func _apply_project(path: String) -> void:
	if _current_id.is_empty():
		return
	var profile := ProfileStore.get_profile(_current_id)
	if profile == null:
		return
	if not path.is_empty() and not _is_valid_dir(path):
		EventBus.agent_output.emit(_current_id, "[error] Invalid folder path: %s" % path)
		project_path_edit.text = profile.project
		return
	profile.project = path
	ProfileStore.save_profile(profile)
	project_path_edit.text = path
	project_path_edit.tooltip_text = path
	%SendButton.disabled = path.is_empty()
	_skills_project = path
	SkillCatalog.refresh(path)
	AgentManager.queue_git_refresh(_current_id, 0.3)
	EventBus.agent_output.emit(_current_id, "[project] set to %s" % path)


func _is_valid_dir(path: String) -> bool:
	var expanded := path
	if path.begins_with("~"):
		expanded = OS.get_environment("HOME").path_join(path.substr(1).trim_prefix("/"))
	if expanded.begins_with("res://"):
		return true
	return DirAccess.dir_exists_absolute(expanded)


func _populate_skill_source_options() -> void:
	skill_source_option.clear()
	skill_source_option.add_item("All Skills", 0)
	skill_source_option.add_item("Global", 1)
	skill_source_option.add_item("Local", 2)


func _current_skill_source() -> String:
	match skill_source_option.selected:
		1:
			return "global"
		2:
			return "local"
		_:
			return "all"


func _on_skill_source_selected(_index: int) -> void:
	_populate_temp_skill_select()


func _on_skills_loaded() -> void:
	if _current_id.is_empty():
		return
	_populate_temp_skill_select()
	_refresh_temp_skills()


func _populate_temp_skill_select() -> void:
	temp_skill_select.clear()
	temp_skill_select.add_item("Installed skills...", 0)
	for skill in SkillCatalog.get_skills_by_source(_current_skill_source()):
		temp_skill_select.add_item(skill)
	temp_skill_select.select(0)


func _on_temp_skill_selected(index: int) -> void:
	if index <= 0 or _current_id.is_empty():
		return
	var skill := temp_skill_select.get_item_text(index)
	AgentManager.add_temp_skill(_current_id, skill, SkillCatalog.read_skill(skill), SkillCatalog.get_skill_source(skill))
	temp_skill_select.select(0)


func _on_temp_skill_pressed() -> void:
	if _current_id.is_empty():
		return
	temp_skill_dialog.open()


func _on_temp_skill_added(entry: Dictionary) -> void:
	if _current_id.is_empty():
		return
	AgentManager.add_temp_skill(
		_current_id,
		str(entry.get("name", "")),
		str(entry.get("content", "")),
		str(entry.get("source", ""))
	)


func _on_temp_skills_changed(agent_id: String) -> void:
	if agent_id == _current_id:
		_refresh_temp_skills()


func _on_clear_temp_skills_pressed() -> void:
	if _current_id.is_empty():
		return
	AgentManager.clear_temp_skills(_current_id)


func _clear_temp_skill_rows() -> void:
	for child in temp_skills_box.get_children():
		child.queue_free()
	%ClearTempSkillsButton.disabled = true


func _refresh_temp_skills() -> void:
	_clear_temp_skill_rows()
	var profile := ProfileStore.get_profile(_current_id)
	if profile == null:
		return
	for i in profile.temp_skills.size():
		temp_skills_box.add_child(_build_temp_skill_row(profile.temp_skills[i], i))
	%ClearTempSkillsButton.disabled = profile.temp_skills.is_empty()


func _build_temp_skill_row(entry: Dictionary, index: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	var name := str(entry.get("name", ""))
	var source := str(entry.get("source", ""))
	label.text = name if source.is_empty() else "%s (%s)" % [name, source]
	var content := str(entry.get("content", ""))
	label.tooltip_text = content.substr(0, 500)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(label)
	var remove := Button.new()
	remove.text = "x"
	remove.pressed.connect(_on_remove_temp_skill.bind(index))
	row.add_child(remove)
	return row


func _on_remove_temp_skill(index: int) -> void:
	if _current_id.is_empty():
		return
	AgentManager.remove_temp_skill(_current_id, index)
