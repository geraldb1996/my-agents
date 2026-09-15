class_name OpenCodeRunner
extends Node

signal event_received(agent_id: String, event: Dictionary)
signal process_finished(agent_id: String, exit_code: int)

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
var running: bool = false
var stall_timeout_ms: int = 120000

var _prompt: String = ""
var _http: HTTPClient
var _sse_buffer: String = ""
var _sse_requested: bool = false
var _sse_connected: bool = false
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

	if agent_id.is_empty() or project.is_empty():
		return false

	_prompt = _build_prompt()
	_http = null
	_sse_buffer = ""
	_sse_requested = false
	_sse_connected = false
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
	OpenCodeServer.ensure_ready(_on_server_ready)
	return true


func poll() -> void:
	if not running:
		return
	_pump_stream()
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
	var body := {"reply": reply}
	if not message.is_empty():
		body["message"] = message
	OpenCodeServer.post("/permission/%s/reply?directory=%s" % [request_id, _dir_query()], body, _on_reply_result.bind("permission"))
	_awaiting_user = false
	_last_activity_ms = Time.get_ticks_msec()


func reply_question(request_id: String, answers: Array) -> void:
	OpenCodeServer.post("/question/%s/reply?directory=%s" % [request_id, _dir_query()], {"answers": answers}, _on_reply_result.bind("question"))
	_awaiting_user = false
	_last_activity_ms = Time.get_ticks_msec()


func reject_question(request_id: String) -> void:
	OpenCodeServer.post("/question/%s/reject?directory=%s" % [request_id, _dir_query()], {}, _on_reply_result.bind("question"))
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
		_fail("Failed to start opencode server. Is it in PATH?")
		return
	if session_id.is_empty():
		OpenCodeServer.post("/session?directory=%s" % _dir_query(), {}, _on_session_created)
	else:
		_start_stream()


func _on_session_created(code: int, data: Variant) -> void:
	if not running:
		return
	if code < 200 or code >= 300 or not (data is Dictionary) or str((data as Dictionary).get("id", "")).is_empty():
		_fail("Failed to create opencode session (HTTP %d)" % code)
		return
	session_id = str((data as Dictionary)["id"])
	event_received.emit(agent_id, {"type": "session_created", "sessionID": session_id})
	_start_stream()


func _start_stream() -> void:
	_http = HTTPClient.new()
	if _http.connect_to_host(OpenCodeServer.HOST, OpenCodeServer.port()) != OK:
		_fail("Failed to connect to opencode server")


func _send_prompt() -> void:
	var body := {"parts": [{"type": "text", "text": _prompt}]}
	if not model.is_empty():
		var parts := model.split("/", true, 1)
		body["model"] = {"providerID": parts[0], "modelID": parts[1] if parts.size() > 1 else parts[0]}
	if not variant.is_empty():
		body["variant"] = variant
	if not opencode_agent.is_empty():
		body["agent"] = opencode_agent
	OpenCodeServer.post("/session/%s/prompt_async?directory=%s" % [session_id, _dir_query()], body, _on_prompt_accepted)


func _on_prompt_accepted(code: int, _data: Variant) -> void:
	if not running:
		return
	if code != 200 and code != 204:
		_fail("opencode rejected the prompt (HTTP %d)" % code)


func _pump_stream() -> void:
	if _http == null:
		return
	_http.poll()
	var status := _http.get_status()
	if status == HTTPClient.STATUS_CONNECTED:
		if not _sse_requested:
			if _http.request(HTTPClient.METHOD_GET, "/event?directory=%s" % _dir_query(), ["Accept: text/event-stream"]) != OK:
				_fail("Failed to subscribe to opencode events")
				return
			_sse_requested = true
		return
	if status == HTTPClient.STATUS_BODY:
		if not _sse_connected:
			_sse_connected = true
			_send_prompt()
		var chunk := _http.read_response_body_chunk()
		while chunk.size() > 0:
			_sse_buffer += chunk.get_string_from_utf8()
			chunk = _http.read_response_body_chunk()
		_consume_sse()
		return
	if status == HTTPClient.STATUS_DISCONNECTED and _sse_connected:
		_finish(0 if _completed_ok and not _prompt_failed else -1)


func _consume_sse() -> void:
	_sse_buffer = _sse_buffer.replace("\r\n", "\n")
	while true:
		var idx := _sse_buffer.find("\n\n")
		if idx < 0:
			break
		var block := _sse_buffer.substr(0, idx)
		_sse_buffer = _sse_buffer.substr(idx + 2)
		var data := ""
		for line in block.split("\n"):
			if line.begins_with("data:"):
				data += line.substr(5).strip_edges()
		if data.is_empty():
			continue
		var parsed = JSON.parse_string(data)
		if parsed is Dictionary:
			_handle_sse_event(parsed)


