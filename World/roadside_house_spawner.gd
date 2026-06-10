extends Node2D

const GENERATED_GROUP: StringName = &"generated_world_object"

@export var enabled: bool = true
@export var road_layer_path: NodePath = NodePath("../../Y-Sort_Objects/RoadLayer")
@export var spawn_parent_path: NodePath = NodePath("../../Y-Sort_Objects/GeneratedForesterHouses")
@export var road_generator_path: NodePath = NodePath("../ChunkLayerGenerator_Road")
@export var wait_for_tile_generators: bool = true
@export var road_house_scenes: Array[PackedScene] = [
	preload("res://World/Assets/Houses/House1/house_1.tscn"),
	preload("res://World/Assets/Houses/TwoStoriedHouse/twoStoriedHouse.tscn")
]
@export_range(1, 4, 1) var internal_margin_chunks: int = 1
@export_range(3, 64, 1) var min_straight_segment_tiles: int = 6
@export_range(1, 24, 1) var house_spacing_tiles: int = 4
@export_range(16.0, 256.0, 1.0) var house_spacing_reference_px: float = 60.0
@export_range(32.0, 1024.0, 1.0) var roadside_offset_px: float = 190.0
@export_range(1, 32, 1) var max_houses_to_spawn: int = 6
@export_range(1, 8, 1) var max_house_slots_per_step: int = 1
@export_range(0.25, 16.0, 0.25) var generation_step_time_budget_ms: float = 2.0
@export var debug_log: bool = false

var _road_layer: TileMapLayer
var _spawn_parent: Node2D
var _road_generator: Node
var _generation_done: bool = false
var _spawned_scene_counts: Dictionary = {}
var _last_debug_stats: Dictionary = {}
var _generation_job: Dictionary = {}
var _scene_collision_shape_cache: Dictionary = {}


func _ready() -> void:
	_resolve_nodes()
	set_process(enabled)


func _process(_delta: float) -> void:
	force_generate_step()


func has_generation_pending() -> bool:
	return enabled and not _generation_done


func get_pending_generation_chunk_count() -> int:
	return 0 if _generation_done or not enabled else 1


func force_generate_step(_chunk_budget: int = -1) -> void:
	if not enabled or _generation_done:
		return
	_resolve_nodes()
	if _road_layer == null or _spawn_parent == null or road_house_scenes.is_empty():
		return
	if _is_road_generation_pending() or _has_pending_tile_generation_dependencies():
		return
	if _generation_job.is_empty():
		_start_roadside_house_job()
	if _generation_done:
		return
	_process_roadside_house_job(_chunk_budget)


func get_debug_world_generation_info() -> Dictionary:
	return {
		"type": "spawner",
		"name": name,
		"loaded_chunks": [],
		"spawn_scene_counts": _spawned_scene_counts.duplicate(),
		"roadside_stats": _last_debug_stats.duplicate()
	}


func _resolve_nodes() -> void:
	_road_layer = get_node_or_null(road_layer_path) as TileMapLayer
	_spawn_parent = get_node_or_null(spawn_parent_path) as Node2D
	_road_generator = get_node_or_null(road_generator_path)


func _start_roadside_house_job() -> void:
	var road_cells := _road_layer.get_used_cells()
	if road_cells.is_empty():
		_finish_roadside_house_job({
			"road_cells": 0,
			"segments": 0,
			"spacing_px": _get_house_spacing_px(),
			"candidate_attempts": 0,
			"rejected_attempts": 0,
			"spawned": 0
		})
		return

	var road_set: Dictionary = {}
	for cell in road_cells:
		road_set[cell] = true

	var segments := _collect_candidate_segments(road_set)
	if segments.is_empty():
		if debug_log:
			push_warning("RoadsideHouseSpawner: no internal straight road segment found.")
		_finish_roadside_house_job({
			"road_cells": road_cells.size(),
			"segments": 0,
			"spacing_px": _get_house_spacing_px(),
			"candidate_attempts": 0,
			"rejected_attempts": 0,
			"spawned": 0
		})
		return

	_generation_job = {
		"segment_list": segments,
		"road_cells": road_cells.size(),
		"segments": segments.size(),
		"spacing_px": _get_house_spacing_px(),
		"candidate_attempts": 0,
		"rejected_attempts": 0,
		"spawned": 0,
		"scene_index": 0,
		"side_index": 0,
		"segment_index": 0,
		"travel_px": -1.0
	}


