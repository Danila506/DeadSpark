extends Node

const META_GENERATED_CELLS: StringName = &"world_generation_generated_cells"
const META_PRESERVE_EDITOR_TILES: StringName = &"world_generation_preserve_editor_tiles"
const META_PROTECTED_CELLS: StringName = &"world_generation_protected_cells"
const DEFAULT_WORLD_CHUNKS_AXIS: int = 6

@export var enabled: bool = true
@export var tile_map_path: NodePath
@export var player_path: NodePath
@export var config: ChunkWorldGeneratorConfig

@export_category("Chunk Settings")
@export_range(4, 256, 1) var chunk_size_tiles: int = 16
@export_range(1, 12, 1) var load_radius_chunks: int = 3
@export_range(1, 64, 1) var world_chunks_x: int = DEFAULT_WORLD_CHUNKS_AXIS
@export_range(1, 64, 1) var world_chunks_y: int = DEFAULT_WORLD_CHUNKS_AXIS
@export var clear_existing_on_start: bool = true
@export var preserve_editor_tiles: bool = false
@export var load_entire_world_on_start: bool = false
@export var unload_enabled: bool = false
@export var update_interval_sec: float = 0.20
@export_range(1, 32, 1) var max_chunk_operations_per_update: int = 1
@export_range(0.25, 16.0, 0.25) var generation_step_time_budget_ms: float = 1.5

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
@export_range(0.1, 3.0, 0.05) var blob_size_scale_min: float = 0.6
@export_range(0.1, 3.0, 0.05) var blob_size_scale_max: float = 1.7
@export_range(1, 8, 1) var blob_lobe_count_min: int = 1
@export_range(1, 8, 1) var blob_lobe_count_max: int = 4
@export_range(0.0, 2.0, 0.05) var blob_lobe_offset_factor: float = 0.75
@export_range(0.0, 0.8, 0.01) var blob_edge_jitter: float = 0.28
@export_range(0.0, 1.0, 0.01) var blob_cell_keep_probability: float = 0.94
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
@export var blocker_group_name: StringName = &"world_generation_blocker"
@export var blocked_node_radius_px: float = 120.0
@export var avoid_physics_collision: bool = false
@export var physics_collision_padding_px: float = 0.0
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
var _required_chunks := {}
var _pending_load_chunks: Array[Vector2i] = []
var _pending_unload_chunks: Array[Vector2i] = []
var _last_center_chunk := Vector2i(999999, 999999)
var _update_timer: float = 0.0
var _world_min_chunk: Vector2i
var _world_max_chunk: Vector2i
var _blocked_world_positions: Array[Vector2] = []
var _protected_cells := {}
var _generated_cells := {}
var _atlas_source: TileSetAtlasSource
var _valid_tile_options: Array[Vector2i] = []
var _valid_tile_weights: Array[float] = []
var _valid_tile_weight_total: float = 0.0
var _has_matching_tile_weights: bool = false
var _first_available_atlas_tile: Vector2i = Vector2i.ZERO
var _tile_span_cache := {}
var _generation_meta_dirty: bool = false
var _last_chunk_profile_stats: Dictionary = {}


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

	world_seed = _resolve_generation_seed(world_seed)
	_initialize_update_phase_offset()

	if preserve_editor_tiles:
		_cache_protected_cells()
	_sync_generation_layer_meta()

	if not use_terrain_connect and tile_options_atlas.is_empty():
		push_error("ChunkWorldGenerator: tile_options_atlas is empty")
		set_process(false)
		return
	if use_terrain_connect and not _ensure_valid_terrain_target():
		set_process(false)
		return
	_rebuild_tile_cache()

	_collect_blocked_positions()
	_init_world_bounds()

	if clear_existing_on_start:
		_clear_existing_cells()

	_update_visible_chunks(true)
	_prewarm_initial_visible_generation()
	if load_entire_world_on_start and not unload_enabled:
		_prewarm_full_generation()
		set_process(false)


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
	load_entire_world_on_start = cfg.load_entire_world_on_start
	unload_enabled = cfg.unload_enabled
	update_interval_sec = cfg.update_interval_sec
	max_chunk_operations_per_update = cfg.max_chunk_operations_per_update
	generation_step_time_budget_ms = cfg.generation_step_time_budget_ms
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
	blob_size_scale_min = cfg.blob_size_scale_min
	blob_size_scale_max = cfg.blob_size_scale_max
	blob_lobe_count_min = cfg.blob_lobe_count_min
	blob_lobe_count_max = cfg.blob_lobe_count_max
	blob_lobe_offset_factor = cfg.blob_lobe_offset_factor
	blob_edge_jitter = cfg.blob_edge_jitter
	blob_cell_keep_probability = cfg.blob_cell_keep_probability
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
	blocker_group_name = cfg.blocker_group_name
	blocked_node_radius_px = cfg.blocked_node_radius_px
	avoid_physics_collision = cfg.avoid_physics_collision
	physics_collision_padding_px = cfg.physics_collision_padding_px
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
	var has_pending_work := not _pending_load_chunks.is_empty() or not _pending_unload_chunks.is_empty()
	if not force and center_chunk == _last_center_chunk and not has_pending_work:
		return

	if force or center_chunk != _last_center_chunk:
		_last_center_chunk = center_chunk
		_rebuild_chunk_work_queues(center_chunk)

	_process_chunk_work_queues(max_chunk_operations_per_update)


