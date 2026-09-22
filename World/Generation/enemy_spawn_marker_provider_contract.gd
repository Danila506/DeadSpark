class_name EnemySpawnMarkerProviderContract
extends RefCounted
static func validate(provider: Node) -> Dictionary:
	var errors:Array[String]=[]
	for method in ["get_enemy_population_owner_id","get_enemy_population_profile","get_enemy_spawn_markers"]:
		if provider==null or not provider.has_method(method): errors.append("MISSING_PROVIDER_API:%s"%method)
	if not errors.is_empty(): return {"valid":false,"errors":errors}
	if String(provider.call("get_enemy_population_owner_id")).is_empty(): errors.append("MISSING_OWNER_GENERATED_OBJECT_ID")
	if not (provider.call("get_enemy_population_profile") is EnemyPopulationProfile): errors.append("MISSING_PROFILE")
	return {"valid":errors.is_empty(),"errors":errors}
