@tool
extends EditorPlugin

## Editor entry point for GameSpice Anticheat. No autoloads: the server owns its watch node.


func _enter_tree() -> void:
	add_custom_type("DotSuspicionWatch", "Node", load("res://addons/dot_anticheat/runtime/dot_suspicion_watch.gd"), null)


func _exit_tree() -> void:
	remove_custom_type("DotSuspicionWatch")
