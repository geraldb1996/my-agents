class_name WorkspacePanel
extends PanelContainer

@onready var project_path_edit: LineEdit = %ProjectPathEdit
@onready var task_edit: LineEdit = %TaskEdit
@onready var start_stop_button: Button = %StartStopButton
@onready var state_label: Label = %StateLabel
@onready var character_view: CharacterView = %CharacterView
@onready var files_label: RichTextLabel = %FilesLabel
@onready var git_label: Label = %GitLabel
@onready var git_branches: HFlowContainer = %GitBranches
@onready var new_branch_dialog: Window = %NewBranchDialog
@onready var new_branch_edit: LineEdit = %NewBranchEdit
@onready var new_branch_error: Label = %NewBranchError
@onready var output_log: RichTextLabel = %OutputLog
@onready var output_dialog: Window = %OutputDialog
@onready var expanded_output_log: RichTextLabel = %ExpandedOutputLog
@onready var temp_skill_select: OptionButton = %TempSkillSelect
@onready var temp_skills_box: VBoxContainer = %TempSkillsBox
@onready var temp_skill_dialog: TempSkillDialog = %TempSkillDialog
@onready var project_dialog: FileDialog = %ProjectDialog
@onready var project_picker_dialog: Window = %ProjectPickerDialog
@onready var project_folder_list: VBoxContainer = %ProjectFolderList
@onready var agent_name_label: Label = %AgentNameLabel
@onready var skill_source_option: OptionButton = %SkillSourceOption
@onready var task_label: RichTextLabel = %TaskLabel
@onready var info_tabs: TabContainer = %InfoTabs
@onready var settings_dialog: SystemSettingsDialog = %SystemSettingsDialog
@onready var session_manager_dialog: Window = %SessionManagerDialog
@onready var session_list: VBoxContainer = %SessionList

const TASK_PLACEHOLDER := "(No task assigned)"

var _current_id: String = ""
var _skills_project: String = ""
var _last_git_files: Array = []
var _previous_info_tab: int = 0
var _displayed_task: String = ""
var _last_branch: String = ""
var _has_git_status: bool = false
var _output_refresh_pending := false


func _ready() -> void:
	info_tabs.tab_changed.connect(_on_info_tab_changed)
	info_tabs.set_tab_tooltip(4, "System Settings")
	%ExpandOutputButton.pressed.connect(_on_expand_output)
	%ManageSessionsButton.pressed.connect(_on_manage_sessions_pressed)
	%CloseSessionManagerButton.pressed.connect(session_manager_dialog.hide)
	session_manager_dialog.close_requested.connect(session_manager_dialog.hide)
	output_dialog.close_requested.connect(output_dialog.hide)
	EventBus.agent_output_updated.connect(_on_output_updated)
	%SendButton.pressed.connect(_on_send_pressed)
	%SelectProjectButton.pressed.connect(_on_select_project_pressed)
	%BrowseProjectButton.pressed.connect(_on_browse_project_pressed)
	%CloseProjectPickerButton.pressed.connect(project_picker_dialog.hide)
	%NewBranchButton.pressed.connect(_on_new_branch_pressed)
	%CreateBranchButton.pressed.connect(_on_create_branch_pressed)
	%CancelNewBranchButton.pressed.connect(new_branch_dialog.hide)
	%StartStopButton.pressed.connect(_on_start_stop_pressed)
	%TempSkillButton.pressed.connect(_on_temp_skill_pressed)
	%ClearTempSkillsButton.pressed.connect(_on_clear_temp_skills_pressed)
	project_dialog.dir_selected.connect(_on_project_selected)
	project_picker_dialog.close_requested.connect(project_picker_dialog.hide)
	new_branch_dialog.close_requested.connect(new_branch_dialog.hide)
	project_path_edit.text_submitted.connect(_on_project_path_submitted)
	EventBus.agent_selected.connect(_on_agent_selected)
	EventBus.agent_state_changed.connect(_on_state_changed)
	EventBus.agent_output.connect(_on_output)
	EventBus.agent_files_changed.connect(_on_files_changed)
	EventBus.agent_files_status.connect(_on_files_status)
	EventBus.agent_git_status.connect(_on_git_status)
	EventBus.profile_deleted.connect(_on_profile_deleted)
	EventBus.temp_skills_changed.connect(_on_temp_skills_changed)
	EventBus.agent_task_updated.connect(_on_task_updated)
	EventBus.session_titles_loaded.connect(_on_session_titles_loaded)
	skill_source_option.item_selected.connect(_on_skill_source_selected)
	temp_skill_select.item_selected.connect(_on_temp_skill_selected)
	temp_skill_dialog.skill_added.connect(_on_temp_skill_added)
	SkillCatalog.skills_loaded.connect(_on_skills_loaded)
	_populate_skill_source_options()
	clear()
	_refresh_translations()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_translations()


