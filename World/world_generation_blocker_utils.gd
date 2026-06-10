class_name WorldGenerationBlockerUtils
extends RefCounted

const FOOTPRINT_META: StringName = &"world_generation_footprint_rect"
const BLOCKER_GROUP: StringName = &"world_generation_blocker"
const GENERATED_CELLS_META: StringName = &"world_generation_generated_cells"
const PROTECTED_CELLS_META: StringName = &"world_generation_protected_cells"
const PRESERVE_EDITOR_TILES_META: StringName = &"world_generation_preserve_editor_tiles"


static func configure_blocker(node: Node2D, area: Area2D, clear_generated_tiles: bool = true) -> void:
	if node == null:
		return
	if not node.is_in_group(BLOCKER_GROUP):
		node.add_to_group(BLOCKER_GROUP)
	var rect := build_area_rect(area).abs()
	if not rect.has_area():
		return
	node.set_meta(FOOTPRINT_META, rect)
	if clear_generated_tiles:
		clear_generated_tiles_in_rect(node, rect)


static func build_area_rect(area: Area2D) -> Rect2:
	if area == null:
		return Rect2()

	var has_rect := false
	var min_pos := Vector2.ZERO
	var max_pos := Vector2.ZERO
	for child in area.get_children():
		if not (child is CollisionShape2D):
			continue
		var collision_shape := child as CollisionShape2D
		if collision_shape.disabled or collision_shape.shape == null:
			continue
		var shape_rect := _build_collision_shape_rect(collision_shape).abs()
		if not shape_rect.has_area():
			continue
		if not has_rect:
			min_pos = shape_rect.position
			max_pos = shape_rect.end
			has_rect = true
			continue
		min_pos.x = minf(min_pos.x, shape_rect.position.x)
		min_pos.y = minf(min_pos.y, shape_rect.position.y)
		max_pos.x = maxf(max_pos.x, shape_rect.end.x)
		max_pos.y = maxf(max_pos.y, shape_rect.end.y)

	return Rect2(min_pos, max_pos - min_pos) if has_rect else Rect2()


static func clear_generated_tiles_in_rect(context: Node, world_rect: Rect2) -> void:
	if context == null:
		return
	var tree := context.get_tree()
	if tree == null:
		return
	var scene_root := tree.current_scene
	if scene_root == null:
		scene_root = context
	var target_rect := world_rect.abs()
	if not target_rect.has_area():
		return

	var tile_layers: Array[TileMapLayer] = []
	_collect_tile_layers(scene_root, tile_layers)
	for layer in tile_layers:
		_clear_generated_tiles_from_layer(layer, target_rect)


static func _collect_tile_layers(root: Node, out: Array[TileMapLayer]) -> void:
	if root == null:
		return
	if root is TileMapLayer:
		out.append(root as TileMapLayer)
	for child in root.get_children():
		if child is Node:
			_collect_tile_layers(child as Node, out)


static func _clear_generated_tiles_from_layer(layer: TileMapLayer, world_rect: Rect2) -> void:
	if layer == null:
		return
	var generated_cells_variant: Variant = layer.get_meta(GENERATED_CELLS_META, {})
	var generated_cells: Dictionary = generated_cells_variant as Dictionary if generated_cells_variant is Dictionary else {}
	var preserve_editor_tiles: bool = bool(layer.get_meta(PRESERVE_EDITOR_TILES_META, false))
	var protected_cells_variant: Variant = layer.get_meta(PROTECTED_CELLS_META, {})
	var protected_cells: Dictionary = protected_cells_variant as Dictionary if protected_cells_variant is Dictionary else {}

	var erase_origins: Dictionary = {}
	for cell in _get_rect_cells(layer, world_rect):
		if not generated_cells.has(cell):
			continue
		var origin_variant: Variant = generated_cells[cell]
		if not (origin_variant is Vector2i):
			continue
		var origin := origin_variant as Vector2i
		if erase_origins.has(origin):
			continue
		if preserve_editor_tiles and protected_cells.has(origin):
			continue
		var tile_rect := _get_tile_world_rect(layer, origin)
		if tile_rect.has_area() and tile_rect.intersects(world_rect):
			erase_origins[origin] = true
	if erase_origins.is_empty():
		return

	for origin_variant in erase_origins.keys():
		var origin := origin_variant as Vector2i
		_erase_generated_origin_cells(layer, generated_cells, origin)
		if layer.get_cell_source_id(origin) != -1:
			layer.erase_cell(origin)

	layer.set_meta(GENERATED_CELLS_META, generated_cells)


