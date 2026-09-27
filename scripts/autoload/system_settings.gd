extends Node

signal settings_changed

const SETTINGS_PATH := "user://settings.cfg"
const UI_AUDIO_BUS := "UI"

var ui_sounds: bool = true
var ui_language: String = "en"
var ui_theme: String = "dark"
var agents_language_mode: String = "none"
var agents_language: String = ""
var user_name: String = ""
var project_folders: PackedStringArray = []


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	var error := config.load(SETTINGS_PATH)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		push_warning("Could not load system settings: %s" % error_string(error))
	ui_sounds = bool(config.get_value("ui", "sounds", true))
	ui_language = str(config.get_value("ui", "language", "en"))
	if ui_language not in ["en", "es"]:
		ui_language = "en"
	ui_theme = str(config.get_value("ui", "theme", ThemeManager.DEFAULT_THEME))
	if not ThemeManager.is_valid_theme(ui_theme):
		ui_theme = ThemeManager.DEFAULT_THEME
	agents_language_mode = str(config.get_value("agents", "language_mode", "none"))
	agents_language = str(config.get_value("agents", "language", "")).strip_edges()
	if agents_language_mode not in ["none", "type"] or agents_language.is_empty():
		agents_language_mode = "none"
	user_name = str(config.get_value("agents", "user_name", "")).strip_edges()
	project_folders = _valid_project_folders(config.get_value("workspace", "project_folders", PackedStringArray()))
	_apply_settings()


func save_settings(sounds: bool, locale: String, language_mode: String, language: String, theme: String = "dark", user: String = "") -> Error:
	language = language.strip_edges()
	user = user.strip_edges()
	if locale not in ["en", "es"] or language_mode not in ["none", "type"]:
		return ERR_INVALID_PARAMETER
	if language_mode == "type" and language.is_empty():
		return ERR_INVALID_PARAMETER
	if not ThemeManager.is_valid_theme(theme):
		return ERR_INVALID_PARAMETER
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("ui", "sounds", sounds)
	config.set_value("ui", "language", locale)
	config.set_value("ui", "theme", theme)
	config.set_value("agents", "language_mode", language_mode)
	config.set_value("agents", "language", language)
	config.set_value("agents", "user_name", user)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save system settings: %s" % error_string(error))
		return error
	ui_sounds = sounds
	ui_language = locale
	ui_theme = theme
	agents_language_mode = language_mode
	agents_language = language
	user_name = user
	_apply_settings()
	return OK


func add_project_folder(path: String) -> Error:
	path = path.strip_edges()
	if path.is_empty() or not DirAccess.dir_exists_absolute(path):
		return ERR_INVALID_PARAMETER
	if not project_folders.has(path):
		project_folders.append(path)
	return _save_project_folders()


func remove_project_folder(path: String) -> Error:
	project_folders.erase(path)
	return _save_project_folders()


func _save_project_folders() -> Error:
	var config := ConfigFile.new()
	var load_error := config.load(SETTINGS_PATH)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		push_warning("Could not load system settings: %s" % error_string(load_error))
		return load_error
	config.set_value("workspace", "project_folders", project_folders)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save project folders: %s" % error_string(error))
	return error


func _valid_project_folders(value: Variant) -> PackedStringArray:
	var folders := PackedStringArray()
	if value is not Array and value is not PackedStringArray:
		return folders
	for path in value:
		var folder := str(path).strip_edges()
		if not folder.is_empty() and not folders.has(folder):
			folders.append(folder)
	return folders


func _apply_settings() -> void:
	TranslationServer.set_locale(ui_language)
	ThemeManager.apply_theme(ui_theme)
	var bus := AudioServer.get_bus_index(UI_AUDIO_BUS)
	if bus < 0:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, UI_AUDIO_BUS)
		AudioServer.set_bus_send(bus, "Master")
	AudioServer.set_bus_mute(bus, not ui_sounds)
	settings_changed.emit()


func get_agents_language_instruction() -> String:
	if agents_language_mode != "type" or agents_language.strip_edges().is_empty():
		return ""
	return "You must speak and provide the information only in: %s. This language setting overrides any other language preference in your personality." % agents_language.strip_edges()


func get_user_instruction() -> String:
	if user_name.strip_edges().is_empty():
		return ""
	return "The user you assist is named %s; refer to them by name when addressing them." % user_name.strip_edges()
