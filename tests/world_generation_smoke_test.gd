extends SceneTree

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var error := change_scene_to_file("res://level.tscn")
	_assert(error == OK, "level scene must load")
	var last_snapshot_hash := ""
	for _frame in range(12000):
		await process_frame
		var root_for_debug := current_scene
		var generator := root_for_debug.get_node_or_null("WorldGeneration/ChunkWorldGenerator") if root_for_debug != null else null
		if generator != null and generator.has_method("get_chunk_generation_debug_snapshot"):
			var snapshot: Dictionary = generator.call("get_chunk_generation_debug_snapshot")
			var snapshot_hash := GenerationHashes.sha256_of(snapshot)
			if snapshot_hash != last_snapshot_hash and _frame % 30 == 0:
				print("WORLD_GENERATION_SMOKE_PROGRESS frame=%d snapshot=%s" % [_frame, JSON.stringify(snapshot)])
				last_snapshot_hash = snapshot_hash
		# Rebuilding an output manifest scans the whole finite tile map; wait until
		# startup has had enough frames before polling the generation report.
		if _frame < 48:
			continue
		var root := current_scene
		var orchestrator := root.get_node_or_null("WorldGeneration") if root != null else null
		if orchestrator != null and orchestrator.has_method("get_generation_report") and not orchestrator._last_report.is_empty():
			var report: Dictionary = orchestrator.call("get_generation_report")
			if not String(report.get("generation_output_hash", "")).is_empty() and not String(report.get("road_graph_hash", "")).is_empty() and not String(report.get("road_raster_hash", "")).is_empty():
				_assert(report.get("phases", []) == ["base_terrain", "road_graph", "road_raster", "poi_placement", "environment", "enemy_population", "legacy_spawners"], "production phase order")
				_assert(not String(report.get("generation_compatibility_hash", "")).is_empty(), "compatibility hash must be produced")
				_assert(not String(report.get("world_manifest_hash", "")).is_empty(), "manifest hash must be produced")
				var provider := orchestrator.get_node_or_null("DeerPopulationProvider") as DeerPopulationProvider
				_assert(provider != null and provider.geography_occupancy == orchestrator.get_world_occupancy_context(), "Deer receives production occupancy context")
				_assert(provider.applied_population_manifest != null, "Deer population manifest materializes")
				var deer_ids: Array[String] = []
				for actor in provider.get_children():
					if actor.is_in_group("deer_generated_population"):
						deer_ids.append(String(actor.get_meta("population_id", "")))
				deer_ids.sort()
				_assert(deer_ids.size() == provider.applied_population_manifest.records.size(), "Deer materialization count")
				print("PRODUCTION_DEER_POPULATION count=%d ids=%s" % [deer_ids.size(), JSON.stringify(deer_ids)])
				var environment := orchestrator.get_node_or_null("EnvironmentGenerationPass") as EnvironmentGenerationPass
				_assert(environment != null, "environment pass exists")
				var environment_output: Dictionary = environment.get_generation_output_manifest()
				var chunk_counts: Array = environment_output.get("chunk_counts", [])
				_assert(chunk_counts.size() == 36, "environment covers 36 chunks")
				print("WORLD_GENERATION_ENVIRONMENT_CHUNK_COUNTS=" + JSON.stringify(chunk_counts))
				var snapshot: Dictionary = generator.call("get_chunk_generation_debug_snapshot") if generator != null else {}
				var queues: Dictionary = snapshot.get("queue_counts", {})
				_assert(int(queues.get("pending_load", -1)) == 0 and int(queues.get("scheduled_load", -1)) == 0, "chunk queues drained")
				print(JSON.stringify(report))
				print("WORLD_GENERATION_SMOKE_TEST=PASS")
				quit(0)
	push_error("World generation smoke test timed out")
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
