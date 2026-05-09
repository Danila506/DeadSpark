extends Node2D

const GENERATED_FOOTPRINT_META: StringName = &"world_generation_footprint_rect"
const GENERATED_RESERVATION_KEY_META: StringName = &"world_generation_reservation_key"
const GLOBAL_FOOTPRINT_GRID_CELL_SIZE: float = 256.0
const SPAWN_JOB_PHASE_RANDOM: int = 0
const SPAWN_JOB_PHASE_FALLBACK: int = 1
const DEFAULT_WORLD_CHUNKS_AXIS: int = 6

static var _global_registry_scene_id: int = 0
static var _global_reserved_footprints: Dictionary = {}
static var _global_reserved_footprint_grid: Dictionary = {}

@export var enabled: bool = true
@export var spawner_id: String = ""
@export var player_path: NodePath
@export var spawn_parent_path: NodePath
@export var clear_generated_in_spawn_parent_on_start: bool = false
@export var tree_scene: PackedScene
@export var tree_scenes: Array[PackedScene] = []
@export var tree_scene_weights: Array[float] = []
@export var config: ChunkTreeSpawnerConfig

@export_category("Chunk Settings")
@export_range(4, 256, 1) var chunk_size_tiles: int = 16
@export var tile_size_px: Vector2 = Vector2(60.0, 60.0)
@export_range(1, 12, 1) var load_radius_chunks: int = 1
@export_range(1, 64, 1) var world_chunks_x: int = DEFAULT_WORLD_CHUNKS_AXIS
@export_range(1, 64, 1) var world_chunks_y: int = DEFAULT_WORLD_CHUNKS_AXIS
@export var load_entire_world_on_start: bool = false
@export var unload_enabled: bool = true
@export var update_interval_sec: float = 0.20
@export_range(1, 32, 1) var max_chunk_operations_per_update: int = 1
@export_range(1, 512, 1) var max_spawn_candidates_per_update: int = 24
@export_range(1, 128, 1) var max_spawn_nodes_per_update: int = 2
@export_range(0.25, 16.0, 0.25) var spawn_step_time_budget_ms: float = 1.5
@export var revalidate_enabled: bool = false
@export var revalidate_interval_sec: float = 0.6
@export_range(1, 32, 1) var revalidate_chunk_budget_per_pass: int = 2

@export_category("Trees")
@export var world_seed: int = 1337
@export var randomize_seed_on_start: bool = false
@export_range(0.0, 1.0, 0.01) var spawn_probability: float = 0.03
@export var min_trees_per_chunk: int = 1
@export var min_spawn_distance_px: float = 0.0
@export var biome_partition_enabled: bool = false
@export_range(2, 8, 1) var biome_partition_count: int = 2
@export_range(0, 7, 1) var biome_partition_index: int = 0
@export_range(2, 16, 1) var biome_partition_period_chunks: int = 6
@export var biome_half_split_enabled: bool = false
@export var biome_half_split_vertical: bool = true
@export var biome_half_split_upper_or_left: bool = true

@export_category("Placement Rules")
@export var blocked_node_paths: Array[NodePath] = []
@export var blocker_group_name: StringName = &"world_generation_blocker"
@export var blocked_node_radius_px: float = 120.0
@export var spawn_clearance_radius_px: float = 18.0
@export var footprint_size_px: Vector2 = Vector2.ZERO
@export var footprint_offset_px: Vector2 = Vector2.ZERO
@export var spawn_only_on_layer_path: NodePath
@export var forbidden_layer_path: NodePath
@export var forbidden_layer_paths: Array[NodePath] = []
@export_range(0, 8, 1) var forbidden_layer_radius_tiles: int = 0

@export_category("Debug")
@export var debug_log: bool = false

var _player: Node2D
var _spawn_parent: Node2D
var _spawn_only_layer: TileMapLayer
var _lake_layer: TileMapLayer
var _forbidden_layers: Array = []
var _loaded_chunks := {}
var _required_chunks := {}
var _pending_load_chunks: Array[Vector2i] = []
var _pending_unload_chunks: Array[Vector2i] = []
var _spawned_trees_by_chunk := {}
var _last_center_chunk := Vector2i(999999, 999999)
var _update_timer: float = 0.0
var _revalidate_timer: float = 0.0
var _world_min_chunk: Vector2i
var _world_max_chunk: Vector2i
var _blocked_world_positions: Array[Vector2] = []
var _spawn_positions_by_chunk := {}
var _spawn_position_grid := {}
var _layer_max_tile_span_by_id := {}
var _layer_cell_span_cache := {}
var _revalidate_chunk_cursor: int = 0
var _last_chunk_profile_stats: Dictionary = {}
var _active_spawn_job: Dictionary = {}
var _valid_spawn_scenes: Array[PackedScene] = []
var _valid_spawn_scene_weights: Array[float] = []
var _valid_spawn_scene_weight_total: float = 0.0
var _collision_query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
var _collision_rect_shape: RectangleShape2D = RectangleShape2D.new()
var _collision_circle_shape: CircleShape2D = CircleShape2D.new()


func _ready() -> void:
	if config != null:
		_apply_config(config)

	if not enabled:
		set_process(false)
		return

	_ensure_global_spawn_registry()
	_rebuild_spawn_scene_cache()

	_player = get_node_or_null(player_path) as Node2D
	_spawn_parent = get_node_or_null(spawn_parent_path) as Node2D
	if clear_generated_in_spawn_parent_on_start and _spawn_parent != null:
		_clear_generated_spawn_parent_children()
	_spawn_only_layer = null
	if spawn_only_on_layer_path != NodePath(""):
		_spawn_only_layer = get_node_or_null(spawn_only_on_layer_path) as TileMapLayer
	_lake_layer = get_node_or_null("../../Y-Sort_Objects/LakeLayer") as TileMapLayer
	_forbidden_layers.clear()
	if forbidden_layer_path != NodePath(""):
		var single_forbidden := get_node_or_null(forbidden_layer_path) as TileMapLayer
		if single_forbidden != null:
			_forbidden_layers.append(single_forbidden)
	for p in forbidden_layer_paths:
		if p == NodePath(""):
			continue
		var layer := get_node_or_null(p) as TileMapLayer
		if layer != null and not _forbidden_layers.has(layer):
			_forbidden_layers.append(layer)

	if _player == null or _spawn_parent == null or _get_spawn_scene_count() <= 0:
		push_error("ChunkTreeSpawner: set player_path, spawn_parent_path and tree_scene/tree_scenes")
		set_process(false)
		return

	world_seed = _resolve_generation_seed(world_seed)
	_initialize_update_phase_offsets()

	_collect_blocked_positions()
	_init_world_bounds()
	if load_entire_world_on_start:
		_last_center_chunk = _world_to_chunk(_player.global_position)
		_rebuild_chunk_work_queues(_last_center_chunk)
	else:
		_update_visible_chunks(true)

	_prewarm_initial_visible_generation()

	if load_entire_world_on_start and not unload_enabled:
		_prewarm_full_generation()
		if not revalidate_enabled:
			set_process(false)


