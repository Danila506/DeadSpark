class_name RoadGraphPass
extends Node

const PHASE := "road_graph"

@export var enabled := true
@export var profile: RoadGenerationProfile
@export var world_bounds_source_path: NodePath = NodePath("../ChunkWorldGenerator")
@export var water_layer_path: NodePath = NodePath("../../Y-Sort_Objects/LakeLayer")
@export var road_layer_path: NodePath = NodePath("../../Y-Sort_Objects/RoadLayer")
@export var poi_pass_path: NodePath = NodePath("../PoiPlacementPass")

var graph: RoadGraph
var graph_hash := ""
var blocking_errors: Array[String] = []
var _generated := false

func get_generation_phase() -> String: return PHASE
func has_generation_pending() -> bool: return enabled and not _generated

func run_generation_pass() -> void:
	if not enabled or _generated: return
	blocking_errors.clear()
	if profile == null:
		_fail("MISSING_ROAD_PROFILE")
		return
	var master_seed := _resolve_master_seed()
	var connector_cells := _resolve_village_connector_cells()
	if connector_cells.size() < profile.minimum_village_count:
		_fail("REQUIRED_%d_VILLAGE_CONNECTORS_FOUND_%d" % [profile.minimum_village_count, connector_cells.size()])
		return
	build_graph_for_inputs(_resolve_world_cell_bounds(), master_seed, _collect_blocked_water_cells(), connector_cells)
	if graph == null or not bool(graph.validate().get("valid", false)):
		_fail("NO_VALID_CLOSED_ROUTE:%s" % str(graph.validate().get("errors", []) if graph != null else ["NO_VALID_ROUTE"]))
		return
	graph_hash = GenerationHashes.sha256_of(graph.canonical_manifest())
	var poi := get_node_or_null(poi_pass_path) as PoiPlacementPass
	if poi != null:
		poi.assign_road_connector_cells(graph.village_connector_cells)
	_generated = true

func build_graph_for_inputs(world_bounds: Rect2i, master_seed: int, blocked_water_cells: Dictionary = {}, required_connectors: Array[Vector2i] = []) -> RoadGraph:
	graph = RoadGraph.new()
	graph.bounds = world_bounds
	graph.blocked_cells = _expand_blocked_cells(blocked_water_cells, profile.water_clearance_cells, world_bounds)
	var loop: Array[Vector2i] = []
	var selected_bend_count := 4
	var loop_candidates := _connector_loop_candidates(required_connectors, master_seed) if not required_connectors.is_empty() else _loop_rect_candidates(master_seed)
	for candidate in loop_candidates:
		graph.route_attempts += 1
		var proposed: Array[Vector2i] = candidate.get("route", []) as Array[Vector2i] if candidate.has("route") else _rectangular_loop(int(candidate.left), int(candidate.right), int(candidate.top), int(candidate.bottom))
		if _route_hits_blocked(proposed):
			graph.record_rejection("WATER_INTERSECTION")
			continue
		var connectors := required_connectors.duplicate() if not required_connectors.is_empty() else _select_village_connectors(int(candidate.left), int(candidate.right), int(candidate.top), master_seed)
		if connectors.size() < profile.minimum_village_count:
			graph.record_rejection("INSUFFICIENT_VILLAGE_SITES")
			continue
		loop = proposed
		selected_bend_count = int(candidate.get("bend_count", 4))
		graph.village_connector_cells = connectors
		break
	if loop.is_empty():
		graph.record_rejection("NO_VALID_ROUTE")
		return null
	graph.add_route(loop, "primary")
	graph.primary_bend_count = selected_bend_count
	var validation := graph.validate()
	if not bool(validation.get("valid", false)) or not _has_closed_network(graph):
		return null
	return self.graph

func _resolve_village_connector_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var poi := get_node_or_null(poi_pass_path) as PoiPlacementPass
	var road_layer := get_node_or_null(road_layer_path) as TileMapLayer
	if poi == null or road_layer == null:
		return result
	for world_position in poi.get_connector_world_positions():
		result.append(road_layer.local_to_map(road_layer.to_local(world_position)))
	result.sort_custom(func(a: Vector2i, b: Vector2i): return a.x < b.x or (a.x == b.x and a.y < b.y))
	return result

