extends Node

var _dialog: AgentRequestDialog
var _agent_id := ""


func _ready() -> void:
	var profile := AgentProfile.new()
	profile.ensure_id()
	_agent_id = profile.id
	profile.name = "DialogBot"
	ProfileStore.save_profile(profile)

	var scene: PackedScene = load("res://scenes/ui/agent_request_dialog.tscn")
	_dialog = scene.instantiate()
	add_child(_dialog)
	await get_tree().process_frame

	var permission := {
		"id": "per_1",
		"sessionID": "ses_x",
		"permission": "bash",
		"patterns": ["rm -rf /tmp/x"],
		"always": ["rm -rf *"],
		"metadata": {"command": "rm -rf /tmp/x"},
	}
	EventBus.agent_permission_asked.emit(_agent_id, permission)
	await get_tree().process_frame
	var permission_buttons := _button_texts(_dialog)
	var permission_ok: bool = _dialog.visible and permission_buttons.has("Allow once") and permission_buttons.has("Always allow") and permission_buttons.has("Reject")
	print("[DIALOGTEST] permission visible=", _dialog.visible, " buttons=", permission_buttons)

	_press(_dialog, "Reject")
	await get_tree().process_frame

	var question := {
		"id": "que_1",
		"sessionID": "ses_x",
		"questions": [{
			"question": "Which database?",
			"header": "Database",
			"options": [
				{"label": "Postgres", "description": "server"},
				{"label": "SQLite", "description": "file"},
			],
			"multiple": false,
			"custom": true,
		}],
	}
	EventBus.agent_question_asked.emit(_agent_id, question)
	await get_tree().process_frame
	var question_buttons := _button_texts(_dialog)
	var custom := _find_line_edit(_dialog)
	var question_ok: bool = _dialog.visible and question_buttons.has("Send answers") and question_buttons.has("Reject") and custom != null and custom.placeholder_text.contains("own answer")
	print("[DIALOGTEST] question visible=", _dialog.visible, " buttons=", question_buttons, " custom=", custom != null)

	if custom != null:
		custom.text = "MariaDB"
	_click_option("SQLite")
	_press(_dialog, "Send answers")
	await get_tree().process_frame
	var closed_ok := not _dialog.visible and _dialog.pending_count() == 0
	print("[DIALOGTEST] closed=", closed_ok)

	ProfileStore.delete_profile(_agent_id)
	var ok := permission_ok and question_ok and closed_ok
	print("[DIALOGTEST] RESULT=", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)


func _button_texts(node: Node) -> Array[String]:
	var out: Array[String] = []
	_collect_buttons(node, out)
	return out


func _collect_buttons(node: Node, out: Array[String]) -> void:
	for child in node.get_children():
		if child is BaseButton:
			out.append((child as BaseButton).text)
		_collect_buttons(child, out)


func _press(node: Node, text: String) -> void:
	var button := _find_button(node, text)
	if button != null:
		button.pressed.emit()


func _find_button(node: Node, text: String) -> BaseButton:
	for child in node.get_children():
		if child is BaseButton and (child as BaseButton).text == text:
			return child
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _click_option(label: String) -> void:
	for text in _button_texts(_dialog):
		if text.begins_with(label):
			var button := _find_button(_dialog, text)
			if button != null:
				button.button_pressed = true
			return


func _find_line_edit(node: Node) -> LineEdit:
	for child in node.get_children():
		if child is LineEdit:
			return child
		var found := _find_line_edit(child)
		if found != null:
			return found
	return null
