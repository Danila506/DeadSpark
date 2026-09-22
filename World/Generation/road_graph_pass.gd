class_name RoadGraphPass
extends Node

const PHASE := "road_graph"

@export var enabled := true
@export var profile: RoadGenerationProfile
@export var world_bounds_source_path: NodePath = NodePath("../ChunkWorldGenerator")
@export var water_layer_path: NodePath = NodePath("../../Y-Sort_Objects/LakeLayer")

var graph: RoadGraph
var graph_hash := ""
var _generated := false

func get_generation_phase() -> String: return PHASE
func has_generation_pending() -> bool: return enabled and not _generated

func run_generation_pass() -> void:
	if not enabled or _generated: return
	if profile == null:
		push_error("RoadGraphPass: missing RoadGenerationProfile")
		return
	var master_seed := _resolve_master_seed()
	build_graph_for_inputs(_resolve_world_cell_bounds(), master_seed, _collect_blocked_water_cells())
	if graph == null or not bool(graph.validate().get("valid", false)):
		push_error("RoadGraphPass: no valid graph (%s)" % str(graph.validate().get("errors", []) if graph != null else ["NO_VALID_ROUTE"]))
		return
	graph_hash = GenerationHashes.sha256_of(graph.canonical_manifest())
	_generated = true

func build_graph_for_inputs(world_bounds: Rect2i, master_seed: int, blocked_water_cells: Dictionary = {}) -> RoadGraph:
	graph = RoadGraph.new()
	graph.bounds = world_bounds
	graph.blocked_cells = blocked_water_cells.duplicate(true)
	var anchors: Array[Vector2i] = []
	var primary: Array[Vector2i] = []
	for attempt in range(profile.max_route_attempts):
		anchors = _select_primary_anchors(master_seed, attempt)
		if anchors.size() < 2:
			graph.record_rejection("INVALID_BOUNDARY_ANCHOR")
			continue
		graph.route_attempts += 1
		var seed := WorldSeedService.derive_seed(master_seed, profile.road_seed_domain + "/primary-shape", [attempt, anchors[0].x, anchors[0].y, anchors[1].x, anchors[1].y])
		var bends := profile.min_primary_bends + posmod(seed, profile.max_primary_bends - profile.min_primary_bends + 1)
		var start_axis := 0 if anchors[0].x == graph.bounds.position.x or anchors[0].x == graph.bounds.end.x - 1 else 1
		primary = _build_shaped_route(anchors[0], anchors[1], start_axis, bends, seed, "PRIMARY")
		if not primary.is_empty():
			graph.primary_bend_count = bends
			break
		graph.record_rejection("PRIMARY_ROUTE_ATTEMPT_FAILED")
	if primary.is_empty():
		graph.record_rejection("NO_VALID_ROUTE")
		return null
	graph.add_route(primary, "primary")
	_add_secondary_branches(master_seed, anchors)
	var validation := graph.validate()
	if not bool(validation.get("valid", false)):
		return null
	return self.graph

func get_generation_compatibility_profile() -> Dictionary:
	return profile.compatibility_profile() if profile != null else {"id": "road_profile:missing"}

func get_generation_output_manifest() -> Dictionary:
	return {"id": "road_graph_v1", "graph": graph.canonical_manifest() if graph != null else {}, "road_graph_hash": graph_hash}

func get_road_graph_hash() -> String: return graph_hash

func _resolve_world_cell_bounds() -> Rect2i:
	var source := get_node_or_null(world_bounds_source_path)
	var info: Dictionary = source.call("get_debug_world_generation_info") if source != null and source.has_method("get_debug_world_generation_info") else {}
	var min_chunk: Vector2i = info.get("world_min_chunk", Vector2i.ZERO)
	var max_chunk: Vector2i = info.get("world_max_chunk", Vector2i.ZERO)
	var chunk_size := maxi(1, int(info.get("chunk_size_tiles", 16)))
	var min_cell := min_chunk * chunk_size
	return Rect2i(min_cell, (max_chunk - min_chunk + Vector2i.ONE) * chunk_size)

func _resolve_master_seed() -> int:
	var source := get_node_or_null(world_bounds_source_path)
	var info: Dictionary = source.call("get_debug_world_generation_info") if source != null and source.has_method("get_debug_world_generation_info") else {}
	return int(info.get("seed", 0))

func _collect_blocked_water_cells() -> Dictionary:
	var result := {}
	var layer := get_node_or_null(water_layer_path) as TileMapLayer
	if layer == null: return result
	for cell in layer.get_used_cells(): result[cell] = true
	return result

