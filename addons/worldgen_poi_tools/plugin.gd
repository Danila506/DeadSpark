@tool
extends EditorPlugin

const MENU_ID := 42061

func _enter_tree() -> void:
	add_tool_menu_item("Assign Missing Stable IDs", _assign_missing_ids)

func _exit_tree() -> void:
	remove_tool_menu_item("Assign Missing Stable IDs")

func _assign_missing_ids() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null: return
	WorldGenStableIdAssignment.assign_missing(root)
	root.owner = root
	get_editor_interface().mark_scene_as_unsaved()
