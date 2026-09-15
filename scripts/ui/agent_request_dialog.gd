class_name AgentRequestDialog
extends Control

var _queue: Array[Dictionary] = []
var _current: Dictionary = {}
var _options: Array = []
var _custom_edits: Dictionary = {}

var _panel: PanelContainer
var _avatar: CharacterAvatar
var _name_label: Label
var _kind_label: Label
var _title_label: Label
var _body: VBoxContainer
var _buttons: HBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	EventBus.agent_permission_asked.connect(_on_permission_asked)
	EventBus.agent_question_asked.connect(_on_question_asked)
	EventBus.agent_request_resolved.connect(_on_request_resolved)
	ThemeManager.theme_changed.connect(_on_theme_changed)
	visible = false


func pending_count() -> int:
	return _queue.size() + (1 if not _current.is_empty() else 0)


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(_panel)
	_apply_panel_style()
	var panel := _panel

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	_avatar = CharacterAvatar.new()
	_avatar.custom_minimum_size = Vector2(72, 72)
	header.add_child(_avatar)
	var titles := VBoxContainer.new()
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 18)
	titles.add_child(_name_label)
	_kind_label = Label.new()
	_kind_label.add_theme_font_size_override("font_size", 13)
	_kind_label.modulate = ThemeManager.color("warning")
	titles.add_child(_kind_label)
	header.add_child(titles)
	box.add_child(header)

	_title_label = Label.new()
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.custom_minimum_size = Vector2(520, 0)
	box.add_child(_title_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 40)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	scroll.add_child(_body)

	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	_buttons.add_theme_constant_override("separation", 8)
	box.add_child(_buttons)


func _apply_panel_style() -> void:
	if _panel == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeManager.color("dialog")
	style.set_corner_radius_all(10)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	_panel.add_theme_stylebox_override("panel", style)


func _on_theme_changed() -> void:
	_apply_panel_style()
	if visible and not _current.is_empty():
		_populate()


func _on_permission_asked(agent_id: String, request: Dictionary) -> void:
	_enqueue("permission", agent_id, request)


func _on_question_asked(agent_id: String, request: Dictionary) -> void:
	_enqueue("question", agent_id, request)


func _on_request_resolved(agent_id: String, request_id: String) -> void:
	var filtered: Array[Dictionary] = []
	for entry in _queue:
		if _request_id(entry) != request_id:
			filtered.append(entry)
	_queue = filtered
	if _request_id(_current) == request_id:
		_current = {}
		_show_next()


func _enqueue(kind: String, agent_id: String, request: Dictionary) -> void:
	_queue.append({"kind": kind, "agent_id": agent_id, "request": request})
	if _current.is_empty():
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		_current = {}
		visible = false
		return
	_current = _queue.pop_front()
	visible = true
	_populate()


func _populate() -> void:
	for child in _body.get_children():
		child.queue_free()
	for child in _buttons.get_children():
		child.queue_free()
	_options.clear()
	_custom_edits.clear()

	var request: Dictionary = _current.get("request", {})
	var agent_id := str(_current.get("agent_id", ""))
	var profile := ProfileStore.get_profile(agent_id)
	_avatar.set_profile(profile)
	_name_label.text = profile.name if profile != null else agent_id
	_name_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED

	if str(_current.get("kind", "permission")) == "permission":
		_avatar.set_state("approval")
		_kind_label.text = "requests permission"
		_populate_permission(request)
	else:
		_avatar.set_state("question")
		_kind_label.text = "asks a question"
		_populate_question(request)


