class_name RoadRasterizationPass
extends Node

const PHASE := "road_raster"
const GENERATED_CELLS_META := &"world_generation_road_cells"
const OCCUPANCY_META := &"world_generation_road_occupancy"
const CARDINAL_DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

@export var enabled := true
@export var profile: RoadGenerationProfile
@export var graph_pass_path: NodePath = NodePath("../RoadGraphPass")
@export var road_layer_path: NodePath = NodePath("../../Y-Sort_Objects/RoadLayer")

var raster_hash := ""
var _generated := false
var _manifest := {}

func get_generation_phase() -> String: return PHASE
func has_generation_pending() -> bool: return enabled and not _generated

func run_generation_pass() -> void:
	if not enabled or _generated: return
	var graph_pass := get_node_or_null(graph_pass_path) as RoadGraphPass
	var layer := get_node_or_null(road_layer_path) as TileMapLayer
	if profile == null or graph_pass == null or graph_pass.graph == null or layer == null:
		push_error("RoadRasterizationPass: graph/profile/RoadLayer is missing")
		return
	var validation := graph_pass.graph.validate()
	if not bool(validation.get("valid", false)):
		push_error("RoadRasterizationPass: refusing invalid RoadGraph")
		return
	_clear_previous(layer)
	var cells := _sorted_cells(graph_pass.graph.cells.keys())
	var raster_cells: Array[Dictionary] = []
	var occupancy := {}
	for cell in cells:
		var atlas := _atlas_for(cell, graph_pass.graph)
		layer.set_cell(cell, profile.source_id, atlas)
		raster_cells.append({"cell": cell, "atlas": atlas, "source_id": profile.source_id})
		occupancy[cell] = "ROAD"
		for y in range(-1, 2):
			for x in range(-1, 2):
				var clearance := cell + Vector2i(x, y)
				if not occupancy.has(clearance): occupancy[clearance] = "ROAD_CLEARANCE"
	layer.set_meta(GENERATED_CELLS_META, cells)
	layer.set_meta(OCCUPANCY_META, occupancy)
	_manifest = {"id": "road_raster_v1", "cells": raster_cells, "occupancy": _canonical_occupancy(occupancy)}
	raster_hash = GenerationHashes.sha256_of(_manifest)
	_generated = true

func get_generation_compatibility_profile() -> Dictionary:
	return {"id": "road_raster_v1", "tileset_uid": GenerationHashes.resource_uid((get_node_or_null(road_layer_path) as TileMapLayer).tile_set) if get_node_or_null(road_layer_path) is TileMapLayer else "", "palette": profile.compatibility_profile().get("raster_palette", {}) if profile != null else {}}

func get_generation_output_manifest() -> Dictionary:
	return {"id": "road_raster_v1", "raster": _manifest, "road_raster_hash": raster_hash}

func get_road_raster_hash() -> String: return raster_hash

func clear_generated() -> void:
	var layer := get_node_or_null(road_layer_path) as TileMapLayer
	if layer != null:
		_clear_previous(layer)
		layer.remove_meta(GENERATED_CELLS_META)
		layer.remove_meta(OCCUPANCY_META)
	_manifest = {}
	raster_hash = ""
	_generated = false

func get_connectivity_diagnostics() -> Dictionary:
	# Diagnostics intentionally read only RoadRaster-owned ROAD occupancy.  Other
	# tiles sharing RoadLayer (including decoration) are not treated as road cells.
	var graph_pass := get_node_or_null(graph_pass_path) as RoadGraphPass
	var layer := get_node_or_null(road_layer_path) as TileMapLayer
	var occupancy: Dictionary = layer.get_meta(OCCUPANCY_META, {}) if layer != null else {}
	var road_cells: Array[Vector2i] = []
	for raw_cell in occupancy.keys():
		var cell := raw_cell as Vector2i
		if String(occupancy[raw_cell]) == "ROAD":
			road_cells.append(cell)
	road_cells = _sorted_cells(road_cells)
	var components := _components(road_cells)
	var isolated: Array[Dictionary] = []
	for cell in road_cells:
		if _road_neighbor_count(cell, road_cells) == 0:
			isolated.append(_diagnostic_cell_record(cell, 1, layer, graph_pass.graph if graph_pass != null else null))
	var small_components: Array[Dictionary] = []
	for component in components:
		if component.size() <= 3:
			var records: Array[Dictionary] = []
			for cell in component:
				records.append(_diagnostic_cell_record(cell, component.size(), layer, graph_pass.graph if graph_pass != null else null))
			small_components.append({"size": component.size(), "cells": records})
	var graph_cells: Array[Vector2i] = []
	if graph_pass != null and graph_pass.graph != null:
		graph_cells = _sorted_cells(graph_pass.graph.cells.keys())
	var graph_components := _components(graph_cells)
	return {
		"road_cells": road_cells,
		"road_component_count": components.size(),
		"graph_component_count": graph_components.size(),
		"isolated_road_cells": isolated,
		"small_disconnected_components": small_components,
		"matches_graph_cells": road_cells == graph_cells,
		"connectivity_matches_graph": components.size() == graph_components.size() and (components.size() <= 1 or road_cells == graph_cells)
	}

