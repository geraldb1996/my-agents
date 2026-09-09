extends Node

const TOOL_STATES := {
	"bash": "terminal",
	"edit": "coding",
	"multi_edit": "coding",
	"patch": "coding",
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

const CONTEXT_LIMIT := 200000

var sessions: Dictionary = {}
var selected_agent_id: String = ""

var _runners: Dictionary = {}
var _pending_thinking: Dictionary = {}
var _pending_response: Dictionary = {}
var _posted_reply: Dictionary = {}
var _git_refresh_queue: Dictionary = {}
var _git_timers: Dictionary = {}


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


func reset_session(agent_id: String) -> void:
	var runner: OpenCodeRunner = _runners.get(agent_id)
	if runner != null and runner.running:
		runner.stop()
	_runners.erase(agent_id)
	ProfileStore.delete_session(agent_id)
	sessions.erase(agent_id)
	_pending_thinking.erase(agent_id)
	_pending_response.erase(agent_id)
	_posted_reply.erase(agent_id)
	emit_output(agent_id, "[session] reset — next task starts fresh")
	set_state(agent_id, "offline")


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


func add_temp_skill(agent_id: String, skill: String) -> void:
	var profile := get_profile(agent_id)
	if profile == null:
		return
	profile.add_temp_skill(skill)
	emit_output(agent_id, "[skills] temp skill added: %s" % skill)


func clear_temp_skills(agent_id: String) -> void:
	var profile := get_profile(agent_id)
	if profile == null:
		return
	profile.temp_skills.clear()
	emit_output(agent_id, "[skills] temp skills cleared")


func set_state(agent_id: String, state: String) -> void:
	get_session(agent_id)["state"] = state
	EventBus.agent_state_changed.emit(agent_id, state)


func emit_output(agent_id: String, line: String) -> void:
	EventBus.agent_output.emit(agent_id, line)


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

	var started := runner.start({
		"agent_id": agent_id,
		"project": profile.project,
		"model": profile.model,
		"variant": profile.model_variant,
		"opencode_agent": profile.opencode_agent,
		"session_id": str(session.get("opencode_session", "")),
		"task": task,
		"skills_context": ", ".join(profile.get_all_skills()),
	})
	if not started:
		emit_chat_error(agent_id, "Failed to launch opencode CLI. Is it in PATH?")
		runner.queue_free()
		_runners.erase(agent_id)
		set_state(agent_id, "error")
		return false

	runner.event_received.connect(_handle_event)
	runner.process_finished.connect(_on_process_finished)
	emit_output(agent_id, "[start] opencode run (session: %s)" % str(session.get("opencode_session", "new")))
	queue_git_refresh(agent_id, 1.5)
	return true


func _on_process_finished(agent_id: String, exit_code: int) -> void:
	var runner: OpenCodeRunner = _runners.get(agent_id)
	if runner != null and not runner.running:
		_runners.erase(agent_id)
		runner.queue_free()
	if exit_code != 0:
		emit_chat_error(agent_id, "Process exited with code %d" % exit_code)
		set_state(agent_id, "error")
	else:
		if not _posted_reply.get(agent_id, false):
			_post_reply(agent_id)
		emit_output(agent_id, "[end] done")
	queue_git_refresh(agent_id, 0.5)


func _handle_event(agent_id: String, event: Dictionary) -> void:
	if not sessions.has(agent_id):
		return
	var session: Dictionary = sessions[agent_id]
	var etype: String = str(event.get("type", ""))
	var psession: String = str(event.get("sessionID", ""))
	if not psession.is_empty() and str(session.get("opencode_session", "")).is_empty():
		session["opencode_session"] = psession
		ProfileStore.save_session(agent_id, session)

	var part: Dictionary = event.get("part", {})
	if part is not Dictionary:
		part = {}

	match etype:
		"step_start":
			set_state(agent_id, "thinking")
		"reasoning":
			var reason_text: String = str(part.get("text", ""))
			if not reason_text.is_empty():
				_pending_thinking[agent_id] = _pending_thinking.get(agent_id, "") + reason_text
				emit_output(agent_id, "[think] " + reason_text)
		"text":
			if str(part.get("type", "")) == "text":
				var text: String = str(part.get("text", ""))
				if not text.is_empty():
					_pending_response[agent_id] = _pending_response.get(agent_id, "") + text
		"tool_use":
			if str(part.get("type", "")) == "tool":
				_handle_tool(agent_id, part)
		"step_finish":
			_emit_context_usage(agent_id, part)
			if str(part.get("reason", "")) == "stop":
				_finish_task(agent_id)
			else:
				set_state(agent_id, "working")
		_:
			if etype.contains("permission"):
				set_state(agent_id, "approval")


func _emit_context_usage(agent_id: String, part: Dictionary) -> void:
	var tokens: Dictionary = part.get("tokens", {})
	if tokens is not Dictionary:
		tokens = {}
	var input_tokens := int(tokens.get("input", 0))
	var cache_read := 0
	var cache: Variant = tokens.get("cache", {})
	if cache is Dictionary:
		cache_read = int(cache.get("read", 0))
	var context_tokens := input_tokens + cache_read
	var pct := clampf(float(context_tokens) / float(CONTEXT_LIMIT) * 100.0, 0.0, 100.0)
	EventBus.agent_context_usage.emit(agent_id, pct, context_tokens)


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
	elif tool_name in ["edit", "write", "patch"]:
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
			_flash_state(agent_id, "success", 1.2)
		"error":
			emit_output(agent_id, "! %s (error)" % note)
			set_state(agent_id, "error")
		_:
			set_state(agent_id, base_state)

	if tool_name in ["bash", "edit", "write", "patch"]:
		queue_git_refresh(agent_id, 1.0)


func _finish_task(agent_id: String) -> void:
	_post_reply(agent_id)
	var session := get_session(agent_id)
	session["task"] = ""
	session["state"] = "success"
	ProfileStore.save_session(agent_id, session)
	set_state(agent_id, "success")
	await get_tree().create_timer(2.5).timeout
	if sessions.has(agent_id) and str(sessions[agent_id].get("state", "")) == "success":
		set_state(agent_id, "idle")


func _post_reply(agent_id: String) -> void:
	if _posted_reply.get(agent_id, false):
		return
	var reply: String = _pending_response.get(agent_id, "").strip_edges()
	_pending_response[agent_id] = ""
	_pending_thinking.erase(agent_id)
	if reply.is_empty():
		return
	_posted_reply[agent_id] = true
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
	var output: Array = []
	var err := OS.execute("git", ["-C", profile.project, "status", "--porcelain", "-b"], output, true, false)
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
		var trimmed := line.strip_edges()
		if trimmed.is_empty():
			continue
		if trimmed.length() > 3:
			files.append(trimmed.substr(3))
	EventBus.agent_git_status.emit(agent_id, branch, text)
	EventBus.agent_files_changed.emit(agent_id, files)
