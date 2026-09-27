extends Node

signal chat_message_persisted(message: Dictionary)

const TOOL_STATES := {
	"bash": "terminal",
	"edit": "coding",
	"multi_edit": "coding",
	"patch": "coding",
	"apply_patch": "coding",
	"write": "coding",
	"read": "reading",
	"grep": "searching",
	"glob": "searching",
	"search": "searching",
	"websearch": "searching",
	"web_fetch": "searching",
	"ripgrep_search": "searching",
	"list_files": "searching",
	"ask_user": "question",
}

const TASK_OK := 0
const TASK_NO_PROJECT := 1
const TASK_BUSY := 2
const TASK_LAUNCH_FAILED := 3

const ACTIVE_STATES := ["thinking", "working", "reading", "coding", "terminal", "searching", "question", "approval"]

var sessions: Dictionary = {}
var selected_agent_id: String = ""

var _runners: Dictionary = {}
var _output_history: Dictionary = {}
var _last_reasoning_part: Dictionary = {}
var _session_titles: Dictionary = {}
var _session_titles_loaded_at: Dictionary = {}
var _session_title_threads: Dictionary = {}
var _session_titles_queue: Array[String] = []
var _session_titles_inflight: String = ""
var _pending_permissions: Dictionary = {}
var _pending_questions: Dictionary = {}
var _last_error: Dictionary = {}
var _git_refresh_queue: Dictionary = {}
var _git_timers: Dictionary = {}
var _git_threads: Dictionary = {}
var _file_status: Dictionary = {}

const CHAT_MAX_DEPTH := 3
var _chat_inbox: Dictionary = {}
var _chat_depth: Dictionary = {}
var _relay_seen: Dictionary = {}

const FILE_OP_READ := "R"
const FILE_OP_DELETED := "D"
const FILE_OP_CREATED := "C"
const FILE_OP_MODIFIED := "M"


func _ready() -> void:
	for profile_id in ProfileStore.profiles:
		sessions[profile_id] = ProfileStore.load_session(profile_id)
		if not sessions[profile_id].has("state"):
			sessions[profile_id]["state"] = "offline"
	_prewarm_session_titles()


func _process(_delta: float) -> void:
	for agent_id in _runners.keys():
		(_runners[agent_id] as OpenCodeRunner).poll()
	_apply_git_refresh()


func _exit_tree() -> void:
	for project in _session_title_threads.keys():
		var thread: Thread = _session_title_threads[project]
		if thread.is_started():
			thread.wait_to_finish()
	_session_title_threads.clear()
	_session_titles_queue.clear()
	_session_titles_inflight = ""


func get_profile(agent_id: String) -> AgentProfile:
	return ProfileStore.get_profile(agent_id)


func get_session(agent_id: String) -> Dictionary:
	if not sessions.has(agent_id):
		sessions[agent_id] = {}
	return sessions[agent_id]


func select_agent(agent_id: String) -> void:
	selected_agent_id = agent_id
	var profile := get_profile(agent_id)
	if profile != null:
		EventBus.agent_selected.emit(profile)


func start_agent(agent_id: String) -> void:
	var session := get_session(agent_id)
	if not session.has("opencode_session"):
		session["opencode_session"] = ""
	set_state(agent_id, "idle")
	ProfileStore.save_session(agent_id, session)
	EventBus.agent_started.emit(agent_id)


func stop_agent(agent_id: String) -> void:
	var runner: OpenCodeRunner = _runners.get(agent_id)
	if runner != null and runner.running:
		runner.stop()
	if _chat_inbox.has(agent_id):
		_chat_inbox.erase(agent_id)
		_chat_depth.erase(agent_id)
		var profile := get_profile(agent_id)
		var who := profile.name if profile != null else agent_id
		_emit_system_chat("Queued messages for %s cleared because the agent was stopped." % who)
	set_state(agent_id, "offline")
	ProfileStore.save_session(agent_id, get_session(agent_id))
	EventBus.agent_stopped.emit(agent_id)


func send_task(agent_id: String, task: String, sender_name: String = "User") -> int:
	var profile := get_profile(agent_id)
	if profile == null:
		return TASK_LAUNCH_FAILED
	if profile.project.is_empty():
		emit_chat_error(agent_id, "No project/workspace set. Select a folder first.")
		set_state(agent_id, "error")
		return TASK_NO_PROJECT
	var runner: OpenCodeRunner = _runners.get(agent_id)
	if runner != null and runner.running:
		emit_chat_error(agent_id, "Agent busy. Wait for the current task to finish.")
		return TASK_BUSY

	_file_status.erase(agent_id)
	EventBus.agent_files_status.emit(agent_id, {})
	_chat_depth[agent_id] = 0
	_relay_seen[agent_id] = {}

	var formatted_task := "[%s] %s" % [sender_name, task]
	var session := get_session(agent_id)
	session["task"] = formatted_task
	set_state(agent_id, "thinking")
	ProfileStore.save_session(agent_id, session)
	EventBus.agent_task_updated.emit(agent_id, formatted_task)
	if not _spawn_runner(agent_id, formatted_task):
		return TASK_LAUNCH_FAILED
	return TASK_OK


func send_chat_message(agent_id: String, content: String) -> int:
	var runner: OpenCodeRunner = _runners.get(agent_id)
	if runner != null and runner.running:
		_enqueue_chat(agent_id, content, 0)
		var profile := get_profile(agent_id)
		var who := profile.name if profile != null else agent_id
		_emit_system_chat("%s is working; your message is queued and will be delivered when it finishes." % who)
		return TASK_OK
	return send_task(agent_id, content)


func get_user_message_targets(text: String, target_agent_id: String = "") -> Array[String]:
	var targets: Array[String] = []
	var mentions := ProfileStore.extract_mentions(text)
	if not mentions.is_empty():
		if mentions.has("all"):
			for profile_id in ProfileStore.profiles:
				targets.append(profile_id)
		else:
			for agent_id in mentions:
				targets.append(str(agent_id))
	elif not target_agent_id.is_empty() and ProfileStore.get_profile(target_agent_id) != null:
		targets.append(target_agent_id)
	elif not selected_agent_id.is_empty():
		targets.append(selected_agent_id)
	return targets