func _clear_previous(layer: TileMapLayer) -> void:
	var previous: Variant = layer.get_meta(GENERATED_CELLS_META, [])
	if previous is Array:
		for cell in previous:
			if cell is Vector2i: layer.erase_cell(cell)

func _road_neighbor_count(cell: Vector2i, road_cells: Array[Vector2i]) -> int:
	var set := {}
	for road_cell in road_cells: set[road_cell] = true
	var count := 0
	for direction in CARDINAL_DIRECTIONS:
		if set.has(cell + direction): count += 1
	return count

func _components(cells: Array[Vector2i]) -> Array[Array]:
	var available := {}
	for cell in cells: available[cell] = true
	var components: Array[Array] = []
	for start in cells:
		if not available.has(start): continue
		var component: Array[Vector2i] = []
		var pending: Array[Vector2i] = [start]
		available.erase(start)
		while not pending.is_empty():
			var current: Vector2i = pending.pop_back()
			component.append(current)
			for direction in CARDINAL_DIRECTIONS:
				var neighbor: Vector2i = current + direction
				if available.has(neighbor):
					available.erase(neighbor)
					pending.append(neighbor)
		component = _sorted_cells(component)
		components.append(component)
	components.sort_custom(func(a: Array, b: Array):
		var first_a: Vector2i = a[0]
		var first_b: Vector2i = b[0]
		return first_a.x < first_b.x or (first_a.x == first_b.x and first_a.y < first_b.y))
	return components

func _diagnostic_cell_record(cell: Vector2i, component_size: int, layer: TileMapLayer, graph: RoadGraph) -> Dictionary:
	return {
		"cell": cell,
		"component_size": component_size,
		"tile_source_id": layer.get_cell_source_id(cell) if layer != null else -1,
		"tile_atlas_coords": layer.get_cell_atlas_coords(cell) if layer != null else Vector2i(-1, -1),
		"nearest_graph_segment": _nearest_graph_segment(cell, graph)
	}

func _nearest_graph_segment(cell: Vector2i, graph: RoadGraph) -> String:
	if graph == null or graph.cells.is_empty(): return "<missing>"
	var nearest: Vector2i = _sorted_cells(graph.cells.keys())[0]
	var best_distance: int = abs(cell.x - nearest.x) + abs(cell.y - nearest.y)
	for candidate in _sorted_cells(graph.cells.keys()):
		var distance: int = abs(cell.x - candidate.x) + abs(cell.y - candidate.y)
		if distance < best_distance:
			nearest = candidate
			best_distance = distance
	return graph.node_id(nearest)

func _atlas_for(cell: Vector2i, graph: RoadGraph) -> Vector2i:
	var up := graph.has_cell(cell + Vector2i.UP)
	var down := graph.has_cell(cell + Vector2i.DOWN)
	var left := graph.has_cell(cell + Vector2i.LEFT)
	var right := graph.has_cell(cell + Vector2i.RIGHT)
	var degree := int(up) + int(down) + int(left) + int(right)
	if degree >= 4: return profile.cross_atlas
	if degree == 3:
		if not up: return profile.t_missing_up_atlas
		if not down: return profile.t_missing_down_atlas
		if not left: return profile.t_missing_left_atlas
		return profile.t_missing_right_atlas
	if degree == 2:
		if up and down: return profile.vertical_atlas
		if left and right: return profile.horizontal_atlas
		if up and left: return profile.corner_up_left_atlas
		if up and right: return profile.corner_up_right_atlas
		if down and left: return profile.corner_down_left_atlas
		return profile.corner_down_right_atlas
	if up or down: return profile.vertical_atlas
	return profile.horizontal_atlas

func _sorted_cells(raw: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for item in raw:
		if item is Vector2i: result.append(item)
	result.sort_custom(func(a: Vector2i, b: Vector2i): return a.x < b.x or (a.x == b.x and a.y < b.y))
	return result

func _canonical_occupancy(occupancy: Dictionary) -> Array[Dictionary]:
	var cells := _sorted_cells(occupancy.keys())
	var result: Array[Dictionary] = []
	for cell in cells: result.append({"cell": cell, "claim": occupancy[cell]})
	return result
