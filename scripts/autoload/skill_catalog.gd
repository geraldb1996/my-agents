extends Node

signal skills_loaded

var skills: Array[String] = []
var global_skills: Array[String] = []
var local_skills: Array[String] = []
var skill_paths: Dictionary = {}
var skill_sources: Dictionary = {}
var loaded_once: bool = false
var loading: bool = false


func refresh(project_path: String = "") -> void:
	if loading:
		return
	loading = true
	skills.clear()
	global_skills.clear()
	local_skills.clear()
	skill_paths.clear()
	skill_sources.clear()
	var home := OS.get_environment("HOME")
	_scan_dir(home.path_join(".config/opencode/skills"), true)
	_scan_dir(home.path_join(".agents/skills"), true)
	var project := project_path.strip_edges()
	if project.is_empty():
		_scan_dir(ProjectSettings.globalize_path("res://.opencode/skills"), false)
	else:
		var expanded := _expand_path(project)
		_scan_dir(expanded.path_join(".opencode/skills"), false)
		_scan_dir(expanded.path_join(".agents/skills"), false)
	skills.sort()
	global_skills.sort()
	local_skills.sort()
	loading = false
	loaded_once = true
	skills_loaded.emit()


func _expand_path(path: String) -> String:
	if path.begins_with("~"):
		return OS.get_environment("HOME").path_join(path.substr(1).trim_prefix("/"))
	if path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path


func _scan_dir(path: String, is_global: bool) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for entry in dir.get_directories():
		var skill_md := path.path_join(entry).path_join("SKILL.md")
		if FileAccess.file_exists(skill_md):
			if not skills.has(entry):
				skills.append(entry)
				if is_global:
					global_skills.append(entry)
				else:
					local_skills.append(entry)
				skill_paths[entry] = skill_md
				skill_sources[entry] = "global" if is_global else "local"


func get_skills_by_source(source: String) -> Array[String]:
	match source:
		"global":
			return global_skills
		"local":
			return local_skills
		_:
			return skills


func get_skill_source(skill_name: String) -> String:
	return str(skill_sources.get(skill_name, ""))


func get_skill_path(skill_name: String) -> String:
	return str(skill_paths.get(skill_name, ""))


func read_skill(skill_name: String) -> String:
	var path := get_skill_path(skill_name)
	if path.is_empty() or not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text.strip_edges()
