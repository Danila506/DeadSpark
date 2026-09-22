extends Resource
class_name VillageSpawnProfile

@export var object_pool: VillageObjectPool
@export var profile_id := ""
@export_range(0, 1024, 1, "or_greater") var min_spawn_count: int = 0
@export_range(0, 1024, 1, "or_greater") var max_spawn_count: int = 1


func has_valid_pool() -> bool:
	return object_pool != null and not object_pool.is_empty_or_invalid()