func _rebuild_chunk_work_queues(center_chunk: Vector2i) -> void:
	_required_chunks.clear()
	_pending_load_chunks.clear()
	_pending_unload_chunks.clear()
	var min_chunk := _world_min_chunk
	var max_chunk := _world_max_chunk
	if not load_entire_world_on_start:
		min_chunk = Vector2i(center_chunk.x - load_radius_chunks, center_chunk.y - load_radius_chunks)
		max_chunk = Vector2i(center_chunk.x + load_radius_chunks, center_chunk.y + load_radius_chunks)

	for cy in range(min_chunk.y, max_chunk.y + 1):
		for cx in range(min_chunk.x, max_chunk.x + 1):
			var chunk := Vector2i(cx, cy)
			if not _is_chunk_in_world(chunk):
				continue

			_required_chunks[chunk] = true
			if not _loaded_chunks.has(chunk):
				_pending_load_chunks.append(chunk)

	if unload_enabled:
		for chunk_key in _loaded_chunks.keys():
			var loaded_chunk := chunk_key as Vector2i
			if not _required_chunks.has(loaded_chunk):
				_pending_unload_chunks.append(loaded_chunk)

	_sort_chunks_near_center(_pending_load_chunks, center_chunk)
	_sort_chunks_near_center(_pending_unload_chunks, center_chunk)


func _process_chunk_work_queues(chunk_budget: int) -> void:
	var operations_left := maxi(1, chunk_budget)
	var step_start_usec := Time.get_ticks_usec()
	var time_budget_usec := int(maxf(generation_step_time_budget_ms, 0.25) * 1000.0)

	while operations_left > 0 and not _pending_load_chunks.is_empty():
		if Time.get_ticks_usec() - step_start_usec >= time_budget_usec:
			return
		var chunk := _pending_load_chunks.pop_front() as Vector2i
		if _required_chunks.has(chunk) and not _loaded_chunks.has(chunk):
			var load_start_usec := Time.get_ticks_usec()
			_generate_chunk(chunk)
			_loaded_chunks[chunk] = true
			_profile_chunk_operation("generate", chunk, load_start_usec, _last_chunk_profile_stats)
			operations_left -= 1

	if not unload_enabled:
		_pending_unload_chunks.clear()
		return

	while operations_left > 0 and not _pending_unload_chunks.is_empty():
		if Time.get_ticks_usec() - step_start_usec >= time_budget_usec:
			return
		var chunk := _pending_unload_chunks.pop_front() as Vector2i
		if not _required_chunks.has(chunk) and _loaded_chunks.has(chunk):
			var unload_start_usec := Time.get_ticks_usec()
			_unload_chunk(chunk)
			_loaded_chunks.erase(chunk)
			_profile_chunk_operation("unload", chunk, unload_start_usec, _last_chunk_profile_stats)
			operations_left -= 1


func _sort_chunks_near_center(chunks: Array[Vector2i], center_chunk: Vector2i) -> void:
	for i in range(chunks.size()):
		var best := i
		for j in range(i + 1, chunks.size()):
			if _chunk_distance_squared(chunks[j], center_chunk) < _chunk_distance_squared(chunks[best], center_chunk):
				best = j
		if best != i:
			var temp := chunks[i]
			chunks[i] = chunks[best]
			chunks[best] = temp


func _chunk_distance_squared(chunk: Vector2i, center_chunk: Vector2i) -> int:
	var delta := chunk - center_chunk
	return delta.x * delta.x + delta.y * delta.y


func _is_chunk_in_world(chunk: Vector2i) -> bool:
	return chunk.x >= _world_min_chunk.x and chunk.x <= _world_max_chunk.x and chunk.y >= _world_min_chunk.y and chunk.y <= _world_max_chunk.y


func _world_to_chunk(cell: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(cell.x) / float(chunk_size_tiles)),
		floori(float(cell.y) / float(chunk_size_tiles))
	)