func _populate_permission(request: Dictionary) -> void:
	_title_label.text = tr("Permission required: %s") % str(request.get("permission", "action"))
	var patterns: Array = request.get("patterns", [])
	if not patterns.is_empty():
		_add_label("Requested patterns", ThemeManager.color("muted"))
		for pattern in patterns:
			_add_detail(str(pattern))
	var metadata: Variant = request.get("metadata", {})
	if metadata is Dictionary:
		var command := str((metadata as Dictionary).get("command", ""))
		if not command.is_empty():
			_add_label("Command", ThemeManager.color("muted"))
			_add_detail(command)
		var path := str((metadata as Dictionary).get("filePath", (metadata as Dictionary).get("path", "")))
		if not path.is_empty():
			_add_label("Path", ThemeManager.color("muted"))
			_add_detail(path)
	_add_action("Allow once", func() -> void: _reply_permission("once"))
	var always: Array = request.get("always", [])
	_add_action("Always allow", func() -> void: _reply_permission("always"), always.is_empty())
	_add_action("Reject", func() -> void: _reply_permission("reject"))


func _populate_question(request: Dictionary) -> void:
	_title_label.text = "The agent needs your answer to continue."
	var questions: Array = request.get("questions", [])
	for i in questions.size():
		if not (questions[i] is Dictionary):
			continue
		var question: Dictionary = questions[i]
		var header := Label.new()
		header.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		header.text = str(question.get("header", ""))
		header.modulate = ThemeManager.color("warning")
		_body.add_child(header)
		var text := Label.new()
		text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		text.text = str(question.get("question", ""))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(text)
		var multiple := bool(question.get("multiple", false))
		var group := ButtonGroup.new()
		var options: Array = question.get("options", [])
		for option in options:
			if not (option is Dictionary):
				continue
			var label := str((option as Dictionary).get("label", ""))
			var description := str((option as Dictionary).get("description", ""))
			var control: BaseButton
			if multiple:
				control = CheckBox.new()
			else:
				var b := Button.new()
				b.toggle_mode = true
				b.button_group = group
				control = b
			control.text = label if description.is_empty() else "%s — %s" % [label, description]
			control.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			control.alignment = HORIZONTAL_ALIGNMENT_LEFT
			_body.add_child(control)
			_options.append({"index": i, "label": label, "control": control})
		if bool(question.get("custom", false)):
			var edit := LineEdit.new()
			edit.placeholder_text = "Your own answer..."
			_body.add_child(edit)
			_custom_edits[i] = edit
	_add_action("Send answers", _submit_answers)
	_add_action("Reject", _reject_question)


func _add_label(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.modulate = color
	label.add_theme_font_size_override("font_size", 12)
	_body.add_child(label)


func _add_detail(text: String) -> void:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = text
	label.modulate = ThemeManager.color("accent")
	label.add_theme_font_size_override("font_size", 12)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(label)


func _add_action(text: String, callback: Callable, disabled: bool = false) -> void:
	var button := Button.new()
	button.text = text
	button.disabled = disabled
	button.pressed.connect(callback)
	_buttons.add_child(button)


func _reply_permission(reply: String) -> void:
	var request: Dictionary = _current.get("request", {})
	AgentManager.reply_permission(str(_current.get("agent_id", "")), str(request.get("id", "")), reply)


func _submit_answers() -> void:
	var request: Dictionary = _current.get("request", {})
	var questions: Array = request.get("questions", [])
	var answers: Array = []
	for i in questions.size():
		var selected: Array = []
		for entry in _options:
			if int(entry["index"]) != i:
				continue
			var control: BaseButton = entry["control"]
			if control.button_pressed:
				selected.append(str(entry["label"]))
		var edit: Variant = _custom_edits.get(i, null)
		if edit is LineEdit:
			var custom := (edit as LineEdit).text.strip_edges()
			if not custom.is_empty():
				selected.append(custom)
		answers.append(selected)
	AgentManager.reply_question(str(_current.get("agent_id", "")), str(request.get("id", "")), answers)


func _reject_question() -> void:
	var request: Dictionary = _current.get("request", {})
	AgentManager.reject_question(str(_current.get("agent_id", "")), str(request.get("id", "")))


func _request_id(entry: Dictionary) -> String:
	var request: Variant = entry.get("request", {})
	if request is Dictionary:
		return str((request as Dictionary).get("id", ""))
	return ""
