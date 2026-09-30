class_name PoiPlacementPass
extends Node

const PHASE := "poi_placement"
const ACCEPTED := "ACCEPTED"
const OUT_OF_BOUNDS := "OUT_OF_BOUNDS"
const ROAD_OVERLAP := "ROAD_OVERLAP"
const ROAD_CLEARANCE_OVERLAP := "ROAD_CLEARANCE_OVERLAP"
const WATER_OVERLAP := "WATER_OVERLAP"
const POI_OVERLAP := "POI_OVERLAP"
const INVALID_CONNECTOR := "INVALID_CONNECTOR"
const UNSUPPORTED_ORIENTATION := "UNSUPPORTED_ORIENTATION"
const INSUFFICIENT_CLEARANCE := "INSUFFICIENT_CLEARANCE"
const INVALID_AUTHORED_DATA := "INVALID_AUTHORED_DATA"

@export var enabled := true
@export var world_bounds_source_path: NodePath = NodePath("../ChunkWorldGenerator")
@export var road_graph_pass_path: NodePath = NodePath("../RoadGraphPass")
@export var road_raster_pass_path: NodePath = NodePath("../RoadRasterizationPass")
@export var road_layer_path: NodePath = NodePath("../../Y-Sort_Objects/RoadLayer")
@export var water_layer_path: NodePath = NodePath("../../Y-Sort_Objects/LakeLayer")
@export var template: PoiTemplate
@export var spawn_parent_path: NodePath = NodePath("../../Y-Sort_Objects")
@export_range(2, 32, 1) var minimum_accepted_pois := 2
@export_range(2, 32, 1) var max_accepted_pois := 2
@export var occupancy_cell_size := Vector2(60.0, 60.0)
@export_range(16.0, 256.0, 1.0) var road_surface_width_px := 60.0
@export_range(0, 16, 1) var world_edge_margin_cells := 2
@export_range(0, 16, 1) var village_spacing_road_cells := 1

var occupancy := WorldOccupancyMap.new()
var candidates: Array[Dictionary] = []
var accepted: Array[Dictionary] = []
var blocking_errors: Array[String] = []
var _generated := false
var _road_claims_imported := false


func get_generation_phase() -> String:
	return PHASE


func has_generation_pending() -> bool:
	return enabled and not _generated


func run_generation_pass() -> void:
	if not enabled or _generated:
		return
	blocking_errors.clear()
	candidates.clear()
	accepted.clear()
	if template == null:
		_fail("MISSING_TEMPLATE")
		return
	var template_check := template.validate()
	if not bool(template_check.get("valid", false)):
		_fail("INVALID_TEMPLATE:%s" % str(template_check.get("errors", [])))
		return
	if not template.allowed_rotations.has(0.0):
		_fail(UNSUPPORTED_ORIENTATION)
		return
	var road_layer := get_node_or_null(road_layer_path) as TileMapLayer
	var parent := get_node_or_null(spawn_parent_path) as Node2D
	var world_rect := _resolve_world_rect()
	if road_layer == null or parent == null or world_rect.size.x <= 0.0 or world_rect.size.y <= 0.0:
		_fail("MISSING_PLACEMENT_CONTEXT")
		return
	occupancy.reset(_rect_cell_bounds(world_rect))
	_import_water_claims()
	var pair := _select_village_pair(road_layer, world_rect, _resolve_master_seed())
	if pair.size() < minimum_accepted_pois:
		_fail("REQUIRED_%d_VILLAGES_FOUND_%d:NO_WATER_SAFE_PAIR" % [minimum_accepted_pois, pair.size()])
		return
	for candidate in pair:
		candidates.append(candidate)
		_resolve_planned_candidate(candidate, parent)
	if accepted.size() < minimum_accepted_pois:
		_fail("REQUIRED_%d_VILLAGES_PLACED_%d" % [minimum_accepted_pois, accepted.size()])
		return
	_generated = true


func get_connector_world_positions() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for item in accepted:
		result.append(item.get("connector_world", Vector2.ZERO) as Vector2)
	return result


func assign_road_connector_cells(cells: Array[Vector2i]) -> void:
	for index in mini(cells.size(), accepted.size()):
		accepted[index]["road_cell"] = cells[index]