func send_user_attachment(source_path: String, message: String = "", target_agent_id: String = "") -> Dictionary:
	if not FileAccess.file_exists(source_path):
		return {"accepted": false, "error": "file_not_found"}
	var targets := get_user_message_targets(message, target_agent_id)
	if targets.is_empty():
		return {"accepted": false, "error": "no_target"}
	var filename := source_path.get_file()
	if filename.is_empty():
		return {"accepted": false, "error": "invalid_file"}
	var copied_targets: Array[String] = []
	var copied_paths: Array[String] = []
	var errors: Array[String] = []
	for agent_id in targets:
		var profile := get_profile(agent_id)
		if profile == null or profile.project.is_empty():
			errors.append(agent_id)
			continue
		var project_path := ProjectSettings.globalize_path(profile.project)
		if not DirAccess.dir_exists_absolute(project_path):
			errors.append(agent_id)
			continue
		var uploads_path := project_path.path_join(".agents-uploads")
		if DirAccess.make_dir_recursive_absolute(uploads_path) != OK:
			errors.append(agent_id)
			continue
		var relative_path := ".agents-uploads/%d-%s" % [Time.get_unix_time_from_system() * 1000, filename]
		var destination := project_path.path_join(relative_path)
		if DirAccess.copy_absolute(source_path, destination) != OK:
			errors.append(agent_id)
			continue
		copied_targets.append(agent_id)
		copied_paths.append(relative_path)
	if copied_targets.is_empty():
		return {"accepted": false, "error": "copy_failed", "errors": errors}
	var paths := "\n".join(copied_paths)
	var notice := "Attachment copied to:\n%s\nRead the attachment before responding." % paths
	var content := notice if message.strip_edges().is_empty() else message.strip_edges() + "\n\n" + notice
	var result := send_user_message(content, "", copied_targets)
	result["copied_paths"] = copied_paths
	result["errors"] = errors
	return result


func send_user_message(text: String, target_agent_id: String = "", explicit_targets: Array[String] = []) -> Dictionary:
	var content := text.strip_edges()
	if content.is_empty():
		return {"accepted": false, "error": "empty_content"}
	var mentions := ProfileStore.extract_mentions(content)
	var message := _append_and_publish("user", content, mentions, false)
	var targets := explicit_targets if not explicit_targets.is_empty() else get_user_message_targets(content, target_agent_id)
	var results: Array = []
	if targets.is_empty():
		_append_and_publish("system", "No agent targeted. Select an agent in the left panel or use @AgentName / @all.", [], false)
		return {"accepted": true, "message": message, "targets": results}
	for agent_id in targets:
		var result := send_chat_message(agent_id, content)
		results.append({"agent_id": agent_id, "result": result})
		if result != TASK_OK:
			var profile := ProfileStore.get_profile(agent_id)
			var who := profile.name if profile != null else agent_id
			var reason := "%s not reached (OpenCode failed to launch). Check its output log." % who
			if result == TASK_NO_PROJECT:
				reason = "%s has no project set. Open its editor or use Select Folder in Workspace." % who
			elif result == TASK_BUSY:
				reason = "%s is busy with another task. Wait for it to finish." % who
			_append_and_publish("system", reason, [], false)
	return {"accepted": true, "message": message, "targets": results}


func get_chat_messages(after_id: String = "", limit: int = 100) -> Dictionary:
	return ProfileStore.get_chat_messages(after_id, limit)


func get_agent_state(agent_id: String) -> String:
	return str((sessions.get(agent_id, {}) as Dictionary).get("state", "offline"))


func has_running_agents(except_agent_id: String = "") -> bool:
	for agent_id in _runners:
		if agent_id == except_agent_id:
			continue
		var runner: OpenCodeRunner = _runners[agent_id]
		if runner.running:
			return true
	return false


func _append_and_publish(sender: String, content: String, mentions: Array, is_agent: bool, session_id = null) -> Dictionary:
	var timestamp := Time.get_unix_time_from_system() * 1000
	var message := ProfileStore.append_chat_message(sender, content, mentions, timestamp, is_agent, session_id)
	EventBus.chat_message.emit(sender, content, mentions, timestamp, is_agent)
	chat_message_persisted.emit(message)
	return message


func _team_context_for(agent_id: String) -> String:
	var names: Array[String] = []
	for profile_id in ProfileStore.profiles:
		if profile_id == agent_id:
			continue
		var profile := ProfileStore.get_profile(profile_id)
		if profile != null:
			names.append(profile.name)
	return ", ".join(names)


func delete_session(agent_id: String) -> void:
	_detach_runner(agent_id)
	_reset_temp_skills(agent_id)
	emit_output(agent_id, "[session] deleted — next task starts fresh")
	set_state(agent_id, "offline")


func delete_archived_session(agent_id: String, opencode_session_id: String) -> void:
	if opencode_session_id.is_empty():
		return
	var history := ProfileStore.load_session_history(agent_id)
	var remaining: Array = []
	for entry in history:
		if entry is Dictionary and str(entry.get("opencode_session", "")) == opencode_session_id:
			continue
		remaining.append(entry)
	ProfileStore.save_session_history(agent_id, remaining)
	if selected_agent_id == agent_id:
		emit_output(agent_id, "[session] archived session deleted: %s" % opencode_session_id)


func new_session(agent_id: String) -> void:
	_archive_session(agent_id)
	_detach_runner(agent_id)
	_reset_temp_skills(agent_id)
	emit_output(agent_id, "[session] new session — previous kept in history")
	set_state(agent_id, "offline")


func _reset_temp_skills(agent_id: String) -> void:
	var profile := get_profile(agent_id)
	if profile == null or not profile.has_temp_skills():
		return
	profile.temp_skills.clear()
	emit_output(agent_id, "[skills] temp skills cleared for new session")
	EventBus.temp_skills_changed.emit(agent_id)


func switch_session(agent_id: String, opencode_session_id: String) -> void:
	if opencode_session_id.is_empty():
		return
	_archive_session(agent_id)
	_detach_runner(agent_id)
	var history := ProfileStore.load_session_history(agent_id)
	var filtered: Array = []
	for entry in history:
		if str(entry.get("opencode_session", "")) != opencode_session_id:
			filtered.append(entry)
	ProfileStore.save_session_history(agent_id, filtered)
	var session := get_session(agent_id)
	session["opencode_session"] = opencode_session_id
	ProfileStore.save_session(agent_id, session)
	_reset_temp_skills(agent_id)
	emit_output(agent_id, "[session] switched to %s" % opencode_session_id)
	set_state(agent_id, "offline")


