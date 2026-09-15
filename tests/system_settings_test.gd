extends Node

var _ok := true


func _ready() -> void:
	for theme_name in ThemeManager.THEME_NAMES:
		ThemeManager.apply_theme(theme_name)
		_check(ThemeManager.current_theme == theme_name, "Theme builds and applies: %s" % theme_name)
	ThemeManager.apply_theme("dark")
	_check(SystemSettings.save_settings(true, "en", "none", "") == OK, "Save defaults")
	_check(SystemSettings.ui_theme == "dark" and ThemeManager.current_theme == "dark", "Default theme is dark")
	var workspace: WorkspacePanel = load("res://scenes/ui/workspace_panel.tscn").instantiate()
	add_child(workspace)
	var chat: ChatPanel = load("res://scenes/ui/chat_panel.tscn").instantiate()
	add_child(chat)
	await get_tree().process_frame
	var dialog := workspace.settings_dialog
	_check(workspace.info_tabs.get_tab_title(4) == "Sis", "Sis tab exists")
	workspace.info_tabs.current_tab = 2
	workspace.info_tabs.current_tab = 4
	await get_tree().process_frame
	_check(dialog.visible and dialog.exclusive, "Sis opens modal settings without a selected agent")
	_check(dialog.size == Vector2i(get_tree().root.get_visible_rect().size), "Settings cover application viewport")
	_check(workspace.info_tabs.current_tab == 2, "Previous workspace tab is preserved")
	_check(not dialog.agents_language_edit.visible, "None hides language input")
	dialog.agents_language_select.select(1)
	dialog.agents_language_select.item_selected.emit(1)
	_check(dialog.agents_language_edit.visible and dialog.save_button.disabled, "Type requires a nonempty language")
	dialog.agents_language_edit.text = "   "
	dialog.agents_language_edit.text_changed.emit("   ")
	_check(dialog.save_button.disabled, "Whitespace is not a language")
	dialog.agents_language_edit.text = " Japanese "
	dialog.agents_language_edit.text_changed.emit(dialog.agents_language_edit.text)
	dialog.sounds_select.select(1)
	dialog.ui_language_select.select(1)
	dialog.ui_theme_select.select(1)
	dialog.save_button.pressed.emit()
	await get_tree().process_frame
	_check(not dialog.visible, "Save closes settings")
	_check(not SystemSettings.ui_sounds and SystemSettings.ui_language == "es", "UI settings applied")
	_check(SystemSettings.ui_theme == "soft" and ThemeManager.current_theme == "soft", "Theme applied and stored")
	_check(SystemSettings.agents_language == "Japanese", "Typed language trimmed and independent from UI language")
	_check(TranslationServer.translate("System Settings") == "Configuración del sistema", "Spanish catalog loaded")
	_check(workspace.info_tabs.get_tab_title(0) == "Tarea", "Existing workspace translates immediately")
	_check(workspace.task_label.text == "(Sin tarea asignada)", "Dynamic placeholder translates")
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index(SystemSettings.UI_AUDIO_BUS)), "UI audio bus muted")
	chat._play_msg_sound()
	_check(not chat._msg_sound.playing, "Disabled sound does not play")

	var runner := OpenCodeRunner.new()
	runner.agent_name = "LanguageBot"
	runner.personality = "Always speak Spanish."
	runner.task = "Describe this project."
	var prompt := runner._build_prompt()
	_check(prompt.contains("You must speak and provide the information only in: Japanese."), "Initial prompt includes typed language")
	_check(prompt.find("Always speak Spanish.") < prompt.find("only in: Japanese."), "Language preference follows personality")
	_check(prompt.contains("CHAT:") and prompt.ends_with(runner.task), "Prompt format and task preserved")
	runner.session_id = "existing_session"
	_check(not runner._build_prompt().contains("only in:"), "Language instruction is initial-session context")
	runner.session_id = ""

	SystemSettings.ui_language = "en"
	SystemSettings.agents_language = ""
	SystemSettings.load_settings()
	_check(SystemSettings.ui_language == "es" and SystemSettings.agents_language == "Japanese", "Settings persist across reload")
	dialog.open()
	_check(dialog.agents_language_select.selected == 1 and dialog.agents_language_edit.text == "Japanese", "Dialog restores saved values")
	_check(dialog.ui_theme_select.selected == 1, "Dialog restores saved theme")
	dialog.sounds_select.select(0)
	dialog.ui_language_select.select(0)
	dialog.get_node("%CancelSettingsButton").pressed.emit()
	_check(SystemSettings.ui_language == "es" and not SystemSettings.ui_sounds, "Cancel discards draft")
	dialog.open()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	dialog._input(escape)
	_check(not dialog.visible, "Escape closes settings")
	_check(SystemSettings.save_settings(true, "en", "none", "Japanese") == OK, "None can retain an inactive draft")
	_check(not runner._build_prompt().contains("only in:"), "None adds no language instruction even with saved text")
	_check(SystemSettings.save_settings(false, "es", "type", " ") == ERR_INVALID_PARAMETER, "Invalid language cannot be saved")
	_check(SystemSettings.ui_sounds and SystemSettings.ui_language == "en", "Invalid settings do not change active settings")
	_check(SystemSettings.save_settings(true, "en", "none", "", "neon") == ERR_INVALID_PARAMETER, "Invalid theme cannot be saved")
	_check(SystemSettings.ui_theme == "dark", "Invalid theme does not change active theme")
	await get_tree().process_frame
	_check(workspace.info_tabs.get_tab_title(0) == "Task", "Can switch UI back to English")
	_check(workspace.task_label.text == "(No task assigned)", "Dynamic placeholder returns to English")
	_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(SystemSettings.UI_AUDIO_BUS)), "UI audio re-enabled")
	chat._play_msg_sound()
	_check(chat._msg_sound.playing, "Enabled sound plays")
	chat._msg_sound.stop()
	runner.free()
	chat.queue_free()
	workspace.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout
	print("[SETTINGSTEST] RESULT=", "PASS" if _ok else "FAIL")
	get_tree().quit(0 if _ok else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_ok = false
		print("[SETTINGSTEST] ", message)
