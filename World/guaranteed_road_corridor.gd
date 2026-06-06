extends Node2D

const GENERATED_GROUP: StringName = &"generated_world_object"
const META_GENERATED_CELLS: StringName = &"world_generation_generated_cells"

@export var enabled: bool = true
@export var player_path: NodePath = NodePath("../../Y-Sort_Objects/Player2")
@export var road_layer_path: NodePath = NodePath("../../Y-Sort_Objects/RoadLayer")
@export var spawn_parent_path: NodePath = NodePath("../../Y-Sort_Objects/GeneratedForesterHouses")
@export_range(4, 256, 1) var chunk_size_tiles: int = 16
@export_range(1, 64, 1) var world_chunks_x: int = 6
@export_range(1, 64, 1) var world_chunks_y: int = 6
@export_range(1, 4, 1) var edge_margin_chunks: int = 1
@export_range(1, 8, 1) var road_width_tiles: int = 2
@export_range(1, 8, 1) var road_margin_inside_chunk_tiles: int = 3
@export_range(1, 24, 1) var house_spacing_tiles: int = 5
@export_range(0.0, 512.0, 1.0) var roadside_house_margin_px: float = 28.0
@export_range(1, 32, 1) var max_houses_to_spawn: int = 8
@export var road_house_scenes: Array[PackedScene] = [
	preload("res://World/Assets/Houses/House1/house_1.tscn"),
	preload("res://World/Assets/Houses/TwoStoriedHouse/twoStoriedHouse.tscn")
]
@export var debug_log: bool = false

var _player: Node2D
var _road_layer: TileMapLayer
var _spawn_parent: Node2D
var _generated: bool = false
var _spawned_scene_counts: Dictionary = {}


func _ready() -> void:
	_resolve_nodes()
	set_process(false)


func has_generation_pending() -> bool:
	return enabled and not _generated


func get_pending_generation_chunk_count() -> int:
	return 0 if _generated or not enabled else 1


func force_generate_step(_chunk_budget: int = -1) -> void:
	if not enabled or _generated:
		return
	_resolve_nodes()
	if _player == null or _road_layer == null:
		return
	_generate_corridor_and_houses()
	_generated = true


func get_debug_world_generation_info() -> Dictionary:
	return {
		"type": "spawner",
		"name": name,
		"loaded_chunks": [],
		"spawn_scene_counts": _spawned_scene_counts.duplicate()
	}


func _resolve_nodes() -> void:
	_player = get_node_or_null(player_path) as Node2D
	_road_layer = get_node_or_null(road_layer_path) as TileMapLayer
	_spawn_parent = get_node_or_null(spawn_parent_path) as Node2D


func _generate_corridor_and_houses() -> void:
	var corridor_cells: Array[Vector2i] = _build_corridor_cells()
	if corridor_cells.is_empty():
		if debug_log:
			push_warning("GuaranteedRoadCorridor: no corridor cells were generated.")
		return

	_road_layer.clear()
	_paint_corridor_cells(corridor_cells)
	_mark_generated_cells(corridor_cells)
	_spawn_roadside_houses(corridor_cells)


