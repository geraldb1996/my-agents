extends Node


func _ready() -> void:
	ProfileStore.profiles.clear()
	ProfileStore._seed_default_profiles()
	var ok := ProfileStore.profiles.size() == 3
	var expected := {
		"ag_default_amy": {"name": "Amy", "model": "opencode/big-pickle"},
		"ag_default_lucy": {"name": "Lucy", "model": "opencode/big-pickle"},
		"ag_default_elliot": {"name": "Elliot", "model": "opencode/big-pickle"},
	}
	for id in expected:
		var p := ProfileStore.get_profile(id)
		if p == null:
			ok = false
			print("[SEEDTEST] missing profile: ", id)
			continue
		if p.name != expected[id]["name"] or p.model != expected[id]["model"]:
			ok = false
			print("[SEEDTEST] wrong config for ", id, ": ", p.name, "/", p.model)
		if not p.skills.is_empty() or not p.project.is_empty() or p.to_dict().has("character"):
			ok = false
			print("[SEEDTEST] non-default field for ", id)
		var avatar := CharacterAvatar.new()
		avatar.set_profile(p)
		var idle_frames: Array = p.animations.get("idle", {}).get("frames", [])
		if idle_frames.size() < 2:
			ok = false
			print("[SEEDTEST] missing idle animation for ", id)
			avatar.free()
			continue
		if avatar.avatar.texture != load(idle_frames[0]):
			ok = false
			print("[SEEDTEST] missing initial idle frame for ", id)
		avatar._process(1.0 / 6.0)
		if avatar.avatar.texture != load(idle_frames[1]):
			ok = false
			print("[SEEDTEST] idle animation did not advance for ", id)
		avatar.set_state("working")
		if avatar.avatar.texture != load(p.animations["working"]["frames"][0]):
			ok = false
			print("[SEEDTEST] working animation not applied immediately for ", id)
		avatar.set_state("offline")
		if avatar.current_state != "idle" or avatar.avatar.texture != load(idle_frames[0]):
			ok = false
			print("[SEEDTEST] missing idle fallback for ", id)
		for state in p.animations:
			var spec: Dictionary = p.animations[state]
			var paths: Array = spec.get("frames", [])
			if paths.is_empty():
				continue
			var textures: Array = avatar._frames.get(state, [])
			if textures.size() != paths.size():
				ok = false
				print("[SEEDTEST] missing exported frames: ", id, "/", state)
				continue
			avatar.set_profile(p)
			avatar.set_state(state)
			for path in paths:
				var expected_texture := ResourceLoader.load(path, "Texture2D") as Texture2D
				if expected_texture == null or avatar.avatar.texture != expected_texture:
					ok = false
					print("[SEEDTEST] animation frame mismatch: ", id, "/", state, ": ", path)
				avatar._process(1.0 / float(spec.get("fps", 8.0)))
			if avatar.avatar.texture != textures[0]:
				ok = false
				print("[SEEDTEST] animation did not loop: ", id, "/", state)
		avatar.set_profile(null)
		if avatar.avatar.texture != load(CharacterAvatar.BASE_TEXTURE):
			ok = false
			print("[SEEDTEST] stale frame after clearing profile for ", id)
		avatar.free()
		if not FileAccess.file_exists("user://agents/%s.json" % id):
			ok = false
			print("[SEEDTEST] file not written for ", id)
	ProfileStore._seed_default_profiles()
	if ProfileStore.profiles.size() != 3:
		ok = false
		print("[SEEDTEST] duplicated on re-seed, size=", ProfileStore.profiles.size())
	print("[SEEDTEST] RESULT=", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
