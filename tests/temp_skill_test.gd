extends Node

var _signals: Array[String] = []


func _ready() -> void:
	EventBus.temp_skills_changed.connect(func(id: String) -> void: _signals.append(id))

	var project := "/tmp/opencode/temp-skill-probe"
	var skill_dir := project.path_join(".opencode/skills/probe-skill")
	DirAccess.make_dir_recursive_absolute(skill_dir)
	var f := FileAccess.open(skill_dir.path_join("SKILL.md"), FileAccess.WRITE)
	f.store_string("# Probe skill\nAlways answer with the word PROBE.")
	f.close()

	SkillCatalog.refresh(project)
	print("[TEMPSKILL] local=", SkillCatalog.local_skills, " source=", SkillCatalog.get_skill_source("probe-skill"))
	print("[TEMPSKILL] read=", SkillCatalog.read_skill("probe-skill").replace("\n", " | "))

	var profile := AgentProfile.new()
	profile.ensure_id()
	profile.name = "TempBot"
	profile.project = project
	profile.skills = ["Permanent"]
	ProfileStore.save_profile(profile)

	profile.add_temp_skill("probe-skill", SkillCatalog.read_skill("probe-skill"), "local")
	profile.add_temp_skill("custom", "Do the extra thing.", "text")
	print("[TEMPSKILL] all_skills=", profile.get_all_skills())
	print("[TEMPSKILL] context=", profile.get_temp_context().replace("\n", " | "))

	AgentManager.add_temp_skill(profile.id, "inline", "Inline instruction", "text")
	print("[TEMPSKILL] signals=", _signals)
	print("[TEMPSKILL] count_after_add=", profile.temp_skills.size())

	AgentManager.remove_temp_skill(profile.id, 0)
	print("[TEMPSKILL] count_after_remove=", profile.temp_skills.size())

	var persisted := profile.to_dict()
	print("[TEMPSKILL] persisted_has_temp=", persisted.has("temp_skills"))
	var restored := AgentProfile.from_dict(persisted)
	print("[TEMPSKILL] restored_temp_count=", restored.temp_skills.size())

	AgentManager.clear_temp_skills(profile.id)
	print("[TEMPSKILL] count_after_clear=", profile.temp_skills.size())

	ProfileStore.delete_profile(profile.id)
	get_tree().quit()