func _build_corridor_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var world_bounds: Dictionary = _get_world_chunk_bounds()
	var min_chunk: Vector2i = world_bounds["min"] as Vector2i
	var max_chunk: Vector2i = world_bounds["max"] as Vector2i
	var interior_min: Vector2i = min_chunk + Vector2i(edge_margin_chunks, edge_margin_chunks)
	var interior_max: Vector2i = max_chunk - Vector2i(edge_margin_chunks, edge_margin_chunks)
	if interior_min.x > interior_max.x or interior_min.y > interior_max.y:
		interior_min = min_chunk
		interior_max = max_chunk

	var corridor_seed := _get_corridor_seed()
	var orientation_hash: int = _stable_hash(world_chunks_x * 17 + corridor_seed, world_chunks_y * 29 + corridor_seed, 9103)
	var horizontal: bool = true
	if (interior_max.y - interior_min.y) > 0 and (interior_max.x - interior_min.x) > 0:
		horizontal = (orientation_hash % 2) == 0
	elif (interior_max.y - interior_min.y) > 0:
		horizontal = false

	var width: int = maxi(1, road_width_tiles)
	if horizontal:
		var chunk_y: int = interior_min.y + posmod(_stable_hash(11 + corridor_seed, 37 + corridor_seed, 9209), interior_max.y - interior_min.y + 1)
		var local_y: int = clampi(int(chunk_size_tiles / 2), road_margin_inside_chunk_tiles, chunk_size_tiles - road_margin_inside_chunk_tiles - 1)
		var world_y := chunk_y * chunk_size_tiles + local_y
		var start_x := interior_min.x * chunk_size_tiles + road_margin_inside_chunk_tiles
		var end_x := (interior_max.x + 1) * chunk_size_tiles - road_margin_inside_chunk_tiles - 1
		for x in range(start_x, end_x + 1):
			for offset in range(width):
				cells.append(Vector2i(x, world_y + offset))
	else:
		var chunk_x: int = interior_min.x + posmod(_stable_hash(19 + corridor_seed, 43 + corridor_seed, 9281), interior_max.x - interior_min.x + 1)
		var local_x: int = clampi(int(chunk_size_tiles / 2), road_margin_inside_chunk_tiles, chunk_size_tiles - road_margin_inside_chunk_tiles - 1)
		var world_x := chunk_x * chunk_size_tiles + local_x
		var start_y := interior_min.y * chunk_size_tiles + road_margin_inside_chunk_tiles
		var end_y := (interior_max.y + 1) * chunk_size_tiles - road_margin_inside_chunk_tiles - 1
		for y in range(start_y, end_y + 1):
			for offset in range(width):
				cells.append(Vector2i(world_x + offset, y))
	return cells


func _spawn_roadside_houses(corridor_cells: Array[Vector2i]) -> void:
	if _spawn_parent == null or road_house_scenes.is_empty():
		return

	var horizontal: bool = _is_horizontal_corridor(corridor_cells)
	var sorted_cells: Array[Vector2i] = corridor_cells.duplicate()
	sorted_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if horizontal else a.y < b.y
	)

	var unique_centers: Array[Vector2i] = []
	var seen: Dictionary = {}
	for cell_variant in sorted_cells:
		var cell := cell_variant as Vector2i
		var key: int = cell.x if horizontal else cell.y
		if seen.has(key):
			continue
		seen[key] = true
		unique_centers.append(cell)

	var spawned: int = 0
	var scene_cursor: int = 0
	var side_toggle: int = 0
	var normals: Array[Vector2i] = []
	var road_half_width_px: float = _get_road_half_width_px()
	if horizontal:
		normals.append(Vector2i.UP)
		normals.append(Vector2i.DOWN)
	else:
		normals.append(Vector2i.LEFT)
		normals.append(Vector2i.RIGHT)

	for i in range(0, unique_centers.size(), maxi(1, house_spacing_tiles)):
		if spawned >= max_houses_to_spawn:
			break
		var road_cell := unique_centers[i] as Vector2i
		var road_world: Vector2 = _road_layer.to_global(_road_layer.map_to_local(road_cell))
		var scene: PackedScene = _next_house_scene(scene_cursor)
		if scene == null:
			break
		var order: Array[Vector2i] = []
		order.append(normals[side_toggle % 2])
		order.append(normals[(side_toggle + 1) % 2])
		for normal in order:
			var house_half_extent_px: float = _get_scene_half_extent_along_normal(scene, normal)
			var offset_px: float = road_half_width_px + house_half_extent_px + roadside_house_margin_px
			var pos: Vector2 = road_world + Vector2(normal) * offset_px
			if not _can_place_house(scene, pos):
				continue
			_spawn_house(scene, pos, spawned)
			spawned += 1
			side_toggle += 1
			break
		scene_cursor += 1


func _next_house_scene(index: int) -> PackedScene:
	if road_house_scenes.is_empty():
		return null
	for offset in range(road_house_scenes.size()):
		var scene: PackedScene = road_house_scenes[(index + offset) % road_house_scenes.size()]
		if scene != null:
			return scene
	return null


