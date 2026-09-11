extends Node

var _a: String = ""
var _b: String = ""
var _ws: WorkspacePanel


func _ready() -> void:
	var main_scene: PackedScene = load("res://scenes/main/main.tscn")
	var main := main_scene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	_ws = main.get_node("%WorkspacePanel")

	var pa := AgentProfile.new()
	pa.ensure_id()
	_a = pa.id
	pa.name = "BotA"
	pa.model = ""
	pa.project = "/tmp/opencode/ui-probe"
	ProfileStore.save_profile(pa)
	var pb := AgentProfile.new()
	pb.ensure_id()
	_b = pb.id
	pb.name = "BotB"
	pb.model = ""
	pb.project = "/tmp/opencode/ui-probe"
	ProfileStore.save_profile(pb)

	print("[REPLAYTEST] sending task to BotA while BotB selected")
	AgentManager.get_session(_a).set("state", "offline")
	AgentManager.send_task(_a, "Say hi in one short sentence.")
	await get_tree().create_timer(30.0).timeout

	AgentManager.select_agent(_b)
	await get_tree().process_frame
	var log_b: RichTextLabel = _ws.get_node("%OutputLog")
	print("[REPLAYTEST] BotB output lines=", line_count(log_b))
	AgentManager.select_agent(_a)
	await get_tree().process_frame
	await get_tree().process_frame
	var log_a: RichTextLabel = _ws.get_node("%OutputLog")
	print("[REPLAYTEST] OUTPUT_BEGIN")
	print(log_a.get_parsed_text())
	print("[REPLAYTEST] OUTPUT_END")
	ProfileStore.delete_profile(_a)
	ProfileStore.delete_profile(_b)
	get_tree().quit()


func line_count(log: RichTextLabel) -> int:
	return log.text.split("\n").size()
