extends Node

const HOST := "127.0.0.1"
const PID_PATH := "user://opencode_server.pid"
const START_TIMEOUT_MS := 20000
const PROBE_INTERVAL_MS := 300
const VERSION_CACHE_TTL_MS := 30000

var _pid: int = -1
var _port: int = 0
var _starting: bool = false
var _server_ready: bool = false
var _server_version: String = ""
var _server_password: String = ""
var _startup_error: String = ""
var _model_catalog_changed: bool = false
var _started_at_ms: int = 0
var _probe_at_ms: int = 0
var _callbacks: Array[Callable] = []
var _installed_version_cache: String = ""
var _installed_version_probed_at_ms: int = -1
var _version_thread: Thread


func _ready() -> void:
	_kill_stale_server()
	_probe_installed_version_async()


func _exit_tree() -> void:
	if _version_thread != null:
		if _version_thread.is_started():
			_version_thread.wait_to_finish()
		_version_thread = null
	stop_server()


func _process(_delta: float) -> void:
	if _starting and not _server_ready:
		var now := Time.get_ticks_msec()
		if _pid <= 0 or not OS.is_process_running(_pid) or now - _started_at_ms > START_TIMEOUT_MS:
			_fail_callbacks()
			return
		if now - _probe_at_ms >= PROBE_INTERVAL_MS:
			_probe_at_ms = now
			_probe()
		return
	if _server_ready and _pid > 0 and not OS.is_process_running(_pid):
		_server_ready = false


func port() -> int:
	return _port


func base_url() -> String:
	return "http://%s:%d" % [HOST, _port]


func is_ready() -> bool:
	return _server_ready and _pid > 0 and OS.is_process_running(_pid)


func startup_error() -> String:
	return _startup_error


func _auth_headers() -> PackedStringArray:
	return PackedStringArray(["Authorization: Basic " + Marshalls.utf8_to_base64("opencode:" + _server_password)])


func ensure_ready(callback: Callable, starting_agent_id: String = "") -> void:
	if is_ready() and not _needs_restart():
		callback.call(true)
		return
	if not _callbacks.has(callback):
		_callbacks.append(callback)
	if not _starting:
		if is_ready():
			if not _can_restart(starting_agent_id):
				_callbacks.erase(callback)
				callback.call(true)
				return
			_stop_server()
		_start_server()


func mark_model_catalog_refreshed() -> void:
	_model_catalog_changed = true


func _needs_restart() -> bool:
	if _model_catalog_changed:
		return true
	var installed_version := _installed_version()
	return not _server_version.is_empty() and not installed_version.is_empty() and _server_version != installed_version


func _can_restart(starting_agent_id: String) -> bool:
	var manager := get_node_or_null("/root/AgentManager")
	return manager == null or not manager.has_method("has_running_agents") or not manager.call("has_running_agents", starting_agent_id)


func _installed_version() -> String:
	if _installed_version_probed_at_ms < 0 or Time.get_ticks_msec() - _installed_version_probed_at_ms >= VERSION_CACHE_TTL_MS:
		_probe_installed_version_async()
	return _installed_version_cache


func _probe_installed_version_async() -> void:
	if _version_thread != null:
		return
	_installed_version_probed_at_ms = Time.get_ticks_msec()
	_version_thread = Thread.new()
	_version_thread.start(_installed_version_worker)


func _installed_version_worker() -> void:
	var output: Array = []
	var version := ""
	if OS.execute("opencode", ["--version"], output, true, false) == OK:
		version = "".join(PackedStringArray(output)).strip_edges()
	call_deferred("_on_installed_version_probed", version)


func _on_installed_version_probed(version: String) -> void:
	if _version_thread != null:
		_version_thread.wait_to_finish()
		_version_thread = null
	_installed_version_cache = version
	_installed_version_probed_at_ms = Time.get_ticks_msec()


func post(path: String, body: Dictionary, callback: Callable = Callable()) -> void:
	var request := HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, data: PackedByteArray) -> void:
		var parsed: Variant = null
		if data.size() > 0:
			parsed = JSON.parse_string(data.get_string_from_utf8())
		request.queue_free()
		if callback.is_valid():
			callback.call(code, parsed)
	)
	var headers := _auth_headers()
	headers.append("Content-Type: application/json")
	if request.request(base_url() + path, headers, HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		request.queue_free()
		if callback.is_valid():
			callback.call(0, null)


func get_json(path: String, callback: Callable) -> void:
	var request := HTTPRequest.new()
	request.timeout = 20.0
	add_child(request)
	request.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, data: PackedByteArray) -> void:
		request.queue_free()
		if callback.is_valid():
			callback.call(code, JSON.parse_string(data.get_string_from_utf8()))
	)
	if request.request(base_url() + path, _auth_headers()) != OK:
		request.queue_free()
		if callback.is_valid():
			callback.call(0, null)


