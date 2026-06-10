extends Node2D

@export var loot_enabled: bool = true
@export var marker_paths: Array[NodePath] = [
	NodePath("Marker2D"),
	NodePath("Marker2D2")
]
@export var item_spawner_group: StringName = &"item_spawner_network"


func _ready() -> void:
	if Engine.is_editor_hint() or not loot_enabled:
		return
	call_deferred("_spawn_loot_if_needed")


func _spawn_loot_if_needed() -> void:
	var marker := _pick_loot_marker()
	if marker == null:
		return

	var item_spawner := _find_item_spawner()
	if item_spawner == null or not item_spawner.has_method("spawn_random_world_pickup_at_position"):
		return

	item_spawner.call(
		"spawn_random_world_pickup_at_position",
		marker.global_position,
		_build_loot_runtime_id()
	)


func _pick_loot_marker() -> Marker2D:
	var markers := _collect_loot_markers()
	if markers.is_empty():
		return null
	if markers.size() == 1:
		return markers[0]

	var stable_hash := hash(_build_loot_seed_key())
	if stable_hash < 0:
		stable_hash = -stable_hash
	return markers[stable_hash % markers.size()]


func _collect_loot_markers() -> Array[Marker2D]:
	var markers: Array[Marker2D] = []
	for marker_path in marker_paths:
		if marker_path == NodePath(""):
			continue
		var marker := get_node_or_null(marker_path) as Marker2D
		if marker != null and not markers.has(marker):
			markers.append(marker)

	if not markers.is_empty():
		return markers

	for child in get_children():
		if child is Marker2D:
			markers.append(child as Marker2D)
	return markers


func _find_item_spawner() -> Node:
	var scene_tree := get_tree()
	if scene_tree == null:
		return null
	for candidate in scene_tree.get_nodes_in_group(item_spawner_group):
		var node := candidate as Node
		if node != null and is_instance_valid(node):
			return node
	return null


func _build_loot_runtime_id() -> String:
	return "%s:loot" % _build_loot_seed_key()


func _build_loot_seed_key() -> String:
	if has_meta("world_generation_id"):
		return str(get_meta("world_generation_id"))
	return "%s:%.0f:%.0f" % [scene_file_path, global_position.x, global_position.y]
