extends Node

signal models_loaded
signal load_progress(value: float)

var models: Array[String] = []
var model_variants: Dictionary = {}
var model_limits: Dictionary = {}
var loaded_once: bool = false
var loading: bool = false
var _thread: Thread


func refresh() -> void:
	if loading:
		return
	loading = true
	_do_refresh(false)
	_finish_refresh()


func refresh_with_network() -> void:
	if loading:
		return
	loading = true
	_do_refresh(true)
	_finish_refresh()


func refresh_async(network: bool = false) -> void:
	if loading:
		return
	loading = true
	_thread = Thread.new()
	_thread.start(_refresh_worker.bind(network))


func _exit_tree() -> void:
	if _thread != null:
		if _thread.is_started():
			_thread.wait_to_finish()
		_thread = null


func _refresh_worker(network: bool) -> void:
	_do_refresh(network)
	call_deferred("_finish_async")


func _finish_async() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	_finish_refresh()


func _finish_refresh() -> void:
	loading = false
	loaded_once = true
	models_loaded.emit()


func _do_refresh(_network: bool) -> void:
	var args := ["models"]
	var output: Array = []
	var err := OS.execute("opencode", args, output, true, false)
	if err != OK:
		push_warning("opencode models failed with error %d" % err)
		return
	models.clear()
	_collect_models(output)
	_emit_progress(0.5)
	_load_model_details()
	_emit_progress(1.0)


func _emit_progress(value: float) -> void:
	call_deferred("_notify_progress", value)


func _notify_progress(value: float) -> void:
	load_progress.emit(value)


func get_variants(model_id: String) -> Array:
	var v = model_variants.get(model_id, [])
	return v if v is Array else []


func get_context_limit(model_id: String) -> int:
	return int(model_limits.get(model_id, 0))


func _load_model_details() -> void:
	for _attempt in 2:
		var output: Array = []
		if OS.execute("opencode", ["api", "get", "/api/model"], output, true, false) != OK:
			continue
		var parser := JSON.new()
		if parser.parse("".join(PackedStringArray(output))) != OK:
			continue
		var response: Variant = parser.data
		if response is Dictionary and response.get("data") is Array and not response["data"].is_empty():
			model_variants.clear()
			model_limits.clear()
			_collect_model_details(response["data"])
			return
	push_warning("Could not load OpenCode model details from the shared service")


func _collect_model_details(entries: Array) -> void:
	for entry in entries:
		if not entry is Dictionary:
			continue
		var model_id := "%s/%s" % [str(entry.get("providerID", "")), str(entry.get("modelID", ""))]
		if model_id.begins_with("/") or model_id.ends_with("/"):
			continue
		var variants: Variant = entry.get("variants", [])
		var variant_ids: Array[String] = []
		if variants is Array:
			for variant in variants:
				if variant is Dictionary and not str(variant.get("id", "")).is_empty():
					variant_ids.append(str(variant["id"]))
		if not variant_ids.is_empty():
			model_variants[model_id] = variant_ids
		var limit: Variant = entry.get("limit", {})
		if limit is Dictionary:
			model_limits[model_id] = int(limit.get("context", 0))


func _collect_models(output: Array) -> void:
	for raw in output:
		for part in str(raw).split("\n"):
			var m := part.strip_edges()
			if m.is_empty() or m.find("/") == -1:
				continue
			models.append(m)
	models.sort()