func delete_json(path: String, callback: Callable) -> void:
	var request := HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, _data: PackedByteArray) -> void:
		request.queue_free()
		if callback.is_valid():
			callback.call(code, null)
	)
	if request.request(base_url() + path, _auth_headers(), HTTPClient.METHOD_DELETE) != OK:
		request.queue_free()
		if callback.is_valid():
			callback.call(0, null)


func get_agents(directory: String, callback: Callable) -> void:
	ensure_ready(func(ready: bool) -> void:
		if not callback.is_valid():
			return
		if not ready:
			callback.call(0, null)
			return
		var path := "/api/agent"
		var expanded := directory
		if expanded.begins_with("~"):
			expanded = OS.get_environment("HOME").path_join(expanded.substr(1).trim_prefix("/"))
		if not expanded.is_empty():
			path += "?location[directory]=" + expanded.uri_encode()
		get_json(path, callback)
	)


func stop_server() -> void:
	_stop_server()
	_callbacks.clear()


func _stop_server() -> void:
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1
	_server_ready = false
	_server_version = ""
	_starting = false
	_server_password = ""
	if FileAccess.file_exists(PID_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PID_PATH))


func _start_server() -> void:
	_starting = true
	_server_ready = false
	_server_version = ""
	_startup_error = ""
	_port = _find_free_port()
	_server_password = Crypto.new().generate_random_bytes(32).hex_encode()
	var previous_password := OS.get_environment("OPENCODE_SERVER_PASSWORD")
	OS.set_environment("OPENCODE_SERVER_PASSWORD", _server_password)
	_pid = OS.create_process("opencode", ["serve", "--hostname", HOST, "--port", str(_port)], false)
	OS.set_environment("OPENCODE_SERVER_PASSWORD", previous_password)
	if _pid <= 0:
		_startup_error = "Could not launch opencode. Check the app's PATH and installation."
		_fail_callbacks()
		return
	_write_pid_file()
	_started_at_ms = Time.get_ticks_msec()
	_probe_at_ms = 0


func _fail_callbacks() -> void:
	if _startup_error.is_empty():
		_startup_error = "OpenCode did not become ready. Check the OpenCode server log."
	_pid = -1
	_server_ready = false
	_starting = false
	var callbacks := _callbacks.duplicate()
	_callbacks.clear()
	for callback in callbacks:
		callback.call(false)


func _probe() -> void:
	var request := HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		request.queue_free()
		if code == 401:
			_startup_error = "OpenCode server rejected authentication (HTTP 401)."
		if code == 200 and not _server_ready:
			var health: Variant = JSON.parse_string(body.get_string_from_utf8())
			if health is Dictionary:
				_server_version = str((health as Dictionary).get("version", ""))
			_mark_ready()
	)
	if request.request(base_url() + "/api/info", _auth_headers()) != OK:
		request.queue_free()


func _mark_ready() -> void:
	_server_ready = true
	_starting = false
	_model_catalog_changed = false
	var callbacks := _callbacks.duplicate()
	_callbacks.clear()
	for callback in callbacks:
		callback.call(true)


func _find_free_port() -> int:
	for _i in 30:
		var port := randi_range(4310, 4999)
		var probe := TCPServer.new()
		if probe.listen(port, HOST) == OK:
			probe.stop()
			return port
	return 4310


func _write_pid_file() -> void:
	var file := FileAccess.open(PID_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(str(_pid))
		file.close()


func _kill_stale_server() -> void:
	if not FileAccess.file_exists(PID_PATH):
		return
	var file := FileAccess.open(PID_PATH, FileAccess.READ)
	if file == null:
		return
	var pid := int(file.get_as_text().strip_edges())
	file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PID_PATH))
	if pid <= 0:
		return
	var proc := FileAccess.open("/proc/%d/cmdline" % pid, FileAccess.READ)
	if proc == null:
		return
	var cmdline := proc.get_as_text()
	proc.close()
	if cmdline.contains("opencode") and cmdline.contains("serve"):
		OS.kill(pid)
