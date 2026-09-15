extends Node


func _ready() -> void:
	var profile := AgentProfile.new()
	profile.ensure_id()
	profile.name = "UIBot"
	profile.project = "/tmp/opencode/temp-skill-probe"
	ProfileStore.save_profile(profile)

	var panel: WorkspacePanel = load("res://scenes/ui/workspace_panel.tscn").instantiate()
	add_child(panel)
	await get_tree().process_frame

	panel._on_agent_selected(profile)
	panel._populate_temp_skill_select()
	await get_tree().process_frame
	print("[TEMPUI] select_items=", panel.temp_skill_select.item_count)

	AgentManager.add_temp_skill(profile.id, "ui-skill", "Some instructions", "text")
	await get_tree().process_frame
	print("[TEMPUI] rows=", panel.temp_skills_box.get_child_count(), " clear_disabled=", panel.temp_skills_box.get_parent().get_node("ClearTempSkillsButton").disabled)

	panel.temp_skill_dialog.open()
	await get_tree().process_frame
	print("[TEMPUI] dialog_visible=", panel.temp_skill_dialog.visible)
	panel.temp_skill_dialog._on_add_instructions_pressed()
	panel.temp_skill_dialog.text_edit.text = "Typed instruction"
	panel.temp_skill_dialog._on_add_instructions_pressed()
	await get_tree().process_frame
	print("[TEMPUI] rows_after_dialog=", panel.temp_skills_box.get_child_count())
	panel.temp_skill_dialog.hide()

	AgentManager.clear_temp_skills(profile.id)
	await get_tree().process_frame
	print("[TEMPUI] rows_after_clear=", panel.temp_skills_box.get_child_count())
	ProfileStore.delete_profile(profile.id)
	get_tree().quit()
