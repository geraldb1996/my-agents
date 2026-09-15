extends Node

const PROFILES_DIR := "user://agents"
const SESSIONS_DIR := "user://sessions"
const CHAT_PATH := "user://chat.json"
const DEFAULT_AGENTS_DIR := "res://agents/default"

var profiles: Dictionary = {}
var chat_history: Array = []


func _ready() -> void:
	randomize()
	_ensure_dirs()
	load_profiles()
	_seed_default_profiles()
	load_chat_history()


func _ensure_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROFILES_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SESSIONS_DIR))


func load_profiles() -> void:
	profiles.clear()
	var dir := DirAccess.open(PROFILES_DIR)
	if dir == null:
		return
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var path := PROFILES_DIR.path_join(file_name)
		var text := _read_text(path)
		if text.is_empty():
			continue
		var parsed = JSON.parse_string(text)
		if parsed is Dictionary:
			var profile := AgentProfile.from_dict(parsed)
			profile.ensure_id()
			profiles[profile.id] = profile


func _seed_default_profiles() -> void:
	if not profiles.is_empty():
		return
	var dir := DirAccess.open(DEFAULT_AGENTS_DIR)
	if dir == null:
		return
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var text := _read_text(DEFAULT_AGENTS_DIR.path_join(file_name))
		if text.is_empty():
			continue
		var parsed = JSON.parse_string(text)
		if parsed is Dictionary:
			save_profile(AgentProfile.from_dict(parsed))


func save_profile(profile: AgentProfile) -> void:
	profile.ensure_id()
	profile.updated_at = Time.get_unix_time_from_system()
	if profile.created_at == 0:
		profile.created_at = profile.updated_at
	var path := PROFILES_DIR.path_join(profile.id + ".json")
	var err := _write_text(path, JSON.stringify(profile.to_dict(), "\t"))
	if err == OK:
		profiles[profile.id] = profile


func delete_profile(agent_id: String) -> void:
	if not profiles.has(agent_id):
		return
	var path := PROFILES_DIR.path_join(agent_id + ".json")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	profiles.erase(agent_id)


func get_profile(agent_id: String) -> AgentProfile:
	return profiles.get(agent_id, null)


func load_chat_history() -> void:
	var text := _read_text(CHAT_PATH)
	if text.is_empty():
		chat_history = []
		return
	var parsed = JSON.parse_string(text)
	if parsed is Array:
		chat_history = parsed


func append_chat_message(sender: String, content: String, mentions: Array, timestamp: int, is_agent: bool) -> void:
	chat_history.append({
		"sender": sender,
		"content": content,
		"mentions": mentions,
		"timestamp": timestamp,
		"is_agent": is_agent,
	})
	_write_text(CHAT_PATH, JSON.stringify(chat_history, "\t"))


func clear_chat_history() -> void:
	chat_history.clear()
	_write_text(CHAT_PATH, "[]")


func load_session(agent_id: String) -> Dictionary:
	var path := SESSIONS_DIR.path_join(agent_id + ".json")
	var text := _read_text(path)
	if text.is_empty():
		return {}
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func save_session(agent_id: String, session: Dictionary) -> void:
	session["agent_id"] = agent_id
	session["last_active"] = Time.get_unix_time_from_system()
	var path := SESSIONS_DIR.path_join(agent_id + ".json")
	_write_text(path, JSON.stringify(session, "\t"))


func delete_session(agent_id: String) -> void:
	var path := SESSIONS_DIR.path_join(agent_id + ".json")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func load_session_history(agent_id: String) -> Array:
	var path := SESSIONS_DIR.path_join(agent_id + ".history.json")
	var text := _read_text(path)
	if text.is_empty():
		return []
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Array else []


func save_session_history(agent_id: String, history: Array) -> void:
	var path := SESSIONS_DIR.path_join(agent_id + ".history.json")
	_write_text(path, JSON.stringify(history, "\t"))


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _write_text(path: String, text: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	return OK