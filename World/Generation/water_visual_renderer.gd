class_name WaterVisualRenderer
extends RefCounted

const VISUAL_ROOT_NAME := "GeneratedWaterVisuals"
const WATER_ATLAS: Texture2D = preload("res://World/Assets/тайлмап воды.png")
const SOURCE_TILE_SIZE := 56

static var _surface_texture: Texture2D = null


static func rebuild(layer: TileMapLayer, components: Array[Array], smoothing_iterations: int = 3) -> Node2D:
	if layer == null or layer.get_parent() == null:
		return null
	var parent := layer.get_parent() as Node2D
	if parent == null:
		return null
	var previous := parent.get_node_or_null(VISUAL_ROOT_NAME)
	if previous != null:
		parent.remove_child(previous)
		previous.queue_free()

	var root := Node2D.new()
	root.name = VISUAL_ROOT_NAME
	root.z_index = layer.z_index
	root.z_as_relative = layer.z_as_relative
	parent.add_child(root)
	var texture := _get_surface_texture()
	var collision_layer := 1
	var collision_mask := 1
	if layer.tile_set.get_physics_layers_count() > 0:
		collision_layer = layer.tile_set.get_physics_layer_collision_layer(0)
		collision_mask = layer.tile_set.get_physics_layer_collision_mask(0)
	for index in range(components.size()):
		var contour := _largest_boundary_loop(components[index])
		if contour.size() < 3:
			continue
		var points := _grid_contour_to_parent(contour, layer, parent)
		points = _relax_closed(points, 2)
		for _iteration in range(maxi(smoothing_iterations, 0)):
			points = _chaikin_closed(points)
		_add_lake_visual(root, points, texture, layer.material, index, collision_layer, collision_mask)

	# The TileMap remains populated for occupancy and generation hashes. Rendering
	# and physics use the same smoothed contour, so the visible bank cannot diverge
	# from the collision boundary.
	layer.visible = false
	layer.collision_enabled = false
	return root


static func _add_lake_visual(
	root: Node2D,
	points: PackedVector2Array,
	texture: Texture2D,
	material: Material,
	index: int,
	collision_layer: int,
	collision_mask: int
) -> void:
	var lake := Node2D.new()
	lake.name = "LakeVisual_%d" % index
	root.add_child(lake)

	var surface := Polygon2D.new()
	surface.name = "Surface"
	surface.polygon = points
	surface.uv = points
	surface.texture = texture
	surface.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	surface.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	surface.material = material
	lake.add_child(surface)

	var body := StaticBody2D.new()
	body.name = "LakeBoundary"
	body.collision_layer = collision_layer
	body.collision_mask = collision_mask
	lake.add_child(body)
	var collision := CollisionShape2D.new()
	collision.name = "BoundaryShape"
	var boundary_shape := ConcavePolygonShape2D.new()
	var segments := PackedVector2Array()
	for point_index in range(points.size()):
		segments.append(points[point_index])
		segments.append(points[(point_index + 1) % points.size()])
	boundary_shape.segments = segments
	collision.shape = boundary_shape
	body.add_child(collision)


static func _largest_boundary_loop(component: Array) -> Array[Vector2i]:
	var occupied := {}
	for cell_variant in component:
		occupied[cell_variant as Vector2i] = true
	var outgoing := {}
	for cell_variant in component:
		var cell := cell_variant as Vector2i
		if not occupied.has(cell + Vector2i.UP):
			_add_edge(outgoing, cell, cell + Vector2i.RIGHT)
		if not occupied.has(cell + Vector2i.RIGHT):
			_add_edge(outgoing, cell + Vector2i.RIGHT, cell + Vector2i.ONE)
		if not occupied.has(cell + Vector2i.DOWN):
			_add_edge(outgoing, cell + Vector2i.ONE, cell + Vector2i.DOWN)
		if not occupied.has(cell + Vector2i.LEFT):
			_add_edge(outgoing, cell + Vector2i.DOWN, cell)

	var used := {}
	var loops: Array[Array] = []
	for start_variant in outgoing.keys():
		var start := start_variant as Vector2i
		for end_variant in outgoing[start]:
			var first_end := end_variant as Vector2i
			var first_key := _edge_key(start, first_end)
			if used.has(first_key):
				continue
			var loop := _trace_loop(start, first_end, outgoing, used)
			if loop.size() >= 3:
				loops.append(loop)
	var largest: Array[Vector2i] = []
	var largest_area := 0.0
	for loop_variant in loops:
		var loop: Array = loop_variant
		var area := absf(_signed_area(loop))
		if area > largest_area:
			largest_area = area
			largest.assign(loop)
	return largest