func _exit_tree() -> void:
	_cancel_active_spawn_job()
	_release_loaded_spawn_reservations()


func _apply_config(cfg: ChunkTreeSpawnerConfig) -> void:
	enabled = cfg.enabled
	spawner_id = cfg.spawner_id
	player_path = cfg.player_path
	spawn_parent_path = cfg.spawn_parent_path
	clear_generated_in_spawn_parent_on_start = cfg.clear_generated_in_spawn_parent_on_start
	tree_scene = cfg.tree_scene
	tree_scenes = cfg.tree_scenes.duplicate()
	tree_scene_weights = cfg.tree_scene_weights.duplicate()
	chunk_size_tiles = cfg.chunk_size_tiles
	tile_size_px = cfg.tile_size_px
	load_radius_chunks = cfg.load_radius_chunks
	world_chunks_x = cfg.world_chunks_x
	world_chunks_y = cfg.world_chunks_y
	load_entire_world_on_start = cfg.load_entire_world_on_start
	unload_enabled = cfg.unload_enabled
	update_interval_sec = cfg.update_interval_sec
	max_chunk_operations_per_update = cfg.max_chunk_operations_per_update
	max_spawn_candidates_per_update = cfg.max_spawn_candidates_per_update
	max_spawn_nodes_per_update = cfg.max_spawn_nodes_per_update
	spawn_step_time_budget_ms = cfg.spawn_step_time_budget_ms
	revalidate_enabled = cfg.revalidate_enabled
	revalidate_interval_sec = cfg.revalidate_interval_sec
	revalidate_chunk_budget_per_pass = cfg.revalidate_chunk_budget_per_pass
	world_seed = cfg.world_seed
	randomize_seed_on_start = cfg.randomize_seed_on_start
	spawn_probability = cfg.spawn_probability
	min_trees_per_chunk = cfg.min_trees_per_chunk
	min_spawn_distance_px = cfg.min_spawn_distance_px
	biome_partition_enabled = cfg.biome_partition_enabled
	biome_partition_count = cfg.biome_partition_count
	biome_partition_index = cfg.biome_partition_index
	biome_partition_period_chunks = cfg.biome_partition_period_chunks
	biome_half_split_enabled = cfg.biome_half_split_enabled
	biome_half_split_vertical = cfg.biome_half_split_vertical
	biome_half_split_upper_or_left = cfg.biome_half_split_upper_or_left
	blocked_node_paths = cfg.blocked_node_paths.duplicate()
	blocker_group_name = cfg.blocker_group_name
	blocked_node_radius_px = cfg.blocked_node_radius_px
	spawn_clearance_radius_px = cfg.spawn_clearance_radius_px
	footprint_size_px = cfg.footprint_size_px
	footprint_offset_px = cfg.footprint_offset_px
	spawn_only_on_layer_path = cfg.spawn_only_on_layer_path
	forbidden_layer_path = cfg.forbidden_layer_path
	forbidden_layer_paths = cfg.forbidden_layer_paths.duplicate()
	forbidden_layer_radius_tiles = cfg.forbidden_layer_radius_tiles
	debug_log = cfg.debug_log


func _process(delta: float) -> void:
	_update_timer += delta
	if revalidate_enabled:
		_revalidate_timer += delta
	if _update_timer < update_interval_sec:
		_try_revalidate_loaded_spawns()
		return
	_update_timer = 0.0
	_update_visible_chunks(false)
	_try_revalidate_loaded_spawns()


func _clear_generated_spawn_parent_children() -> void:
	for child in _spawn_parent.get_children():
		if not (child is Node):
			continue
		var node := child as Node
		if not node.is_in_group("generated_world_object"):
			continue
		_release_global_reservation_for_node(node)
		if node is Node2D:
			_unregister_spawn_position((node as Node2D).global_position)
		node.queue_free()


func _init_world_bounds() -> void:
	var start_chunk := _world_to_chunk(_player.global_position)
	var half_x := int(floor(world_chunks_x / 2.0))
	var half_y := int(floor(world_chunks_y / 2.0))
	_world_min_chunk = Vector2i(start_chunk.x - half_x, start_chunk.y - half_y)
	_world_max_chunk = Vector2i(_world_min_chunk.x + world_chunks_x - 1, _world_min_chunk.y + world_chunks_y - 1)


func _update_visible_chunks(force: bool) -> void:
	var center_chunk := _world_to_chunk(_player.global_position)
	var has_pending_work := not _pending_load_chunks.is_empty() or not _pending_unload_chunks.is_empty()
	if not force and center_chunk == _last_center_chunk and not has_pending_work:
		return

	if force or center_chunk != _last_center_chunk:
		_last_center_chunk = center_chunk
		_rebuild_chunk_work_queues(center_chunk)

	_process_chunk_work_queues(max_chunk_operations_per_update)


func _try_revalidate_loaded_spawns() -> void:
	if not revalidate_enabled:
		return
	if _revalidate_timer < maxf(0.05, revalidate_interval_sec):
		return
	_revalidate_timer = 0.0
	revalidate_loaded_spawns(false)


