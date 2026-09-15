extends Node

var _messages: Array[String] = []

const CASES := [
	{"text": "reasoning line\nCHAT: hello team", "chat": "hello team", "think": "reasoning line"},
	{"text": "CHAT: only message", "chat": "only message", "think": ""},
	{"text": "no marker at all", "chat": "no marker at all", "think": ""},
	{"text": "a\nchat: lower marker\nb", "chat": "lower marker\nb", "think": "a"},
	{"text": "  CHAT:   padded  ", "chat": "padded", "think": ""},
]


func _ready() -> void:
	var ok := true
	for c in CASES:
		var result: Dictionary = AgentManager._split_chat_reply(str(c["text"]))
		var got_chat := str(result["chat"])
		var got_think := str(result["thinking"])
		var passed: bool = got_chat == str(c["chat"]) and got_think == str(c["think"])
		ok = ok and passed
		print("[CHATTEST] pass=", passed, " chat=", got_chat, " think=", got_think)
	ok = _test_live_messages() and ok
	print("[CHATTEST] RESULT=", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)


func _test_live_messages() -> bool:
	var profile := AgentProfile.new()
	profile.id = "chat_stream_test_%d" % Time.get_ticks_usec()
	profile.name = profile.id
	ProfileStore.profiles[profile.id] = profile
	AgentManager.sessions[profile.id] = {"state": "working", "task": "test"}
	var saved_history := ProfileStore.chat_history.duplicate(true)
	var receive := func(sender: String, content: String, _mentions: Array, _timestamp: int, _is_agent: bool) -> void:
		if sender == profile.name:
			_messages.append(content)
	EventBus.chat_message.connect(receive)
	var runner := OpenCodeRunner.new()
	add_child(runner)
	runner.agent_id = profile.id
	runner.session_id = "ses_chat_test"
	runner.running = true
	runner._sse_connected = true
	runner.event_received.connect(AgentManager._handle_event)
	runner.process_finished.connect(AgentManager._on_process_finished)
	var first := {"id": "text_1", "messageID": "same_message", "sessionID": runner.session_id, "type": "text", "text": "Agregaré doble clic"}
	_send_part(runner, first)
	var ok := _messages.is_empty()
	first["time"] = {"end": 1}
	_send_part(runner, first)
	ok = ok and _messages == ["Agregaré doble clic"] and runner.running
	ok = ok and AgentManager.get_session(profile.id)["task"] == "test"
	ProfileStore.load_chat_history()
	ok = ok and ProfileStore.chat_history.size() == saved_history.size() + 1
	_send_part(runner, first)
	_send_part(runner, {"id": "reason_1", "sessionID": runner.session_id, "type": "reasoning", "text": "pensamiento interno"})
	ok = ok and _messages.size() == 1 and AgentManager.get_output_history(profile.id).has("[think] pensamiento interno")
	var second := {"id": "text_2", "messageID": "same_message", "sessionID": runner.session_id, "type": "text", "text": "CHAT"}
	_send_part(runner, second)
	runner._handle_sse_event({"type": "message.part.delta", "properties": {"sessionID": runner.session_id, "partID": "text_2", "field": "text", "delta": ": Cambio listo"}})
	ok = ok and _messages.size() == 1
	second["text"] = "CHAT: Cambio listo"
	second["time"] = {"end": 2}
	_send_part(runner, second)
	_send_part(runner, second)
	ok = ok and _messages == ["Agregaré doble clic", "Cambio listo"] and runner.running
	_send_part(runner, {"id": "finish", "sessionID": runner.session_id, "type": "step-finish", "reason": "stop"})
	runner._handle_sse_event({"type": "session.status", "properties": {"sessionID": runner.session_id, "status": {"type": "idle"}}})
	ok = ok and _messages == ["Agregaré doble clic", "Cambio listo"] and not runner.running
	ProfileStore.load_chat_history()
	ok = ok and ProfileStore.chat_history.size() == saved_history.size() + 2
	EventBus.chat_message.disconnect(receive)
	ProfileStore.chat_history = saved_history
	ProfileStore._write_text(ProfileStore.CHAT_PATH, JSON.stringify(saved_history, "\t"))
	ProfileStore.profiles.erase(profile.id)
	AgentManager.sessions.erase(profile.id)
	AgentManager._output_history.erase(profile.id)
	AgentManager._last_reasoning_part.erase(profile.id)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ProfileStore.SESSIONS_DIR.path_join(profile.id + ".json")))
	runner.queue_free()
	print("[CHATTEST] immediate/separate/deduplicated/persisted=", ok)
	return ok


func _send_part(runner: OpenCodeRunner, part: Dictionary) -> void:
	runner._handle_sse_event({"type": "message.part.updated", "properties": {"part": part}})
