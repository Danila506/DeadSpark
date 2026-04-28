extends Node


@export var enabled: bool = true
@export var tile_map_path: NodePath
@export var player_path: NodePath
@export var config: ChunkWorldGeneratorConfig

@export_category("Chunk Settings")
@export_range(4, 256, 1) var chunk_size_tiles: int = 16
@export_range(1, 12, 1) var load_radius_chunks: int = 3
@export_range(1, 64, 1) var world_chunks_x: int = 8
@export_range(1, 64, 1) var world_chunks_y: int = 8
@export var clear_existing_on_start: bool = true
@export var preserve_editor_tiles: bool = false
@export var update_interval_sec: float = 0.20

@export_category("Generation")
@export var world_seed: int = 1337
@export var randomize_seed_on_start: bool = false
@export_range(0.0, 1.0, 0.01) var fill_probability: float = 0.2
@export var ensure_non_empty_chunk: bool = false
@export var biome_partition_enabled: bool = false
@export_range(2, 8, 1) var biome_partition_count: int = 2
@export_range(0, 7, 1) var biome_partition_index: int = 0
@export_range(2, 16, 1) var biome_partition_period_chunks: int = 6
@export var biome_half_split_enabled: bool = false
@export var biome_half_split_vertical: bool = true
@export var biome_half_split_upper_or_left: bool = true

@export_category("TileMap Source")
@export var source_id: int = 2
@export var tile_options_atlas: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
@export var tile_option_weights: Array[float] = []

@export_category("Terrain Placement")
@export var use_terrain_connect: bool = false
@export var terrain_set_id: int = 0
@export var terrain_id: int = 0
@export var terrain_ignore_empty: bool = true
@export var terrain_blob_mode: bool = false
@export var road_corner_atlas: Vector2i = Vector2i(-1, -1)
@export var road_corner_alt_up_left: int = 0
@export var road_corner_alt_up_right: int = -1
@export var road_corner_alt_down_left: int = -1
@export var road_corner_alt_down_right: int = -1
@export var road_t_atlas: Vector2i = Vector2i(-1, -1)
@export var road_t_alt_missing_up: int = -1
@export var road_t_alt_missing_down: int = -1
@export var road_t_alt_missing_left: int = -1
@export var road_t_alt_missing_right: int = -1
@export var road_cross_atlas: Vector2i = Vector2i(-1, -1)
@export var road_cross_alternative: int = -1
@export_range(1, 12, 1) var road_min_straight_before_turn: int = 5
@export_range(0, 100, 1) var road_turn_jitter_chance: int = 18
@export_range(0, 100, 1) var road_side_jog_chance: int = 8
@export_range(0.0, 1.0, 0.01) var road_branch_density: float = 0.45
@export_range(0, 3, 1) var road_max_branches_per_chunk: int = 1
@export_range(0, 100, 1) var road_continue_direction_chance: int = 82
@export_range(1, 8, 1) var road_trim_dead_end_max_len: int = 4
@export var road_force_center_connector: bool = true
@export_range(2, 12, 1) var road_trunk_period_chunks: int = 5
@export_range(1, 8, 1) var road_min_branch_spacing_tiles: int = 5
@export var road_enable_service_pocket: bool = true

@export_category("Placement Rules")
@export var blocked_node_paths: Array[NodePath] = []
@export var blocked_node_radius_px: float = 120.0
@export var avoid_layer_path: NodePath
@export_range(0, 8, 1) var avoid_layer_radius_tiles: int = 0
@export var avoid_layer_paths: Array[NodePath] = []
@export var overlap_clear_layer_paths: Array[NodePath] = []
@export_range(0, 8, 1) var overlap_clear_radius_tiles: int = 0
@export var prefer_layer_path: NodePath
@export_range(0, 8, 1) var prefer_layer_radius_tiles: int = 0
@export_range(0.0, 1.0, 0.01) var prefer_layer_fill_bonus: float = 0.0

@export_category("Debug")
@export var debug_log: bool = false

var _tile_map: TileMapLayer
var _avoid_layer: TileMapLayer
var _avoid_layers: Array = []
var _overlap_clear_layers: Array = []
var _prefer_layer: TileMapLayer
var _player: Node2D
var _loaded_chunks := {}
var _last_center_chunk := Vector2i(999999, 999999)
var _update_timer: float = 0.0
var _world_min_chunk: Vector2i
var _world_max_chunk: Vector2i
var _blocked_world_positions: Array[Vector2] = []
var _protected_cells := {}


func _ready() -> void:
	if config != null:
		_apply_config(config)

	if not enabled:
		set_process(false)
		return

	_tile_map = get_node_or_null(tile_map_path) as TileMapLayer
	_avoid_layer = null
	_avoid_layers.clear()
	_overlap_clear_layers.clear()
	if avoid_layer_path != NodePath(""):
		_avoid_layer = get_node_or_null(avoid_layer_path) as TileMapLayer
		if _avoid_layer != null:
			_avoid_layers.append(_avoid_layer)
	for p in avoid_layer_paths:
		if p == NodePath(""):
			continue
		var avoid_candidate := get_node_or_null(p) as TileMapLayer
		if avoid_candidate != null and not _avoid_layers.has(avoid_candidate):
			_avoid_layers.append(avoid_candidate)
	for p in overlap_clear_layer_paths:
		if p == NodePath(""):
			continue
		var clear_layer_candidate := get_node_or_null(p) as TileMapLayer
		if clear_layer_candidate != null and clear_layer_candidate != _tile_map and not _overlap_clear_layers.has(clear_layer_candidate):
			_overlap_clear_layers.append(clear_layer_candidate)
	_prefer_layer = null
	if prefer_layer_path != NodePath(""):
		_prefer_layer = get_node_or_null(prefer_layer_path) as TileMapLayer
	_player = get_node_or_null(player_path) as Node2D

	# Fallback for scenes where explicit path was changed in editor.
	if _tile_map == null and use_terrain_connect:
		_tile_map = _resolve_fallback_tile_map()

	if _tile_map == null:
		push_error("ChunkWorldGenerator: TileMapLayer not found by tile_map_path")
		set_process(false)
		return

	if _player == null:
		push_error("ChunkWorldGenerator: Player not found by player_path")
		set_process(false)
		return

	if randomize_seed_on_start:
		var time_seed := int(Time.get_unix_time_from_system())
		var tick_seed := int(Time.get_ticks_usec())
		world_seed = abs(time_seed ^ tick_seed)

	if preserve_editor_tiles:
		_cache_protected_cells()

	if not use_terrain_connect and tile_options_atlas.is_empty():
		push_error("ChunkWorldGenerator: tile_options_atlas is empty")
		set_process(false)
		return
	if use_terrain_connect and not _ensure_valid_terrain_target():
		set_process(false)
		return

	_collect_blocked_positions()
	_init_world_bounds()

	if clear_existing_on_start:
		_clear_existing_cells()

	_update_visible_chunks(true)