func import_road_claims_after_raster() -> void:
	if _road_claims_imported or not _generated:
		return
	var raster := get_node_or_null(road_raster_pass_path)
	var road_pass := get_node_or_null(road_graph_pass_path) as RoadGraphPass
	var layer := get_node_or_null(road_layer_path) as TileMapLayer
	if raster == null or road_pass == null or road_pass.graph == null or layer == null:
		_fail("MISSING_ROAD_OCCUPANCY_CONTEXT")
		return
	var roads_set := {}
	var clearance_set := {}
	for occupancy_cell in _road_corridor_cells(layer, road_pass.graph):
		if occupancy.bounds.has_point(occupancy_cell):
			roads_set[occupancy_cell] = true
	var clearance_radius := maxi(1, template.required_clearance_cells)
	for road_variant in roads_set.keys():
		var road_cell := road_variant as Vector2i
		for y in range(-clearance_radius, clearance_radius + 1):
			for x in range(-clearance_radius, clearance_radius + 1):
				var clearance_cell := road_cell + Vector2i(x, y)
				if occupancy.bounds.has_point(clearance_cell) and not roads_set.has(clearance_cell):
					clearance_set[clearance_cell] = true
	occupancy.claim_cells(_sorted_cells(roads_set.keys()), WorldOccupancyMap.ROAD, "road:v1", "RoadRasterizationPass")
	occupancy.claim_cells(_sorted_cells(clearance_set.keys()), WorldOccupancyMap.ROAD_CLEARANCE, "road-clearance:v1", "RoadRasterizationPass")
	_road_claims_imported = true


func _select_village_pair(road_layer: TileMapLayer, world_rect: Rect2, master_seed: int) -> Array[Dictionary]:
	var inset := Vector2(0.01, 0.01)
	var first := road_layer.local_to_map(road_layer.to_local(world_rect.position + inset))
	var last := road_layer.local_to_map(road_layer.to_local(world_rect.end - inset))
	var min_cell := Vector2i(mini(first.x, last.x), mini(first.y, last.y))
	var max_cell := Vector2i(maxi(first.x, last.x), maxi(first.y, last.y))
	var valid_by_row := {}
	for y in range(min_cell.y + world_edge_margin_cells, max_cell.y - world_edge_margin_cells + 1):
		var row: Array[Dictionary] = []
		for x in range(min_cell.x + world_edge_margin_cells, max_cell.x - world_edge_margin_cells + 1):
			var road_cell := Vector2i(x, y)
			var connector_world := road_layer.to_global(road_layer.map_to_local(road_cell))
			var origin_world := connector_world - template.connector_local_position
			var footprint := Rect2(origin_world + template.authored_bounds.position, template.authored_bounds.size)
			var footprint_cells := _rect_cells(footprint, occupancy_cell_size)
			if not _rect_contains_rect(world_rect, footprint):
				continue
			if occupancy.has_flags(footprint_cells, WorldOccupancyMap.WATER):
				continue
			row.append({
				"candidate_id": "poi-candidate:v3:%d,%d" % [x, y],
				"road_cell": road_cell,
				"connector_world": connector_world,
				"world_position": origin_world,
				"footprint_cells": footprint_cells,
				"template_id": template.template_id,
				"connector_id": template.connector_id,
				"accepted": false,
				"status": ""
			})
		if not row.is_empty():
			valid_by_row[y] = row
	var pairs: Array[Dictionary] = []
	for y_variant in valid_by_row.keys():
		var row := valid_by_row[y_variant] as Array
		for left_index in range(row.size()):
			for right_index in range(left_index + 1, row.size()):
				var left := row[left_index] as Dictionary
				var right := row[right_index] as Dictionary
				var left_cell := left.get("road_cell", Vector2i.ZERO) as Vector2i
				var right_cell := right.get("road_cell", Vector2i.ZERO) as Vector2i
				if right_cell.x - left_cell.x < village_spacing_road_cells + 4:
					continue
				if _cells_overlap(left.get("footprint_cells", []) as Array, right.get("footprint_cells", []) as Array):
					continue
				if not _connector_corridor_is_water_free(road_layer, left_cell, right_cell):
					continue
				var score := WorldSeedService.derive_seed(master_seed, "poi/village-pair/v3", [left_cell.x, left_cell.y, right_cell.x, right_cell.y])
				pairs.append({"left": left, "right": right, "score": score})
	if pairs.is_empty():
		return []
	pairs.sort_custom(func(a: Dictionary, b: Dictionary):
		if int(a.get("score", 0)) != int(b.get("score", 0)):
			return int(a.get("score", 0)) < int(b.get("score", 0))
		return String((a.get("left", {}) as Dictionary).get("candidate_id", "")) < String((b.get("left", {}) as Dictionary).get("candidate_id", "")))
	var road_pass := get_node_or_null(road_graph_pass_path) as RoadGraphPass
	for pair_variant in pairs:
		var pair := pair_variant as Dictionary
		var left := pair.get("left", {}) as Dictionary
		var right := pair.get("right", {}) as Dictionary
		var connector_cells: Array[Vector2i] = [left.get("road_cell", Vector2i.ZERO) as Vector2i, right.get("road_cell", Vector2i.ZERO) as Vector2i]
		if road_pass == null or road_pass.can_build_closed_loop_for_connectors(connector_cells):
			return [left, right]
	return []


