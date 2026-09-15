extends Node


func _ready() -> void:
	var source := AgentProfile.new()
	source.ensure_id()
	source.name = "DupeBot"
	source.model = "opencode-go/deepseek-v4.1-flash"
	source.model_variant = "high"
	source.personality = "Amigable y directo"
	source.opencode_agent = "build"
	source.project = "/tmp/opencode/dupe-probe"
	source.skills.assign(["skill-a", "skill-b"])
	source.animations = {"idle": {"frames": ["res://images/agents/agent.png"], "fps": 8}}
	ProfileStore.save_profile(source)

	var panel: AgentsPanel = load("res://scenes/ui/agents_panel.tscn").instantiate()
	add_child(panel)
	await get_tree().process_frame

	var menu: PopupMenu = panel.get_node("%ContextMenu")
	var dupe_index := menu.get_item_index(4)
	var menu_ok: bool = dupe_index >= 0 and menu.get_item_text(dupe_index) == "Duplicate Agent"
	var emitted: Array = []
	panel.duplicate_agent_requested.connect(func(agent_id: String): emitted.append(agent_id))
	panel._context_target = source.id
	menu.id_pressed.emit(4)
	var signal_ok: bool = menu_ok and emitted.size() == 1 and emitted[0] == source.id
	print("[DUPETEST] menu_ok=", menu_ok, " emitted=", emitted)

	var editor: AgentEditor = load("res://scenes/ui/agent_editor.tscn").instantiate()
	add_child(editor)
	await get_tree().process_frame
	editor.open_duplicate(source)
	await get_tree().process_frame
	editor._on_opencode_agents_loaded(200, [{"name": "build"}, {"name": "plan"}], editor._agent_request_id)
	var prefilled: bool = editor.name_edit.text == "DupeBot (copy)" \
		and editor._editing_id.is_empty() \
		and editor._get_selected_model() == source.model \
		and editor._get_selected_variant() == source.model_variant \
		and editor.personality_edit.text == source.personality \
		and editor._selected_opencode_agent == source.opencode_agent \
		and editor.opencode_agent_select.get_item_text(editor.opencode_agent_select.selected) == source.opencode_agent \
		and editor._project_path == source.project \
		and editor._collect_skills() == source.skills \
		and editor._animations.has("idle")
	print("[DUPETEST] prefilled=", prefilled)

	var before: Array = ProfileStore.profiles.keys()
	editor._on_save_pressed()
	await get_tree().process_frame

	var new_ids: Array = []
	for id in ProfileStore.profiles.keys():
		if not before.has(id):
			new_ids.append(id)
	var copy: AgentProfile = ProfileStore.get_profile(str(new_ids[0])) if new_ids.size() == 1 else null
	var copy_ok: bool = copy != null \
		and copy.id != source.id \
		and copy.name == "DupeBot (copy)" \
		and copy.model == source.model \
		and copy.model_variant == source.model_variant \
		and copy.personality == source.personality \
		and copy.opencode_agent == source.opencode_agent \
		and copy.project == source.project \
		and copy.skills == source.skills \
		and copy.animations.has("idle") \
		and ProfileStore.load_session(copy.id).is_empty()
	var original := ProfileStore.get_profile(source.id)
	var original_ok: bool = original != null and original.name == "DupeBot" and original.skills.size() == 2
	print("[DUPETEST] copy_ok=", copy_ok, " original_ok=", original_ok)

	if copy != null:
		ProfileStore.delete_profile(copy.id)
		ProfileStore.delete_session(copy.id)
	ProfileStore.delete_profile(source.id)
	ProfileStore.delete_session(source.id)
	editor._selected_opencode_agent = "missing-agent"
	editor._on_opencode_agents_loaded(200, [{"name": "build"}], editor._agent_request_id)
	var missing_ok: bool = not editor._agent_selection_valid and editor.get_node("%SaveButton").disabled
	editor.opencode_agent_select.select(0)
	editor.opencode_agent_select.item_selected.emit(0)
	var default_ok: bool = editor._agent_selection_valid and editor._selected_opencode_agent.is_empty()
	editor._on_opencode_agents_loaded(0, null, editor._agent_request_id)
	var failure_ok: bool = editor.opencode_agent_select.item_count == 1 and editor._agent_selection_valid
	editor._on_opencode_agents_loaded(200, [{"name": "stale"}], editor._agent_request_id - 1)
	var stale_ok: bool = editor.opencode_agent_select.item_count == 1
	print("[DUPETEST] missing_ok=", missing_ok, " default_ok=", default_ok, " failure_ok=", failure_ok, " stale_ok=", stale_ok)
	var ok := signal_ok and prefilled and copy_ok and original_ok and missing_ok and default_ok and failure_ok and stale_ok
	print("[DUPETEST] RESULT=", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
