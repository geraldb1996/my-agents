extends Control

@onready var agents_panel: AgentsPanel = %AgentsPanel
@onready var workspace_panel: WorkspacePanel = %WorkspacePanel
@onready var chat_panel: ChatPanel = %ChatPanel
@onready var editor: AgentEditor = %AgentEditor
@onready var loading_overlay: Control = %LoadingOverlay

var _pending_catalogs: int = 0


func _ready() -> void:
	agents_panel.new_agent_requested.connect(_on_new_agent)
	agents_panel.edit_agent_requested.connect(_on_edit_agent)
	agents_panel.delete_agent_requested.connect(_on_delete_agent)
	ModelCatalog.models_loaded.connect(_on_catalog_loaded)
	SkillCatalog.skills_loaded.connect(_on_catalog_loaded)
	if not ProfileStore.profiles.is_empty():
		var first_id: String = ProfileStore.profiles.keys()[0]
		AgentManager.select_agent(first_id)
	_start_initial_loading()


func _start_initial_loading() -> void:
	_pending_catalogs = 2
	loading_overlay.visible = true
	await get_tree().process_frame
	ModelCatalog.refresh()
	SkillCatalog.refresh()


func _on_catalog_loaded() -> void:
	_pending_catalogs -= 1
	if _pending_catalogs <= 0:
		loading_overlay.visible = false
		agents_panel.refresh()


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
