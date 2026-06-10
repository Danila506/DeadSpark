extends Node2D

const GENERATED_GROUP: StringName = &"generated_world_object"
const META_GENERATED_CELLS: StringName = &"world_generation_generated_cells"
const PATTERN_OPEN_TOP: int = 0
const PATTERN_OPEN_BOTTOM: int = 1
const PATTERN_OPEN_LEFT: int = 2
const PATTERN_OPEN_RIGHT: int = 3
const MIN_PATTERN_CHUNKS: int = 2
const MAX_PATTERN_CHUNKS: int = 3

@export var enabled: bool = true
@export var player_path: NodePath = NodePath("../../Y-Sort_Objects/Player2")
@export var road_layer_path: NodePath = NodePath("../../Y-Sort_Objects/RoadLayer")
@export var road_generator_path: NodePath = NodePath("../ChunkLayerGenerator_Road")
@export var spawn_parent_path: NodePath = NodePath("../../Y-Sort_Objects/GeneratedForesterHouses")
@export var wait_for_tile_generators: bool = true
@export_range(4, 256, 1) var chunk_size_tiles: int = 16
@export_range(1, 64, 1) var world_chunks_x: int = 6
@export_range(1, 64, 1) var world_chunks_y: int = 6
@export_range(0, 4, 1) var edge_margin_chunks: int = 1
@export_range(1, 8, 1) var road_width_tiles: int = 1
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
var _road_generator: Node
var _spawn_parent: Node2D
var _generated: bool = false
var _spawned_scene_counts: Dictionary = {}


func _ready() -> void:
	_resolve_nodes()
	set_process(enabled)


func _process(_delta: float) -> void:
	force_generate_step()


func has_generation_pending() -> bool:
	return enabled and not _generated


func is_world_generation_tile_source() -> bool:
	return true


func get_pending_generation_chunk_count() -> int:
	return 0 if _generated or not enabled else 1


func force_generate_step(_chunk_budget: int = -1) -> void:
	if not enabled or _generated:
		return
	_resolve_nodes()
	if _player == null or _road_layer == null:
		return
	if _has_pending_tile_generation_dependencies():
		return
	_generate_pattern_road_and_houses()
	_generated = true
	set_process(false)


func get_debug_world_generation_info() -> Dictionary:
	return {
		"type": "tile_layer",
		"name": name,
		"loaded_chunks": [],
		"spawn_scene_counts": _spawned_scene_counts.duplicate()
	}


func _resolve_nodes() -> void:
	_player = get_node_or_null(player_path) as Node2D
	_road_layer = get_node_or_null(road_layer_path) as TileMapLayer
	_road_generator = get_node_or_null(road_generator_path)
	_spawn_parent = get_node_or_null(spawn_parent_path) as Node2D


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


func _generate_pattern_road_and_houses() -> void:
	var layout := _build_pattern_layout()
	var road_cells: Array[Vector2i] = []
	for cell_variant in layout.get("cells", []):
		road_cells.append(cell_variant as Vector2i)
	var segments: Array = layout.get("segments", [])
	if road_cells.is_empty():
		if debug_log:
			push_warning("GuaranteedRoadCorridor: no patterned road cells were generated.")
		return

	_road_layer.clear()
	_paint_corridor_cells(road_cells)
	_mark_generated_cells(road_cells)
	_spawn_roadside_houses(segments)


func _build_pattern_layout() -> Dictionary:
	var world_bounds := _get_world_chunk_bounds()
	var min_chunk: Vector2i = world_bounds["min"] as Vector2i
	var max_chunk: Vector2i = world_bounds["max"] as Vector2i
	var interior_min := min_chunk + Vector2i(edge_margin_chunks, edge_margin_chunks)
	var interior_max := max_chunk - Vector2i(edge_margin_chunks, edge_margin_chunks)
	if interior_min.x > interior_max.x or interior_min.y > interior_max.y:
		interior_min = min_chunk
		interior_max = max_chunk

	var rng := RandomNumberGenerator.new()
	rng.seed = _get_corridor_seed()

	var pattern_id := rng.randi_range(PATTERN_OPEN_TOP, PATTERN_OPEN_RIGHT)
	var footprint := _pick_pattern_footprint(pattern_id, interior_min, interior_max, rng)
	var origin_chunk := _pick_pattern_origin(interior_min, interior_max, footprint, rng)
	var polyline := _build_pattern_polyline(pattern_id, origin_chunk, footprint)
	return _build_layout_from_polyline(polyline)


func _pick_pattern_footprint(
	_pattern_id: int,
	interior_min: Vector2i,
	interior_max: Vector2i,
	rng: RandomNumberGenerator
) -> Vector2i:
	var max_width := maxi(1, interior_max.x - interior_min.x + 1)
	var max_height := maxi(1, interior_max.y - interior_min.y + 1)
	var width := _pick_pattern_chunk_span(max_width, rng)
	var height := _pick_pattern_chunk_span(max_height, rng)
	return Vector2i(width, height)