func _rebuild_chunk_work_queues(center_chunk: Vector2i) -> void:
	_required_chunks.clear()
	_pending_load_chunks.clear()
	_pending_unload_chunks.clear()
	var has_active_job := not _active_spawn_job.is_empty()
	var active_chunk := Vector2i(999999, 999999)
	if has_active_job:
		active_chunk = _active_spawn_job.get("chunk", active_chunk) as Vector2i
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
			if has_active_job and chunk == active_chunk:
				continue
			if not _loaded_chunks.has(chunk):
				_pending_load_chunks.append(chunk)

	if has_active_job and not _required_chunks.has(active_chunk):
		_cancel_active_spawn_job()

	if unload_enabled:
		for chunk_key in _loaded_chunks.keys():
			var loaded_chunk := chunk_key as Vector2i
			if not _required_chunks.has(loaded_chunk):
				_pending_unload_chunks.append(loaded_chunk)

	_sort_chunks_near_center(_pending_load_chunks, center_chunk)
	_sort_chunks_near_center(_pending_unload_chunks, center_chunk)


func _process_chunk_work_queues(chunk_budget: int) -> void:
	var operations_left := maxi(1, chunk_budget)

	if not _active_spawn_job.is_empty():
		var active_chunk: Vector2i = _active_spawn_job.get("chunk", Vector2i(999999, 999999)) as Vector2i
		if not _required_chunks.has(active_chunk):
			_cancel_active_spawn_job()
		elif _process_active_spawn_job():
			operations_left -= 1
		else:
			return

	if unload_enabled:
		while operations_left > 0 and not _pending_unload_chunks.is_empty():
			var chunk := _pending_unload_chunks.pop_front() as Vector2i
			if not _required_chunks.has(chunk) and _loaded_chunks.has(chunk):
				var unload_start_usec := Time.get_ticks_usec()
				_unload_chunk_trees(chunk)
				_loaded_chunks.erase(chunk)
				_profile_chunk_operation("unload", chunk, unload_start_usec, _last_chunk_profile_stats)
				operations_left -= 1

	while operations_left > 0 and not _pending_load_chunks.is_empty():
		var chunk := _pending_load_chunks.pop_front() as Vector2i
		if _required_chunks.has(chunk) and not _loaded_chunks.has(chunk):
			_start_spawn_chunk_job(chunk)
			if _process_active_spawn_job():
				operations_left -= 1
			else:
				return

	if not unload_enabled:
		_pending_unload_chunks.clear()
		return


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


func _start_spawn_chunk_job(chunk: Vector2i) -> void:
	var chunk_cell_count := chunk_size_tiles * chunk_size_tiles
	var stats := {
		"nodes_spawned": 0,
		"nodes_freed": 0,
		"revalidated_removed": 0
	}
	var base_cell := chunk * chunk_size_tiles
	var random_cells := _build_chunk_random_cell_order(base_cell)
	var target_min_trees := clampi(min_trees_per_chunk, 0, chunk_cell_count)
	_active_spawn_job = {
		"chunk": chunk,
		"base_cell": base_cell,
		"random_cells": random_cells,
		"nodes": [],
		"chunk_spawn_positions": [],
		"chunk_spawn_cells": {},
		"placed": 0,
		"phase": SPAWN_JOB_PHASE_RANDOM,
		"next_index": 0,
		"target_min_trees": target_min_trees,
		"attempts_limit": maxi(target_min_trees, chunk_cell_count),
		"stats": stats,
		"start_usec": Time.get_ticks_usec(),
		"work_usec": 0,
		"skip": not _is_chunk_allowed_for_biome(chunk)
	}


func _process_active_spawn_job() -> bool:
	if _active_spawn_job.is_empty():
		return false

	if bool(_active_spawn_job.get("skip", false)):
		_finish_active_spawn_job()
		return true

	var chunk: Vector2i = _active_spawn_job.get("chunk", Vector2i.ZERO) as Vector2i
	var base_cell: Vector2i = _active_spawn_job.get("base_cell", chunk * chunk_size_tiles) as Vector2i
	var random_cells: Array = _active_spawn_job.get("random_cells", [])
	var nodes: Array = _active_spawn_job.get("nodes", [])
	var chunk_spawn_positions: Array = _active_spawn_job.get("chunk_spawn_positions", [])
	var chunk_spawn_cells: Dictionary = _active_spawn_job.get("chunk_spawn_cells", {})
	var placed := int(_active_spawn_job.get("placed", 0))
	var phase := int(_active_spawn_job.get("phase", SPAWN_JOB_PHASE_RANDOM))
	var next_index := int(_active_spawn_job.get("next_index", 0))
	var target_min_trees := int(_active_spawn_job.get("target_min_trees", 0))
	var attempts_limit := int(_active_spawn_job.get("attempts_limit", chunk_size_tiles * chunk_size_tiles))
	var stats: Dictionary = _active_spawn_job.get("stats", {})
	var chunk_cell_count := chunk_size_tiles * chunk_size_tiles
	var max_attempts := maxi(1, max_spawn_candidates_per_update)
	var max_spawned := maxi(1, max_spawn_nodes_per_update)
	var time_budget_usec := int(maxf(spawn_step_time_budget_ms, 0.25) * 1000.0)
	var step_start_usec := Time.get_ticks_usec()
	var attempts_this_step := 0
	var spawned_this_step := 0

	while attempts_this_step < max_attempts and spawned_this_step < max_spawned:
		if Time.get_ticks_usec() - step_start_usec >= time_budget_usec:
			break

		if phase == SPAWN_JOB_PHASE_RANDOM and next_index >= random_cells.size():
			phase = SPAWN_JOB_PHASE_FALLBACK
			next_index = 0
			continue

		if phase == SPAWN_JOB_PHASE_FALLBACK:
			if placed >= target_min_trees or spawn_probability <= 0.0 or next_index >= attempts_limit:
				break

		var cell := Vector2i.ZERO
		if phase == SPAWN_JOB_PHASE_RANDOM:
			cell = random_cells[next_index] as Vector2i
			next_index += 1
			attempts_this_step += 1
			if _roll(cell) > spawn_probability:
				continue
		else:
			cell = _fallback_cell(base_cell, next_index)
			next_index += 1
			attempts_this_step += 1

		var n := _spawn_tree_at_cell(cell, chunk, placed, chunk_spawn_positions, chunk_spawn_cells)
		if n == null:
			continue
		nodes.append(n)
		chunk_spawn_positions.append(n.global_position)
		_register_spawn_position(n.global_position)
		chunk_spawn_cells[cell] = true
		placed += 1
		spawned_this_step += 1
		stats["nodes_spawned"] = int(stats.get("nodes_spawned", 0)) + 1

	if phase == SPAWN_JOB_PHASE_RANDOM and next_index >= random_cells.size():
		phase = SPAWN_JOB_PHASE_FALLBACK
		next_index = 0

	var step_elapsed_usec := Time.get_ticks_usec() - step_start_usec
	_active_spawn_job["nodes"] = nodes
	_active_spawn_job["chunk_spawn_positions"] = chunk_spawn_positions
	_active_spawn_job["chunk_spawn_cells"] = chunk_spawn_cells
	_active_spawn_job["placed"] = placed
	_active_spawn_job["phase"] = phase
	_active_spawn_job["next_index"] = next_index
	_active_spawn_job["stats"] = stats
	_active_spawn_job["work_usec"] = int(_active_spawn_job.get("work_usec", 0)) + step_elapsed_usec

	if phase == SPAWN_JOB_PHASE_FALLBACK:
		if placed >= target_min_trees or spawn_probability <= 0.0 or next_index >= attempts_limit:
			_finish_active_spawn_job()
			return true

	return false


