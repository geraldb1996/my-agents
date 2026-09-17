class_name AgentsPanel
extends PanelContainer

signal new_agent_requested
signal edit_agent_requested(agent_id: String)
signal duplicate_agent_requested(agent_id: String)
signal delete_agent_requested(agent_id: String)

const STATE_LABELS := {
	"idle": "Idle",
	"thinking": "Thinking",
	"working": "Working",
	"reading": "Reading",
	"coding": "Coding",
	"terminal": "Terminal",
	"searching": "Searching",
	"waiting": "Waiting",
	"question": "Question",
	"approval": "Approval",
	"error": "Error",
	"success": "Success",
	"offline": "Offline",
}

@onready var agent_list: VBoxContainer = %AgentList
@onready var empty_label: Label = %EmptyLabel

var _cards: Dictionary = {}
var _selected_id: String = ""


func _ready() -> void:
	EventBus.profile_saved.connect(_on_profile_saved)
	EventBus.profile_deleted.connect(_on_profile_deleted)
	EventBus.agent_state_changed.connect(_on_state_changed)
	EventBus.agent_output.connect(_on_agent_output)
	EventBus.agent_selected.connect(_on_agent_selected)
	EventBus.agent_context_usage.connect(_on_context_usage)
	EventBus.session_renamed.connect(_on_session_renamed)
	%NewButton.pressed.connect(_on_new_pressed)
	%ContextMenu.id_pressed.connect(_on_context_menu_pressed)
	%ModelMenu.id_pressed.connect(_on_model_menu_pressed)
	%VariantMenu.id_pressed.connect(_on_variant_menu_pressed)
	%SessionMenu.id_pressed.connect(_on_session_menu_pressed)
	%ContextMenu.set_item_submenu(1, "SessionMenu")
	%ContextMenu.set_item_submenu(3, "ModelMenu")
	%ContextMenu.set_item_submenu(4, "VariantMenu")
	ThemeManager.theme_changed.connect(_on_theme_changed)
	refresh()


func _on_theme_changed() -> void:
	refresh()
	if not _selected_id.is_empty():
		_apply_selection_highlight(_selected_id)


func refresh() -> void:
	for card in _cards.values():
		card.queue_free()
	_cards.clear()
	empty_label.visible = ProfileStore.profiles.is_empty()
	for profile in ProfileStore.profiles.values():
		var card := _build_card(profile)
		agent_list.add_child(card)
		_cards[profile.id] = card


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		for agent_id in _cards:
			_update_card_session(agent_id)


func get_selected_id() -> String:
	return _selected_id