func _pick_pattern_chunk_span(max_available: int, rng: RandomNumberGenerator) -> int:
	var max_span := mini(MAX_PATTERN_CHUNKS, maxi(1, max_available))
	var min_span := mini(MIN_PATTERN_CHUNKS, max_span)
	if max_span <= min_span:
		return max_span
	return rng.randi_range(min_span, max_span)


func _pick_pattern_origin(
	interior_min: Vector2i,
	interior_max: Vector2i,
	footprint: Vector2i,
	rng: RandomNumberGenerator
) -> Vector2i:
	var max_origin_x := interior_max.x - footprint.x + 1
	var max_origin_y := interior_max.y - footprint.y + 1
	var origin_x := interior_min.x
	var origin_y := interior_min.y
	if max_origin_x > interior_min.x:
		origin_x = rng.randi_range(interior_min.x, max_origin_x)
	if max_origin_y > interior_min.y:
		origin_y = rng.randi_range(interior_min.y, max_origin_y)
	return Vector2i(origin_x, origin_y)


func _build_pattern_polyline(pattern_id: int, origin_chunk: Vector2i, footprint: Vector2i) -> Array[Vector2i]:
	var tile_origin := origin_chunk * chunk_size_tiles
	var width_tiles := maxi(1, footprint.x * chunk_size_tiles)
	var height_tiles := maxi(1, footprint.y * chunk_size_tiles)
	var left := tile_origin.x + road_margin_inside_chunk_tiles
	var right := tile_origin.x + width_tiles - road_margin_inside_chunk_tiles - 1
	var top := tile_origin.y + road_margin_inside_chunk_tiles
	var bottom := tile_origin.y + height_tiles - road_margin_inside_chunk_tiles - 1

	if right < left:
		right = left
	if bottom < top:
		bottom = top

	match pattern_id:
		PATTERN_OPEN_TOP:
			return [
				Vector2i(left, top),
				Vector2i(left, bottom),
				Vector2i(right, bottom),
				Vector2i(right, top)
			]
		PATTERN_OPEN_BOTTOM:
			return [
				Vector2i(left, bottom),
				Vector2i(left, top),
				Vector2i(right, top),
				Vector2i(right, bottom)
			]
		PATTERN_OPEN_LEFT:
			return [
				Vector2i(right, top),
				Vector2i(left, top),
				Vector2i(left, bottom),
				Vector2i(right, bottom)
			]
		_:
			return [
				Vector2i(left, top),
				Vector2i(right, top),
				Vector2i(right, bottom),
				Vector2i(left, bottom)
			]


func _build_layout_from_polyline(polyline: Array[Vector2i]) -> Dictionary:
	var cells: Array[Vector2i] = []
	var road_set: Dictionary = {}
	var segments: Array = []
	if polyline.size() < 2:
		return {"cells": cells, "segments": segments}

	for i in range(polyline.size() - 1):
		var start := polyline[i]
		var finish := polyline[i + 1]
		var axis := _segment_axis_from_points(start, finish)
		var centerline_cells := _trace_axis_segment(start, finish)
		if centerline_cells.is_empty():
			continue
		var paint_cells := _expand_segment_cells(centerline_cells, axis)
		for cell in paint_cells:
			if road_set.has(cell):
				continue
			road_set[cell] = true
			cells.append(cell)
		segments.append({
			"start": start,
			"end": finish,
			"axis": axis,
			"cells": centerline_cells
		})

	return {"cells": cells, "segments": segments}


