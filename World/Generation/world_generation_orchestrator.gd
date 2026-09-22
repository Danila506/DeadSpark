class_name WorldGenerationOrchestrator
extends Node

signal generation_finished(report: Dictionary)

@export var finite_world_required: bool = true
@export_range(1, 512, 1) var default_step_budget: int = 24
@export var road_graph_source_path: NodePath = NodePath("RoadGraphPass")
@export var road_raster_source_path: NodePath = NodePath("RoadRasterizationPass")
@export var poi_source_path: NodePath = NodePath("PoiPlacementPass")
@export var environment_source_path: NodePath = NodePath("EnvironmentGenerationPass")
@export var deer_population_provider_path: NodePath = NodePath("DeerPopulationProvider")
@export var world_seed_source_path: NodePath = NodePath("ChunkWorldGenerator")

var _has_started := false
var _last_report: Dictionary = {}
var blocking_errors: Array[String] = []


func generate_startup(step_budget: int = -1, max_frames: int = 420) -> Dictionary:
	if _has_started:
		return _last_report.duplicate(true)
	_has_started = true
	blocking_errors.clear()
	var budget := maxi(1, default_step_budget if step_budget <= 0 else step_budget)
	var phases := _build_phases()
	if not blocking_errors.is_empty():
		_last_report = _build_report(phases)
		_last_report["blocking_errors"] = blocking_errors.duplicate()
		return _last_report.duplicate(true)
	for phase in phases:
		var sources: Array[Node] = phase.get("sources", [])
		var phase_id := String(phase.get("id", "unknown"))
		for source in sources:
			if source != null:
				source.set_process(false)
		if phase_id == "road_graph" or phase_id == "road_raster" or phase_id == "poi_placement" or phase_id == "environment":
			for source in sources:
				if source != null and source.has_method("run_generation_pass_async"):
					await source.call("run_generation_pass_async")
				elif source != null and source.has_method("run_generation_pass"):
					source.call("run_generation_pass")
			if _has_pending(sources):
				push_error("WorldGenerationOrchestrator: phase '%s' did not complete" % phase_id)
			continue
		if phase_id == "enemy_population":
			_run_deer_population_phase(sources)
			continue
		var frames := 0
		while _has_pending(sources) and frames < maxi(1, max_frames):
			for source in sources:
				if source != null and source.has_method("force_generate_step"):
					source.call("force_generate_step", budget)
			frames += 1
			if _has_pending(sources):
				await get_tree().process_frame
		if _has_pending(sources):
			push_error("WorldGenerationOrchestrator: phase '%s' did not finish within %d frames" % [phase.get("id", "unknown"), max_frames])
		for source in sources:
			if source != null and bool(source.get("enabled")):
				source.set_process(true)
	_last_report = _build_report(phases)
	if GameSaveManager != null and GameSaveManager.has_method("set_generation_contract"):
		GameSaveManager.set_generation_contract(_last_report)
	generation_finished.emit(_last_report.duplicate(true))
	return _last_report.duplicate(true)


func get_generation_report() -> Dictionary:
	return _last_report.duplicate(true) if not _last_report.is_empty() else _build_report(_build_phases())