func _build_chunk_random_cell_order(chunk_origin: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	cells.resize(chunk_size_tiles * chunk_size_tiles)
	var idx := 0
	for y in range(chunk_size_tiles):
		for x in range(chunk_size_tiles):
			cells[idx] = chunk_origin + Vector2i(x, y)
			idx += 1

	var state := _seed_for_chunk_shuffle(chunk_origin)
	for i in range(cells.size() - 1, 0, -1):
		state = _xorshift32(state)
		var j := int(posmod(state, i + 1))
		if i == j:
			continue
		var tmp := cells[i]
		cells[i] = cells[j]
		cells[j] = tmp
	return cells


func _seed_for_chunk_shuffle(chunk_origin: Vector2i) -> int:
	var seed := _hash_cell(chunk_origin.x, chunk_origin.y, world_seed + 11939)
	if seed == 0:
		seed = 1
	return seed


func _xorshift32(value: int) -> int:
	var x := value
	x ^= (x << 13)
	x ^= (x >> 17)
	x ^= (x << 5)
	if x == 0:
		return 1
	return x


func _finish_active_spawn_job() -> void:
	if _active_spawn_job.is_empty():
		return
	var chunk: Vector2i = _active_spawn_job.get("chunk", Vector2i.ZERO) as Vector2i
	var nodes: Array = _active_spawn_job.get("nodes", [])
	var chunk_spawn_positions: Array = _active_spawn_job.get("chunk_spawn_positions", [])
	var stats: Dictionary = _active_spawn_job.get("stats", {})
	var work_usec := int(_active_spawn_job.get("work_usec", 0))
	var profile_start_usec := Time.get_ticks_usec() - maxi(work_usec, 0)
	_spawned_trees_by_chunk[chunk] = nodes
	_spawn_positions_by_chunk[chunk] = chunk_spawn_positions
	_loaded_chunks[chunk] = true
	_last_chunk_profile_stats = stats
	_active_spawn_job.clear()
	_profile_chunk_operation("spawn", chunk, profile_start_usec, stats)


func _cancel_active_spawn_job() -> void:
	if _active_spawn_job.is_empty():
		return
	var nodes: Array = _active_spawn_job.get("nodes", [])
	for item in nodes:
		var node := item as Node
		if node == null or not is_instance_valid(node):
			continue
		if node is Node2D:
			_unregister_spawn_position((node as Node2D).global_position)
		_release_global_reservation_for_node(node)
		node.queue_free()
	_active_spawn_job.clear()


func _release_loaded_spawn_reservations() -> void:
	for chunk_key in _spawned_trees_by_chunk.keys():
		var nodes := _spawned_trees_by_chunk[chunk_key] as Array
		for item in nodes:
			var node := item as Node
			if node == null or not is_instance_valid(node):
				continue
			if node is Node2D:
				_unregister_spawn_position((node as Node2D).global_position)
			_release_global_reservation_for_node(node)
	_spawned_trees_by_chunk.clear()
	_spawn_positions_by_chunk.clear()
	_spawn_position_grid.clear()


func _spawn_tree_at_cell(
	cell: Vector2i,
	chunk: Vector2i,
	placed_index: int,
	chunk_spawn_positions: Array,
	chunk_spawn_cells: Dictionary
) -> Node2D:
	if chunk_spawn_cells.has(cell):
		return null
	var world_pos := Vector2((cell.x + 0.5) * tile_size_px.x, (cell.y + 0.5) * tile_size_px.y)
	if not _is_allowed_by_biome_layers(world_pos):
		return null
	if _overlaps_blocked(world_pos):
		return null
	if _overlaps_world_collision(world_pos):
		return null
	if _too_close_to_other_spawns(world_pos, chunk_spawn_positions):
		return null

	var candidate_rect: Rect2 = _get_candidate_spawn_rect(world_pos)
	if _is_globally_occupied(candidate_rect):
		return null
	var scene := _pick_tree_scene(cell, chunk, placed_index)
	if scene == null:
		return null
	var reservation_key: String = _make_spawn_reservation_key(chunk, cell)
	_reserve_global_footprint(reservation_key, candidate_rect)

	var tree := scene.instantiate()
	if not (tree is Node2D):
		_release_global_footprint(reservation_key)
		if tree != null:
			tree.queue_free()
		return null
	var node := tree as Node2D
	node.global_position = world_pos
	node.set_meta(GENERATED_FOOTPRINT_META, candidate_rect)
	_prepare_generated_node(node, chunk, cell, scene)
	_spawn_parent.add_child(node)
	_bind_global_reservation_to_node(node, reservation_key)
	if GameSaveManager != null and GameSaveManager.has_method("register_persistent_node"):
		GameSaveManager.register_persistent_node(node)
	return node


func _unload_chunk_trees(chunk: Vector2i) -> void:
	var stats := {
		"nodes_spawned": 0,
		"nodes_freed": 0,
		"revalidated_removed": 0
	}
	if not unload_enabled:
		_last_chunk_profile_stats = stats
		return
	if not _spawned_trees_by_chunk.has(chunk):
		_last_chunk_profile_stats = stats
		return
	var nodes := _spawned_trees_by_chunk[chunk] as Array
	for item in nodes:
		var n := item as Node
		if n != null and is_instance_valid(n):
			if n is Node2D:
				_unregister_spawn_position((n as Node2D).global_position)
			_record_generated_object_state(n)
			_release_global_reservation_for_node(n)
			n.queue_free()
			stats["nodes_freed"] = int(stats["nodes_freed"]) + 1
	_spawned_trees_by_chunk.erase(chunk)
	_spawn_positions_by_chunk.erase(chunk)
	_last_chunk_profile_stats = stats


func _is_chunk_in_world(chunk: Vector2i) -> bool:
	return chunk.x >= _world_min_chunk.x and chunk.x <= _world_max_chunk.x and chunk.y >= _world_min_chunk.y and chunk.y <= _world_max_chunk.y


func _world_to_chunk(world_pos: Vector2) -> Vector2i:
	var cell_x := floori(world_pos.x / tile_size_px.x)
	var cell_y := floori(world_pos.y / tile_size_px.y)
	return Vector2i(floori(float(cell_x) / float(chunk_size_tiles)), floori(float(cell_y) / float(chunk_size_tiles)))


func _roll(cell: Vector2i) -> float:
	var h := _hash_cell(cell.x, cell.y, world_seed + 2222)
	return float(h % 10000) / 10000.0


func _fallback_cell(chunk_origin: Vector2i, index: int) -> Vector2i:
	var h := _hash_cell(chunk_origin.x + index, chunk_origin.y - index, world_seed + 8888)
	var count := chunk_size_tiles * chunk_size_tiles
	var idx := h % count
	var local_y := int(floor(float(idx) / float(chunk_size_tiles)))
	return chunk_origin + Vector2i(idx % chunk_size_tiles, local_y)


func _hash_cell(x: int, y: int, seed_value: int) -> int:
	var h := int(seed_value)
	h = int((h * 73856093) ^ (x * 19349663) ^ (y * 83492791))
	if h < 0:
		h = -h
	return h


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


func _overlaps_blocked(world_pos: Vector2) -> bool:
	if _blocked_world_positions.is_empty():
		return false
	var radius := maxf(0.0, blocked_node_radius_px)
	var radius_sq := radius * radius
	for blocked_pos in _blocked_world_positions:
		if blocked_pos.distance_squared_to(world_pos) <= radius_sq:
			return true
	return false


func _too_close_to_other_spawns(world_pos: Vector2, chunk_spawn_positions: Array) -> bool:
	var min_dist := maxf(0.0, min_spawn_distance_px)
	if min_dist <= 0.0:
		return false
	var min_dist_sq := min_dist * min_dist
	for local_pos_variant in chunk_spawn_positions:
		var local_pos: Vector2 = local_pos_variant
		if local_pos.distance_squared_to(world_pos) < min_dist_sq:
			return true
	var cell_size := _get_spawn_position_grid_cell_size()
	var center_cell := _get_spawn_position_grid_cell(world_pos)
	var search_radius_cells := maxi(1, ceili(min_dist / cell_size))
	for gy in range(center_cell.y - search_radius_cells, center_cell.y + search_radius_cells + 1):
		for gx in range(center_cell.x - search_radius_cells, center_cell.x + search_radius_cells + 1):
			var bucket_key := Vector2i(gx, gy)
			if not _spawn_position_grid.has(bucket_key):
				continue
			var positions := _spawn_position_grid[bucket_key] as Array
			for p in positions:
				var existing_pos: Vector2 = p
				if existing_pos.distance_squared_to(world_pos) < min_dist_sq:
					return true
	return false


func _get_spawn_position_grid_cell_size() -> float:
	return maxf(min_spawn_distance_px, 1.0)


func _get_spawn_position_grid_cell(world_pos: Vector2) -> Vector2i:
	var cell_size := _get_spawn_position_grid_cell_size()
	return Vector2i(floori(world_pos.x / cell_size), floori(world_pos.y / cell_size))


func _register_spawn_position(world_pos: Vector2) -> void:
	if min_spawn_distance_px <= 0.0:
		return
	var cell := _get_spawn_position_grid_cell(world_pos)
	if not _spawn_position_grid.has(cell):
		_spawn_position_grid[cell] = []
	var positions := _spawn_position_grid[cell] as Array
	positions.append(world_pos)
	_spawn_position_grid[cell] = positions


func _unregister_spawn_position(world_pos: Vector2) -> void:
	if min_spawn_distance_px <= 0.0:
		return
	var cell := _get_spawn_position_grid_cell(world_pos)
	if not _spawn_position_grid.has(cell):
		return
	var positions := _spawn_position_grid[cell] as Array
	for i in range(positions.size() - 1, -1, -1):
		var existing_pos := positions[i] as Vector2
		if existing_pos.is_equal_approx(world_pos):
			positions.remove_at(i)
			break
	if positions.is_empty():
		_spawn_position_grid.erase(cell)
	else:
		_spawn_position_grid[cell] = positions


func _rebuild_spawn_position_grid() -> void:
	_spawn_position_grid.clear()
	if min_spawn_distance_px <= 0.0:
		return
	for chunk_key in _spawn_positions_by_chunk.keys():
		var positions := _spawn_positions_by_chunk[chunk_key] as Array
		for p in positions:
			var position: Vector2 = p
			_register_spawn_position(position)


func _is_allowed_by_biome_layers(world_pos: Vector2) -> bool:
	var lake_guard_radius := maxi(1, forbidden_layer_radius_tiles)
	if _lake_layer != null and _spawn_footprint_has_layer_tile(_lake_layer, world_pos, lake_guard_radius):
		return false
	if _spawn_only_layer != null and not _layer_has_tile_at_world(_spawn_only_layer, world_pos):
		return false
	for layer in _forbidden_layers:
		var forbidden_layer := layer as TileMapLayer
		if forbidden_layer != null and _spawn_footprint_has_layer_tile(forbidden_layer, world_pos, forbidden_layer_radius_tiles):
			return false
	return true


func _overlaps_world_collision(world_pos: Vector2) -> bool:
	var has_rect_footprint := footprint_size_px.x > 0.0 and footprint_size_px.y > 0.0
	var radius: float = maxf(spawn_clearance_radius_px, 0.0)
	if not has_rect_footprint and radius <= 0.0:
		return false
	var world := get_world_2d()
	if world == null:
		return false

	var query_position := world_pos
	if has_rect_footprint:
		var footprint_rect := _get_spawn_footprint_rect(world_pos)
		_collision_rect_shape.size = footprint_rect.size
		query_position = footprint_rect.get_center()
		_collision_query.shape = _collision_rect_shape
	else:
		_collision_circle_shape.radius = radius
		_collision_query.shape = _collision_circle_shape

	_collision_query.transform = Transform2D(0.0, query_position)
	_collision_query.collide_with_bodies = true
	_collision_query.collide_with_areas = true
	_collision_query.collision_mask = 0x7fffffff
	var hits: Array = world.direct_space_state.intersect_shape(_collision_query, 8)
	for hit_value in hits:
		if not (hit_value is Dictionary):
			continue
		var hit: Dictionary = hit_value as Dictionary
		var collider: Object = hit.get("collider", null)
		if collider is TileMapLayer:
			continue
		return true
	return false


func _layer_has_tile_at_world(layer: TileMapLayer, world_pos: Vector2) -> bool:
	var local_pos := layer.to_local(world_pos)
	var cell := layer.local_to_map(local_pos)
	return _layer_has_effective_tile_at_cell(layer, cell)


func _layer_has_tile_near_world(layer: TileMapLayer, world_pos: Vector2, radius_tiles: int) -> bool:
	var local_pos := layer.to_local(world_pos)
	var center := layer.local_to_map(local_pos)
	var r := maxi(0, radius_tiles)
	for oy in range(-r, r + 1):
		for ox in range(-r, r + 1):
			if _layer_has_effective_tile_at_cell(layer, center + Vector2i(ox, oy)):
				return true
	return false


func _spawn_footprint_has_layer_tile(layer: TileMapLayer, world_pos: Vector2, radius_tiles: int) -> bool:
	if footprint_size_px.x <= 0.0 or footprint_size_px.y <= 0.0:
		return _layer_has_tile_near_world(layer, world_pos, radius_tiles)

	var footprint_rect := _get_spawn_footprint_rect(world_pos)
	var start_cell := layer.local_to_map(layer.to_local(footprint_rect.position))
	var end_cell := layer.local_to_map(layer.to_local(footprint_rect.end))
	var min_x := mini(start_cell.x, end_cell.x) - maxi(0, radius_tiles)
	var max_x := maxi(start_cell.x, end_cell.x) + maxi(0, radius_tiles)
	var min_y := mini(start_cell.y, end_cell.y) - maxi(0, radius_tiles)
	var max_y := maxi(start_cell.y, end_cell.y) + maxi(0, radius_tiles)

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if _layer_has_effective_tile_at_cell(layer, Vector2i(x, y)):
				return true
	return false


func _layer_has_effective_tile_at_cell(layer: TileMapLayer, cell: Vector2i) -> bool:
	if layer == null:
		return false
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
			var span := _get_layer_cell_tile_span(layer, origin)
			if ox < span.x and oy < span.y:
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


func _get_layer_cell_tile_span(layer: TileMapLayer, cell: Vector2i) -> Vector2i:
	var source_id := layer.get_cell_source_id(cell)
	if source_id == -1:
		return Vector2i.ONE
	if layer.tile_set == null:
		return Vector2i.ONE

	var atlas_coords := layer.get_cell_atlas_coords(cell)
	var cache_key := "%d:%d:%d:%d:%d" % [int(layer.get_instance_id()), source_id, atlas_coords.x, atlas_coords.y, layer.get_cell_alternative_tile(cell)]
	if _layer_cell_span_cache.has(cache_key):
		return _layer_cell_span_cache[cache_key] as Vector2i

	var span := Vector2i.ONE
	var source := layer.tile_set.get_source(source_id)
	if source is TileSetAtlasSource:
		var atlas_source := source as TileSetAtlasSource
		if atlas_source.has_tile(atlas_coords):
			var atlas_span := atlas_source.get_tile_size_in_atlas(atlas_coords)
			span = Vector2i(maxi(1, atlas_span.x), maxi(1, atlas_span.y))

	_layer_cell_span_cache[cache_key] = span
	return span


func _get_spawn_footprint_rect(world_pos: Vector2) -> Rect2:
	var size := Vector2(maxf(footprint_size_px.x, 0.0), maxf(footprint_size_px.y, 0.0))
	var center := world_pos + footprint_offset_px
	return Rect2(center - size * 0.5, size)


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


func has_generation_pending() -> bool:
	return not _active_spawn_job.is_empty() or not _pending_load_chunks.is_empty() or not _pending_unload_chunks.is_empty()


func get_pending_generation_chunk_count() -> int:
	var active_count := 1 if not _active_spawn_job.is_empty() else 0
	return active_count + _pending_load_chunks.size() + _pending_unload_chunks.size()


func force_generate_step(chunk_budget: int = -1) -> void:
	if not enabled or _player == null:
		return

	var budget := chunk_budget
	if budget <= 0:
		budget = max_chunk_operations_per_update

	var center_chunk := _world_to_chunk(_player.global_position)
	if center_chunk != _last_center_chunk or not has_generation_pending():
		_last_center_chunk = center_chunk
		_rebuild_chunk_work_queues(center_chunk)

	_process_chunk_work_queues(maxi(1, budget))


func _prewarm_full_generation() -> void:
	var guard := 0
	var max_iterations := maxi(world_chunks_x * world_chunks_y * 32, 1024)
	while has_generation_pending() and guard < max_iterations:
		_process_chunk_work_queues(maxi(max_chunk_operations_per_update, 32))
		guard += 1


func _prewarm_initial_visible_generation() -> void:
	var guard := 0
	var max_iterations := 160
	while has_generation_pending() and guard < max_iterations:
		_process_chunk_work_queues(maxi(max_chunk_operations_per_update, 24))
		guard += 1


func revalidate_loaded_spawns(full_pass: bool = true) -> void:
	if not revalidate_enabled:
		return
	var keys: Array = _spawned_trees_by_chunk.keys()
	if keys.is_empty():
		_revalidate_chunk_cursor = 0
		return

	if full_pass:
		for chunk_key in keys:
			_revalidate_spawn_chunk(chunk_key as Vector2i)
		_revalidate_chunk_cursor = 0
		_rebuild_spawn_position_grid()
		return

	var total_chunks := keys.size()
	var chunk_budget := mini(maxi(1, revalidate_chunk_budget_per_pass), total_chunks)
	if _revalidate_chunk_cursor >= total_chunks:
		_revalidate_chunk_cursor = 0

	for _i in range(chunk_budget):
		var index := _revalidate_chunk_cursor % total_chunks
		_revalidate_spawn_chunk(keys[index] as Vector2i)
		_revalidate_chunk_cursor += 1

	if _revalidate_chunk_cursor >= total_chunks:
		_revalidate_chunk_cursor = 0


func _revalidate_spawn_chunk(chunk: Vector2i) -> void:
	var stats := {
		"nodes_spawned": 0,
		"nodes_freed": 0,
		"revalidated_removed": 0
	}
	if not _spawned_trees_by_chunk.has(chunk):
		_last_chunk_profile_stats = stats
		return
	var nodes := _spawned_trees_by_chunk[chunk] as Array
	var valid_nodes: Array[Node2D] = []
	var valid_positions: Array[Vector2] = []
	for item in nodes:
		var node := item as Node2D
		if node == null or not is_instance_valid(node):
			continue
		if not _is_allowed_by_biome_layers(node.global_position):
			_unregister_spawn_position(node.global_position)
			_record_generated_object_state(node)
			_release_global_reservation_for_node(node)
			node.queue_free()
			stats["nodes_freed"] = int(stats["nodes_freed"]) + 1
			stats["revalidated_removed"] = int(stats["revalidated_removed"]) + 1
			continue
		valid_nodes.append(node)
		valid_positions.append(node.global_position)
	_spawned_trees_by_chunk[chunk] = valid_nodes
	_spawn_positions_by_chunk[chunk] = valid_positions
	_last_chunk_profile_stats = stats


func _ensure_global_spawn_registry() -> void:
	var scene_root: Node = get_tree().current_scene
	var scene_id: int = int(scene_root.get_instance_id()) if scene_root != null else 0
	if _global_registry_scene_id == scene_id:
		return
	_global_registry_scene_id = scene_id
	_global_reserved_footprints.clear()
	_global_reserved_footprint_grid.clear()


func _get_candidate_spawn_rect(world_pos: Vector2) -> Rect2:
	if footprint_size_px.x > 0.0 and footprint_size_px.y > 0.0:
		return _get_spawn_footprint_rect(world_pos).abs()

	var radius := maxf(spawn_clearance_radius_px, 0.0)
	if radius <= 0.0:
		radius = maxf(min_spawn_distance_px * 0.5, minf(tile_size_px.x, tile_size_px.y) * 0.35)
	radius = maxf(radius, 1.0)
	var size := Vector2(radius * 2.0, radius * 2.0)
	return Rect2(world_pos - size * 0.5, size).abs()


func _make_spawn_reservation_key(chunk: Vector2i, cell: Vector2i) -> String:
	return "planned:%s:%d,%d:%d,%d" % [
		_get_spawner_identity(),
		chunk.x,
		chunk.y,
		cell.x,
		cell.y
	]


func _is_globally_occupied(candidate_rect: Rect2) -> bool:
	if not candidate_rect.has_area():
		return false
	for grid_cell in _get_footprint_grid_cells_for_rect(candidate_rect):
		if not _global_reserved_footprint_grid.has(grid_cell):
			continue
		var keys := _global_reserved_footprint_grid[grid_cell] as Array
		for key_variant in keys:
			var key := str(key_variant)
			var rect_variant: Variant = _global_reserved_footprints.get(key, Rect2())
			if not (rect_variant is Rect2):
				continue
			var reserved_rect: Rect2 = rect_variant
			reserved_rect = reserved_rect.abs()
			if reserved_rect.has_area() and reserved_rect.intersects(candidate_rect):
				return true
	return false


func _get_footprint_grid_cells_for_rect(rect: Rect2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var normalized_rect := rect.abs()
	if not normalized_rect.has_area():
		return result
	var min_cell := _get_footprint_grid_cell(normalized_rect.position)
	var max_pos := normalized_rect.end - Vector2(0.001, 0.001)
	var max_cell := _get_footprint_grid_cell(max_pos)
	for y in range(min_cell.y, max_cell.y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			result.append(Vector2i(x, y))
	return result


func _get_footprint_grid_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / GLOBAL_FOOTPRINT_GRID_CELL_SIZE),
		floori(world_pos.y / GLOBAL_FOOTPRINT_GRID_CELL_SIZE)
	)


func _reserve_global_footprint(key: String, rect: Rect2) -> void:
	if key.is_empty():
		return
	if _global_reserved_footprints.has(key):
		_release_global_footprint(key)
	var normalized_rect := rect.abs()
	if not normalized_rect.has_area():
		return
	_global_reserved_footprints[key] = normalized_rect
	for grid_cell in _get_footprint_grid_cells_for_rect(normalized_rect):
		if not _global_reserved_footprint_grid.has(grid_cell):
			_global_reserved_footprint_grid[grid_cell] = []
		var keys := _global_reserved_footprint_grid[grid_cell] as Array
		if not keys.has(key):
			keys.append(key)
		_global_reserved_footprint_grid[grid_cell] = keys


func _release_global_footprint(key: String) -> void:
	if key.is_empty():
		return
	var rect_variant: Variant = _global_reserved_footprints.get(key, Rect2())
	if rect_variant is Rect2:
		var rect: Rect2 = rect_variant
		for grid_cell in _get_footprint_grid_cells_for_rect(rect):
			if not _global_reserved_footprint_grid.has(grid_cell):
				continue
			var keys := _global_reserved_footprint_grid[grid_cell] as Array
			keys.erase(key)
			if keys.is_empty():
				_global_reserved_footprint_grid.erase(grid_cell)
			else:
				_global_reserved_footprint_grid[grid_cell] = keys
	_global_reserved_footprints.erase(key)


func _bind_global_reservation_to_node(node: Node2D, temp_key: String) -> void:
	if node == null:
		_release_global_footprint(temp_key)
		return
	var rect_variant: Variant = node.get_meta(GENERATED_FOOTPRINT_META, Rect2())
	if not (rect_variant is Rect2):
		_release_global_footprint(temp_key)
		return
	var rect: Rect2 = rect_variant
	rect = rect.abs()
	var node_key := "node:%d" % [node.get_instance_id()]
	_release_global_footprint(temp_key)
	_reserve_global_footprint(node_key, rect)
	node.set_meta(GENERATED_RESERVATION_KEY_META, node_key)


func _release_global_reservation_for_node(node: Node) -> void:
	if node == null:
		return
	if not node.has_meta(GENERATED_RESERVATION_KEY_META):
		return
	var key := str(node.get_meta(GENERATED_RESERVATION_KEY_META, ""))
	_release_global_footprint(key)
	node.remove_meta(GENERATED_RESERVATION_KEY_META)


func _initialize_update_phase_offsets() -> void:
	var update_interval := maxf(update_interval_sec, 0.001)
	var revalidate_interval := maxf(revalidate_interval_sec, 0.001)
	_update_timer = _compute_phase_offset(update_interval, 173)
	_revalidate_timer = _compute_phase_offset(revalidate_interval, 941)


func _compute_phase_offset(interval_sec: float, salt: int) -> float:
	var stable_hash := int(get_instance_id()) ^ (world_seed * 1103515245) ^ salt
	if stable_hash < 0:
		stable_hash = -stable_hash
	var normalized := float(stable_hash % 10000) / 10000.0
	return normalized * maxf(interval_sec, 0.001)


func _resolve_generation_seed(config_seed: int) -> int:
	if GameSaveManager != null and GameSaveManager.has_method("resolve_world_generation_seed"):
		return int(GameSaveManager.resolve_world_generation_seed(config_seed))
	if randomize_seed_on_start:
		return abs(int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_usec()))
	return config_seed