func _generate_chunk(chunk: Vector2i) -> void:
	var stats := {
		"cells_set": 0,
		"cells_erased": 0,
		"overlap_erased": 0
	}
	if not _is_chunk_allowed_for_biome(chunk):
		if unload_enabled:
			_unload_chunk(chunk)
			stats = _last_chunk_profile_stats
		else:
			_last_chunk_profile_stats = stats
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
			if _can_place(chunk, fallback_local, Vector2i.ONE, occupied) and not _is_blocked_by_avoid_layer(fallback_cell) and not _overlaps_blocked_nodes(fallback_cell, Vector2i.ONE) and not _is_protected_cell(fallback_cell):
				terrain_cells.append(fallback_cell)
				_mark_occupied(fallback_local, Vector2i.ONE, occupied)

		if not terrain_cells.is_empty():
			_tile_map.set_cells_terrain_connect(terrain_cells, terrain_set_id, terrain_id, terrain_ignore_empty)
			stats["cells_set"] = terrain_cells.size()
			_mark_generated_cells(terrain_cells)
			stats["overlap_erased"] = _clear_overlapping_layers(terrain_cells)
			if not terrain_blob_mode:
				_apply_corner_alternatives(terrain_cells)
			_sync_generation_layer_meta_if_dirty()
		_last_chunk_profile_stats = stats
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
					stats["cells_erased"] = int(stats["cells_erased"]) + _erase_cell_if_present(cell, false)
				continue

			var atlas := _pick_tile(cell)
			var local_cell := Vector2i(local_x, local_y)
			if _is_blocked_by_avoid_layer(cell):
				if not _is_protected_cell(cell):
					stats["cells_erased"] = int(stats["cells_erased"]) + _erase_cell_if_present(cell, false)
				continue
			if _try_place_tile(chunk, origin, local_cell, cell, atlas, occupied):
				placed_count += 1
				placed_cells.append(cell)
				stats["cells_set"] = int(stats["cells_set"]) + 1
			else:
				if not _is_protected_cell(cell):
					stats["cells_erased"] = int(stats["cells_erased"]) + _erase_cell_if_present(cell, false)

	if ensure_non_empty_chunk and fill_probability > 0.0 and placed_count == 0:
		var fallback_cell := _pick_fallback_cell(origin)
		var fallback_local := fallback_cell - origin
		var fallback_atlas := _pick_tile(fallback_cell)
		if _try_place_tile(chunk, origin, fallback_local, fallback_cell, fallback_atlas, occupied):
			placed_cells.append(fallback_cell)
			stats["cells_set"] = int(stats["cells_set"]) + 1
	stats["overlap_erased"] = _clear_overlapping_layers(placed_cells)
	_sync_generation_layer_meta_if_dirty()
	_last_chunk_profile_stats = stats


func _unload_chunk(chunk: Vector2i) -> void:
	var stats := {
		"cells_set": 0,
		"cells_erased": 0,
		"overlap_erased": 0
	}
	if not unload_enabled:
		_last_chunk_profile_stats = stats
		return
	var origin := chunk * chunk_size_tiles

	for local_y in range(chunk_size_tiles):
		for local_x in range(chunk_size_tiles):
			var cell := origin + Vector2i(local_x, local_y)
			if not _is_protected_cell(cell):
				stats["cells_erased"] = int(stats["cells_erased"]) + _erase_cell_if_present(cell, true)
	_sync_generation_layer_meta_if_dirty()
	_last_chunk_profile_stats = stats


func _erase_cell_if_present(cell: Vector2i, unmark_generated: bool) -> int:
	var had_cell := _tile_map != null and _tile_map.get_cell_source_id(cell) != -1
	if _tile_map != null:
		_tile_map.erase_cell(cell)
	if unmark_generated:
		_unmark_generated_cell(cell)
	return 1 if had_cell else 0


func _pick_tile(cell: Vector2i) -> Vector2i:
	var option_count := _valid_tile_options.size()
	if option_count <= 0:
		return _get_first_available_atlas_tile()
	if option_count <= 1:
		return _valid_tile_options[0]
	if not _has_matching_tile_weights:
		var idx := int(_hash_cell(cell.x, cell.y, world_seed) % option_count)
		return _valid_tile_options[idx]
	if _valid_tile_weight_total <= 0.0:
		return _valid_tile_options[0]

	var h := _hash_cell(cell.x, cell.y, world_seed + 3333)
	var roll := (float(h % 100000) / 100000.0) * _valid_tile_weight_total
	var acc := 0.0
	for i in range(option_count):
		acc += _valid_tile_weights[i]
		if roll <= acc:
			return _valid_tile_options[i]
	return _valid_tile_options[option_count - 1]


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
		_unmark_generated_cell(cell)
	_sync_generation_layer_meta_if_dirty()


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
	if anchors.is_empty():
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
	var chunk_area := chunk_size_tiles * chunk_size_tiles
	var base_target := maxi(0, int(round(float(chunk_area) * fill_probability)))
	if base_target <= 0:
		return result

	var region_size_cells := _get_blob_region_size_cells()
	var min_world_cell := origin
	var max_world_cell := origin + Vector2i(chunk_size_tiles - 1, chunk_size_tiles - 1)
	var min_region := _world_to_blob_region(min_world_cell, region_size_cells)
	var max_region := _world_to_blob_region(max_world_cell, region_size_cells)

	var regions: Array = []
	for ry in range(min_region.y - 1, max_region.y + 2):
		for rx in range(min_region.x - 1, max_region.x + 2):
			var region := Vector2i(rx, ry)
			var region_data := _build_blob_region_descriptor(region, region_size_cells)
			if region_data.is_empty():
				continue
			regions.append(region_data)

	if regions.is_empty():
		return result

	var used_world: Dictionary = {}
	for ly in range(chunk_size_tiles):
		for lx in range(chunk_size_tiles):
			var local_cell := Vector2i(lx, ly)
			var world_cell := origin + local_cell
			if not _is_world_cell_inside_blob_regions(world_cell, regions):
				continue
			_try_add_terrain_local(chunk, origin, local_cell, result, used_world, occupied)

	_fill_small_blob_holes(chunk, origin, result, used_world, occupied)
	_smooth_blob_contour(origin, result, used_world, occupied, 2)
	_fill_small_blob_holes(chunk, origin, result, used_world, occupied)
	result = _remove_isolated_cells(result)

	return result


