class_name AgentsPanel
extends PanelContainer

signal new_agent_requested
signal edit_agent_requested(agent_id: String)
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
	EventBus.agent_selected.connect(_on_agent_selected)
	EventBus.agent_context_usage.connect(_on_context_usage)
	%NewButton.pressed.connect(_on_new_pressed)
	%ContextMenu.id_pressed.connect(_on_context_menu_pressed)
	%VariantMenu.id_pressed.connect(_on_variant_menu_pressed)
	refresh()


func refresh() -> void:
	for card in _cards.values():
		card.queue_free()
	_cards.clear()
	empty_label.visible = ProfileStore.profiles.is_empty()
	for profile in ProfileStore.profiles.values():
		var card := _build_card(profile)
		agent_list.add_child(card)
		_cards[profile.id] = card


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
	name_label.text = profile.name
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(name_label)
	var meta_label := Label.new()
	meta_label.modulate = Color(0.7, 0.7, 0.75)
	meta_label.add_theme_font_size_override("font_size", 8)
	meta_label.text = profile.model
	meta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(meta_label)
	var variant_label := Label.new()
	variant_label.name = "VariantLabel"
	variant_label.modulate = Color(1, 0.85, 0.3)
	variant_label.add_theme_font_size_override("font_size", 8)
	variant_label.text = profile.model_variant
	variant_label.visible = not profile.model_variant.is_empty()
	variant_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(variant_label)
	var state_label := Label.new()
	state_label.name = "StateLabel"
	state_label.modulate = Color(0.6, 0.65, 0.7)
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
	context_pct.modulate = Color(0.5, 0.55, 0.6)
	context_pct.mouse_filter = Control.MOUSE_FILTER_IGNORE
	context_row.add_child(context_pct)
	info.add_child(context_row)
	row.add_child(info)

	var actions := VBoxContainer.new()
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var start_button := Button.new()
	start_button.name = "StartButton"
	start_button.text = "Start"
	start_button.custom_minimum_size = Vector2(56, 28)
	start_button.pressed.connect(_on_start_pressed.bind(profile.id, start_button))
	actions.add_child(start_button)
	var ses_button := Button.new()
	ses_button.text = "Ses"
	ses_button.custom_minimum_size = Vector2(56, 28)
	ses_button.tooltip_text = "Reset session"
	ses_button.pressed.connect(_on_ses_pressed.bind(profile.id))
	actions.add_child(ses_button)
	var var_button := Button.new()
	var_button.text = "Var"
	var_button.custom_minimum_size = Vector2(56, 28)
	var_button.tooltip_text = "Model variant"
	var_button.pressed.connect(_on_var_pressed.bind(profile.id, var_button))
	var variants := ModelCatalog.get_variants(profile.model)
	var_button.disabled = variants.is_empty()
	actions.add_child(var_button)
	row.add_child(actions)

	card.set_meta("start_button", start_button)
	card.set_meta("state_label", state_label)
	card.set_meta("context_bar", context_bar)
	card.set_meta("context_pct", context_pct)
	card.set_meta("avatar", avatar)
	card.set_meta("variant_label", variant_label)
	_update_card_state(profile.id, _get_state(profile.id))
	return card


func _on_card_input(event: InputEvent, agent_id: String) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_select(agent_id)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_open_context_menu(agent_id, event.global_position)


var _context_target: String = ""
var _variant_target: String = ""


func _open_context_menu(agent_id: String, at_position: Vector2) -> void:
	_context_target = agent_id
	%ContextMenu.popup(Rect2i(at_position, Vector2(200, 0)))


func _on_context_menu_pressed(index: int) -> void:
	if _context_target.is_empty():
		return
	match index:
		0:
			AgentManager.reset_session(_context_target)
		1:
			edit_agent_requested.emit(_context_target)
		2:
			delete_agent_requested.emit(_context_target)


func _on_ses_pressed(agent_id: String) -> void:
	AgentManager.reset_session(agent_id)


func _on_var_pressed(agent_id: String, button: Button) -> void:
	var profile := ProfileStore.get_profile(agent_id)
	if profile == null:
		return
	var variants := ModelCatalog.get_variants(profile.model)
	if variants.is_empty():
		return
	_variant_target = agent_id
	%VariantMenu.clear()
	%VariantMenu.add_item("Default (none)", 0)
	var current := profile.model_variant
	for v in variants:
		%VariantMenu.add_item(str(v))
		if str(v) == current:
			%VariantMenu.set_item_checked(%VariantMenu.item_count - 1, true)
	%VariantMenu.add_item("Custom...", -1)
	%VariantMenu.popup(Rect2i(button.global_position + Vector2(0, button.size.y), Vector2(180, 0)))


func _on_variant_menu_pressed(index: int) -> void:
	if _variant_target.is_empty():
		return
	var variant := ""
	if index > 0:
		var custom_idx: int = %VariantMenu.item_count - 1
		if index == custom_idx:
			return
		variant = %VariantMenu.get_item_text(index)
	AgentManager.set_variant(_variant_target, variant)


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
			sb.bg_color = Color(0.22, 0.28, 0.42, 1)
			sb.set_corner_radius_all(6)
			card.add_theme_stylebox_override("panel", sb)
		else:
			card.remove_theme_stylebox_override("panel")


func _on_start_pressed(agent_id: String, button: Button) -> void:
	var state := _get_state(agent_id)
	if state in ["offline", "idle", "error"]:
		AgentManager.start_agent(agent_id)
		button.text = "Stop"
	else:
		AgentManager.stop_agent(agent_id)
		button.text = "Start"


func _on_edit_pressed(agent_id: String) -> void:
	edit_agent_requested.emit(agent_id)


func _on_delete_pressed(agent_id: String) -> void:
	delete_agent_requested.emit(agent_id)


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


func _update_card_state(agent_id: String, state: String) -> void:
	var card: Control = _cards.get(agent_id)
	if card == null:
		return
	var state_label: Label = card.get_meta("state_label")
	var start_button: Button = card.get_meta("start_button")
	var avatar: CharacterAvatar = card.get_meta("avatar")
	state_label.text = STATE_LABELS.get(state, state.capitalize())
	start_button.text = "Stop" if state in ["thinking", "working", "reading", "coding", "terminal", "searching", "question", "approval", "success"] else "Start"
	avatar.set_state(state)


func _get_state(agent_id: String) -> String:
	return str(AgentManager.get_session(agent_id).get("state", "offline"))


func _on_context_usage(agent_id: String, percent: float, tokens: int) -> void:
	var card: Control = _cards.get(agent_id)
	if card == null:
		return
	var bar: ProgressBar = card.get_meta("context_bar")
	var pct_label: Label = card.get_meta("context_pct")
	bar.value = percent
	pct_label.text = "%d%% %s" % [int(percent), _fmt_tokens(tokens)]
	_update_bar_color(bar, percent)


func _fmt_tokens(n: int) -> String:
	if n >= 1000:
		return "%.1fk" % (n / 1000.0)
	return str(n)


func _context_bar_bg() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.15, 0.16, 0.2, 1)
	sb.set_corner_radius_all(3)
	return sb


func _context_bar_fill() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.25, 0.55, 1)
	sb.set_corner_radius_all(3)
	return sb


func _update_bar_color(bar: ProgressBar, percent: float) -> void:
	var col := Color(0.25, 0.55, 1)
	if percent >= 75.0:
		col = Color(1, 0.4, 0.35)
	elif percent >= 50.0:
		col = Color(1, 0.75, 0.3)
	var sb := _context_bar_fill()
	sb.bg_color = col
	bar.add_theme_stylebox_override("fill", sb)
