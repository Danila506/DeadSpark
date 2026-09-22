class_name EnemyPopulationEntry
extends Resource

@export var entry_id := ""
@export var enabled := true
@export var enemy_scene: PackedScene
@export var weight := 1.0
@export var min_count := 0
@export var max_count := 1
@export var allowed_marker_tags: Array[String] = []
@export var unique := false
@export var spawn_radius := 0.0
@export var initial_state := "alive"

func validate() -> Dictionary:
	var errors: Array[String] = []
	if entry_id.is_empty(): errors.append("MISSING_ENTRY_ID")
	if enemy_scene == null or enemy_scene.resource_path.is_empty(): errors.append("MISSING_ENEMY_RESOURCE")
	if weight <= 0.0: errors.append("INVALID_WEIGHT")
	if min_count < 0 or max_count < min_count: errors.append("INVALID_ENTRY_COUNT")
	return {"valid":errors.is_empty(),"errors":errors}

func canonical_record() -> Dictionary:
	var tags:=allowed_marker_tags.duplicate(); tags.sort()
	return {"entry_id":entry_id,"enabled":enabled,"enemy_resource_key":enemy_scene.resource_path if enemy_scene!=null else "","weight":weight,"min_count":min_count,"max_count":max_count,"allowed_marker_tags":tags,"unique":unique,"spawn_radius":spawn_radius,"initial_state":initial_state}