func _get_blob_region_size_cells() -> int:
	var min_region_size := maxi(chunk_size_tiles * 2, 8)
	var max_region_size := maxi(min_region_size, chunk_size_tiles * 5)
	var sparse_factor := clampf(1.0 - fill_probability, 0.0, 1.0)
	var blended := lerpf(float(min_region_size), float(max_region_size), sparse_factor)
	return maxi(8, int(round(blended)))


func _world_to_blob_region(world_cell: Vector2i, region_size_cells: int) -> Vector2i:
	var div := maxi(region_size_cells, 1)
	return Vector2i(
		floori(float(world_cell.x) / float(div)),
		floori(float(world_cell.y) / float(div))
	)


func _build_blob_region_descriptor(region: Vector2i, region_size_cells: int) -> Dictionary:
	var activation_hash := _hash_cell(region.x * 991 + 17, region.y * 733 + 31, world_seed + 20411)
	var activation_roll := float(activation_hash % 10000) / 10000.0
	var spawn_chance := clampf(fill_probability * 4.1 + 0.04, 0.06, 0.78)
	if activation_roll > spawn_chance:
		return {}

	var region_origin := region * region_size_cells
	var center_hash := _hash_cell(region.x * 761 + 11, region.y * 587 + 19, world_seed + 20627)
	var center_jitter_x := float(center_hash % 10000) / 10000.0
	var center_jitter_y := float((int(center_hash / 101)) % 10000) / 10000.0
	var center := Vector2(
		float(region_origin.x) + lerpf(float(region_size_cells) * 0.15, float(region_size_cells) * 0.85, center_jitter_x),
		float(region_origin.y) + lerpf(float(region_size_cells) * 0.15, float(region_size_cells) * 0.85, center_jitter_y)
	)

	var size_scale_min := minf(blob_size_scale_min, blob_size_scale_max)
	var size_scale_max := maxf(blob_size_scale_min, blob_size_scale_max)
	var size_roll := float((int(center_hash / 211)) % 10000) / 10000.0
	var global_scale := lerpf(size_scale_min, size_scale_max, size_roll)
	var base_radius := maxf(2.0, float(region_size_cells) * 0.24 * global_scale)

	var lobe_min := maxi(1, mini(blob_lobe_count_min, blob_lobe_count_max))
	var lobe_max := maxi(lobe_min, maxi(blob_lobe_count_min, blob_lobe_count_max))
	var lobe_span := lobe_max - lobe_min + 1
	var lobe_count := lobe_min + (_hash_cell(region.x * 397 + 43, region.y * 461 + 59, world_seed + 20971) % lobe_span)

	var lobes: Array = []
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for i in range(lobe_count):
		var h := _hash_cell(region.x * 601 + i * 43, region.y * 809 - i * 59, world_seed + 21421)
		var angle := TAU * (float(h % 10000) / 10000.0)
		var offset_roll := float((int(h / 10000)) % 10000) / 10000.0
		var offset_dist := base_radius * blob_lobe_offset_factor * offset_roll
		var lobe_center := center + Vector2(cos(angle), sin(angle)) * offset_dist

		var rx_roll := float((int(h / 173)) % 10000) / 10000.0
		var ry_roll := float((int(h / 347)) % 10000) / 10000.0
		var lobe_radius_x := maxf(1.4, base_radius * lerpf(0.55, 1.35, rx_roll))
		var lobe_radius_y := maxf(1.4, base_radius * lerpf(0.55, 1.35, ry_roll))
		lobes.append({
			"center": lobe_center,
			"rx": lobe_radius_x,
			"ry": lobe_radius_y,
			"seed": _hash_cell(region.x * 151 + i * 71, region.y * 173 + i * 89, world_seed + 21859)
		})

		min_x = minf(min_x, lobe_center.x - lobe_radius_x)
		min_y = minf(min_y, lobe_center.y - lobe_radius_y)
		max_x = maxf(max_x, lobe_center.x + lobe_radius_x)
		max_y = maxf(max_y, lobe_center.y + lobe_radius_y)

	var margin := maxf(1.0, base_radius * 0.4)
	var bbox := Rect2(
		Vector2(min_x - margin, min_y - margin),
		Vector2((max_x - min_x) + margin * 2.0, (max_y - min_y) + margin * 2.0)
	).abs()
	return {
		"bbox": bbox,
		"lobes": lobes
	}


func _is_world_cell_inside_blob_regions(world_cell: Vector2i, regions: Array) -> bool:
	var p := Vector2(float(world_cell.x) + 0.5, float(world_cell.y) + 0.5)
	for region_variant in regions:
		if not (region_variant is Dictionary):
			continue
		var region_data := region_variant as Dictionary
		var bbox := region_data.get("bbox", Rect2()) as Rect2
		if not bbox.has_area() or not bbox.has_point(p):
			continue

		var lobes: Array = region_data.get("lobes", [])
		var inside := false
		for lobe_variant in lobes:
			if not (lobe_variant is Dictionary):
				continue
			var lobe := lobe_variant as Dictionary
			var c := Vector2(lobe.get("center", p))
			var rx := maxf(float(lobe.get("rx", 1.0)), 0.001)
			var ry := maxf(float(lobe.get("ry", 1.0)), 0.001)
			var nx := (p.x - c.x) / rx
			var ny := (p.y - c.y) / ry
			var d := nx * nx + ny * ny
			var lobe_seed := int(lobe.get("seed", 0))
			var edge_hash := _hash_cell(world_cell.x * 997 + int(c.x) * 17, world_cell.y * 881 + int(c.y) * 19, world_seed + 22003 + lobe_seed)
			var edge_roll := float(edge_hash % 10000) / 10000.0
			var threshold := 1.0 + (edge_roll - 0.5) * blob_edge_jitter
			if d <= threshold:
				inside = true
				break

		if not inside:
			continue

		var keep_hash := _hash_cell(world_cell.x * 457 + 41, world_cell.y * 521 + 37, world_seed + 22307)
		var keep_roll := float(keep_hash % 10000) / 10000.0
		if keep_roll <= blob_cell_keep_probability:
			return true

	return false


