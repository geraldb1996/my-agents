extends Node


func _ready() -> void:
	var scene: PackedScene = load("res://scenes/main/main.tscn")
	var main := scene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var dialog := main.get_node_or_null("AgentRequestDialog") as AgentRequestDialog
	var ok := dialog != null and not dialog.visible
	print("[MAINTEST] dialog=", dialog != null, " visible=", dialog.visible if dialog != null else false)
	print("[MAINTEST] RESULT=", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
