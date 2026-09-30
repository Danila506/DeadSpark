extends SceneTree

var _failed := false

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
				_assert(report.get("phases", []) == ["base_terrain", "water", "poi_placement", "road_graph", "road_raster", "environment", "enemy_population", "legacy_spawners"], "production phase order")
				var water := orchestrator.get_node_or_null("WaterGenerationPass") as WaterGenerationPass
				_assert(water != null and not water.generated_cells.is_empty(), "water pass generates a lake")
				_assert(water.lake_components.size() >= water.profile.min_lakes, "water components satisfy profile")
				var lake_layer := root.get_node_or_null("Y-Sort_Objects/LakeLayer") as TileMapLayer
				_assert(lake_layer != null and lake_layer.get_used_cells().size() >= water.generated_cells.size(), "water cells are rasterized")
				for cell in water.generated_cells:
					_assert(lake_layer.get_cell_source_id(cell) != -1, "every generated water cell has a visible tile")
				_assert(not String(report.get("generation_compatibility_hash", "")).is_empty(), "compatibility hash must be produced")
				_assert(not String(report.get("world_manifest_hash", "")).is_empty(), "manifest hash must be produced")
				_assert_road_and_village_contract(orchestrator, report)
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
				_assert_base_terrain_coverage(root, generator)
				if _failed:
					quit(1)
					return
				print(JSON.stringify(report))
				print("WORLD_GENERATION_SMOKE_TEST=PASS")
				quit(0)
	push_error("World generation smoke test timed out")
	quit(1)


func _assert_base_terrain_coverage(root: Node, generator: Node) -> void:
	var snow_layer := root.get_node_or_null("SnowLayer") as TileMapLayer
	_assert(snow_layer != null, "SnowLayer exists")
	var info: Dictionary = generator.call("get_debug_world_generation_info")
	var min_chunk := info.get("world_min_chunk", Vector2i.ZERO) as Vector2i
	var max_chunk := info.get("world_max_chunk", Vector2i.ZERO) as Vector2i
	var chunk_size := int(info.get("chunk_size_tiles", 0))
	_assert(chunk_size > 0, "base terrain chunk size is valid")
	var missing_cells: Array[Vector2i] = []
	var min_cell := min_chunk * chunk_size
	var max_cell_exclusive := (max_chunk + Vector2i.ONE) * chunk_size
	for y in range(min_cell.y, max_cell_exclusive.y):
		for x in range(min_cell.x, max_cell_exclusive.x):
			var cell := Vector2i(x, y)
			if snow_layer.get_cell_source_id(cell) == -1:
				missing_cells.append(cell)
	var sample := missing_cells.slice(0, mini(12, missing_cells.size()))
	print("BASE_TERRAIN_COVERAGE expected=%d actual=%d missing=%d sample=%s" % [
		(max_cell_exclusive.x - min_cell.x) * (max_cell_exclusive.y - min_cell.y),
		snow_layer.get_used_cells().size(),
		missing_cells.size(),
		str(sample)
	])
	_assert(missing_cells.is_empty(), "base snow terrain must not contain holes")


func _assert_road_and_village_contract(orchestrator: Node, report: Dictionary) -> void:
	var road := orchestrator.get_node_or_null("RoadGraphPass") as RoadGraphPass
	_assert(road != null and road.graph != null, "road graph exists")
	if road == null or road.graph == null: return
	_assert(road.graph.village_connector_cells.size() >= road.profile.minimum_village_count, "road graph reserves at least two village connectors")
	_assert(road.graph.primary_bend_count > 4, "production village road must be an irregular loop, not a rectangle")
	for cell_variant in road.graph.cells.keys():
		_assert(road.graph.neighbors(cell_variant as Vector2i).size() >= 2, "closed village road has no dead ends")
	_assert((report.get("poi_accepted", []) as Array).size() >= road.profile.minimum_village_count, "at least two villages are placed on the road loop")
	var poi := orchestrator.get_node_or_null("PoiPlacementPass") as PoiPlacementPass
	var environment := orchestrator.get_node_or_null("EnvironmentGenerationPass") as EnvironmentGenerationPass
	if poi == null or environment == null: return
	var road_cells := {}
	var clearance_cells := {}
	for claim_variant in poi.occupancy.canonical_manifest().claims:
		var claim := claim_variant as Dictionary
		if String(claim.owner_id) == "road:v1":
			for cell in claim.cells: road_cells[cell] = true
		elif String(claim.owner_id) == "road-clearance:v1":
			for cell in claim.cells: clearance_cells[cell] = true
	var natural_near_road := 0
	for placement_variant in environment.get_generation_output_manifest().accepted:
		var placement := placement_variant as Dictionary
		if String(placement.category) not in ["trees", "bushes", "berry_bushes", "stones", "puddles", "deadwood"]: continue
		for cell in placement.footprint:
			_assert(not road_cells.has(cell), "natural environment footprint must not overlap the road surface")
			if clearance_cells.has(cell): natural_near_road += 1
	_assert(natural_near_road > 0, "natural objects may populate the soft roadside clearance")


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