func _fill_small_blob_holes(
	chunk: Vector2i,
	origin: Vector2i,
	result: Array[Vector2i],
	used_world: Dictionary,
	occupied: Dictionary
) -> void:
	if result.is_empty():
		return
	var world_set: Dictionary = {}
	for cell in result:
		world_set[cell] = true

	var to_fill: Array[Vector2i] = []
	for ly in range(chunk_size_tiles):
		for lx in range(chunk_size_tiles):
			var local_cell := Vector2i(lx, ly)
			var world_cell := origin + local_cell
			if world_set.has(world_cell):
				continue

			var neighbors := 0
			for n in [world_cell + Vector2i.RIGHT, world_cell + Vector2i.LEFT, world_cell + Vector2i.UP, world_cell + Vector2i.DOWN]:
				if world_set.has(n):
					neighbors += 1
			if neighbors < 3:
				continue

			if _is_protected_cell(world_cell):
				continue
			if _is_blocked_by_avoid_layer(world_cell):
				continue
			if _overlaps_blocked_nodes(world_cell, Vector2i.ONE):
				continue
			if not _can_place(chunk, local_cell, Vector2i.ONE, occupied):
				continue
			to_fill.append(local_cell)

	for local_cell in to_fill:
		_try_add_terrain_local(chunk, origin, local_cell, result, used_world, occupied)


func _smooth_blob_contour(
	origin: Vector2i,
	result: Array[Vector2i],
	used_world: Dictionary,
	occupied: Dictionary,
	iterations: int
) -> void:
	if result.is_empty() or iterations <= 0:
		return

	var world_set: Dictionary = {}
	for world_cell in result:
		world_set[world_cell] = true

	for _i in range(iterations):
		var next_set: Dictionary = {}
		for ly in range(chunk_size_tiles):
			for lx in range(chunk_size_tiles):
				var world_cell := origin + Vector2i(lx, ly)
				var n4 := _count_blob_neighbors_4(world_cell, world_set)
				var n8 := _count_blob_neighbors_8(world_cell, world_set)
				if world_set.has(world_cell):
					next_set[world_cell] = true
					continue

				if n8 < 5 or n4 < 2:
					continue
				if not _can_use_blob_cell(world_cell):
					continue
				next_set[world_cell] = true
		world_set = next_set

	_apply_blob_world_set(origin, world_set, result, used_world, occupied)


func _count_blob_neighbors_4(world_cell: Vector2i, world_set: Dictionary) -> int:
	var count := 0
	for n in [world_cell + Vector2i.RIGHT, world_cell + Vector2i.LEFT, world_cell + Vector2i.UP, world_cell + Vector2i.DOWN]:
		if world_set.has(n):
			count += 1
	return count


func _count_blob_neighbors_8(world_cell: Vector2i, world_set: Dictionary) -> int:
	var count := 0
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			if ox == 0 and oy == 0:
				continue
			var n := world_cell + Vector2i(ox, oy)
			if world_set.has(n):
				count += 1
	return count


func _can_use_blob_cell(world_cell: Vector2i) -> bool:
	if _is_protected_cell(world_cell):
		return false
	if _is_blocked_by_avoid_layer(world_cell):
		return false
	if _overlaps_blocked_nodes(world_cell, Vector2i.ONE):
		return false
	return true


func _apply_blob_world_set(
	origin: Vector2i,
	world_set: Dictionary,
	result: Array[Vector2i],
	used_world: Dictionary,
	occupied: Dictionary
) -> void:
	result.clear()
	used_world.clear()
	occupied.clear()

	for ly in range(chunk_size_tiles):
		for lx in range(chunk_size_tiles):
			var local_cell := Vector2i(lx, ly)
			var world_cell := origin + local_cell
			if not world_set.has(world_cell):
				continue
			result.append(world_cell)
			used_world[world_cell] = true
			_mark_occupied(local_cell, Vector2i.ONE, occupied)


func _shrink_blob_to_target(chunk: Vector2i, cells: Array[Vector2i], target_count: int) -> Array[Vector2i]:
	if cells.size() <= target_count:
		return cells
	var scored: Array = []
	for world_cell in cells:
		var local := world_cell - chunk * chunk_size_tiles
		var d := absf(float(local.x) - float(chunk_size_tiles) * 0.5) + absf(float(local.y) - float(chunk_size_tiles) * 0.5)
		scored.append({"cell": world_cell, "score": d})

	var out: Array[Vector2i] = []
	while out.size() < target_count and not scored.is_empty():
		var best_idx := 0
		var best_score := float(scored[0]["score"])
		for i in range(1, scored.size()):
			var score := float(scored[i]["score"])
			if score < best_score:
				best_score = score
				best_idx = i
		out.append(scored[best_idx]["cell"] as Vector2i)
		scored[best_idx] = scored[scored.size() - 1]
		scored.pop_back()
	return out


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