func rename_session(agent_id: String, title: String) -> void:
	var session := get_session(agent_id)
	if str(session.get("opencode_session", "")).is_empty():
		return
	var clean := title.strip_edges()
	if clean.is_empty():
		session.erase("title_override")
		clean = "(automatic)"
	else:
		session["title_override"] = clean
	ProfileStore.save_session(agent_id, session)
	emit_output(agent_id, "[session] renamed: %s" % clean)
	EventBus.session_renamed.emit(agent_id)


func _detach_runner(agent_id: String) -> void:
	var runner: OpenCodeRunner = _runners.get(agent_id)
	if runner != null and runner.running:
		runner.stop()
	_runners.erase(agent_id)
	ProfileStore.delete_session(agent_id)
	sessions.erase(agent_id)
	_output_history.erase(agent_id)
	_last_error.erase(agent_id)
	_file_status.erase(agent_id)
	_chat_inbox.erase(agent_id)
	_chat_depth.erase(agent_id)
	_clear_pending_requests(agent_id)


func _clear_pending_requests(agent_id: String) -> void:
	for requests in [_pending_permissions, _pending_questions]:
		var request: Variant = requests.get(agent_id, null)
		if request is Dictionary and not (request as Dictionary).is_empty():
			EventBus.agent_request_resolved.emit(agent_id, str((request as Dictionary).get("id", "")))
	_pending_permissions.erase(agent_id)
	_pending_questions.erase(agent_id)


func reply_permission(agent_id: String, request_id: String, reply: String, message: String = "") -> void:
	var runner: OpenCodeRunner = _runners.get(agent_id)
	if runner != null:
		runner.reply_permission(request_id, reply, message)
	_pending_permissions.erase(agent_id)
	emit_output(agent_id, "[permission] %s" % reply)
	EventBus.agent_request_resolved.emit(agent_id, request_id)


func reply_question(agent_id: String, request_id: String, answers: Array) -> void:
	var runner: OpenCodeRunner = _runners.get(agent_id)
	if runner != null:
		runner.reply_question(request_id, answers)
	_pending_questions.erase(agent_id)
	emit_output(agent_id, "[question] answered")
	EventBus.agent_request_resolved.emit(agent_id, request_id)


func reject_question(agent_id: String, request_id: String) -> void:
	var runner: OpenCodeRunner = _runners.get(agent_id)
	if runner != null:
		runner.reject_question(request_id)
	_pending_questions.erase(agent_id)
	emit_output(agent_id, "[question] rejected")
	EventBus.agent_request_resolved.emit(agent_id, request_id)


func get_pending_remote_requests() -> Array:
	var pending: Array = []
	for agent_id in _pending_permissions:
		var request: Dictionary = _pending_permissions[agent_id]
		var profile := get_profile(agent_id)
		var metadata: Dictionary = request.get("metadata", {}) if request.get("metadata", {}) is Dictionary else {}
		pending.append({
			"kind": "permission",
			"agent_id": agent_id,
			"agent_name": profile.name if profile != null else agent_id,
			"request_id": str(request.get("id", "")),
			"permission": str(request.get("permission", "action")),
			"patterns": request.get("patterns", []) if request.get("patterns", []) is Array else [],
			"command": str(metadata.get("command", "")),
			"path": str(metadata.get("filePath", metadata.get("path", ""))),
			"can_always": request.get("always", []) is Array and not (request.get("always", []) as Array).is_empty(),
		})
	for agent_id in _pending_questions:
		var request: Dictionary = _pending_questions[agent_id]
		var profile := get_profile(agent_id)
		var questions: Array = []
		for raw_question in request.get("questions", []):
			if not raw_question is Dictionary:
				continue
			var options: Array = []
			for raw_option in raw_question.get("options", []):
				if raw_option is Dictionary:
					options.append({"label": str(raw_option.get("label", "")), "description": str(raw_option.get("description", ""))})
			questions.append({
				"header": str(raw_question.get("header", "")),
				"question": str(raw_question.get("question", "")),
				"multiple": bool(raw_question.get("multiple", false)),
				"custom": bool(raw_question.get("custom", false)),
				"options": options,
			})
		pending.append({
			"kind": "question",
			"agent_id": agent_id,
			"agent_name": profile.name if profile != null else agent_id,
			"request_id": str(request.get("id", "")),
			"questions": questions,
		})
	return pending


func respond_remote_request(payload: Dictionary) -> Dictionary:
	var kind := str(payload.get("kind", ""))
	var agent_id := str(payload.get("agent_id", ""))
	var request_id := str(payload.get("request_id", ""))
	var decision := str(payload.get("decision", ""))
	var runner: OpenCodeRunner = _runners.get(agent_id)
	if runner == null or not runner.running:
		return {"ok": false, "error": "unavailable"}
	if kind == "permission":
		var request: Dictionary = _pending_permissions.get(agent_id, {})
		if request.is_empty() or str(request.get("id", "")) != request_id:
			return {"ok": false, "error": "stale_request"}
		if decision not in ["once", "always", "reject"]:
			return {"ok": false, "error": "invalid_response"}
		if decision == "always" and (not request.get("always", []) is Array or (request.get("always", []) as Array).is_empty()):
			return {"ok": false, "error": "invalid_response"}
		reply_permission(agent_id, request_id, decision)
		return {"ok": true}
	if kind == "question":
		var request: Dictionary = _pending_questions.get(agent_id, {})
		if request.is_empty() or str(request.get("id", "")) != request_id:
			return {"ok": false, "error": "stale_request"}
		if decision == "reject":
			reject_question(agent_id, request_id)
			return {"ok": true}
		if decision != "answer":
			return {"ok": false, "error": "invalid_response"}
		var answers = payload.get("answers", null)
		var questions: Array = request.get("questions", [])
		if not answers is Array or answers.size() != questions.size():
			return {"ok": false, "error": "invalid_response"}
		var validated: Array = []
		for index in questions.size():
			if not questions[index] is Dictionary or not answers[index] is Array:
				return {"ok": false, "error": "invalid_response"}
			var question: Dictionary = questions[index]
			var allowed: Array[String] = []
			for option in question.get("options", []):
				if option is Dictionary:
					allowed.append(str(option.get("label", "")))
			var values: Array = []
			for raw_value in answers[index]:
				var value := str(raw_value).strip_edges()
				if value.is_empty() or value.length() > 1000:
					return {"ok": false, "error": "invalid_response"}
				if not allowed.has(value) and not bool(question.get("custom", false)):
					return {"ok": false, "error": "invalid_response"}
				values.append(value)
			if values.is_empty() or (not bool(question.get("multiple", false)) and values.size() > 1):
				return {"ok": false, "error": "invalid_response"}
			validated.append(values)
		reply_question(agent_id, request_id, validated)
		return {"ok": true}
	return {"ok": false, "error": "invalid_response"}


