class_name CharacterView
extends Control

const STATE_COLORS := {
	"idle": Color(1, 1, 1),
	"thinking": Color(1, 0.85, 0.3),
	"working": Color(1, 0.62, 0.2),
	"reading": Color(0.42, 0.8, 1),
	"coding": Color(0.3, 1, 0.5),
	"terminal": Color(0.75, 0.5, 1),
	"searching": Color(0.35, 0.62, 1),
	"waiting": Color(0.72, 0.72, 0.72),
	"question": Color(1, 0.75, 0.3),
	"approval": Color(1, 0.52, 0.2),
	"error": Color(1, 0.25, 0.25),
	"success": Color(0.3, 1, 0.42),
	"offline": Color(0.42, 0.42, 0.48),
}

const STATE_PARAMS := {
	"idle": {"speed": 0.8, "bob": 0.02, "tilt": 0.0, "pulse": 0.0},
	"thinking": {"speed": 1.1, "bob": 0.035, "tilt": 0.05, "pulse": 0.02},
	"working": {"speed": 2.2, "bob": 0.055, "tilt": 0.0, "pulse": 0.03},
	"reading": {"speed": 1.4, "bob": 0.03, "tilt": 0.03, "pulse": 0.0},
	"coding": {"speed": 3.0, "bob": 0.06, "tilt": 0.02, "pulse": 0.04},
	"terminal": {"speed": 2.0, "bob": 0.05, "tilt": 0.04, "pulse": 0.02},
	"searching": {"speed": 2.6, "bob": 0.03, "tilt": 0.06, "pulse": 0.02},
	"waiting": {"speed": 0.5, "bob": 0.012, "tilt": 0.0, "pulse": 0.0},
	"question": {"speed": 1.8, "bob": 0.03, "tilt": 0.09, "pulse": 0.02},
	"approval": {"speed": 1.8, "bob": 0.03, "tilt": 0.09, "pulse": 0.02},
	"error": {"speed": 4.0, "bob": 0.03, "tilt": 0.0, "pulse": 0.08},
	"success": {"speed": 3.5, "bob": 0.07, "tilt": 0.0, "pulse": 0.05},
	"offline": {"speed": 0.0, "bob": 0.0, "tilt": 0.0, "pulse": 0.0},
}

const FALLBACKS := {
	"coding": "working",
	"terminal": "working",
	"reading": "thinking",
	"searching": "thinking",
	"question": "approval",
}

const BASE_TEXTURE := "res://images/agents/agent.png"

@onready var avatar: TextureRect = %Avatar
@onready var state_label: Label = %StateLabel
@onready var state_dot: ColorRect = %StateDot

var profile: AgentProfile
var current_state: String = "idle"

var _time: float = 0.0
var _frames: Dictionary = {}
var _frame_index: int = 0
var _frame_timer: float = 0.0


func _ready() -> void:
	avatar.texture = _load_texture(BASE_TEXTURE)
	avatar.pivot_offset = avatar.size / 2.0
	_apply_state("idle")


func set_profile(p: AgentProfile) -> void:
	profile = p
	_frames.clear()
	if p != null:
		var path := p.character
		if path.is_empty():
			path = BASE_TEXTURE
		avatar.texture = _load_texture(path)
		_prepare_custom_frames()
	set_state("idle")


func set_state(state: String) -> void:
	var resolved := _resolve_state(state)
	if resolved != current_state:
		_frame_index = 0
		_frame_timer = 0.0
		current_state = resolved
	_apply_state(resolved)


func _resolve_state(state: String) -> String:
	var s := state if STATE_PARAMS.has(state) else "idle"
	if _frames.has(s):
		return s
	if FALLBACKS.has(s) and _frames.has(FALLBACKS[s]):
		return FALLBACKS[s]
	if s != "idle" and _frames.has("idle"):
		return "idle"
	return s


func _process(delta: float) -> void:
	_time += delta
	var anim_frames: Array = _frames.get(current_state, [])
	if not anim_frames.is_empty():
		_frame_timer += delta
		var fps: float = _get_anim_fps(current_state)
		if fps > 0.0 and _frame_timer >= 1.0 / fps:
			_frame_timer = 0.0
			_frame_index = (_frame_index + 1) % anim_frames.size()
		if _frame_index < anim_frames.size():
			avatar.texture = anim_frames[_frame_index]
		return

	var params: Dictionary = STATE_PARAMS.get(current_state, STATE_PARAMS["idle"])
	var speed: float = params.get("speed", 0.8)
	var bob: float = params.get("bob", 0.0)
	var tilt: float = params.get("tilt", 0.0)
	var pulse: float = params.get("pulse", 0.0)
	var s := sin(_time * speed)

	avatar.position.y = avatar.size.y * bob * s
	avatar.rotation = tilt * sin(_time * speed * 0.7)
	var scale := 1.0 + pulse * s
	avatar.scale = Vector2(scale, scale)


func _apply_state(state: String) -> void:
	var color: Color = STATE_COLORS.get(state, STATE_COLORS["idle"])
	state_dot.color = color
	if state == "offline":
		avatar.modulate = Color(0.55, 0.55, 0.6, 0.85)
	else:
		avatar.modulate = color.lerp(Color(1, 1, 1), 0.65)
	state_label.text = state.capitalize()


func _prepare_custom_frames() -> void:
	if profile == null or profile.animations.is_empty():
		return
	for state in profile.animations:
		var spec: Dictionary = profile.animations[state]
		if spec is not Dictionary:
			continue
		if spec.has("frames") and spec["frames"] is Array:
			var list: Array[Texture2D] = []
			for path in spec["frames"]:
				var tex := _load_texture(str(path))
				if tex != null:
					list.append(tex)
			if not list.is_empty():
				_frames[state] = list
		elif spec.has("folder"):
			var folder := str(spec["folder"])
			var dir := DirAccess.open(folder)
			if dir != null:
				var list3: Array[Texture2D] = []
				var files := dir.get_files()
				files.sort()
				for f in files:
					if f.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
						var tex := _load_texture(folder.path_join(f))
						if tex != null:
							list3.append(tex)
				if not list3.is_empty():
					_frames[state] = list3
		elif spec.has("sheet"):
			var sheet := _load_texture(str(spec["sheet"]))
			if sheet != null:
				var hf := int(spec.get("hf", 1))
				var vf := int(spec.get("vf", 1))
				var count := int(spec.get("count", hf * vf))
				var list2: Array[Texture2D] = []
				for i in count:
					var col := i % hf
					var row := i / hf
					if row >= vf:
						break
					var atlas := AtlasTexture.new()
					atlas.atlas = sheet
					atlas.region = Rect2(col * 256, row * 256, 256, 256)
					list2.append(atlas)
				if not list2.is_empty():
					_frames[state] = list2


func _get_anim_fps(state: String) -> float:
	var spec: Dictionary = profile.animations.get(state, {}) if profile != null else {}
	return float(spec.get("fps", 8.0))


func _load_texture(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		push_warning("Texture not found: %s" % path)
		return null
	var tex := load(path) as Texture2D
	return tex