static func _get_tile_world_rect(layer: TileMapLayer, origin_cell: Vector2i) -> Rect2:
	if layer == null or layer.tile_set == null:
		return Rect2()

	var tile_size := Vector2(layer.tile_set.tile_size)
	if tile_size.x <= 0.0 or tile_size.y <= 0.0:
		return Rect2()

	var span := Vector2i.ONE
	var source_id := layer.get_cell_source_id(origin_cell)
	if source_id != -1:
		var source := layer.tile_set.get_source(source_id)
		if source is TileSetAtlasSource:
			var atlas_source := source as TileSetAtlasSource
			var atlas_coords := layer.get_cell_atlas_coords(origin_cell)
			var atlas_span := atlas_source.get_tile_size_in_atlas(atlas_coords)
			if atlas_span.x > 0 and atlas_span.y > 0:
				span = atlas_span

	var top_left := layer.to_global(layer.map_to_local(origin_cell) - (tile_size * 0.5))
	return Rect2(top_left, Vector2(tile_size.x * span.x, tile_size.y * span.y))


static func _get_rect_cells(layer: TileMapLayer, world_rect: Rect2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if layer == null:
		return out

	var epsilon := Vector2(0.01, 0.01)
	var corners := [
		world_rect.position,
		Vector2(world_rect.end.x - epsilon.x, world_rect.position.y),
		Vector2(world_rect.position.x, world_rect.end.y - epsilon.y),
		world_rect.end - epsilon
	]

	var min_cell := Vector2i(999999, 999999)
	var max_cell := Vector2i(-999999, -999999)
	for corner in corners:
		var cell := layer.local_to_map(layer.to_local(corner))
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)

	for y in range(min_cell.y, max_cell.y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			out.append(Vector2i(x, y))
	return out


static func _erase_generated_origin_cells(layer: TileMapLayer, generated_cells: Dictionary, origin: Vector2i) -> void:
	var span := Vector2i.ONE
	if layer != null and layer.tile_set != null:
		var source_id := layer.get_cell_source_id(origin)
		if source_id != -1:
			var source := layer.tile_set.get_source(source_id)
			if source is TileSetAtlasSource:
				var atlas_source := source as TileSetAtlasSource
				var atlas_coords := layer.get_cell_atlas_coords(origin)
				var atlas_span := atlas_source.get_tile_size_in_atlas(atlas_coords)
				span = Vector2i(maxi(1, atlas_span.x), maxi(1, atlas_span.y))

	for y in range(span.y):
		for x in range(span.x):
			var key := origin + Vector2i(x, y)
			var mapped_origin: Variant = generated_cells.get(key, null)
			if key == origin or (mapped_origin is Vector2i and mapped_origin == origin):
				generated_cells.erase(key)


static func _build_collision_shape_rect(collision_shape: CollisionShape2D) -> Rect2:
	if collision_shape == null or collision_shape.shape == null:
		return Rect2()
	if collision_shape.shape is RectangleShape2D:
		var rect_shape := collision_shape.shape as RectangleShape2D
		var half_size := rect_shape.size * 0.5
		var corners := [
			Vector2(-half_size.x, -half_size.y),
			Vector2(half_size.x, -half_size.y),
			Vector2(half_size.x, half_size.y),
			Vector2(-half_size.x, half_size.y)
		]
		return _rect_from_transformed_points(collision_shape.global_transform, corners)
	if collision_shape.shape is CircleShape2D:
		var circle_shape := collision_shape.shape as CircleShape2D
		var radius := maxf(circle_shape.radius, 0.0)
		var transform := collision_shape.global_transform
		var x_axis := transform.x * radius
		var y_axis := transform.y * radius
		var extents := Vector2(
			sqrt(x_axis.x * x_axis.x + y_axis.x * y_axis.x),
			sqrt(x_axis.y * x_axis.y + y_axis.y * y_axis.y)
		)
		var center := transform * Vector2.ZERO
		return Rect2(center - extents, extents * 2.0)

	var local_rect := collision_shape.shape.get_rect()
	if not local_rect.has_area():
		return Rect2()
	var corners := [
		local_rect.position,
		Vector2(local_rect.end.x, local_rect.position.y),
		local_rect.end,
		Vector2(local_rect.position.x, local_rect.end.y)
	]
	return _rect_from_transformed_points(collision_shape.global_transform, corners)


static func _rect_from_transformed_points(transform: Transform2D, points: Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var first_point: Vector2 = transform * (points[0] as Vector2)
	var min_pos: Vector2 = first_point
	var max_pos: Vector2 = first_point
	for i in range(1, points.size()):
		var point: Vector2 = transform * (points[i] as Vector2)
		min_pos.x = minf(min_pos.x, point.x)
		min_pos.y = minf(min_pos.y, point.y)
		max_pos.x = maxf(max_pos.x, point.x)
		max_pos.y = maxf(max_pos.y, point.y)
	return Rect2(min_pos, max_pos - min_pos)
