@tool
extends EditorPlugin

const KeyboardActions = preload("res://addons/nildevgames_directional_movement_2d/internals/keyboard_actions_2d.gd")

func _enter_tree() -> void:
	if KeyboardActions.set_missing_default_project_actions():
		var save_error := ProjectSettings.save()
		if save_error != OK:
			push_error("Failed to save default NilDevGames keyboard actions to project settings.")
	print(&"NilDevGames Directional Movement 2D plugin loaded.")

func _exit_tree() -> void:
	print(&"NilDevGames Directional Movement 2D plugin unloaded.")
