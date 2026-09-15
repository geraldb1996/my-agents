extends Node

var _lines: Array[String] = []


func _ready() -> void:
	EventBus.agent_output.connect(func(_id: String, line: String) -> void: _lines.append(line))
	var error_line := 'timestamp=2026-09-11T17:57:53.173Z level=ERROR run=cae3d3f3 message="stream error" providerID=opencode modelID=big-pickle error.error="AI_APICallError: Rate limit exceeded. Please try again later."'
	var info_line := 'timestamp=2026-09-11T18:07:13.437Z level=INFO run=2dfb8fb7 message="creating instance" directory=/tmp/opencode/probe'
	AgentManager._handle_stderr("test_agent", error_line)
	AgentManager._handle_stderr("test_agent", info_line)
	print("[ERRTEST] emitted=", _lines)
	print("[ERRTEST] last_error=", AgentManager._last_error.get("test_agent", ""))
	get_tree().quit()
