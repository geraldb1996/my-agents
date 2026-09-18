extends Node

const CONFIG_PATH := "user://remote_chat.cfg"
const API_PREFIX := "/api/remote-chat/v1"
const MAX_BODY_BYTES := 8192
const MAX_REQUEST_BYTES := 9216
const DEFAULT_PORT := 38471

var enabled := false
var port := DEFAULT_PORT
var access_url := ""
var _token := ""
var _server := TCPServer.new()
var _clients: Array[Dictionary] = []
var _submissions: Dictionary = {}
var _rate_limits: Dictionary = {}


func _ready() -> void:
	_load_config()
	if enabled:
		start()


func _exit_tree() -> void:
	stop()


func configure(is_enabled: bool, requested_port: int = DEFAULT_PORT) -> Error:
	enabled = is_enabled
	port = clampi(requested_port, 1024, 65535)
	if _token.is_empty():
		_token = Crypto.new().generate_random_bytes(32).hex_encode()
	_save_config()
	if enabled:
		return start()
	stop()
	return OK


func regenerate_token() -> String:
	_token = Crypto.new().generate_random_bytes(32).hex_encode()
	_save_config()
	return _token


func get_token() -> String:
	if _token.is_empty():
		_token = Crypto.new().generate_random_bytes(32).hex_encode()
		_save_config()
	return _token


func set_access_url(value: String) -> void:
	access_url = value.strip_edges().trim_suffix("/")
	_save_config()


func start() -> Error:
	if _server.is_listening():
		return OK
	if _token.is_empty():
		get_token()
	var err := _server.listen(port, "127.0.0.1")
	if err != OK:
		push_warning("Remote Chat could not bind loopback port %s: %s" % [port, error_string(err)])
	return err


func stop() -> void:
	for client in _clients:
		(client.peer as StreamPeerTCP).disconnect_from_host()
	_clients.clear()
	if _server.is_listening():
		_server.stop()


func _process(_delta: float) -> void:
	while _server.is_listening() and _server.is_connection_available():
		_clients.append({"peer": _server.take_connection(), "buffer": ""})
	for index in range(_clients.size() - 1, -1, -1):
		var client: Dictionary = _clients[index]
		var peer: StreamPeerTCP = client.peer
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.remove_at(index)
			continue
		var available := peer.get_available_bytes()
		if available > 0:
			var received := peer.get_data(available)
			if received[0] == OK:
				client.buffer += (received[1] as PackedByteArray).get_string_from_utf8()
		if client.buffer.length() > MAX_REQUEST_BYTES:
			_send(peer, 413, {"error": "payload_too_large"})
			_clients.remove_at(index)
			continue
		var parsed := _parse_request(client.buffer)
		if not parsed.is_empty():
			_handle_request(peer, parsed)
			_clients.remove_at(index)


func _parse_request(raw: String) -> Dictionary:
	var separator := raw.find("\r\n\r\n")
	if separator < 0:
		return {}
	var lines := raw.substr(0, separator).split("\r\n")
	if lines.is_empty():
		return {"invalid": true}
	var request_parts := lines[0].split(" ")
	if request_parts.size() != 3:
		return {"invalid": true}
	var headers := {}
	for index in range(1, lines.size()):
		var header := lines[index]
		var colon := header.find(":")
		if colon > 0:
			headers[header.substr(0, colon).to_lower()] = header.substr(colon + 1).strip_edges()
	var length := int(headers.get("content-length", "0"))
	if length < 0 or length > MAX_BODY_BYTES:
		return {"oversized": true}
	var body := raw.substr(separator + 4)
	if body.to_utf8_buffer().size() < length:
		return {}
	return {"method": request_parts[0], "path": request_parts[1], "headers": headers, "body": body.substr(0, length)}