func _build_phases() -> Array[Dictionary]:
	var terrain: Array[Node] = []
	var legacy_spawners: Array[Node] = []
	var road_graph: Array[Node] = []
	var road_raster: Array[Node] = []
	var poi: Array[Node] = []
	var environment: Array[Node] = []
	var enemy_population: Array[Node] = []
	var explicit := {
		"road_graph": _resolve_source(road_graph_source_path, "road_graph"),
		"road_raster": _resolve_source(road_raster_source_path, "road_raster"),
		"poi_placement": _resolve_source(poi_source_path, "poi_placement"),
		"environment": _resolve_source(environment_source_path, "environment")
	}
	for phase_id in ["road_graph", "road_raster", "poi_placement", "environment"]:
		if explicit[phase_id] == null:
			blocking_errors.append("MISSING_REQUIRED_SOURCE:%s" % phase_id)
	for child in get_children():
		if child == null:
			continue
		var enabled_value: Variant = child.get("enabled")
		if enabled_value != null and not bool(enabled_value):
			continue
		var explicit_phase := String(child.call("get_generation_phase")) if child.has_method("get_generation_phase") else ""
		if child in explicit.values():
			continue
		if explicit_phase == "road_graph":
			road_graph.append(child)
			continue
		if explicit_phase == "road_raster":
			road_raster.append(child)
			continue
		if explicit_phase == "poi_placement":
			poi.append(child)
			continue
		if explicit_phase == "environment":
			environment.append(child)
			continue
		if not child.has_method("has_generation_pending"):
			continue
		var info: Variant = child.call("get_debug_world_generation_info") if child.has_method("get_debug_world_generation_info") else {}
		if info is Dictionary and String((info as Dictionary).get("type", "")) == "spawner":
			legacy_spawners.append(child)
		else:
			terrain.append(child)
	if explicit["road_graph"] != null: road_graph.append(explicit["road_graph"])
	if explicit["road_raster"] != null: road_raster.append(explicit["road_raster"])
	if explicit["poi_placement"] != null: poi.append(explicit["poi_placement"])
	if explicit["environment"] != null: environment.append(explicit["environment"])
	var deer_provider := get_node_or_null(deer_population_provider_path)
	if deer_provider != null:
		enemy_population.append(deer_provider)
	return [
		{"id": "base_terrain", "sources": terrain},
		{"id": "road_graph", "sources": road_graph},
		{"id": "road_raster", "sources": road_raster},
		{"id": "poi_placement", "sources": poi},
		{"id": "environment", "sources": environment},
		{"id": "enemy_population", "sources": enemy_population},
		# This phase preserves legacy behaviour.
		{"id": "legacy_spawners", "sources": legacy_spawners}
	]


func _run_deer_population_phase(providers: Array[Node]) -> void:
	if multiplayer != null and multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return
	var occupancy := get_world_occupancy_context()
	var seed_source := get_node_or_null(world_seed_source_path)
	var seed := int(seed_source.get("world_seed")) if seed_source != null else 0
	for provider in providers:
		if provider != null and provider.has_method("set_geography_context"):
			provider.call("set_geography_context", occupancy)
	var result := (EnemyPopulationPass.new() as EnemyPopulationPass).build_manifests(seed, providers)
	for message in result.get("blocking_errors", []):
		blocking_errors.append(String(message))
	for raw_manifest in result.get("population_manifests", []):
		var manifest := _enemy_manifest_from_record(raw_manifest as Dictionary)
		for provider in providers:
			if provider != null and provider.has_method("get_enemy_population_owner_id") and String(provider.call("get_enemy_population_owner_id")) == manifest.owner_generated_object_id:
				var applied: Dictionary = provider.call("apply_enemy_population_manifest", manifest)
				for error in applied.get("errors", []):
					blocking_errors.append("stage=enemy_population owner=%s reason=%s" % [manifest.owner_generated_object_id, String(error)])


func _enemy_manifest_from_record(raw: Dictionary) -> EnemyPopulationManifest:
	var manifest := EnemyPopulationManifest.new()
	manifest.owner_generated_object_id = String(raw.get("owner_generated_object_id", ""))
	manifest.profile_id = String(raw.get("profile_id", ""))
	for item in raw.get("records", []):
		var record := EnemyPopulationRecord.new()
		record.population_id = String(item.get("population_id", ""))
		record.owner_generated_object_id = manifest.owner_generated_object_id
		record.marker_id = String(item.get("marker_id", ""))
		record.profile_id = manifest.profile_id
		record.enemy_entry_id = String(item.get("enemy_entry_id", ""))
		record.enemy_resource_key = String(item.get("enemy_resource_key", ""))
		record.position = item.get("position", Vector2.ZERO) as Vector2
		record.ordinal = int(item.get("ordinal", 0))
		record.initial_state = String(item.get("initial_state", "alive"))
		manifest.records.append(record)
	return manifest


