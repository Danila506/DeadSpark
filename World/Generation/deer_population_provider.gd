class_name DeerPopulationProvider
extends Node2D

const DeerPersistence = preload("res://World/Generation/enemy_population_persistence.gd")

@export var world_generated_mode := true
@export var world_id := "default"
@export var region_id := "finite_00"
@export var population_profile: EnemyPopulationProfile
@export var candidate_positions: Array[Vector2] = [Vector2(-720, -480), Vector2(-480, -240), Vector2(480, -240), Vector2(720, 360)]
@export var candidate_tags: Array[String] = ["wildlife", "forest", "land"]
@export var candidate_capacity := 1
@export var occupancy_cell_size := Vector2(60.0, 60.0)

## Read-only production context supplied by PoiPlacementPass/EnvironmentGenerationPass.
var geography_occupancy: WorldOccupancyMap
var _exclusion_diagnostics: Array[Dictionary] = []

var applied_population_manifest: EnemyPopulationManifest
var _population_states: Dictionary = {}


func get_enemy_population_owner_id() -> String:
	if not world_generated_mode or world_id.strip_edges().is_empty() or region_id.strip_edges().is_empty():
		return ""
	return "world/%s/wildlife/deer/%s" % [world_id.strip_edges(), region_id.strip_edges()]


func get_enemy_population_profile() -> EnemyPopulationProfile:
	return population_profile


func get_enemy_spawn_markers() -> Array:
	var records: Array[EnemySpawnMarkerRecord] = []
	_exclusion_diagnostics.clear()
	for index in range(candidate_positions.size()):
		var marker := EnemySpawnMarkerRecord.new()
		marker.marker_id = "candidate_%02d" % index
		marker.position = candidate_positions[index]
		marker.tags = candidate_tags.duplicate()
		var reason := _candidate_exclusion_reason(marker.position)
		marker.enabled = candidate_capacity > 0 and reason.is_empty()
		marker.capacity = candidate_capacity
		marker.exclusion_flags = ["road", "road_clearance", "water", "poi", "environment_footprint"]
		records.append(marker)
		if not reason.is_empty(): _exclusion_diagnostics.append({"candidate_id": marker.marker_id, "reason": reason})
	records.sort_custom(func(a, b): return a.marker_id < b.marker_id)
	_exclusion_diagnostics.sort_custom(func(a, b): return String(a.candidate_id) < String(b.candidate_id))
	return records


func set_geography_context(occupancy: WorldOccupancyMap) -> void:
	geography_occupancy = occupancy


func get_exclusion_diagnostics() -> Array[Dictionary]:
	return _exclusion_diagnostics.duplicate(true)


func _candidate_exclusion_reason(position: Vector2) -> String:
	if not is_finite(position.x) or not is_finite(position.y): return "invalid_position"
	if geography_occupancy == null: return ""
	var cell := Vector2i(floori(position.x / maxf(occupancy_cell_size.x, 1.0)), floori(position.y / maxf(occupancy_cell_size.y, 1.0)))
	if not geography_occupancy.bounds.has_point(cell): return "out_of_bounds"
	for pair in [[WorldOccupancyMap.ROAD, "road"], [WorldOccupancyMap.ROAD_CLEARANCE, "road_clearance"], [WorldOccupancyMap.WATER, "water"], [WorldOccupancyMap.POI | WorldOccupancyMap.BUILDING, "poi_footprint"], [WorldOccupancyMap.STATIC_PROP | WorldOccupancyMap.NO_SPAWN, "environment_footprint"], [WorldOccupancyMap.INTERACTIVE_OBJECT, "occupied"]]:
		if geography_occupancy.has_flags([cell], int(pair[0])): return String(pair[1])
	return ""


