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
var _filter_name := ""
var _opt_ids: Array[String] = []
var _copy_menu: PopupMenu
var _copy_content := ""
var _mention_menu: PopupMenu
var _mention_tokens: Array[String] = []
var _message_dialog: AcceptDialog
var _message_body: RichTextLabel


func _ready() -> void:
	%SendButton.pressed.connect(_on_send_pressed)
	%ClearButton.pressed.connect(_on_clear_pressed)
	%ClearDialog.confirmed.connect(_on_clear_confirmed)
	%AgentFilter.item_selected.connect(_on_filter_selected)
	input_edit.text_submitted.connect(func(_t): _on_send_pressed())
	input_edit.text_changed.connect(_on_input_changed)
	EventBus.chat_message.connect(_on_chat_message)
	EventBus.agent_state_changed.connect(_on_state_changed)
	EventBus.profile_deleted.connect(_on_profile_deleted)
	EventBus.profile_saved.connect(_on_profile_saved)
	_build_filter_options()
	_populate_history()


func _build_filter_options() -> void:
	var keep_name := _filter_name
	%AgentFilter.clear()
	_opt_ids.clear()
	_opt_ids.append("")
	%AgentFilter.add_item("All agents")
	for agent_id in ProfileStore.profiles:
		var profile := ProfileStore.get_profile(agent_id)
		if profile == null:
			continue
		_opt_ids.append(agent_id)
		%AgentFilter.add_item(profile.name)
	var idx := 0
	for i in range(1, _opt_ids.size()):
		var profile := ProfileStore.get_profile(_opt_ids[i])
		if profile != null and profile.name == keep_name:
			idx = i
			break
	%AgentFilter.select(idx)
	_filter_name = "" if idx == 0 else %AgentFilter.get_item_text(idx)


func _on_filter_selected(index: int) -> void:
	_filter_name = "" if index <= 0 else %AgentFilter.get_item_text(index)
	_populate_history()


func _passes_filter(sender: String, is_agent: bool) -> bool:
	if _filter_name.is_empty():
		return true
	if is_agent:
		return sender == _filter_name
	return sender == "user"


func _on_clear_pressed() -> void:
	%ClearDialog.popup_centered()


func _on_clear_confirmed() -> void:
	ProfileStore.clear_chat_history()
	for child in messages_box.get_children():
		child.queue_free()


func _populate_history() -> void:
	for child in messages_box.get_children():
		child.queue_free()
	for msg in ProfileStore.chat_history:
		if msg is Dictionary:
			var sender := str(msg.get("sender", "?"))
			var content := str(msg.get("content", ""))
			var timestamp := int(msg.get("timestamp", 0))
			var is_agent := bool(msg.get("is_agent", false))
			if _passes_filter(sender, is_agent):
				_add_bubble(sender, content, timestamp, is_agent)
	_autoscroll()


func _on_chat_message(sender: String, content: String, _mentions: Array, timestamp: int, is_agent: bool) -> void:
	if not _passes_filter(sender, is_agent):
		return
	_add_bubble(sender, content, timestamp, is_agent)
	_autoscroll()


func _add_bubble(sender: String, content: String, timestamp: int, is_agent: bool) -> void:
	var is_user := sender == "user"
	var is_system := sender == "system"
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if is_user:
		var spacer_left := Control.new()
		spacer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer_left)

	var bubble := PanelContainer.new()
	bubble.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var sb := StyleBoxFlat.new()
	if is_user:
		sb.bg_color = Color(0.28, 0.42, 0.6, 1)
	elif is_system:
		sb.bg_color = Color(0.3, 0.28, 0.22, 1)
	else:
		sb.bg_color = Color(0.2, 0.21, 0.27, 1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	bubble.add_theme_stylebox_override("panel", sb)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_FILL

	var header := HBoxContainer.new()
	var sender_label := Label.new()
	var color: Color = Color(1, 1, 1)
	if is_agent:
		color = SENDER_COLORS[hash(sender) % SENDER_COLORS.size()]
	elif is_system:
		color = Color(0.75, 0.75, 0.5)
	sender_label.text = sender if is_agent else ("You" if is_user else "System")
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
	body.size_flags_horizontal = Control.SIZE_FILL
	body.custom_minimum_size = Vector2(280, 0)
	inner.add_child(body)

	bubble.add_child(inner)
	row.add_child(bubble)
	bubble.tooltip_text = "Double-click to enlarge message"
	bubble.gui_input.connect(_on_bubble_gui_input.bind(content, sender_label.text, timestamp))

	if not is_user:
		var spacer_right := Control.new()
		spacer_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer_right)

	messages_box.add_child(row)