func _archive_session(agent_id: String) -> void:
	var sid := str(get_session(agent_id).get("opencode_session", ""))
	if sid.is_empty():
		return
	var history := ProfileStore.load_session_history(agent_id)
	for entry in history:
		if str(entry.get("opencode_session", "")) == sid:
			return
	var override := str(get_session(agent_id).get("title_override", ""))
	history.append({
		"opencode_session": sid,
		"archived_at": Time.get_unix_time_from_system(),
		"title": override if not override.is_empty() else get_cached_session_title(sid, _project_of(agent_id)),
		"context_tokens": int(get_session(agent_id).get("context_tokens", 0)),
		"context_percent": float(get_session(agent_id).get("context_percent", 0.0)),
	})
	ProfileStore.save_session_history(agent_id, history)


func set_model(agent_id: String, model: String) -> void:
	var profile := get_profile(agent_id)
	if profile == null:
		return
	profile.model = model
	profile.model_variant = ""
	ProfileStore.save_profile(profile)
	if model.is_empty():
		emit_output(agent_id, "[model] default (auto)")
	else:
		emit_output(agent_id, "[model] %s" % model)
	EventBus.profile_saved.emit(profile)


func set_variant(agent_id: String, variant: String) -> void:
	var profile := get_profile(agent_id)
	if profile == null:
		return
	profile.model_variant = variant
	ProfileStore.save_profile(profile)
	if variant.is_empty():
		emit_output(agent_id, "[variant] default")
	else:
		emit_output(agent_id, "[variant] %s" % variant)
	EventBus.profile_saved.emit(profile)


func add_temp_skill(agent_id: String, skill: String, content: String = "", source: String = "") -> void:
	var profile := get_profile(agent_id)
	if profile == null:
		return
	profile.add_temp_skill(skill, content, source)
	emit_output(agent_id, "[skills] temp skill added: %s" % skill)
	EventBus.temp_skills_changed.emit(agent_id)


func remove_temp_skill(agent_id: String, index: int) -> void:
	var profile := get_profile(agent_id)
	if profile == null:
		return
	var name := ""
	if index >= 0 and index < profile.temp_skills.size():
		name = str(profile.temp_skills[index].get("name", ""))
	profile.remove_temp_skill(index)
	emit_output(agent_id, "[skills] temp skill removed: %s" % name)
	EventBus.temp_skills_changed.emit(agent_id)


func clear_temp_skills(agent_id: String) -> void:
	var profile := get_profile(agent_id)
	if profile == null:
		return
	profile.temp_skills.clear()
	emit_output(agent_id, "[skills] temp skills cleared")
	EventBus.temp_skills_changed.emit(agent_id)


func set_state(agent_id: String, state: String) -> void:
	var session := get_session(agent_id)
	if str(session.get("state", "")) == state:
		return
	session["state"] = state
	EventBus.agent_state_changed.emit(agent_id, state)


func emit_output(agent_id: String, line: String) -> void:
	_last_reasoning_part.erase(agent_id)
	var history: Array = _output_history.get(agent_id, [])
	history.append(line)
	if history.size() > 500:
		_output_history[agent_id] = history.slice(history.size() - 400)
	else:
		_output_history[agent_id] = history
	EventBus.agent_output.emit(agent_id, line)


func get_output_history(agent_id: String) -> Array:
	return _output_history.get(agent_id, [])


func get_file_status(agent_id: String) -> Dictionary:
	if not _file_status.has(agent_id):
		return {}
	return _file_status[agent_id].duplicate()


const SESSION_TITLES_TTL := 20.0
const SESSION_TITLES_LIMIT := 300


func get_session_title(session_id: String, project: String = "") -> String:
	if session_id.is_empty():
		return ""
	if _session_titles_stale(project):
		_load_session_titles_sync(project)
	var title := _lookup_session_title(session_id, project)
	if title.is_empty() and not project.is_empty():
		if _session_titles_stale(""):
			_load_session_titles_sync("")
		title = _lookup_session_title(session_id, "")
	return title


func get_cached_session_title(session_id: String, project: String = "") -> String:
	if session_id.is_empty():
		return ""
	if _session_titles_stale(project):
		_request_session_titles(project)
	var title := _lookup_session_title(session_id, project)
	if title.is_empty() and not project.is_empty():
		if _session_titles_stale(""):
			_request_session_titles("")
		title = _lookup_session_title(session_id, "")
	return title


func _prewarm_session_titles() -> void:
	var projects: Dictionary = {}
	for profile_id in ProfileStore.profiles:
		var profile: AgentProfile = ProfileStore.profiles[profile_id]
		projects[str(profile.project).strip_edges()] = true
	for project in projects:
		_request_session_titles(str(project))


func _project_of(agent_id: String) -> String:
	var profile := get_profile(agent_id)
	return profile.project if profile != null else ""


func _session_titles_stale(project: String) -> bool:
	var loaded_at := float(_session_titles_loaded_at.get(project, -1.0))
	if loaded_at < 0.0:
		return true
	return Time.get_ticks_msec() / 1000.0 - loaded_at >= SESSION_TITLES_TTL


func _lookup_session_title(session_id: String, project: String) -> String:
	return str((_session_titles.get(project, {}) as Dictionary).get(session_id, ""))


func _load_session_titles_sync(project: String) -> void:
	_session_titles_loaded_at[project] = Time.get_ticks_msec() / 1000.0
	_session_titles.erase(project)
	var titles: Variant = _fetch_session_titles(project)
	if titles is Dictionary:
		_session_titles[project] = titles


