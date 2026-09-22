class_name EnemyPopulationPersistence
extends RefCounted

## Stage-8-local persistence contract for world-generated enemy populations.
## Despawn is permanent: both killed and explicitly despawned records stay as
## tombstones and are never rematerialized by this adapter.
const SCHEMA_VERSION := 1
const DESPAWN_POLICY := "permanent"
const STATE_ALIVE := "alive"
const STATE_KILLED := "killed"
const STATE_DESPAWNED := "despawned"
const VALID_STATES := [STATE_ALIVE, STATE_KILLED, STATE_DESPAWNED]


static func get_persistence_key(owner_generated_object_id: String) -> String:
	return "enemy_population/%s" % owner_generated_object_id.strip_edges()


static func serialize_camp(camp: Node) -> Dictionary:
	var manifest: EnemyPopulationManifest = camp.applied_population_manifest
	var states: Dictionary = camp.get_population_states() if camp.has_method("get_population_states") else {}
	var canonical_records: Array = []
	if manifest != null:
		canonical_records = manifest.canonical_record().get("records", []) as Array
	var result := canonicalize_saved_state({
		"schema_version": SCHEMA_VERSION,
		"persistence_key": get_persistence_key(String(camp.get_enemy_population_owner_id())),
		"owner_generated_object_id": String(camp.get_enemy_population_owner_id()),
		"population_manifest_hash": manifest.manifest_hash() if manifest != null else "",
		"population_records": canonical_records,
		"actor_states": states,
		"tombstones": _tombstones_from_states(states),
		"despawn_policy": DESPAWN_POLICY,
	})
	result["saved_state_hash"] = compute_saved_state_hash(result)
	return result


static func restore_camp(camp: Node, data: Dictionary) -> Dictionary:
	var validation := validate_saved_state(data, camp)
	if not validation.valid:
		return {"valid": false, "errors": validation.errors}
	if not camp.has_method("restore_persisted_population_state"):
		return {"valid": false, "errors": ["MISSING_PERSISTENCE_RESTORE_API"]}
	return camp.restore_persisted_population_state(validation.manifest, validation.actor_states)


