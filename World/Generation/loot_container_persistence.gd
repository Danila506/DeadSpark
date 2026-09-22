class_name LootContainerPersistence
extends RefCounted

## Versioned, canonical snapshot format for deterministic loot providers.
const SCHEMA_VERSION := 1
const STATE_UNOPENED := "unopened"
const STATE_OPENED := "opened"
const STATE_PARTIALLY_EMPTIED := "partially_emptied"
const VALID_STATES := [STATE_UNOPENED, STATE_OPENED, STATE_PARTIALLY_EMPTIED]


static func get_persistence_key(container_id: String) -> String:
	return "loot_container/%s" % container_id.strip_edges()


## Compatibility alias for the initial adapter surface.
static func persistence_key(container_id: String) -> String:
	return get_persistence_key(container_id)


static func serialize_provider_state(provider: Node) -> Dictionary:
	var manifest: LootContainerManifest = provider.call("get_existing_loot_manifest")
	var profile: LootProfile = provider.call("get_loot_profile") as LootProfile
	var state := String(provider.call("get_loot_persistence_state")) if provider.has_method("get_loot_persistence_state") else STATE_UNOPENED
	var removed: Array = provider.call("get_removed_loot_slot_ids") if provider.has_method("get_removed_loot_slot_ids") else []
	return canonicalize_saved_state({
		"schema_version": SCHEMA_VERSION,
		"container_id": String(provider.call("get_loot_container_id")),
		"profile_id": manifest.profile_id if manifest != null else (profile.profile_id if profile != null else ""),
		"manifest_hash": manifest.manifest_hash() if manifest != null else "",
		"manifest": manifest.canonical_record() if manifest != null else {},
		"state": state,
		"removed_slot_ids": removed,
	})


static func restore_provider_state(provider: Node, data: Dictionary) -> Dictionary:
	var validation := validate_saved_state(data, provider)
	if not validation.valid:
		return {"valid": false, "errors": validation.errors}
	if not provider.has_method("restore_persisted_loot_state"):
		return {"valid": false, "errors": ["MISSING_PERSISTENCE_RESTORE_API"]}
	return provider.call("restore_persisted_loot_state", validation.manifest, validation.state, validation.removed_slot_ids)


static func mark_opened(provider: Node) -> Dictionary:
	if not provider.has_method("set_loot_persistence_state"):
		return {"valid": false, "errors": ["MISSING_PERSISTENCE_STATE_API"]}
	var state := String(provider.call("get_loot_persistence_state")) if provider.has_method("get_loot_persistence_state") else STATE_UNOPENED
	if state != STATE_PARTIALLY_EMPTIED:
		provider.call("set_loot_persistence_state", STATE_OPENED)
	return {"valid": true, "errors": []}


static func mark_slot_removed(provider: Node, slot_id: String) -> Dictionary:
	if not provider.has_method("record_persisted_loot_slot_removal"):
		return {"valid": false, "errors": ["MISSING_PERSISTENCE_REMOVAL_API"]}
	return provider.call("record_persisted_loot_slot_removal", slot_id)


static func validate_saved_state(data: Dictionary, provider: Node = null) -> Dictionary:
	var errors: Array[String] = []
	if int(data.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("UNSUPPORTED_LOOT_SCHEMA")
	var container_id := String(data.get("container_id", "")).strip_edges()
	if container_id.is_empty():
		errors.append("MISSING_CONTAINER_ID")
	if provider != null and container_id != String(provider.call("get_loot_container_id")):
		errors.append("CONTAINER_ID_MISMATCH")
	var profile_id := String(data.get("profile_id", "")).strip_edges()
	if profile_id.is_empty():
		errors.append("MISSING_PROFILE_ID")
	if not data.get("manifest", {}) is Dictionary:
		errors.append("INVALID_MANIFEST_RECORD")
	var manifest := LootContainerManifest.from_canonical(data.get("manifest", {}) as Dictionary)
	if manifest.container_generated_id != container_id or manifest.profile_id != profile_id:
		errors.append("MANIFEST_ID_OR_PROFILE_MISMATCH")
	if manifest.manifest_hash() != String(data.get("manifest_hash", "")):
		errors.append("CORRUPTED_MANIFEST")
	var bindings: Dictionary = provider.call("get_loot_slot_bindings") if provider != null else {}
	var seen_slots := {}
	for slot in manifest.slots:
		if slot.slot_id.is_empty() or seen_slots.has(slot.slot_id):
			errors.append("DUPLICATE_SAVED_SLOT_ID")
		seen_slots[slot.slot_id] = true
		if provider != null and not bindings.has(slot.slot_id):
			errors.append("UNKNOWN_SLOT")
		if slot.container_generated_id != container_id or slot.profile_id != profile_id or slot.quantity <= 0:
			errors.append("INVALID_MANIFEST_SLOT")
		if slot.item_resource_key.is_empty() or not ResourceLoader.exists(slot.item_resource_key):
			errors.append("UNKNOWN_ITEM_RESOURCE")
		elif load(slot.item_resource_key) as ItemData == null:
			errors.append("UNKNOWN_ITEM_RESOURCE")
	var state := String(data.get("state", ""))
	if not state in VALID_STATES:
		errors.append("INVALID_LOOT_STATE")
	var raw_removed: Variant = data.get("removed_slot_ids", [])
	if not (raw_removed is Array):
		errors.append("INVALID_REMOVED_SLOT_IDS")
	var removed: Array[String] = []
	var seen_removed := {}
	if raw_removed is Array:
		for value in raw_removed:
			if not (value is String) or String(value).is_empty() or seen_removed.has(String(value)) or not seen_slots.has(String(value)):
				errors.append("INVALID_REMOVED_SLOT_IDS")
			else:
				seen_removed[String(value)] = true
				removed.append(String(value))
	if state == STATE_UNOPENED and not removed.is_empty():
		errors.append("INVALID_REMOVED_SLOT_IDS")
	if state == STATE_PARTIALLY_EMPTIED and removed.is_empty():
		errors.append("INVALID_REMOVED_SLOT_IDS")
	return {"valid": errors.is_empty(), "errors": errors, "manifest": manifest, "state": state, "removed_slot_ids": removed}


static func canonicalize_saved_state(data: Dictionary) -> Dictionary:
	var result := data.duplicate(true)
	var manifest := LootContainerManifest.from_canonical(result.get("manifest", {}) as Dictionary)
	result["manifest"] = manifest.canonical_record()
	var removed: Array[String] = []
	for value in result.get("removed_slot_ids", []):
		removed.append(String(value))
	removed.sort()
	result["removed_slot_ids"] = removed
	return result


static func compute_saved_state_hash(data: Dictionary) -> String:
	return GenerationHashes.sha256_of(canonicalize_saved_state(data))


## Compatibility aliases retained while callers migrate to the explicit API.
static func serialize(provider: Node, _state := STATE_UNOPENED, _removed_slot_ids: Array[String] = []) -> Dictionary:
	return serialize_provider_state(provider)

static func validate(data: Dictionary, provider: Node) -> Dictionary:
	return validate_saved_state(data, provider)
