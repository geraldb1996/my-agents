class_name AgentProfile
extends Resource

const ANIMATION_STATES: Array[String] = [
	"idle", "thinking", "working", "reading", "coding", "terminal",
	"searching", "waiting", "question", "approval", "error", "success", "offline",
]

const DEFAULT_CHARACTER := "res://images/agents/agent.png"

@export var id: String = ""
@export var name: String = "New Agent"
@export var model: String = ""
@export var model_variant: String = ""
@export_multiline var personality: String = ""
@export var skills: Array[String] = []
@export var character: String = DEFAULT_CHARACTER
@export var animations: Dictionary = {}
@export var opencode_agent: String = ""
@export var project: String = ""
@export var created_at: int = 0
@export var updated_at: int = 0

var temp_skills: Array[Dictionary] = []


func ensure_id() -> void:
	if id.is_empty():
		id = "ag_%d_%d" % [Time.get_unix_time_from_system(), randi()]


func get_all_skills() -> Array[String]:
	var all: Array[String] = skills.duplicate()
	for entry in temp_skills:
		var name := str(entry.get("name", ""))
		if not name.is_empty() and not all.has(name):
			all.append(name)
	return all


func add_temp_skill(skill: String, content: String = "", source: String = "") -> void:
	var trimmed := skill.strip_edges()
	if trimmed.is_empty():
		trimmed = "Custom instructions"
	for entry in temp_skills:
		if str(entry.get("name", "")) == trimmed and str(entry.get("source", "")) == source:
			entry["content"] = content
			return
	temp_skills.append({"name": trimmed, "source": source, "content": content})


func remove_temp_skill(index: int) -> void:
	if index >= 0 and index < temp_skills.size():
		temp_skills.remove_at(index)


func has_temp_skills() -> bool:
	return not temp_skills.is_empty()


func get_temp_context() -> String:
	var blocks: Array[String] = []
	for entry in temp_skills:
		var content := str(entry.get("content", "")).strip_edges()
		if content.is_empty():
			continue
		var name := str(entry.get("name", ""))
		if name.is_empty():
			blocks.append(content)
		else:
			blocks.append("### %s\n%s" % [name, content])
	return "\n\n".join(blocks)


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"model": model,
		"model_variant": model_variant,
		"personality": personality,
		"skills": skills,
		"character": character,
		"animations": animations,
		"opencode_agent": opencode_agent,
		"project": project,
		"created_at": created_at,
		"updated_at": updated_at,
	}


static func from_dict(data: Dictionary) -> AgentProfile:
	var p := AgentProfile.new()
	p.id = str(data.get("id", ""))
	p.name = str(data.get("name", "New Agent"))
	p.model = str(data.get("model", ""))
	p.model_variant = str(data.get("model_variant", str(data.get("variant", ""))))
	p.personality = str(data.get("personality", ""))
	var raw_skills: Array = data.get("skills", [])
	p.skills.assign(raw_skills)
	p.character = str(data.get("character", DEFAULT_CHARACTER))
	p.animations = data.get("animations", {})
	p.opencode_agent = str(data.get("opencode_agent", ""))
	p.project = str(data.get("project", ""))
	p.created_at = int(data.get("created_at", 0))
	p.updated_at = int(data.get("updated_at", 0))
	return p