func _on_bubble_gui_input(event: InputEvent, content: String, sender: String, timestamp: int) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		accept_event()
		_show_message_dialog(content, sender, timestamp)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_copy_content = content
		_show_copy_menu()


func _show_message_dialog(content: String, sender: String, timestamp: int) -> void:
	if _message_dialog == null:
		_message_dialog = AcceptDialog.new()
		_message_dialog.name = "MessageDialog"
		_message_dialog.exclusive = true
		_message_dialog.min_size = Vector2i(320, 240)
		_message_dialog.ok_button_text = "Close"
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.16, 0.17, 0.22, 1)
		style.set_corner_radius_all(10)
		style.set_content_margin_all(18.0)
		_message_dialog.add_theme_stylebox_override("panel", style)
		_message_body = RichTextLabel.new()
		_message_body.bbcode_enabled = false
		_message_body.selection_enabled = true
		_message_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_message_body.add_theme_font_size_override("normal_font_size", 20)
		_message_dialog.add_child(_message_body)
		add_child(_message_dialog)
	_message_dialog.title = "Team Chat — %s %s" % [sender, _format_time(timestamp)]
	_message_body.text = content
	_message_dialog.popup_centered_clamped(Vector2i(800, 600), 0.9)
	_message_body.scroll_to_line(0)
	_message_body.grab_focus()


func _show_copy_menu() -> void:
	if _copy_menu == null:
		_copy_menu = PopupMenu.new()
		_copy_menu.add_item("Copy message")
		_copy_menu.id_pressed.connect(_on_copy_id)
		add_child(_copy_menu)
	_copy_menu.popup(Rect2i(Vector2i(get_viewport().get_mouse_position()), Vector2i()))


func _on_copy_id(_id: int) -> void:
	DisplayServer.clipboard_set(_copy_content)


func _on_input_changed(_new_text: String) -> void:
	var text := input_edit.text
	var caret := input_edit.caret_column
	if caret > text.length():
		caret = text.length()
	var before := text.substr(0, caret)
	var at := before.rfind("@")
	if at < 0:
		_hide_mention_menu()
		return
	var query := before.substr(at + 1)
	if query.contains(" ") or query.contains("\t"):
		_hide_mention_menu()
		return
	if _show_mention_menu(query):
		input_edit.grab_focus()


func _show_mention_menu(query: String) -> bool:
	if _mention_menu == null:
		_mention_menu = PopupMenu.new()
		_mention_menu.set_flag(Window.FLAG_NO_FOCUS, true)
		_mention_menu.id_pressed.connect(_on_mention_id_pressed)
		add_child(_mention_menu)
	_mention_menu.clear()
	_mention_tokens.clear()
	var q := query.to_lower()
	_add_mention_entry("all", "All agents", q)
	for agent_id in ProfileStore.profiles:
		var profile := ProfileStore.get_profile(agent_id)
		if profile != null:
			_add_mention_entry(profile.name.replace(" ", "_"), profile.name, q)
	if _mention_tokens.is_empty():
		_hide_mention_menu()
		return false
	if not _mention_menu.visible:
		var rect := input_edit.get_global_rect()
		_mention_menu.popup(Rect2i(Vector2i(rect.position.x, rect.end.y), Vector2i(int(rect.size.x), 0)))
	return true


func _add_mention_entry(token: String, label: String, query: String) -> void:
	if not query.is_empty() and not token.to_lower().contains(query) and not label.to_lower().contains(query):
		return
	var id := _mention_tokens.size()
	_mention_tokens.append(token)
	_mention_menu.add_item(label, id)


func _on_mention_id_pressed(id: int) -> void:
	if id < 0 or id >= _mention_tokens.size():
		return
	var token := _mention_tokens[id]
	var text := input_edit.text
	var caret := input_edit.caret_column
	if caret > text.length():
		caret = text.length()
	var before := text.substr(0, caret)
	var at := before.rfind("@")
	if at < 0:
		return
	var insert := "@%s " % token
	input_edit.text = text.substr(0, at) + insert + text.substr(caret)
	input_edit.caret_column = at + insert.length()
	input_edit.grab_focus()
	_hide_mention_menu()


func _hide_mention_menu() -> void:
	if _mention_menu != null and _mention_menu.visible:
		_mention_menu.hide()


func _on_send_pressed() -> void:
	_hide_mention_menu()
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
	if _passes_filter("system", false):
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
	_build_filter_options()
	_populate_history()


func _on_profile_saved(_profile: AgentProfile) -> void:
	_build_filter_options()
	if _filter_name.is_empty():
		_populate_history()


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
