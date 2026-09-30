class_name WaterGenerationPass
extends Node

const PHASE := "water"
const GENERATED_CELLS_META := &"world_generation_water_cells"
const CARDINAL_DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const WATER_VISUAL_RENDERER := preload("res://World/Generation/water_visual_renderer.gd")

@export var enabled := true
@export var profile: Resource
@export var world_bounds_source_path: NodePath = NodePath("../ChunkWorldGenerator")
@export var water_layer_path: NodePath = NodePath("../../Y-Sort_Objects/LakeLayer")
@export var player_path: NodePath = NodePath("../../Y-Sort_Objects/Player2")

var blocking_errors: Array[String] = []
var generated_cells: Array[Vector2i] = []
var lake_components: Array[Array] = []
var _generated := false


func get_generation_phase() -> String:
	return PHASE


func has_generation_pending() -> bool:
	return enabled and not _generated


func run_generation_pass() -> void:
	if not enabled or _generated:
		return
	blocking_errors.clear()
	var check: Dictionary = profile.call("validate") if profile != null and profile.has_method("validate") else {"valid": false, "errors": ["MISSING_PROFILE"]}
	if not bool(check.get("valid", false)):
		_blocking("INVALID_PROFILE:%s" % ",".join(check.get("errors", [])))
		return
	var layer := get_node_or_null(water_layer_path) as TileMapLayer
	if not _validate_layer(layer):
		return
	var bounds := _resolve_world_cell_bounds()
	if bounds.size.x <= profile.border_margin_cells * 2 or bounds.size.y <= profile.border_margin_cells * 2:
		_blocking("WORLD_BOUNDS_TOO_SMALL")
		return
	_clear_previous_generated_cells(layer)
	var excluded := _player_exclusion(layer, bounds)
	var result := build_cells_for_inputs(bounds, _resolve_master_seed(), excluded)
	generated_cells.assign(result.get("cells", []))
	lake_components.assign(result.get("components", []))
	if lake_components.size() < profile.min_lakes:
		_blocking("MIN_LAKES_NOT_REACHED:%d/%d" % [lake_components.size(), profile.min_lakes])
		return
	layer.set_cells_terrain_connect(generated_cells, profile.terrain_set_id, profile.terrain_id, profile.terrain_ignore_empty)
	layer.set_meta(GENERATED_CELLS_META, generated_cells.duplicate())
	WATER_VISUAL_RENDERER.rebuild(layer, lake_components)
	_generated = true


func build_cells_for_inputs(bounds: Rect2i, master_seed: int, excluded_cells: Dictionary = {}) -> Dictionary:
	var target_count: int = int(profile.min_lakes)
	if profile.max_lakes > profile.min_lakes:
		target_count += posmod(WorldSeedService.derive_seed(master_seed, profile.seed_domain + "/count"), profile.max_lakes - profile.min_lakes + 1)
	var occupied := {}
	var components: Array[Array] = []
	var centers: Array[Vector2i] = []
	var radii: Array[int] = []
	for lake_index in range(target_count):
		for attempt in range(profile.placement_attempts_per_lake):
			var radius := _lake_radius(master_seed, lake_index, attempt)
			var center := _candidate_center(bounds, master_seed, lake_index, attempt, radius)
			if _center_is_blocked(center, radius, centers, radii, excluded_cells):
				continue
			var cells := _build_lake_blob(bounds, center, radius, master_seed, lake_index, attempt)
			cells = _connected_component(cells, center)
			if cells.size() < profile.minimum_lake_cells or _contains_any(cells, excluded_cells):
				continue
			components.append(cells)
			centers.append(center)
			radii.append(radius)
			for cell in cells:
				occupied[cell] = true
			break
	var cells: Array[Vector2i] = []
	for cell in occupied.keys():
		cells.append(cell as Vector2i)
	cells.sort_custom(_cell_less)
	return {"cells": cells, "components": components, "centers": centers}


func get_generation_compatibility_profile() -> Dictionary:
	return profile.compatibility_profile() if profile != null else {"id": "water_profile:missing"}


