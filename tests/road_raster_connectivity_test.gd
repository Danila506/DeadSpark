extends SceneTree

const PROFILE := preload("res://Resources/WorldGen/road_generation_profile.tres")
const TILESET := preload("res://Assets/World/Roads/RoadTileSet.tres")
const GRAPH_PASS := preload("res://World/Generation/road_graph_pass.gd")
const RASTER_PASS := preload("res://World/Generation/road_rasterization_pass.gd")
const SEEDS := [1337, 1338, 7331, 15885, 1001, 2026, 99999]
const BOUNDS := Rect2i(Vector2i(-48, -48), Vector2i(96, 96))

func _init() -> void:
	var results: Array[Dictionary] = []
	for seed in SEEDS:
		results.append(_test_seed(seed))
	print("ROAD_RASTER_CONNECTIVITY=" + JSON.stringify(results))
	quit(0)

func _test_seed(seed: int) -> Dictionary:
	var root := Node.new()
	root.name = "RasterTest"
	self.root.add_child(root)
	var graph := GRAPH_PASS.new() as RoadGraphPass
	graph.name = "RoadGraph"
	graph.profile = PROFILE
	root.add_child(graph)
	var layer := TileMapLayer.new()
	layer.name = "RoadLayer"
	layer.tile_set = TILESET
	root.add_child(layer)
	var raster := RASTER_PASS.new() as RoadRasterizationPass
	raster.name = "RoadRaster"
	raster.profile = PROFILE
	raster.graph_pass_path = NodePath("../RoadGraph")
	raster.road_layer_path = NodePath("../RoadLayer")
	root.add_child(raster)
	graph.build_graph_for_inputs(BOUNDS, seed)
	_assert(graph.graph != null and bool(graph.graph.validate().valid), "seed %d invalid RoadGraph" % seed)
	raster.run_generation_pass()
	var diagnostic := raster.get_connectivity_diagnostics()
	_assert((diagnostic.isolated_road_cells as Array).is_empty(), "seed %d isolated road cells: %s" % [seed, JSON.stringify(diagnostic.isolated_road_cells)])
	_assert((diagnostic.small_disconnected_components as Array).is_empty(), "seed %d small disconnected components: %s" % [seed, JSON.stringify(diagnostic.small_disconnected_components)])
	_assert(bool(diagnostic.matches_graph_cells) and bool(diagnostic.connectivity_matches_graph) and int(diagnostic.road_component_count) == 1, "seed %d graph/raster connectivity mismatch: %s" % [seed, JSON.stringify(diagnostic)])
	var first_hash := raster.raster_hash
	raster.clear_generated()
	_assert(layer.get_meta(RoadRasterizationPass.GENERATED_CELLS_META, []).is_empty(), "seed %d stale generated cells after clear" % seed)
	raster.run_generation_pass()
	_assert(first_hash == raster.raster_hash, "seed %d Generate-Clear-Generate raster hash changed" % seed)
	var result := {"seed":seed, "road_graph_hash":GenerationHashes.sha256_of(graph.graph.canonical_manifest()), "road_raster_hash":raster.raster_hash, "road_cells":(diagnostic.road_cells as Array).size(), "components":diagnostic.road_component_count}
	root.queue_free()
	return result

func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error("RoadRaster connectivity: " + message)
		quit(1)