func _refresh_translations() -> void:
	for index in 4:
		info_tabs.set_tab_title(index, tr(["Task", "Files", "Git", "Output"][index]))
	info_tabs.set_tab_tooltip(4, tr("System Settings"))
	_update_task_label(_displayed_task)
	files_label.tooltip_text = _status_legend()
	if _current_id.is_empty():
		agent_name_label.text = tr("No agent selected")
	else:
		var profile := ProfileStore.get_profile(_current_id)
		if profile != null:
			output_dialog.title = tr("Output — %s") % profile.name
		var files := AgentManager.get_file_status(_current_id)
		if not files.is_empty():
			_render_files_status(files)
		elif _last_git_files.is_empty():
			files_label.text = tr("No files touched")
	if _has_git_status:
		git_label.text = tr("Branch: %s") % _last_branch if not _last_branch.is_empty() else tr("Not a git repo")


func _on_info_tab_changed(index: int) -> void:
	if index == 4:
		settings_dialog.open()
		info_tabs.current_tab = _previous_info_tab
	else:
		_previous_info_tab = index


func clear() -> void:
	_current_id = ""
	_last_git_files = []
	_last_branch = ""
	_has_git_status = false
	agent_name_label.text = tr("No agent selected")
	project_path_edit.text = ""
	state_label.text = "--"
	git_label.text = "--"
	files_label.text = "--"
	task_edit.text = ""
	_update_task_label("")
	output_log.text = ""
	expanded_output_log.text = ""
	output_dialog.hide()
	project_picker_dialog.hide()
	new_branch_dialog.hide()
	_clear_git_branches()
	start_stop_button.text = "Start"
	start_stop_button.disabled = true
	%SendButton.disabled = true
	%SelectProjectButton.disabled = true
	character_view.set_profile(null)
	character_view.set_state("offline")
	_clear_temp_skill_rows()


func _on_agent_selected(profile: AgentProfile) -> void:
	_current_id = profile.id
	_has_git_status = false
	_last_git_files = []
	agent_name_label.text = profile.name
	project_path_edit.text = profile.project
	project_path_edit.tooltip_text = profile.project
	character_view.set_profile(profile)
	start_stop_button.disabled = false
	%SelectProjectButton.disabled = false
	%SendButton.disabled = profile.project.is_empty()
	var session := AgentManager.get_session(profile.id)
	state_label.text = str(session.get("state", "offline")).capitalize()
	_update_task_label(str(session.get("task", "")))
	output_log.text = ""
	expanded_output_log.text = ""
	output_dialog.title = tr("Output — %s") % profile.name
	var file_status := AgentManager.get_file_status(profile.id)
	if not file_status.is_empty():
		_render_files_status(file_status)
	for line in AgentManager.get_output_history(profile.id):
		_append_output(str(line))
	var project := profile.project
	if _skills_project != project:
		_skills_project = project
		SkillCatalog.refresh_async(project)
	else:
		_populate_temp_skill_select()
	_refresh_temp_skills()
	AgentManager.queue_git_refresh(profile.id, 0.3)
	_refresh_git_branches()


func _on_state_changed(agent_id: String, state: String) -> void:
	if agent_id != _current_id:
		return
	state_label.text = state.capitalize()
	state_label.modulate = CharacterAvatar.STATE_COLORS.get(state, Color.WHITE).lerp(ThemeManager.color("text"), 0.25)
	character_view.set_state(state)
	var active := state in ["thinking", "working", "reading", "coding", "terminal", "searching", "question", "approval", "success"]
	start_stop_button.text = "Stop" if active else "Start"
	start_stop_button.disabled = false


func _on_task_updated(agent_id: String, task: String) -> void:
	if agent_id != _current_id:
		return
	_update_task_label(task)


func _update_task_label(task: String) -> void:
	_displayed_task = task
	task_label.text = task if not task.is_empty() else tr(TASK_PLACEHOLDER)


func _on_output(agent_id: String, line: String) -> void:
	if agent_id != _current_id:
		return
	_append_output(line)
	if AgentManager.get_output_history(_current_id).size() == 400:
		_on_output_updated(_current_id)


func _append_output(line: String) -> void:
	output_log.add_text(line + "\n")
	if output_dialog.visible:
		expanded_output_log.add_text(line + "\n")


func _on_output_updated(agent_id: String) -> void:
	if agent_id != _current_id:
		return
	if _output_refresh_pending:
		return
	_output_refresh_pending = true
	_refresh_output.call_deferred(agent_id)