func get_generation_output_manifest() -> Dictionary:
	var components: Array[Dictionary] = []
	for index in range(lake_components.size()):
		var cells: Array = lake_components[index].duplicate()
		cells.sort_custom(_cell_less)
		components.append({"id": "lake:%d" % index, "cells": cells})
	return {
		"id": "water_v1",
		"components": components,
		"cells": generated_cells,
		"water_hash": GenerationHashes.sha256_of(components)
	}


func _build_lake_blob(bounds: Rect2i, center: Vector2i, radius: int, master_seed: int, lake_index: int, attempt: int) -> Array[Vector2i]:
	var lobes: Array[Dictionary] = [{"center": center, "rx": radius, "ry": _axis_radius(radius, master_seed, lake_index, 0)}]
	var lobe_count: int = int(profile.extra_lobes_min)
	if profile.extra_lobes_max > profile.extra_lobes_min:
		lobe_count += posmod(WorldSeedService.derive_seed(master_seed, profile.seed_domain + "/lobes", [lake_index, attempt]), profile.extra_lobes_max - profile.extra_lobes_min + 1)
	for lobe_index in range(lobe_count):
		var lobe_seed := WorldSeedService.derive_seed(master_seed, profile.seed_domain + "/lobe", [lake_index, attempt, lobe_index])
		var direction := CARDINAL_DIRECTIONS[posmod(lobe_seed, CARDINAL_DIRECTIONS.size())]
		var side := Vector2i(-direction.y, direction.x)
		var offset := direction * maxi(1, radius / 3) + side * (posmod(int(lobe_seed / 11), 3) - 1)
		var lobe_radius := maxi(3, radius - 2 - posmod(int(lobe_seed / 17), 3))
		lobes.append({"center": center + offset, "rx": lobe_radius, "ry": _axis_radius(lobe_radius, master_seed, lake_index, lobe_index + 1)})
	var raw := {}
	var extent := radius * 2 + 3
	for y in range(center.y - extent, center.y + extent + 1):
		for x in range(center.x - extent, center.x + extent + 1):
			var cell := Vector2i(x, y)
			if not bounds.has_point(cell):
				continue
			for lobe in lobes:
				var lobe_center := lobe.center as Vector2i
				var dx := float(cell.x - lobe_center.x) / float(lobe.rx)
				var dy := float(cell.y - lobe_center.y) / float(lobe.ry)
				var distance := dx * dx + dy * dy
				if distance <= 0.72 or distance <= 1.0 + _edge_noise(master_seed, lake_index, cell):
					raw[cell] = true
					break
	_fill_small_holes(raw, bounds)
	var result: Array[Vector2i] = []
	for cell in raw.keys():
		result.append(cell as Vector2i)
	return result


func _fill_small_holes(cells: Dictionary, bounds: Rect2i) -> void:
	var additions: Array[Vector2i] = []
	for y in range(bounds.position.y + 1, bounds.end.y - 1):
		for x in range(bounds.position.x + 1, bounds.end.x - 1):
			var cell := Vector2i(x, y)
			if cells.has(cell):
				continue
			var neighbors := 0
			for direction in CARDINAL_DIRECTIONS:
				if cells.has(cell + direction): neighbors += 1
			if neighbors >= 3: additions.append(cell)
	for cell in additions: cells[cell] = true


func _connected_component(cells: Array[Vector2i], center: Vector2i) -> Array[Vector2i]:
	var available := {}
	for cell in cells: available[cell] = true
	if not available.has(center): return []
	var queue: Array[Vector2i] = [center]
	var visited := {center: true}
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		for direction in CARDINAL_DIRECTIONS:
			var next: Vector2i = current + direction
			if available.has(next) and not visited.has(next):
				visited[next] = true
				queue.append(next)
	var result: Array[Vector2i] = []
	for cell in visited.keys(): result.append(cell as Vector2i)
	result.sort_custom(_cell_less)
	return result


func _candidate_center(bounds: Rect2i, master_seed: int, lake_index: int, attempt: int, radius: int) -> Vector2i:
	var shape_extent := radius + maxi(1, radius / 3)
	var inner := bounds.grow(-(int(profile.border_margin_cells) + shape_extent))
	var seed := WorldSeedService.derive_seed(master_seed, profile.seed_domain + "/center", [lake_index, attempt])
	return Vector2i(inner.position.x + posmod(seed, inner.size.x), inner.position.y + posmod(int(seed / 65537), inner.size.y))