func _build_card(profile: AgentProfile) -> Control:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_card_input.bind(profile.id))
	card.custom_minimum_size = Vector2(0, 72)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.add_child(row)

	var avatar := CharacterAvatar.new()
	avatar.custom_minimum_size = Vector2(48, 48)
	avatar.set_profile(profile)
	row.add_child(avatar)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := Label.new()
	name_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	name_label.text = _card_name_text(profile)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.tooltip_text = profile.project
	info.add_child(name_label)
	var session_label := Label.new()
	session_label.name = "SessionLabel"
	session_label.modulate = ThemeManager.color("muted")
	session_label.add_theme_font_size_override("font_size", 9)
	session_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	session_label.text = _session_text(profile)
	session_label.mouse_filter = Control.MOUSE_FILTER_STOP
	session_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	session_label.tooltip_text = tr("Click to rename session")
	session_label.gui_input.connect(_on_session_label_input.bind(profile.id))
	info.add_child(session_label)
	var meta_label := Label.new()
	meta_label.modulate = ThemeManager.color("muted")
	meta_label.add_theme_font_size_override("font_size", 8)
	meta_label.text = profile.model
	meta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(meta_label)
	var variant_label := Label.new()
	variant_label.name = "VariantLabel"
	variant_label.modulate = ThemeManager.color("warning")
	variant_label.add_theme_font_size_override("font_size", 8)
	variant_label.text = profile.model_variant
	variant_label.visible = not profile.model_variant.is_empty()
	variant_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(variant_label)
	var state_label := Label.new()
	state_label.name = "StateLabel"
	state_label.modulate = ThemeManager.color("muted")
	state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(state_label)
	var context_row := HBoxContainer.new()
	context_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	context_row.add_theme_constant_override("separation", 4)
	var context_bar := ProgressBar.new()
	context_bar.name = "ContextBar"
	context_bar.custom_minimum_size = Vector2(0, 10)
	context_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	context_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	context_bar.show_percentage = false
	context_bar.max_value = 100.0
	context_bar.value = 0.0
	context_bar.add_theme_stylebox_override("background", _context_bar_bg())
	context_bar.add_theme_stylebox_override("fill", _context_bar_fill())
	context_row.add_child(context_bar)
	var context_pct := Label.new()
	context_pct.name = "ContextPct"
	context_pct.text = "0%"
	context_pct.add_theme_font_size_override("font_size", 8)
	context_pct.modulate = ThemeManager.color("muted")
	context_pct.mouse_filter = Control.MOUSE_FILTER_IGNORE
	context_row.add_child(context_pct)
	info.add_child(context_row)
	row.add_child(info)

	card.set_meta("state_label", state_label)
	card.set_meta("context_bar", context_bar)
	card.set_meta("context_pct", context_pct)
	card.set_meta("avatar", avatar)
	card.set_meta("variant_label", variant_label)
	card.set_meta("session_label", session_label)
	_update_card_state(profile.id, _get_state(profile.id))
	return card


func _card_name_text(profile: AgentProfile) -> String:
	var folder := _folder_name(profile.project)
	if folder.is_empty():
		return profile.name
	return "%s - %s" % [profile.name, folder]


func _folder_name(path: String) -> String:
	var p := path.strip_edges()
	if p.is_empty():
		return ""
	while p.ends_with("/") or p.ends_with("\\"):
		p = p.substr(0, p.length() - 1)
	if p.is_empty():
		return ""
	return p.get_file()


func _session_text(profile: AgentProfile) -> String:
	var session := AgentManager.get_session(profile.id)
	var sid := str(session.get("opencode_session", ""))
	if sid.is_empty():
		return "New session"
	var title := str(session.get("title_override", ""))
	if title.is_empty():
		title = AgentManager.get_session_title(sid, profile.project)
	if title.is_empty():
		return tr("Session %s") % sid.right(6)
	return title


