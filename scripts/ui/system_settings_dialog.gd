class_name SystemSettingsDialog
extends Window

@onready var sounds_select: OptionButton = %SoundsSelect
@onready var ui_theme_select: OptionButton = %ThemeSelect
@onready var ui_language_select: OptionButton = %UILanguageSelect
@onready var agents_language_select: OptionButton = %AgentsLanguageSelect
@onready var agents_language_edit: LineEdit = %AgentsLanguageEdit
@onready var error_label: Label = %SettingsError
@onready var save_button: Button = %SaveSettingsButton


func _ready() -> void:
	close_requested.connect(hide)
	%CancelSettingsButton.pressed.connect(hide)
	save_button.pressed.connect(_on_save_pressed)
	agents_language_select.item_selected.connect(_on_language_mode_selected)
	agents_language_edit.text_changed.connect(func(_text: String): _update_language_input())
	get_tree().root.size_changed.connect(_fit_to_application)


func open() -> void:
	sounds_select.select(0 if SystemSettings.ui_sounds else 1)
	ui_theme_select.select(maxi(0, ThemeManager.THEME_NAMES.find(SystemSettings.ui_theme)))
	ui_language_select.select(0 if SystemSettings.ui_language == "en" else 1)
	agents_language_select.select(0 if SystemSettings.agents_language_mode == "none" else 1)
	agents_language_edit.text = SystemSettings.agents_language
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
		ThemeManager.THEME_NAMES[theme_index]
	)
	if error != OK:
		error_label.text = tr("Could not save settings: %s") % error_string(error)
		return
	hide()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		hide()
		set_input_as_handled()
