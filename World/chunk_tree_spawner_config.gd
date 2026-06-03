extends Resource
class_name ChunkTreeSpawnerConfig

const DEFAULT_WORLD_CHUNKS_AXIS: int = 6

@export var enabled: bool = true
@export var spawner_id: String = ""
@export var player_path: NodePath
@export var spawn_parent_path: NodePath
@export var clear_generated_in_spawn_parent_on_start: bool = false
@export var tree_scene: PackedScene
@export var tree_scenes: Array[PackedScene] = []
@export var tree_scene_weights: Array[float] = []

@export_category("Chunk Settings")
@export_range(4, 256, 1) var chunk_size_tiles: int = 16
@export var tile_size_px: Vector2 = Vector2(60.0, 60.0)
@export_range(1, 12, 1) var load_radius_chunks: int = 1
@export_range(1, 64, 1) var world_chunks_x: int = DEFAULT_WORLD_CHUNKS_AXIS
@export_range(1, 64, 1) var world_chunks_y: int = DEFAULT_WORLD_CHUNKS_AXIS
@export var load_entire_world_on_start: bool = false
@export var unload_enabled: bool = true
@export var update_interval_sec: float = 0.08
@export_range(1, 32, 1) var max_chunk_operations_per_update: int = 1
@export_range(1, 512, 1) var max_spawn_candidates_per_update: int = 24
@export_range(1, 128, 1) var max_spawn_nodes_per_update: int = 2
@export_range(0, 512, 1) var max_total_spawn_attempts_per_chunk: int = 0
@export_range(1, 64, 1) var max_expensive_spawn_checks_per_update: int = 4
@export_range(0.25, 16.0, 0.25) var spawn_step_time_budget_ms: float = 1.5
@export var large_structure_mode: bool = false
@export_range(1, 9, 1) var large_structure_candidates_per_chunk: int = 9
@export_range(0.0, 480.0, 1.0) var large_structure_candidate_jitter_px: float = 120.0
@export var revalidate_enabled: bool = false
@export var revalidate_interval_sec: float = 0.6
@export_range(1, 32, 1) var revalidate_chunk_budget_per_pass: int = 2

@export_category("Trees")
@export var world_seed: int = 1337
@export var randomize_seed_on_start: bool = false
@export_range(0.0, 1.0, 0.01) var spawn_probability: float = 0.03
@export var min_trees_per_chunk: int = 1
@export var min_spawn_distance_px: float = 0.0
@export var spawn_cell_jitter_px: Vector2 = Vector2.ZERO
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
