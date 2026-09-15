extends Node

var _events: Array[Dictionary] = []
var _finished := -99


func _ready() -> void:
	var runner := OpenCodeRunner.new()
	add_child(runner)
	runner.agent_id = "flow_agent"
	runner.session_id = "ses_test"
	runner.running = true
	runner._sse_connected = true
	runner._last_activity_ms = Time.get_ticks_msec()
	runner.event_received.connect(func(_id: String, event: Dictionary) -> void: _events.append(event))
	runner.process_finished.connect(func(_id: String, code: int) -> void: _finished = code)

	runner._handle_sse_event({"type": "message.part.updated", "properties": {"sessionID": "ses_test", "part": {"id": "prt_t1", "sessionID": "ses_test", "type": "text", "text": "partial"}}})
	runner._handle_sse_event({"type": "message.part.updated", "properties": {"sessionID": "ses_test", "part": {"id": "prt_t1", "sessionID": "ses_test", "type": "text", "text": "hello team", "time": {"start": 1, "end": 2}}}})
	runner._handle_sse_event({"type": "message.part.updated", "properties": {"part": {"id": "prt_r1", "sessionID": "ses_test", "type": "reasoning", "text": "", "time": {"start": 1}}}})
	runner._handle_sse_event({"type": "message.part.delta", "properties": {"sessionID": "other_session", "partID": "prt_r1", "field": "text", "delta": "ignore"}})
	runner._handle_sse_event({"type": "message.part.delta", "properties": {"sessionID": "ses_test", "partID": "prt_r1", "field": "text", "delta": "think"}})
	var streamed_before_end: bool = _events.size() == 2 and _events[1]["part"]["text"] == "think"
	runner._handle_sse_event({"type": "message.part.updated", "properties": {"part": {"id": "prt_r1", "sessionID": "ses_test", "type": "reasoning", "text": "thinking", "time": {"start": 1}}}})
	runner._handle_sse_event({"type": "message.part.updated", "properties": {"part": {"id": "prt_r1", "sessionID": "ses_test", "type": "reasoning", "text": "thinking", "time": {"start": 1, "end": 2}}}})
	runner._handle_sse_event({"type": "message.part.updated", "properties": {"sessionID": "ses_test", "part": {"id": "prt_s1", "sessionID": "ses_test", "type": "step-start"}}})
	runner._handle_sse_event({"type": "permission.asked", "properties": {"id": "per_x", "sessionID": "ses_test", "permission": "bash", "patterns": ["rm -rf"]}})
	runner._handle_sse_event({"type": "question.asked", "properties": {"id": "que_x", "sessionID": "ses_test", "questions": []}})
	runner._handle_sse_event({"type": "message.part.updated", "properties": {"sessionID": "other_session", "part": {"id": "prt_z", "sessionID": "other_session", "type": "text", "text": "ignore me", "time": {"end": 3}}}})
	runner._handle_sse_event({"type": "message.part.updated", "properties": {"sessionID": "ses_test", "part": {"id": "prt_f1", "sessionID": "ses_test", "type": "step-finish", "reason": "stop"}}})
	runner._handle_sse_event({"type": "session.status", "properties": {"sessionID": "ses_test", "status": {"type": "idle"}}})

	await get_tree().process_frame

	var types: Array[String] = []
	for event in _events:
		types.append(str(event.get("type", "")))
	var expected: Array[String] = ["text", "reasoning", "reasoning", "step_start", "permission_asked", "question_asked", "step_finish"]
	var ok: bool = types == expected and streamed_before_end and _events[2]["part"]["text"] == "ing" and _finished == 0 and not runner.running
	print("[FLOWTEST] events=", types)
	print("[FLOWTEST] finished=", _finished)
	print("[FLOWTEST] RESULT=", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
