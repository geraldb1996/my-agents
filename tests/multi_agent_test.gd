extends Node

var _agent_ids: Array[String] = []


func _ready() -> void:
	var p1 := AgentProfile.new()
	p1.ensure_id()
	p1.name = "CoderBot"
	p1.project = "/tmp/opencode/test-json"
	_agent_ids.append(p1.id)
	var p2 := AgentProfile.new()
	p2.ensure_id()
	p2.name = "QABot"
	p2.project = "/tmp/opencode/test-json"
	_agent_ids.append(p2.id)
	ProfileStore.save_profile(p1)
	ProfileStore.save_profile(p2)

	EventBus.chat_message.connect(_on_chat)
	EventBus.agent_output.connect(_on_output)

	print("[TEST] two agents, sending tasks concurrently")
	AgentManager.send_task(p1.id, "Say: coder ready. One line only.")
	AgentManager.send_task(p2.id, "Say: qa ready. One line only.")
	await get_tree().create_timer(45.0).timeout
	print("[TEST] done, quitting")
	for id in _agent_ids:
		ProfileStore.delete_profile(id)
	get_tree().quit()


func _on_chat(sender: String, content: String, _m: Array, _ts: int, _a: bool) -> void:
	print("[TEST] chat <%s> %s" % [sender, content])


func _on_output(agent_id: String, line: String) -> void:
	if line.begins_with("[start]") or line.begins_with("[end]") or line.begins_with("[error]"):
		var name := ""
		for id in _agent_ids:
			var p := ProfileStore.get_profile(id)
			if p != null and p.id == agent_id:
				name = p.name
		print("[TEST] %s: %s" % [name, line])