func _apply_config(cfg: ChunkWorldGeneratorConfig) -> void:
	enabled = cfg.enabled
	tile_map_path = cfg.tile_map_path
	player_path = cfg.player_path
	chunk_size_tiles = cfg.chunk_size_tiles
	load_radius_chunks = cfg.load_radius_chunks
	world_chunks_x = cfg.world_chunks_x
	world_chunks_y = cfg.world_chunks_y
	clear_existing_on_start = cfg.clear_existing_on_start
	preserve_editor_tiles = cfg.preserve_editor_tiles
	update_interval_sec = cfg.update_interval_sec
	world_seed = cfg.world_seed
	randomize_seed_on_start = cfg.randomize_seed_on_start
	fill_probability = cfg.fill_probability
	ensure_non_empty_chunk = cfg.ensure_non_empty_chunk
	biome_partition_enabled = cfg.biome_partition_enabled
	biome_partition_count = cfg.biome_partition_count
	biome_partition_index = cfg.biome_partition_index
	biome_partition_period_chunks = cfg.biome_partition_period_chunks
	biome_half_split_enabled = cfg.biome_half_split_enabled
	biome_half_split_vertical = cfg.biome_half_split_vertical
	biome_half_split_upper_or_left = cfg.biome_half_split_upper_or_left
	source_id = cfg.source_id
	tile_options_atlas = cfg.tile_options_atlas.duplicate()
	tile_option_weights = cfg.tile_option_weights.duplicate()
	use_terrain_connect = cfg.use_terrain_connect
	terrain_set_id = cfg.terrain_set_id
	terrain_id = cfg.terrain_id
	terrain_ignore_empty = cfg.terrain_ignore_empty
	terrain_blob_mode = cfg.terrain_blob_mode
	road_corner_atlas = cfg.road_corner_atlas
	road_corner_alt_up_left = cfg.road_corner_alt_up_left
	road_corner_alt_up_right = cfg.road_corner_alt_up_right
	road_corner_alt_down_left = cfg.road_corner_alt_down_left
	road_corner_alt_down_right = cfg.road_corner_alt_down_right
	road_t_atlas = cfg.road_t_atlas
	road_t_alt_missing_up = cfg.road_t_alt_missing_up
	road_t_alt_missing_down = cfg.road_t_alt_missing_down
	road_t_alt_missing_left = cfg.road_t_alt_missing_left
	road_t_alt_missing_right = cfg.road_t_alt_missing_right
	road_cross_atlas = cfg.road_cross_atlas
	road_cross_alternative = cfg.road_cross_alternative
	road_min_straight_before_turn = cfg.road_min_straight_before_turn
	road_turn_jitter_chance = cfg.road_turn_jitter_chance
	road_side_jog_chance = cfg.road_side_jog_chance
	road_branch_density = cfg.road_branch_density
	road_max_branches_per_chunk = cfg.road_max_branches_per_chunk
	road_continue_direction_chance = cfg.road_continue_direction_chance
	road_trim_dead_end_max_len = cfg.road_trim_dead_end_max_len
	road_force_center_connector = cfg.road_force_center_connector
	road_trunk_period_chunks = cfg.road_trunk_period_chunks
	road_min_branch_spacing_tiles = cfg.road_min_branch_spacing_tiles
	road_enable_service_pocket = cfg.road_enable_service_pocket
	blocked_node_paths = cfg.blocked_node_paths.duplicate()
	blocked_node_radius_px = cfg.blocked_node_radius_px
	avoid_layer_path = cfg.avoid_layer_path
	avoid_layer_radius_tiles = cfg.avoid_layer_radius_tiles
	avoid_layer_paths = cfg.avoid_layer_paths.duplicate()
	overlap_clear_layer_paths = cfg.overlap_clear_layer_paths.duplicate()
	overlap_clear_radius_tiles = cfg.overlap_clear_radius_tiles
	prefer_layer_path = cfg.prefer_layer_path
	prefer_layer_radius_tiles = cfg.prefer_layer_radius_tiles
	prefer_layer_fill_bonus = cfg.prefer_layer_fill_bonus
	debug_log = cfg.debug_log


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer < update_interval_sec:
		return
	_update_timer = 0.0

	_update_visible_chunks(false)


func _init_world_bounds() -> void:
	var player_cell := _tile_map.local_to_map(_tile_map.to_local(_player.global_position))
	var start_chunk := _world_to_chunk(player_cell)
	var half_x := int(floor(world_chunks_x / 2.0))
	var half_y := int(floor(world_chunks_y / 2.0))

	_world_min_chunk = Vector2i(start_chunk.x - half_x, start_chunk.y - half_y)
	_world_max_chunk = Vector2i(
		_world_min_chunk.x + world_chunks_x - 1,
		_world_min_chunk.y + world_chunks_y - 1
	)


func _update_visible_chunks(force: bool) -> void:
	var player_cell := _tile_map.local_to_map(_tile_map.to_local(_player.global_position))
	var center_chunk := _world_to_chunk(player_cell)
	if not force and center_chunk == _last_center_chunk:
		return

	_last_center_chunk = center_chunk
	var required_chunks := {}

	for cy in range(center_chunk.y - load_radius_chunks, center_chunk.y + load_radius_chunks + 1):
		for cx in range(center_chunk.x - load_radius_chunks, center_chunk.x + load_radius_chunks + 1):
			var chunk := Vector2i(cx, cy)
			if not _is_chunk_in_world(chunk):
				continue

			required_chunks[chunk] = true
			if not _loaded_chunks.has(chunk):
				_generate_chunk(chunk)
				_loaded_chunks[chunk] = true

	var to_unload: Array[Vector2i] = []
	for chunk_key in _loaded_chunks.keys():
		var loaded_chunk := chunk_key as Vector2i
		if not required_chunks.has(loaded_chunk):
			to_unload.append(loaded_chunk)

	for chunk in to_unload:
		_unload_chunk(chunk)
		_loaded_chunks.erase(chunk)


func _is_chunk_in_world(chunk: Vector2i) -> bool:
	return chunk.x >= _world_min_chunk.x and chunk.x <= _world_max_chunk.x and chunk.y >= _world_min_chunk.y and chunk.y <= _world_max_chunk.y


func _world_to_chunk(cell: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(cell.x) / float(chunk_size_tiles)),
		floori(float(cell.y) / float(chunk_size_tiles))
	)


