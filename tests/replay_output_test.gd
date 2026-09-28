extends Node

var _a: String = ""
var _b: String = ""
var _ws: WorkspacePanel
var _replied := false


func _ready() -> void:
	var main_scene: PackedScene = load("res://scenes/main/main.tscn")
	var main := main_scene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	_ws = main.get_node("%WorkspacePanel")
	EventBus.chat_message.connect(_on_chat_message)
	var project := "/tmp/opencode/ui-probe"
	DirAccess.make_dir_recursive_absolute(project)

	var pa := AgentProfile.new()
	pa.ensure_id()
	_a = pa.id
	pa.name = "BotA"
	pa.model = "opencode/big-pickle"
	pa.project = project
	ProfileStore.save_profile(pa)
	var pb := AgentProfile.new()
	pb.ensure_id()
	_b = pb.id
	pb.name = "BotB"
	pb.model = "opencode/big-pickle"
	pb.project = project
	ProfileStore.save_profile(pb)

	print("[REPLAYTEST] sending task to BotA while BotB selected")
	AgentManager.get_session(_a).set("state", "offline")
	var accepted := AgentManager.send_task(_a, "Reply exactly CHAT: replay-ok") == AgentManager.TASK_OK
	var deadline := Time.get_ticks_msec() + 90000
	while not _replied and Time.get_ticks_msec() < deadline and str(AgentManager.get_session(_a).get("state", "")) != "error":
		await get_tree().create_timer(0.25).timeout

	AgentManager.select_agent(_b)
	await get_tree().process_frame
	var log_b: RichTextLabel = _ws.get_node("%OutputLog")
	print("[REPLAYTEST] BotB output lines=", line_count(log_b))
	var isolated := not log_b.get_parsed_text().contains("[start] opencode")
	AgentManager.select_agent(_a)
	await get_tree().process_frame
	await get_tree().process_frame
	var log_a: RichTextLabel = _ws.get_node("%OutputLog")
	print("[REPLAYTEST] OUTPUT_BEGIN")
	print(log_a.get_parsed_text())
	print("[REPLAYTEST] OUTPUT_END")
	var ok := accepted and _replied and isolated and log_a.get_parsed_text().contains("[start] opencode")
	print("[REPLAYTEST] RESULT=", "PASS" if ok else "FAIL")
	AgentManager.stop_agent(_a)
	ProfileStore.delete_profile(_a)
	ProfileStore.delete_profile(_b)
	ProfileStore.delete_session(_a)
	ProfileStore.delete_session(_b)
	get_tree().quit(0 if ok else 1)


func _on_chat_message(sender: String, content: String, _mentions: Array, _timestamp: int, _is_agent: bool) -> void:
	if sender == "BotA" and content.contains("replay-ok"):
		_replied = true


func line_count(log: RichTextLabel) -> int:
	return log.text.split("\n").size()