func _rebuild_spawn_scene_cache() -> void:
	_valid_spawn_scenes.clear()
	_valid_spawn_scene_weights.clear()
	_valid_spawn_scene_weight_total = 0.0

	if tree_scenes.is_empty():
		if tree_scene != null:
			_valid_spawn_scenes.append(tree_scene)
			_valid_spawn_scene_weights.append(1.0)
			_valid_spawn_scene_weight_total = 1.0
		return

	for i in range(tree_scenes.size()):
		var scene := tree_scenes[i]
		if scene == null:
			continue
		var weight := 1.0
		if i < tree_scene_weights.size():
			weight = maxf(tree_scene_weights[i], 0.0)
		_valid_spawn_scenes.append(scene)
		_valid_spawn_scene_weights.append(weight)
		_valid_spawn_scene_weight_total += weight


func _prepare_generated_node(node: Node2D, chunk: Vector2i, cell: Vector2i, scene: PackedScene) -> void:
	var object_id := _make_generated_object_id(chunk, cell, scene)
	node.set_meta("world_generation_id", object_id)
	if scene != null:
		node.set_meta("world_generation_scene_path", scene.resource_path)
	node.add_to_group("generated_world_object")
	if "persistent_id" in node:
		node.persistent_id = object_id


func _make_generated_object_id(chunk: Vector2i, cell: Vector2i, scene: PackedScene) -> String:
	var scene_path := ""
	if scene != null:
		scene_path = scene.resource_path
	return "%s:%d,%d:%d,%d:%s" % [
		_get_spawner_identity(),
		chunk.x,
		chunk.y,
		cell.x,
		cell.y,
		scene_path
	]


