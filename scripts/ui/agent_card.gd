extends PanelContainer

var agent_id: String
var agents_panel: AgentsPanel


func _get_drag_data(at_position: Vector2) -> Variant:
	set_drag_preview(_build_drag_preview(at_position))
	return {"agent_id": agent_id, "panel": agents_panel.get_instance_id()}


func _build_drag_preview(at_position: Vector2) -> Control:
	var preview := duplicate(0) as Control
	preview.custom_minimum_size = size
	preview.size = size
	preview.position = -at_position
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return preview


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("panel") == agents_panel.get_instance_id() and data.get("agent_id") != agent_id and ProfileStore.get_profile(str(data.get("agent_id", ""))) != null


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if _can_drop_data(at_position, data):
		agents_panel.move_agent(str(data["agent_id"]), agent_id, at_position.y >= size.y / 2.0)