func _select_primary_anchors(master_seed: int, attempt: int) -> Array[Vector2i]:
	if profile.primary_anchor_pair_modes.is_empty(): return []
	var pair_seed := WorldSeedService.derive_seed(master_seed, profile.road_seed_domain + "/primary-anchor-pair")
	var pair := String(profile.primary_anchor_pair_modes[posmod(pair_seed + attempt, profile.primary_anchor_pair_modes.size())]).split(":")
	if pair.size() != 2: return []
	graph.primary_anchor_sides = [String(pair[0]), String(pair[1])]
	var candidates: Array[Vector2i] = []
	for side_variant in pair:
		var side := String(side_variant)
		var cell := _anchor_for_side(side, master_seed)
		if graph.blocked_cells.has(cell) or _near_any(cell, candidates, profile.minimum_anchor_spacing_cells):
			graph.record_rejection("INVALID_BOUNDARY_ANCHOR")
			return []
		candidates.append(cell)
	return candidates

func _anchor_for_side(side: String, master_seed: int) -> Vector2i:
	var margin := mini(profile.boundary_margin_cells, mini(graph.bounds.size.x / 3, graph.bounds.size.y / 3))
	var value := WorldSeedService.derive_seed(master_seed, "%s/anchor/%s" % [profile.road_seed_domain, side])
	if side == "west" or side == "east":
		var y_span := maxi(1, graph.bounds.size.y - margin * 2)
		return Vector2i(graph.bounds.position.x if side == "west" else graph.bounds.end.x - 1, graph.bounds.position.y + margin + posmod(value, y_span))
	var x_span := maxi(1, graph.bounds.size.x - margin * 2)
	return Vector2i(graph.bounds.position.x + margin + posmod(value, x_span), graph.bounds.position.y if side == "north" else graph.bounds.end.y - 1)

func _build_shaped_route(start: Vector2i, goal: Vector2i, start_axis: int, bends: int, seed: int, role: String) -> Array[Vector2i]:
	if bends < 0: return []
	var segment_count := bends + 1
	var x_count := 0
	var y_count := 0
	for index in range(segment_count):
		if posmod(start_axis + index, 2) == 0: x_count += 1
		else: y_count += 1
	var dx := goal.x - start.x
	var dy := goal.y - start.y
	var x_parts := _split_distance(abs(dx), x_count, seed + 11)
	var y_parts := _split_distance(abs(dy), y_count, seed + 29)
	if x_parts.is_empty() or y_parts.is_empty(): return []
	var x_index := 0
	var y_index := 0
	var cursor := start
	var route: Array[Vector2i] = [start]
	for index in range(segment_count):
		var axis := posmod(start_axis + index, 2)
		var next := cursor
		if axis == 0:
			next.x += signi(dx) * x_parts[x_index]
			x_index += 1
		else:
			next.y += signi(dy) * y_parts[y_index]
			y_index += 1
		var segment := _route_bfs(cursor, next, seed + index, role)
		if segment.is_empty(): return []
		segment.remove_at(0)
		route.append_array(segment)
		cursor = next
	return route if cursor == goal else []

func _split_distance(distance: int, part_count: int, seed: int) -> Array[int]:
	if part_count <= 0: return [] if distance != 0 else [0]
	if distance == 0: return []
	var minimum := maxi(profile.min_segment_length, profile.turn_spacing)
	if distance < minimum * part_count or distance > profile.max_segment_length * part_count: return []
	var result: Array[int] = []
	for _index in range(part_count): result.append(minimum)
	var remaining := distance - minimum * part_count
	var cursor := posmod(seed, part_count)
	while remaining > 0:
		if result[cursor] < profile.max_segment_length:
			result[cursor] += 1
			remaining -= 1
		cursor = posmod(cursor + 1, part_count)
	return result

func _route_bfs(start: Vector2i, goal: Vector2i, seed: int, role: String) -> Array[Vector2i]:
	var queue: Array[Vector2i] = [start]
	var came_from := {start: start}
	var directions: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT]
	if posmod(seed, 2) == 1: directions.reverse()
	var inspected := 0
	var encountered_network := false
	while not queue.is_empty() and inspected < profile.max_route_search_cells:
		var current: Vector2i = queue.pop_front()
		if current == goal: break
		inspected += 1
		for direction in directions:
			var next: Vector2i = current + direction
			if not graph.bounds.has_point(next) or came_from.has(next): continue
			if role == "SECONDARY":
				if next != start and graph.has_cell(next):
					encountered_network = true
					continue
				if _touches_existing_network(next, start):
					encountered_network = true
					continue
			if graph.blocked_cells.has(next):
				graph.record_rejection("WATER_INTERSECTION")
				continue
			came_from[next] = current
			queue.append(next)
	if not came_from.has(goal):
		if encountered_network: graph.record_rejection("BRANCH_INTERSECTS_NETWORK")
		return []
	var result: Array[Vector2i] = []
	var cursor := goal
	while cursor != start:
		result.append(cursor)
		cursor = came_from[cursor] as Vector2i
	result.append(start)
	result.reverse()
	return result

func _touches_existing_network(cell: Vector2i, allowed_neighbor: Vector2i) -> bool:
	for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var neighbor: Vector2i = cell + direction
		if neighbor != allowed_neighbor and graph.has_cell(neighbor): return true
	return false

