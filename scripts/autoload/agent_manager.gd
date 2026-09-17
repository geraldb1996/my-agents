extends Node

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
var _pending_permissions: Dictionary = {}
var _pending_questions: Dictionary = {}
var _last_error: Dictionary = {}
var _git_refresh_queue: Dictionary = {}
var _git_timers: Dictionary = {}
var _git_threads: Dictionary = {}
var _file_status: Dictionary = {}

const FILE_OP_READ := "R"
const FILE_OP_DELETED := "D"
const FILE_OP_CREATED := "C"
const FILE_OP_MODIFIED := "M"


func _ready() -> void:
	for profile_id in ProfileStore.profiles:
		sessions[profile_id] = ProfileStore.load_session(profile_id)
		if not sessions[profile_id].has("state"):
			sessions[profile_id]["state"] = "offline"


func _process(_delta: float) -> void:
	for agent_id in _runners.keys():
		(_runners[agent_id] as OpenCodeRunner).poll()
	_apply_git_refresh()


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
	session["state"] = "idle"
	ProfileStore.save_session(agent_id, session)
	set_state(agent_id, "idle")
	EventBus.agent_started.emit(agent_id)


func stop_agent(agent_id: String) -> void:
	var runner: OpenCodeRunner = _runners.get(agent_id)
	if runner != null and runner.running:
		runner.stop()
	set_state(agent_id, "offline")
	ProfileStore.save_session(agent_id, get_session(agent_id))
	EventBus.agent_stopped.emit(agent_id)


func send_task(agent_id: String, task: String) -> int:
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

	var session := get_session(agent_id)
	session["task"] = task
	session["state"] = "thinking"
	ProfileStore.save_session(agent_id, session)
	EventBus.agent_task_updated.emit(agent_id, task)
	set_state(agent_id, "thinking")
	if not _spawn_runner(agent_id, task):
		return TASK_LAUNCH_FAILED
	return TASK_OK


func send_chat_message(agent_id: String, content: String) -> int:
	return send_task(agent_id, "[Team chat] %s" % content)


func delete_session(agent_id: String) -> void:
	_detach_runner(agent_id)
	_reset_temp_skills(agent_id)
	emit_output(agent_id, "[session] deleted — next task starts fresh")
	set_state(agent_id, "offline")


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
		"title": override if not override.is_empty() else get_session_title(sid, _project_of(agent_id)),
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
	get_session(agent_id)["state"] = state
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


func get_session_title(session_id: String, project: String = "") -> String:
	if session_id.is_empty():
		return ""
	_ensure_session_titles(project)
	var title := str((_session_titles.get(project, {}) as Dictionary).get(session_id, ""))
	if title.is_empty() and not project.is_empty():
		_ensure_session_titles("")
		title = str((_session_titles.get("", {}) as Dictionary).get(session_id, ""))
	return title


func _project_of(agent_id: String) -> String:
	var profile := get_profile(agent_id)
	return profile.project if profile != null else ""


func _ensure_session_titles(project: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var loaded_at := float(_session_titles_loaded_at.get(project, -1.0))
	if loaded_at >= 0.0 and now - loaded_at < SESSION_TITLES_TTL:
		return
	_session_titles_loaded_at[project] = now
	_session_titles.erase(project)
	var output: Array = []
	var cmd := "opencode session list --format json -n 300 </dev/null"
	if not project.is_empty():
		cmd = "cd %s && %s" % [_shell_quote(project), cmd]
	if OS.execute("bash", ["-c", cmd], output, false, false) != OK:
		return
	var parsed = JSON.parse_string(_extract_json("\n".join(output)))
	if not parsed is Array:
		return
	var titles: Dictionary = {}
	for entry in parsed:
		if entry is Dictionary:
			var id := str(entry.get("id", ""))
			if not id.is_empty():
				titles[id] = str(entry.get("title", ""))
	_session_titles[project] = titles


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
	var ts := Time.get_unix_time_from_system() * 1000
	ProfileStore.append_chat_message(sender, "[error] " + message, [], ts, true)
	EventBus.chat_message.emit(sender, "[error] " + message, [], ts, true)


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
	session["state"] = "success"
	ProfileStore.save_session(agent_id, session)
	set_state(agent_id, "success")
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
	var ts := Time.get_unix_time_from_system() * 1000
	ProfileStore.append_chat_message(profile.name, reply, [], ts, true)
	EventBus.chat_message.emit(profile.name, reply, [], ts, true)


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
