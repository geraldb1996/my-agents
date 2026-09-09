extends Node

signal models_loaded

var models: Array[String] = []
var model_variants: Dictionary = {}
var loaded_once: bool = false
var loading: bool = false


func refresh() -> void:
	if loading:
		return
	loading = true
	var output: Array = []
	var err := OS.execute("opencode", ["models"], output, true, false)
	loading = false
	models.clear()
	if err != OK:
		push_warning("opencode models failed with error %d" % err)
		return
	_collect_models(output)
	_load_variants()
	loaded_once = true
	models_loaded.emit()


func refresh_with_network() -> void:
	if loading:
		return
	loading = true
	var output: Array = []
	var err := OS.execute("opencode", ["models", "--refresh"], output, true, false)
	loading = false
	models.clear()
	if err != OK:
		return
	_collect_models(output)
	_load_variants()
	loaded_once = true
	models_loaded.emit()


func get_variants(model_id: String) -> Array:
	var v = model_variants.get(model_id, [])
	return v if v is Array else []


func _load_variants() -> void:
	model_variants.clear()
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
		if s.begins_with("{"):
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


func _collect_models(output: Array) -> void:
	for raw in output:
		for part in str(raw).split("\n"):
			var m := part.strip_edges()
			if m.is_empty() or m.find("/") == -1:
				continue
			models.append(m)
	models.sort()