extends Node


func _ready() -> void:
	var runner := OpenCodeRunner.new()
	add_child(runner)
	runner.agent_id = "sess_agent"
	runner.running = true
	var events: Array[Dictionary] = []
	runner.event_received.connect(func(_id: String, event: Dictionary) -> void: events.append(event))
	runner._on_session_created(200, {"id": "ses_persist"})
	var runner_ok := false
	for event in events:
		if str(event.get("type", "")) == "session_created" and str(event.get("sessionID", "")) == "ses_persist":
			runner_ok = true

	var test_id := "sess_test_agent"
	ProfileStore.delete_session(test_id)
	AgentManager.get_session(test_id)
	AgentManager._handle_event(test_id, {"type": "session_created", "sessionID": "ses_persist"})
	var stored: Dictionary = ProfileStore.load_session(test_id)
	var agent_ok: bool = str(stored.get("opencode_session", "")) == "ses_persist"

	ProfileStore.delete_session(test_id)
	AgentManager.sessions.erase(test_id)
	print("[SESSPERSIST] runner=", runner_ok, " agent=", agent_ok)
	var ok := runner_ok and agent_ok
	print("[SESSPERSIST] RESULT=", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