func _generate_chunk(chunk: Vector2i) -> void:
	if not _is_chunk_allowed_for_biome(chunk):
		_unload_chunk(chunk)
		return

	var origin := chunk * chunk_size_tiles
	var placed_count := 0
	var occupied := {}
	var terrain_cells: Array[Vector2i] = []

	if use_terrain_connect:
		if terrain_blob_mode:
			terrain_cells = _collect_blob_terrain_cells(chunk, origin, occupied)
		else:
			terrain_cells = _collect_connected_terrain_cells(chunk, origin, occupied)
		placed_count = terrain_cells.size()
		if ensure_non_empty_chunk and fill_probability > 0.0 and placed_count == 0:
			var fallback_cell := _pick_fallback_cell(origin)
			var fallback_local := fallback_cell - origin
			if _can_place(chunk, fallback_local, Vector2i.ONE, occupied) and not _overlaps_blocked_nodes(fallback_cell, Vector2i.ONE) and not _is_protected_cell(fallback_cell):
				terrain_cells.append(fallback_cell)
				_mark_occupied(fallback_local, Vector2i.ONE, occupied)

		if not terrain_cells.is_empty():
			_tile_map.set_cells_terrain_connect(terrain_cells, terrain_set_id, terrain_id, terrain_ignore_empty)
			_clear_overlapping_layers(terrain_cells)
			if not terrain_blob_mode:
				_apply_corner_alternatives(terrain_cells)
		return

	var placed_cells: Array[Vector2i] = []
	for local_y in range(chunk_size_tiles):
		for local_x in range(chunk_size_tiles):
			var cell := origin + Vector2i(local_x, local_y)
			var fill_prob := fill_probability
			if _is_near_prefer_layer(cell):
				fill_prob = clampf(fill_prob + prefer_layer_fill_bonus, 0.0, 1.0)
			if _cell_fill_roll(cell) > fill_prob:
				if not _is_protected_cell(cell):
					_tile_map.erase_cell(cell)
				continue

			var atlas := _pick_tile(cell)
			var local_cell := Vector2i(local_x, local_y)
			if _is_blocked_by_avoid_layer(cell):
				if not _is_protected_cell(cell):
					_tile_map.erase_cell(cell)
				continue
			if _try_place_tile(chunk, origin, local_cell, cell, atlas, occupied):
				placed_count += 1
				placed_cells.append(cell)
			else:
				if not _is_protected_cell(cell):
					_tile_map.erase_cell(cell)

	if ensure_non_empty_chunk and fill_probability > 0.0 and placed_count == 0:
		var fallback_cell := _pick_fallback_cell(origin)
		var fallback_local := fallback_cell - origin
		var fallback_atlas := _pick_tile(fallback_cell)
		_try_place_tile(chunk, origin, fallback_local, fallback_cell, fallback_atlas, occupied)
		placed_cells.append(fallback_cell)
	_clear_overlapping_layers(placed_cells)


func _unload_chunk(chunk: Vector2i) -> void:
	var origin := chunk * chunk_size_tiles

	for local_y in range(chunk_size_tiles):
		for local_x in range(chunk_size_tiles):
			var cell := origin + Vector2i(local_x, local_y)
			if not _is_protected_cell(cell):
				_tile_map.erase_cell(cell)


func _pick_tile(cell: Vector2i) -> Vector2i:
	var valid_options: Array[Vector2i] = []
	var valid_weights: Array[float] = []
	for i in range(tile_options_atlas.size()):
		var atlas := tile_options_atlas[i]
		if not _is_valid_atlas_tile(atlas):
			continue
		valid_options.append(atlas)
		if i < tile_option_weights.size():
			valid_weights.append(maxf(tile_option_weights[i], 0.0))
		else:
			valid_weights.append(1.0)

	if valid_options.is_empty():
		return _get_first_available_atlas_tile()

	var option_count := valid_options.size()
	if option_count <= 1:
		return valid_options[0]
	if tile_option_weights.size() != tile_options_atlas.size():
		var idx := int(_hash_cell(cell.x, cell.y, world_seed) % option_count)
		return valid_options[idx]

	var total_weight := 0.0
	for i in range(option_count):
		total_weight += valid_weights[i]
	if total_weight <= 0.0:
		return valid_options[0]

	var h := _hash_cell(cell.x, cell.y, world_seed + 3333)
	var roll := (float(h % 100000) / 100000.0) * total_weight
	var acc := 0.0
	for i in range(option_count):
		acc += valid_weights[i]
		if roll <= acc:
			return valid_options[i]
	return valid_options[option_count - 1]


func _cell_fill_roll(cell: Vector2i) -> float:
	var value := _hash_cell(cell.x, cell.y, world_seed + 911)
	return float(value % 10000) / 10000.0


func _hash_cell(x: int, y: int, seed_value: int) -> int:
	var h := int(seed_value)
	h = int((h * 73856093) ^ (x * 19349663) ^ (y * 83492791))
	if h < 0:
		h = -h
	return h


func _clear_existing_cells() -> void:
	for cell in _tile_map.get_used_cells():
		if _is_protected_cell(cell):
			continue
		_tile_map.erase_cell(cell)


func _pick_fallback_cell(chunk_origin: Vector2i) -> Vector2i:
	var index_seed := _hash_cell(chunk_origin.x, chunk_origin.y, world_seed + 4242)
	var chunk_cells := chunk_size_tiles * chunk_size_tiles
	var idx := index_seed % chunk_cells
	var local_x := idx % chunk_size_tiles
	var local_y := int(floor(float(idx) / float(chunk_size_tiles)))
	return chunk_origin + Vector2i(local_x, local_y)


func _is_chunk_allowed_for_biome(chunk: Vector2i) -> bool:
	if biome_half_split_enabled:
		if biome_half_split_vertical:
			var half_x := _world_min_chunk.x + int(floor(world_chunks_x / 2.0))
			return chunk.x < half_x if biome_half_split_upper_or_left else chunk.x >= half_x
		var half_y := _world_min_chunk.y + int(floor(world_chunks_y / 2.0))
		return chunk.y < half_y if biome_half_split_upper_or_left else chunk.y >= half_y

	if not biome_partition_enabled:
		return true
	var count := maxi(2, biome_partition_count)
	var index := clampi(biome_partition_index, 0, count - 1)
	var period := maxi(2, biome_partition_period_chunks)
	var gx := floori(float(chunk.x) / float(period))
	var gy := floori(float(chunk.y) / float(period))
	var h := _hash_cell(gx, gy, world_seed + 9127)
	return posmod(h, count) == index


