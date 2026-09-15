extends Node

var _got_code := 999


func _ready() -> void:
	var profile := AgentProfile.new()
	profile.ensure_id()
	profile.name = "StallBot"
	profile.project = "/tmp/opencode/ui-probe"
	ProfileStore.save_profile(profile)
	AgentManager.get_session(profile.id)

	AgentManager.set_state(profile.id, "thinking")
	var runner := OpenCodeRunner.new()
	runner.agent_id = profile.id
	runner.name = "StallRunner"
	add_child(runner)
	runner.stall_timeout_ms = 400
	runner._last_activity_ms = Time.get_ticks_msec()
	runner.running = true
	runner.process_finished.connect(func(_id: String, code: int) -> void: _got_code = code)
	runner.process_finished.connect(AgentManager._on_process_finished)

	await get_tree().create_timer(0.8).timeout
	runner.poll()
	await get_tree().process_frame
	print("[STALLTEST] exit_code=", _got_code, " (expect -2)")
	print("[STALLTEST] state_after_stall=", AgentManager.get_session(profile.id).get("state"), " (expect error)")

	AgentManager.set_state(profile.id, "thinking")
	AgentManager._on_process_finished(profile.id, 0)
	await get_tree().process_frame
	print("[STALLTEST] state_after_clean_exit_no_stop=", AgentManager.get_session(profile.id).get("state"), " (expect idle)")
	ProfileStore.delete_profile(profile.id)
	get_tree().quit()