func _resolve_planned_candidate(candidate: Dictionary, parent: Node2D) -> void:
	var cells: Array[Vector2i] = []
	for cell in candidate.get("footprint_cells", []):
		cells.append(cell as Vector2i)
	if cells.is_empty():
		candidate["status"] = OUT_OF_BOUNDS
		return
	if occupancy.has_flags(cells, WorldOccupancyMap.WATER):
		candidate["status"] = WATER_OVERLAP
		return
	if occupancy.has_flags(cells, WorldOccupancyMap.POI | WorldOccupancyMap.NO_SPAWN):
		candidate["status"] = POI_OVERLAP
		return
	var owner := "poi:v3/%s/%s" % [template.template_id, candidate.get("candidate_id", "unknown")]
	var result := occupancy.claim_cells(cells, WorldOccupancyMap.POI | WorldOccupancyMap.NO_SPAWN, owner, "PoiPlacementPass")
	if not bool(result.get("valid", false)):
		candidate["status"] = String(result.get("reason", OUT_OF_BOUNDS))
		return
	candidate.erase("footprint_cells")
	candidate["accepted"] = true
	candidate["status"] = ACCEPTED
	accepted.append(candidate)
	_instantiate_village(candidate.get("world_position", Vector2.ZERO) as Vector2, owner, parent)


func _import_water_claims() -> void:
	var layer := get_node_or_null(water_layer_path) as TileMapLayer
	if layer == null:
		return
	var water_set := {}
	var tile_size := Vector2(layer.tile_set.tile_size) if layer.tile_set != null else occupancy_cell_size
	for cell in layer.get_used_cells():
		var center := layer.to_global(layer.map_to_local(cell))
		for occupied in _rect_cells(Rect2(center - tile_size * 0.5, tile_size), occupancy_cell_size):
			if occupancy.bounds.has_point(occupied):
				water_set[occupied] = true
	var water := _sorted_cells(water_set.keys())
	if not water.is_empty():
		occupancy.claim_cells(water, WorldOccupancyMap.WATER, "water:v1", "WaterGenerationPass")


func _connector_corridor_is_water_free(layer: TileMapLayer, left: Vector2i, right: Vector2i) -> bool:
	var half_width := road_surface_width_px * 0.5
	var start := layer.to_global(layer.map_to_local(left))
	var finish := layer.to_global(layer.map_to_local(right))
	var rect := Rect2(Vector2(minf(start.x, finish.x), minf(start.y, finish.y)) - Vector2.ONE * half_width, Vector2(absf(finish.x - start.x), absf(finish.y - start.y)) + Vector2.ONE * road_surface_width_px)
	return not occupancy.has_flags(_rect_cells(rect, occupancy_cell_size), WorldOccupancyMap.WATER)


func _resolve_world_rect() -> Rect2:
	var source := get_node_or_null(world_bounds_source_path)
	if source != null and source.has_method("get_world_bounds_rect"):
		var direct := source.call("get_world_bounds_rect") as Rect2
		if direct.size.x > 0.0 and direct.size.y > 0.0:
			return direct
	var info: Dictionary = source.call("get_debug_world_generation_info") if source != null and source.has_method("get_debug_world_generation_info") else {}
	if info.has("world_min_chunk") and info.has("world_max_chunk"):
		var min_chunk := info.get("world_min_chunk", Vector2i.ZERO) as Vector2i
		var max_chunk := info.get("world_max_chunk", Vector2i.ZERO) as Vector2i
		var chunk_size := maxi(1, int(info.get("chunk_size_tiles", 16)))
		var minimum := Vector2(min_chunk * chunk_size) * occupancy_cell_size
		var size := Vector2((max_chunk - min_chunk + Vector2i.ONE) * chunk_size) * occupancy_cell_size
		return Rect2(minimum, size)
	return Rect2()


