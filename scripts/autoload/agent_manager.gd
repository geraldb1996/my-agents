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

var sessions: Dictionary = {}
var selected_agent_id: String = ""

var _runners: Dictionary = {}
var _pending_text: Dictionary = {}
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


func send_task(agent_id: String, task: String) -> bool:
	var profile := get_profile(agent_id)
	if profile == null:
		return false
	if profile.project.is_empty():
		emit_output(agent_id, "[error] No project/workspace set. Select a folder first.")
		set_state(agent_id, "error")
		return false
	var runner: OpenCodeRunner = _runners.get(agent_id)
	if runner != null and runner.running:
		emit_output(agent_id, "[warn] Agent busy. Wait for the current task to finish.")
		return false

	var session := get_session(agent_id)
	session["task"] = task
	session["state"] = "thinking"
	ProfileStore.save_session(agent_id, session)
	EventBus.agent_task_updated.emit(agent_id, task)
	set_state(agent_id, "thinking")
	_spawn_runner(agent_id, task)
	return true


func send_chat_message(agent_id: String, content: String) -> bool:
	return send_task(agent_id, "[Team chat] %s" % content)


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


func _spawn_runner(agent_id: String, task: String) -> void:
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
		"opencode_agent": profile.opencode_agent,
		"session_id": str(session.get("opencode_session", "")),
		"task": task,
		"skills_context": ", ".join(profile.get_all_skills()),
	})
	if not started:
		emit_output(agent_id, "[error] Failed to launch opencode CLI. Is it in PATH?")
		runner.queue_free()
		_runners.erase(agent_id)
		set_state(agent_id, "error")
		return

	runner.event_received.connect(_handle_event)
	runner.process_finished.connect(_on_process_finished)
	emit_output(agent_id, "[start] opencode run (session: %s)" % str(session.get("opencode_session", "new")))
	queue_git_refresh(agent_id, 1.5)


func _on_process_finished(agent_id: String, exit_code: int) -> void:
	var runner: OpenCodeRunner = _runners.get(agent_id)
	if runner != null and not runner.running:
		_runners.erase(agent_id)
		runner.queue_free()
	if exit_code != 0:
		emit_output(agent_id, "[end] process exited with code %d" % exit_code)
		set_state(agent_id, "error")
	else:
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
		"text":
			if str(part.get("type", "")) == "text":
				var text: String = str(part.get("text", ""))
				if not text.is_empty():
					_pending_text[agent_id] = _pending_text.get(agent_id, "") + text
		"tool_use":
			if str(part.get("type", "")) == "tool":
				_handle_tool(agent_id, part)
		"step_finish":
			if str(part.get("reason", "")) == "stop":
				_finish_task(agent_id)
			else:
				set_state(agent_id, "working")
		_:
			if etype.contains("permission"):
				set_state(agent_id, "approval")


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
			if tool_name == "ask_user":
				set_state(agent_id, "question")
			else:
				set_state(agent_id, base_state)
		"running":
			set_state(agent_id, base_state)
			emit_output(agent_id, "> %s" % note)
		"completed":
			emit_output(agent_id, "+ %s" % note)
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
	var reply: String = _pending_text.get(agent_id, "").strip_edges()
	_pending_text[agent_id] = ""
	var profile := get_profile(agent_id)
	if not reply.is_empty() and profile != null:
		var ts := Time.get_unix_time_from_system() * 1000
		ProfileStore.append_chat_message(profile.name, reply, [], ts, true)
		EventBus.chat_message.emit(profile.name, reply, [], ts, true)
	var session := get_session(agent_id)
	session["task"] = ""
	session["state"] = "success"
	ProfileStore.save_session(agent_id, session)
	set_state(agent_id, "success")
	await get_tree().create_timer(2.5).timeout
	if sessions.has(agent_id) and str(sessions[agent_id].get("state", "")) == "success":
		set_state(agent_id, "idle")


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