extends Node


func _ready() -> void:
	OpenCodeServer.ensure_ready(_on_ready)


func _on_ready(ok: bool) -> void:
	if not ok:
		print("[SERVERTEST] FAIL: ", OpenCodeServer.startup_error())
		get_tree().quit(1)
		return
	OpenCodeServer.get_json("/api/info", _on_info)


func _on_info(code: int, data: Variant) -> void:
	if code != 200 or not (data is Dictionary) or str(data.get("version", "")).is_empty():
		print("[SERVERTEST] RESULT=FAIL HTTP ", code)
		OpenCodeServer.stop_server()
		get_tree().quit(1)
		return
	ModelCatalog.models_loaded.connect(_on_models_loaded, CONNECT_ONE_SHOT)
	ModelCatalog.refresh_async()


func _on_models_loaded() -> void:
	var port := OpenCodeServer.port()
	OpenCodeServer.ensure_ready(func(ready: bool) -> void:
		var ok := ready and OpenCodeServer.port() == port and not ModelCatalog.models.is_empty() and not ModelCatalog.model_limits.is_empty()
		print("[SERVERTEST] RESULT=", "PASS" if ok else "FAIL", " models=", ModelCatalog.models.size(), " limits=", ModelCatalog.model_limits.size(), " stable_port=", OpenCodeServer.port() == port)
		OpenCodeServer.stop_server()
		get_tree().quit(0 if ok else 1)
	)