func _refresh_output(agent_id: String) -> void:
	_output_refresh_pending = false
	if agent_id != _current_id:
		return
	var text := "\n".join(AgentManager.get_output_history(agent_id)) + "\n"
	var log_views: Array[RichTextLabel] = [output_log]
	if output_dialog.visible:
		log_views.append(expanded_output_log)
	for log_view in log_views:
		var bar: VScrollBar = log_view.get_v_scroll_bar()
		var position := bar.value
		var following := position >= bar.max_value - bar.page - 1.0
		log_view.text = text
		_restore_output_scroll.call_deferred(log_view, position, following)


func _restore_output_scroll(log_view: RichTextLabel, position: float, following: bool) -> void:
	var bar := log_view.get_v_scroll_bar()
	bar.value = bar.max_value if following else position


func _on_expand_output() -> void:
	expanded_output_log.text = output_log.text
	output_dialog.popup_centered_ratio(0.85)


func _on_manage_sessions_pressed() -> void:
	_refresh_session_list()
	session_manager_dialog.popup_centered_ratio(0.8)


func _refresh_session_list() -> void:
	for child in session_list.get_children():
		child.queue_free()
	var has_sessions := false
	for profile_id in ProfileStore.profiles:
		var profile := ProfileStore.get_profile(profile_id)
		if profile == null:
			continue
		var active := AgentManager.get_session(profile.id)
		var active_id := str(active.get("opencode_session", ""))
		if not active_id.is_empty():
			has_sessions = true
			var active_title := AgentManager.get_cached_session_title(active_id, profile.project)
			if active_title.is_empty():
				active_title = tr("Session %s") % active_id.right(6)
			session_list.add_child(_build_session_row(profile, active_id, active_title, int(active.get("context_tokens", 0)), float(active.get("context_percent", 0.0)), true))
		for entry in ProfileStore.load_session_history(profile.id):
			if entry is not Dictionary:
				continue
			var session_id := str(entry.get("opencode_session", ""))
			if session_id.is_empty():
				continue
			has_sessions = true
			var title := str(entry.get("title", ""))
			if title.is_empty():
				title = AgentManager.get_cached_session_title(session_id, profile.project)
			if title.is_empty():
				title = tr("Session %s") % session_id.right(6)
			session_list.add_child(_build_session_row(profile, session_id, title, int(entry.get("context_tokens", 0)), float(entry.get("context_percent", 0.0)), false))
	if not has_sessions:
		var empty := Label.new()
		empty.text = tr("No sessions available")
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		session_list.add_child(empty)


func _on_session_titles_loaded(_project: String) -> void:
	if session_manager_dialog.visible:
		_refresh_session_list()