func _process_roadside_house_job(chunk_budget: int) -> void:
	if _generation_job.is_empty():
		return
	var segments: Array = _generation_job.get("segment_list", [])
	var segment_index := int(_generation_job.get("segment_index", 0))
	var travel_px := float(_generation_job.get("travel_px", -1.0))
	var spawned := int(_generation_job.get("spawned", 0))
	var scene_index := int(_generation_job.get("scene_index", 0))
	var side_index := int(_generation_job.get("side_index", 0))
	var candidate_attempts := int(_generation_job.get("candidate_attempts", 0))
	var rejected_attempts := int(_generation_job.get("rejected_attempts", 0))
	var spacing_px := float(_generation_job.get("spacing_px", _get_house_spacing_px()))
	var slot_budget := max_house_slots_per_step
	if chunk_budget > 0:
		slot_budget = mini(slot_budget, chunk_budget)
	slot_budget = maxi(1, slot_budget)
	var slots_processed := 0
	var step_start_usec := Time.get_ticks_usec()
	var time_budget_usec := int(maxf(generation_step_time_budget_ms, 0.25) * 1000.0)

	while slots_processed < slot_budget and spawned < max_houses_to_spawn:
		if Time.get_ticks_usec() - step_start_usec >= time_budget_usec:
			break
		if segment_index >= segments.size():
			break

		var segment := segments[segment_index] as Array
		if segment.is_empty():
			segment_index += 1
			travel_px = -1.0
			continue

		var axis := _segment_axis(segment)
		var normals := [Vector2i.UP, Vector2i.DOWN] if axis == Vector2i.RIGHT else [Vector2i.LEFT, Vector2i.RIGHT]
		var segment_start_world := _get_road_cell_world(segment[0] as Vector2i)
		var segment_end_world := _get_road_cell_world(segment[segment.size() - 1] as Vector2i)
		var direction := segment_end_world - segment_start_world
		var segment_length_px := direction.length()
		if segment_length_px <= 0.0:
			segment_index += 1
			travel_px = -1.0
			continue
		direction /= segment_length_px

		if travel_px < 0.0:
			travel_px = minf(
				segment_length_px * 0.5,
				maxf(_get_road_step_world_px(axis) * 0.5, spacing_px * 0.5)
			)
		if travel_px >= segment_length_px:
			segment_index += 1
			travel_px = -1.0
			continue

		var scene := _get_next_valid_scene(scene_index)
		if scene == null:
			segment_index = segments.size()
			break
		var road_world := segment_start_world + direction * travel_px
		var ordered_normals := [normals[side_index % normals.size()], normals[(side_index + 1) % normals.size()]]
		var placed := false
		for normal in ordered_normals:
			candidate_attempts += 1
			var candidate_pos := road_world + Vector2(normal) * roadside_offset_px
			if not _can_place_house_scene(scene, candidate_pos):
				rejected_attempts += 1
				continue
			_spawn_house_scene(scene, candidate_pos, spawned)
			spawned += 1
			scene_index += 1
			side_index += 1
			placed = true
			break
		if not placed:
			scene_index += 1
		travel_px += spacing_px
		slots_processed += 1

	_generation_job["segment_index"] = segment_index
	_generation_job["travel_px"] = travel_px
	_generation_job["spawned"] = spawned
	_generation_job["scene_index"] = scene_index
	_generation_job["side_index"] = side_index
	_generation_job["candidate_attempts"] = candidate_attempts
	_generation_job["rejected_attempts"] = rejected_attempts

	if spawned >= max_houses_to_spawn or segment_index >= segments.size():
		_finish_roadside_house_job(_generation_job)


func _finish_roadside_house_job(stats: Dictionary) -> void:
	_last_debug_stats = {
		"road_cells": int(stats.get("road_cells", 0)),
		"segments": int(stats.get("segments", 0)),
		"spacing_px": float(stats.get("spacing_px", _get_house_spacing_px())),
		"candidate_attempts": int(stats.get("candidate_attempts", 0)),
		"rejected_attempts": int(stats.get("rejected_attempts", 0)),
		"spawned": int(stats.get("spawned", 0))
	}
	_generation_job.clear()
	_generation_done = true
	set_process(false)
	if debug_log:
		print("[RoadsideHouseSpawner] road_cells=%d segments=%d spacing_px=%.1f attempts=%d rejected=%d spawned=%d" % [
			int(_last_debug_stats.get("road_cells", 0)),
			int(_last_debug_stats.get("segments", 0)),
			float(_last_debug_stats.get("spacing_px", 0.0)),
			int(_last_debug_stats.get("candidate_attempts", 0)),
			int(_last_debug_stats.get("rejected_attempts", 0)),
			int(_last_debug_stats.get("spawned", 0))
		])

	if debug_log and int(_last_debug_stats.get("spawned", 0)) == 0:
		push_warning("RoadsideHouseSpawner: failed to place any roadside houses.")


