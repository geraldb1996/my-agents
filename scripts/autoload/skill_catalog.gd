extends Node

signal skills_loaded

var skills: Array[String] = []
var loaded_once: bool = false
var loading: bool = false


func refresh() -> void:
	if loading:
		return
	loading = true
	skills.clear()
	_scan_dir(OS.get_environment("HOME").path_join(".config/opencode/skills"))
	_scan_dir(OS.get_environment("HOME").path_join(".agents/skills"))
	_scan_dir(ProjectSettings.globalize_path("res://.opencode/skills"))
	skills.sort()
	loading = false
	loaded_once = true
	skills_loaded.emit()


func _scan_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for entry in dir.get_directories():
		if FileAccess.file_exists(path.path_join(entry).path_join("SKILL.md")):
			if not skills.has(entry):
				skills.append(entry)