func _handle_request(peer: StreamPeerTCP, request: Dictionary) -> void:
	if request.has("oversized"):
		_send(peer, 413, {"error": "payload_too_large"})
		return
	if request.has("invalid"):
		_send(peer, 400, {"error": "bad_request"})
		return
	var raw_path := str(request.path)
	var query_at := raw_path.find("?")
	var path := raw_path.substr(0, query_at) if query_at >= 0 else raw_path
	if request.method == "GET" and _send_pwa_asset(peer, path):
		return
	var headers: Dictionary = request.headers
	var host := peer.get_connected_host()
	if str(headers.get("authorization", "")) != "Bearer " + _token:
		if not _allow(host + ":auth", 5):
			_send(peer, 429, {"error": "rate_limited"})
		else:
			_send(peer, 401, {"error": "unauthorized"})
		return
	if path == API_PREFIX + "/health" and request.method == "GET":
		_send(peer, 200, {"ok": true, "version": "v1"})
		return
	if path == API_PREFIX + "/agents" and request.method == "GET":
		_send(peer, 200, {"agents": _remote_agents()})
		return
	if path == API_PREFIX + "/requests" and request.method == "GET":
		_send(peer, 200, {"requests": AgentManager.get_pending_remote_requests()})
		return
	if path == API_PREFIX + "/requests/respond" and request.method == "POST":
		if not str(headers.get("content-type", "")).to_lower().begins_with("application/json"):
			_send(peer, 400, {"error": "bad_request"})
			return
		if not _allow(host + ":response", 20):
			_send(peer, 429, {"error": "rate_limited"})
			return
		var response_payload = JSON.parse_string(request.body)
		if not response_payload is Dictionary:
			_send(peer, 400, {"error": "bad_request"})
			return
		var response_result := AgentManager.respond_remote_request(response_payload)
		if bool(response_result.get("ok", false)):
			_send(peer, 200, response_result)
		elif str(response_result.get("error", "")) == "stale_request":
			_send(peer, 409, response_result)
		elif str(response_result.get("error", "")) == "unavailable":
			_send(peer, 503, response_result)
		else:
			_send(peer, 400, response_result)
		return
	if path.begins_with(API_PREFIX + "/avatars/") and request.method == "GET":
		var agent_id := path.trim_prefix(API_PREFIX + "/avatars/")
		if not _send_agent_avatar(peer, agent_id):
			_send(peer, 404, {"error": "not_found"})
		return
	if path == API_PREFIX + "/messages" and request.method == "GET":
		var query := raw_path.substr(query_at + 1) if query_at >= 0 else ""
		var after := ""
		var limit := 100
		for item in query.split("&"):
			var pair := item.split("=", false, 1)
			if pair.size() == 2 and pair[0] == "after": after = pair[1].uri_decode()
			if pair.size() == 2 and pair[0] == "limit": limit = int(pair[1])
		_send(peer, 200, AgentManager.get_chat_messages(after, limit))
		return
	if path == API_PREFIX + "/messages" and request.method == "POST":
		if not str(headers.get("content-type", "")).to_lower().begins_with("application/json"):
			_send(peer, 400, {"error": "bad_request"})
			return
		if not _allow(host + ":message", 20):
			_send(peer, 429, {"error": "rate_limited"})
			return
		var payload = JSON.parse_string(request.body)
		if not payload is Dictionary:
			_send(peer, 400, {"error": "bad_request"})
			return
		var content := str(payload.get("content", "")).strip_edges()
		var client_message_id := str(payload.get("client_message_id", ""))
		var target_agent_id := str(payload.get("target_agent_id", ""))
		if content.is_empty() or client_message_id.is_empty():
			_send(peer, 400, {"error": "bad_request"})
			return
		if not target_agent_id.is_empty() and ProfileStore.get_profile(target_agent_id) == null:
			_send(peer, 400, {"error": "bad_request"})
			return
		if _submissions.has(client_message_id):
			_send(peer, 200, _submissions[client_message_id])
			return
		var result := AgentManager.send_user_message(content, target_agent_id)
		if not bool(result.get("accepted", false)):
			_send(peer, 503, {"error": "unavailable"})
			return
		result["target_results"] = result.get("targets", [])
		_submissions[client_message_id] = result
		_send(peer, 201, result)
		return
	_send(peer, 404, {"error": "not_found"})


func _allow(key: String, maximum: int) -> bool:
	var now := Time.get_ticks_msec()
	var entries: Array = _rate_limits.get(key, [])
	var kept: Array = []
	for timestamp in entries:
		if now - int(timestamp) < 60000:
			kept.append(timestamp)
	if kept.size() >= maximum:
		_rate_limits[key] = kept
		return false
	kept.append(now)
	_rate_limits[key] = kept
	return true


func _send(peer: StreamPeerTCP, status: int, payload: Dictionary) -> void:
	var body := JSON.stringify(payload)
	_send_raw(peer, status, "application/json", body, "no-store")


func _send_pwa_asset(peer: StreamPeerTCP, path: String) -> bool:
	var asset_name := "index.html" if path == "/" else path.trim_prefix("/")
	if asset_name not in ["index.html", "app.css", "app.js", "manifest.webmanifest", "service-worker.js"]:
		return false
	var asset_path := "res://remote-chat/" + asset_name
	if not FileAccess.file_exists(asset_path):
		return false
	var file := FileAccess.open(asset_path, FileAccess.READ)
	if file == null:
		return false
	var content := file.get_as_text()
	file.close()
	var content_type := "text/plain"
	if asset_name.ends_with(".html"): content_type = "text/html; charset=utf-8"
	elif asset_name.ends_with(".css"): content_type = "text/css; charset=utf-8"
	elif asset_name.ends_with(".js"): content_type = "application/javascript; charset=utf-8"
	elif asset_name.ends_with(".webmanifest"): content_type = "application/manifest+json"
	_send_raw(peer, 200, content_type, content, "no-cache")
	return true