func _is_road_generation_pending() -> bool:
	return (
		_road_generator != null
		and _road_generator.has_method("has_generation_pending")
		and bool(_road_generator.call("has_generation_pending"))
	)


func _has_pending_tile_generation_dependencies() -> bool:
	if not wait_for_tile_generators:
		return false
	var generation_root := get_parent()
	if generation_root == null:
		return false
	for sibling in generation_root.get_children():
		if sibling == self or not _is_tile_generation_source(sibling):
			continue
		if bool(sibling.call("has_generation_pending")):
			return true
	return false


func _is_tile_generation_source(source: Node) -> bool:
	if source == null or not source.has_method("has_generation_pending"):
		return false
	if source.has_method("is_world_generation_tile_source"):
		return bool(source.call("is_world_generation_tile_source"))
	return not source is Node2D


func _collect_candidate_segments(road_set: Dictionary) -> Array:
	var scored_segments: Array = []
	var center_chunk := _get_internal_center_chunk()

	for cell_variant in road_set.keys():
		var cell := cell_variant as Vector2i
		if not _is_internal_road_cell(cell):
			continue

		for axis in [Vector2i.RIGHT, Vector2i.DOWN]:
			if road_set.has(cell - axis):
				continue
			var segment := _collect_straight_segment(cell, axis, road_set)
			if segment.size() < min_straight_segment_tiles:
				continue
			var segment_center := segment[int(segment.size() / 2)] as Vector2i
			var segment_chunk := _cell_to_chunk(segment_center)
			var distance := float((segment_chunk - center_chunk).length_squared())
			scored_segments.append({
				"segment": segment,
				"distance": distance
			})

	if scored_segments.is_empty():
		return []

	for i in range(scored_segments.size()):
		var best_index := i
		for j in range(i + 1, scored_segments.size()):
			var best_item := scored_segments[best_index] as Dictionary
			var candidate_item := scored_segments[j] as Dictionary
			var best_segment := best_item.get("segment", []) as Array
			var candidate_segment := candidate_item.get("segment", []) as Array
			var candidate_is_better := false
			if candidate_segment.size() > best_segment.size():
				candidate_is_better = true
			elif candidate_segment.size() == best_segment.size():
				var candidate_distance := float(candidate_item.get("distance", INF))
				var best_distance := float(best_item.get("distance", INF))
				if candidate_distance < best_distance:
					candidate_is_better = true
				elif is_equal_approx(candidate_distance, best_distance):
					var candidate_first := candidate_segment[0] as Vector2i
					var best_first := best_segment[0] as Vector2i
					candidate_is_better = (
						candidate_first.y < best_first.y
						or (candidate_first.y == best_first.y and candidate_first.x < best_first.x)
					)
			if candidate_is_better:
				best_index = j
		if best_index != i:
			var temp = scored_segments[i]
			scored_segments[i] = scored_segments[best_index]
			scored_segments[best_index] = temp

	var result: Array = []
	for item in scored_segments:
		result.append(item.get("segment", []))
	return result


func _collect_straight_segment(start: Vector2i, axis: Vector2i, road_set: Dictionary) -> Array[Vector2i]:
	var segment: Array[Vector2i] = []
	var current := start
	while road_set.has(current):
		segment.append(current)
		current += axis
	return segment


func _segment_axis(segment: Array) -> Vector2i:
	if segment.size() < 2:
		return Vector2i.RIGHT
	var first := segment[0] as Vector2i
	var second := segment[1] as Vector2i
	return Vector2i.RIGHT if first.y == second.y else Vector2i.DOWN


func _is_internal_road_cell(cell: Vector2i) -> bool:
	var info := _get_road_generator_info()
	if info.is_empty():
		return true
	var min_chunk := info.get("world_min_chunk", Vector2i.ZERO) as Vector2i
	var max_chunk := info.get("world_max_chunk", Vector2i.ZERO) as Vector2i
	var chunk := _cell_to_chunk(cell)
	return (
		chunk.x >= min_chunk.x + internal_margin_chunks
		and chunk.x <= max_chunk.x - internal_margin_chunks
		and chunk.y >= min_chunk.y + internal_margin_chunks
		and chunk.y <= max_chunk.y - internal_margin_chunks
	)


func _cell_to_chunk(cell: Vector2i) -> Vector2i:
	var chunk_size := _get_road_chunk_size_tiles()
	return Vector2i(
		floori(float(cell.x) / float(chunk_size)),
		floori(float(cell.y) / float(chunk_size))
	)


