extends Node2D

const GENERATED_GROUP: StringName = &"generated_world_object"

@export var enabled: bool = true
@export var road_layer_path: NodePath = NodePath("../../Y-Sort_Objects/RoadLayer")
@export var spawn_parent_path: NodePath = NodePath("../../Y-Sort_Objects/GeneratedForesterHouses")
@export var road_generator_path: NodePath = NodePath("../ChunkLayerGenerator_Road")
@export var road_house_scenes: Array[PackedScene] = [
	preload("res://World/Assets/Houses/House1/house_1.tscn"),
	preload("res://World/Assets/Houses/TwoStoriedHouse/twoStoriedHouse.tscn")
]
@export_range(1, 4, 1) var internal_margin_chunks: int = 1
@export_range(3, 64, 1) var min_straight_segment_tiles: int = 6
@export_range(1, 24, 1) var house_spacing_tiles: int = 4
@export_range(32.0, 1024.0, 1.0) var roadside_offset_px: float = 190.0
@export_range(1, 32, 1) var max_houses_to_spawn: int = 6
@export var debug_log: bool = false

var _road_layer: TileMapLayer
var _spawn_parent: Node2D
var _road_generator: Node
var _generation_done: bool = false
var _spawned_scene_counts: Dictionary = {}


func _ready() -> void:
	_resolve_nodes()
	set_process(false)


func has_generation_pending() -> bool:
	return enabled and not _generation_done


func get_pending_generation_chunk_count() -> int:
	return 0 if _generation_done or not enabled else 1


func force_generate_step(_chunk_budget: int = -1) -> void:
	if not enabled or _generation_done:
		return
	_resolve_nodes()
	_generate_roadside_houses()
	_generation_done = true


func get_debug_world_generation_info() -> Dictionary:
	return {
		"type": "spawner",
		"name": name,
		"loaded_chunks": [],
		"spawn_scene_counts": _spawned_scene_counts.duplicate()
	}


func _resolve_nodes() -> void:
	_road_layer = get_node_or_null(road_layer_path) as TileMapLayer
	_spawn_parent = get_node_or_null(spawn_parent_path) as Node2D
	_road_generator = get_node_or_null(road_generator_path)


func _generate_roadside_houses() -> void:
	if _road_layer == null or _spawn_parent == null or road_house_scenes.is_empty():
		return

	var road_cells := _road_layer.get_used_cells()
	if road_cells.is_empty():
		return

	var road_set: Dictionary = {}
	for cell in road_cells:
		road_set[cell] = true

	var segments := _collect_candidate_segments(road_set)
	if segments.is_empty():
		if debug_log:
			push_warning("RoadsideHouseSpawner: no internal straight road segment found.")
		return

	var spawned := 0
	var scene_index := 0
	var side_index := 0
	for segment_variant in segments:
		var segment := segment_variant as Array
		if segment.is_empty():
			continue
		if spawned >= max_houses_to_spawn:
			break
		var axis := _segment_axis(segment)
		var normals := [Vector2i.UP, Vector2i.DOWN] if axis == Vector2i.RIGHT else [Vector2i.LEFT, Vector2i.RIGHT]
		var start_index := mini(maxi(1, int(floor(house_spacing_tiles * 0.5))), maxi(1, segment.size() - 1))

		for i in range(start_index, segment.size() - 1, maxi(1, house_spacing_tiles)):
			if spawned >= max_houses_to_spawn:
				break
			var road_cell := segment[i] as Vector2i
			var road_world := _road_layer.to_global(_road_layer.map_to_local(road_cell))
			var scene := _get_next_valid_scene(scene_index)
			if scene == null:
				break

			var ordered_normals := [normals[side_index % normals.size()], normals[(side_index + 1) % normals.size()]]
			var placed := false
			for normal in ordered_normals:
				var candidate_pos := road_world + Vector2(normal) * roadside_offset_px
				if not _can_place_house_scene(scene, candidate_pos):
					continue
				_spawn_house_scene(scene, candidate_pos, spawned)
				spawned += 1
				scene_index += 1
				side_index += 1
				placed = true
				break
			if not placed:
				scene_index += 1

	if debug_log and spawned == 0:
		push_warning("RoadsideHouseSpawner: failed to place any roadside houses.")


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
				candidate_is_better = float(candidate_item.get("distance", INF)) < float(best_item.get("distance", INF))
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
	var preview := scene.instantiate() as Node2D
	if preview == null:
		return false
	var shape_entries := _collect_collision_shape_entries(preview, Transform2D(0.0, world_pos))
	preview.free()
	if shape_entries.is_empty():
		return false

	var space_state := get_world_2d().direct_space_state
	for entry in shape_entries:
		var params := PhysicsShapeQueryParameters2D.new()
		params.shape = entry["shape"]
		params.transform = entry["transform"]
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
	_spawn_parent.add_child(house)
	house.global_position = world_pos
	var scene_key := scene.resource_path if not scene.resource_path.is_empty() else scene.resource_name
	_spawned_scene_counts[scene_key] = int(_spawned_scene_counts.get(scene_key, 0)) + 1