func _get_spawner_identity() -> String:
	var id := spawner_id.strip_edges()
	if not id.is_empty():
		return id
	return name


func _get_spawn_scene_count() -> int:
	return _valid_spawn_scenes.size()


func _pick_tree_scene(cell: Vector2i, chunk: Vector2i, placed_index: int) -> PackedScene:
	var scene_count := _valid_spawn_scenes.size()
	if scene_count <= 0:
		return tree_scene
	if scene_count == 1:
		return _valid_spawn_scenes[0]
	if _has_balanced_spawn_scene_weights():
		var offset := int(_hash_cell(chunk.x, chunk.y, world_seed + 6163) % scene_count)
		return _valid_spawn_scenes[(offset + maxi(0, placed_index)) % scene_count]
	if _valid_spawn_scene_weight_total <= 0.0:
		var uniform_index := int(_hash_cell(cell.x, cell.y, world_seed + 6163) % scene_count)
		return _valid_spawn_scenes[uniform_index]

	var h := _hash_cell(cell.x, cell.y, world_seed + 6163)
	var roll := (float(h % 100000) / 100000.0) * _valid_spawn_scene_weight_total
	var acc := 0.0
	for i in range(scene_count):
		acc += _valid_spawn_scene_weights[i]
		if roll <= acc:
			return _valid_spawn_scenes[i]
	return _valid_spawn_scenes[scene_count - 1]