func _is_blocked_by_avoid_layer(world_cell: Vector2i, span: Vector2i = Vector2i.ONE) -> bool:
	if _avoid_layers.is_empty() or avoid_layer_radius_tiles < 0:
		return false
	var world_rect := _get_world_cell_rect(world_cell, span)
	for layer_item in _avoid_layers:
		var avoid := layer_item as TileMapLayer
		if avoid != null and _layer_has_tile_in_world_rect(avoid, world_rect, avoid_layer_radius_tiles):
			return true
	return false


func _clear_overlapping_layers(cells: Array[Vector2i]) -> int:
	if _overlap_clear_layers.is_empty() or cells.is_empty():
		return 0
	var erased_count := 0
	var erased_origins_by_layer := {}
	var layer_by_id := {}
	var radius: int = maxi(0, overlap_clear_radius_tiles)
	for cell in cells:
		var world_rect := _get_world_cell_rect(cell, Vector2i.ONE)
		for layer_item in _overlap_clear_layers:
			var layer := layer_item as TileMapLayer
			if layer == null:
				continue
			var layer_id := int(layer.get_instance_id())
			var erased_origins: Dictionary = erased_origins_by_layer.get(layer_id, {})
			layer_by_id[layer_id] = layer
			for target_cell in _get_layer_cells_in_world_rect(layer, world_rect, radius):
				var erase_cell := _get_overlap_erase_cell(layer, target_cell)
				if erase_cell == Vector2i(999999, 999999):
					continue
				if erased_origins.has(erase_cell):
					continue
				if layer.get_cell_source_id(erase_cell) == -1:
					continue
				layer.erase_cell(erase_cell)
				erased_origins[erase_cell] = true
				erased_count += 1
			erased_origins_by_layer[layer_id] = erased_origins
	for layer_id in erased_origins_by_layer.keys():
		var layer := layer_by_id.get(layer_id, null) as TileMapLayer
		if layer == null:
			continue
		_unmark_layer_generated_origins(layer, erased_origins_by_layer[layer_id] as Dictionary)
	return erased_count


func _is_near_prefer_layer(world_cell: Vector2i) -> bool:
	if _prefer_layer == null or prefer_layer_radius_tiles <= 0:
		return false
	return _layer_has_tile_in_world_rect(_prefer_layer, _get_world_cell_rect(world_cell, Vector2i.ONE), prefer_layer_radius_tiles)


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
	if _is_blocked_by_avoid_layer(world_cell, span):
		return false
	if not _can_place(chunk, local_cell, span, occupied):
		return false
	if _overlaps_blocked_nodes(world_cell, span):
		return false
	if avoid_physics_collision and _overlaps_world_collision(world_cell, span):
		return false

	_tile_map.set_cell(world_cell, source_id, atlas)
	_mark_generated_span(world_cell, span)
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
	if _tile_span_cache.has(atlas):
		return _tile_span_cache[atlas] as Vector2i
	if _atlas_source == null:
		return Vector2i.ONE
	if not _atlas_source.has_tile(atlas):
		_tile_span_cache[atlas] = Vector2i.ONE
		return Vector2i.ONE
	var span := _atlas_source.get_tile_size_in_atlas(atlas)
	if span.x <= 0 or span.y <= 0:
		span = Vector2i.ONE
	_tile_span_cache[atlas] = span
	return span


func _is_valid_atlas_tile(atlas: Vector2i) -> bool:
	return _atlas_source != null and _atlas_source.has_tile(atlas)


func _get_first_available_atlas_tile() -> Vector2i:
	return _first_available_atlas_tile


func _rebuild_tile_cache() -> void:
	_atlas_source = null
	_valid_tile_options.clear()
	_valid_tile_weights.clear()
	_valid_tile_weight_total = 0.0
	_has_matching_tile_weights = tile_option_weights.size() == tile_options_atlas.size()
	_first_available_atlas_tile = Vector2i.ZERO
	_tile_span_cache.clear()

	if _tile_map == null or _tile_map.tile_set == null:
		return
	var source := _tile_map.tile_set.get_source(source_id)
	if source == null:
		return
	if source is TileSetAtlasSource:
		_atlas_source = source as TileSetAtlasSource
	if _atlas_source == null:
		return

	var source_tile_count := int(_atlas_source.get_tiles_count())
	if source_tile_count > 0:
		_first_available_atlas_tile = _atlas_source.get_tile_id(0)

	for i in range(tile_options_atlas.size()):
		var atlas := tile_options_atlas[i]
		if not _is_valid_atlas_tile(atlas):
			continue
		_valid_tile_options.append(atlas)
		var weight := 1.0
		if i < tile_option_weights.size():
			weight = maxf(tile_option_weights[i], 0.0)
		_valid_tile_weights.append(weight)
		_valid_tile_weight_total += weight


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


func _mark_generated_cells(cells: Array[Vector2i]) -> void:
	for cell in cells:
		_generated_cells[cell] = cell
	_generation_meta_dirty = true


