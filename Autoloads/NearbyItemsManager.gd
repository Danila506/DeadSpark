extends Node

signal nearby_items_changed

var nearby_items: Array = []


func add_item(world_item: Node) -> void:
	if world_item == null:
		return

	if nearby_items.has(world_item):
		return

	nearby_items.append(world_item)
	_cleanup()
	nearby_items_changed.emit()


func remove_item(world_item: Node) -> void:
	if world_item == null:
		return

	if nearby_items.has(world_item):
		nearby_items.erase(world_item)
		_cleanup()
		nearby_items_changed.emit()


func get_items() -> Array:
	_cleanup()
	return nearby_items


func _cleanup() -> void:
	nearby_items = nearby_items.filter(func(item): return is_instance_valid(item))
