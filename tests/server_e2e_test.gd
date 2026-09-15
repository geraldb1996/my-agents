extends Node

const TIMEOUT_MS := 120000

var _agent_id := ""
var _agent_name := "E2EBot"
var _messages: Array[String] = []
var _permissions := 0
var _questions := 0
var _last_state := ""


func _ready() -> void:
	var dir := "/tmp/opencode/e2e-probe"
	DirAccess.make_dir_recursive_absolute(dir)
	var profile := AgentProfile.new()
	profile.ensure_id()
	_agent_id = profile.id
	profile.name = _agent_name
	profile.project = dir
	ProfileStore.save_profile(profile)

	EventBus.chat_message.connect(_on_chat)
	EventBus.agent_state_changed.connect(_on_state)
	EventBus.agent_permission_asked.connect(_on_permission)
	EventBus.agent_question_asked.connect(_on_question)
	EventBus.agent_output.connect(_on_output)

	print("[E2E] task 1")
	await _run("Use the read tool to read /etc/hostname and then reply with its content. Start your reply with CHAT:")
	print("[E2E] task 2")
	await _run("Now reply with exactly: CHAT: listo")

	var first := _messages[0] if _messages.size() > 0 else ""
	var second := _messages[1] if _messages.size() > 1 else ""
	var ok := _messages.size() >= 2 and not second.is_empty() and second != first and second.to_lower().contains("listo")
	print("[E2E] messages=", _messages)
	print("[E2E] permissions=", _permissions, " questions=", _questions, " last_state=", _last_state)
	print("[E2E] RESULT=", "PASS" if ok else "FAIL")

	AgentManager.stop_agent(_agent_id)
	ProfileStore.delete_profile(_agent_id)
	get_tree().quit(0 if ok else 1)


func _run(prompt: String) -> void:
	var before := _messages.size()
	_last_state = ""
	AgentManager.send_task(_agent_id, prompt)
	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	while _messages.size() == before and Time.get_ticks_msec() < deadline:
		if _last_state == "error":
			break
		await get_tree().create_timer(0.3).timeout
	await get_tree().create_timer(1.0).timeout


func _on_chat(sender: String, content: String, _mentions: Array, _ts: int, _is_agent: bool) -> void:
	if sender == _agent_name:
		_messages.append(content)
		print("[E2E] chat <", sender, "> ", content)


func _on_state(agent_id: String, state: String) -> void:
	if agent_id == _agent_id:
		_last_state = state


func _on_permission(agent_id: String, request: Dictionary) -> void:
	_permissions += 1
	print("[E2E] permission=", request.get("permission"), " patterns=", request.get("patterns"))
	AgentManager.reply_permission(agent_id, str(request.get("id", "")), "once")


func _on_question(agent_id: String, request: Dictionary) -> void:
	_questions += 1
	var answers: Array = []
	var questions: Array = request.get("questions", [])
	for question in questions:
		if not (question is Dictionary):
			answers.append([])
			continue
		var options: Array = question.get("options", [])
		if options.is_empty() or not (options[0] is Dictionary):
			answers.append([])
		else:
			answers.append([str((options[0] as Dictionary).get("label", ""))])
	print("[E2E] question answers=", answers)
	AgentManager.reply_question(agent_id, str(request.get("id", "")), answers)


func _on_output(agent_id: String, line: String) -> void:
	if agent_id != _agent_id:
		return
	if line.begins_with("[error]") or line.begins_with("[start]") or line.begins_with("[end]") or line.begins_with("[permission]") or line.begins_with("[question]"):
		print("[E2E] output ", line)