func _get_internal_center_chunk() -> Vector2i:
	var info := _get_road_generator_info()
	if info.is_empty():
		return Vector2i.ZERO
	var min_chunk := info.get("world_min_chunk", Vector2i.ZERO) as Vector2i
	var max_chunk := info.get("world_max_chunk", Vector2i.ZERO) as Vector2i
	return Vector2i(
		int(floor((min_chunk.x + max_chunk.x) * 0.5)),
		int(floor((min_chunk.y + max_chunk.y) * 0.5))
	)


func _get_road_chunk_size_tiles() -> int:
	var info := _get_road_generator_info()
	if info.is_empty():
		return 16
	return maxi(1, int(info.get("chunk_size_tiles", 16)))


func _get_road_generator_info() -> Dictionary:
	if _road_generator == null or not _road_generator.has_method("get_debug_world_generation_info"):
		return {}
	var info: Variant = _road_generator.call("get_debug_world_generation_info")
	return info as Dictionary if info is Dictionary else {}


func _get_house_spacing_px() -> float:
	return maxf(16.0, float(house_spacing_tiles) * maxf(house_spacing_reference_px, 1.0))


func _get_road_cell_world(cell: Vector2i) -> Vector2:
	return _road_layer.to_global(_road_layer.map_to_local(cell))


func _get_road_step_world_px(axis: Vector2i) -> float:
	if _road_layer == null:
		return maxf(house_spacing_reference_px, 1.0)
	return maxf((_get_road_cell_world(axis) - _get_road_cell_world(Vector2i.ZERO)).length(), 1.0)


func _get_next_valid_scene(index: int) -> PackedScene:
	if road_house_scenes.is_empty():
		return null
	for offset in range(road_house_scenes.size()):
		var scene := road_house_scenes[(index + offset) % road_house_scenes.size()]
		if scene != null:
			return scene
	return null


func _can_place_house_scene(scene: PackedScene, world_pos: Vector2) -> bool:
	if scene == null:
		return false
	var shape_entries := _get_cached_collision_shape_entries(scene)
	if shape_entries.is_empty():
		return false

	var space_state := get_world_2d().direct_space_state
	for entry in shape_entries:
		var params := PhysicsShapeQueryParameters2D.new()
		params.shape = entry["shape"]
		params.transform = Transform2D(0.0, world_pos) * (entry["transform"] as Transform2D)
		params.collide_with_bodies = true
		params.collide_with_areas = true
		params.collision_mask = 0x7fffffff
		var hits := space_state.intersect_shape(params, 16)
		for hit_value in hits:
			if not (hit_value is Dictionary):
				continue
			var collider: Object = (hit_value as Dictionary).get("collider", null)
			if collider == null or collider == _road_layer or collider == self:
				continue
			return false
	return true


func _get_cached_collision_shape_entries(scene: PackedScene) -> Array:
	if scene == null:
		return []
	var cache_key := scene.resource_path
	if cache_key.is_empty():
		cache_key = "scene:%d" % int(scene.get_instance_id())
	if _scene_collision_shape_cache.has(cache_key):
		return _scene_collision_shape_cache[cache_key] as Array

	var preview := scene.instantiate() as Node2D
	if preview == null:
		_scene_collision_shape_cache[cache_key] = []
		return []
	var shape_entries := _collect_collision_shape_entries(preview, Transform2D.IDENTITY)
	preview.free()
	_scene_collision_shape_cache[cache_key] = shape_entries
	return shape_entries


func _collect_collision_shape_entries(node: Node, parent_transform: Transform2D) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var node_transform := parent_transform
	if node is Node2D:
		node_transform = parent_transform * (node as Node2D).transform
	if node is CollisionShape2D:
		var collision_shape := node as CollisionShape2D
		if not collision_shape.disabled and collision_shape.shape != null:
			entries.append({
				"shape": collision_shape.shape,
				"transform": node_transform
			})
	for child in node.get_children():
		var child_entries := _collect_collision_shape_entries(child, node_transform)
		for entry in child_entries:
			entries.append(entry)
	return entries


func _spawn_house_scene(scene: PackedScene, world_pos: Vector2, spawned_index: int) -> void:
	var house := scene.instantiate() as Node2D
	if house == null:
		return
	var object_id := "roadside_house:%d:%s" % [spawned_index, scene.resource_path]
	house.set_meta("world_generation_id", object_id)
	house.set_meta("world_generation_scene_path", scene.resource_path)
	house.add_to_group(GENERATED_GROUP)
	if "persistent_id" in house:
		house.persistent_id = object_id
	house.position = _spawn_parent.to_local(world_pos)
	_spawn_parent.add_child(house)
	var scene_key := scene.resource_path if not scene.resource_path.is_empty() else scene.resource_name
	_spawned_scene_counts[scene_key] = int(_spawned_scene_counts.get(scene_key, 0)) + 1
