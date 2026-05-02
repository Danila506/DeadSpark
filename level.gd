extends Node2D


@export_category("World Bounds")
@export var player_path: NodePath
@export var world_bounds_generator_path: NodePath = NodePath("ChunkWorldGenerator")
@export var world_bounds_thickness_px: float = 128.0
@export var world_bounds_collision_layer: int = 1
@export var world_bounds_collision_mask: int = 0
@export var auto_navigation_region_enabled: bool = true
@export var navigation_region_padding_px: float = 64.0

@export_category("Visual Mood")
@export var world_mood_enabled: bool = true
@export var world_mood_color: Color = Color(0.62, 0.67, 0.78, 1.0)
@export var world_mood_targets: Array[NodePath] = [
	NodePath("SnowLayer"),
	NodePath("WoodLayer"),
	NodePath("RoadLayer"),
	NodePath("RoadCustomLayer"),
	NodePath("Y-Sort_Objects"),
	NodePath("Snowfall")
]

@export_category("Safe Spawn")
@export var safe_player_spawn_enabled: bool = true
@export var safe_spawn_points_root_path: NodePath = NodePath("Y-Sort_Objects/ItemSpawner")
@export var safe_spawn_lake_layer_path: NodePath = NodePath("Y-Sort_Objects/LakeLayer")
@export var safe_spawn_collision_radius_px: float = 14.0
@export var safe_spawn_search_step_px: float = 28.0
@export var safe_spawn_search_max_rings: int = 28
@export var safe_spawn_recheck_frames: int = 8

@export_category("Startup Loading")
@export var startup_loading_enabled: bool = true
@export var world_generation_root_path: NodePath = NodePath("WorldGeneration")
@export_range(1, 512, 1) var startup_preload_chunk_budget: int = 24
@export_range(30, 2000, 1) var startup_preload_max_frames: int = 420
@export var startup_hidden_nodes: Array[NodePath] = [
	NodePath("SnowLayer"),
	NodePath("WoodLayer"),
	NodePath("RoadLayer"),
	NodePath("Y-Sort_Objects"),
	NodePath("UI"),
	NodePath("Snowfall"),
	NodePath("Projectile")
]

var _player: Node2D
var _cached_world_bounds: Rect2 = Rect2()
var _layer_max_tile_span_by_id := {}
var _loading_canvas: CanvasLayer
var _loading_label: Label


func _ready() -> void:
	if startup_loading_enabled:
		_create_loading_overlay()
		_set_startup_world_visible(false)
		await _preload_world_generation()

	_apply_world_mood_grade()
	_player = _resolve_player()
	_setup_world_bounds()
	if safe_player_spawn_enabled:
		await _ensure_player_safe_spawn_deferred()
	_spawn_starter_items_near_player()

	if startup_loading_enabled:
		_set_startup_world_visible(true)
		_destroy_loading_overlay()


func _create_loading_overlay() -> void:
	if _loading_canvas != null:
		return
	_loading_canvas = CanvasLayer.new()
	_loading_canvas.name = "StartupLoadingLayer"
	_loading_canvas.layer = 120
	add_child(_loading_canvas)

	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 0.0
	root.offset_top = 0.0
	root.offset_right = 0.0
	root.offset_bottom = 0.0
	_loading_canvas.add_child(root)

	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.offset_left = 0.0
	shade.offset_top = 0.0
	shade.offset_right = 0.0
	shade.offset_bottom = 0.0
	shade.color = Color(0.02, 0.02, 0.03, 1.0)
	root.add_child(shade)

	_loading_label = Label.new()
	_loading_label.name = "LoadingLabel"
	_loading_label.text = "Загрузка мира..."
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_label.offset_left = 0.0
	_loading_label.offset_top = 0.0
	_loading_label.offset_right = 0.0
	_loading_label.offset_bottom = 0.0
	_loading_label.add_theme_font_size_override("font_size", 30)
	_loading_label.add_theme_color_override("font_color", Color(0.92, 0.93, 0.96, 1.0))
	root.add_child(_loading_label)


