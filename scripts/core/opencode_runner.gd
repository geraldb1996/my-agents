class_name OpenCodeRunner
extends Node

signal event_received(agent_id: String, event: Dictionary)
signal process_finished(agent_id: String, exit_code: int)

const POLL_INTERVAL_MS := 600

var agent_id: String = ""
var agent_name: String = ""
var project: String = ""
var model: String = ""
var variant: String = ""
var opencode_agent: String = ""
var session_id: String = ""
var task: String = ""
var personality: String = ""
var skills_context: String = ""
var temp_context: String = ""
var team_context: String = ""
var running: bool = false
var stall_timeout_ms: int = 120000

var _prompt: String = ""
var _poll_pending: bool = false
var _prompt_submitted: bool = false
var _next_poll_ms: int = 0
var _message_ids: Dictionary = {}
var _permission_ids: Dictionary = {}
var _form_ids: Dictionary = {}
var _finished: bool = false
var _completed_ok: bool = false
var _prompt_failed: bool = false
var _awaiting_user: bool = false
var _last_error: String = ""
var _last_activity_ms: int = 0
var _seen: Dictionary = {}
var _stream_parts: Dictionary = {}
var _reasoning_text: Dictionary = {}


func start(opts: Dictionary) -> bool:
	agent_id = str(opts.get("agent_id", ""))
	agent_name = str(opts.get("agent_name", ""))
	project = _expand_home(str(opts.get("project", "")))
	model = str(opts.get("model", ""))
	variant = str(opts.get("variant", ""))
	opencode_agent = str(opts.get("opencode_agent", ""))
	session_id = str(opts.get("session_id", ""))
	task = str(opts.get("task", ""))
	personality = str(opts.get("personality", ""))
	skills_context = str(opts.get("skills_context", ""))
	temp_context = str(opts.get("temp_context", ""))
	team_context = str(opts.get("team_context", ""))

	if agent_id.is_empty() or project.is_empty():
		return false

	_prompt = _build_prompt()
	_poll_pending = false
	_prompt_submitted = false
	_next_poll_ms = 0
	_message_ids.clear()
	_permission_ids.clear()
	_form_ids.clear()
	_finished = false
	_completed_ok = false
	_prompt_failed = false
	_awaiting_user = false
	_last_error = ""
	_seen.clear()
	_stream_parts.clear()
	_reasoning_text.clear()
	_last_activity_ms = Time.get_ticks_msec()
	running = true
	OpenCodeServer.ensure_ready(_on_server_ready, agent_id)
	return true


func poll() -> void:
	if not running:
		return
	if _prompt_submitted and not _poll_pending and Time.get_ticks_msec() >= _next_poll_ms and not session_id.is_empty():
		_poll_messages()
	if not running:
		return
	if stall_timeout_ms > 0 and not _awaiting_user and Time.get_ticks_msec() - _last_activity_ms > stall_timeout_ms:
		_last_error = "No activity for %d s. The model/provider may be unresponsive or rate-limited." % int(stall_timeout_ms / 1000)
		_abort()
		_finish(-2)


func stop() -> void:
	if not running:
		return
	_abort()
	_finish(0)


func reply_permission(request_id: String, reply: String, message: String = "") -> void:
	var body := {"decision": reply}
	if not message.is_empty():
		body["message"] = message
	OpenCodeServer.post("/api/session/%s/permission/%s/reply" % [session_id, request_id], body, _on_reply_result.bind("permission"))
	_awaiting_user = false
	_last_activity_ms = Time.get_ticks_msec()


func reply_question(request_id: String, answers: Array) -> void:
	var answer := {}
	var fields: Array = _form_ids.get(request_id, [])
	for i in mini(answers.size(), fields.size()):
		var field: Dictionary = fields[i]
		var selected: Array = answers[i]
		var values := []
		for label in selected:
			var value := str(label)
			for option in field.get("options", []):
				if option is Dictionary and str(option.get("label", "")) == value:
					value = str(option.get("value", value))
					break
			values.append(value)
		if str(field.get("type", "")) == "multiselect":
			answer[str(field.get("key", ""))] = values
		elif not values.is_empty():
			answer[str(field.get("key", ""))] = values[0]
	OpenCodeServer.post("/api/session/%s/form/%s/reply" % [session_id, request_id], {"answer": answer}, _on_reply_result.bind("question"))
	_awaiting_user = false
	_last_activity_ms = Time.get_ticks_msec()


func reject_question(request_id: String) -> void:
	OpenCodeServer.delete_json("/api/session/%s/form/%s" % [session_id, request_id], _on_reply_result.bind("question"))
	_awaiting_user = false
	_last_activity_ms = Time.get_ticks_msec()


func _on_reply_result(code: int, _data: Variant, kind: String) -> void:
	if code >= 200 and code < 300:
		return
	event_received.emit(agent_id, {"type": "runner_error", "message": "%s reply failed (HTTP %d)" % [kind, code]})


func _on_server_ready(ok: bool) -> void:
	if not running:
		return
	if not ok:
		_fail(OpenCodeServer.startup_error())
		return
	if session_id.is_empty():
		OpenCodeServer.post("/api/session", {"location": {"directory": project}}, _on_session_created)
	else:
		_load_baseline()


