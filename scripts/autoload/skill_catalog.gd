extends Node

signal skills_loaded

var skills: Array[String] = []
var global_skills: Array[String] = []
var local_skills: Array[String] = []
var loaded_once: bool = false
var loading: bool = false


func refresh() -> void:
	if loading:
		return
	loading = true
	skills.clear()
	global_skills.clear()
	local_skills.clear()
	_scan_dir(OS.get_environment("HOME").path_join(".config/opencode/skills"), true)
	_scan_dir(OS.get_environment("HOME").path_join(".agents/skills"), true)
	_scan_dir(ProjectSettings.globalize_path("res://.opencode/skills"), false)
	skills.sort()
	global_skills.sort()
	local_skills.sort()
	loading = false
	loaded_once = true
	skills_loaded.emit()


func _scan_dir(path: String, is_global: bool) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for entry in dir.get_directories():
		if FileAccess.file_exists(path.path_join(entry).path_join("SKILL.md")):
			if not skills.has(entry):
				skills.append(entry)
				if is_global:
					global_skills.append(entry)
				else:
					local_skills.append(entry)


func get_skills_by_source(source: String) -> Array[String]:
	match source:
		"global":
			return global_skills
		"local":
			return local_skills
		_:
			return skills