func apply_enemy_population_manifest(manifest: EnemyPopulationManifest) -> Dictionary:
	if not world_generated_mode:
		return {"valid": false, "errors": ["NOT_WORLD_GENERATED_DEER_PROVIDER"]}
	if manifest == null or manifest.owner_generated_object_id != get_enemy_population_owner_id() or population_profile == null or manifest.profile_id != population_profile.profile_id:
		return {"valid": false, "errors": ["MANIFEST_OWNER_OR_PROFILE_MISMATCH"]}
	if applied_population_manifest != null:
		return {"valid": applied_population_manifest.manifest_hash() == manifest.manifest_hash(), "errors": [] if applied_population_manifest.manifest_hash() == manifest.manifest_hash() else ["CONFLICTING_POPULATION_MANIFEST"]}
	var markers := {}
	for marker in get_enemy_spawn_markers(): markers[marker.marker_id] = true
	for record in manifest.records:
		if not markers.has(record.marker_id) or _population_states.has(record.population_id): return {"valid": false, "errors": ["DUPLICATE_POPULATION_ID_OR_UNKNOWN_MARKER"]}
		var scene := load(record.enemy_resource_key) as PackedScene
		if scene == null: return {"valid": false, "errors": ["MISSING_DEER_SCENE"]}
		var deer := scene.instantiate() as Node2D
		if deer == null: return {"valid": false, "errors": ["INVALID_DEER_SCENE"]}
		deer.global_position = record.position
		_set_population_metadata(deer, record, manifest)
		_population_states[record.population_id] = "alive"
		add_child(deer)
	applied_population_manifest = manifest
	return {"valid": true, "errors": []}


func _set_population_metadata(deer: Node2D, record: EnemyPopulationRecord, manifest: EnemyPopulationManifest) -> void:
	deer.set_meta("population_id", record.population_id)
	deer.set_meta("population_owner_id", record.owner_generated_object_id)
	deer.set_meta("population_marker_id", record.marker_id)
	deer.set_meta("population_entry_id", record.enemy_entry_id)
	deer.set_meta("population_manifest_hash", manifest.manifest_hash())
	deer.set_meta("population_state", "alive")
	deer.add_to_group("deer_generated_population")
	deer.add_to_group("generated_world_object")
	deer.set_meta("world_generation_id", record.population_id)
	deer.set_meta("world_generation_scene_path", record.enemy_resource_key)
	deer.set_multiplayer_authority(1)
	if deer.has_signal("died"):
		deer.died.connect(func(_deer): mark_population_killed(record.population_id))


func clear_enemy_population() -> void:
	for child in get_children():
		if child.is_in_group("deer_generated_population"): child.queue_free()
	applied_population_manifest = null
	_population_states.clear()


func get_population_states() -> Dictionary: return _population_states.duplicate(true)
func get_population_persistence_key() -> String: return DeerPersistence.get_persistence_key(get_enemy_population_owner_id())
func serialize_population_state() -> Dictionary: return DeerPersistence.serialize_camp(self)
func restore_population_state(data: Dictionary) -> Dictionary: return DeerPersistence.restore_camp(self, data)
func mark_population_killed(population_id: String) -> Dictionary: return _mark_population_state(population_id, "killed")
func mark_population_despawned(population_id: String) -> Dictionary: return _mark_population_state(population_id, "despawned")
func _mark_population_state(population_id: String, state: String) -> Dictionary:
	if applied_population_manifest == null or not _population_states.has(population_id): return {"valid": false, "errors": ["UNKNOWN_POPULATION_ID"]}
	_population_states[population_id] = state
	if state == "despawned":
		for child in get_children(): if child.get_meta("population_id", "") == population_id: child.queue_free()
	return {"valid": true, "errors": []}


func restore_persisted_population_state(manifest: EnemyPopulationManifest, states: Dictionary) -> Dictionary:
	if applied_population_manifest != null and applied_population_manifest.manifest_hash() != manifest.manifest_hash(): return {"valid": false, "errors": ["INCOMPATIBLE_MATERIALIZED_POPULATION"]}
	if applied_population_manifest == null:
		var markers := {}; for marker in get_enemy_spawn_markers(): markers[marker.marker_id] = true
		for record in manifest.records:
			if not markers.has(record.marker_id): return {"valid": false, "errors": ["UNKNOWN_SAVED_MARKER"]}
			if String(states.get(record.population_id, "alive")) != "alive": continue
			var scene := load(record.enemy_resource_key) as PackedScene
			if scene == null: return {"valid": false, "errors": ["MISSING_DEER_SCENE"]}
			var deer := scene.instantiate() as Node2D
			deer.global_position = record.position
			_set_population_metadata(deer, record, manifest)
			add_child(deer)
		applied_population_manifest = manifest
	_population_states = states.duplicate(true)
	return {"valid": true, "errors": []}