func _resolve_source(path: NodePath, expected_phase: String) -> Node:
	var source := get_node_or_null(path)
	if source == null:
		return null
	if not source.has_method("get_generation_phase") or String(source.call("get_generation_phase")) != expected_phase or not source.has_method("run_generation_pass"):
		blocking_errors.append("INVALID_SOURCE_CONTRACT:%s" % expected_phase)
		return null
	return source


func get_world_occupancy_context() -> WorldOccupancyMap:
	var poi := get_node_or_null(poi_source_path) as PoiPlacementPass
	return poi.occupancy if poi != null else null


func _has_pending(sources: Array[Node]) -> bool:
	for source in sources:
		if source != null and source.has_method("has_generation_pending") and bool(source.call("has_generation_pending")):
			return true
	return false


func _build_report(phases: Array[Dictionary]) -> Dictionary:
	var compatibility_profiles: Array[Dictionary] = []
	var outputs: Array[Dictionary] = []
	var finite_bounds := {}
	var master_seed := 0
	for phase in phases:
		for source in phase.get("sources", []):
			if source == null:
				continue
			if source.has_method("get_generation_compatibility_profile"):
				compatibility_profiles.append(source.call("get_generation_compatibility_profile"))
			if source.has_method("get_generation_output_manifest"):
				outputs.append(source.call("get_generation_output_manifest"))
			var info: Dictionary = source.call("get_debug_world_generation_info") if source.has_method("get_debug_world_generation_info") else {}
			if finite_bounds.is_empty():
				finite_bounds = {"min_chunk": info.get("world_min_chunk", Vector2i.ZERO), "max_chunk": info.get("world_max_chunk", Vector2i.ZERO)}
				master_seed = int(info.get("seed", 0))
	compatibility_profiles.sort_custom(func(a: Dictionary, b: Dictionary): return String(a.get("id", "")) < String(b.get("id", "")))
	outputs.sort_custom(func(a: Dictionary, b: Dictionary): return String(a.get("id", "")) < String(b.get("id", "")))
	var compatibility := WorldGenerationContract.compatibility_hash(compatibility_profiles)
	var manifest := WorldGenerationContract.world_manifest_hash(compatibility, master_seed, finite_bounds)
	var road_graph_hash := ""
	var road_raster_hash := ""
	var poi_output := {}
	for phase in phases:
		for source in phase.get("sources", []):
			if source != null and source.has_method("get_road_graph_hash"):
				road_graph_hash = String(source.call("get_road_graph_hash"))
			if source != null and source.has_method("get_road_raster_hash"):
				road_raster_hash = String(source.call("get_road_raster_hash"))
			if source != null and source.has_method("get_generation_phase") and String(source.call("get_generation_phase")) == "poi_placement" and source.has_method("get_generation_output_manifest"):
				poi_output = source.call("get_generation_output_manifest")
	return {
		"generation_compatibility_hash": compatibility,
		"world_manifest_hash": manifest,
		"generation_output_hash": WorldGenerationContract.generation_output_hash(manifest, outputs),
		"road_graph_hash": road_graph_hash,
		"road_raster_hash": road_raster_hash,
		"occupancy_hash": String(poi_output.get("occupancy_hash", "")),
		"poi_candidate_hash": String(poi_output.get("candidate_hash", "")),
		"poi_placement_hash": String(poi_output.get("placement_hash", "")),
		"poi_candidates": poi_output.get("candidates", []),
		"poi_accepted": poi_output.get("accepted", []),
		"master_seed": master_seed,
		"finite_bounds": finite_bounds,
		"seed_test_vectors": WorldSeedService.get_test_vectors(),
		"phases": phases.map(func(phase: Dictionary): return String(phase.get("id", "")))
	}
