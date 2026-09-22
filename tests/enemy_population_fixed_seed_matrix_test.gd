extends Node

const CAMP := preload("res://Enemies/Bandits/bandit_base.tscn")
const DEER := preload("res://World/Generation/deer_population_provider.gd")
const DEER_PROFILE := preload("res://Resources/WorldGen/EnemyPopulation/deer_population_profile.tres")
const PASS := preload("res://World/Generation/enemy_population_pass.gd")
const PERSISTENCE := preload("res://World/Generation/enemy_population_persistence.gd")

func _ready() -> void: call_deferred("_run")
func _assert(value: bool, message: String) -> void:
	if value: return
	push_error("Enemy population matrix: " + message); get_tree().quit(1)
func _providers() -> Array:
	var camp := CAMP.instantiate(); camp.world_generated_mode=true; camp.generated_object_id="poi/matrix_camp"; add_child(camp)
	var deer := DEER.new() as DeerPopulationProvider; deer.population_profile=DEER_PROFILE; add_child(deer)
	return [camp,deer]
func _build(seed: int, providers: Array) -> Dictionary: return (PASS.new() as EnemyPopulationPass).build_manifests(seed, providers)
func _all_ids(raw: Dictionary) -> Array[String]:
	var ids:Array[String]=[]
	for manifest in raw.population_manifests:
		for record in manifest.records: ids.append(String(record.population_id))
	ids.sort(); return ids
func _run() -> void:
	var one := _providers(); var run_one := _build(1337, one); var digest_one := GenerationHashes.sha256_of(run_one.population_manifests)
	_assert(run_one.blocking_errors.is_empty(), "run one valid")
	var two := _providers(); var run_two := _build(1337, two); var digest_two := GenerationHashes.sha256_of(run_two.population_manifests)
	_assert(digest_one == digest_two, "same seed")
	var reordered := _build(1337, [two[1], two[0]])
	_assert(GenerationHashes.sha256_of(reordered.population_manifests) == digest_one, "provider reorder")
	var varied := _build(7331, _providers())
	_assert(GenerationHashes.sha256_of(varied.population_manifests) != digest_one, "seed variation")
	var ids := _all_ids(run_one); var seen := {}; for id in ids: _assert(not seen.has(id), "duplicate id"); seen[id]=true
	var deer_raw: Dictionary = run_one.population_manifests.filter(func(m): return String(m.owner_generated_object_id).begins_with("world/default/wildlife/deer"))[0]
	var manifest := EnemyPopulationManifest.new(); manifest.owner_generated_object_id=String(deer_raw.owner_generated_object_id); manifest.profile_id=String(deer_raw.profile_id)
	for raw in deer_raw.records:
		var r:=EnemyPopulationRecord.new(); r.population_id=String(raw.population_id);r.owner_generated_object_id=String(raw.owner_generated_object_id);r.marker_id=String(raw.marker_id);r.profile_id=String(raw.profile_id);r.enemy_entry_id=String(raw.enemy_entry_id);r.enemy_resource_key=String(raw.enemy_resource_key);r.position=raw.position as Vector2;r.ordinal=int(raw.ordinal);r.initial_state=String(raw.initial_state);manifest.records.append(r)
	var deer := one[1] as DeerPopulationProvider; _assert(deer.apply_enemy_population_manifest(manifest).valid,"deer materialize")
	var actors:=deer.get_children().filter(func(n):return n.is_in_group("deer_generated_population")); _assert(actors.size()==manifest.records.size(),"no duplicate actors")
	if not actors.is_empty(): actors[0].died.emit(actors[0])
	var state:=deer.serialize_population_state(); var path:="user://enemy_population_matrix_roundtrip.json"; var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(PERSISTENCE.canonicalize_saved_state(state)));file.close();var parsed:=JSON.parse_string(FileAccess.open(path,FileAccess.READ).get_as_text()) as Dictionary
	deer.queue_free(); await get_tree().process_frame
	var restored:=DEER.new() as DeerPopulationProvider;restored.population_profile=DEER_PROFILE;add_child(restored);_assert(restored.restore_population_state(parsed).valid,"JSON restore")
	var restored_ids:Array[String]=[];for actor in restored.get_children():if actor.is_in_group("deer_generated_population"):restored_ids.append(String(actor.get_meta("population_id","")))
	var tombstones:Array=parsed.tombstones;for tombstone in tombstones:_assert(not restored_ids.has(String(tombstone)),"tombstone no resurrection")
	print("ENEMY_POPULATION_FIXED_SEED_MATRIX_TEST=PASS run1=%s run2=%s tombstones=%d duplicates=0" % [digest_one,digest_two,tombstones.size()]);get_tree().quit(0)