func _collect_connected_terrain_cells(chunk: Vector2i, origin: Vector2i, occupied: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var used_world: Dictionary = {}
	var anchors: Array[Vector2i] = _get_chunk_road_anchors(chunk)
	if anchors.size() < 2:
		return result
	var target_count := maxi(0, int(round(float(chunk_size_tiles * chunk_size_tiles) * fill_probability)))
	target_count = maxi(target_count, anchors.size() * 5)
	if target_count <= 0:
		return result

	var hub_sum := Vector2i.ZERO
	for a in anchors:
		hub_sum += a
	var hub := Vector2i(
		clampi(int(round(float(hub_sum.x) / float(anchors.size()))), 0, chunk_size_tiles - 1),
		clampi(int(round(float(hub_sum.y) / float(anchors.size()))), 0, chunk_size_tiles - 1)
	)

	var jitter_hash := _hash_cell(chunk.x * 17, chunk.y * 23, world_seed + 7711)
	hub += Vector2i((jitter_hash % 3) - 1, ((int(jitter_hash / 3)) % 3) - 1)
	hub.x = clampi(hub.x, 0, chunk_size_tiles - 1)
	hub.y = clampi(hub.y, 0, chunk_size_tiles - 1)

	var path_id: int = 0
	for anchor in anchors:
		if result.size() >= target_count:
			break
		_append_terrain_path(chunk, origin, anchor, hub, path_id, target_count, result, used_world, occupied)
		path_id += 1

	var branch_count := clampi(int(round(float(anchors.size()) * road_branch_density)), 0, road_max_branches_per_chunk)
	for b in range(branch_count):
		if result.size() >= target_count:
			break
		var branch_hash := _hash_cell(chunk.x * 97 + b * 7, chunk.y * 101 - b * 11, world_seed + 7861)
		if branch_hash % 100 >= int(round(road_branch_density * 100.0)):
			continue
		var dir := Vector2i.RIGHT
		match branch_hash % 4:
			0:
				dir = Vector2i.RIGHT
			1:
				dir = Vector2i.LEFT
			2:
				dir = Vector2i.UP
			_:
				dir = Vector2i.DOWN
		var branch_len := 4 + (branch_hash % 4)
		var branch_end := hub + dir * branch_len
		branch_end.x = clampi(branch_end.x, 0, chunk_size_tiles - 1)
		branch_end.y = clampi(branch_end.y, 0, chunk_size_tiles - 1)
		_append_terrain_path(chunk, origin, hub, branch_end, path_id + 301 + b, target_count, result, used_world, occupied)

	if road_force_center_connector and result.size() < target_count:
		var center := Vector2i(int(chunk_size_tiles / 2), int(chunk_size_tiles / 2))
		_append_terrain_path(chunk, origin, hub, center, path_id + 451, target_count, result, used_world, occupied)
		if road_enable_service_pocket:
			_add_service_pocket(chunk, origin, center, path_id + 509, target_count, result, used_world, occupied)

	if anchors.size() == 2 and result.size() < target_count:
		_append_terrain_path(chunk, origin, anchors[0], anchors[1], path_id + 101, target_count, result, used_world, occupied)

	result = _connect_road_components(chunk, origin, result, used_world, occupied)
	result = _trim_short_dead_ends(chunk, origin, result, anchors)
	result = _remove_isolated_cells(result)

	return result


func _collect_blob_terrain_cells(chunk: Vector2i, origin: Vector2i, occupied: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var target_count := maxi(0, int(round(float(chunk_size_tiles * chunk_size_tiles) * fill_probability)))
	if target_count <= 0:
		return result

	var side_min := 2
	var side_max := maxi(2, chunk_size_tiles - 1)
	var area_min := side_min * side_min
	var area_max := side_max * side_max
	var target_area := clampi(target_count, area_min, area_max)

	var candidates: Array[Vector2i] = []
	var side_base := clampi(int(round(sqrt(float(target_area)))), side_min, side_max)
	candidates.append(Vector2i(side_base, side_base))
	candidates.append(Vector2i(clampi(side_base + 1, side_min, side_max), side_base))
	candidates.append(Vector2i(side_base, clampi(side_base + 1, side_min, side_max)))
	candidates.append(Vector2i(clampi(side_base + 2, side_min, side_max), side_base))
	candidates.append(Vector2i(side_base, clampi(side_base + 2, side_min, side_max)))
	candidates.append(Vector2i(clampi(side_base + 1, side_min, side_max), clampi(side_base + 1, side_min, side_max)))

	for i in range(candidates.size()):
		var size := candidates[i] as Vector2i
		if size.x <= 0 or size.y <= 0:
			continue
		if size.x > chunk_size_tiles or size.y > chunk_size_tiles:
			continue

		var max_x := chunk_size_tiles - size.x
		var max_y := chunk_size_tiles - size.y
		var h := _hash_cell(chunk.x * 733 + i * 17, chunk.y * 977 - i * 23, world_seed + 12341)
		var x0 := 0 if max_x <= 0 else (h % (max_x + 1))
		var y0 := 0 if max_y <= 0 else ((int(h / 97)) % (max_y + 1))
		var local_origin := Vector2i(x0, y0)

		if not _can_place_lake_rect(chunk, origin, local_origin, size, occupied):
			continue

		var used_world: Dictionary = {}
		for ly in range(size.y):
			for lx in range(size.x):
				var local_cell := local_origin + Vector2i(lx, ly)
				_try_add_terrain_local(chunk, origin, local_cell, result, used_world, occupied)
		return result

	return result


func _can_place_lake_rect(
	chunk: Vector2i,
	origin: Vector2i,
	local_origin: Vector2i,
	size: Vector2i,
	occupied: Dictionary
) -> bool:
	for ly in range(size.y):
		for lx in range(size.x):
			var local_cell := local_origin + Vector2i(lx, ly)
			var world_cell := origin + local_cell
			if not _can_place(chunk, local_cell, Vector2i.ONE, occupied):
				return false
			if _is_protected_cell(world_cell):
				return false
			if _is_blocked_by_avoid_layer(world_cell):
				return false
			if _overlaps_blocked_nodes(world_cell, Vector2i.ONE):
				return false
	return true


func _get_chunk_road_anchors(chunk: Vector2i) -> Array[Vector2i]:
	var anchors: Array[Vector2i] = []
	var is_trunk := _is_trunk_chunk(chunk)
	var border_chance := clampi(int(round(fill_probability * 220.0)), 8, 85)
	if not is_trunk:
		border_chance = int(round(border_chance * 0.6))

	if chunk.x > _world_min_chunk.x and _is_vertical_border_active(chunk.x - 1, chunk.y, border_chance):
		anchors.append(Vector2i(0, _vertical_border_anchor(chunk.x - 1, chunk.y)))
	if chunk.x < _world_max_chunk.x and _is_vertical_border_active(chunk.x, chunk.y, border_chance):
		anchors.append(Vector2i(chunk_size_tiles - 1, _vertical_border_anchor(chunk.x, chunk.y)))
	if chunk.y > _world_min_chunk.y and _is_horizontal_border_active(chunk.x, chunk.y - 1, border_chance):
		anchors.append(Vector2i(_horizontal_border_anchor(chunk.x, chunk.y - 1), 0))
	if chunk.y < _world_max_chunk.y and _is_horizontal_border_active(chunk.x, chunk.y, border_chance):
		anchors.append(Vector2i(_horizontal_border_anchor(chunk.x, chunk.y), chunk_size_tiles - 1))

	var unique := {}
	var deduped: Array[Vector2i] = []
	for a in anchors:
		if unique.has(a):
			continue
		unique[a] = true
		deduped.append(a)

	if deduped.is_empty():
		var trunk_chance := clampi(int(round(fill_probability * 120.0)), 4, 35)
		var trunk_hash := _hash_cell(chunk.x * 37, chunk.y * 41, world_seed + 7757)
		if trunk_hash % 100 < trunk_chance:
			var lane := trunk_hash % chunk_size_tiles
			if (int(trunk_hash / 3)) % 2 == 0:
				deduped.append(Vector2i(0, lane))
				deduped.append(Vector2i(chunk_size_tiles - 1, lane))
			else:
				deduped.append(Vector2i(lane, 0))
				deduped.append(Vector2i(lane, chunk_size_tiles - 1))
	elif deduped.size() == 1:
		deduped.append(_opposite_border_anchor(deduped[0]))

	var cross_hash := _hash_cell(chunk.x * 109 + 3, chunk.y * 113 + 5, world_seed + 7919)
	var cross_chance := clampi(int(round(fill_probability * 180.0)), 15, 72)
	if not is_trunk:
		cross_chance = int(round(cross_chance * 0.45))
	if cross_hash % 100 < cross_chance:
		var y_lane := (int(cross_hash / 7)) % chunk_size_tiles
		deduped.append(Vector2i(0, y_lane))
		deduped.append(Vector2i(chunk_size_tiles - 1, y_lane))
	if (int(cross_hash / 11)) % 100 < int(cross_chance / 2):
		var x_lane := (int(cross_hash / 13)) % chunk_size_tiles
		deduped.append(Vector2i(x_lane, 0))
		deduped.append(Vector2i(x_lane, chunk_size_tiles - 1))

	if deduped.size() > 6:
		var reduced: Array[Vector2i] = []
		for i in range(6):
			reduced.append(deduped[i])
		deduped = reduced
	deduped = _enforce_anchor_spacing(deduped)

	return deduped


func _opposite_border_anchor(anchor: Vector2i) -> Vector2i:
	if anchor.x == 0:
		return Vector2i(chunk_size_tiles - 1, anchor.y)
	if anchor.x == chunk_size_tiles - 1:
		return Vector2i(0, anchor.y)
	if anchor.y == 0:
		return Vector2i(anchor.x, chunk_size_tiles - 1)
	return Vector2i(anchor.x, 0)


func _is_vertical_border_active(x_border: int, y_chunk: int, chance: int) -> bool:
	var h := _hash_cell(x_border * 911 + 17, y_chunk * 547 + 31, world_seed + 7603)
	return h % 100 < chance


func _is_horizontal_border_active(x_chunk: int, y_border: int, chance: int) -> bool:
	var h := _hash_cell(x_chunk * 613 + 19, y_border * 983 + 29, world_seed + 7639)
	return h % 100 < chance


func _is_trunk_chunk(chunk: Vector2i) -> bool:
	var period := maxi(2, road_trunk_period_chunks)
	var x_lane := posmod(_hash_cell(1001, 73, world_seed + 8011), period)
	var y_lane := posmod(_hash_cell(67, 2003, world_seed + 8039), period)
	var on_x_lane := posmod(chunk.x, period) == x_lane
	var on_y_lane := posmod(chunk.y, period) == y_lane
	var x_gate := posmod(_hash_cell(chunk.y, chunk.x * 3 + 11, world_seed + 8053), 100) < 62
	var y_gate := posmod(_hash_cell(chunk.x, chunk.y * 5 + 17, world_seed + 8081), 100) < 62
	return (on_x_lane and x_gate) or (on_y_lane and y_gate)


func _enforce_anchor_spacing(anchors: Array[Vector2i]) -> Array[Vector2i]:
	if anchors.size() <= 2:
		return anchors
	var filtered: Array[Vector2i] = []
	var min_gap := maxi(1, road_min_branch_spacing_tiles)
	for a in anchors:
		var keep := true
		for b in filtered:
			if _anchors_too_close(a, b, min_gap):
				keep = false
				break
		if keep:
			filtered.append(a)
	return filtered


func _anchors_too_close(a: Vector2i, b: Vector2i, min_gap: int) -> bool:
	var a_is_lr := a.x == 0 or a.x == chunk_size_tiles - 1
	var b_is_lr := b.x == 0 or b.x == chunk_size_tiles - 1
	var a_is_tb := a.y == 0 or a.y == chunk_size_tiles - 1
	var b_is_tb := b.y == 0 or b.y == chunk_size_tiles - 1
	if a_is_lr and b_is_lr:
		return absi(a.y - b.y) < min_gap
	if a_is_tb and b_is_tb:
		return absi(a.x - b.x) < min_gap
	return false


func _vertical_border_anchor(x_border: int, y_chunk: int) -> int:
	var h := _hash_cell(x_border * 733 + 43, y_chunk * 421 + 37, world_seed + 7673)
	return h % chunk_size_tiles


func _horizontal_border_anchor(x_chunk: int, y_border: int) -> int:
	var h := _hash_cell(x_chunk * 467 + 53, y_border * 877 + 41, world_seed + 7699)
	return h % chunk_size_tiles


func _append_terrain_path(
	chunk: Vector2i,
	origin: Vector2i,
	start_local: Vector2i,
	end_local: Vector2i,
	path_id: int,
	target_count: int,
	result: Array[Vector2i],
	used_world: Dictionary,
	occupied: Dictionary
) -> void:
	var current := start_local
	var max_steps := chunk_size_tiles * chunk_size_tiles * 3
	var last_dir := Vector2i.ZERO
	var straight_steps := 0

	for step in range(max_steps):
		_try_add_terrain_local(chunk, origin, current, result, used_world, occupied)
		if result.size() >= target_count:
			return
		if current == end_local:
			return

		var dx := end_local.x - current.x
		var dy := end_local.y - current.y
		var prefer_x := absi(dx) >= absi(dy)
		var h := _hash_cell(origin.x + path_id * 59 + step, origin.y - path_id * 43 - step, world_seed + 7817)

		if h % 100 < road_turn_jitter_chance and straight_steps >= road_min_straight_before_turn:
			prefer_x = not prefer_x

		var next := current
		var current_dist := absi(dx) + absi(dy)
		var can_continue := last_dir != Vector2i.ZERO and (straight_steps < road_min_straight_before_turn or h % 100 < road_continue_direction_chance)
		if can_continue:
			var forward := current + last_dir
			if _is_local_cell_inside_chunk(forward):
				var forward_dist := absi(end_local.x - forward.x) + absi(end_local.y - forward.y)
				if forward_dist <= current_dist + 1:
					next = forward

		if next != current:
			pass
		elif prefer_x and dx != 0:
			next.x += signi(dx)
		elif dy != 0:
			next.y += signi(dy)
		elif dx != 0:
			next.x += signi(dx)

		if h % 100 < int(maxi(0, road_turn_jitter_chance / 2)) and straight_steps >= road_min_straight_before_turn:
			if prefer_x and dy != 0:
				next.y += signi(dy)
			elif not prefer_x and dx != 0:
				next.x += signi(dx)

		next.x = clampi(next.x, 0, chunk_size_tiles - 1)
		next.y = clampi(next.y, 0, chunk_size_tiles - 1)
		if next == current:
			return

		var step_dir := next - current
		if step_dir == last_dir:
			straight_steps += 1
		else:
			straight_steps = 1
			last_dir = step_dir

		current = next
		if result.size() >= target_count:
			return

		if h % 100 < road_side_jog_chance and straight_steps >= road_min_straight_before_turn:
			var side_local := current
			var side_sign := -1
			if (int(h / 7)) % 2 != 0:
				side_sign = 1
			if absi(dx) >= absi(dy):
				side_local.y += side_sign
			else:
				side_local.x += side_sign
			_try_add_terrain_local(chunk, origin, side_local, result, used_world, occupied)
			if result.size() >= target_count:
				return


func _try_add_terrain_local(
	chunk: Vector2i,
	origin: Vector2i,
	local_cell: Vector2i,
	result: Array[Vector2i],
	used_world: Dictionary,
	occupied: Dictionary
) -> void:
	if local_cell.x < 0 or local_cell.y < 0 or local_cell.x >= chunk_size_tiles or local_cell.y >= chunk_size_tiles:
		return

	var world_cell := origin + local_cell
	if used_world.has(world_cell):
		return
	if _is_protected_cell(world_cell):
		return
	if _is_blocked_by_avoid_layer(world_cell):
		return
	if not _can_place(chunk, local_cell, Vector2i.ONE, occupied):
		return
	if _overlaps_blocked_nodes(world_cell, Vector2i.ONE):
		return

	result.append(world_cell)
	used_world[world_cell] = true
	_mark_occupied(local_cell, Vector2i.ONE, occupied)


func _connect_road_components(
	chunk: Vector2i,
	origin: Vector2i,
	cells: Array[Vector2i],
	used_world: Dictionary,
	occupied: Dictionary
) -> Array[Vector2i]:
	if cells.size() < 2:
		return cells

	var world_set: Dictionary = {}
	for w in cells:
		world_set[w] = true

	var components: Array = []
	var visited: Dictionary = {}
	for w in cells:
		if visited.has(w):
			continue
		var comp: Array[Vector2i] = []
		var stack: Array[Vector2i] = [w]
		visited[w] = true
		while not stack.is_empty():
			var cur: Vector2i = stack.pop_back() as Vector2i
			comp.append(cur)
			for n in _world_neighbors(cur):
				if not world_set.has(n):
					continue
				if visited.has(n):
					continue
				visited[n] = true
				stack.append(n)
		components.append(comp)

	if components.size() <= 1:
		return cells

	var main_component: Array[Vector2i] = components[0] as Array[Vector2i]
	for i in range(1, components.size()):
		var candidate: Array[Vector2i] = components[i] as Array[Vector2i]
		if candidate.size() > main_component.size():
			main_component = candidate
	var main_set: Dictionary = {}
	for w in main_component:
		main_set[w] = true

	for i in range(1, components.size()):
		var comp: Array[Vector2i] = components[i] as Array[Vector2i]
		if comp == main_component:
			continue
		var best_a: Vector2i = main_component[0]
		var best_b: Vector2i = comp[0]
		var best_d: int = 1 << 30
		for a in main_component:
			for b in comp:
				var d := absi(a.x - b.x) + absi(a.y - b.y)
				if d < best_d:
					best_d = d
					best_a = a
					best_b = b
		_carve_manhattan_bridge(chunk, origin, best_a, best_b, cells, used_world, occupied)
		for w in comp:
			if not main_set.has(w):
				main_set[w] = true
				main_component.append(w)
		for w in cells:
			if not main_set.has(w):
				main_set[w] = true
				main_component.append(w)

	return cells


func _carve_manhattan_bridge(
	chunk: Vector2i,
	origin: Vector2i,
	start_world: Vector2i,
	end_world: Vector2i,
	cells: Array[Vector2i],
	used_world: Dictionary,
	occupied: Dictionary
) -> void:
	var current := start_world
	var max_steps := chunk_size_tiles * chunk_size_tiles * 2
	for step in range(max_steps):
		_try_add_terrain_local(chunk, origin, current - origin, cells, used_world, occupied)
		if current == end_world:
			return
		var dx := end_world.x - current.x
		var dy := end_world.y - current.y
		if absi(dx) >= absi(dy):
			if dx != 0:
				current.x += signi(dx)
			elif dy != 0:
				current.y += signi(dy)
		else:
			if dy != 0:
				current.y += signi(dy)
			elif dx != 0:
				current.x += signi(dx)


func _trim_short_dead_ends(
	_chunk: Vector2i,
	origin: Vector2i,
	cells: Array[Vector2i],
	anchors: Array[Vector2i]
) -> Array[Vector2i]:
	if cells.size() < 4:
		return cells

	var keep_world: Dictionary = {}
	for a in anchors:
		keep_world[origin + a] = true

	var world_set: Dictionary = {}
	for w in cells:
		world_set[w] = true

	var changed := true
	while changed:
		changed = false
		var endpoints: Array[Vector2i] = []
		for w in world_set.keys():
			var world_cell := w as Vector2i
			var deg := _world_degree(world_cell, world_set)
			if deg <= 1 and not keep_world.has(world_cell):
				endpoints.append(world_cell)

		for e in endpoints:
			if not world_set.has(e):
				continue
			var branch: Array[Vector2i] = []
			var cur: Vector2i = e
			var prev := Vector2i(999999, 999999)
			var max_len := road_trim_dead_end_max_len

			for _i in range(max_len):
				if keep_world.has(cur):
					break
				branch.append(cur)
				var neighbors: Array[Vector2i] = _world_neighbors_in_set(cur, world_set)
				if neighbors.is_empty():
					break
				var next: Vector2i = neighbors[0]
				if neighbors.size() > 1 and next == prev:
					next = neighbors[1]
				if next == prev:
					break
				prev = cur
				cur = next
				if _world_degree(cur, world_set) != 2:
					break

			var end_degree := _world_degree(cur, world_set)
			if branch.size() <= road_trim_dead_end_max_len and end_degree >= 2:
				var has_corner := false
				for b in branch:
					if _is_corner_cell(b, world_set):
						has_corner = true
						break
				if has_corner:
					continue
				for b in branch:
					if keep_world.has(b):
						continue
					world_set.erase(b)
					changed = true

	var trimmed: Array[Vector2i] = []
	for w in world_set.keys():
		trimmed.append(w as Vector2i)
	return trimmed


func _world_neighbors(world_cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.append(world_cell + Vector2i.RIGHT)
	out.append(world_cell + Vector2i.LEFT)
	out.append(world_cell + Vector2i.UP)
	out.append(world_cell + Vector2i.DOWN)
	return out


func _is_local_cell_inside_chunk(local_cell: Vector2i) -> bool:
	return local_cell.x >= 0 and local_cell.y >= 0 and local_cell.x < chunk_size_tiles and local_cell.y < chunk_size_tiles


func _world_neighbors_in_set(world_cell: Vector2i, world_set: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for n in _world_neighbors(world_cell):
		if world_set.has(n):
			out.append(n)
	return out


func _world_degree(world_cell: Vector2i, world_set: Dictionary) -> int:
	return _world_neighbors_in_set(world_cell, world_set).size()


func _is_corner_cell(world_cell: Vector2i, world_set: Dictionary) -> bool:
	var up := world_set.has(world_cell + Vector2i.UP)
	var down := world_set.has(world_cell + Vector2i.DOWN)
	var left := world_set.has(world_cell + Vector2i.LEFT)
	var right := world_set.has(world_cell + Vector2i.RIGHT)
	var degree := int(up) + int(down) + int(left) + int(right)
	if degree != 2:
		return false
	return (up and left) or (up and right) or (down and left) or (down and right)


func _is_blocked_by_avoid_layer(world_cell: Vector2i) -> bool:
	if _avoid_layers.is_empty() or avoid_layer_radius_tiles < 0:
		return false
	for oy in range(-avoid_layer_radius_tiles, avoid_layer_radius_tiles + 1):
		for ox in range(-avoid_layer_radius_tiles, avoid_layer_radius_tiles + 1):
			var c := world_cell + Vector2i(ox, oy)
			for layer_item in _avoid_layers:
				var avoid := layer_item as TileMapLayer
				if avoid != null and avoid.get_cell_source_id(c) != -1:
					return true
	return false


func _clear_overlapping_layers(cells: Array[Vector2i]) -> void:
	if _overlap_clear_layers.is_empty() or cells.is_empty():
		return
	var radius: int = maxi(0, overlap_clear_radius_tiles)
	for cell in cells:
		for oy in range(-radius, radius + 1):
			for ox in range(-radius, radius + 1):
				var target_cell := cell + Vector2i(ox, oy)
				for layer_item in _overlap_clear_layers:
					var layer := layer_item as TileMapLayer
					if layer == null:
						continue
					layer.erase_cell(target_cell)


func _is_near_prefer_layer(world_cell: Vector2i) -> bool:
	if _prefer_layer == null or prefer_layer_radius_tiles <= 0:
		return false
	for oy in range(-prefer_layer_radius_tiles, prefer_layer_radius_tiles + 1):
		for ox in range(-prefer_layer_radius_tiles, prefer_layer_radius_tiles + 1):
			var c := world_cell + Vector2i(ox, oy)
			if _prefer_layer.get_cell_source_id(c) != -1:
				return true
	return false


func _add_service_pocket(
	chunk: Vector2i,
	origin: Vector2i,
	center: Vector2i,
	path_id: int,
	target_count: int,
	result: Array[Vector2i],
	used_world: Dictionary,
	occupied: Dictionary
) -> void:
	var h := _hash_cell(chunk.x * 191 + 17, chunk.y * 223 + 29, world_seed + 8111)
	var dir := Vector2i.RIGHT
	match h % 4:
		0:
			dir = Vector2i.RIGHT
		1:
			dir = Vector2i.LEFT
		2:
			dir = Vector2i.UP
		_:
			dir = Vector2i.DOWN
	var side := Vector2i(-dir.y, dir.x)
	var len_a := 3 + (h % 2)
	var len_b := 2 + ((int(h / 5)) % 2)
	var p1 := center + dir * len_a
	var p2 := p1 + side * len_b
	p1.x = clampi(p1.x, 0, chunk_size_tiles - 1)
	p1.y = clampi(p1.y, 0, chunk_size_tiles - 1)
	p2.x = clampi(p2.x, 0, chunk_size_tiles - 1)
	p2.y = clampi(p2.y, 0, chunk_size_tiles - 1)
	_append_terrain_path(chunk, origin, center, p1, path_id, target_count, result, used_world, occupied)
	_append_terrain_path(chunk, origin, p1, p2, path_id + 1, target_count, result, used_world, occupied)


func _apply_corner_alternatives(terrain_cells: Array[Vector2i]) -> void:
	var corner_enabled := road_corner_atlas.x >= 0 and road_corner_atlas.y >= 0
	var t_atlas := road_t_atlas
	if t_atlas.x < 0 or t_atlas.y < 0:
		t_atlas = road_corner_atlas
	var t_enabled := t_atlas.x >= 0 and t_atlas.y >= 0
	var cross_atlas := road_cross_atlas
	if cross_atlas.x < 0 or cross_atlas.y < 0:
		cross_atlas = road_corner_atlas
	var cross_enabled := cross_atlas.x >= 0 and cross_atlas.y >= 0 and road_cross_alternative >= 0
	if not corner_enabled and not t_enabled and not cross_enabled:
		return

	var terrain_set: Dictionary = {}
	for c in terrain_cells:
		terrain_set[c] = true

	var replaced_count: int = 0
	for c in terrain_cells:
		var up := terrain_set.has(c + Vector2i.UP)
		var down := terrain_set.has(c + Vector2i.DOWN)
		var left := terrain_set.has(c + Vector2i.LEFT)
		var right := terrain_set.has(c + Vector2i.RIGHT)
		var degree := int(up) + int(down) + int(left) + int(right)

		var alternative_id := -1
		if degree == 4 and cross_enabled:
			_tile_map.set_cell(c, source_id, cross_atlas, road_cross_alternative)
			replaced_count += 1
			continue

		if degree == 3 and t_enabled:
			if not up:
				alternative_id = road_t_alt_missing_up
			elif not down:
				alternative_id = road_t_alt_missing_down
			elif not left:
				alternative_id = road_t_alt_missing_left
			elif not right:
				alternative_id = road_t_alt_missing_right
			if alternative_id >= 0:
				_tile_map.set_cell(c, source_id, t_atlas, alternative_id)
				replaced_count += 1
				continue

		if degree == 2 and corner_enabled:
			if up and left:
				alternative_id = road_corner_alt_up_left
			elif up and right:
				alternative_id = road_corner_alt_up_right
			elif down and left:
				alternative_id = road_corner_alt_down_left
			elif down and right:
				alternative_id = road_corner_alt_down_right

			if alternative_id >= 0:
				_tile_map.set_cell(c, source_id, road_corner_atlas, alternative_id)
				replaced_count += 1
	if debug_log and replaced_count == 0:
		push_warning("ChunkWorldGenerator: no road alternatives applied. Check road_corner/road_t/road_cross settings and alternative ids.")


func _remove_isolated_cells(cells: Array[Vector2i]) -> Array[Vector2i]:
	if cells.size() <= 2:
		return cells
	var world_set: Dictionary = {}
	for w in cells:
		world_set[w] = true
	var filtered: Array[Vector2i] = []
	for w in cells:
		if _world_degree(w, world_set) == 0:
			continue
		filtered.append(w)
	return filtered


func _keep_largest_components(cells: Array[Vector2i], max_components: int, min_component_size: int) -> Array[Vector2i]:
	if cells.size() <= 1 or max_components <= 0:
		return cells

	var world_set: Dictionary = {}
	for w in cells:
		world_set[w] = true

	var visited: Dictionary = {}
	var components: Array = []
	for w in cells:
		if visited.has(w):
			continue
		var comp: Array[Vector2i] = []
		var stack: Array[Vector2i] = [w]
		visited[w] = true
		while not stack.is_empty():
			var cur: Vector2i = stack.pop_back() as Vector2i
			comp.append(cur)
			for n in _world_neighbors(cur):
				if not world_set.has(n):
					continue
				if visited.has(n):
					continue
				visited[n] = true
				stack.append(n)
		if comp.size() >= maxi(min_component_size, 1):
			components.append(comp)

	if components.is_empty():
		return []

	for i in range(components.size()):
		var best := i
		for j in range(i + 1, components.size()):
			var comp_j: Array[Vector2i] = components[j] as Array[Vector2i]
			var comp_best: Array[Vector2i] = components[best] as Array[Vector2i]
			if comp_j.size() > comp_best.size():
				best = j
		if best != i:
			var temp = components[i]
			components[i] = components[best]
			components[best] = temp

	var out: Array[Vector2i] = []
	for i in range(mini(max_components, components.size())):
		var comp: Array[Vector2i] = components[i] as Array[Vector2i]
		for c in comp:
			out.append(c)
	return out


func _try_place_tile(chunk: Vector2i, _chunk_origin: Vector2i, local_cell: Vector2i, world_cell: Vector2i, atlas: Vector2i, occupied: Dictionary) -> bool:
	if not _is_valid_atlas_tile(atlas):
		return false
	var span := _get_tile_span(atlas)
	if _is_world_span_protected(world_cell, span):
		return false
	if not _can_place(chunk, local_cell, span, occupied):
		return false
	if _overlaps_blocked_nodes(world_cell, span):
		return false

	_tile_map.set_cell(world_cell, source_id, atlas)
	_mark_occupied(local_cell, span, occupied)
	return true


func _can_place(_chunk: Vector2i, local_cell: Vector2i, span: Vector2i, occupied: Dictionary) -> bool:
	if local_cell.x < 0 or local_cell.y < 0:
		return false
	if local_cell.x + span.x > chunk_size_tiles:
		return false
	if local_cell.y + span.y > chunk_size_tiles:
		return false

	for oy in range(span.y):
		for ox in range(span.x):
			var k := local_cell + Vector2i(ox, oy)
			if occupied.has(k):
				return false
	return true


func _mark_occupied(local_cell: Vector2i, span: Vector2i, occupied: Dictionary) -> void:
	for oy in range(span.y):
		for ox in range(span.x):
			var k := local_cell + Vector2i(ox, oy)
			occupied[k] = true


func _get_tile_span(atlas: Vector2i) -> Vector2i:
	if _tile_map == null or _tile_map.tile_set == null:
		return Vector2i.ONE
	var source := _tile_map.tile_set.get_source(source_id)
	if source == null:
		return Vector2i.ONE
	if source is TileSetAtlasSource:
		var atlas_source := source as TileSetAtlasSource
		if atlas_source.has_method("has_tile") and not atlas_source.has_tile(atlas):
			return Vector2i.ONE
		if atlas_source.has_method("get_tile_size_in_atlas"):
			var span := atlas_source.get_tile_size_in_atlas(atlas)
			if span.x > 0 and span.y > 0:
				return span
	return Vector2i.ONE


func _is_valid_atlas_tile(atlas: Vector2i) -> bool:
	if _tile_map == null or _tile_map.tile_set == null:
		return false
	var source := _tile_map.tile_set.get_source(source_id)
	if source == null:
		return false
	if source is TileSetAtlasSource:
		var atlas_source := source as TileSetAtlasSource
		if atlas_source.has_method("has_tile"):
			return atlas_source.has_tile(atlas)
	return false


func _get_first_available_atlas_tile() -> Vector2i:
	if _tile_map == null or _tile_map.tile_set == null:
		return Vector2i.ZERO
	var source := _tile_map.tile_set.get_source(source_id)
	if source == null:
		return Vector2i.ZERO
	if source is TileSetAtlasSource:
		var atlas_source := source as TileSetAtlasSource
		if atlas_source.has_method("get_tiles_count") and atlas_source.has_method("get_tile_id"):
			var count := int(atlas_source.get_tiles_count())
			if count > 0:
				return atlas_source.get_tile_id(0)
	return Vector2i.ZERO


func _cache_protected_cells() -> void:
	_protected_cells.clear()
	if _tile_map == null:
		return
	for cell in _tile_map.get_used_cells():
		_protected_cells[cell] = true


func _is_protected_cell(cell: Vector2i) -> bool:
	if not preserve_editor_tiles:
		return false
	return _protected_cells.has(cell)


func _is_world_span_protected(world_cell: Vector2i, span: Vector2i) -> bool:
	if not preserve_editor_tiles:
		return false
	var span_w := maxi(1, span.x)
	var span_h := maxi(1, span.y)
	for oy in range(span_h):
		for ox in range(span_w):
			if _is_protected_cell(world_cell + Vector2i(ox, oy)):
				return true
	return false


func _collect_blocked_positions() -> void:
	_blocked_world_positions.clear()
	for p in blocked_node_paths:
		if p == NodePath(""):
			continue
		var n := get_node_or_null(p)
		if n is Node2D:
			_blocked_world_positions.append((n as Node2D).global_position)


func _overlaps_blocked_nodes(world_cell: Vector2i, span: Vector2i) -> bool:
	if _blocked_world_positions.is_empty() or _tile_map == null or _tile_map.tile_set == null:
		return false

	var tile_size: Vector2i = _tile_map.tile_set.tile_size
	var rect_pos: Vector2 = _tile_map.to_global(_tile_map.map_to_local(world_cell))
	var span_w: int = maxi(1, span.x)
	var span_h: int = maxi(1, span.y)
	var rect_size: Vector2 = Vector2(float(span_w * tile_size.x), float(span_h * tile_size.y))
	var rect: Rect2 = Rect2(rect_pos, rect_size)

	var pad: float = maxf(blocked_node_radius_px, 0.0)
	rect.position -= Vector2(pad, pad)
	rect.size += Vector2(pad * 2.0, pad * 2.0)

	for world_pos in _blocked_world_positions:
		if rect.has_point(world_pos):
			return true
	return false


func get_world_bounds_rect() -> Rect2:
	if _tile_map == null or _tile_map.tile_set == null:
		return Rect2()

	var tile_size: Vector2 = Vector2(_tile_map.tile_set.tile_size)
	var half_tile := tile_size * 0.5
	var min_cell := _world_min_chunk * chunk_size_tiles
	var max_cell_exclusive := (_world_max_chunk + Vector2i.ONE) * chunk_size_tiles
	var min_world := _tile_map.to_global(_tile_map.map_to_local(min_cell) - half_tile)
	var max_world := _tile_map.to_global(_tile_map.map_to_local(max_cell_exclusive) - half_tile)
	return Rect2(min_world, max_world - min_world)


func _resolve_fallback_tile_map() -> TileMapLayer:
	var scene := get_tree().current_scene
	if scene == null:
		return null

	var path_text := String(tile_map_path)
	if not path_text.is_empty():
		var requested_name := path_text.get_file()
		if not requested_name.is_empty():
			var by_path_name := scene.find_child(requested_name, true, false) as TileMapLayer
			if by_path_name != null:
				return by_path_name

	var lower_path := path_text.to_lower()
	var road_layer := scene.find_child("RoadLayer", true, false) as TileMapLayer
	var lake_layer := scene.find_child("LakeLayer", true, false) as TileMapLayer
	if lower_path.contains("road"):
		if road_layer != null:
			return road_layer
		if lake_layer != null:
			return lake_layer
	else:
		if lake_layer != null:
			return lake_layer
		if road_layer != null:
			return road_layer

	return null


func _ensure_valid_terrain_target() -> bool:
	if _tile_map == null:
		push_error("ChunkWorldGenerator: terrain target tilemap is null")
		return false
	if _tile_map.tile_set == null:
		push_error("ChunkWorldGenerator: TileMapLayer has no TileSet for terrain placement")
		return false

	var ts: TileSet = _tile_map.tile_set
	var terrain_sets := ts.get_terrain_sets_count()
	if terrain_sets <= 0:
		push_error("ChunkWorldGenerator: TileSet has no terrain sets")
		return false

	var chosen_set := terrain_set_id
	if chosen_set < 0 or chosen_set >= terrain_sets or ts.get_terrains_count(chosen_set) <= 0:
		chosen_set = -1
		for i in range(terrain_sets):
			if ts.get_terrains_count(i) > 0:
				chosen_set = i
				break
		if chosen_set < 0:
			push_error("ChunkWorldGenerator: TileSet has terrain sets but no terrains")
			return false
		if debug_log:
			print("ChunkWorldGenerator: terrain_set_id adjusted from %d to %d" % [terrain_set_id, chosen_set])
		terrain_set_id = chosen_set

	var terrain_count := ts.get_terrains_count(terrain_set_id)
	if terrain_count <= 0:
		push_error("ChunkWorldGenerator: selected terrain set has no terrains")
		return false

	var chosen_terrain := terrain_id
	if chosen_terrain < 0 or chosen_terrain >= terrain_count:
		if debug_log:
			print("ChunkWorldGenerator: terrain_id adjusted from %d to 0" % terrain_id)
		chosen_terrain = 0
	terrain_id = chosen_terrain
	return true
