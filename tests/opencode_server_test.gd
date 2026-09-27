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
	var ok := code == 200 and data is Dictionary and not str(data.get("version", "")).is_empty()
	print("[SERVERTEST] RESULT=", "PASS" if ok else "FAIL", " HTTP ", code)
	OpenCodeServer.stop_server()
	get_tree().quit(0 if ok else 1)
