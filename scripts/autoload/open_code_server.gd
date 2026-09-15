extends Node

const HOST := "127.0.0.1"
const PID_PATH := "user://opencode_server.pid"
const START_TIMEOUT_MS := 20000
const PROBE_INTERVAL_MS := 300

var _pid: int = -1
var _port: int = 0
var _starting: bool = false
var _server_ready: bool = false
var _started_at_ms: int = 0
var _probe_at_ms: int = 0
var _callbacks: Array[Callable] = []


func _ready() -> void:
	_kill_stale_server()


func _exit_tree() -> void:
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


func ensure_ready(callback: Callable) -> void:
	if is_ready():
		callback.call(true)
		return
	if not _callbacks.has(callback):
		_callbacks.append(callback)
	if not _starting:
		_start_server()


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
	if request.request(base_url() + path, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
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
		var request := HTTPRequest.new()
		request.timeout = 20.0
		add_child(request)
		request.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, data: PackedByteArray) -> void:
			request.queue_free()
			if callback.is_valid():
				callback.call(code, JSON.parse_string(data.get_string_from_utf8()))
		)
		var path := "/agent"
		var expanded := directory
		if expanded.begins_with("~"):
			expanded = OS.get_environment("HOME").path_join(expanded.substr(1).trim_prefix("/"))
		if not expanded.is_empty():
			path += "?directory=" + expanded.uri_encode()
		if request.request(base_url() + path) != OK:
			request.queue_free()
			if callback.is_valid():
				callback.call(0, null)
	)


func stop_server() -> void:
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1
	_server_ready = false
	_starting = false
	_callbacks.clear()
	if FileAccess.file_exists(PID_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PID_PATH))


func _start_server() -> void:
	_starting = true
	_server_ready = false
	_port = _find_free_port()
	_pid = OS.create_process("opencode", ["serve", "--hostname", HOST, "--port", str(_port)], false)
	if _pid <= 0:
		_fail_callbacks()
		return
	_write_pid_file()
	_started_at_ms = Time.get_ticks_msec()
	_probe_at_ms = 0


func _fail_callbacks() -> void:
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
	request.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
		request.queue_free()
		if code == 200 and not _server_ready:
			_mark_ready()
	)
	if request.request(base_url() + "/global/health") != OK:
		request.queue_free()


func _mark_ready() -> void:
	_server_ready = true
	_starting = false
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