static func validate_saved_state(data: Dictionary, camp: Node = null) -> Dictionary:
	var errors: Array[String] = []
	if int(data.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("UNSUPPORTED_ENEMY_POPULATION_SCHEMA")
	var owner_id := String(data.get("owner_generated_object_id", "")).strip_edges()
	if owner_id.is_empty():
		errors.append("MISSING_OWNER_ID")
	if String(data.get("persistence_key", "")) != get_persistence_key(owner_id):
		errors.append("INVALID_PERSISTENCE_KEY")
	if String(data.get("despawn_policy", "")) != DESPAWN_POLICY:
		errors.append("INVALID_DESPAWN_POLICY")
	if camp != null and owner_id != String(camp.get_enemy_population_owner_id()):
		errors.append("OWNER_MISMATCH")

	var raw_records: Variant = data.get("population_records", [])
	if not (raw_records is Array):
		errors.append("INVALID_POPULATION_RECORDS")
		raw_records = []
	var manifest := EnemyPopulationManifest.new()
	manifest.owner_generated_object_id = owner_id
	var seen_ids := {}
	for raw_value in raw_records as Array:
		if not (raw_value is Dictionary):
			errors.append("INVALID_POPULATION_RECORD")
			continue
		var record := _record_from_canonical(raw_value as Dictionary)
		if record.population_id.is_empty() or seen_ids.has(record.population_id):
			errors.append("DUPLICATE_POPULATION_ID")
		seen_ids[record.population_id] = true
		if record.owner_generated_object_id != owner_id:
			errors.append("INVALID_RECORD_OWNER")
		if record.profile_id.is_empty() or record.marker_id.is_empty() or record.enemy_entry_id.is_empty():
			errors.append("INVALID_POPULATION_RECORD")
		if record.enemy_resource_key.is_empty() or not ResourceLoader.exists(record.enemy_resource_key):
			errors.append("MISSING_ENEMY_RESOURCE")
		elif load(record.enemy_resource_key) as PackedScene == null:
			errors.append("MISSING_ENEMY_RESOURCE")
		if not is_finite(record.position.x) or not is_finite(record.position.y):
			errors.append("INVALID_TRANSFORM")
		manifest.profile_id = record.profile_id
		manifest.records.append(record)
	if manifest.manifest_hash() != String(data.get("population_manifest_hash", "")):
		errors.append("CORRUPTED_MANIFEST_HASH")

	var raw_states: Variant = data.get("actor_states", {})
	if not (raw_states is Dictionary):
		errors.append("INVALID_ACTOR_STATES")
		raw_states = {}
	var states: Dictionary = raw_states as Dictionary
	for raw_id in states.keys():
		var population_id := String(raw_id)
		if not seen_ids.has(population_id):
			errors.append("UNKNOWN_POPULATION_ID")
		if not String(states[raw_id]) in VALID_STATES:
			errors.append("INVALID_POPULATION_STATE")
	for population_id in seen_ids.keys():
		if not states.has(population_id):
			errors.append("MISSING_POPULATION_STATE")

	var raw_tombstones: Variant = data.get("tombstones", [])
	if not (raw_tombstones is Array):
		errors.append("INVALID_TOMBSTONES")
		raw_tombstones = []
	var expected_tombstones := _tombstones_from_states(states)
	var actual_tombstones: Array[String] = []
	for raw_id in raw_tombstones as Array:
		var population_id := String(raw_id)
		if not seen_ids.has(population_id) or String(states.get(population_id, STATE_ALIVE)) == STATE_ALIVE:
			errors.append("INVALID_TOMBSTONE")
		actual_tombstones.append(population_id)
	actual_tombstones.sort()
	if actual_tombstones != expected_tombstones:
		errors.append("INVALID_TOMBSTONES")

	if not data.has("saved_state_hash") or String(data.get("saved_state_hash", "")) != compute_saved_state_hash(data):
		errors.append("CORRUPTED_SAVED_STATE_HASH")
	return {"valid": errors.is_empty(), "errors": errors, "manifest": manifest, "actor_states": states.duplicate(true)}


static func canonicalize_saved_state(data: Dictionary) -> Dictionary:
	var result := data.duplicate(true)
	result["schema_version"] = int(result.get("schema_version", 0))
	result["persistence_key"] = String(result.get("persistence_key", ""))
	result["owner_generated_object_id"] = String(result.get("owner_generated_object_id", ""))
	result["population_manifest_hash"] = String(result.get("population_manifest_hash", ""))
	result["despawn_policy"] = String(result.get("despawn_policy", ""))
	var canonical_records: Array[Dictionary] = []
	for raw_value in result.get("population_records", []) as Array:
		if raw_value is Dictionary:
			var record := _record_from_canonical(raw_value as Dictionary)
			var canonical_record := record.canonical_record()
			# JSON reload parses whole-valued coordinates as integers. Keep the
			# persistence payload scalar-only so its hash is format-invariant.
			canonical_record["position"] = {"x": float(record.position.x), "y": float(record.position.y)}
			canonical_records.append(canonical_record)
	canonical_records.sort_custom(func(a: Dictionary, b: Dictionary): return String(a.get("population_id", "")) < String(b.get("population_id", "")))
	result["population_records"] = canonical_records
	var canonical_states := {}
	var state_keys: Array[String] = []
	for raw_id in (result.get("actor_states", {}) as Dictionary).keys():
		state_keys.append(String(raw_id))
	state_keys.sort()
	for population_id in state_keys:
		canonical_states[population_id] = String((result.get("actor_states", {}) as Dictionary).get(population_id, ""))
	result["actor_states"] = canonical_states
	result["tombstones"] = _tombstones_from_states(canonical_states)
	return result


static func compute_saved_state_hash(data: Dictionary) -> String:
	var hashed := data.duplicate(true)
	hashed.erase("saved_state_hash")
	return GenerationHashes.sha256_of(canonicalize_saved_state(hashed))


static func _tombstones_from_states(states: Dictionary) -> Array[String]:
	var tombstones: Array[String] = []
	for raw_id in states.keys():
		if String(states[raw_id]) != STATE_ALIVE:
			tombstones.append(String(raw_id))
	tombstones.sort()
	return tombstones


static func _record_from_canonical(data: Dictionary) -> EnemyPopulationRecord:
	var record := EnemyPopulationRecord.new()
	record.population_id = String(data.get("population_id", ""))
	record.owner_generated_object_id = String(data.get("owner_generated_object_id", ""))
	record.marker_id = String(data.get("marker_id", ""))
	record.profile_id = String(data.get("profile_id", ""))
	record.enemy_entry_id = String(data.get("enemy_entry_id", ""))
	record.enemy_resource_key = String(data.get("enemy_resource_key", ""))
	record.ordinal = int(data.get("ordinal", 0))
	record.initial_state = String(data.get("initial_state", STATE_ALIVE))
	record.materialization_state = String(data.get("materialization_state", "not_materialized"))
	var raw_position: Variant = data.get("position", Vector2.ZERO)
	if raw_position is Vector2:
		record.position = raw_position
	elif raw_position is Dictionary:
		record.position = Vector2(float(raw_position.get("x", 0.0)), float(raw_position.get("y", 0.0)))
	else:
		record.position = Vector2(NAN, NAN)
	return record
