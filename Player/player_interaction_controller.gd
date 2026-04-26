extends RefCounted
class_name PlayerInteractionController

var player


func _init(owner) -> void:
	player = owner


func trigger_primary_interaction() -> bool:
	return _trigger_interaction(&"primary_interactable", "handle_primary_interaction")


func trigger_secondary_interaction() -> bool:
	return _trigger_interaction(&"secondary_interactable", "handle_secondary_interaction")


func _trigger_interaction(group_name: StringName, handler_name: String) -> bool:
	if player == null:
		return false

	var player_position: Vector2 = player.global_position
	var best_target: Node = null
	var best_distance: float = INF

	for node in player.get_tree().get_nodes_in_group(group_name):
		if node == null or not is_instance_valid(node):
			continue
		if not node.has_method(handler_name):
			continue
		if not (node is Node2D):
			continue

		var distance: float = player_position.distance_to((node as Node2D).global_position)
		if distance < best_distance:
			best_distance = distance
			best_target = node

	if best_target == null:
		return false

	return bool(best_target.call(handler_name, player))
