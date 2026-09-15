extends Control

@onready var background: ColorRect = $Background
@onready var agents_panel: AgentsPanel = %AgentsPanel
@onready var workspace_panel: WorkspacePanel = %WorkspacePanel
@onready var chat_panel: ChatPanel = %ChatPanel
@onready var editor: AgentEditor = %AgentEditor
@onready var loading_overlay: Control = %LoadingOverlay
@onready var loading_progress: ProgressBar = %LoadingProgress

var _pending_catalogs: int = 0
var _load_sources: Dictionary = {"models": 0.0, "skills": 0.0}
var _load_target: float = 0.0


func _ready() -> void:
	agents_panel.new_agent_requested.connect(_on_new_agent)
	agents_panel.edit_agent_requested.connect(_on_edit_agent)
	agents_panel.duplicate_agent_requested.connect(_on_duplicate_agent)
	agents_panel.delete_agent_requested.connect(_on_delete_agent)
	ModelCatalog.models_loaded.connect(_on_catalog_loaded)
	SkillCatalog.skills_loaded.connect(_on_catalog_loaded)
	ModelCatalog.load_progress.connect(_on_load_progress.bind("models"))
	SkillCatalog.load_progress.connect(_on_load_progress.bind("skills"))
	ThemeManager.theme_changed.connect(_apply_theme)
	_apply_theme()
	if not ProfileStore.profiles.is_empty():
		var first_id: String = ProfileStore.profiles.keys()[0]
		AgentManager.select_agent(first_id)
	_start_initial_loading()


func _apply_theme() -> void:
	background.color = ThemeManager.color("window")


func _process(delta: float) -> void:
	if not loading_overlay.visible:
		return
	loading_progress.value = lerpf(loading_progress.value, _load_target, clampf(delta * 5.0, 0.0, 1.0))


func _start_initial_loading() -> void:
	_pending_catalogs = 2
	_load_sources["models"] = 0.0
	_load_sources["skills"] = 0.0
	_load_target = 0.0
	loading_progress.value = 0.0
	loading_overlay.visible = true
	await get_tree().process_frame
	ModelCatalog.refresh_async()
	var project := ""
	var profile := ProfileStore.get_profile(AgentManager.selected_agent_id)
	if profile != null:
		project = profile.project
	SkillCatalog.refresh_async(project)


func _on_load_progress(value: float, source: String) -> void:
	if _pending_catalogs <= 0:
		return
	_load_sources[source] = value
	_load_target = (_load_sources["models"] + _load_sources["skills"]) * 0.5


func _on_catalog_loaded() -> void:
	_pending_catalogs -= 1
	if _pending_catalogs > 0:
		return
	_load_target = 1.0
	var tween := create_tween()
	tween.tween_property(loading_progress, "value", 1.0, 0.3)
	await tween.finished
	loading_overlay.visible = false
	agents_panel.refresh()


func _on_new_agent() -> void:
	editor.open_new()


func _on_edit_agent(agent_id: String) -> void:
	var profile := ProfileStore.get_profile(agent_id)
	if profile != null:
		editor.open_profile(profile)


func _on_duplicate_agent(agent_id: String) -> void:
	var profile := ProfileStore.get_profile(agent_id)
	if profile != null:
		editor.open_duplicate(profile)


func _on_delete_agent(agent_id: String) -> void:
	AgentManager.stop_agent(agent_id)
	ProfileStore.delete_profile(agent_id)
	ProfileStore.delete_session(agent_id)
	AgentManager.sessions.erase(agent_id)
	AgentManager.selected_agent_id = ""
	EventBus.profile_deleted.emit(agent_id)