func can_build_closed_loop_for_connectors(required_connectors: Array[Vector2i]) -> bool:
	if profile == null or required_connectors.size() < profile.minimum_village_count:
		return false
	var previous_graph := graph
	var preview := build_graph_for_inputs(_resolve_world_cell_bounds(), _resolve_master_seed(), _collect_blocked_water_cells(), required_connectors)
	var valid := preview != null and bool(preview.validate().get("valid", false)) and _has_closed_network(preview)
	graph = previous_graph
	return valid

func _connector_loop_candidates(connectors: Array[Vector2i], master_seed: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if connectors.size() < 2:
		return result
	var top := connectors[0].y
	var min_x := connectors[0].x
	var max_x := connectors[0].x
	for connector in connectors:
		if connector.y != top:
			return result
		min_x = mini(min_x, connector.x)
		max_x = maxi(max_x, connector.x)
	var seen_routes := {}
	for side_extension in range(1, 4):
		var left := min_x - side_extension
		var right := max_x + side_extension
		var maximum_bottom := graph.bounds.end.y - 1 - profile.loop_side_inset_cells
		var minimum_bottom := top + maxi(5, profile.loop_min_height_cells - 1)
		if minimum_bottom > maximum_bottom:
			continue
		for shape_variant in range(32):
			var shape_seed := WorldSeedService.derive_seed(master_seed, profile.road_seed_domain + "/village-loop-shape/v4", [left, right, top, shape_variant])
			var left_bulge := 1 + posmod(shape_seed, 3)
			var right_bulge := 1 + posmod(int(shape_seed / 5), 3)
			var left_drop := 2 + posmod(int(shape_seed / 11), 2)
			var right_drop := 2 + posmod(int(shape_seed / 17), 2)
			var bottom := minimum_bottom + posmod(int(shape_seed / 23), maximum_bottom - minimum_bottom + 1)
			var available_notch := bottom - top - maxi(left_drop, right_drop) - 1
			if available_notch < 1:
				continue
			var notch_depth := 1 + posmod(int(shape_seed / 31), mini(3, available_notch))
			var left_out := left - left_bulge
			var right_out := right + right_bulge
			if left_out < graph.bounds.position.x or right_out >= graph.bounds.end.x:
				continue
			var span := right - left
			var inner_offset := maxi(2, span / 3)
			var inner_left := left + inner_offset
			var inner_right := right - inner_offset
			if inner_right - inner_left < 2:
				continue
			var vertices: Array[Vector2i] = [
				Vector2i(left, top),
				Vector2i(right, top),
				Vector2i(right, top + right_drop),
				Vector2i(right_out, top + right_drop),
				Vector2i(right_out, bottom),
				Vector2i(inner_right, bottom),
				Vector2i(inner_right, bottom - notch_depth),
				Vector2i(inner_left, bottom - notch_depth),
				Vector2i(inner_left, bottom),
				Vector2i(left_out, bottom),
				Vector2i(left_out, top + left_drop),
				Vector2i(left, top + left_drop),
				Vector2i(left, top)
			]
			var route := _orthogonal_loop_from_vertices(vertices)
			var route_key := GenerationHashes.sha256_of(route)
			if route.is_empty() or seen_routes.has(route_key):
				continue
			seen_routes[route_key] = true
			var score := WorldSeedService.derive_seed(master_seed, profile.road_seed_domain + "/village-loop-rank/v4", [left, right, top, bottom, shape_variant])
			result.append({"left": left, "right": right, "top": top, "bottom": bottom, "route": route, "bend_count": vertices.size() - 1, "score": score})
	result.sort_custom(func(a: Dictionary, b: Dictionary):
		if int(a.score) != int(b.score): return int(a.score) < int(b.score)
		return "%d,%d,%d,%d" % [a.left, a.right, a.top, a.bottom] < "%d,%d,%d,%d" % [b.left, b.right, b.top, b.bottom])
	return result

func _orthogonal_loop_from_vertices(vertices: Array[Vector2i]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if vertices.size() < 5 or vertices.front() != vertices.back():
		return result
	for index in range(vertices.size() - 1):
		var from := vertices[index]
		var to := vertices[index + 1]
		if from.x != to.x and from.y != to.y:
			return []
		var cursor := from
		if result.is_empty() or result.back() != cursor:
			result.append(cursor)
		var direction := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
		while cursor != to:
			cursor += direction
			result.append(cursor)
	if result.size() > 1 and result.front() == result.back():
		result.pop_back()
	return result

func _loop_rect_candidates(master_seed: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var side_min := profile.loop_side_inset_cells
	var side_max := mini(side_min + 3, maxi(side_min, graph.bounds.size.x / 3))
	var top_min := profile.loop_top_inset_cells
	var top_max := mini(top_min + 3, maxi(top_min, graph.bounds.size.y / 3))
	var bottom_min := profile.loop_side_inset_cells
	var bottom_max := mini(bottom_min + 3, maxi(bottom_min, graph.bounds.size.y / 3))
	for left_inset in range(side_min, side_max + 1):
		for right_inset in range(side_min, side_max + 1):
			for top_inset in range(top_min, top_max + 1):
				for bottom_inset in range(bottom_min, bottom_max + 1):
					var left := graph.bounds.position.x + left_inset
					var right := graph.bounds.end.x - 1 - right_inset
					var top := graph.bounds.position.y + top_inset
					var bottom := graph.bounds.end.y - 1 - bottom_inset
					if right - left + 1 < profile.loop_min_width_cells or bottom - top + 1 < profile.loop_min_height_cells: continue
					var score := WorldSeedService.derive_seed(master_seed, profile.road_seed_domain + "/loop-rect", [left, right, top, bottom])
					result.append({"left": left, "right": right, "top": top, "bottom": bottom, "score": score})
	result.sort_custom(func(a: Dictionary, b: Dictionary):
		if int(a.score) != int(b.score): return int(a.score) < int(b.score)
		return "%d,%d,%d,%d" % [a.left, a.right, a.top, a.bottom] < "%d,%d,%d,%d" % [b.left, b.right, b.top, b.bottom])
	return result

func _rectangular_loop(left: int, right: int, top: int, bottom: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in range(left, right + 1): result.append(Vector2i(x, top))
	for y in range(top + 1, bottom + 1): result.append(Vector2i(right, y))
	for x in range(right - 1, left - 1, -1): result.append(Vector2i(x, bottom))
	for y in range(bottom - 1, top, -1): result.append(Vector2i(left, y))
	return result

func _route_hits_blocked(route: Array[Vector2i]) -> bool:
	for cell in route:
		if graph.blocked_cells.has(cell): return true
	return false

func _select_village_connectors(left: int, right: int, top: int, master_seed: int) -> Array[Vector2i]:
	var ranked: Array[Dictionary] = []
	var half_width := profile.village_footprint_half_width_cells
	for x in range(left + half_width, right - half_width + 1):
		var cell := Vector2i(x, top)
		if not _village_site_is_clear(cell): continue
		var score := WorldSeedService.derive_seed(master_seed, profile.road_seed_domain + "/village-site", [x, top])
		ranked.append({"cell": cell, "score": score})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary):
		if int(a.score) != int(b.score): return int(a.score) < int(b.score)
		return (a.cell as Vector2i).x < (b.cell as Vector2i).x)
	var selected: Array[Vector2i] = []
	for item in ranked:
		var cell := item.cell as Vector2i
		if _near_any(cell, selected, profile.village_connector_spacing_cells + 1): continue
		selected.append(cell)
		if selected.size() >= profile.minimum_village_count: break
	selected.sort_custom(func(a: Vector2i, b: Vector2i): return a.x < b.x or (a.x == b.x and a.y < b.y))
	return selected

func _village_site_is_clear(connector: Vector2i) -> bool:
	var half_width := profile.village_footprint_half_width_cells
	for y in range(connector.y - profile.village_footprint_depth_cells, connector.y):
		for x in range(connector.x - half_width, connector.x + half_width + 1):
			var cell := Vector2i(x, y)
			if not graph.bounds.has_point(cell) or graph.blocked_cells.has(cell): return false
	return true

func _has_closed_network(value: RoadGraph) -> bool:
	if value == null or value.cells.is_empty(): return false
	for cell_variant in value.cells.keys():
		if value.neighbors(cell_variant as Vector2i).size() < 2: return false
	return true

func get_generation_compatibility_profile() -> Dictionary:
	return profile.compatibility_profile() if profile != null else {"id": "road_profile:missing"}

func get_generation_output_manifest() -> Dictionary:
	return {"id": "road_graph_v1", "graph": graph.canonical_manifest() if graph != null else {}, "road_graph_hash": graph_hash}

func get_road_graph_hash() -> String: return graph_hash

func _fail(reason: String) -> void:
	if not blocking_errors.has(reason):
		blocking_errors.append(reason)
	_generated = true

func _resolve_world_cell_bounds() -> Rect2i:
	var source := get_node_or_null(world_bounds_source_path)
	var road_layer := get_node_or_null(road_layer_path) as TileMapLayer
	if source != null and source.has_method("get_world_bounds_rect") and road_layer != null:
		var world_bounds: Rect2 = source.call("get_world_bounds_rect")
		if world_bounds.size.x > 0.0 and world_bounds.size.y > 0.0:
			var inset := Vector2(0.01, 0.01)
			var first := road_layer.local_to_map(road_layer.to_local(world_bounds.position + inset))
			var last := road_layer.local_to_map(road_layer.to_local(world_bounds.end - inset))
			var minimum := Vector2i(mini(first.x, last.x), mini(first.y, last.y))
			var maximum := Vector2i(maxi(first.x, last.x), maxi(first.y, last.y))
			return Rect2i(minimum, maximum - minimum + Vector2i.ONE)
	return get_world_occupancy_bounds()

func get_world_occupancy_bounds() -> Rect2i:
	var source := get_node_or_null(world_bounds_source_path)
	var info: Dictionary = source.call("get_debug_world_generation_info") if source != null and source.has_method("get_debug_world_generation_info") else {}
	if info.has("world_min_chunk") and info.has("world_max_chunk"):
		var min_chunk: Vector2i = info.get("world_min_chunk", Vector2i.ZERO)
		var max_chunk: Vector2i = info.get("world_max_chunk", Vector2i.ZERO)
		var chunk_size := maxi(1, int(info.get("chunk_size_tiles", 16)))
		var min_cell := min_chunk * chunk_size
		return Rect2i(min_cell, (max_chunk - min_chunk + Vector2i.ONE) * chunk_size)
	if graph != null and not graph.bounds.size == Vector2i.ZERO:
		var scale := 256.0 / 60.0
		var first := Vector2i(floori(graph.bounds.position.x * scale), floori(graph.bounds.position.y * scale))
		var last := Vector2i(ceili(graph.bounds.end.x * scale), ceili(graph.bounds.end.y * scale))
		return Rect2i(first, last - first)
	return Rect2i(Vector2i.ZERO, Vector2i(16, 16))

func _resolve_master_seed() -> int:
	var source := get_node_or_null(world_bounds_source_path)
	var info: Dictionary = source.call("get_debug_world_generation_info") if source != null and source.has_method("get_debug_world_generation_info") else {}
	return int(info.get("seed", 0))

func _collect_blocked_water_cells() -> Dictionary:
	var result := {}
	var water_layer := get_node_or_null(water_layer_path) as TileMapLayer
	if water_layer == null: return result
	var road_layer := get_node_or_null(road_layer_path) as TileMapLayer
	if road_layer == null:
		for cell in water_layer.get_used_cells(): result[cell] = true
		return result
	for water_cell in water_layer.get_used_cells():
		for road_cell in _road_cells_overlapping_water_cell(water_layer, road_layer, water_cell):
			result[road_cell] = true
	return result

func _road_cells_overlapping_water_cell(water_layer: TileMapLayer, road_layer: TileMapLayer, water_cell: Vector2i) -> Array[Vector2i]:
	var center := water_layer.map_to_local(water_cell)
	var tile_size := Vector2(water_layer.tile_set.tile_size)
	var half_size := tile_size * 0.5
	var inset := Vector2(0.01, 0.01)
	var offsets: Array[Vector2] = [
		Vector2.ZERO,
		-half_size + inset,
		Vector2(half_size.x - inset.x, -half_size.y + inset.y),
		half_size - inset,
		Vector2(-half_size.x + inset.x, half_size.y - inset.y)
	]
	var cells := {}
	for offset in offsets:
		var world_position := water_layer.to_global(center + offset)
		var road_cell := road_layer.local_to_map(road_layer.to_local(world_position))
		cells[road_cell] = true
	var result: Array[Vector2i] = []
	for cell in cells.keys(): result.append(cell as Vector2i)
	result.sort_custom(func(a: Vector2i, b: Vector2i): return a.x < b.x or (a.x == b.x and a.y < b.y))
	return result

func _expand_blocked_cells(source: Dictionary, clearance: int, bounds: Rect2i) -> Dictionary:
	var result := {}
	var radius := maxi(0, clearance)
	for raw_cell in source.keys():
		var cell := raw_cell as Vector2i
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var blocked := cell + Vector2i(x, y)
				if bounds.has_point(blocked): result[blocked] = true
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
