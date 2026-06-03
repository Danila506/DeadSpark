extends Node2D

var controller: Node


func set_active(is_active: bool) -> void:
	if is_active:
		if not is_in_group("primary_interactable"):
			add_to_group("primary_interactable")
	else:
		if is_in_group("primary_interactable"):
			remove_from_group("primary_interactable")


func handle_primary_interaction(interactor: Node) -> bool:
	if controller == null or not is_instance_valid(controller):
		return false
	if not controller.has_method("handle_primary_interaction"):
		return false
	return bool(controller.call("handle_primary_interaction", interactor))