func _lake_radius(master_seed: int, lake_index: int, attempt: int) -> int:
	var seed := WorldSeedService.derive_seed(master_seed, profile.seed_domain + "/radius", [lake_index, attempt])
	return profile.radius_min_cells + posmod(seed, profile.radius_max_cells - profile.radius_min_cells + 1)


func _axis_radius(radius: int, master_seed: int, lake_index: int, lobe_index: int) -> int:
	var seed := WorldSeedService.derive_seed(master_seed, profile.seed_domain + "/axis", [lake_index, lobe_index])
	return maxi(3, radius - posmod(seed, maxi(2, radius / 2)))


func _edge_noise(master_seed: int, lake_index: int, cell: Vector2i) -> float:
	var value := posmod(WorldSeedService.derive_seed(master_seed, profile.seed_domain + "/edge", [lake_index, cell.x, cell.y]), 2001) - 1000
	return float(value) / 1000.0 * profile.edge_jitter


func _center_is_blocked(center: Vector2i, radius: int, centers: Array[Vector2i], radii: Array[int], excluded: Dictionary) -> bool:
	for cell in excluded.keys():
		var blocked := cell as Vector2i
		if center.distance_squared_to(blocked) <= float(radius * radius): return true
	for index in range(centers.size()):
		var required: int = radius + radii[index] + int(profile.lake_spacing_cells)
		if center.distance_squared_to(centers[index]) < float(required * required): return true
	return false


func _contains_any(cells: Array[Vector2i], blocked: Dictionary) -> bool:
	for cell in cells:
		if blocked.has(cell): return true
	return false


func _player_exclusion(layer: TileMapLayer, bounds: Rect2i) -> Dictionary:
	var result := {}
	var player := get_node_or_null(player_path) as Node2D
	if player == null: return result
	var center := layer.local_to_map(layer.to_local(player.global_position))
	var radius: int = int(profile.player_clearance_cells)
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var cell := Vector2i(x, y)
			if bounds.has_point(cell) and center.distance_squared_to(cell) <= float(radius * radius): result[cell] = true
	return result


func _clear_previous_generated_cells(layer: TileMapLayer) -> void:
	var previous: Variant = layer.get_meta(GENERATED_CELLS_META, [])
	if previous is Array:
		for cell in previous:
			if cell is Vector2i: layer.erase_cell(cell as Vector2i)
	layer.remove_meta(GENERATED_CELLS_META)


func _validate_layer(layer: TileMapLayer) -> bool:
	if layer == null or layer.tile_set == null:
		_blocking("MISSING_WATER_LAYER")
		return false
	if profile.terrain_set_id >= layer.tile_set.get_terrain_sets_count() or profile.terrain_id >= layer.tile_set.get_terrains_count(profile.terrain_set_id):
		_blocking("INVALID_WATER_TERRAIN")
		return false
	return true


func _resolve_world_cell_bounds() -> Rect2i:
	var source := get_node_or_null(world_bounds_source_path)
	var info: Dictionary = source.call("get_debug_world_generation_info") if source != null and source.has_method("get_debug_world_generation_info") else {}
	var min_chunk: Vector2i = info.get("world_min_chunk", Vector2i.ZERO)
	var max_chunk: Vector2i = info.get("world_max_chunk", Vector2i(-1, -1))
	var chunk_size := maxi(1, int(info.get("chunk_size_tiles", 16)))
	return Rect2i(min_chunk * chunk_size, (max_chunk - min_chunk + Vector2i.ONE) * chunk_size)


func _resolve_master_seed() -> int:
	var source := get_node_or_null(world_bounds_source_path)
	var info: Dictionary = source.call("get_debug_world_generation_info") if source != null and source.has_method("get_debug_world_generation_info") else {}
	return int(info.get("seed", 0))


func _blocking(message: String) -> void:
	if not blocking_errors.has(message): blocking_errors.append(message)
	push_error("WaterGenerationPass: " + message)


func _cell_less(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x if a.y == b.y else a.y < b.y