func _mark_generated_span(world_cell: Vector2i, span: Vector2i) -> void:
	var span_w := maxi(1, span.x)
	var span_h := maxi(1, span.y)
	for oy in range(span_h):
		for ox in range(span_w):
			_generated_cells[world_cell + Vector2i(ox, oy)] = world_cell
	_generation_meta_dirty = true


func _unmark_generated_cell(cell: Vector2i) -> void:
	if not _generated_cells.has(cell):
		return
	_generated_cells.erase(cell)
	_generation_meta_dirty = true


func _sync_generation_layer_meta_if_dirty() -> void:
	if not _generation_meta_dirty:
		return
	_sync_generation_layer_meta()


func _sync_generation_layer_meta() -> void:
	if _tile_map == null:
		return
	_tile_map.set_meta(META_GENERATED_CELLS, _generated_cells)
	_tile_map.set_meta(META_PRESERVE_EDITOR_TILES, preserve_editor_tiles)
	_tile_map.set_meta(META_PROTECTED_CELLS, _protected_cells)
	_generation_meta_dirty = false


func _get_overlap_erase_cell(layer: TileMapLayer, cell: Vector2i) -> Vector2i:
	var generated_cells: Variant = layer.get_meta(META_GENERATED_CELLS, {})
	if generated_cells is Dictionary:
		var cells := generated_cells as Dictionary
		if not cells.has(cell):
			return Vector2i(999999, 999999)
		var origin: Variant = cells.get(cell, cell)
		if origin is Vector2i:
			return origin as Vector2i
		return cell
	if layer.get_cell_source_id(cell) == -1:
		return Vector2i(999999, 999999)
	if bool(layer.get_meta(META_PRESERVE_EDITOR_TILES, false)):
		return Vector2i(999999, 999999)
	return cell


func _unmark_layer_generated_origin(layer: TileMapLayer, origin: Vector2i) -> void:
	_unmark_layer_generated_origins(layer, {origin: true})


func _unmark_layer_generated_origins(layer: TileMapLayer, origins: Dictionary) -> void:
	if origins.is_empty():
		return
	var generated_cells: Variant = layer.get_meta(META_GENERATED_CELLS, {})
	if not (generated_cells is Dictionary):
		return
	var cells := generated_cells as Dictionary
	for key in cells.keys():
		var generated_cell := key as Vector2i
		var generated_origin: Variant = cells.get(generated_cell, generated_cell)
		if origins.has(generated_cell) or (generated_origin is Vector2i and origins.has(generated_origin)):
			cells.erase(generated_cell)
	layer.set_meta(META_GENERATED_CELLS, cells)


func _get_world_cell_rect(world_cell: Vector2i, span: Vector2i) -> Rect2:
	if _tile_map == null or _tile_map.tile_set == null:
		return Rect2()
	var tile_size := Vector2(_tile_map.tile_set.tile_size)
	var span_w := maxi(1, span.x)
	var span_h := maxi(1, span.y)
	var top_left := _tile_map.to_global(_tile_map.map_to_local(world_cell) - tile_size * 0.5)
	return Rect2(top_left, Vector2(float(span_w) * tile_size.x, float(span_h) * tile_size.y))


func _layer_has_tile_in_world_rect(layer: TileMapLayer, world_rect: Rect2, radius_tiles: int) -> bool:
	for cell in _get_layer_cells_in_world_rect(layer, world_rect, radius_tiles):
		if layer.get_cell_source_id(cell) != -1:
			return true
	return false


func _get_layer_cells_in_world_rect(layer: TileMapLayer, world_rect: Rect2, radius_tiles: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if layer == null or world_rect.size.x <= 0.0 or world_rect.size.y <= 0.0:
		return out

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
		var cell := layer.local_to_map(layer.to_local(corner))
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)

	var radius := maxi(0, radius_tiles)
	for y in range(min_cell.y - radius, max_cell.y + radius + 1):
		for x in range(min_cell.x - radius, max_cell.x + radius + 1):
			out.append(Vector2i(x, y))
	return out


func _collect_blocked_positions() -> void:
	_blocked_world_positions.clear()
	for p in blocked_node_paths:
		if p == NodePath(""):
			continue
		var n := get_node_or_null(p)
		if n is Node2D:
			_append_blocked_world_position((n as Node2D).global_position)

	if blocker_group_name == &"":
		return
	var scene_root := get_tree().current_scene
	for candidate in get_tree().get_nodes_in_group(blocker_group_name):
		if not (candidate is Node2D):
			continue
		var node := candidate as Node2D
		if scene_root != null and node != scene_root and not scene_root.is_ancestor_of(node):
			continue
		_append_blocked_world_position(node.global_position)


func _append_blocked_world_position(world_pos: Vector2) -> void:
	if _blocked_world_positions.has(world_pos):
		return
	_blocked_world_positions.append(world_pos)


func _overlaps_blocked_nodes(world_cell: Vector2i, span: Vector2i) -> bool:
	if _blocked_world_positions.is_empty() or _tile_map == null or _tile_map.tile_set == null:
		return false

	var tile_size: Vector2i = _tile_map.tile_set.tile_size
	var half_tile := Vector2(tile_size) * 0.5
	var rect_pos: Vector2 = _tile_map.to_global(_tile_map.map_to_local(world_cell) - half_tile)
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


