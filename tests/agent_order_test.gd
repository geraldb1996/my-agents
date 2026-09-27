extends Node


func _ready() -> void:
	var original_profiles := ProfileStore.profiles
	var original_colors := ProfileStore.project_colors
	var original_order := ProfileStore.agent_order.duplicate()
	var order_path := ProfileStore.AGENT_ORDER_PATH
	var had_order_file := FileAccess.file_exists(order_path)
	var original_file := ""
	if had_order_file:
		original_file = FileAccess.get_file_as_string(order_path)
	ProfileStore.profiles = {}
	ProfileStore.project_colors = {"/project/a": "e5484d", "/project/b": "e5484d", "/project/c": "0091ff"}
	for id in ["a", "b", "c", "d"]:
		var profile := AgentProfile.new()
		profile.id = id
		profile.name = id
		profile.project = "/project/a" if id == "a" else ("/project/b" if id == "b" else ("/project/c" if id == "c" else ""))
		ProfileStore.profiles[id] = profile
	ProfileStore.agent_order = ["a", "d", "b", "c"]
	var ok := ProfileStore.get_agent_order() == ["a", "b", "d", "c"]
	var panel := load("res://scenes/ui/agents_panel.tscn").instantiate() as AgentsPanel
	add_child(panel)
	panel.move_agent("b", "a", false)
	ok = ok and ProfileStore.get_agent_order() == ["b", "a", "d", "c"]
	panel.move_agent("a", "c", true)
	ok = ok and ProfileStore.get_agent_order() == ["d", "c", "b", "a"]
	panel.move_agent("d", "a", false)
	ok = ok and ProfileStore.get_agent_order() == ["c", "d", "b", "a"]
	ProfileStore.load_agent_order()
	ok = ok and ProfileStore.get_agent_order() == ["c", "d", "b", "a"]
	ProfileStore.project_colors["/project/b"] = "0091ff"
	ok = ok and ProfileStore.get_agent_order() == ["c", "b", "d", "a"]
	ProfileStore.project_colors["/project/b"] = "e5484d"
	ProfileStore.profiles.erase("d")
	ok = ok and ProfileStore.get_agent_order() == ["c", "b", "a"]
	var card: Control = panel._cards["a"]
	var grab_point := Vector2(23, 31)
	var preview := card._build_drag_preview(grab_point) as Control
	ok = ok and preview.position == -grab_point and preview.size.x >= card.size.x and preview.size.y >= card.size.y
	ok = ok and preview.get_child_count() == 1
	if preview.get_child_count() == 1:
		var row := preview.get_child(0) as HBoxContainer
		ok = ok and row != null and row.get_child_count() == 2
		if row != null and row.get_child_count() == 2:
			var info := row.get_child(1) as VBoxContainer
			ok = ok and info != null and info.get_child(0).text == "a - a"
	preview.free()
	ok = ok and card._can_drop_data(Vector2.ZERO, {"agent_id": "b", "panel": panel.get_instance_id()})
	ok = ok and not card._can_drop_data(Vector2.ZERO, {"agent_id": "a", "panel": panel.get_instance_id()})
	card._drop_data(Vector2(0, card.size.y), {"agent_id": "b", "panel": panel.get_instance_id()})
	ok = ok and ProfileStore.get_agent_order() == ["c", "a", "b"]
	panel.queue_free()
	ProfileStore.profiles = original_profiles
	ProfileStore.project_colors = original_colors
	ProfileStore.agent_order = original_order
	if had_order_file:
		var file := FileAccess.open(order_path, FileAccess.WRITE)
		file.store_string(original_file)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(order_path))
	print("[ORDERTEST] RESULT=", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
