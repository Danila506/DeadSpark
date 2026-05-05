extends Resource
class_name ChunkWorldGeneratorConfig

@export var enabled: bool = true
@export var tile_map_path: NodePath
@export var player_path: NodePath

@export_category("Chunk Settings")
@export_range(4, 256, 1) var chunk_size_tiles: int = 16
@export_range(1, 12, 1) var load_radius_chunks: int = 3
@export_range(1, 64, 1) var world_chunks_x: int = 8
@export_range(1, 64, 1) var world_chunks_y: int = 8
@export var clear_existing_on_start: bool = true
@export var preserve_editor_tiles: bool = false
@export var load_entire_world_on_start: bool = false
@export var unload_enabled: bool = false
@export var update_interval_sec: float = 0.20
@export_range(1, 32, 1) var max_chunk_operations_per_update: int = 1

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