func _overlaps_world_collision(world_cell: Vector2i, span: Vector2i) -> bool:
	if _tile_map == null or _tile_map.tile_set == null:
		return false
	var viewport := get_viewport()
	if viewport == null or viewport.world_2d == null:
		return false
	var space_state: PhysicsDirectSpaceState2D = viewport.world_2d.direct_space_state

	var world_rect := _get_world_cell_rect(world_cell, span).abs()
	var padding := maxf(physics_collision_padding_px, 0.0)
	if padding > 0.0:
		world_rect = world_rect.grow(padding)
	if not world_rect.has_area():
		return false

	var shape := RectangleShape2D.new()
	shape.size = world_rect.size

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, world_rect.get_center())
	query.collide_with_bodies = true
	query.collide_with_areas = true
	query.collision_mask = 0x7fffffff

	var hits: Array = space_state.intersect_shape(query, 16)
	for hit_value in hits:
		if not (hit_value is Dictionary):
			continue
		var hit := hit_value as Dictionary
		var collider: Object = hit.get("collider", null)
		if collider == null:
			continue
		if collider == _tile_map:
			continue
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


func has_generation_pending() -> bool:
	return not _pending_load_chunks.is_empty() or not _pending_unload_chunks.is_empty()


func get_pending_generation_chunk_count() -> int:
	return _pending_load_chunks.size() + _pending_unload_chunks.size()


func force_generate_step(chunk_budget: int = -1) -> void:
	if not enabled or _tile_map == null or _player == null:
		return

	var budget := chunk_budget
	if budget <= 0:
		budget = max_chunk_operations_per_update

	var player_cell := _tile_map.local_to_map(_tile_map.to_local(_player.global_position))
	var center_chunk := _world_to_chunk(player_cell)
	if center_chunk != _last_center_chunk or not has_generation_pending():
		_last_center_chunk = center_chunk
		_rebuild_chunk_work_queues(center_chunk)

	_process_chunk_work_queues(maxi(1, budget))


func _prewarm_full_generation() -> void:
	var guard := 0
	var max_iterations := maxi(world_chunks_x * world_chunks_y * 16, 512)
	while has_generation_pending() and guard < max_iterations:
		_process_chunk_work_queues(maxi(max_chunk_operations_per_update, 32))
		guard += 1
	if _generation_meta_dirty:
		_sync_generation_layer_meta()


func _prewarm_initial_visible_generation() -> void:
	var guard := 0
	var max_iterations := 128
	while has_generation_pending() and guard < max_iterations:
		_process_chunk_work_queues(maxi(max_chunk_operations_per_update, 24))
		guard += 1
	if _generation_meta_dirty:
		_sync_generation_layer_meta()


func _resolve_generation_seed(config_seed: int) -> int:
	if GameSaveManager != null and GameSaveManager.has_method("resolve_world_generation_seed"):
		return int(GameSaveManager.resolve_world_generation_seed(config_seed))
	if randomize_seed_on_start:
		var time_seed := int(Time.get_unix_time_from_system())
		var tick_seed := int(Time.get_ticks_usec())
		return abs(time_seed ^ tick_seed)
	return config_seed


func _initialize_update_phase_offset() -> void:
	_update_timer = _compute_phase_offset(update_interval_sec, 587)


func _compute_phase_offset(interval_sec: float, salt: int) -> float:
	var interval := maxf(interval_sec, 0.001)
	var stable_hash := int(get_instance_id()) ^ (world_seed * 1103515245) ^ salt
	if stable_hash < 0:
		stable_hash = -stable_hash
	var normalized := float(stable_hash % 10000) / 10000.0
	return normalized * interval


func _profile_chunk_operation(action: String, chunk: Vector2i, start_usec: int, stats: Dictionary) -> void:
	var profiler := get_node_or_null("/root/ChunkProfiler")
	if profiler == null or not profiler.has_method("record_chunk_operation"):
		return
	var payload := stats.duplicate()
	payload["elapsed_ms"] = float(Time.get_ticks_usec() - start_usec) / 1000.0
	payload["pending_load"] = _pending_load_chunks.size()
	payload["pending_unload"] = _pending_unload_chunks.size()
	payload["loaded_chunks"] = _loaded_chunks.size()
	profiler.call("record_chunk_operation", name, action, chunk, payload)


func get_debug_world_generation_info() -> Dictionary:
	var tile_size := Vector2.ZERO
	if _tile_map != null and _tile_map.tile_set != null:
		tile_size = Vector2(_tile_map.tile_set.tile_size)
	return {
		"type": "tile_layer",
		"name": name,
		"seed": world_seed,
		"chunk_size_tiles": chunk_size_tiles,
		"tile_size_px": tile_size,
		"world_min_chunk": _world_min_chunk,
		"world_max_chunk": _world_max_chunk,
		"loaded_chunks": _loaded_chunks.keys(),
		"load_entire_world_on_start": load_entire_world_on_start,
		"unload_enabled": unload_enabled,
		"protected_cells": _protected_cells.keys(),
		"generated_cells": _generated_cells.keys(),
		"blocked_world_positions": _blocked_world_positions.duplicate()
	}


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
