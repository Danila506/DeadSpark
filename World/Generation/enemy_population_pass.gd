class_name EnemyPopulationPass
extends Node

var blocking_errors:Array[String]=[]
func build_manifests(master_seed:int, providers:Array) -> Dictionary:
	blocking_errors.clear(); var manifests:Array[Dictionary]=[]; var ordered:=providers.duplicate(); ordered.sort_custom(func(a,b):return String(a.call("get_enemy_population_owner_id"))<String(b.call("get_enemy_population_owner_id")))
	for provider in ordered:
		var check:=EnemySpawnMarkerProviderContract.validate(provider); if not check.valid: _error(master_seed,"","","","",";".join(check.errors)); continue
		var owner:=String(provider.call("get_enemy_population_owner_id")); var profile:EnemyPopulationProfile=provider.call("get_enemy_population_profile"); var profile_check:=profile.validate(); if not profile_check.valid: _error(master_seed,owner,profile.profile_id,"","",";".join(profile_check.errors)); continue
		var manifest:=_build(master_seed,owner,profile,provider.call("get_enemy_spawn_markers") as Array); if manifest!=null: manifests.append(manifest.canonical_record())
	manifests.sort_custom(func(a,b):return String(a.owner_generated_object_id)<String(b.owner_generated_object_id)); return {"id":"enemy_population_v1","population_manifests":manifests,"population_manifest_hash":GenerationHashes.sha256_of(manifests),"population_content_hash":GenerationHashes.sha256_of(manifests),"blocking_errors":blocking_errors.duplicate()}
func _build(seed:int, owner:String, profile:EnemyPopulationProfile, raw_markers:Array) -> EnemyPopulationManifest:
	var markers:Array[EnemySpawnMarkerRecord]=[]; var seen:= {}
	for marker in raw_markers:
		if not (marker is EnemySpawnMarkerRecord): _error(seed,owner,profile.profile_id,"","","INVALID_MARKER"); return null
		if marker.marker_id.is_empty() or seen.has(marker.marker_id) or marker.capacity<0: _error(seed,owner,profile.profile_id,marker.marker_id,"","INVALID_OR_DUPLICATE_MARKER"); return null
		seen[marker.marker_id]=true; if marker.enabled: markers.append(marker)
	markers.sort_custom(func(a,b):return a.marker_id<b.marker_id); var manifest:=EnemyPopulationManifest.new(); manifest.owner_generated_object_id=owner; manifest.profile_id=profile.profile_id
	var valid:Array[EnemyPopulationEntry]=[]; for entry in profile.entries: if entry!=null and entry.enabled and entry.validate().valid: valid.append(entry)
	valid.sort_custom(func(a,b):return a.entry_id<b.entry_id); var total:=0; var ids:= {}
	for marker in markers:
		var marker_cap: int=min(marker.capacity,profile.per_marker_cap); var count: int=min(marker_cap,posmod(WorldSeedService.derive_seed(seed,"enemy_population/%s/%s/count"%[owner,marker.marker_id]),marker_cap+1))
		for ordinal in range(count):
			var eligible: Array[EnemyPopulationEntry]=[]
			for candidate in valid:
				if candidate.allowed_marker_tags.is_empty() or candidate.allowed_marker_tags.any(func(tag):return marker.tags.has(tag)): eligible.append(candidate)
			if eligible.is_empty(): continue
			var entry: EnemyPopulationEntry=eligible[posmod(WorldSeedService.derive_seed(seed,"enemy_population/%s/%s/entry/%d"%[owner,marker.marker_id,ordinal]),eligible.size())]
			var record:=EnemyPopulationRecord.new(); record.owner_generated_object_id=owner;record.marker_id=marker.marker_id;record.profile_id=profile.profile_id;record.enemy_entry_id=entry.entry_id;record.enemy_resource_key=entry.enemy_scene.resource_path;record.ordinal=ordinal;record.population_id="%s/population/%s/%s/%d"%[owner,marker.marker_id,entry.entry_id,ordinal];record.position=marker.position;record.initial_state=entry.initial_state
			if ids.has(record.population_id): _error(seed,owner,profile.profile_id,marker.marker_id,entry.entry_id,"DUPLICATE_POPULATION_ID"); return null
			ids[record.population_id]=true; manifest.records.append(record); total+=1
	if total<profile.min_total_count or total>profile.max_total_count or total>profile.spawn_budget: _error(seed,owner,profile.profile_id,"","","IMPOSSIBLE_COUNT_OR_BUDGET required=%d available=%d"%[profile.min_total_count,total]); return null
	return manifest
func _error(seed:int,owner:String,profile:String,marker:String,entry:String,reason:String)->void: blocking_errors.append("stage=enemy_population owner=%s profile=%s marker=%s entry=%s seed=%d reason=%s"%[owner,profile,marker,entry,seed,reason])