func _has_balanced_spawn_scene_weights() -> bool:
	if _valid_spawn_scenes.size() <= 1:
		return false
	if _valid_spawn_scene_weight_total <= 0.0:
		return true
	var first_weight := float(_valid_spawn_scene_weights[0])
	if first_weight <= 0.0:
		return false
	for weight in _valid_spawn_scene_weights:
		if not is_equal_approx(float(weight), first_weight):
			return false
	return true


func _record_generated_object_state(node: Node) -> void:
	if GameSaveManager == null or not GameSaveManager.has_method("record_world_generation_object_state"):
		return
	GameSaveManager.record_world_generation_object_state(node)


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
	return {
		"type": "spawner",
		"name": name,
		"seed": world_seed,
		"chunk_size_tiles": chunk_size_tiles,
		"tile_size_px": tile_size_px,
		"world_min_chunk": _world_min_chunk,
		"world_max_chunk": _world_max_chunk,
		"loaded_chunks": _loaded_chunks.keys(),
		"load_entire_world_on_start": load_entire_world_on_start,
		"unload_enabled": unload_enabled,
		"revalidate_enabled": revalidate_enabled,
		"spawn_positions_by_chunk": _spawn_positions_by_chunk.duplicate(true),
		"spawn_scene_counts": _collect_spawn_scene_counts(),
		"blocked_world_positions": _blocked_world_positions.duplicate()
	}


func _collect_spawn_scene_counts() -> Dictionary:
	var counts := {}
	for chunk_key in _spawned_trees_by_chunk.keys():
		var nodes := _spawned_trees_by_chunk[chunk_key] as Array
		for item in nodes:
			var node := item as Node
			if node == null or not is_instance_valid(node):
				continue
			var scene_path := str(node.get_meta("world_generation_scene_path", ""))
			if scene_path.is_empty():
				scene_path = node.scene_file_path
			if scene_path.is_empty():
				scene_path = node.name
			counts[scene_path] = int(counts.get(scene_path, 0)) + 1
	return counts
