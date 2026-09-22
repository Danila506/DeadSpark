extends SceneTree

const ROAD_PROFILE = preload("res://Resources/WorldGen/road_generation_profile.tres")
const ROAD_GRAPH_PASS = preload("res://World/Generation/road_graph_pass.gd")
const ROAD_RASTER_PASS = preload("res://World/Generation/road_rasterization_pass.gd")

func _init() -> void:
	var generator: RoadGraphPass = ROAD_GRAPH_PASS.new()
	generator.profile = ROAD_PROFILE
	var bounds := Rect2i(Vector2i(-48, -48), Vector2i(96, 96))
	generator.build_graph_for_inputs(bounds, 1337)
	var graph_a := generator.graph
	var hash_a := GenerationHashes.sha256_of(graph_a.canonical_manifest())
	generator.build_graph_for_inputs(bounds, 1337)
	var graph_repeat := generator.graph
	var hash_repeat := GenerationHashes.sha256_of(graph_repeat.canonical_manifest())
	generator.build_graph_for_inputs(bounds, 7331)
	var graph_b := generator.graph
	var hash_b := GenerationHashes.sha256_of(graph_b.canonical_manifest())
	_assert(hash_a == hash_repeat, "same seed graph hash must be stable")
	_assert(hash_a != hash_b, "different seed must change graph for regression seed pair")
	var permuted_graph := RoadGraph.new()
	permuted_graph.bounds = bounds
	var reverse_cells: Array = graph_a.cells.keys()
	reverse_cells.reverse()
	for cell_variant in reverse_cells:
		var cell := cell_variant as Vector2i
		permuted_graph.add_route([cell], String((graph_a.cells[cell] as Dictionary).get("role", "primary")))
	permuted_graph.rejection_counts = graph_a.rejection_counts.duplicate(true)
	permuted_graph.rejection_reasons = graph_a.rejection_reasons.duplicate()
	permuted_graph.branch_start_cells = graph_a.branch_start_cells.duplicate()
	permuted_graph.primary_anchor_sides = graph_a.primary_anchor_sides.duplicate()
	permuted_graph.route_attempts = graph_a.route_attempts
	permuted_graph.primary_bend_count = graph_a.primary_bend_count
	permuted_graph.branch_bend_count_total = graph_a.branch_bend_count_total
	_assert(hash_a == GenerationHashes.sha256_of(permuted_graph.canonical_manifest()), "internal insertion order must not change graph identity/output")
	_assert(bool(graph_a.validate().get("valid", false)), "graph invariants and connectivity must hold")
	var road_cells: Array = graph_a.cells.keys()
	var blocked: Dictionary = {road_cells[int(road_cells.size() / 2)]: true}
	generator.build_graph_for_inputs(bounds, 1337, blocked)
	var water_graph := generator.graph
	_assert(water_graph != null, "bounded reroute must find a water-safe route")
	_assert(not water_graph.cells.has(blocked.keys()[0]), "roads must not cross blocked water")
	_assert(water_graph.rejection_reasons.has("WATER_INTERSECTION"), "water rejection must be reported")
	_assert(bool(water_graph.validate().get("valid", false)), "water reroute graph must validate")
	var junction_graph := RoadGraph.new()
	junction_graph.bounds = bounds
	junction_graph.add_route([Vector2i.ZERO, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT], "primary")
	var raster: RoadRasterizationPass = ROAD_RASTER_PASS.new()
	raster.profile = ROAD_PROFILE
	_assert(raster._atlas_for(Vector2i.ZERO, junction_graph) == ROAD_PROFILE.cross_atlas, "cross raster mapping")
	var t_graph := RoadGraph.new()
	t_graph.bounds = bounds
	t_graph.add_route([Vector2i.ZERO, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT], "primary")
	_assert(raster._atlas_for(Vector2i.ZERO, t_graph) == ROAD_PROFILE.t_missing_down_atlas, "T raster mapping")
	print(JSON.stringify({"seed_1337": hash_a, "seed_7331": hash_b, "water_reroute": GenerationHashes.sha256_of(water_graph.canonical_manifest())}))
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition: return
	push_error(message)
	quit(1)
