extends Node

var _agent_id: String = ""
var _ws: WorkspacePanel


func _ready() -> void:
	var main_scene: PackedScene = load("res://scenes/main/main.tscn")
	var main := main_scene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	_ws = main.get_node("%WorkspacePanel")

	var profile := AgentProfile.new()
	profile.ensure_id()
	_agent_id = profile.id
	profile.name = "UiBot"
	profile.model = ""
	profile.project = "/tmp/opencode/ui-probe"
	ProfileStore.save_profile(profile)
	AgentManager.select_agent(_agent_id)
	await get_tree().process_frame

	print("[UITEST] sending task")
	AgentManager.send_task(_agent_id, "Say hello in one short sentence.")
	await get_tree().create_timer(30.0).timeout
	var log: RichTextLabel = _ws.get_node("%OutputLog")
	print("[UITEST] OUTPUT_BEGIN")
	print(log.get_parsed_text())
	print("[UITEST] OUTPUT_END")
	print("[UITEST] current_id=", _ws._current_id, " agent=", _agent_id)
	ProfileStore.delete_profile(_agent_id)
	get_tree().quit()