func _remote_agents() -> Array:
	var agents: Array = []
	for profile_id in ProfileStore.profiles:
		var profile := ProfileStore.get_profile(profile_id)
		if profile == null:
			continue
		agents.append({
			"id": profile.id,
			"name": profile.name,
			"state": AgentManager.get_agent_state(profile.id),
			"avatar_url": API_PREFIX + "/avatars/" + profile.id.uri_encode(),
		})
	return agents


func _send_agent_avatar(peer: StreamPeerTCP, agent_id: String) -> bool:
	var profile := ProfileStore.get_profile(agent_id.uri_decode())
	if profile == null:
		return false
	var image := _idle_image(profile)
	if image == null or image.is_empty():
		return false
	var bytes := image.save_png_to_buffer()
	if bytes.is_empty():
		return false
	_send_bytes(peer, 200, "image/png", bytes, "no-store")
	return true


func _idle_image(profile: AgentProfile) -> Image:
	var spec = profile.animations.get("idle", {})
	if spec is Dictionary:
		var frames = spec.get("frames", [])
		if frames is Array and not frames.is_empty():
			var frame_image := _load_avatar_image(str(frames[0]))
			if frame_image != null:
				return frame_image
		var folder := str(spec.get("folder", ""))
		if not folder.is_empty():
			var dir := DirAccess.open(folder)
			if dir != null:
				var files := dir.get_files()
				files.sort()
				for file_name in files:
					if file_name.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
						var folder_image := _load_avatar_image(folder.path_join(file_name))
						if folder_image != null:
							return folder_image
		var sheet := str(spec.get("sheet", ""))
		if not sheet.is_empty():
			var sheet_image := _load_avatar_image(sheet)
			if sheet_image != null:
				var hf := maxi(1, int(spec.get("hf", 1)))
				var vf := maxi(1, int(spec.get("vf", 1)))
				return sheet_image.get_region(Rect2i(0, 0, sheet_image.get_width() / hf, sheet_image.get_height() / vf))
	return _load_avatar_image("res://images/agents/agent.png")


func _load_avatar_image(path: String) -> Image:
	if path.begins_with("res://"):
		var resource = load(path)
		if resource is Texture2D:
			return (resource as Texture2D).get_image()
	return Image.load_from_file(path)


func _send_raw(peer: StreamPeerTCP, status: int, content_type: String, body: String, cache_control: String) -> void:
	var text := "HTTP/1.1 %s %s\r\nContent-Type: %s\r\nContent-Length: %s\r\nCache-Control: %s\r\nConnection: close\r\n\r\n%s" % [status, _status_text(status), content_type, body.to_utf8_buffer().size(), cache_control, body]
	peer.put_data(text.to_utf8_buffer())
	peer.disconnect_from_host()


func _send_bytes(peer: StreamPeerTCP, status: int, content_type: String, body: PackedByteArray, cache_control: String) -> void:
	var headers := "HTTP/1.1 %s %s\r\nContent-Type: %s\r\nContent-Length: %s\r\nCache-Control: %s\r\nConnection: close\r\n\r\n" % [status, _status_text(status), content_type, body.size(), cache_control]
	peer.put_data(headers.to_utf8_buffer())
	peer.put_data(body)
	peer.disconnect_from_host()


func _status_text(status: int) -> String:
	return {200: "OK", 201: "Created", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 409: "Conflict", 413: "Payload Too Large", 429: "Too Many Requests", 503: "Service Unavailable"}.get(status, "Error")


func _load_config() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	enabled = bool(config.get_value("remote_chat", "enabled", false))
	port = clampi(int(config.get_value("remote_chat", "port", DEFAULT_PORT)), 1024, 65535)
	access_url = str(config.get_value("remote_chat", "access_url", "")).strip_edges().trim_suffix("/")
	_token = str(config.get_value("remote_chat", "token", ""))


func _save_config() -> void:
	var config := ConfigFile.new()
	config.set_value("remote_chat", "enabled", enabled)
	config.set_value("remote_chat", "port", port)
	config.set_value("remote_chat", "access_url", access_url)
	config.set_value("remote_chat", "token", _token)
	config.save(CONFIG_PATH)