func _trace_axis_segment(start: Vector2i, finish: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if start.x != finish.x and start.y != finish.y:
		return out

	var current := start
	var step := Vector2i.ZERO
	if finish.x > start.x:
		step = Vector2i.RIGHT
	elif finish.x < start.x:
		step = Vector2i.LEFT
	elif finish.y > start.y:
		step = Vector2i.DOWN
	elif finish.y < start.y:
		step = Vector2i.UP

	out.append(current)
	while current != finish:
		current += step
		out.append(current)
	return out


func _segment_axis_from_points(start: Vector2i, finish: Vector2i) -> Vector2i:
	return Vector2i.RIGHT if start.y == finish.y else Vector2i.DOWN


func _expand_segment_cells(centerline_cells: Array[Vector2i], axis: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen: Dictionary = {}
	var half_width := maxi(0, road_width_tiles - 1)
	for center_cell in centerline_cells:
		for offset in range(half_width + 1):
			var shifted := center_cell
			if axis == Vector2i.RIGHT:
				shifted += Vector2i(0, offset)
			else:
				shifted += Vector2i(offset, 0)
			if seen.has(shifted):
				continue
			seen[shifted] = true
			out.append(shifted)
	return out


func _spawn_roadside_houses(segments: Array) -> void:
	if _spawn_parent == null or road_house_scenes.is_empty():
		return

	var spawned := 0
	var scene_cursor := 0
	var side_toggle := 0
	var road_half_width_px := _get_road_half_width_px()

	for segment_variant in segments:
		if spawned >= max_houses_to_spawn:
			break
		if not (segment_variant is Dictionary):
			continue
		var segment := segment_variant as Dictionary
		var centerline_cells: Array[Vector2i] = []
		for cell_variant in segment.get("cells", []):
			centerline_cells.append(cell_variant as Vector2i)
		if centerline_cells.size() < 2:
			continue
		var axis := segment.get("axis", Vector2i.RIGHT) as Vector2i
		var normals: Array = [Vector2i.UP, Vector2i.DOWN] if axis == Vector2i.RIGHT else [Vector2i.LEFT, Vector2i.RIGHT]
		var start_index := mini(maxi(1, int(floor(house_spacing_tiles * 0.5))), maxi(1, centerline_cells.size() - 1))

		for i in range(start_index, centerline_cells.size() - 1, maxi(1, house_spacing_tiles)):
			if spawned >= max_houses_to_spawn:
				break
			var road_cell := centerline_cells[i]
			var road_world := _road_layer.to_global(_road_layer.map_to_local(road_cell))
			var scene := _next_house_scene(scene_cursor)
			if scene == null:
				break
			var normal_order: Array[Vector2i] = [
				normals[side_toggle % normals.size()],
				normals[(side_toggle + 1) % normals.size()]
			]
			var placed := false
			for normal in normal_order:
				var house_half_extent_px := _get_scene_half_extent_along_normal(scene, normal)
				var offset_px := road_half_width_px + house_half_extent_px + roadside_house_margin_px
				var world_pos := road_world + Vector2(normal) * offset_px
				if not _can_place_house(scene, world_pos):
					continue
				_spawn_house(scene, world_pos, spawned)
				spawned += 1
				side_toggle += 1
				placed = true
				break
			scene_cursor += 1
			if placed and spawned >= max_houses_to_spawn:
				break


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
	var object_id := "pattern_road_house:%d:%s" % [index, scene.resource_path]
	house.set_meta("world_generation_id", object_id)
	house.set_meta("world_generation_scene_path", scene.resource_path)
	house.add_to_group(GENERATED_GROUP)
	if "persistent_id" in house:
		house.persistent_id = object_id
	house.position = _spawn_parent.to_local(world_pos)
	_spawn_parent.add_child(house)
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

	var road_set: Dictionary = {}
	for cell in cells:
		road_set[cell] = true

	var source_id := int(_get_road_generator_value("source_id", 0))
	for cell in cells:
		var atlas := _resolve_road_atlas(cell, road_set)
		_road_layer.set_cell(cell, source_id, atlas, 0)


func _resolve_road_atlas(cell: Vector2i, road_set: Dictionary) -> Vector2i:
	var up := road_set.has(cell + Vector2i.UP)
	var down := road_set.has(cell + Vector2i.DOWN)
	var left := road_set.has(cell + Vector2i.LEFT)
	var right := road_set.has(cell + Vector2i.RIGHT)
	var connections := 0
	connections += 1 if up else 0
	connections += 1 if down else 0
	connections += 1 if left else 0
	connections += 1 if right else 0

	if connections >= 3:
		if (up and down) or (connections == 4):
			return _get_road_atlas_value("road_straight_vertical_atlas", Vector2i(0, 0))
		return _get_road_atlas_value("road_straight_horizontal_atlas", Vector2i(0, 1))
	if connections == 2:
		if up and down:
			return _get_road_atlas_value("road_straight_vertical_atlas", Vector2i(0, 0))
		if left and right:
			return _get_road_atlas_value("road_straight_horizontal_atlas", Vector2i(0, 1))
		if up and left:
			return _get_road_atlas_value("road_corner_atlas_up_left", Vector2i(3, 1))
		if up and right:
			return _get_road_atlas_value("road_corner_atlas_up_right", Vector2i(2, 1))
		if down and left:
			return _get_road_atlas_value("road_corner_atlas_down_left", Vector2i(1, 1))
		return _get_road_atlas_value("road_corner_atlas_down_right", Vector2i(4, 1))
	if up or down:
		return _get_road_atlas_value("road_straight_vertical_atlas", Vector2i(0, 0))
	return _get_road_atlas_value("road_straight_horizontal_atlas", Vector2i(0, 1))


func _get_road_atlas_value(property_name: String, fallback: Vector2i) -> Vector2i:
	var value: Variant = _get_road_generator_value(property_name, fallback)
	if value is Vector2i:
		return value as Vector2i
	return fallback


func _get_road_generator_value(property_name: String, fallback: Variant) -> Variant:
	if _road_generator == null:
		return fallback
	var value: Variant = _road_generator.get(property_name)
	return fallback if value == null else value


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
	var seed_value: Variant = _get_road_generator_value("world_seed", null)
	if seed_value != null:
		return int(seed_value)
	return int(_player.global_position.x) ^ (int(_player.global_position.y) << 1)
