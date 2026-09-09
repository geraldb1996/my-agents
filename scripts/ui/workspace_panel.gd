class_name WorkspacePanel
extends PanelContainer

@onready var project_path_edit: LineEdit = %ProjectPathEdit
@onready var task_edit: LineEdit = %TaskEdit
@onready var start_stop_button: Button = %StartStopButton
@onready var state_label: Label = %StateLabel
@onready var character_view: CharacterView = %CharacterView
@onready var files_label: Label = %FilesLabel
@onready var git_label: Label = %GitLabel
@onready var output_log: RichTextLabel = %OutputLog
@onready var output_scroll: ScrollContainer = %OutputScroll
@onready var temp_skill_edit: LineEdit = %TempSkillEdit
@onready var project_dialog: FileDialog = %ProjectDialog
@onready var agent_name_label: Label = %AgentNameLabel
@onready var skill_source_option: OptionButton = %SkillSourceOption

var _current_id: String = ""


func _ready() -> void:
	%SendButton.pressed.connect(_on_send_pressed)
	%SelectProjectButton.pressed.connect(_on_select_project_pressed)
	%StartStopButton.pressed.connect(_on_start_stop_pressed)
	%TempSkillButton.pressed.connect(_on_temp_skill_pressed)
	project_dialog.dir_selected.connect(_on_project_selected)
	project_path_edit.text_submitted.connect(_on_project_path_submitted)
	EventBus.agent_selected.connect(_on_agent_selected)
	EventBus.agent_state_changed.connect(_on_state_changed)
	EventBus.agent_output.connect(_on_output)
	EventBus.agent_files_changed.connect(_on_files_changed)
	EventBus.agent_git_status.connect(_on_git_status)
	EventBus.profile_deleted.connect(_on_profile_deleted)
	skill_source_option.item_selected.connect(_on_skill_source_selected)
	_populate_skill_source_options()
	clear()


func clear() -> void:
	_current_id = ""
	agent_name_label.text = "No agent selected"
	project_path_edit.text = ""
	state_label.text = "--"
	git_label.text = "--"
	files_label.text = "--"
	task_edit.text = ""
	output_log.clear()
	start_stop_button.text = "Start"
	start_stop_button.disabled = true
	%SendButton.disabled = true
	%SelectProjectButton.disabled = true
	character_view.set_profile(null)
	character_view.set_state("offline")


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
	output_log.clear()
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


func _append_output(line: String) -> void:
	output_log.append_text(line + "\n")
	if output_log.get_line_count() > 500:
		var lines := output_log.text.split("\n")
		output_log.clear()
		for i in range(maxi(0, lines.size() - 400), lines.size()):
			output_log.append_text(lines[i] + "\n")
	output_scroll.scroll_vertical = int(output_scroll.get_v_scroll_bar().max_value)


func _on_files_changed(agent_id: String, files: Array) -> void:
	if agent_id != _current_id:
		return
	if files.is_empty():
		files_label.text = "No modified files"
	else:
		files_label.text = "\n".join(files)


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


func _on_skill_source_selected(index: int) -> void:
	pass


func _on_temp_skill_pressed() -> void:
	if _current_id.is_empty():
		return
	var skill := temp_skill_edit.text.strip_edges()
	if skill.is_empty():
		return
	AgentManager.add_temp_skill(_current_id, skill)
	temp_skill_edit.clear()