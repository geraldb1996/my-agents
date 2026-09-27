extends Node

var _events: Array[Dictionary] = []
var _finished := -99


func _ready() -> void:
	var runner := OpenCodeRunner.new()
	add_child(runner)
	runner.agent_id = "flow_agent"
	runner.session_id = "ses_test"
	runner.running = true
	runner._last_activity_ms = Time.get_ticks_msec()
	runner.event_received.connect(func(_id: String, event: Dictionary) -> void: _events.append(event))
	runner.process_finished.connect(func(_id: String, code: int) -> void: _finished = code)

	runner._message_ids["msg_old"] = true
	runner._handle_message({"id": "msg_old", "type": "assistant", "content": [{"type": "text", "text": "old"}]})
	runner._handle_message({"id": "msg_new", "type": "assistant", "time": {"created": 1}, "content": [{"type": "reasoning", "text": "think"}, {"type": "text", "text": "partial"}]})
	runner._handle_message({"id": "msg_new", "type": "assistant", "time": {"created": 1, "completed": 2}, "finish": "stop", "tokens": {"input": 10, "output": 4}, "cost": 0.01, "content": [{"type": "reasoning", "text": "thinking"}, {"type": "text", "text": "CHAT: hello team"}]})
	runner._handle_message({"id": "msg_new", "type": "assistant", "time": {"created": 1, "completed": 2}, "finish": "stop", "content": []})
	runner._on_permissions(200, {"data": [{"id": "per_test", "sessionID": "ses_test", "action": "shell", "resources": ["git status"], "save": ["git status"]}]})
	runner._on_forms(200, {"data": [{"id": "frm_test", "sessionID": "ses_test", "title": "Choose", "fields": [{"key": "choice", "type": "string", "title": "Which?", "options": [{"label": "First", "value": "one"}]}]}]})
	runner._on_permissions(200, {"data": []})
	runner._on_forms(200, {"data": []})
	runner._handle_message({"id": "msg_idle", "type": "idle", "outcome": "succeeded"})

	var types: Array[String] = []
	for event in _events:
		types.append(str(event.get("type", "")))
	var expected: Array[String] = ["reasoning", "reasoning", "text", "step_finish", "permission_asked", "question_asked", "permission_replied", "question_resolved"]
	var ok: bool = types == expected and _events[1]["part"]["text"] == "ing" and _events[2]["part"]["text"] == "CHAT: hello team" and _events[4]["request"]["permission"] == "shell" and _events[5]["request"]["questions"][0]["options"][0]["value"] == "one" and _finished == 0
	print("[FLOWTEST] events=", types)
	print("[FLOWTEST] RESULT=", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
