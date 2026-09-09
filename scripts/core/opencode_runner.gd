class_name OpenCodeRunner
extends Node

signal event_received(agent_id: String, event: Dictionary)
signal process_finished(agent_id: String, exit_code: int)

var agent_id: String = ""
var project: String = ""
var model: String = ""
var variant: String = ""
var opencode_agent: String = ""
var session_id: String = ""
var task: String = ""
var skills_context: String = ""
var running: bool = false

var _pid: int = -1
var _out_path: String = ""
var _buffer: String = ""
var _last_text: String = ""
var _completed_ok: bool = false
var _stopped_by_user: bool = false


func start(opts: Dictionary) -> bool:
	agent_id = str(opts.get("agent_id", ""))
	project = str(opts.get("project", ""))
	model = str(opts.get("model", ""))
	variant = str(opts.get("variant", ""))
	opencode_agent = str(opts.get("opencode_agent", ""))
	session_id = str(opts.get("session_id", ""))
	task = str(opts.get("task", ""))
	skills_context = str(opts.get("skills_context", ""))

	if agent_id.is_empty() or project.is_empty():
		return false

	var args := PackedStringArray(["run", "--format", "json", "--thinking"])
	if not model.is_empty():
		args.append_array(["-m", model])
	if not variant.is_empty():
		args.append_array(["--variant", variant])
	if not opencode_agent.is_empty():
		args.append_array(["--agent", opencode_agent])
	if not session_id.is_empty():
		args.append_array(["-s", session_id])
	args.append_array(["--dir", project])
	args.append(_build_prompt())

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tmp"))
	_out_path = "user://tmp/%s.out" % agent_id
	var out := ProjectSettings.globalize_path(_out_path)
	var quoted: Array[String] = []
	for a in args:
		quoted.append(_shell_quote(a))
	var shell_cmd := "exec opencode %s > %s 2>&1" % [" ".join(quoted), _shell_quote(out)]
	_pid = OS.create_process("bash", ["-c", shell_cmd], false)
	if _pid <= 0:
		return false

	_buffer = ""
	_last_text = ""
	_completed_ok = false
	_stopped_by_user = false
	running = true
	return true


func stop() -> void:
	_stopped_by_user = true
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	if running:
		running = false
		process_finished.emit(agent_id, 0 if _completed_ok or _stopped_by_user else -1)


func poll() -> void:
	if not running:
		return
	var file := FileAccess.open(_out_path, FileAccess.READ)
	if file != null:
		var text := _read_file(file)
		file.close()
		if text.begins_with(_last_text):
			var new_part := text.substr(_last_text.length())
			_last_text = text
			_buffer += new_part
		else:
			_last_text = text
			_buffer = ""
		_consume_lines()

	if _pid > 0 and not OS.is_process_running(_pid):
		running = false
		process_finished.emit(agent_id, 0 if _completed_ok else -1)


func _read_file(file: FileAccess) -> String:
	var bytes := file.get_buffer(file.get_length())
	return bytes.get_string_from_utf8()


func _build_prompt() -> String:
	var parts: Array[String] = []
	if session_id.is_empty():
		var intro := "You are %s, an AI agent in a team working through OpenCode CLI." % agent_id
		parts.append(intro)
		if not skills_context.is_empty():
			parts.append("Your skills: %s" % skills_context)
	if not task.is_empty():
		parts.append(task)
	return "\n".join(parts)


func _consume_lines() -> void:
	while _buffer.contains("\n"):
		var idx := _buffer.find("\n")
		var line := _buffer.substr(0, idx).strip_edges()
		_buffer = _buffer.substr(idx + 1)
		if line.is_empty():
			continue
		_parse_line(line)


func _shell_quote(s: String) -> String:
	return "'" + s.replace("'", "'\\''") + "'"


func _parse_line(line: String) -> void:
	var parsed = JSON.parse_string(line)
	if parsed is Dictionary:
		var event: Dictionary = parsed
		if str(event.get("type", "")) == "step_finish" and str(event.get("part", {}).get("reason", "")) == "stop":
			_completed_ok = true
		event_received.emit(agent_id, event)