func _request_session_titles(project: String) -> void:
	if project == _session_titles_inflight or _session_titles_queue.has(project):
		return
	_session_titles_queue.append(project)
	_start_next_session_titles_load()


func _start_next_session_titles_load() -> void:
	if not _session_titles_inflight.is_empty() or _session_titles_queue.is_empty():
		return
	var project: String = _session_titles_queue.pop_front()
	_session_titles_inflight = project
	_session_titles_loaded_at[project] = Time.get_ticks_msec() / 1000.0
	var thread := Thread.new()
	_session_title_threads[project] = thread
	thread.start(_session_titles_worker.bind(project))


func _session_titles_worker(project: String) -> void:
	var titles: Variant = _fetch_session_titles(project)
	call_deferred("_on_session_titles_loaded", project, titles)


func _on_session_titles_loaded(project: String, titles: Variant) -> void:
	if _session_title_threads.has(project):
		var thread: Thread = _session_title_threads[project]
		_session_title_threads.erase(project)
		if thread.is_started():
			thread.wait_to_finish()
	if titles is Dictionary:
		_session_titles[project] = titles
	if _session_titles_inflight == project:
		_session_titles_inflight = ""
	EventBus.session_titles_loaded.emit(project)
	_start_next_session_titles_load()


func _fetch_session_titles(project: String) -> Variant:
	var output: Array = []
	var cmd := "opencode session list --format json -n %d </dev/null" % SESSION_TITLES_LIMIT
	if not project.is_empty():
		cmd = "cd %s && %s" % [_shell_quote(project), cmd]
	if OS.execute("bash", ["-c", cmd], output, false, false) != OK:
		return null
	var text := _extract_json("\n".join(output))
	if not text.begins_with("[") and not text.begins_with("{"):
		return null
	var parsed = JSON.parse_string(text)
	if not parsed is Array:
		return null
	var titles: Dictionary = {}
	for entry in parsed:
		if entry is Dictionary:
			var id := str(entry.get("id", ""))
			if not id.is_empty():
				titles[id] = str(entry.get("title", ""))
	return titles


func _shell_quote(s: String) -> String:
	return "'" + s.replace("'", "'\\''") + "'"


func _extract_json(text: String) -> String:
	var start := text.find("[")
	var start_obj := text.find("{")
	if start < 0 or (start_obj >= 0 and start_obj < start):
		start = start_obj
	if start < 0:
		return text
	var open := text[start]
	var close := "]" if open == "[" else "}"
	var end := text.rfind(close)
	if end <= start:
		return text.substr(start)
	return text.substr(start, end - start + 1)


func emit_chat_error(agent_id: String, message: String) -> void:
	emit_output(agent_id, "[error] " + message)
	var profile := get_profile(agent_id)
	var sender := profile.name if profile != null else agent_id
	_append_and_publish(sender, "[error] " + message, [], true)


func _spawn_runner(agent_id: String, task: String) -> bool:
	var profile := get_profile(agent_id)
	var session := get_session(agent_id)
	var runner := OpenCodeRunner.new()
	runner.name = "Runner_%s" % agent_id
	add_child(runner)
	_runners[agent_id] = runner
	_last_error.erase(agent_id)

	var started := runner.start({
		"agent_id": agent_id,
		"agent_name": profile.name,
		"project": profile.project,
		"model": profile.model,
		"variant": profile.model_variant,
		"opencode_agent": profile.opencode_agent,
		"session_id": str(session.get("opencode_session", "")),
		"task": task,
		"personality": profile.personality,
		"skills_context": ", ".join(profile.get_all_skills()),
		"temp_context": profile.get_temp_context(),
		"team_context": _team_context_for(agent_id),
	})
	if not started:
		emit_chat_error(agent_id, "Failed to launch opencode CLI. Is it in PATH?")
		runner.queue_free()
		_runners.erase(agent_id)
		set_state(agent_id, "error")
		return false

	runner.event_received.connect(_handle_event)
	runner.process_finished.connect(_on_process_finished)
	emit_output(agent_id, "[start] opencode (session: %s)" % str(session.get("opencode_session", "new")))
	queue_git_refresh(agent_id, 1.5)
	return true


func _on_process_finished(agent_id: String, exit_code: int) -> void:
	var runner: OpenCodeRunner = _runners.get(agent_id)
	var stall_ms: int = runner.stall_timeout_ms if runner != null else 120000
	if runner != null and not runner.running:
		_runners.erase(agent_id)
		runner.queue_free()
	_clear_pending_requests(agent_id)
	if exit_code == -2:
		var stall_reason := str(_last_error.get(agent_id, ""))
		_last_error.erase(agent_id)
		if stall_reason.is_empty():
			stall_reason = "No activity for %d s. The model/provider may be unresponsive or rate-limited." % int(stall_ms / 1000)
		emit_chat_error(agent_id, stall_reason)
		set_state(agent_id, "error")
	elif exit_code != 0:
		var message := str(_last_error.get(agent_id, ""))
		_last_error.erase(agent_id)
		if message.is_empty():
			message = "Process exited with code %d" % exit_code
		emit_chat_error(agent_id, message)
		set_state(agent_id, "error")
	else:
		emit_output(agent_id, "[end] done")
	if str(get_session(agent_id).get("state", "")) in ACTIVE_STATES:
		set_state(agent_id, "idle")
	var session := get_session(agent_id)
	if not str(session.get("task", "")).is_empty():
		session["task"] = ""
		EventBus.agent_task_updated.emit(agent_id, "")
		ProfileStore.save_session(agent_id, session)
	queue_git_refresh(agent_id, 0.5)
	_deliver_inbox(agent_id)


