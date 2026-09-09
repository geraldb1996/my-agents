class_name ChatPanel
extends PanelContainer

const SENDER_COLORS := [
	Color(0.4, 0.8, 1),
	Color(0.5, 1, 0.6),
	Color(1, 0.8, 0.4),
	Color(1, 0.55, 0.85),
	Color(0.85, 0.6, 1),
	Color(1, 0.65, 0.4),
	Color(0.5, 1, 0.9),
	Color(0.9, 0.9, 0.4),
]

const TYPING_STATES := ["thinking", "working", "reading", "coding", "terminal", "searching", "question", "approval"]

@onready var messages_box: VBoxContainer = %MessagesBox
@onready var scroll: ScrollContainer = %Scroll
@onready var typing_label: Label = %TypingLabel
@onready var input_edit: LineEdit = %InputEdit

var _typing: Dictionary = {}


func _ready() -> void:
	%SendButton.pressed.connect(_on_send_pressed)
	%ClearButton.pressed.connect(_on_clear_pressed)
	%ClearDialog.confirmed.connect(_on_clear_confirmed)
	input_edit.text_submitted.connect(func(_t): _on_send_pressed())
	EventBus.chat_message.connect(_on_chat_message)
	EventBus.agent_state_changed.connect(_on_state_changed)
	EventBus.profile_deleted.connect(_on_profile_deleted)
	_populate_history()


func _on_clear_pressed() -> void:
	%ClearDialog.popup_centered()


func _on_clear_confirmed() -> void:
	ProfileStore.clear_chat_history()
	for child in messages_box.get_children():
		child.queue_free()


func _populate_history() -> void:
	for msg in ProfileStore.chat_history:
		if msg is Dictionary:
			_add_bubble(str(msg.get("sender", "?")), str(msg.get("content", "")), int(msg.get("timestamp", 0)), bool(msg.get("is_agent", false)))
	_autoscroll()


func _on_chat_message(sender: String, content: String, _mentions: Array, timestamp: int, is_agent: bool) -> void:
	_add_bubble(sender, content, timestamp, is_agent)
	_autoscroll()


func _add_bubble(sender: String, content: String, timestamp: int, is_agent: bool) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var bubble := PanelContainer.new()
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var header := HBoxContainer.new()
	var sender_label := Label.new()
	var color: Color = Color(1, 1, 1)
	if is_agent:
		color = SENDER_COLORS[hash(sender) % SENDER_COLORS.size()]
	elif sender == "system":
		color = Color(0.75, 0.75, 0.5)
	sender_label.text = sender if is_agent else ("You" if sender != "system" else "System")
	sender_label.modulate = color
	sender_label.add_theme_font_size_override("font_size", 13)
	sender_label.add_theme_color_override("font_color", color)
	header.add_child(sender_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var time_label := Label.new()
	time_label.text = _format_time(timestamp)
	time_label.modulate = Color(0.55, 0.55, 0.6)
	time_label.add_theme_font_size_override("font_size", 11)
	header.add_child(time_label)
	inner.add_child(header)

	var body := Label.new()
	body.text = content
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(body)

	bubble.add_child(inner)
	row.add_child(bubble)
	messages_box.add_child(row)


func _on_send_pressed() -> void:
	var text := input_edit.text.strip_edges()
	if text.is_empty():
		return
	var mentions := _extract_mentions(text)
	var ts := Time.get_unix_time_from_system() * 1000
	ProfileStore.append_chat_message("user", text, mentions, ts, false)
	EventBus.chat_message.emit("user", text, mentions, ts, false)
	input_edit.clear()
	_route_message(text, mentions)


func _extract_mentions(text: String) -> Array:
	var mentions: Array = []
	var regex := RegEx.new()
	regex.compile("@([A-Za-z0-9_]+)")
	for m in regex.search_all(text):
		var name := m.get_string(1)
		if name == "all" and not mentions.has("all"):
			mentions.append("all")
		else:
			var profile := _find_profile_by_name(name)
			if profile != null and not mentions.has(profile.id):
				mentions.append(profile.id)
	return mentions


func _find_profile_by_name(name: String) -> AgentProfile:
	var lower := name.to_lower()
	for profile in ProfileStore.profiles.values():
		if profile.name.to_lower() == lower or profile.name.to_lower().replace(" ", "_") == lower:
			return profile
	return null


func _route_message(text: String, mentions: Array) -> void:
	var targets: Array[String] = []
	if not mentions.is_empty():
		if mentions.has("all"):
			for profile_id in ProfileStore.profiles:
				targets.append(profile_id)
		else:
			for id in mentions:
				targets.append(id)
	elif not AgentManager.selected_agent_id.is_empty():
		targets.append(AgentManager.selected_agent_id)

	if targets.is_empty():
		_add_system_hint("No agent targeted. Select an agent in the left panel or use @AgentName / @all.")
		return

	for agent_id in targets:
		var result := AgentManager.send_chat_message(agent_id, text)
		if result != AgentManager.TASK_OK:
			var profile := ProfileStore.get_profile(agent_id)
			var who := profile.name if profile != null else agent_id
			var reason := ""
			match result:
				AgentManager.TASK_NO_PROJECT:
					reason = "%s has no project set. Open its editor or use Select Folder in Workspace." % who
				AgentManager.TASK_BUSY:
					reason = "%s is busy with another task. Wait for it to finish." % who
				_:
					reason = "%s not reached (OpenCode failed to launch). Check its output log." % who
			_add_system_hint(reason)


func _add_system_hint(content: String) -> void:
	var ts := Time.get_unix_time_from_system() * 1000
	ProfileStore.append_chat_message("system", content, [], ts, false)
	_add_bubble("system", content, ts, false)


func _on_state_changed(agent_id: String, state: String) -> void:
	var profile := ProfileStore.get_profile(agent_id)
	if profile == null:
		return
	if state in TYPING_STATES:
		_typing[agent_id] = profile.name
	else:
		_typing.erase(agent_id)
	_update_typing_label()


func _on_profile_deleted(agent_id: String) -> void:
	_typing.erase(agent_id)
	_update_typing_label()


func _update_typing_label() -> void:
	if _typing.is_empty():
		typing_label.text = ""
		typing_label.visible = false
		return
	var names := _typing.values()
	typing_label.text = "%s is working..." % names[0] if names.size() == 1 else "%d agents working..." % names.size()
	typing_label.visible = true


func _autoscroll() -> void:
	await get_tree().process_frame
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func _format_time(ts: int) -> String:
	if ts <= 0:
		return ""
	var dt := Time.get_datetime_dict_from_unix_time(int(ts / 1000.0))
	return "%02d:%02d" % [dt["hour"], dt["minute"]]