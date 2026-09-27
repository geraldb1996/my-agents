extends Node


func _ready() -> void:
	var scene: PackedScene = load("res://scenes/main/main.tscn")
	var main := scene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var dialog := main.get_node_or_null("AgentRequestDialog") as AgentRequestDialog
	var ok := dialog != null and not dialog.visible
	var chat := main.get_node("Panels/ChatPanel") as ChatPanel
	chat._visible_messages = [
		{"sender": "user", "content": "First", "timestamp": 0, "is_agent": false},
		{"sender": "user", "content": "Second", "timestamp": 0, "is_agent": false},
		{"sender": "user", "content": "Third", "timestamp": 0, "is_agent": false},
	]
	chat._show_message_dialog(1)
	var left := InputEventKey.new()
	left.keycode = KEY_LEFT
	left.pressed = true
	var right := InputEventKey.new()
	right.keycode = KEY_RIGHT
	right.pressed = true
	chat._message_dialog.window_input.emit(left)
	ok = ok and chat._dialog_message_index == 0 and chat._message_body.text == "First"
	chat._message_dialog.window_input.emit(left)
	ok = ok and chat._dialog_message_index == 0
	chat._message_dialog.window_input.emit(right)
	ok = ok and chat._dialog_message_index == 1 and chat._message_body.text == "Second"
	chat._message_dialog.window_input.emit(right)
	chat._message_dialog.window_input.emit(right)
	ok = ok and chat._dialog_message_index == 2 and chat._message_body.text == "Third"
	chat._message_dialog.hide()
	chat._message_dialog.window_input.emit(left)
	ok = ok and chat._dialog_message_index == 2
	print("[MAINTEST] dialog=", dialog != null, " visible=", dialog.visible if dialog != null else false)
	print("[MAINTEST] RESULT=", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
