extends Node

const CAMP_1 := preload("res://Enemies/Bandits/bandit_base.tscn")
const CAMP_2 := preload("res://Enemies/Bandits/BanditBase2.tscn")
const POPULATION_PASS := preload("res://World/Generation/enemy_population_pass.gd")
const PERSISTENCE := preload("res://World/Generation/enemy_population_persistence.gd")


func _ready() -> void:
	call_deferred("_run")


func _assert(value: bool, message: String) -> bool:
	if value:
		return true
	push_error("Enemy bandit persistence reload test: " + message)
	get_tree().quit(1)
	return false


func _make_camp(scene: PackedScene, owner_id: String, profile_suffix := "") -> Node:
	var camp := scene.instantiate()
	camp.world_generated_mode = true
	camp.generated_object_id = owner_id
	if not profile_suffix.is_empty():
		var changed_profile: EnemyPopulationProfile = camp.population_profile.duplicate(true)
		changed_profile.profile_id = "%s_%s" % [changed_profile.profile_id, profile_suffix]
		camp.population_profile = changed_profile
	add_child(camp)
	return camp


func _manifest_for(camp: Node, seed := 1337) -> EnemyPopulationManifest:
	var output := (POPULATION_PASS.new() as EnemyPopulationPass).build_manifests(seed, [camp])
	if not _assert(output.blocking_errors.is_empty(), "generation is valid"):
		return null
	var raw: Dictionary = output.population_manifests[0]
	var manifest := EnemyPopulationManifest.new()
	manifest.owner_generated_object_id = String(raw.get("owner_generated_object_id", ""))
	manifest.profile_id = String(raw.get("profile_id", ""))
	for raw_record in raw.get("records", []) as Array:
		var record := EnemyPopulationRecord.new()
		record.population_id = String(raw_record.get("population_id", ""))
		record.owner_generated_object_id = String(raw_record.get("owner_generated_object_id", ""))
		record.marker_id = String(raw_record.get("marker_id", ""))
		record.profile_id = String(raw_record.get("profile_id", ""))
		record.enemy_entry_id = String(raw_record.get("enemy_entry_id", ""))
		record.enemy_resource_key = String(raw_record.get("enemy_resource_key", ""))
		record.position = raw_record.get("position", Vector2.ZERO) as Vector2
		record.ordinal = int(raw_record.get("ordinal", 0))
		record.initial_state = String(raw_record.get("initial_state", "alive"))
		manifest.records.append(record)
	return manifest


func _manifest_with_min_records(camp: Node, minimum: int) -> EnemyPopulationManifest:
	for seed in [1337, 7331, 15885, 1001, 2026, 99999]:
		var candidate := _manifest_for(camp, seed)
		if candidate != null and candidate.records.size() >= minimum:
			return candidate
	return null


func _actors(camp: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in camp.get_children():
		if child.is_in_group("camp_generated_population"):
			result.append(child)
	result.sort_custom(func(a: Node, b: Node): return String(a.get_meta("population_id", "")) < String(b.get_meta("population_id", "")))
	return result


func _actor_ids(camp: Node) -> Array[String]:
	var result: Array[String] = []
	for actor in _actors(camp):
		result.append(String(actor.get_meta("population_id", "")))
	return result


func _json_safe(value: Variant) -> Variant:
	if value is Vector2:
		return {"x": value.x, "y": value.y}
	if value is Dictionary:
		var result := {}
		for key in value.keys():
			result[String(key)] = _json_safe(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_json_safe(item))
		return result
	return value


func _json_roundtrip(state: Dictionary, file_name: String) -> Dictionary:
	var path := "user://%s" % file_name
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(_json_safe(state)))
	file.close()
	file = FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	var parse_result := json.parse(file.get_as_text())
	file.close()
	if not _assert(parse_result == OK, "JSON parses"):
		return {}
	return json.data as Dictionary


