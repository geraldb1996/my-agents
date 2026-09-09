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
	%NewButton.pressed.connect(_on_new_pressed)
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

	var avatar := TextureRect.new()
	avatar.custom_minimum_size = Vector2(48, 48)
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := _load_texture(profile.character)
	if tex != null:
		avatar.texture = tex
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
	meta_label.text = profile.model
	meta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(meta_label)
	var state_label := Label.new()
	state_label.name = "StateLabel"
	state_label.modulate = Color(0.6, 0.65, 0.7)
	state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(state_label)
	row.add_child(info)

	var actions := VBoxContainer.new()
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var start_button := Button.new()
	start_button.name = "StartButton"
	start_button.text = "Start"
	start_button.custom_minimum_size = Vector2(56, 28)
	start_button.pressed.connect(_on_start_pressed.bind(profile.id, start_button))
	actions.add_child(start_button)
	var edit_button := Button.new()
	edit_button.text = "Edit"
	edit_button.custom_minimum_size = Vector2(56, 28)
	edit_button.pressed.connect(_on_edit_pressed.bind(profile.id))
	actions.add_child(edit_button)
	var delete_button := Button.new()
	delete_button.text = "Del"
	delete_button.custom_minimum_size = Vector2(56, 28)
	delete_button.pressed.connect(_on_delete_pressed.bind(profile.id))
	actions.add_child(delete_button)
	row.add_child(actions)

	card.set_meta("start_button", start_button)
	card.set_meta("state_label", state_label)
	card.set_meta("avatar", avatar)
	_update_card_state(profile.id, _get_state(profile.id))
	return card


func _on_card_input(event: InputEvent, agent_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select(agent_id)


func _select(agent_id: String) -> void:
	if _selected_id == agent_id and not _cards.is_empty():
		return
	_selected_id = agent_id
	AgentManager.select_agent(agent_id)
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
	var avatar: TextureRect = card.get_meta("avatar")
	state_label.text = STATE_LABELS.get(state, state.capitalize())
	var color: Color = CharacterView.STATE_COLORS.get(state, Color(1, 1, 1))
	start_button.text = "Stop" if state in ["thinking", "working", "reading", "coding", "terminal", "searching", "question", "approval", "success"] else "Start"
	if state == "offline":
		avatar.modulate = Color(0.55, 0.55, 0.6, 0.85)
	else:
		avatar.modulate = color.lerp(Color(1, 1, 1), 0.65)


func _get_state(agent_id: String) -> String:
	return str(AgentManager.get_session(agent_id).get("state", "offline"))


func _load_texture(path: String) -> Texture2D:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	return load(path) as Texture2D