func _destroy_loading_overlay() -> void:
	if _loading_canvas != null and is_instance_valid(_loading_canvas):
		_loading_canvas.queue_free()
	_loading_canvas = null
	_loading_label = null


func _set_startup_world_visible(is_visible: bool) -> void:
	for path in startup_hidden_nodes:
		if path == NodePath(""):
			continue
		var target := get_node_or_null(path)
		if target is CanvasItem:
			(target as CanvasItem).visible = is_visible


func _set_loading_status(text: String) -> void:
	if _loading_label == null:
		return
	_loading_label.text = text


func _preload_world_generation() -> void:
	var world_generation_root := get_node_or_null(world_generation_root_path)
	if world_generation_root == null:
		return

	var tile_sources: Array[Node] = []
	var spawner_sources: Array[Node] = []
	for child in world_generation_root.get_children():
		var source := child as Node
		if source == null:
			continue
		if not source.has_method("force_generate_step") or not source.has_method("has_generation_pending"):
			continue
		if _is_world_generation_spawner(source):
			spawner_sources.append(source)
		else:
			tile_sources.append(source)

	await _drain_world_generation_sources(tile_sources, "Генерация мира...")
	await _drain_world_generation_sources(spawner_sources, "Размещение объектов...")
	for spawner in spawner_sources:
		if spawner.has_method("revalidate_loaded_spawns"):
			spawner.call("revalidate_loaded_spawns")
	await _drain_world_generation_sources(spawner_sources, "Финальная проверка...")


func _drain_world_generation_sources(sources: Array[Node], loading_text: String) -> void:
	if sources.is_empty():
		return

	var max_frames := maxi(1, startup_preload_max_frames)
	for _frame in range(max_frames):
		var pending_total := 0
		for source in sources:
			if source == null or not is_instance_valid(source):
				continue
			source.call("force_generate_step", startup_preload_chunk_budget)
			if source.has_method("get_pending_generation_chunk_count"):
				pending_total += int(source.call("get_pending_generation_chunk_count"))
			elif bool(source.call("has_generation_pending")):
				pending_total += 1

		if pending_total <= 0:
			_set_loading_status(loading_text)
			return
		_set_loading_status("%s (%d)" % [loading_text, pending_total])
		await get_tree().process_frame


func _is_world_generation_spawner(source: Node) -> bool:
	if source == null or not source.has_method("get_debug_world_generation_info"):
		return false
	var info: Variant = source.call("get_debug_world_generation_info")
	if not (info is Dictionary):
		return false
	return String((info as Dictionary).get("type", "")) == "spawner"


func _spawn_starter_items_near_player() -> void:
	var item_spawner := get_node_or_null(safe_spawn_points_root_path)
	if item_spawner == null or not item_spawner.has_method("spawn_starter_items_near_player_if_enabled"):
		return
	item_spawner.call("spawn_starter_items_near_player_if_enabled")


func _resolve_player() -> Node2D:
	if player_path != NodePath(""):
		return get_node_or_null(player_path) as Node2D

	var from_group := get_tree().get_first_node_in_group("player")
	return from_group as Node2D


func _apply_world_mood_grade() -> void:
	if not world_mood_enabled:
		return

	for target_path in world_mood_targets:
		if target_path == NodePath(""):
			continue
		var node: Node = get_node_or_null(target_path)
		if node == null or not (node is CanvasItem):
			continue
		(node as CanvasItem).modulate = world_mood_color


func _setup_world_bounds() -> void:
	var generator := get_node_or_null(world_bounds_generator_path)
	if generator == null or not generator.has_method("get_world_bounds_rect"):
		return

	var bounds: Rect2 = generator.call("get_world_bounds_rect")
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return

	_cached_world_bounds = bounds
	_apply_camera_limits(bounds)
	_create_world_boundaries(bounds)
	_setup_navigation_region(bounds)


func _apply_camera_limits(bounds: Rect2) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = _resolve_player()
		if _player == null:
			return

	var camera := _player.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return

	camera.limit_enabled = true
	camera.limit_left = int(floor(bounds.position.x))
	camera.limit_top = int(floor(bounds.position.y))
	camera.limit_right = int(ceil(bounds.end.x))
	camera.limit_bottom = int(ceil(bounds.end.y))


