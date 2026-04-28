extends Resource
class_name ChunkTreeSpawnerConfig

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
@export_range(0, 8, 1) var forbidden_layer_radius_tiles: int = 0

@export_category("Debug")
@export var debug_log: bool = false
