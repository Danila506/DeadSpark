extends Node2D


@export var enabled: bool = true
@export var player_path: NodePath
@export var spawn_parent_path: NodePath
@export var tree_scene: PackedScene

@export_category("Chunk Settings")
@export_range(4, 256, 1) var chunk_size_tiles: int = 16
@export var tile_size_px: Vector2 = Vector2(60.0, 60.0)
@export_range(1, 12, 1) var load_radius_chunks: int = 2
@export_range(1, 64, 1) var world_chunks_x: int = 8
@export_range(1, 64, 1) var world_chunks_y: int = 8
@export var update_interval_sec: float = 0.20

@export_category("Trees")
@export var world_seed: int = 1337
@export var randomize_seed_on_start: bool = false
@export_range(0.0, 1.0, 0.01) var tree_probability: float = 0.03
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
@export var blocked_node_radius_px: float = 120.0
@export var spawn_only_on_layer_path: NodePath
@export var forbidden_layer_path: NodePath
@export var forbidden_layer_paths: Array[NodePath] = []

@export_category("Debug")
@export var debug_log: bool = false

var _player: Node2D
var _spawn_parent: Node2D
var _spawn_only_layer: TileMapLayer
var _forbidden_layers: Array = []
var _loaded_chunks := {}
var _spawned_trees_by_chunk := {}
var _last_center_chunk := Vector2i(999999, 999999)
var _update_timer: float = 0.0
var _world_min_chunk: Vector2i
var _world_max_chunk: Vector2i
var _blocked_world_positions: Array[Vector2] = []
var _spawn_positions_by_chunk := {}


func _ready() -> void:
	if not enabled:
		set_process(false)
		return

	_player = get_node_or_null(player_path) as Node2D
	_spawn_parent = get_node_or_null(spawn_parent_path) as Node2D
	_spawn_only_layer = null
	if spawn_only_on_layer_path != NodePath(""):
		_spawn_only_layer = get_node_or_null(spawn_only_on_layer_path) as TileMapLayer
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

	if _player == null or _spawn_parent == null or tree_scene == null:
		push_error("ChunkTreeSpawner: set player_path, spawn_parent_path and tree_scene")
		set_process(false)
		return

	if randomize_seed_on_start:
		world_seed = abs(int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_usec()))

	_collect_blocked_positions()
	_init_world_bounds()
	_update_visible_chunks(true)


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer < update_interval_sec:
		return
	_update_timer = 0.0
	_update_visible_chunks(false)


func _init_world_bounds() -> void:
	var start_chunk := _world_to_chunk(_player.global_position)
	var half_x := int(floor(world_chunks_x / 2.0))
	var half_y := int(floor(world_chunks_y / 2.0))
	_world_min_chunk = Vector2i(start_chunk.x - half_x, start_chunk.y - half_y)
	_world_max_chunk = Vector2i(_world_min_chunk.x + world_chunks_x - 1, _world_min_chunk.y + world_chunks_y - 1)


func _update_visible_chunks(force: bool) -> void:
	var center_chunk := _world_to_chunk(_player.global_position)
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
				_spawn_chunk_trees(chunk)
				_loaded_chunks[chunk] = true

	var to_unload: Array[Vector2i] = []
	for chunk_key in _loaded_chunks.keys():
		var loaded_chunk := chunk_key as Vector2i
		if not required_chunks.has(loaded_chunk):
			to_unload.append(loaded_chunk)

	for chunk in to_unload:
		_unload_chunk_trees(chunk)
		_loaded_chunks.erase(chunk)


func _spawn_chunk_trees(chunk: Vector2i) -> void:
	if not _is_chunk_allowed_for_biome(chunk):
		_spawned_trees_by_chunk[chunk] = []
		_spawn_positions_by_chunk[chunk] = []
		return

	var nodes: Array[Node2D] = []
	var base_cell := chunk * chunk_size_tiles
	var placed := 0

	for ly in range(chunk_size_tiles):
		for lx in range(chunk_size_tiles):
			var cell := base_cell + Vector2i(lx, ly)
			if _roll(cell) > tree_probability:
				continue
			var n := _spawn_tree_at_cell(cell)
			if n != null:
				nodes.append(n)
				placed += 1

	if placed < min_trees_per_chunk and tree_probability > 0.0:
		var need := min_trees_per_chunk - placed
		for i in range(need):
			var fallback_cell := _fallback_cell(base_cell, i)
			var n := _spawn_tree_at_cell(fallback_cell)
			if n != null:
				nodes.append(n)

	_spawned_trees_by_chunk[chunk] = nodes
	var spawn_positions: Array[Vector2] = []
	for n in nodes:
		spawn_positions.append(n.global_position)
	_spawn_positions_by_chunk[chunk] = spawn_positions


func _spawn_tree_at_cell(cell: Vector2i) -> Node2D:
	var tree := tree_scene.instantiate()
	if not (tree is Node2D):
		return null
	var node := tree as Node2D
	var world_pos := Vector2((cell.x + 0.5) * tile_size_px.x, (cell.y + 0.5) * tile_size_px.y)
	if not _is_allowed_by_biome_layers(world_pos):
		node.queue_free()
		return null
	if _overlaps_blocked(world_pos):
		node.queue_free()
		return null
	if _too_close_to_other_spawns(world_pos):
		node.queue_free()
		return null
	node.global_position = world_pos
	_spawn_parent.add_child(node)
	return node


func _unload_chunk_trees(chunk: Vector2i) -> void:
	if not _spawned_trees_by_chunk.has(chunk):
		return
	var nodes := _spawned_trees_by_chunk[chunk] as Array
	for item in nodes:
		var n := item as Node
		if n != null and is_instance_valid(n):
			n.queue_free()
	_spawned_trees_by_chunk.erase(chunk)
	_spawn_positions_by_chunk.erase(chunk)


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
			_blocked_world_positions.append((n as Node2D).global_position)


func _overlaps_blocked(world_pos: Vector2) -> bool:
	if _blocked_world_positions.is_empty():
		return false
	var radius := maxf(0.0, blocked_node_radius_px)
	for blocked_pos in _blocked_world_positions:
		if blocked_pos.distance_to(world_pos) <= radius:
			return true
	return false


func _too_close_to_other_spawns(world_pos: Vector2) -> bool:
	var min_dist := maxf(0.0, min_spawn_distance_px)
	if min_dist <= 0.0:
		return false
	for chunk_key in _spawn_positions_by_chunk.keys():
		var positions := _spawn_positions_by_chunk[chunk_key] as Array
		for p in positions:
			var existing_pos := p as Vector2
			if existing_pos.distance_to(world_pos) < min_dist:
				return true
	return false


func _is_allowed_by_biome_layers(world_pos: Vector2) -> bool:
	if _spawn_only_layer != null and not _layer_has_tile_at_world(_spawn_only_layer, world_pos):
		return false
	for layer in _forbidden_layers:
		var forbidden_layer := layer as TileMapLayer
		if forbidden_layer != null and _layer_has_tile_at_world(forbidden_layer, world_pos):
			return false
	return true


func _layer_has_tile_at_world(layer: TileMapLayer, world_pos: Vector2) -> bool:
	var local_pos := layer.to_local(world_pos)
	var cell := layer.local_to_map(local_pos)
	return layer.get_cell_source_id(cell) != -1


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
