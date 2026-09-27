extends Node
## Chequeo de actualizaciones contra el manifest central de GGUpdater.
## No descarga ni instala: solo compara version_number y, si hay algo nuevo,
## muestra un popup y lanza GGUpdater únicamente si el usuario acepta.

const APP_ID := "myagents"
const GITHUB_OWNER := "GeraldGlitch"
const GITHUB_REPO := "ggupdater"
const GITHUB_BRANCH := "main"
const VERSION_PATH := "res://version.json"

var _remote_manifest: Dictionary = {}


func check_for_updates() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var local := _load_local_version()
	if local.is_empty():
		return
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	http.request_completed.connect(_on_manifest_received.bind(http, local))
	var url := _manifest_url() + "?t=%d" % int(Time.get_unix_time_from_system())
	if http.request(url) != OK:
		http.queue_free()


func _manifest_url() -> String:
	return "https://raw.githubusercontent.com/%s/%s/%s/manifests/%s.json" % [
		GITHUB_OWNER, GITHUB_REPO, GITHUB_BRANCH, APP_ID,
	]


func _load_local_version() -> Dictionary:
	if not FileAccess.file_exists(VERSION_PATH):
		return {}
	var file := FileAccess.open(VERSION_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}


func _on_manifest_received(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest, local: Dictionary) -> void:
	http.queue_free()
	if response_code != 200:
		return
	var remote: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (remote is Dictionary):
		return
	if str(remote.get("app_id", "")) != APP_ID:
		return
	var remote_number := int(remote.get("version_number", -1))
	var local_number := int(local.get("version_number", -1))
	if remote_number <= local_number:
		return
	_remote_manifest = remote
	_show_update_popup(remote, local)


func _show_update_popup(remote: Dictionary, local: Dictionary) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = str(remote.get("update_title", tr("Update available")))
	var message := str(remote.get("update_msg", ""))
	if message.is_empty():
		message = tr("New version %s → %s") % [str(local.get("version", "")), str(remote.get("version", ""))]
	dialog.dialog_text = message
	dialog.ok_button_text = tr("Update")
	dialog.cancel_button_text = tr("Cancel")
	dialog.min_size = Vector2(420, 180)
	get_tree().root.add_child(dialog)
	dialog.confirmed.connect(_launch_updater.bind(local))
	dialog.canceled.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)
	dialog.popup_centered()


func _launch_updater(local: Dictionary) -> void:
	var exe_path := OS.get_executable_path()
	var app_root := exe_path.get_base_dir()
	var updater_name := "ggupdater.exe" if OS.get_name() == "Windows" else "ggupdater.x86_64"
	var updater_path := app_root.path_join("ggupdater").path_join(updater_name)
	if not FileAccess.file_exists(updater_path):
		_show_error(tr("GGUpdater was not found in: %s") % updater_path)
		return
	var args := PackedStringArray([
		"--app", APP_ID,
		"--executable", exe_path.get_file(),
		"--current-version", str(local.get("version", "")),
		"--current-version-number", str(int(local.get("version_number", 0))),
		"--pid", str(OS.get_process_id()),
	])
	var pid := OS.create_process(updater_path, args, false)
	if pid <= 0:
		_show_error(tr("Could not start GGUpdater."))
		return
	get_tree().quit()


func _show_error(message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = tr("Update error")
	dialog.dialog_text = message
	dialog.min_size = Vector2(420, 180)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
