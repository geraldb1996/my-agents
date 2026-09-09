extends Node

signal models_loaded

var models: Array[String] = []
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
	loaded_once = true
	models_loaded.emit()


func _collect_models(output: Array) -> void:
	for raw in output:
		for part in str(raw).split("\n"):
			var m := part.strip_edges()
			if m.is_empty() or m.find("/") == -1:
				continue
			models.append(m)
	models.sort()