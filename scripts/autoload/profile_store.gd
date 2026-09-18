extends Node

const PROFILES_DIR := "user://agents"
const SESSIONS_DIR := "user://sessions"
const CHAT_PATH := "user://chat.json"
const PROJECT_COLORS_PATH := "user://project_colors.json"
const DEFAULT_AGENTS_DIR := "res://agents/default"

var profiles: Dictionary = {}
var chat_history: Array = []
var project_colors: Dictionary = {}


func _ready() -> void:
	randomize()
	_ensure_dirs()
	load_profiles()
	_seed_default_profiles()
	load_chat_history()
	load_project_colors()


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


func find_profile_by_name(name: String) -> AgentProfile:
	var lower := name.to_lower()
	for profile in profiles.values():
		if profile.name.to_lower() == lower or profile.name.to_lower().replace(" ", "_") == lower:
			return profile
	return null


func extract_mentions(text: String) -> Array:
	var mentions: Array = []
	var regex := RegEx.new()
	regex.compile("@([A-Za-z0-9_]+)")
	for m in regex.search_all(text):
		var name := m.get_string(1)
		if name == "all":
			if not mentions.has("all"):
				mentions.append("all")
			continue
		var profile := find_profile_by_name(name)
		if profile != null and not mentions.has(profile.id):
			mentions.append(profile.id)
	return mentions


func load_chat_history() -> void:
	var text := _read_text(CHAT_PATH)
	if text.is_empty():
		chat_history = []
		return
	var parsed = JSON.parse_string(text)
	if parsed is Array:
		chat_history = []
		var migrated := false
		for raw_message in parsed:
			if raw_message is Dictionary:
				var message := _normalize_chat_message(raw_message)
				migrated = migrated or not raw_message.has("id") or not raw_message.has("session_id")
				chat_history.append(message)
		if migrated:
			_write_chat_history()


func append_chat_message(sender: String, content: String, mentions: Array, timestamp: int, is_agent: bool, session_id = null) -> Dictionary:
	var message := {
		"id": _new_chat_id(),
		"sender": sender,
		"content": content,
		"mentions": mentions.duplicate(),
		"timestamp": timestamp,
		"is_agent": is_agent,
		"session_id": session_id,
	}
	chat_history.append(message)
	_write_chat_history()
	return message


func clear_chat_history() -> void:
	chat_history.clear()
	_write_chat_history()


func get_chat_messages(after_id: String = "", limit: int = 100) -> Dictionary:
	var capped_limit := clampi(limit, 1, 250)
	var start := 0
	if not after_id.is_empty():
		for index in chat_history.size():
			if str((chat_history[index] as Dictionary).get("id", "")) == after_id:
				start = index + 1
				break
	else:
		start = maxi(0, chat_history.size() - capped_limit)
	var end := mini(chat_history.size(), start + capped_limit)
	var messages: Array = []
	for index in range(start, end):
		messages.append((chat_history[index] as Dictionary).duplicate(true))
	return {
		"messages": messages,
		"next_cursor": str(messages.back().get("id", "")) if not messages.is_empty() else after_id,
		"has_more": end < chat_history.size(),
	}


func _normalize_chat_message(raw_message: Dictionary) -> Dictionary:
	return {
		"id": str(raw_message.get("id", _new_chat_id())),
		"sender": str(raw_message.get("sender", "system")),
		"content": str(raw_message.get("content", "")),
		"mentions": raw_message.get("mentions", []) if raw_message.get("mentions", []) is Array else [],
		"timestamp": int(raw_message.get("timestamp", 0)),
		"is_agent": bool(raw_message.get("is_agent", false)),
		"session_id": raw_message.get("session_id", null),
	}


func _new_chat_id() -> String:
	return "msg_" + Crypto.new().generate_random_bytes(16).hex_encode()


func _write_chat_history() -> Error:
	var temporary_path := CHAT_PATH + ".tmp"
	var err := _write_text(temporary_path, JSON.stringify(chat_history, "\t"))
	if err != OK:
		return err
	var absolute_path := ProjectSettings.globalize_path(CHAT_PATH)
	var temporary_absolute_path := ProjectSettings.globalize_path(temporary_path)
	err = DirAccess.rename_absolute(temporary_absolute_path, absolute_path)
	if err != OK:
		return err
	return OK


func load_project_colors() -> void:
	var text := _read_text(PROJECT_COLORS_PATH)
	if text.is_empty():
		project_colors = {}
		return
	var parsed = JSON.parse_string(text)
	project_colors = parsed if parsed is Dictionary else {}


func get_project_color(project: String) -> String:
	return str(project_colors.get(_project_key(project), ""))


func set_project_color(project: String, color: String) -> void:
	var key := _project_key(project)
	if key.is_empty():
		return
	if color.is_empty():
		project_colors.erase(key)
	else:
		project_colors[key] = color
	_write_text(PROJECT_COLORS_PATH, JSON.stringify(project_colors, "\t"))


func _project_key(project: String) -> String:
	var p := project.strip_edges()
	while p.ends_with("/") or p.ends_with("\\"):
		p = p.substr(0, p.length() - 1)
	return p


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
