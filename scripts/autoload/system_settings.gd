extends Node

signal settings_changed

const SETTINGS_PATH := "user://settings.cfg"
const UI_AUDIO_BUS := "UI"

var ui_sounds: bool = true
var ui_language: String = "en"
var ui_theme: String = "dark"
var agents_language_mode: String = "none"
var agents_language: String = ""


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
	_apply_settings()


func save_settings(sounds: bool, locale: String, language_mode: String, language: String, theme: String = "dark") -> Error:
	language = language.strip_edges()
	if locale not in ["en", "es"] or language_mode not in ["none", "type"]:
		return ERR_INVALID_PARAMETER
	if language_mode == "type" and language.is_empty():
		return ERR_INVALID_PARAMETER
	if not ThemeManager.is_valid_theme(theme):
		return ERR_INVALID_PARAMETER
	var config := ConfigFile.new()
	config.set_value("ui", "sounds", sounds)
	config.set_value("ui", "language", locale)
	config.set_value("ui", "theme", theme)
	config.set_value("agents", "language_mode", language_mode)
	config.set_value("agents", "language", language)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save system settings: %s" % error_string(error))
		return error
	ui_sounds = sounds
	ui_language = locale
	ui_theme = theme
	agents_language_mode = language_mode
	agents_language = language
	_apply_settings()
	return OK


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