func _assert_saved_restore(scene: PackedScene, owner_id: String, file_name: String) -> String:
	var original := _make_camp(scene, owner_id)
	var manifest := _manifest_with_min_records(original, 2)
	if manifest == null or not _assert(manifest.records.size() >= 2, "two-record bandit manifest"):
		return ""
	if not _assert(original.apply_enemy_population_manifest(manifest).valid, "initial materialization"):
		return ""
	var all_alive_source: Dictionary = original.serialize_population_state()
	var all_alive := _json_roundtrip(all_alive_source, "%s_alive.json" % file_name)
	var all_alive_validation := PERSISTENCE.validate_saved_state(all_alive, original)
	if not _assert(all_alive_validation.valid, "all-alive JSON state: %s" % [all_alive_validation.errors]):
		return ""
	var initial_ids := _actor_ids(original)
	var killed_id := initial_ids[0]
	var second_killed_id := initial_ids[1]
	# Exercise the existing EnemyAI death signal rather than a second death system.
	var killed_actor := _actors(original)[0]
	killed_actor.died.emit(killed_actor)
	_actors(original)[1].died.emit(_actors(original)[1])
	if initial_ids.size() >= 3:
		original.mark_population_despawned(initial_ids[2])
	var state := _json_roundtrip(original.serialize_population_state(), file_name)
	var persisted_validation := PERSISTENCE.validate_saved_state(state, original)
	if not _assert(persisted_validation.valid, "killed/despawned JSON state: %s" % [persisted_validation.errors]):
		return ""
	if not _assert(String(state.actor_states[killed_id]) == PERSISTENCE.STATE_KILLED, "death signal creates tombstone"):
		return ""
	if not _assert(String(state.actor_states[second_killed_id]) == PERSISTENCE.STATE_KILLED, "multiple killed actors persist"):
		return ""
	if not _assert(state.tombstones.has(killed_id), "killed tombstone persists"):
		return ""
	var digest := PERSISTENCE.compute_saved_state_hash(state)
	original.queue_free()

	var restored := _make_camp(scene, owner_id, "changed_after_save")
	if not _assert(restored.restore_population_state(state).valid, "saved manifest wins changed profile"):
		return ""
	var restored_ids := _actor_ids(restored)
	if not _assert(not restored_ids.has(killed_id), "killed actor does not materialize"):
		return ""
	if not _assert(restored_ids.size() == initial_ids.size() - state.tombstones.size(), "only alive actors materialize"):
		return ""
	if not _assert(restored.restore_population_state(state).valid and _actor_ids(restored) == restored_ids, "repeated restore idempotent"):
		return ""
	var changed_seed := _manifest_for(restored, 7331)
	if not _assert(changed_seed != null and not restored_ids.has(killed_id), "seed change cannot resurrect"):
		return ""
	# Reordering structural marker enumeration must not affect the already loaded state.
	var markers: Array = restored.get_enemy_spawn_markers()
	markers.reverse()
	if not _assert(not restored_ids.has(killed_id), "marker order cannot resurrect"):
		return ""

	var corrupt := state.duplicate(true)
	corrupt["population_manifest_hash"] = "broken"
	if not _assert(not restored.restore_population_state(corrupt).valid, "corrupted manifest blocks restore"):
		return ""
	var owner_mismatch := state.duplicate(true)
	owner_mismatch["owner_generated_object_id"] = "poi/other"
	if not _assert(not restored.restore_population_state(owner_mismatch).valid, "owner mismatch blocks restore"):
		return ""
	var unknown_state := state.duplicate(true)
	unknown_state["actor_states"]["unknown_population"] = PERSISTENCE.STATE_KILLED
	unknown_state["saved_state_hash"] = PERSISTENCE.compute_saved_state_hash(unknown_state)
	if not _assert(not restored.restore_population_state(unknown_state).valid, "unknown population blocks restore"):
		return ""
	var duplicate := state.duplicate(true)
	duplicate["population_records"].append(duplicate["population_records"][0].duplicate(true))
	duplicate["saved_state_hash"] = PERSISTENCE.compute_saved_state_hash(duplicate)
	if not _assert(not restored.restore_population_state(duplicate).valid, "duplicate population blocks restore"):
		return ""
	var missing_resource := state.duplicate(true)
	missing_resource["population_records"][0]["enemy_resource_key"] = "res://missing_enemy.tscn"
	missing_resource["saved_state_hash"] = PERSISTENCE.compute_saved_state_hash(missing_resource)
	if not _assert(not restored.restore_population_state(missing_resource).valid, "missing resource blocks restore"):
		return ""
	restored.queue_free()
	return digest


func _run() -> void:
	var digest_one: String = _assert_saved_restore(CAMP_1, "poi/persistence_camp_one", "enemy_bandit_persistence_one.json")
	if digest_one.is_empty():
		return
	var digest_two: String = _assert_saved_restore(CAMP_2, "poi/persistence_camp_two", "enemy_bandit_persistence_two.json")
	if digest_two.is_empty():
		return
	var standalone := CAMP_1.instantiate()
	standalone.world_generated_mode = false
	add_child(standalone)
	for _frame in range(8):
		await get_tree().process_frame
	if not _assert(_actors(standalone).is_empty() and standalone.get_child_count() > 4, "standalone camp remains legacy-functional"):
		return
	print("ENEMY_BANDIT_PERSISTENCE_RELOAD_TEST=PASS digest=%s" % GenerationHashes.sha256_of({"camp_one": digest_one, "camp_two": digest_two}))
	get_tree().quit(0)