func _handle_event(agent_id: String, event: Dictionary) -> void:
	if not sessions.has(agent_id):
		return
	var session: Dictionary = sessions[agent_id]
	var etype: String = str(event.get("type", ""))
	var part: Dictionary = event.get("part", {})
	if part is not Dictionary:
		part = {}
	var psession: String = str(event.get("sessionID", ""))
	if psession.is_empty():
		psession = str(part.get("sessionID", ""))
	if not psession.is_empty() and str(session.get("opencode_session", "")).is_empty():
		session["opencode_session"] = psession
		ProfileStore.save_session(agent_id, session)

	match etype:
		"step_start":
			set_state(agent_id, "thinking")
		"reasoning":
			var reason_text: String = str(part.get("text", ""))
			if not reason_text.is_empty():
				var pid := str(part.get("id", ""))
				var history := get_output_history(agent_id)
				if not pid.is_empty() and _last_reasoning_part.get(agent_id, "") == pid and not history.is_empty():
					history[history.size() - 1] += reason_text
					EventBus.agent_output_updated.emit(agent_id)
				else:
					emit_output(agent_id, "[think] " + reason_text)
					_last_reasoning_part[agent_id] = pid
		"text":
			if str(part.get("type", "")) == "text":
				var text: String = str(part.get("text", ""))
				if not text.is_empty():
					_post_reply(agent_id, text)
		"tool_use":
			if str(part.get("type", "")) == "tool":
				_handle_tool(agent_id, part)
		"step_finish":
			_emit_context_usage(agent_id, part)
			if str(part.get("reason", "")) == "stop":
				_finish_task(agent_id)
			else:
				set_state(agent_id, "working")
		"permission_asked":
			var permission: Dictionary = event.get("request", {})
			_pending_permissions[agent_id] = permission
			set_state(agent_id, "approval")
			emit_output(agent_id, "[permission] %s" % _describe_permission(permission))
			EventBus.agent_permission_asked.emit(agent_id, permission)
		"permission_replied":
			_pending_permissions.erase(agent_id)
			set_state(agent_id, "working")
			EventBus.agent_request_resolved.emit(agent_id, str(event.get("request_id", "")))
		"question_asked":
			var question: Dictionary = event.get("request", {})
			_pending_questions[agent_id] = question
			set_state(agent_id, "question")
			emit_output(agent_id, "[question] %s" % _describe_question(question))
			EventBus.agent_question_asked.emit(agent_id, question)
		"question_resolved":
			_pending_questions.erase(agent_id)
			set_state(agent_id, "working")
			EventBus.agent_request_resolved.emit(agent_id, str(event.get("request_id", "")))
		_:
			if etype == "stderr":
				_handle_stderr(agent_id, str(event.get("line", "")))
			elif etype == "error":
				_capture_error(agent_id, event)
			elif etype == "runner_error":
				var message := str(event.get("message", ""))
				_last_error[agent_id] = message
				emit_output(agent_id, "[error] " + message)


func _describe_permission(request: Dictionary) -> String:
	var kind := str(request.get("permission", "action"))
	var patterns: Array = request.get("patterns", [])
	var detail := " ".join(patterns) if not patterns.is_empty() else ""
	if detail.is_empty():
		var metadata: Variant = request.get("metadata", {})
		if metadata is Dictionary:
			var meta: Dictionary = metadata
			detail = str(meta.get("command", meta.get("filePath", meta.get("path", ""))))
	if detail.is_empty():
		return kind
	return "%s: %s" % [kind, detail]


func _describe_question(request: Dictionary) -> String:
	var questions: Array = request.get("questions", [])
	if questions.is_empty() or not (questions[0] is Dictionary):
		return "question"
	var first: Dictionary = questions[0]
	return str(first.get("header", first.get("question", "question")))


func _handle_stderr(agent_id: String, line: String) -> void:
	if not line.contains("level=ERROR"):
		return
	var message := _extract_log_message(line)
	if message.is_empty():
		return
	emit_output(agent_id, "[stderr] " + message)
	_last_error[agent_id] = message


func _extract_log_message(line: String) -> String:
	var msg := ""
	var re_message := RegEx.new()
	re_message.compile('message=(?:"([^"]*)"|([^\\s]+))')
	var m := re_message.search(line)
	if m != null:
		msg = m.get_string(1) if not m.get_string(1).is_empty() else m.get_string(2)
	var re_error := RegEx.new()
	re_error.compile('error\\.error="([^"]*)"')
	var e := re_error.search(line)
	if e != null:
		var detail := e.get_string(1)
		msg = detail if msg.is_empty() else "%s — %s" % [msg, detail]
	if msg.is_empty():
		msg = line
	return msg


func _capture_error(agent_id: String, event: Dictionary) -> void:
	var error: Variant = event.get("error", {})
	if error is not Dictionary:
		error = {"message": str(error)}
	var data: Variant = error.get("data", {})
	if data is not Dictionary:
		data = {}
	var message := str(data.get("message", ""))
	if message.is_empty():
		message = str(error.get("message", ""))
	var name := str(error.get("name", ""))
	if not message.is_empty() and not name.is_empty() and not message.begins_with(name):
		message = "%s: %s" % [name, message]
	if message.is_empty():
		message = name if not name.is_empty() else "Unknown OpenCode error"
	_last_error[agent_id] = message


func _emit_context_usage(agent_id: String, part: Dictionary) -> void:
	var tokens: Dictionary = part.get("tokens", {})
	if tokens is not Dictionary:
		tokens = {}
	var cache: Variant = tokens.get("cache", {})
	if cache is not Dictionary:
		cache = {}
	var output_tokens := int(tokens.get("output", 0))
	if output_tokens <= 0:
		return
	var context_tokens := int(tokens.get("input", 0)) + output_tokens + int(tokens.get("reasoning", 0)) + int(cache.get("read", 0)) + int(cache.get("write", 0))
	var profile := get_profile(agent_id)
	var limit := 0
	if profile != null:
		limit = ModelCatalog.get_context_limit(profile.model)
	var pct := 0.0
	if limit > 0:
		pct = minf(roundf(float(context_tokens) / float(limit) * 100.0), 100.0)
	var session := get_session(agent_id)
	session["cost_spent"] = float(session.get("cost_spent", 0.0)) + float(part.get("cost", 0.0))
	session["context_tokens"] = context_tokens
	session["context_percent"] = pct
	ProfileStore.save_session(agent_id, session)
	EventBus.agent_context_usage.emit(agent_id, context_tokens, pct, float(session["cost_spent"]))