func _on_session_created(code: int, data: Variant) -> void:
	if not running:
		return
	var session: Variant = data.get("data", {}) if data is Dictionary else {}
	if code < 200 or code >= 300 or not (session is Dictionary) or str(session.get("id", "")).is_empty():
		_fail("Failed to create opencode session (HTTP %d)" % code)
		return
	session_id = str(session["id"])
	event_received.emit(agent_id, {"type": "session_created", "sessionID": session_id})
	_send_prompt()


func _load_baseline() -> void:
	OpenCodeServer.get_json("/api/session/%s/message?limit=100&order=desc" % session_id, func(code: int, response: Variant) -> void:
		if not running:
			return
		if code != 200 or not (response is Dictionary) or not (response.get("data") is Array):
			_fail("Failed to load opencode session messages (HTTP %d)" % code)
			return
		for message in response["data"]:
			if message is Dictionary:
				_message_ids[str(message.get("id", ""))] = true
		_send_prompt()
	)


func _send_prompt() -> void:
	var body := {"text": _prompt}
	if not model.is_empty():
		var parts := model.split("/", true, 1)
		var ref := {"providerID": parts[0], "id": parts[1] if parts.size() > 1 else parts[0]}
		if not variant.is_empty():
			ref["variant"] = variant
		OpenCodeServer.post("/api/session/%s/model" % session_id, {"model": ref}, _on_model_selected.bind(body))
	elif not opencode_agent.is_empty():
		_select_agent(body)
	else:
		_post_prompt(body)


func _on_model_selected(code: int, _data: Variant, body: Dictionary) -> void:
	if not running:
		return
	if code != 204:
		_fail("Failed to select opencode model (HTTP %d)" % code)
		return
	if not opencode_agent.is_empty():
		_select_agent(body)
	else:
		_post_prompt(body)


func _select_agent(body: Dictionary) -> void:
	OpenCodeServer.post("/api/session/%s/agent" % session_id, {"agent": opencode_agent}, func(code: int, _data: Variant) -> void:
		if not running:
			return
		if code != 204:
			_fail("Failed to select opencode agent (HTTP %d)" % code)
			return
		_post_prompt(body)
	)


func _post_prompt(body: Dictionary) -> void:
	OpenCodeServer.post("/api/session/%s/prompt" % session_id, body, _on_prompt_accepted)


func _on_prompt_accepted(code: int, _data: Variant) -> void:
	if not running:
		return
	if code != 200:
		_fail("opencode rejected the prompt (HTTP %d)" % code)
	else:
		_prompt_submitted = true
		_next_poll_ms = 0


func _poll_messages() -> void:
	_poll_pending = true
	OpenCodeServer.get_json("/api/session/%s/message?limit=100&order=desc" % session_id, _on_messages)


func _on_messages(code: int, response: Variant) -> void:
	_poll_pending = false
	_next_poll_ms = Time.get_ticks_msec() + POLL_INTERVAL_MS
	if not running:
		return
	if code != 200 or not (response is Dictionary) or not (response.get("data") is Array):
		_fail("Failed to read opencode messages (HTTP %d)" % code)
		return
	var messages: Array = response["data"]
	messages.reverse()
	for message in messages:
		if message is Dictionary:
			_handle_message(message)
			if not running:
				return
	_poll_requests()


func _handle_message(message: Dictionary) -> void:
	var mid := str(message.get("id", ""))
	if _message_ids.has(mid):
		return
	match str(message.get("type", "")):
		"assistant":
			for i in message.get("content", []).size():
				var part: Variant = message["content"][i]
				if part is Dictionary:
					_forward_content(mid, i, part, not (message.get("time", {}) as Dictionary).has("completed"))
			if message.has("error"):
				_prompt_failed = true
				event_received.emit(agent_id, {"type": "error", "error": message["error"]})
			if (message.get("time", {}) as Dictionary).has("completed"):
				_message_ids[mid] = true
				var finish := str(message.get("finish", ""))
				if finish == "stop":
					_completed_ok = true
				event_received.emit(agent_id, {"type": "step_finish", "part": {"reason": finish, "tokens": message.get("tokens", {}), "cost": message.get("cost", 0.0), "model": message.get("model", {})}})
			_last_activity_ms = Time.get_ticks_msec()
		"idle":
			_message_ids[mid] = true
			_finish(0 if str(message.get("outcome", "")) == "succeeded" and not _prompt_failed else -1)
		"user":
			_message_ids[mid] = true