func _handle_sse_event(event: Dictionary) -> void:
	var etype := str(event.get("type", ""))
	var props: Variant = event.get("properties", {})
	if not props is Dictionary:
		props = {}
	var data: Dictionary = props
	var sid := str(data.get("sessionID", ""))
	if sid.is_empty():
		var part: Variant = data.get("part", {})
		if part is Dictionary:
			sid = str((part as Dictionary).get("sessionID", ""))
	if not sid.is_empty() and sid != session_id:
		return
	_last_activity_ms = Time.get_ticks_msec()
	match etype:
		"message.part.updated":
			var part: Variant = data.get("part", {})
			if part is Dictionary:
				_stream_parts[str(part.get("id", ""))] = part.duplicate(true)
				_forward_part(part)
		"message.part.delta":
			var pid := str(data.get("partID", ""))
			if str(data.get("field", "")) == "text" and _stream_parts.has(pid):
				var part: Dictionary = _stream_parts[pid]
				part["text"] = str(part.get("text", "")) + str(data.get("delta", ""))
				_forward_part(part)
		"permission.asked":
			_awaiting_user = true
			event_received.emit(agent_id, {"type": "permission_asked", "request": data})
		"permission.replied":
			_awaiting_user = false
			event_received.emit(agent_id, {"type": "permission_replied", "request_id": str(data.get("requestID", ""))})
		"question.asked":
			_awaiting_user = true
			event_received.emit(agent_id, {"type": "question_asked", "request": data})
		"question.replied", "question.rejected":
			_awaiting_user = false
			event_received.emit(agent_id, {"type": "question_resolved", "request_id": str(data.get("requestID", ""))})
		"session.error":
			_prompt_failed = true
			event_received.emit(agent_id, {"type": "error", "error": data.get("error", {})})
		"session.status":
			var status: Variant = data.get("status", {})
			if _sse_connected and not _finished and status is Dictionary and str((status as Dictionary).get("type", "")) == "idle":
				_finish(0 if _completed_ok and not _prompt_failed else -1)


func _forward_part(part: Dictionary) -> void:
	var ptype := str(part.get("type", ""))
	var pid := str(part.get("id", ""))
	match ptype:
		"reasoning":
			var text := str(part.get("text", ""))
			var previous := str(_reasoning_text.get(pid, ""))
			if text.is_empty() or text == previous:
				return
			_reasoning_text[pid] = text
			var delta := text.substr(previous.length()) if text.begins_with(previous) else text
			var streamed := part.duplicate(true)
			streamed["text"] = delta
			event_received.emit(agent_id, {"type": "reasoning", "part": streamed})
		"text":
			var time: Variant = part.get("time", {})
			if not (time is Dictionary) or int((time as Dictionary).get("end", 0)) <= 0:
				return
			if _seen.has(pid):
				return
			_seen[pid] = true
			event_received.emit(agent_id, {"type": ptype, "part": part})
		"step-start", "step-finish":
			if _seen.has(pid):
				return
			_seen[pid] = true
			if ptype == "step-finish" and str(part.get("reason", "")) == "stop":
				_completed_ok = true
			event_received.emit(agent_id, {"type": ptype.replace("-", "_"), "part": part})
		"tool":
			var state: Variant = part.get("state", {})
			var status := ""
			if state is Dictionary:
				status = str((state as Dictionary).get("status", ""))
			var key := pid + ":" + status
			if _seen.has(key):
				return
			_seen[key] = true
			event_received.emit(agent_id, {"type": "tool_use", "part": part})


func _finish(code: int) -> void:
	if _finished:
		return
	_finished = true
	running = false
	if _http != null:
		_http.close()
		_http = null
	process_finished.emit(agent_id, code)


func _fail(message: String) -> void:
	_last_error = message
	event_received.emit(agent_id, {"type": "runner_error", "message": message})
	_finish(-1)


func _abort() -> void:
	if session_id.is_empty() or not OpenCodeServer.is_ready():
		return
	OpenCodeServer.post("/session/%s/abort?directory=%s" % [session_id, _dir_query()], {})


func _dir_query() -> String:
	return project.uri_encode()


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
	if not temp_context.is_empty():
		parts.append("Temporary skill instructions (session only):\n%s" % temp_context)
	if not task.is_empty():
		parts.append(task)
	return "\n".join(parts)