func _resolve_master_seed() -> int:
	var source := get_node_or_null(world_bounds_source_path)
	var info: Dictionary = source.call("get_debug_world_generation_info") if source != null and source.has_method("get_debug_world_generation_info") else {}
	return int(info.get("seed", 0))


func _rect_cell_bounds(rect: Rect2) -> Rect2i:
	var minimum := Vector2i(floori(rect.position.x / occupancy_cell_size.x), floori(rect.position.y / occupancy_cell_size.y))
	var maximum := Vector2i(ceili(rect.end.x / occupancy_cell_size.x), ceili(rect.end.y / occupancy_cell_size.y))
	return Rect2i(minimum, maximum - minimum)


func _rect_cells(rect: Rect2, cell_size: Vector2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var min_cell := Vector2i(floori(rect.position.x / cell_size.x), floori(rect.position.y / cell_size.y))
	var max_cell := Vector2i(floori((rect.end.x - 0.01) / cell_size.x), floori((rect.end.y - 0.01) / cell_size.y))
	for y in range(min_cell.y, max_cell.y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			result.append(Vector2i(x, y))
	return result


func _road_corridor_cells(layer: TileMapLayer, road_graph: RoadGraph) -> Array[Vector2i]:
	var result := {}
	var half_width := road_surface_width_px * 0.5
	for cell_variant in road_graph.cells.keys():
		var cell := cell_variant as Vector2i
		var center := layer.to_global(layer.map_to_local(cell))
		for occupied in _rect_cells(Rect2(center - Vector2.ONE * half_width, Vector2.ONE * road_surface_width_px), occupancy_cell_size):
			result[occupied] = true
		for neighbor in road_graph.neighbors(cell):
			if road_graph.node_id(cell) >= road_graph.node_id(neighbor):
				continue
			var other := layer.to_global(layer.map_to_local(neighbor))
			var start := Vector2(minf(center.x, other.x), minf(center.y, other.y)) - Vector2.ONE * half_width
			var size := Vector2(absf(other.x - center.x), absf(other.y - center.y)) + Vector2.ONE * road_surface_width_px
			for occupied in _rect_cells(Rect2(start, size), occupancy_cell_size):
				result[occupied] = true
	return _sorted_cells(result.keys())


func _sorted_cells(raw: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for item in raw:
		if item is Vector2i:
			result.append(item)
	result.sort_custom(func(a: Vector2i, b: Vector2i): return a.x < b.x or (a.x == b.x and a.y < b.y))
	return result


func _cells_overlap(a: Array, b: Array) -> bool:
	var seen := {}
	for cell in a:
		seen[cell] = true
	for cell in b:
		if seen.has(cell):
			return true
	return false


func _rect_contains_rect(outer: Rect2, inner: Rect2) -> bool:
	return outer.has_point(inner.position) and inner.end.x <= outer.end.x + 0.01 and inner.end.y <= outer.end.y + 0.01


func _instantiate_village(world_position: Vector2, owner: String, parent: Node2D) -> void:
	var instance := template.scene.instantiate() as Node2D
	if instance == null:
		return
	instance.set_meta("generated_object_id", owner)
	parent.add_child(instance)
	instance.position = parent.to_local(world_position)
	if instance.has_method("generate_from_poi"):
		instance.call("generate_from_poi", owner)


func _fail(reason: String) -> void:
	if not blocking_errors.has(reason):
		blocking_errors.append(reason)
	_generated = true


func get_generation_compatibility_profile() -> Dictionary:
	return template.compatibility_profile() if template != null else {"id": "poi:missing"}


func get_generation_output_manifest() -> Dictionary:
	return {
		"id": "poi_placement_v3",
		"minimum_required": minimum_accepted_pois,
		"occupancy_hash": GenerationHashes.sha256_of(occupancy.canonical_manifest()),
		"candidate_hash": GenerationHashes.sha256_of(candidates),
		"placement_hash": GenerationHashes.sha256_of(accepted),
		"candidates": candidates,
		"accepted": accepted
	}
