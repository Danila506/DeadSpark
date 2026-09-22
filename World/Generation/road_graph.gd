class_name RoadGraph
extends RefCounted

var cells: Dictionary = {} # Vector2i -> { role: String }
var blocked_cells: Dictionary = {}
var bounds := Rect2i()
var rejection_reasons: Array[String] = []
var rejection_counts: Dictionary = {}
var branch_start_cells: Array[Vector2i] = []
var primary_anchor_sides: Array[String] = []
var route_attempts := 0
var primary_bend_count := 0
var branch_bend_count_total := 0

func record_rejection(reason: String) -> void:
	if not rejection_reasons.has(reason): rejection_reasons.append(reason)
	rejection_counts[reason] = int(rejection_counts.get(reason, 0)) + 1

func add_route(route: Array[Vector2i], role: String) -> void:
	for cell in route:
		var previous: Dictionary = cells.get(cell, {})
		if previous.is_empty() or role == "primary":
			cells[cell] = {"role": role}

func has_cell(cell: Vector2i) -> bool:
	return cells.has(cell)

func node_id(cell: Vector2i) -> String:
	return "road-node:v1:%d,%d" % [cell.x, cell.y]

func edge_id(a: Vector2i, b: Vector2i) -> String:
	var first := a
	var second := b
	if b.x < a.x or (b.x == a.x and b.y < a.y):
		first = b
		second = a
	return "road-edge:v1:%d,%d--%d,%d" % [first.x, first.y, second.x, second.y]

func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	for direction in directions:
		var candidate: Vector2i = cell + direction
		if cells.has(candidate):
			result.append(candidate)
	return result

func canonical_manifest() -> Dictionary:
	var sorted_cells := _sorted_cells(cells.keys())
	var nodes: Array[Dictionary] = []
	var edges: Array[Dictionary] = []
	for cell in sorted_cells:
		var adjacent := neighbors(cell)
		var topology := "SEGMENT"
		if _is_boundary(cell): topology = "BOUNDARY_ANCHOR"
		elif adjacent.size() >= 3: topology = "JUNCTION"
		elif adjacent.size() == 1: topology = "DEAD_END_POI_CANDIDATE" if String((cells[cell] as Dictionary).get("role", "")) == "secondary" else "DEAD_END"
		nodes.append({"id": node_id(cell), "cell": cell, "topology": topology})
		for other in adjacent:
			if node_id(cell) < node_id(other):
				edges.append({"id": edge_id(cell, other), "from": node_id(cell), "to": node_id(other), "role": String((cells[cell] as Dictionary).get("role", "primary"))})
	return {"bounds": bounds, "nodes": nodes, "edges": edges, "rejections": rejection_counts, "primary_anchor_sides": primary_anchor_sides, "route_attempts": route_attempts, "primary_bends": primary_bend_count, "branch_bends_total": branch_bend_count_total}

func validate() -> Dictionary:
	var errors: Array[String] = []
	var node_ids := {}
	var edge_ids := {}
	var primary_cells: Array[Vector2i] = []
	for cell_variant in cells.keys():
		var cell := cell_variant as Vector2i
		var id := node_id(cell)
		if node_ids.has(id): errors.append("DUPLICATE_NODE_ID")
		node_ids[id] = true
		if not bounds.has_point(cell): errors.append("OUT_OF_BOUNDS_NODE")
		if blocked_cells.has(cell): errors.append("WATER_INTERSECTION")
		var adjacent := neighbors(cell)
		if adjacent.is_empty(): errors.append("ISOLATED_ROAD_CELL")
		if String((cells[cell] as Dictionary).get("role", "")) == "primary": primary_cells.append(cell)
		for other in adjacent:
			if cell == other: errors.append("SELF_EDGE")
			var edge := edge_id(cell, other)
			if edge_ids.has(edge): continue
			edge_ids[edge] = true
			if abs(cell.x - other.x) + abs(cell.y - other.y) != 1: errors.append("ZERO_OR_NON_ORTHOGONAL_EDGE")
	if primary_cells.size() >= 2 and not _is_connected(primary_cells): errors.append("PRIMARY_NOT_CONNECTED")
	var all_cells := _sorted_cells(cells.keys())
	if all_cells.size() >= 2 and not _is_connected(all_cells): errors.append("GRAPH_NOT_CONNECTED")
	for branch_start in branch_start_cells:
		if not cells.has(branch_start) or neighbors(branch_start).size() < 3: errors.append("INVALID_BRANCH_START")
	return {"valid": errors.is_empty(), "errors": errors}

func _is_connected(required: Array[Vector2i]) -> bool:
	var pending := [required[0]]
	var visited := {}
	while not pending.is_empty():
		var current: Vector2i = pending.pop_back()
		if visited.has(current): continue
		visited[current] = true
		for other in neighbors(current):
			if cells.has(other) and not visited.has(other): pending.append(other)
	for cell in required:
		if not visited.has(cell): return false
	return true

func _is_boundary(cell: Vector2i) -> bool:
	return cell.x == bounds.position.x or cell.y == bounds.position.y or cell.x == bounds.end.x - 1 or cell.y == bounds.end.y - 1

func _sorted_cells(raw: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for item in raw:
		if item is Vector2i: result.append(item)
	result.sort_custom(func(a: Vector2i, b: Vector2i): return a.x < b.x or (a.x == b.x and a.y < b.y))
	return result
