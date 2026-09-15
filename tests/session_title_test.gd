extends Node

var _sid := ""
var _expected := ""


func _ready() -> void:
	if not _load_first_session():
		print("[TITLETEST] SKIPPED (no opencode sessions available)")
		get_tree().quit()
		return

	var got := AgentManager.get_session_title(_sid)
	print("[TITLETEST] sid=", _sid)
	print("[TITLETEST] cli_title=", _expected)
	print("[TITLETEST] lookup=", got, " match=", got == _expected)

	var main_scene: PackedScene = load("res://scenes/main/main.tscn")
	var main := main_scene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var panel := _find_agents_panel(main)

	var profile := AgentProfile.new()
	profile.ensure_id()
	profile.name = "TitleBot"
	profile.project = "/tmp/opencode/ui-probe"
	ProfileStore.save_profile(profile)
	ProfileStore.save_session_history(profile.id, [{
		"opencode_session": _sid,
		"archived_at": int(Time.get_unix_time_from_system()),
	}])
	AgentManager.get_session(profile.id).set("opencode_session", "")

	panel._context_target = profile.id
	panel._populate_session_menu(profile.id)
	var menu: PopupMenu = panel.get_node("%SessionMenu")
	print("[TITLETEST] menu_items=", menu.item_count)
	for i in menu.item_count:
		print("[TITLETEST] item[", i, "]=", menu.get_item_text(i), " | tooltip=", menu.get_item_tooltip(i))
	ProfileStore.delete_profile(profile.id)
	get_tree().quit()


func _load_first_session() -> bool:
	var output: Array = []
	if OS.execute("bash", ["-c", "opencode session list --format json -n 1 </dev/null"], output, false, false) != OK:
		return false
	var text := "\n".join(output)
	var start := text.find("[")
	if start < 0:
		return false
	var end := text.rfind("]")
	if end <= start:
		return false
	var parsed = JSON.parse_string(text.substr(start, end - start + 1))
	if not (parsed is Array) or parsed.is_empty():
		return false
	var entry: Dictionary = parsed[0]
	_sid = str(entry.get("id", ""))
	_expected = str(entry.get("title", ""))
	return not _sid.is_empty()


func _find_agents_panel(node: Node) -> Node:
	if node.has_method("_populate_session_menu"):
		return node
	for child in node.get_children():
		var found := _find_agents_panel(child)
		if found != null:
			return found
	return null