func _handle_tool(agent_id: String, part: Dictionary) -> void:
	var tool_name: String = str(part.get("tool", ""))
	var tool_state: Dictionary = part.get("state", {})
	if tool_state is not Dictionary:
		tool_state = {}
	var status: String = str(tool_state.get("status", ""))
	var title: String = str(tool_state.get("title", ""))
	var tool_input: Dictionary = tool_state.get("input", {})
	if tool_input is not Dictionary:
		tool_input = {}

	var base_state: String = TOOL_STATES.get(tool_name, "working")
	var note := title
	if tool_name == "bash":
		note = "bash: %s" % str(tool_input.get("command", title))
	elif tool_name in ["edit", "multi_edit", "write", "patch", "apply_patch"]:
		note = "%s: %s" % [tool_name, str(tool_input.get("filePath", title))]

	match status:
		"pending":
			emit_output(agent_id, "[tool] %s (started)" % note)
			if tool_name == "ask_user":
				set_state(agent_id, "question")
			else:
				set_state(agent_id, base_state)
		"running":
			set_state(agent_id, base_state)
		"completed":
			emit_output(agent_id, "[tool] %s (done)" % note)
			set_state(agent_id, base_state)
			var metadata: Variant = tool_state.get("metadata", {})
			_track_file_operation(agent_id, tool_name, tool_input, status, metadata if metadata is Dictionary else {})
			_flash_state(agent_id, "success", 1.2)
		"error":
			emit_output(agent_id, "! %s (error)" % note)
			set_state(agent_id, "error")
		_:
			set_state(agent_id, base_state)

	if tool_name in ["bash", "edit", "multi_edit", "write", "patch", "apply_patch"]:
		queue_git_refresh(agent_id, 1.0)


func _track_file_operation(agent_id: String, tool_name: String, tool_input: Dictionary, status: String, metadata: Dictionary = {}) -> void:
	if status != "completed":
		return
	var op: String = ""
	var files: Array = []
	match tool_name:
		"read":
			op = FILE_OP_READ
			var path := str(tool_input.get("filePath", ""))
			if not path.is_empty():
				files.append(path)
		"edit":
			op = FILE_OP_MODIFIED
			var path := str(tool_input.get("filePath", ""))
			if not path.is_empty():
				files.append(path)
		"apply_patch", "patch":
			var patch_text := str(tool_input.get("patchText", tool_input.get("patch", "")))
			if not patch_text.is_empty():
				_track_patch_files(agent_id, patch_text)
				return
			op = FILE_OP_MODIFIED
			for edit in tool_input.get("edits", []):
				if edit is Dictionary:
					files.append(str(edit.get("filePath", "")))
		"multi_edit":
			op = FILE_OP_MODIFIED
			files.append(str(tool_input.get("filePath", "")))
			for edit in tool_input.get("edits", []):
				if edit is Dictionary:
					files.append(str((edit as Dictionary).get("filePath", "")))
		"write":
			var path := str(tool_input.get("filePath", ""))
			if path.is_empty():
				return
			op = FILE_OP_MODIFIED if bool(metadata.get("exists", true)) else FILE_OP_CREATED
			files.append(path)
		"bash":
			_track_bash_deletes(agent_id, str(tool_input.get("command", "")))
			return
		_:
			return

	for path in files:
		if path.is_empty():
			continue
		_record_file_status(agent_id, path, op)


func _track_patch_files(agent_id: String, patch_text: String) -> void:
	var updated_path := ""
	for line in patch_text.split("\n"):
		if line.begins_with("*** Add File: "):
			updated_path = ""
			_record_file_status(agent_id, line.trim_prefix("*** Add File: "), FILE_OP_CREATED)
		elif line.begins_with("*** Delete File: "):
			updated_path = ""
			_record_file_status(agent_id, line.trim_prefix("*** Delete File: "), FILE_OP_DELETED)
		elif line.begins_with("*** Update File: "):
			updated_path = line.trim_prefix("*** Update File: ")
			_record_file_status(agent_id, updated_path, FILE_OP_MODIFIED)
		elif line.begins_with("*** Move to: ") and not updated_path.is_empty():
			_record_file_status(agent_id, updated_path, FILE_OP_DELETED)
			_record_file_status(agent_id, line.trim_prefix("*** Move to: "), FILE_OP_CREATED)
			updated_path = ""


func _track_bash_deletes(agent_id: String, command: String) -> void:
	if command.is_empty():
		return
	var regex := RegEx.new()
	regex.compile("\\b(?:rm|rmdir|unlink|del)\\s+(?:-[^\\s]+\\s+)*([^\\s;&|]+)")
	var m := regex.search_all(command)
	for match in m:
		var path := match.get_string(1).strip_edges()
		if path.is_empty() or path.begins_with("-") or path.begins_with("\\"):
			continue
		if (path.begins_with("\"") or path.begins_with("'")) and path.length() > 2:
			path = path.substr(1, path.length() - 2)
		_record_file_status(agent_id, path, FILE_OP_DELETED)


func _record_file_status(agent_id: String, path: String, op: String) -> void:
	path = _normalize_file_path(agent_id, path)
	if path.is_empty():
		return
	if not _file_status.has(agent_id):
		_file_status[agent_id] = {}
	var files: Dictionary = _file_status[agent_id]
	var previous := str(files.get(path, ""))
	if op == FILE_OP_READ and not previous.is_empty():
		return
	if op == FILE_OP_MODIFIED and previous == FILE_OP_CREATED:
		return
	files[path] = op
	EventBus.agent_files_status.emit(agent_id, files.duplicate())


func _normalize_file_path(agent_id: String, path: String) -> String:
	path = path.strip_edges()
	if path.is_empty():
		return ""
	if path.begins_with("res://") or path.begins_with("user://"):
		path = ProjectSettings.globalize_path(path)
	elif not path.is_absolute_path():
		var project := _project_of(agent_id)
		if project.begins_with("~"):
			project = OS.get_environment("HOME").path_join(project.trim_prefix("~").trim_prefix("/"))
		if project.begins_with("res://") or project.begins_with("user://"):
			project = ProjectSettings.globalize_path(project)
		if not project.is_empty():
			path = project.path_join(path)
	return path.simplify_path()


func _finish_task(agent_id: String) -> void:
	var session := get_session(agent_id)
	session["task"] = ""
	set_state(agent_id, "success")
	ProfileStore.save_session(agent_id, session)
	await get_tree().create_timer(2.5).timeout
	if sessions.has(agent_id) and str(sessions[agent_id].get("state", "")) == "success":
		set_state(agent_id, "idle")


