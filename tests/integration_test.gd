extends Node

var _agent_id: String = ""
var _timeout := 90.0


func _ready() -> void:
	var profile := AgentProfile.new()
	profile.ensure_id()
	_agent_id = profile.id
	profile.name = "TestBot"
	profile.model = ""
	profile.project = "/tmp/opencode/test-json"
	profile.skills = ["Testing"]
	ProfileStore.save_profile(profile)

	EventBus.agent_state_changed.connect(_on_state)
	EventBus.chat_message.connect(_on_chat)
	EventBus.agent_output.connect(_on_output)
	EventBus.agent_git_status.connect(_on_git)
	EventBus.agent_files_changed.connect(_on_files)

	print("[TEST] sending task")
	AgentManager.send_task(_agent_id, "What files are in this directory? Answer in one short sentence.")
	await get_tree().create_timer(25.0).timeout
	print("[TEST] sending second task (should resume session)")
	AgentManager.send_task(_agent_id, "Say hello in two words.")
	await get_tree().create_timer(20.0).timeout
	print("[TEST] done, quitting")
	ProfileStore.delete_profile(_agent_id)
	get_tree().quit()


func _on_state(agent_id: String, state: String) -> void:
	if agent_id == _agent_id:
		print("[TEST] state -> ", state)


func _on_chat(sender: String, content: String, _m: Array, _ts: int, _a: bool) -> void:
	print("[TEST] chat <%s> %s" % [sender, content])


func _on_output(agent_id: String, line: String) -> void:
	if agent_id == _agent_id:
		print("[TEST] out: ", line)


func _on_git(agent_id: String, branch: String, status: String) -> void:
	if agent_id == _agent_id:
		print("[TEST] git branch=%s status=%s" % [branch, status])


func _on_files(agent_id: String, files: Array) -> void:
	if agent_id == _agent_id:
		print("[TEST] files: ", files)