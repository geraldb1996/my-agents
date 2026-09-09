class_name CharacterView
extends Control

@onready var state_label: Label = %StateLabel
@onready var state_dot: ColorRect = %StateDot
@onready var avatar: CharacterAvatar = %Avatar

var current_state: String = "idle"


func _ready() -> void:
	_apply_state("idle")


func set_profile(p: AgentProfile) -> void:
	if p != null:
		avatar.set_profile(p)
	set_state("idle")


func set_state(state: String) -> void:
	avatar.set_state(state)
	_apply_state(avatar.current_state)


func _apply_state(state: String) -> void:
	var color: Color = CharacterAvatar.STATE_COLORS.get(state, CharacterAvatar.STATE_COLORS["idle"])
	state_dot.color = color
	state_label.text = state.capitalize()