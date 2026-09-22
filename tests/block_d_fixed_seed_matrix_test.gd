extends Node

const SEEDS := [1337, 7331, 15885, 1001, 2026, 99999]
const BOUNDS := Rect2i(Vector2i(-48, -48), Vector2i(96, 96))
const DIR := "res://tests/artifacts/block_d"
const ROAD_PROFILE = preload("res://Resources/WorldGen/road_generation_profile.tres")
const ENV_PROFILE = preload("res://Resources/WorldGen/environment_generation_profile.tres")
const TEMPLATE = preload("res://Resources/WorldGen/village_poi_template.tres")
const ROAD_TILESET = preload("res://Assets/World/Roads/RoadTileSet.tres")
const ROAD = preload("res://World/Generation/road_graph_pass.gd")
const RASTER = preload("res://World/Generation/road_rasterization_pass.gd")
const POI = preload("res://World/Generation/poi_placement_pass.gd")
const ENV = preload("res://World/Generation/environment_generation_pass.gd")
class SeedSource extends Node:
	var seed := 0
	func get_debug_world_generation_info() -> Dictionary: return {"seed":seed,"chunk_size_tiles":16}
func _ready() -> void: call_deferred("_run")
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var rows: Array[Dictionary] = []
	for seed in SEEDS:
		var first := await _row(seed); var second := await _row(seed)
		_assert(GenerationHashes.sha256_of(first) == GenerationHashes.sha256_of(second), "in-process repeat seed %d" % seed)
		if seed == SEEDS[0]:
			var reordered_entries := await _row(seed, true, false)
			var reordered_chunks := await _row(seed, false, true)
			_assert(first.environment_manifest_hash == reordered_entries.environment_manifest_hash and first.environment_content_hash == reordered_entries.environment_content_hash, "entry order seed %d" % seed)
			_assert(first.environment_manifest_hash == reordered_chunks.environment_manifest_hash and first.environment_content_hash == reordered_chunks.environment_content_hash, "chunk order seed %d" % seed)
		rows.append(first)
	var content_hashes := {}
	for row in rows: content_hashes[String(row.environment_content_hash)] = true
	_assert(content_hashes.size() > 1, "different seeds vary environment content")
	_assert(String(rows[0].road_graph_hash) == "75916414acdf7aef1502e082bcc72bd976b5b24f8b7aca5a4177e4d5e48d49f7", "RoadGraph baseline")
	_assert(String(rows[0].road_raster_hash) == "0c17ddbedde7fdf8c6e98690b73cba62dc100d15231ee2a4f4dc59827ed2dcb8", "RoadRaster baseline")
	var matrix := {"id":"block_d_fixed_seed_environment_matrix_v1", "seeds":rows}
	var digest := GenerationHashes.sha256_of(matrix); matrix["matrix_digest"] = digest
	var file := FileAccess.open(ProjectSettings.globalize_path(DIR + "/fixed_seed_environment_matrix.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(matrix, "\t")); file.close()
	print("BLOCK_D_MATRIX_DIGEST=" + digest); print("BLOCK_D_MATRIX=PASS rows=%d" % rows.size())
	get_tree().quit(0)
func _row(seed: int, reverse_entries := false, reverse_chunks := false) -> Dictionary:
	var world := Node2D.new(); add_child(world)
	var ysort := Node2D.new(); ysort.name="Y-Sort_Objects"; world.add_child(ysort)
	var road_layer:=TileMapLayer.new(); road_layer.name="RoadLayer"; road_layer.tile_set=ROAD_TILESET; ysort.add_child(road_layer)
	for biome in ["Biom1", "Biom2"]:
		var container:=Node2D.new(); container.name=biome; ysort.add_child(container)
		for child_name in (["Biom1Layer","Trees","Bushes"] if biome=="Biom1" else ["Biom2Layer","Trees","Stones","Puddles","DeadWoodTrees","BerryBushes"]):
			var child: Node = TileMapLayer.new() if child_name.ends_with("Layer") else Node2D.new(); child.name=child_name
			if child is TileMapLayer: (child as TileMapLayer).tile_set = ROAD_TILESET
			container.add_child(child)
	var xz:=TileMapLayer.new(); xz.name="xz"; xz.tile_set=ROAD_TILESET; ysort.add_child(xz)
	var authored := (load("res://level.tscn") as PackedScene).instantiate()
	for path in ["Y-Sort_Objects/Biom1/Biom1Layer", "Y-Sort_Objects/Biom2/Biom2Layer", "Y-Sort_Objects/xz"]:
		var target_layer := world.get_node(path) as TileMapLayer
		var source_layer := authored.get_node(path) as TileMapLayer
		target_layer.tile_set = source_layer.tile_set
		target_layer.transform = source_layer.transform
	authored.free()
	var gen:=Node.new(); world.add_child(gen)
	var source:=SeedSource.new(); source.name="ChunkWorldGenerator"; source.seed=seed; gen.add_child(source)
	var road: RoadGraphPass=ROAD.new(); road.name="RoadGraphPass"; road.profile=ROAD_PROFILE; gen.add_child(road)
	var raster: RoadRasterizationPass=RASTER.new(); raster.name="RoadRasterizationPass"; raster.profile=ROAD_PROFILE; gen.add_child(raster)
	var poi: PoiPlacementPass=POI.new(); poi.name="PoiPlacementPass"; poi.template=TEMPLATE; gen.add_child(poi)
	var env: EnvironmentGenerationPass=ENV.new(); env.name="EnvironmentGenerationPass"; env.profile=ENV_PROFILE.duplicate(true) as EnvironmentGenerationProfile
	if reverse_entries: env.profile.entries.reverse()
	env.set_chunk_enumeration_reversed_for_test(reverse_chunks)
	gen.add_child(env)
	await get_tree().process_frame; road.build_graph_for_inputs(BOUNDS, seed); road.graph_hash=GenerationHashes.sha256_of(road.graph.canonical_manifest()); raster.run_generation_pass(); poi.run_generation_pass()
	var available_chunks := _chunks_with_available_environment(env, poi.occupancy)
	env.run_generation_pass(); await get_tree().process_frame
	_assert(env.blocking_errors.is_empty(), "environment blocking seed %d" % seed)
	var out:=env.get_generation_output_manifest(); var categories := {}; var scenes:=0; var tiles:=0; var ids:Array[String]=[]
	var species := {}
	var structures := {}
	var occupied_environment_cells := {}
	for item in out.accepted:
		var category:=String(item.category); categories[category]=int(categories.get(category,0))+1; ids.append(String(item.generated_id))
		if category == "trees": species[item.entry_id] = int(species.get(item.entry_id, 0)) + 1
		if category == "structures": structures[item.entry_id] = int(structures.get(item.entry_id, 0)) + 1
		for cell in item.footprint:
			_assert(not occupied_environment_cells.has(cell), "environment footprint overlap seed %d cell %s" % [seed, cell])
			occupied_environment_cells[cell] = item.generated_id
		var entry:=env._entry_by_id(String(item.entry_id)); if entry.kind==EnvironmentEntry.Kind.SCENE: scenes+=1
		else: tiles+=1
	var forest := env.get_forest_statistics()
	_assert(absf(float(forest.coverage) - 0.75) < 0.001, "forest land coverage seed %d" % seed)
	_assert(species.size() == 5, "all five tree species seed %d: %s" % [seed, species])
	_assert(int(categories.get("trees", 0)) > 500, "forest density seed %d" % seed)
	_assert(structures.size() == 5, "all five structure variants seed %d: %s" % [seed, structures])
	for id in structures:
		_assert(int(structures[id]) <= env._entry_by_id(id).max_instances_per_world, "world structure cap: " + id)
	print("STRUCTURES seed=%d counts=%s" % [seed, structures])
	print("FOREST seed=%d coverage=%.3f species=%s categories=%s" % [seed, forest.coverage, species, categories])
	ids.sort(); var unique_ids := {}; for id in ids: unique_ids[id] = true
	_assert(ids.size() == unique_ids.size(), "duplicate generated IDs seed %d" % seed); var claims:=0
	for claim in poi.occupancy.canonical_manifest().claims:
		if String((claim as Dictionary).source)=="environment": claims+=1
	var profiles:Array[Dictionary]=[road.get_generation_compatibility_profile(),raster.get_generation_compatibility_profile(),poi.get_generation_compatibility_profile(),env.get_generation_compatibility_profile()]; profiles.sort_custom(func(a,b):return String(a.id)<String(b.id))
	var compatibility:=WorldGenerationContract.compatibility_hash(profiles); var manifest:=WorldGenerationContract.world_manifest_hash(compatibility,seed,{"min_cell":BOUNDS.position,"max_cell":BOUNDS.end-Vector2i.ONE})
	var outputs:Array[Dictionary]=[road.get_generation_output_manifest(),raster.get_generation_output_manifest(),poi.get_generation_output_manifest(),out]; outputs.sort_custom(func(a,b):return String(a.id)<String(b.id))
	var chunk_counts: Array = out.chunk_counts
	_assert(chunk_counts.size() == 36, "all 36 finite chunks represented seed %d" % seed)
	for row in chunk_counts:
		var chunk_id := String((row as Dictionary).chunk)
		if available_chunks.has(chunk_id): _assert(int((row as Dictionary).count) > 0, "non-empty environment chunk %s seed %d" % [chunk_id, seed])
	var result={"seed":seed,"environment_manifest_hash":out.environment_manifest_hash,"environment_content_hash":out.environment_content_hash,"total_placements":out.accepted.size(),"placements_by_category":categories,"scene_placement_count":scenes,"tilemap_placement_count":tiles,"environment_occupancy_claim_count":claims,"chunk_counts":chunk_counts,"rejection_counts":out.rejection_counts,"generated_object_id_digest":GenerationHashes.sha256_of(ids),"road_graph_hash":road.graph_hash,"road_raster_hash":raster.raster_hash,"poi_hash":String(poi.get_generation_output_manifest().placement_hash),"village_hash":GenerationHashes.sha256_of([]),"compatibility_hash":compatibility,"global_manifest_hash":manifest,"global_output_hash":WorldGenerationContract.generation_output_hash(manifest,outputs)}
	_assert(result.total_placements==scenes+tiles and claims==result.total_placements,"counts seed %d"%seed)
	world.queue_free(); await get_tree().process_frame; return result
func _chunks_with_available_environment(env: EnvironmentGenerationPass, occupancy: WorldOccupancyMap) -> Dictionary:
	var result := {}
	var entry := env._entry_by_id("biom1_static_tiles")
	_assert(entry != null, "coverage entry exists")
	for y in range(-3, 3):
		for x in range(-3, 3):
			var chunk := Vector2i(x, y)
			var chunk_bounds := Rect2i(chunk * 16, Vector2i(16, 16))
			for cell_y in range(chunk_bounds.position.y, chunk_bounds.end.y):
				for cell_x in range(chunk_bounds.position.x, chunk_bounds.end.x):
					var footprint := env._footprint(Vector2i(cell_x, cell_y), entry)
					if env._within_bounds(footprint, occupancy.bounds) and not occupancy.has_flags(footprint, entry.blocked_occupancy_mask):
						result["%d,%d" % [x, y]] = true
						break
				if result.has("%d,%d" % [x, y]): break
	return result
func _assert(c:bool,m:String)->void:
	if c:return
	push_error("Block D matrix: "+m); get_tree().quit(1)