func _can_place_house(scene: PackedScene, world_pos: Vector2) -> bool:
	var preview := scene.instantiate() as Node2D
	if preview == null:
		return false
	var shapes := _collect_collision_shapes(preview, Transform2D(0.0, world_pos))
	var world_rect := _get_shape_entries_rect(shapes)
	preview.free()
	if shapes.is_empty():
		return false
	if _road_rect_has_tiles(world_rect):
		return false

	var space_state := get_world_2d().direct_space_state
	for shape_entry in shapes:
		var params := PhysicsShapeQueryParameters2D.new()
		params.shape = shape_entry["shape"] as Shape2D
		params.transform = shape_entry["transform"] as Transform2D
		params.collide_with_bodies = true
		params.collide_with_areas = true
		params.collision_mask = 0x7fffffff
		var hits: Array = space_state.intersect_shape(params, 16)
		for hit_variant in hits:
			if not (hit_variant is Dictionary):
				continue
			var hit := hit_variant as Dictionary
			var collider: Object = hit.get("collider", null)
			if collider == null or collider == self or collider == _road_layer:
				continue
			return false
	return true


func _get_scene_half_extent_along_normal(scene: PackedScene, normal: Vector2i) -> float:
	var preview := scene.instantiate() as Node2D
	if preview == null:
		return 0.0
	var shapes := _collect_collision_shapes(preview, Transform2D.IDENTITY)
	var rect := _get_shape_entries_rect(shapes)
	preview.free()
	if rect.size == Vector2.ZERO:
		return 0.0
	if normal == Vector2i.LEFT or normal == Vector2i.RIGHT:
		return rect.size.x * 0.5
	return rect.size.y * 0.5


func _get_shape_entries_rect(shape_entries: Array[Dictionary]) -> Rect2:
	var has_rect := false
	var min_pos := Vector2.ZERO
	var max_pos := Vector2.ZERO
	for entry in shape_entries:
		var shape := entry.get("shape", null) as Shape2D
		var transform := entry.get("transform", Transform2D.IDENTITY) as Transform2D
		if shape == null:
			continue
		var rect := Rect2()
		if shape is RectangleShape2D:
			var rectangle := shape as RectangleShape2D
			var half := rectangle.size * 0.5
			var corners: Array[Vector2] = [
				transform * Vector2(-half.x, -half.y),
				transform * Vector2(half.x, -half.y),
				transform * Vector2(half.x, half.y),
				transform * Vector2(-half.x, half.y)
			]
			rect = Rect2(corners[0], Vector2.ZERO)
			for corner in corners:
				rect = rect.expand(corner)
		else:
			continue
		if not has_rect:
			min_pos = rect.position
			max_pos = rect.end
			has_rect = true
		else:
			min_pos.x = minf(min_pos.x, rect.position.x)
			min_pos.y = minf(min_pos.y, rect.position.y)
			max_pos.x = maxf(max_pos.x, rect.end.x)
			max_pos.y = maxf(max_pos.y, rect.end.y)
	if not has_rect:
		return Rect2()
	return Rect2(min_pos, max_pos - min_pos)


