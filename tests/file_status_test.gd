extends Node

var _ok := true
var _part_id := 0
var _runner: OpenCodeRunner
const AGENT_ID := "file_status_test"
const PROJECT := "/tmp/opencode/file-status-project"


func _ready() -> void:
	var profile := AgentProfile.new()
	profile.id = AGENT_ID
	profile.project = PROJECT
	ProfileStore.profiles[AGENT_ID] = profile
	var panel: WorkspacePanel = load("res://scenes/ui/workspace_panel.tscn").instantiate()
	add_child(panel)
	panel._current_id = AGENT_ID
	_runner = OpenCodeRunner.new()
	add_child(_runner)
	_runner.agent_id = AGENT_ID
	_runner.session_id = "ses_files"
	_runner.event_received.connect(func(agent_id: String, event: Dictionary):
		AgentManager._handle_tool(agent_id, event["part"]))

	_emit_tool("read", {"filePath": PROJECT + "/changed.gd"})
	_emit_tool("apply_patch", {"patchText": "*** Begin Patch\n*** Update File: changed.gd\n@@\n-old\n+new\n*** Add File: created.gd\n+new\n*** Delete File: deleted.gd\n*** Update File: old name.gd\n*** Move to: new name.gd\n@@\n-old\n+new\n*** End Patch"})
	_emit_tool("read", {"filePath": PROJECT + "/changed.gd"})
	_emit_tool("edit", {"filePath": "./created.gd"})
	_emit_tool("read", {"filePath": "created.gd"})
	_emit_tool("read", {"filePath": "read-only.gd"})
	_expect("changed.gd", "M")
	_expect("created.gd", "C")
	_expect("deleted.gd", "D")
	_expect("old name.gd", "D")
	_expect("new name.gd", "C")
	_expect("read-only.gd", "R")
	_check(AgentManager.get_file_status(AGENT_ID).size() == 6, "Relative and absolute paths should share one entry")
	for op in ["C", "R", "D", "M"]:
		_check(panel.files_label.text.contains("(" + op + ")"), "Missing UI marker " + op)

	_emit_tool("apply_patch", {"patchText": "*** Begin Patch\n*** Add File: failed.gd\n+bad\n*** End Patch"}, "error")
	_emit_tool("apply_patch", {"patchText": "*** Begin Patch\n*** Add File: pending.gd\n+pending\n*** End Patch"}, "running")
	_check(AgentManager.get_file_status(AGENT_ID).size() == 6, "Failed or running tools must not record changes")
	_emit_tool("write", {"filePath": "write-new.gd"}, "completed", {"exists": false})
	_emit_tool("write", {"filePath": "write-existing.gd"}, "completed", {"exists": true})
	_emit_tool("multi_edit", {"filePath": "multi.gd", "edits": [{"oldString": "a", "newString": "b"}]})
	_emit_tool("patch", {"edits": [{"filePath": "legacy.gd"}]})
	_expect("write-new.gd", "C")
	_expect("write-existing.gd", "M")
	_expect("multi.gd", "M")
	_expect("legacy.gd", "M")
	_emit_tool("apply_patch", {"patchText": "*** Begin Patch\n*** Delete File: created.gd\n*** End Patch"})
	_expect("created.gd", "D")
	_emit_tool("apply_patch", {"patchText": "*** Begin Patch\n*** Add File: created.gd\n+restored\n*** End Patch"})
	_expect("created.gd", "C")
	_check(AgentManager._git_refresh_queue.has(AGENT_ID), "Mutating tools should queue Git refresh")
	ProfileStore.profiles.erase(AGENT_ID)
	print("[FILETEST] RESULT=", "PASS" if _ok else "FAIL")
	get_tree().quit(0 if _ok else 1)


func _emit_tool(tool: String, input: Dictionary, status: String = "completed", metadata: Dictionary = {}) -> void:
	_part_id += 1
	_runner._handle_sse_event({"type": "message.part.updated", "properties": {
		"sessionID": "ses_files", "part": {
			"id": "file_part_%d" % _part_id, "sessionID": "ses_files", "type": "tool", "tool": tool,
			"state": {"status": status, "input": input, "metadata": metadata},
		},
	}})


func _expect(path: String, expected: String) -> void:
	var actual := str(AgentManager.get_file_status(AGENT_ID).get(PROJECT.path_join(path), ""))
	_check(actual == expected, "%s: expected %s, got %s" % [path, expected, actual])


func _check(condition: bool, message: String) -> void:
	if not condition:
		_ok = false
		print("[FILETEST] ", message)
