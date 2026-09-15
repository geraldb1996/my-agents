extends Node


func _ready() -> void:
	var panel: WorkspacePanel = load("res://scenes/ui/workspace_panel.tscn").instantiate()
	add_child(panel)
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.size = Vector2(650, 850)
	panel._current_id = "output_test"
	AgentManager.sessions["output_test"] = {}
	var runner := OpenCodeRunner.new()
	add_child(runner)
	runner.agent_id = "output_test"
	runner.session_id = "ses_output"
	runner.event_received.connect(AgentManager._handle_event)
	runner._handle_sse_event({"type": "message.part.updated", "properties": {"part": {"id": "reason", "sessionID": "ses_output", "type": "reasoning", "text": ""}}})
	for delta in ["Visible ", "[b]literal[/b]\n", "long output line\n".repeat(200)]:
		runner._handle_sse_event({"type": "message.part.delta", "properties": {"sessionID": "ses_output", "partID": "reason", "field": "text", "delta": delta}})
	await get_tree().process_frame
	await get_tree().process_frame
	var history := AgentManager.get_output_history("output_test")
	var ok := history.size() == 1 and str(history[0]).begins_with("[think] Visible [b]literal[/b]")
	ok = ok and panel.output_log.get_parsed_text() == str(history[0]) + "\n"
	ok = ok and panel.size.y == 850 and panel.output_log.size.y < panel.size.y
	var bar := panel.output_log.get_v_scroll_bar()
	ok = ok and bar.max_value > bar.page
	print("[OUTPUTTEST] stream/layout=", ok, " size=", panel.size, " scroll=", bar.max_value, "/", bar.page)
	panel.get_node("Root/InfoTabs/Output/OutputHeader/ExpandOutputButton").pressed.emit()
	await get_tree().process_frame
	ok = ok and panel.output_dialog.visible and panel.expanded_output_log.text == panel.output_log.text
	print("[OUTPUTTEST] popup=", ok)
	bar.value = 0
	runner._handle_sse_event({"type": "message.part.delta", "properties": {"sessionID": "ses_output", "partID": "reason", "field": "text", "delta": "live popup"}})
	await get_tree().process_frame
	await get_tree().process_frame
	ok = ok and bar.value == 0 and panel.expanded_output_log.text.ends_with("live popup\n")
	print("[OUTPUTTEST] live/scroll=", ok, " position=", bar.value)
	panel.output_dialog.close_requested.emit()
	ok = ok and not panel.output_dialog.visible
	panel.clear()
	ok = ok and panel.output_log.text.is_empty() and panel.expanded_output_log.text.is_empty()
	AgentManager.sessions.erase("output_test")
	AgentManager._output_history.erase("output_test")
	print("[OUTPUTTEST] RESULT=", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