func _on_session_label_input(event: InputEvent, agent_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_open_rename_dialog(agent_id)


var _rename_dialog: Window
var _rename_edit: LineEdit
var _rename_agent: String = ""


func _open_rename_dialog(agent_id: String) -> void:
	if str(AgentManager.get_session(agent_id).get("opencode_session", "")).is_empty():
		return
	if _rename_dialog == null:
		_rename_dialog = Window.new()
		_rename_dialog.title = tr("Rename session")
		_rename_dialog.exclusive = true
		_rename_dialog.close_requested.connect(_rename_dialog.hide)
		var root := VBoxContainer.new()
		root.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_theme_constant_override("separation", 10)
		_rename_dialog.add_child(root)
		var prompt := Label.new()
		prompt.text = tr("Session name:")
		root.add_child(prompt)
		_rename_edit = LineEdit.new()
		_rename_edit.placeholder_text = tr("Leave empty to restore automatic title")
		_rename_edit.text_submitted.connect(func(_t: String): _confirm_rename())
		root.add_child(_rename_edit)
		var buttons := HBoxContainer.new()
		var ok := Button.new()
		ok.text = tr("OK")
		ok.pressed.connect(_confirm_rename)
		buttons.add_child(ok)
		var cancel := Button.new()
		cancel.text = tr("Cancel")
		cancel.pressed.connect(_rename_dialog.hide)
		buttons.add_child(cancel)
		root.add_child(buttons)
		add_child(_rename_dialog)
	_rename_agent = agent_id
	_rename_edit.text = str(AgentManager.get_session(agent_id).get("title_override", ""))
	_rename_dialog.popup_centered(Vector2i(360, 150))
	_rename_edit.grab_focus()


func _confirm_rename() -> void:
	if _rename_dialog == null or not _rename_dialog.visible:
		return
	var title := _rename_edit.text.strip_edges()
	AgentManager.rename_session(_rename_agent, title)
	_rename_dialog.hide()
	_update_card_session(_rename_agent)


func _on_session_renamed(agent_id: String) -> void:
	_update_card_session(agent_id)


func _update_card_session(agent_id: String) -> void:
	var card: Control = _cards.get(agent_id)
	if card == null:
		return
	var label: Label = card.get_meta("session_label")
	if label == null:
		return
	var profile := ProfileStore.get_profile(agent_id)
	if profile == null:
		return
	label.text = _session_text(profile)


func _on_card_input(event: InputEvent, agent_id: String) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_select(agent_id)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_open_context_menu(agent_id, event.global_position)


var _context_target: String = ""
var _menu_models: Array[String] = []
var _menu_variants: Array[String] = []
var _menu_sessions: Array[String] = []


func _open_context_menu(agent_id: String, at_position: Vector2) -> void:
	var profile := ProfileStore.get_profile(agent_id)
	if profile == null:
		return
	_context_target = agent_id
	_populate_model_menu(profile)
	_populate_variant_menu(profile)
	_populate_session_menu(agent_id)
	%ContextMenu.popup(Rect2i(at_position, Vector2(200, 0)))


func _populate_model_menu(profile: AgentProfile) -> void:
	_menu_models.clear()
	%ModelMenu.clear()
	_menu_models.append("")
	%ModelMenu.add_item("Default (auto)", 0)
	if profile.model.is_empty():
		%ModelMenu.set_item_checked(0, true)
	for i in ModelCatalog.models.size():
		var model := ModelCatalog.models[i]
		var id := i + 1
		_menu_models.append(model)
		%ModelMenu.add_item(model, id)
		if model == profile.model:
			%ModelMenu.set_item_checked(id, true)


func _populate_variant_menu(profile: AgentProfile) -> void:
	_menu_variants.clear()
	%VariantMenu.clear()
	var variants := ModelCatalog.get_variants(profile.model)
	%ContextMenu.set_item_disabled(4, variants.is_empty())
	if variants.is_empty():
		%VariantMenu.add_item("No variants", 0)
		return
	_menu_variants.append("")
	%VariantMenu.add_item("Default (none)", 0)
	if profile.model_variant.is_empty():
		%VariantMenu.set_item_checked(0, true)
	for i in variants.size():
		var variant := str(variants[i])
		var id := i + 1
		_menu_variants.append(variant)
		%VariantMenu.add_item(variant, id)
		if variant == profile.model_variant:
			%VariantMenu.set_item_checked(id, true)


func _populate_session_menu(agent_id: String) -> void:
	_menu_sessions.clear()
	%SessionMenu.clear()
	var history := ProfileStore.load_session_history(agent_id)
	var profile := ProfileStore.get_profile(agent_id)
	var project := profile.project if profile != null else ""
	if history.is_empty():
		%SessionMenu.add_item("No previous sessions", 0)
		return
	var active := str(AgentManager.get_session(agent_id).get("opencode_session", ""))
	for entry in history:
		if entry is not Dictionary:
			continue
		var sid := str(entry.get("opencode_session", ""))
		if sid.is_empty():
			continue
		_menu_sessions.append(sid)
		var id := _menu_sessions.size() - 1
		var archived := int(entry.get("archived_at", 0))
		var title := str(entry.get("title", ""))
		if title.is_empty():
			title = AgentManager.get_session_title(sid, project)
		if title.is_empty():
			title = tr("Session %s") % sid.right(6)
		var label := "%s · %s" % [title, Time.get_datetime_string_from_unix_time(archived)]
		%SessionMenu.add_item(label, id)
		%SessionMenu.set_item_tooltip(id, sid)
		if sid == active:
			%SessionMenu.set_item_checked(id, true)


func _on_context_menu_pressed(index: int) -> void:
	if _context_target.is_empty():
		return
	match index:
		0:
			AgentManager.new_session(_context_target)
		1:
			AgentManager.delete_session(_context_target)
		2:
			edit_agent_requested.emit(_context_target)
		3:
			delete_agent_requested.emit(_context_target)
		4:
			duplicate_agent_requested.emit(_context_target)

func _on_session_menu_pressed(index: int) -> void:
	if _context_target.is_empty() or index >= _menu_sessions.size():
		return
	AgentManager.switch_session(_context_target, _menu_sessions[index])


func _on_model_menu_pressed(index: int) -> void:
	if _context_target.is_empty() or index >= _menu_models.size():
		return
	AgentManager.set_model(_context_target, _menu_models[index])


func _on_variant_menu_pressed(index: int) -> void:
	if _context_target.is_empty() or index >= _menu_variants.size():
		return
	AgentManager.set_variant(_context_target, _menu_variants[index])


func _select(agent_id: String) -> void:
	if _selected_id == agent_id and not _cards.is_empty():
		return
	_selected_id = agent_id
	AgentManager.select_agent(agent_id)
	_apply_selection_highlight(agent_id)


func _apply_selection_highlight(agent_id: String) -> void:
	for id in _cards:
		var card: Control = _cards[id]
		if id == agent_id:
			var sb := StyleBoxFlat.new()
			sb.bg_color = ThemeManager.color("selected")
			sb.set_corner_radius_all(6)
			card.add_theme_stylebox_override("panel", sb)
		else:
			card.remove_theme_stylebox_override("panel")


func _on_new_pressed() -> void:
	new_agent_requested.emit()


func _on_profile_saved(_profile: AgentProfile) -> void:
	refresh()
	if not _selected_id.is_empty() and _cards.has(_selected_id):
		_apply_selection_highlight(_selected_id)


func _on_profile_deleted(_agent_id: String) -> void:
	refresh()


func _on_agent_selected(profile: AgentProfile) -> void:
	_select(profile.id)


func _on_state_changed(agent_id: String, _state: String) -> void:
	_update_card_state(agent_id, _get_state(agent_id))
	_update_card_session(agent_id)


func _on_agent_output(agent_id: String, _line: String) -> void:
	_update_card_session(agent_id)


func _update_card_state(agent_id: String, state: String) -> void:
	var card: Control = _cards.get(agent_id)
	if card == null:
		return
	var state_label: Label = card.get_meta("state_label")
	var avatar: CharacterAvatar = card.get_meta("avatar")
	state_label.text = STATE_LABELS.get(state, state.capitalize())
	avatar.set_state(state)


func _get_state(agent_id: String) -> String:
	return str(AgentManager.get_session(agent_id).get("state", "offline"))


func _on_context_usage(agent_id: String, tokens: int, percent: float, cost: float) -> void:
	var card: Control = _cards.get(agent_id)
	if card == null:
		return
	var bar: ProgressBar = card.get_meta("context_bar")
	var pct_label: Label = card.get_meta("context_pct")
	bar.value = percent
	pct_label.text = "%d%% · %s · $%.2f" % [int(percent), _fmt_tokens(tokens), cost]
	_update_bar_color(bar, percent)


func _fmt_tokens(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


func _context_bar_bg() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = ThemeManager.color("sunken")
	sb.set_corner_radius_all(3)
	return sb


func _context_bar_fill() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = ThemeManager.color("accent")
	sb.set_corner_radius_all(3)
	return sb


func _update_bar_color(bar: ProgressBar, percent: float) -> void:
	var col := ThemeManager.color("accent")
	if percent >= 75.0:
		col = ThemeManager.color("danger")
	elif percent >= 50.0:
		col = ThemeManager.color("warning")
	var sb := _context_bar_fill()
	sb.bg_color = col
	bar.add_theme_stylebox_override("fill", sb)