func _forward_content(mid: String, index: int, part: Dictionary, streaming: bool) -> void:
	var pid := "%s:%d" % [mid, index]
	match str(part.get("type", "")):
		"reasoning":
			var text := str(part.get("text", ""))
			var previous := str(_reasoning_text.get(pid, ""))
			if text != previous:
				_last_activity_ms = Time.get_ticks_msec()
				_reasoning_text[pid] = text
				var delta := text.substr(previous.length()) if text.begins_with(previous) else text
				event_received.emit(agent_id, {"type": "reasoning", "part": {"id": pid, "text": delta}})
		"text":
			if not streaming and not _seen.has(pid):
				_seen[pid] = true
				event_received.emit(agent_id, {"type": "text", "part": part})
		"tool":
			var state: Dictionary = part.get("state", {})
			var status := str(state.get("status", ""))
			if not _seen.has(pid + status):
				_last_activity_ms = Time.get_ticks_msec()
				_seen[pid + status] = true
				var legacy := part.duplicate(true)
				legacy["tool"] = str(part.get("name", ""))
				if status == "streaming":
					state["status"] = "running"
				event_received.emit(agent_id, {"type": "tool_use", "part": legacy})


func _poll_requests() -> void:
	OpenCodeServer.get_json("/api/session/%s/permission" % session_id, _on_permissions)
	OpenCodeServer.get_json("/api/session/%s/form" % session_id, _on_forms)


func _on_permissions(code: int, response: Variant) -> void:
	if not running or code != 200 or not (response is Dictionary):
		return
	var pending := {}
	for request in response.get("data", []):
		if not (request is Dictionary):
			continue
		var id := str(request.get("id", ""))
		pending[id] = true
		if not _permission_ids.has(id):
			_permission_ids[id] = true
			_awaiting_user = true
			var adapted: Dictionary = request.duplicate(true)
			adapted["permission"] = str(request.get("action", ""))
			adapted["patterns"] = request.get("resources", [])
			adapted["always"] = request.get("save", [])
			event_received.emit(agent_id, {"type": "permission_asked", "request": adapted})
	for id in _permission_ids.keys():
		if not pending.has(id):
			_permission_ids.erase(id)
			_awaiting_user = not _form_ids.is_empty()
			event_received.emit(agent_id, {"type": "permission_replied", "request_id": id})


func _on_forms(code: int, response: Variant) -> void:
	if not running or code != 200 or not (response is Dictionary):
		return
	var pending := {}
	for form in response.get("data", []):
		if not (form is Dictionary):
			continue
		var id := str(form.get("id", ""))
		pending[id] = true
		if not _form_ids.has(id):
			_form_ids[id] = form.get("fields", [])
			_awaiting_user = true
			var adapted: Dictionary = form.duplicate(true)
			adapted["questions"] = _form_questions(form)
			event_received.emit(agent_id, {"type": "question_asked", "request": adapted})
	for id in _form_ids.keys():
		if not pending.has(id):
			_form_ids.erase(id)
			_awaiting_user = not _permission_ids.is_empty()
			event_received.emit(agent_id, {"type": "question_resolved", "request_id": id})


func _form_questions(form: Dictionary) -> Array:
	var questions := []
	for field in form.get("fields", []):
		if field is Dictionary:
			var options := []
			for option in field.get("options", []):
				if option is Dictionary:
					options.append({"label": option.get("label", ""), "value": option.get("value", "")})
			questions.append({"header": field.get("title", form.get("title", "")), "question": field.get("description", ""), "options": options, "multiple": field.get("type", "") == "multiselect", "custom": field.get("custom", false) or options.is_empty()})
	return questions


func _finish(code: int) -> void:
	if _finished:
		return
	_finished = true
	running = false
	process_finished.emit(agent_id, code)


func _fail(message: String) -> void:
	_last_error = message
	event_received.emit(agent_id, {"type": "runner_error", "message": message})
	_finish(-1)


func _abort() -> void:
	if session_id.is_empty() or not OpenCodeServer.is_ready():
		return
	OpenCodeServer.post("/api/session/%s/interrupt" % session_id, {})


func _expand_home(path: String) -> String:
	if path.begins_with("~"):
		return OS.get_environment("HOME").path_join(path.substr(1).trim_prefix("/"))
	return path


func _build_prompt() -> String:
	var parts: Array[String] = []
	if session_id.is_empty():
		var display_name := agent_name if not agent_name.is_empty() else agent_id
		var intro := "You are %s, an AI agent in a team working through OpenCode CLI." % display_name
		parts.append(intro)
		var trimmed_personality := personality.strip_edges()
		if not trimmed_personality.is_empty():
			parts.append(trimmed_personality)
		if not skills_context.is_empty():
			parts.append("Your skills: %s" % skills_context)
		parts.append("RESPONSE FORMAT (mandatory): always start your final reply with 'CHAT:' followed by your message, for example: CHAT: your reply here. Never respond without this prefix.")
		var user_instruction := SystemSettings.get_user_instruction()
		if not user_instruction.is_empty():
			parts.append(user_instruction)
		var language_instruction := SystemSettings.get_agents_language_instruction()
		if not language_instruction.is_empty():
			parts.append(language_instruction)
	if not team_context.is_empty():
		parts.append("Your teammates: %s. To hand work to a teammate, mention @TheirName in your reply (use underscores for spaces), for example: @Elliot commit and push the changes. It is delivered as a new task to that agent." % team_context)
	if not temp_context.is_empty():
		parts.append("Temporary skill instructions (session only):\n%s" % temp_context)
	if not task.is_empty():
		parts.append(task)
	return "\n".join(parts)