static func _add_edge(outgoing: Dictionary, start: Vector2i, finish: Vector2i) -> void:
	if not outgoing.has(start):
		outgoing[start] = []
	(outgoing[start] as Array).append(finish)


static func _trace_loop(start: Vector2i, first_end: Vector2i, outgoing: Dictionary, used: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = [start]
	var previous := start
	var current := first_end
	used[_edge_key(previous, current)] = true
	var guard := 0
	while current != start and guard < 100000:
		result.append(current)
		var next := _choose_next_edge(previous, current, outgoing.get(current, []), used)
		if next == current:
			return []
		previous = current
		current = next
		used[_edge_key(previous, current)] = true
		guard += 1
	return result if current == start else []


static func _choose_next_edge(previous: Vector2i, current: Vector2i, candidates: Array, used: Dictionary) -> Vector2i:
	var incoming_index := _direction_index(current - previous)
	var best := current
	var best_score := 100
	for candidate_variant in candidates:
		var candidate := candidate_variant as Vector2i
		if used.has(_edge_key(current, candidate)):
			continue
		var turn := posmod(_direction_index(candidate - current) - incoming_index, 4)
		var score := 0
		match turn:
			1: score = 0 # Prefer a clockwise/right turn at diagonal contacts.
			0: score = 1
			3: score = 2
			_: score = 3
		if score < best_score:
			best_score = score
			best = candidate
	return best


static func _direction_index(direction: Vector2i) -> int:
	if direction == Vector2i.RIGHT:
		return 0
	if direction == Vector2i.DOWN:
		return 1
	if direction == Vector2i.LEFT:
		return 2
	return 3


static func _edge_key(start: Vector2i, finish: Vector2i) -> String:
	return "%d,%d>%d,%d" % [start.x, start.y, finish.x, finish.y]


static func _signed_area(points: Array) -> float:
	var area := 0.0
	for index in range(points.size()):
		var a := Vector2(points[index] as Vector2i)
		var b := Vector2(points[(index + 1) % points.size()] as Vector2i)
		area += a.x * b.y - b.x * a.y
	return area * 0.5


static func _grid_contour_to_parent(contour: Array[Vector2i], layer: TileMapLayer, parent: Node2D) -> PackedVector2Array:
	var result := PackedVector2Array()
	var half_tile := Vector2(layer.tile_set.tile_size) * 0.5
	for corner in contour:
		var layer_local := layer.map_to_local(corner) - half_tile
		result.append(parent.to_local(layer.to_global(layer_local)))
	return result


static func _chaikin_closed(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var result := PackedVector2Array()
	for index in range(points.size()):
		var current := points[index]
		var next := points[(index + 1) % points.size()]
		result.append(current.lerp(next, 0.25))
		result.append(current.lerp(next, 0.75))
	return result


static func _relax_closed(points: PackedVector2Array, passes: int) -> PackedVector2Array:
	var current := points
	for _pass in range(maxi(passes, 0)):
		if current.size() < 5:
			break
		var relaxed := PackedVector2Array()
		for index in range(current.size()):
			var previous := current[posmod(index - 1, current.size())]
			var point := current[index]
			var next := current[(index + 1) % current.size()]
			relaxed.append(previous * 0.2 + point * 0.6 + next * 0.2)
		current = relaxed
	return current


static func _get_surface_texture() -> Texture2D:
	if _surface_texture != null:
		return _surface_texture
	var atlas_image := WATER_ATLAS.get_image()
	if atlas_image == null:
		return WATER_ATLAS
	var region := Rect2i(SOURCE_TILE_SIZE, SOURCE_TILE_SIZE, SOURCE_TILE_SIZE, SOURCE_TILE_SIZE)
	var surface_image := atlas_image.get_region(region)
	_surface_texture = ImageTexture.create_from_image(surface_image)
	return _surface_texture
