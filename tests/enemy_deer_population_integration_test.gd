extends Node

const DEER_SCENE := preload("res://Animals/Deer/Deer.tscn")
const PROVIDER_SCRIPT := preload("res://World/Generation/deer_population_provider.gd")
const PROFILE := preload("res://Resources/WorldGen/EnemyPopulation/deer_population_profile.tres")
const PASS := preload("res://World/Generation/enemy_population_pass.gd")
const PERSISTENCE := preload("res://World/Generation/enemy_population_persistence.gd")
const CAMP := preload("res://Enemies/Bandits/bandit_base.tscn")

func _ready() -> void: call_deferred("_run")
func _assert(value: bool, message: String) -> bool:
	if value: return true
	push_error("Enemy Deer population: " + message); get_tree().quit(1); return false
func _provider(owner_region := "finite_00") -> DeerPopulationProvider:
	var provider := PROVIDER_SCRIPT.new() as DeerPopulationProvider
	provider.world_id = "default"; provider.region_id = owner_region; provider.population_profile = PROFILE; add_child(provider); return provider
func _build(seed: int, providers: Array) -> Dictionary: return (PASS.new() as EnemyPopulationPass).build_manifests(seed, providers)
func _manifest(raw: Dictionary) -> EnemyPopulationManifest:
	var output := EnemyPopulationManifest.new(); output.owner_generated_object_id = String(raw.owner_generated_object_id); output.profile_id = String(raw.profile_id)
	for value in raw.records:
		var r := EnemyPopulationRecord.new(); r.population_id=String(value.population_id);r.owner_generated_object_id=String(value.owner_generated_object_id);r.marker_id=String(value.marker_id);r.profile_id=String(value.profile_id);r.enemy_entry_id=String(value.enemy_entry_id);r.enemy_resource_key=String(value.enemy_resource_key);r.position=value.position as Vector2;r.ordinal=int(value.ordinal);r.initial_state=String(value.initial_state);output.records.append(r)
	return output
func _actors(provider: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in provider.get_children():
		if child.is_in_group("deer_generated_population"):
			result.append(child)
	result.sort_custom(func(a, b): return String(a.get_meta("population_id", "")) < String(b.get_meta("population_id", "")))
	return result
func _ids(provider: Node) -> Array[String]:
	var result: Array[String] = []
	for actor in _actors(provider):
		result.append(String(actor.get_meta("population_id", "")))
	return result
func _json_roundtrip(state: Dictionary) -> Dictionary:
	var path := "user://enemy_deer_population_roundtrip.json";var f:=FileAccess.open(path,FileAccess.WRITE);f.store_string(JSON.stringify(PERSISTENCE.canonicalize_saved_state(state)));f.close();f=FileAccess.open(path,FileAccess.READ);var json:=JSON.new();_assert(json.parse(f.get_as_text())==OK,"JSON");f.close();return json.data as Dictionary
func _run() -> void:
	_assert(DEER_SCENE.instantiate()!=null,"production scene instantiate")
	var occupancy := WorldOccupancyMap.new(); occupancy.reset(Rect2i(Vector2i.ZERO, Vector2i(8, 2)))
	occupancy.claim_cells([Vector2i(1, 0)], WorldOccupancyMap.ROAD, "road", "test")
	occupancy.claim_cells([Vector2i(2, 0)], WorldOccupancyMap.ROAD_CLEARANCE, "clearance", "test")
	occupancy.claim_cells([Vector2i(3, 0)], WorldOccupancyMap.WATER, "water", "test")
	occupancy.claim_cells([Vector2i(4, 0)], WorldOccupancyMap.POI, "poi", "test")
	occupancy.claim_cells([Vector2i(5, 0)], WorldOccupancyMap.STATIC_PROP, "environment", "test")
	var geography := _provider("geography"); geography.candidate_positions=[Vector2(60,0),Vector2(120,0),Vector2(180,0),Vector2(240,0),Vector2(300,0),Vector2(360,0),Vector2(540,0)]; geography.set_geography_context(occupancy)
	var markers:=geography.get_enemy_spawn_markers();var rejected:=geography.get_exclusion_diagnostics();_assert(markers.filter(func(m):return m.enabled).size()==1,"occupancy and bounds filtering");_assert(rejected.map(func(d):return String(d.reason))==["road","road_clearance","water","poi_footprint","environment_footprint","out_of_bounds"],"canonical exclusion reasons")
	var deer := _provider();var first:=_build(1337,[deer]);var reordered:=_build(1337,[deer]);var varied:=_build(7331,[deer])
	_assert(first.blocking_errors.is_empty() and first.population_manifest_hash==reordered.population_manifest_hash,"same seed/candidate order")
	_assert(first.population_manifest_hash!=varied.population_manifest_hash,"different seed variation")
	var camp:=CAMP.instantiate();camp.world_generated_mode=true;camp.generated_object_id="poi/deer_rng";add_child(camp);var with_camp:=_build(1337,[camp,deer]);var deer_only:=_build(1337,[deer]);var deer_raw:Dictionary=with_camp.population_manifests.filter(func(m):return String(m.owner_generated_object_id)==deer.get_enemy_population_owner_id())[0];var deer_only_raw:Dictionary=deer_only.population_manifests[0];if not _assert(GenerationHashes.sha256_of(deer_raw)==GenerationHashes.sha256_of(deer_only_raw),"bandit RNG isolation"):return
	var manifest:=_manifest(first.population_manifests[0]);_assert(deer.apply_enemy_population_manifest(manifest).valid,"materialize");var actors:=_actors(deer);_assert(actors.size()==manifest.records.size(),"count")
	_assert(deer.apply_enemy_population_manifest(manifest).valid and _actors(deer).size()==actors.size(),"idempotent")
	for actor in actors:_assert(actor.has_meta("population_id") and actor.has_meta("population_manifest_hash"),"stable metadata")
	if not actors.is_empty(): actors[0].died.emit(actors[0])
	if actors.size()>1: deer.mark_population_despawned(String(actors[1].get_meta("population_id")))
	var state:=_json_roundtrip(deer.serialize_population_state());_assert(PERSISTENCE.validate_saved_state(state,deer).valid,"persistence valid")
	var killed:=String(actors[0].get_meta("population_id")) if not actors.is_empty() else "";deer.queue_free();await get_tree().process_frame
	var restored:=_provider();var changed_profile:EnemyPopulationProfile=PROFILE.duplicate(true);changed_profile.profile_id="deer_changed_after_save";restored.population_profile=changed_profile;_assert(restored.restore_population_state(state).valid,"saved state priority")
	var ids:=_ids(restored)
	_assert(killed.is_empty() or not ids.has(killed),"killed no resurrection")
	_assert(restored.restore_population_state(state).valid and ids==_ids(restored),"repeated restore")
	var legacy:=load("res://Resources/WorldGen/spawner_deer.tres") as ChunkTreeSpawnerConfig;_assert(legacy!=null and legacy.tree_scene==DEER_SCENE,"legacy config remains explicit")
	var digest:=GenerationHashes.sha256_of({"manifest":first.population_manifest_hash,"state":PERSISTENCE.compute_saved_state_hash(state),"owner":restored.get_enemy_population_owner_id()})
	print("ENEMY_DEER_POPULATION_INTEGRATION_TEST=PASS digest=%s"%digest);get_tree().quit(0)