func _is_near_world_border(cell: Vector2i) -> bool:
	return cell.x - graph.bounds.position.x < profile.branch_border_buffer_cells or graph.bounds.end.x - 1 - cell.x < profile.branch_border_buffer_cells or cell.y - graph.bounds.position.y < profile.branch_border_buffer_cells or graph.bounds.end.y - 1 - cell.y < profile.branch_border_buffer_cells

func _add_secondary_branches(master_seed: int, anchors: Array[Vector2i]) -> void:
	var starts: Array[Vector2i] = []
	var candidates: Array[Vector2i] = []
	for cell_variant in graph.cells.keys():
		var cell := cell_variant as Vector2i
		if graph.neighbors(cell).size() != 2 or _near_anchor_or_border(cell, anchors): continue
		candidates.append(cell)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i): return WorldSeedService.derive_seed(master_seed, profile.road_seed_domain + "/branch-candidate", [a.x, a.y]) < WorldSeedService.derive_seed(master_seed, profile.road_seed_domain + "/branch-candidate", [b.x, b.y]))
	var candidate_cursor := 0
	var attempt_count := 0
	while candidate_cursor < candidates.size() and attempt_count < profile.branch_attempts and starts.size() < profile.max_branches:
		var start: Vector2i = candidates[candidate_cursor]
		candidate_cursor += 1
		attempt_count += 1
		if graph.neighbors(start).size() != 2 or _near_existing_junction(start): continue
		if _near_any(start, starts, profile.branch_start_spacing_cells): continue
		var route := _build_branch(start, master_seed)
		if route.is_empty():
			graph.record_rejection("BRANCH_ROUTE_ATTEMPT_FAILED")
			continue
		graph.add_route(route, "secondary")
		starts.append(start)
		graph.branch_start_cells.append(start)
	if starts.size() < profile.min_branches:
		graph.record_rejection("MIN_BRANCHES_NOT_REACHED")

func _near_anchor_or_border(cell: Vector2i, anchors: Array[Vector2i]) -> bool:
	if cell.x - graph.bounds.position.x < profile.branch_border_buffer_cells or graph.bounds.end.x - 1 - cell.x < profile.branch_border_buffer_cells: return true
	if cell.y - graph.bounds.position.y < profile.branch_border_buffer_cells or graph.bounds.end.y - 1 - cell.y < profile.branch_border_buffer_cells: return true
	return _near_any(cell, anchors, profile.branch_junction_buffer_cells)

func _near_any(cell: Vector2i, others: Array[Vector2i], distance: int) -> bool:
	for other in others:
		if abs(cell.x - other.x) + abs(cell.y - other.y) < distance: return true
	return false

func _near_existing_junction(cell: Vector2i) -> bool:
	for other_variant in graph.cells.keys():
		var other := other_variant as Vector2i
		if other != cell and graph.neighbors(other).size() >= 3 and abs(cell.x - other.x) + abs(cell.y - other.y) < profile.branch_junction_buffer_cells:
			return true
	return false

func _build_branch(start: Vector2i, master_seed: int) -> Array[Vector2i]:
	var seed := WorldSeedService.derive_seed(master_seed, profile.road_seed_domain + "/branch", [start.x, start.y])
	var primary_neighbors := graph.neighbors(start)
	if primary_neighbors.size() != 2: return []
	var along_horizontal := primary_neighbors[0].y == start.y and primary_neighbors[1].y == start.y
	var directions: Array[Vector2i] = []
	if along_horizontal:
		directions = [Vector2i.UP, Vector2i.DOWN]
	else:
		directions = [Vector2i.LEFT, Vector2i.RIGHT]
	for attempt in range(profile.max_route_attempts):
		graph.route_attempts += 1
		var direction: Vector2i = directions[posmod(seed + attempt, directions.size())]
		var side := Vector2i(-direction.y, direction.x) if posmod(seed + attempt, 2) == 0 else Vector2i(direction.y, -direction.x)
		var main_length := profile.branch_length_min_cells + posmod(int(seed / 7) + attempt, profile.branch_length_max_cells - profile.branch_length_min_cells + 1)
		var side_length := profile.min_segment_length + posmod(int(seed / 13) + attempt, maxi(1, profile.branch_length_max_cells - profile.min_segment_length + 1))
		var goal := start + direction * main_length + side * side_length
		if not graph.bounds.has_point(goal) or _is_near_world_border(goal) or graph.blocked_cells.has(goal):
			graph.record_rejection("BRANCH_ENDPOINT_OUT_OF_BOUNDS")
			continue
		if graph.has_cell(goal):
			graph.record_rejection("BRANCH_INTERSECTS_NETWORK")
			continue
		var bends := 1 + posmod(seed + attempt, 2)
		var start_axis := 0 if direction.x != 0 else 1
		var route := _build_shaped_route(start, goal, start_axis, bends, seed + attempt * 47, "SECONDARY")
		if route.size() > 1:
			graph.branch_bend_count_total += bends
			return route
		graph.record_rejection("BRANCH_ROUTE_ATTEMPT_FAILED")
	return []
