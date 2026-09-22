extends Node2D
class_name VillageSpawnGroup

const GENERATED_GROUP: StringName = &"generated_village_object"

@export var spawn_profile: VillageSpawnProfile
@export var group_id := ""


func get_spawn_markers() -> Array[Marker2D]:
	var markers: Array[Marker2D] = []
	_collect_spawn_markers(self, markers)
	return markers


func _collect_spawn_markers(node: Node, markers: Array[Marker2D]) -> void:
	for child in node.get_children():
		if child.is_queued_for_deletion() or child.is_in_group(GENERATED_GROUP):
			continue
		if child is Marker2D:
			markers.append(child as Marker2D)
		_collect_spawn_markers(child, markers)
