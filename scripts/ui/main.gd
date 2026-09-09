extends Control

@onready var agents_panel: AgentsPanel = %AgentsPanel
@onready var workspace_panel: WorkspacePanel = %WorkspacePanel
@onready var chat_panel: ChatPanel = %ChatPanel
@onready var editor: AgentEditor = %AgentEditor


func _ready() -> void:
	agents_panel.new_agent_requested.connect(_on_new_agent)
	agents_panel.edit_agent_requested.connect(_on_edit_agent)
	agents_panel.delete_agent_requested.connect(_on_delete_agent)
	if not ProfileStore.profiles.is_empty():
		var first_id: String = ProfileStore.profiles.keys()[0]
		AgentManager.select_agent(first_id)


func _on_new_agent() -> void:
	editor.open_new()


func _on_edit_agent(agent_id: String) -> void:
	var profile := ProfileStore.get_profile(agent_id)
	if profile != null:
		editor.open_profile(profile)


func _on_delete_agent(agent_id: String) -> void:
	AgentManager.stop_agent(agent_id)
	ProfileStore.delete_profile(agent_id)
	ProfileStore.delete_session(agent_id)
	AgentManager.sessions.erase(agent_id)
	AgentManager.selected_agent_id = ""
	EventBus.profile_deleted.emit(agent_id)