func _build_session_row(profile: AgentProfile, session_id: String, title: String, context_tokens: int, context_percent: float, is_active: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var agent := Label.new()
	agent.text = profile.name
	agent.custom_minimum_size.x = 105
	row.add_child(agent)
	var name := Label.new()
	name.text = title
	name.tooltip_text = session_id
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	var context := Label.new()
	context.text = "%d" % context_tokens
	context.custom_minimum_size.x = 100
	row.add_child(context)
	var percent := Label.new()
	percent.text = "%.0f%%" % context_percent
	percent.custom_minimum_size.x = 55
	row.add_child(percent)
	var delete := Button.new()
	delete.text = tr("Delete")
	delete.tooltip_text = tr("Delete active session") if is_active else tr("Delete archived session")
	delete.pressed.connect(_on_delete_managed_session.bind(profile.id, session_id, is_active))
	row.add_child(delete)
	return row


func _on_delete_managed_session(agent_id: String, session_id: String, is_active: bool) -> void:
	if is_active:
		AgentManager.delete_session(agent_id)
	else:
		AgentManager.delete_archived_session(agent_id, session_id)
	_refresh_session_list()


func _on_files_changed(agent_id: String, files: Array) -> void:
	if agent_id != _current_id:
		return
	_last_git_files = files
	if not AgentManager.get_file_status(agent_id).is_empty():
		return
	if files.is_empty():
		files_label.text = tr("No modified files")
	else:
		files_label.text = "\n".join(files)


func _on_files_status(agent_id: String, files: Dictionary) -> void:
	if agent_id != _current_id:
		return
	_render_files_status(files)


func _render_files_status(files: Dictionary) -> void:
	if files.is_empty():
		files_label.text = tr("No files touched")
		return
	var lines: Array[String] = []
	for path in files:
		var op := str(files[path])
		var color := _file_op_color(op)
		lines.append("[color=#%s](%s) %s[/color]" % [color.to_html(false), op, path])
	files_label.text = "\n".join(lines)
	files_label.tooltip_text = _status_legend()


func _file_op_color(op: String) -> Color:
	match op:
		AgentManager.FILE_OP_DELETED:
			return ThemeManager.color("deleted")
		AgentManager.FILE_OP_CREATED:
			return ThemeManager.color("created")
		AgentManager.FILE_OP_MODIFIED:
			return ThemeManager.color("modified")
		_:
			return ThemeManager.color("read")


func _status_legend() -> String:
	return tr("(R) (white): read - (D) (red): deleted - (C) (blue): created - (M) (yellow): modified")


func _on_git_status(agent_id: String, branch: String, status: String) -> void:
	if agent_id != _current_id:
		return
	_last_branch = branch
	_has_git_status = true
	git_label.text = tr("Branch: %s") % branch if not branch.is_empty() else tr("Not a git repo")
	git_label.tooltip_text = status
	_refresh_git_branches()


func _clear_git_branches() -> void:
	for child in git_branches.get_children():
		child.queue_free()


func _refresh_git_branches() -> void:
	_clear_git_branches()
	if _current_id.is_empty():
		return
	var profile := ProfileStore.get_profile(_current_id)
	if profile == null or profile.project.is_empty():
		return
	var output: Array = []
	if OS.execute("git", ["-C", profile.project, "branch", "--format=%(refname:short)"], output, true, false) != OK:
		return
	for branch in "\n".join(output).split("\n", false):
		var branch_name := branch.strip_edges()
		if branch_name.is_empty():
			continue
		var button := Button.new()
		button.text = branch_name
		button.disabled = branch_name == _last_branch
		button.tooltip_text = tr("Current branch") if button.disabled else tr("Switch to this branch")
		button.pressed.connect(_on_git_branch_pressed.bind(branch_name))
		git_branches.add_child(button)


func _on_git_branch_pressed(branch: String) -> void:
	_run_git_command(["switch", "--", branch], tr("switch to branch"))


func _on_new_branch_pressed() -> void:
	if _current_id.is_empty() or _last_branch.is_empty():
		return
	new_branch_edit.clear()
	new_branch_error.text = ""
	new_branch_dialog.popup_centered(Vector2i(420, 180))
	new_branch_edit.grab_focus()


func _on_create_branch_pressed() -> void:
	var branch := new_branch_edit.text.strip_edges()
	if branch.is_empty():
		new_branch_error.text = tr("Enter a branch name")
		return
	if _run_git_command(["switch", "-c", branch], tr("create branch")):
		new_branch_dialog.hide()


func _run_git_command(arguments: Array[String], action: String) -> bool:
	if _current_id.is_empty():
		return false
	var profile := ProfileStore.get_profile(_current_id)
	if profile == null or profile.project.is_empty():
		return false
	var output: Array = []
	var result := OS.execute("git", ["-C", profile.project] + arguments, output, true, false)
	var details := "\n".join(output).strip_edges()
	if result != OK:
		EventBus.agent_output.emit(_current_id, "[git] Could not %s: %s" % [action, details if not details.is_empty() else tr("unknown error")])
		return false
	AgentManager.queue_git_refresh(_current_id, 0.0)
	_refresh_git_branches()
	return true


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
	_refresh_project_folder_list()
	project_picker_dialog.popup_centered(Vector2i(620, 440))


func _on_browse_project_pressed() -> void:
	project_dialog.popup_centered_ratio(0.5)


func _refresh_project_folder_list() -> void:
	for child in project_folder_list.get_children():
		child.queue_free()
	if SystemSettings.project_folders.is_empty():
		var empty := Label.new()
		empty.text = tr("No saved projects yet")
		empty.theme_type_variation = &"MutedLabel"
		project_folder_list.add_child(empty)
		return
	for path in SystemSettings.project_folders:
		project_folder_list.add_child(_build_project_folder_row(path))


func _build_project_folder_row(path: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var select := Button.new()
	select.text = path
	select.tooltip_text = path
	select.alignment = HORIZONTAL_ALIGNMENT_LEFT
	select.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select.pressed.connect(_on_saved_project_selected.bind(path))
	row.add_child(select)
	var remove := Button.new()
	remove.text = tr("Remove")
	remove.tooltip_text = tr("Remove saved project")
	remove.pressed.connect(_on_saved_project_removed.bind(path))
	row.add_child(remove)
	return row


func _on_saved_project_selected(path: String) -> void:
	_apply_project(path)
	project_picker_dialog.hide()


func _on_saved_project_removed(path: String) -> void:
	SystemSettings.remove_project_folder(path)
	_refresh_project_folder_list()


func _on_project_selected(path: String) -> void:
	SystemSettings.add_project_folder(path)
	project_path_edit.text = path
	_apply_project(path)
	project_picker_dialog.hide()


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
	SkillCatalog.refresh_async(path)
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