func _road_rect_has_tiles(world_rect: Rect2) -> bool:
	if _road_layer == null or not world_rect.has_area():
		return false
	var epsilon := Vector2(0.01, 0.01)
	var corners: Array[Vector2] = [
		world_rect.position,
		Vector2(world_rect.end.x - epsilon.x, world_rect.position.y),
		Vector2(world_rect.position.x, world_rect.end.y - epsilon.y),
		world_rect.end - epsilon
	]
	var min_cell := Vector2i(999999, 999999)
	var max_cell := Vector2i(-999999, -999999)
	for corner in corners:
		var cell := _road_layer.local_to_map(_road_layer.to_local(corner))
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
	for y in range(min_cell.y, max_cell.y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			if _road_layer.get_cell_source_id(Vector2i(x, y)) != -1:
				return true
	return false


func _get_road_half_width_px() -> float:
	if _road_layer == null or _road_layer.tile_set == null:
		return 60.0
	var cell_size := Vector2(_road_layer.tile_set.tile_size) * _road_layer.scale
	if absf(cell_size.x) < absf(cell_size.y):
		return maxf(absf(cell_size.x), 1.0) * float(maxi(1, road_width_tiles)) * 0.5
	return maxf(absf(cell_size.y), 1.0) * float(maxi(1, road_width_tiles)) * 0.5


func _collect_collision_shapes(node: Node, parent_transform: Transform2D) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var node_transform := parent_transform
	if node is Node2D:
		node_transform = parent_transform * (node as Node2D).transform
	if node is CollisionShape2D:
		var shape_node := node as CollisionShape2D
		if not shape_node.disabled and shape_node.shape != null:
			out.append({
				"shape": shape_node.shape,
				"transform": node_transform
			})
	for child in node.get_children():
		var child_entries := _collect_collision_shapes(child, node_transform)
		for entry in child_entries:
			out.append(entry)
	return out


func _spawn_house(scene: PackedScene, world_pos: Vector2, index: int) -> void:
	var house := scene.instantiate() as Node2D
	if house == null:
		return
	var object_id := "guaranteed_road_house:%d:%s" % [index, scene.resource_path]
	house.set_meta("world_generation_id", object_id)
	house.set_meta("world_generation_scene_path", scene.resource_path)
	house.add_to_group(GENERATED_GROUP)
	if "persistent_id" in house:
		house.persistent_id = object_id
	_spawn_parent.add_child(house)
	house.global_position = world_pos
	var key := scene.resource_path if not scene.resource_path.is_empty() else scene.resource_name
	_spawned_scene_counts[key] = int(_spawned_scene_counts.get(key, 0)) + 1


func _mark_generated_cells(cells: Array[Vector2i]) -> void:
	var generated: Dictionary = {}
	for cell in cells:
		generated[cell] = cell
	_road_layer.set_meta(META_GENERATED_CELLS, generated)


func _paint_corridor_cells(cells: Array[Vector2i]) -> void:
	if cells.is_empty() or _road_layer == null:
		return

	var horizontal := _is_horizontal_corridor(cells)
	var road_generator := get_node_or_null("../ChunkLayerGenerator_Road")
	var source_id := 0
	var atlas := Vector2i(0, 1) if horizontal else Vector2i(0, 0)

	if road_generator != null:
		var source_value: Variant = road_generator.get("source_id")
		if source_value != null:
			source_id = int(source_value)
		var atlas_value: Variant = road_generator.get("road_straight_horizontal_atlas" if horizontal else "road_straight_vertical_atlas")
		if atlas_value is Vector2i and atlas_value.x >= 0 and atlas_value.y >= 0:
			atlas = atlas_value as Vector2i

	for cell in cells:
		_road_layer.set_cell(cell, source_id, atlas, 0)


func _is_horizontal_corridor(cells: Array[Vector2i]) -> bool:
	if cells.size() < 2:
		return true
	var first := cells[0] as Vector2i
	var last := cells[cells.size() - 1] as Vector2i
	return abs(first.x - last.x) >= abs(first.y - last.y)


func _get_world_chunk_bounds() -> Dictionary:
	var player_cell: Vector2i = _road_layer.local_to_map(_road_layer.to_local(_player.global_position))
	var start_chunk: Vector2i = Vector2i(
		floori(float(player_cell.x) / float(chunk_size_tiles)),
		floori(float(player_cell.y) / float(chunk_size_tiles))
	)
	var half_x: int = int(floor(world_chunks_x / 2.0))
	var half_y: int = int(floor(world_chunks_y / 2.0))
	var min_chunk: Vector2i = Vector2i(start_chunk.x - half_x, start_chunk.y - half_y)
	var max_chunk: Vector2i = Vector2i(min_chunk.x + world_chunks_x - 1, min_chunk.y + world_chunks_y - 1)
	return {
		"min": min_chunk,
		"max": max_chunk
	}


func _get_corridor_seed() -> int:
	var road_generator := get_node_or_null("../ChunkLayerGenerator_Road")
	if road_generator != null:
		var seed_value: Variant = road_generator.get("world_seed")
		if seed_value != null:
			return int(seed_value)
	return int(_player.global_position.x) ^ (int(_player.global_position.y) << 1)


func _stable_hash(x: int, y: int, salt: int) -> int:
	var h := int((x * 73856093) ^ (y * 19349663) ^ salt)
	if h < 0:
		h = -h
	return h
