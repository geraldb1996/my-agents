class_name TempSkillDialog
extends Window

signal skill_added(entry: Dictionary)

@onready var source_option: OptionButton = %SourceOption
@onready var skill_select: OptionButton = %SkillSelect
@onready var load_file_button: Button = %LoadFileButton
@onready var file_path_label: Label = %FilePathLabel
@onready var name_edit: LineEdit = %NameEdit
@onready var text_edit: TextEdit = %TextEdit
@onready var add_instructions_button: Button = %AddInstructionsButton
@onready var close_button: Button = %CloseButton
@onready var file_dialog: FileDialog = %TempFileDialog

var _file_content: String = ""
var _file_name: String = ""


func _ready() -> void:
	_populate_source_options()
	source_option.item_selected.connect(_on_source_selected)
	skill_select.item_selected.connect(_on_skill_selected)
	load_file_button.pressed.connect(_on_load_file_pressed)
	file_dialog.file_selected.connect(_on_file_selected)
	add_instructions_button.pressed.connect(_on_add_instructions_pressed)
	close_button.pressed.connect(hide)
	SkillCatalog.skills_loaded.connect(_on_skills_loaded)


func open() -> void:
	_reset()
	_populate_skills()
	popup_centered(Vector2i(560, 540))


func _reset() -> void:
	_file_content = ""
	_file_name = ""
	name_edit.text = ""
	text_edit.text = ""
	file_path_label.text = "No file loaded"
	file_path_label.tooltip_text = ""
	source_option.select(0)


func _populate_source_options() -> void:
	source_option.clear()
	source_option.add_item("All skills", 0)
	source_option.add_item("Global", 1)
	source_option.add_item("Local (project)", 2)


func _selected_source() -> String:
	match source_option.selected:
		1:
			return "global"
		2:
			return "local"
		_:
			return "all"


func _populate_skills() -> void:
	var source := _selected_source()
	skill_select.clear()
	skill_select.add_item("Pick an installed skill...", 0)
	for skill in SkillCatalog.get_skills_by_source(source):
		skill_select.add_item(skill)
	skill_select.select(0)


func _on_source_selected(_index: int) -> void:
	_populate_skills()


func _on_skills_loaded() -> void:
	if visible:
		_populate_skills()


func _on_skill_selected(index: int) -> void:
	if index <= 0:
		return
	var skill := skill_select.get_item_text(index)
	skill_added.emit({
		"name": skill,
		"source": SkillCatalog.get_skill_source(skill),
		"content": SkillCatalog.read_skill(skill),
	})
	skill_select.select(0)


func _on_load_file_pressed() -> void:
	file_dialog.popup_centered_ratio(0.5)


func _on_file_selected(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	_file_content = file.get_as_text().strip_edges()
	file.close()
	_file_name = path.get_file().get_basename()
	if name_edit.text.strip_edges().is_empty():
		name_edit.text = _file_name
	file_path_label.text = "%s (%d chars)" % [path.get_file(), _file_content.length()]
	file_path_label.tooltip_text = path


func _on_add_instructions_pressed() -> void:
	var content := text_edit.text.strip_edges()
	if content.is_empty():
		content = _file_content
	if content.is_empty():
		return
	var name := name_edit.text.strip_edges()
	if name.is_empty():
		name = _file_name if not _file_name.is_empty() else "Custom instructions"
	var source := "file" if content == _file_content and not _file_content.is_empty() else "text"
	skill_added.emit({"name": name, "source": source, "content": content})
	_reset()
