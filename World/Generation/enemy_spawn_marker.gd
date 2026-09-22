class_name EnemySpawnMarker
extends Node2D

@export var stable_marker_id := ""
@export var marker_tags: Array[String] = ["guard"]
@export var enabled_for_population := true
@export_range(0, 16, 1) var capacity := 1

func to_population_record() -> EnemySpawnMarkerRecord:
	var record := EnemySpawnMarkerRecord.new()
	record.marker_id = stable_marker_id.strip_edges()
	record.position = global_position
	record.tags = marker_tags.duplicate()
	record.enabled = enabled_for_population
	record.capacity = capacity
	return record
