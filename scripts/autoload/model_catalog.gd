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
	loading = false
	loaded_once = true
	models_loaded.emit()


func refresh_with_network() -> void:
	if loading:
		return
	loading = true
	_do_refresh(true)
	loading = false
	loaded_once = true
	models_loaded.emit()


func refresh_async() -> void:
	if loading:
		return
	loading = true
	_thread = Thread.new()
	_thread.start(_refresh_worker)


func _refresh_worker() -> void:
	_do_refresh(false)
	call_deferred("_finish_async")


func _finish_async() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	loading = false
	loaded_once = true
	models_loaded.emit()


func _do_refresh(network: bool) -> void:
	var args := ["models", "--refresh"] if network else ["models"]
	var output: Array = []
	var err := OS.execute("opencode", args, output, true, false)
	models.clear()
	if err != OK:
		push_warning("opencode models failed with error %d" % err)
		return
	_collect_models(output)
	_emit_progress(0.5)
	_load_variants()
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


func _load_variants() -> void:
	model_variants.clear()
	model_limits.clear()
	var output: Array = []
	var err := OS.execute("opencode", ["models", "--verbose"], output, true, false)
	if err != OK:
		return
	var text := ""
	for raw in output:
		text += str(raw)
	var lines := text.split("\n")
	var current_model := ""
	var block: PackedStringArray = PackedStringArray()
	var depth := 0
	for ln in lines:
		var s := ln.strip_edges()
		if current_model.is_empty() and not s.begins_with("{") and not s.begins_with("\"") and s.find("/") != -1:
			current_model = s
			continue
		if depth == 0 and s.begins_with("{"):
			depth = s.count("{") - s.count("}")
			block = PackedStringArray([ln])
			continue
		if depth > 0:
			block.append(ln)
			depth += ln.count("{") - ln.count("}")
			if depth <= 0:
				_finish_variant_block(current_model, block)
				current_model = ""
				depth = 0


func _finish_variant_block(model_id: String, block: PackedStringArray) -> void:
	if model_id.is_empty():
		return
	var parsed = JSON.parse_string("\n".join(block))
	if parsed is Dictionary:
		var v: Dictionary = parsed.get("variants", {})
		if v is Dictionary and not v.is_empty():
			model_variants[model_id] = v.keys()
		var limit: Dictionary = parsed.get("limit", {})
		if limit is Dictionary and not limit.is_empty():
			model_limits[model_id] = int(limit.get("context", 0))


func _collect_models(output: Array) -> void:
	for raw in output:
		for part in str(raw).split("\n"):
			var m := part.strip_edges()
			if m.is_empty() or m.find("/") == -1:
				continue
			models.append(m)
	models.sort()