func _create_world_boundaries(bounds: Rect2) -> void:
	var existing := get_node_or_null("WorldBounds")
	if existing != null:
		existing.queue_free()

	var root := Node2D.new()
	root.name = "WorldBounds"
	add_child(root)

	var thickness := maxf(16.0, world_bounds_thickness_px)
	var half := thickness * 0.5
	var min_x := bounds.position.x
	var min_y := bounds.position.y
	var max_x := bounds.end.x
	var max_y := bounds.end.y
	var mid_x := (min_x + max_x) * 0.5
	var mid_y := (min_y + max_y) * 0.5
	var vertical_size := Vector2(thickness, bounds.size.y + thickness * 2.0)
	var horizontal_size := Vector2(bounds.size.x + thickness * 2.0, thickness)

	_add_world_boundary(root, "WorldBoundLeft", Vector2(min_x - half, mid_y), vertical_size)
	_add_world_boundary(root, "WorldBoundRight", Vector2(max_x + half, mid_y), vertical_size)
	_add_world_boundary(root, "WorldBoundTop", Vector2(mid_x, min_y - half), horizontal_size)
	_add_world_boundary(root, "WorldBoundBottom", Vector2(mid_x, max_y + half), horizontal_size)


func _add_world_boundary(parent: Node, body_name: String, body_pos: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.name = body_name
	body.position = body_pos
	body.collision_layer = world_bounds_collision_layer
	body.collision_mask = world_bounds_collision_mask

	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	shape_node.shape = shape

	body.add_child(shape_node)
	parent.add_child(body)


func _setup_navigation_region(bounds: Rect2) -> void:
	if not auto_navigation_region_enabled:
		return

	var region := get_node_or_null("WorldNavigationRegion") as NavigationRegion2D
	if region == null:
		region = NavigationRegion2D.new()
		region.name = "WorldNavigationRegion"
		add_child(region)

	var nav_bounds := bounds.grow(maxf(navigation_region_padding_px, 0.0))
	var polygon := NavigationPolygon.new()
	var outline := PackedVector2Array([
		nav_bounds.position,
		Vector2(nav_bounds.end.x, nav_bounds.position.y),
		nav_bounds.end,
		Vector2(nav_bounds.position.x, nav_bounds.end.y)
	])
	polygon.add_outline(outline)
	polygon.make_polygons_from_outlines()
	region.navigation_polygon = polygon


func _ensure_player_safe_spawn_deferred() -> void:
	for _i in range(maxi(1, safe_spawn_recheck_frames)):
		await get_tree().process_frame
		_relocate_player_if_spawn_unsafe()


func _relocate_player_if_spawn_unsafe() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = _resolve_player()
		if _player == null:
			return

	var player_pos := _player.global_position
	if _is_safe_spawn_position(player_pos):
		return

	var best := _find_best_safe_spawn_position(player_pos)
	if not bool(best.get("found", false)):
		return

	var safe_pos := best.get("position", player_pos) as Vector2
	_player.global_position = safe_pos
	if "velocity" in _player:
		_player.velocity = Vector2.ZERO


func _find_best_safe_spawn_position(origin: Vector2) -> Dictionary:
	var candidates: Array[Vector2] = [origin]
	var points_root := get_node_or_null(safe_spawn_points_root_path)
	if points_root != null:
		for child in points_root.get_children():
			if child is Marker2D:
				candidates.append((child as Marker2D).global_position)

	var best_pos := origin
	var best_dist_sq := INF
	for candidate in candidates:
		var result := _find_nearest_safe_position(candidate)
		if not bool(result.get("found", false)):
			continue
		var safe_pos := result.get("position", candidate) as Vector2
		var dist_sq := safe_pos.distance_squared_to(origin)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_pos = safe_pos

	return {"found": best_dist_sq < INF, "position": best_pos}


func _find_nearest_safe_position(origin: Vector2) -> Dictionary:
	var step := maxf(8.0, safe_spawn_search_step_px)
	var max_rings := maxi(1, safe_spawn_search_max_rings)

	for ring in range(max_rings + 1):
		if ring == 0:
			if _is_safe_spawn_position(origin):
				return {"found": true, "position": origin}
			continue

		for y in range(-ring, ring + 1):
			for x in range(-ring, ring + 1):
				if abs(x) != ring and abs(y) != ring:
					continue
				var candidate := origin + Vector2(float(x) * step, float(y) * step)
				if _is_safe_spawn_position(candidate):
					return {"found": true, "position": candidate}

	return {"found": false, "position": origin}


func _is_safe_spawn_position(world_pos: Vector2) -> bool:
	if not _is_within_world_bounds(world_pos):
		return false
	if _is_world_position_on_lake(world_pos):
		return false
	if _has_world_collision_at_spawn(world_pos):
		return false
	return true


func _is_within_world_bounds(world_pos: Vector2) -> bool:
	if _cached_world_bounds.size.x <= 0.0 or _cached_world_bounds.size.y <= 0.0:
		return true
	return _cached_world_bounds.has_point(world_pos)


func _is_world_position_on_lake(world_pos: Vector2) -> bool:
	var lake_layer := get_node_or_null(safe_spawn_lake_layer_path) as TileMapLayer
	if lake_layer == null:
		return false
	return _layer_has_effective_tile_at_world(lake_layer, world_pos)


func _has_world_collision_at_spawn(world_pos: Vector2) -> bool:
	var world := get_world_2d()
	if world == null:
		return false

	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = maxf(4.0, safe_spawn_collision_radius_px)
	query.shape = shape
	query.transform = Transform2D(0.0, world_pos)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = 0x7fffffff
	if _player != null and is_instance_valid(_player) and _player is CollisionObject2D:
		query.exclude = [(_player as CollisionObject2D).get_rid()]

	var hits: Array = world.direct_space_state.intersect_shape(query, 12)
	return not hits.is_empty()


func _layer_has_effective_tile_at_world(layer: TileMapLayer, world_pos: Vector2) -> bool:
	var local_pos := layer.to_local(world_pos)
	var cell := layer.local_to_map(local_pos)
	if layer.get_cell_source_id(cell) != -1:
		return true

	var max_span := _get_layer_max_tile_span(layer)
	if max_span.x <= 1 and max_span.y <= 1:
		return false

	for oy in range(max_span.y):
		for ox in range(max_span.x):
			var origin := cell - Vector2i(ox, oy)
			if layer.get_cell_source_id(origin) == -1:
				continue
			var source_id := layer.get_cell_source_id(origin)
			if source_id == -1:
				continue
			var source := layer.tile_set.get_source(source_id)
			if not (source is TileSetAtlasSource):
				continue
			var atlas_source := source as TileSetAtlasSource
			var atlas_coords := layer.get_cell_atlas_coords(origin)
			if not atlas_source.has_tile(atlas_coords):
				continue
			var span := atlas_source.get_tile_size_in_atlas(atlas_coords)
			if ox < maxi(1, span.x) and oy < maxi(1, span.y):
				return true
	return false


func _get_layer_max_tile_span(layer: TileMapLayer) -> Vector2i:
	if layer == null or layer.tile_set == null:
		return Vector2i.ONE

	var layer_id := int(layer.get_instance_id())
	if _layer_max_tile_span_by_id.has(layer_id):
		return _layer_max_tile_span_by_id[layer_id] as Vector2i

	var max_span := Vector2i.ONE
	var tile_set := layer.tile_set
	for i in range(tile_set.get_source_count()):
		var source_id := tile_set.get_source_id(i)
		var source := tile_set.get_source(source_id)
		if not (source is TileSetAtlasSource):
			continue
		var atlas_source := source as TileSetAtlasSource
		for tile_idx in range(int(atlas_source.get_tiles_count())):
			var atlas_coords := atlas_source.get_tile_id(tile_idx)
			var span := atlas_source.get_tile_size_in_atlas(atlas_coords)
			max_span.x = maxi(max_span.x, maxi(1, span.x))
			max_span.y = maxi(max_span.y, maxi(1, span.y))

	_layer_max_tile_span_by_id[layer_id] = max_span
	return max_span
