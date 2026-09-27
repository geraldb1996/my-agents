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
@onready var remote_chat_access_url: LineEdit = %RemoteChatAccessUrl
@onready var remote_chat_token: LineEdit = %RemoteChatToken
@onready var remote_chat_status: Label = %RemoteChatStatus
@onready var restore_defaults_status: Label = %RestoreDefaultsStatus
@onready var error_label: Label = %SettingsError
@onready var save_button: Button = %SaveSettingsButton

var _remote_setup_thread: Thread


func _ready() -> void:
	close_requested.connect(hide)
	%CancelSettingsButton.pressed.connect(hide)
	save_button.pressed.connect(_on_save_pressed)
	%RegenerateRemoteChatTokenButton.pressed.connect(_on_regenerate_token_pressed)
	%CopyRemoteChatTokenButton.pressed.connect(_on_copy_token_pressed)
	%CopyRemoteChatUrlButton.pressed.connect(_on_copy_url_pressed)
	%ShowRemoteChatQrButton.pressed.connect(_on_show_qr_pressed)
	%RestoreDefaultAgentsButton.pressed.connect(_on_restore_defaults_pressed)
	%RestoreDefaultsDialog.confirmed.connect(_on_restore_defaults_confirmed)
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
	remote_chat_access_url.text = RemoteChatServer.access_url
	remote_chat_token.text = RemoteChatServer.get_token()
	_update_remote_chat_status()
	restore_defaults_status.text = ""
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
	RemoteChatServer.set_access_url(remote_chat_access_url.text)
	hide()


func _on_regenerate_token_pressed() -> void:
	remote_chat_token.text = RemoteChatServer.regenerate_token()
	_update_remote_chat_status()


func _on_copy_token_pressed() -> void:
	DisplayServer.clipboard_set(remote_chat_token.text)
	remote_chat_status.text = tr("Remote Chat token copied.")


func _on_copy_url_pressed() -> void:
	_start_remote_access(false)


func _remote_chat_access_link() -> String:
	var base_url := remote_chat_access_url.text.strip_edges().trim_suffix("/")
	if base_url.is_empty():
		base_url = "http://127.0.0.1:%s" % int(remote_chat_port.value)
	return base_url + "#remote_chat_token=" + remote_chat_token.text.uri_encode()


func _on_show_qr_pressed() -> void:
	_start_remote_access(true)


func _start_remote_access(show_qr: bool) -> void:
	if _remote_setup_thread != null:
		return
	var error := RemoteChatServer.configure(true, int(remote_chat_port.value))
	if error != OK:
		remote_chat_status.text = tr("Could not start Remote Chat: %s") % error_string(error)
		return
	remote_chat_enabled.button_pressed = true
	remote_chat_status.text = tr("Preparing phone access...")
	%CopyRemoteChatUrlButton.disabled = true
	%ShowRemoteChatQrButton.disabled = true
	_remote_setup_thread = Thread.new()
	_remote_setup_thread.start(_remote_setup_worker.bind(int(remote_chat_port.value), remote_chat_access_url.text.strip_edges().trim_suffix("/"), show_qr))


func _remote_setup_worker(local_port: int, manual_url: String, show_qr: bool) -> void:
	var output: Array = []
	var code := OS.execute("tailscale", ["status", "--json"], output, true)
	var status = JSON.parse_string("".join(PackedStringArray(output))) if code == OK else null
	var auto_url := _tailscale_access_url(status)
	if not manual_url.is_empty() and manual_url != auto_url:
		if not (manual_url.begins_with("https://") or manual_url.begins_with("http://")):
			call_deferred("_remote_setup_finished", "", show_qr, "Enter a valid HTTP or HTTPS access URL.")
			return
		call_deferred("_remote_setup_finished", manual_url, show_qr, "")
		return
	if auto_url.is_empty():
		call_deferred("_remote_setup_finished", "", show_qr, "Install Tailscale and sign in on your computer and phone.")
		return
	output.clear()
	code = OS.execute("tailscale", ["serve", "status", "--json"], output, true)
	var serve_status = JSON.parse_string("".join(PackedStringArray(output))) if code == OK else null
	if not _tailscale_serves_port(serve_status, auto_url, local_port):
		output.clear()
		code = OS.execute("tailscale", ["serve", "--bg", "--yes", str(local_port)], output, true)
		if code != OK:
			call_deferred("_remote_setup_finished", "", show_qr, "Could not start Tailscale Serve. Check Tailscale on your computer.")
			return
	call_deferred("_remote_setup_finished", auto_url, show_qr, "")


func _tailscale_access_url(status: Variant) -> String:
	if status is not Dictionary or status.get("BackendState", "") != "Running":
		return ""
	var self_node: Variant = status.get("Self", {})
	if self_node is not Dictionary:
		return ""
	var domain := str(self_node.get("DNSName", "")).trim_suffix(".")
	return "https://" + domain if not domain.is_empty() else ""


func _tailscale_serves_port(status: Variant, url: String, local_port: int) -> bool:
	if status is not Dictionary:
		return false
	var web: Variant = status.get("Web", {})
	if web is not Dictionary:
		return false
	var site: Variant = web.get(url.trim_prefix("https://") + ":443", {})
	if site is not Dictionary:
		return false
	var handlers: Variant = site.get("Handlers", {})
	if handlers is not Dictionary:
		return false
	var root: Variant = handlers.get("/", {})
	return root is Dictionary and str(root.get("Proxy", "")) == "http://127.0.0.1:%d" % local_port


func _remote_setup_finished(url: String, show_qr: bool, error: String) -> void:
	_remote_setup_thread.wait_to_finish()
	_remote_setup_thread = null
	%CopyRemoteChatUrlButton.disabled = false
	%ShowRemoteChatQrButton.disabled = false
	if not error.is_empty():
		remote_chat_status.text = tr(error)
		return
	remote_chat_access_url.text = url
	RemoteChatServer.set_access_url(url)
	var link := _remote_chat_access_link()
	if not show_qr:
		DisplayServer.clipboard_set(link)
		remote_chat_status.text = tr("Remote Chat access link copied.")
		return
	var output_path := ProjectSettings.globalize_path("user://remote-chat-qr.png")
	var result := OS.execute("qrencode", ["-o", output_path, "-s", "8", "-m", "2", link], [], true)
	if result != 0 or not FileAccess.file_exists("user://remote-chat-qr.png"):
		DisplayServer.clipboard_set(link)
		remote_chat_status.text = tr("Could not generate QR. Install qrencode; access link copied instead.")
		return
	OS.shell_open(output_path)
	remote_chat_status.text = tr("QR opened locally. It contains the access URL and token only.")


func _exit_tree() -> void:
	if _remote_setup_thread != null:
		_remote_setup_thread.wait_to_finish()


func _on_restore_defaults_pressed() -> void:
	restore_defaults_status.text = ""
	%RestoreDefaultsDialog.popup_centered()


func _on_restore_defaults_confirmed() -> void:
	var restored := ProfileStore.restore_default_agents()
	if restored.is_empty():
		restore_defaults_status.text = tr("All default agents are already present.")
		return
	restore_defaults_status.text = tr("Restored %d default agent(s).") % restored.size()


func _update_remote_chat_status() -> void:
	remote_chat_status.text = tr("Local-only service. Use Tailscale Serve for private HTTPS access.")


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		hide()
		set_input_as_handled()