const CHAT_MARKER := "CHAT:"


func _split_chat_reply(text: String) -> Dictionary:
	var idx := text.to_lower().find(CHAT_MARKER.to_lower())
	if idx < 0:
		return {"thinking": "", "chat": text.strip_edges()}
	return {
		"thinking": text.substr(0, idx).strip_edges(),
		"chat": text.substr(idx + CHAT_MARKER.length()).strip_edges(),
	}


func _post_reply(agent_id: String, text: String) -> void:
	var split := _split_chat_reply(text)
	var thinking := str(split["thinking"])
	for line in thinking.split("\n"):
		var clean := line.strip_edges()
		if not clean.is_empty():
			emit_output(agent_id, "[think] " + clean)
	var reply := str(split["chat"])
	if reply.is_empty():
		return
	var profile := get_profile(agent_id)
	if profile == null:
		return
	var mentions := ProfileStore.extract_mentions(reply)
	_append_and_publish(profile.name, reply, mentions, true)
	_relay_mentions(agent_id, reply, mentions)


func _relay_mentions(sender_id: String, reply: String, mentions: Array) -> void:
	if mentions.is_empty():
		return
	var depth := int(_chat_depth.get(sender_id, 0)) + 1
	if depth > CHAT_MAX_DEPTH:
		return
	if not _relay_seen.has(sender_id):
		_relay_seen[sender_id] = {}
	var seen: Dictionary = _relay_seen[sender_id]
	for target_id in mentions:
		if str(target_id) == "all" or str(target_id) == sender_id:
			continue
		if seen.has(str(target_id)):
			continue
		seen[str(target_id)] = true
		_deliver_relay(str(target_id), sender_id, reply, depth)


func _deliver_relay(target_id: String, sender_id: String, text: String, depth: int) -> void:
	var profile := get_profile(target_id)
	if profile == null:
		return
	var sender := get_profile(sender_id)
	var sender_name := sender.name if sender != null else sender_id
	if profile.project.is_empty():
		_emit_system_chat("%s could not receive a message from %s: no project set." % [profile.name, sender_name])
		return
	if sender != null and not sender.project.is_empty() and sender.project != profile.project:
		_emit_system_chat("Note: %s works in a different project (%s) than %s; the message will run there." % [profile.name, profile.project, sender_name])
	var result := send_task(target_id, text, sender_name)
	if result == TASK_OK:
		_chat_depth[target_id] = depth
	elif result == TASK_BUSY:
		_enqueue_chat(target_id, text, depth, sender_name)
		_emit_system_chat("%s is busy; message from %s queued and will be delivered when it finishes." % [profile.name, sender_name])


func _enqueue_chat(agent_id: String, task: String, depth: int, sender_name: String = "User") -> void:
	if not _chat_inbox.has(agent_id):
		_chat_inbox[agent_id] = []
	(_chat_inbox[agent_id] as Array).append({"task": task, "depth": depth, "sender_name": sender_name})


func _deliver_inbox(agent_id: String) -> void:
	if not _chat_inbox.has(agent_id):
		return
	var queued: Array = _chat_inbox[agent_id]
	if queued.is_empty():
		_chat_inbox.erase(agent_id)
		return
	var item: Dictionary = queued.pop_front()
	if queued.is_empty():
		_chat_inbox.erase(agent_id)
	var result := send_task(agent_id, str(item.get("task", "")), str(item.get("sender_name", "User")))
	if result == TASK_OK:
		_chat_depth[agent_id] = int(item.get("depth", 0))
	elif result == TASK_BUSY:
		queued.push_front(item)
		_chat_inbox[agent_id] = queued


func _emit_system_chat(message: String) -> void:
	_append_and_publish("system", message, [], false)


func _flash_state(agent_id: String, state: String, duration: float) -> void:
	set_state(agent_id, state)
	await get_tree().create_timer(duration).timeout
	if _runners.has(agent_id):
		var runner: OpenCodeRunner = _runners[agent_id]
		if runner.running:
			set_state(agent_id, "working")


func queue_git_refresh(agent_id: String, delay: float) -> void:
	if not _git_timers.has(agent_id):
		_git_timers[agent_id] = get_tree().create_timer(delay)
		_git_timers[agent_id].timeout.connect(_on_git_timer.bind(agent_id))
	_git_refresh_queue[agent_id] = true


func _on_git_timer(agent_id: String) -> void:
	_git_timers.erase(agent_id)
	if _git_refresh_queue.has(agent_id):
		_git_refresh_queue.erase(agent_id)
		_refresh_git(agent_id)


func _apply_git_refresh() -> void:
	if _git_refresh_queue.is_empty():
		return
	for agent_id in _git_refresh_queue.keys():
		if _git_timers.has(agent_id):
			continue
		_git_refresh_queue.erase(agent_id)
		_refresh_git(agent_id)


func _refresh_git(agent_id: String) -> void:
	var profile := get_profile(agent_id)
	if profile == null or profile.project.is_empty():
		return
	if _git_threads.has(agent_id):
		return
	var thread := Thread.new()
	_git_threads[agent_id] = thread
	thread.start(_git_worker.bind(agent_id, profile.project))


func _git_worker(agent_id: String, project: String) -> void:
	var output: Array = []
	var err := OS.execute("git", ["-C", project, "status", "--porcelain", "-b"], output, true, false)
	call_deferred("_on_git_refreshed", agent_id, err, output.duplicate())


func _on_git_refreshed(agent_id: String, err: int, output: Array) -> void:
	if _git_threads.has(agent_id):
		var thread: Thread = _git_threads[agent_id]
		_git_threads.erase(agent_id)
		if thread.is_started():
			thread.wait_to_finish()
	if err != OK:
		emit_output(agent_id, "[git] not a git repository")
		return
	var text := "\n".join(output)
	var branch := ""
	var files: Array = []
	var lines := text.split("\n")
	for i in lines.size():
		var line := lines[i]
		if i == 0 and line.begins_with("## "):
			branch = line.substr(3).split("...")[0].split(" ")[0]
			continue
		if line.strip_edges().is_empty():
			continue
		if line.length() > 3:
			files.append(line.substr(3))
	EventBus.agent_git_status.emit(agent_id, branch, text)
	EventBus.agent_files_changed.emit(agent_id, files)
