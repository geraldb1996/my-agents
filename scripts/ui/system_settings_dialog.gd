class_name SystemSettingsDialog
extends Window

@onready var sounds_select: OptionButton = %SoundsSelect
@onready var ui_theme_select: OptionButton = %ThemeSelect
@onready var ui_language_select: OptionButton = %UILanguageSelect
@onready var agents_language_select: OptionButton = %AgentsLanguageSelect
@onready var agents_language_edit: LineEdit = %AgentsLanguageEdit
@onready var user_name_edit: LineEdit = %UserNameEdit
@onready var remote_chat_enabled: CheckBox = %RemoteChatEnabled
@onready var remote_chat_port: SpinBox = %RemoteChatPort
@onready var remote_chat_token: LineEdit = %RemoteChatToken
@onready var remote_chat_status: Label = %RemoteChatStatus
@onready var error_label: Label = %SettingsError
@onready var save_button: Button = %SaveSettingsButton


func _ready() -> void:
	close_requested.connect(hide)
	%CancelSettingsButton.pressed.connect(hide)
	save_button.pressed.connect(_on_save_pressed)
	%RegenerateRemoteChatTokenButton.pressed.connect(_on_regenerate_token_pressed)
	%CopyRemoteChatTokenButton.pressed.connect(_on_copy_token_pressed)
	%CopyRemoteChatUrlButton.pressed.connect(_on_copy_url_pressed)
	agents_language_select.item_selected.connect(_on_language_mode_selected)
	agents_language_edit.text_changed.connect(func(_text: String): _update_language_input())
	get_tree().root.size_changed.connect(_fit_to_application)


func open() -> void:
	sounds_select.select(0 if SystemSettings.ui_sounds else 1)
	ui_theme_select.select(maxi(0, ThemeManager.THEME_NAMES.find(SystemSettings.ui_theme)))
	ui_language_select.select(0 if SystemSettings.ui_language == "en" else 1)
	agents_language_select.select(0 if SystemSettings.agents_language_mode == "none" else 1)
	agents_language_edit.text = SystemSettings.agents_language
	user_name_edit.text = SystemSettings.user_name
	remote_chat_enabled.button_pressed = RemoteChatServer.enabled
	remote_chat_port.value = RemoteChatServer.port
	remote_chat_token.text = RemoteChatServer.get_token()
	_update_remote_chat_status()
	error_label.text = ""
	_update_language_input()
	popup()
	_fit_to_application()
	sounds_select.grab_focus()


func _fit_to_application() -> void:
	if not visible:
		return
	var root := get_tree().root
	size = Vector2i(root.get_visible_rect().size) if is_embedded() else root.size
	position = Vector2i.ZERO if is_embedded() else root.position


func _on_language_mode_selected(_index: int) -> void:
	_update_language_input()
	if agents_language_edit.visible:
		agents_language_edit.grab_focus()


func _update_language_input() -> void:
	var typed := agents_language_select.selected == 1
	agents_language_edit.visible = typed
	save_button.disabled = typed and agents_language_edit.text.strip_edges().is_empty()


func _on_save_pressed() -> void:
	var theme_index: int = clampi(ui_theme_select.selected, 0, ThemeManager.THEME_NAMES.size() - 1)
	var error := SystemSettings.save_settings(
		sounds_select.selected == 0,
		"en" if ui_language_select.selected == 0 else "es",
		"none" if agents_language_select.selected == 0 else "type",
		agents_language_edit.text,
		ThemeManager.THEME_NAMES[theme_index],
		user_name_edit.text
	)
	if error != OK:
		error_label.text = tr("Could not save settings: %s") % error_string(error)
		return
	error = RemoteChatServer.configure(remote_chat_enabled.button_pressed, int(remote_chat_port.value))
	if error != OK:
		error_label.text = tr("Could not start Remote Chat: %s") % error_string(error)
		return
	hide()


func _on_regenerate_token_pressed() -> void:
	remote_chat_token.text = RemoteChatServer.regenerate_token()
	_update_remote_chat_status()


func _on_copy_token_pressed() -> void:
	DisplayServer.clipboard_set(remote_chat_token.text)
	remote_chat_status.text = tr("Remote Chat token copied.")


func _on_copy_url_pressed() -> void:
	DisplayServer.clipboard_set("http://127.0.0.1:%s" % int(remote_chat_port.value))
	remote_chat_status.text = tr("Local API URL copied. Publish it with Tailscale Serve for remote access.")


func _update_remote_chat_status() -> void:
	remote_chat_status.text = tr("Local-only service. Use Tailscale Serve for private HTTPS access.")


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		hide()
		set_input_as_handled()
