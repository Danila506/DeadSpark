class_name BuildingLootProvider
extends RefCounted

## Shared bridge for building-owned legacy inventories. Buildings remain the
## provider because their wardrobe/bedside/box slots are not child Box nodes.
static func derived_id(building_generated_id: String, local_container_id: String) -> String:
	return "%s/loot/%s" % [building_generated_id, local_container_id]

static func materialize(provider: Node, manifest: LootContainerManifest, slot_count: int, slots: Array) -> Dictionary:
	if manifest == null or manifest.container_generated_id != String(provider.call("get_loot_container_id")):
		return {"valid":false,"errors":["MANIFEST_CONTAINER_MISMATCH"]}
	if manifest.profile_id != String((provider.call("get_loot_profile") as LootProfile).profile_id): return {"valid":false,"errors":["MANIFEST_PROFILE_MISMATCH"]}
	var bindings: Dictionary = provider.call("get_loot_slot_bindings"); var result: Array[ItemData] = []; result.resize(slot_count); var seen := {}
	for record in manifest.slots:
		if seen.has(record.slot_id) or not bindings.has(record.slot_id): return {"valid":false,"errors":["DUPLICATE_OR_UNKNOWN_SLOT"]}
		seen[record.slot_id] = true; var item := load(record.item_resource_key) as ItemData
		if item == null: return {"valid":false,"errors":["MISSING_ITEM_RESOURCE"]}
		var instance := item.create_instance(record.quantity); instance.set_meta("loot_container_id", manifest.container_generated_id); instance.set_meta("loot_slot_id", record.slot_id); result[int(bindings[record.slot_id])] = instance
	slots.clear(); slots.append_array(result)
	return {"valid":true,"errors":[]}


## Rehydrates an already validated persistence snapshot.  Unlike materialize(),
## this intentionally does not compare against the provider's current profile:
## saved deterministic loot wins after a profile or world-seed change.
static func restore_persisted_slots(provider: Node, existing_manifest: LootContainerManifest, manifest: LootContainerManifest, slot_count: int, removed_slot_ids: Array[String], require_empty := false) -> Dictionary:
	if existing_manifest != null and existing_manifest.manifest_hash() != manifest.manifest_hash():
		return {"valid": false, "errors": ["INCOMPATIBLE_MATERIALIZED_STATE"]}
	var result: Array[ItemData] = []
	result.resize(slot_count)
	var bindings: Dictionary = provider.call("get_loot_slot_bindings")
	for record in manifest.slots:
		if not bindings.has(record.slot_id) or record.item_resource_key.is_empty() or not ResourceLoader.exists(record.item_resource_key):
			return {"valid": false, "errors": ["UNKNOWN_SLOT_OR_RESOURCE"]}
		var item := load(record.item_resource_key) as ItemData
		if item == null:
			return {"valid": false, "errors": ["UNKNOWN_SLOT_OR_RESOURCE"]}
		var instance := item.create_instance(record.quantity)
		instance.set_meta("loot_container_id", manifest.container_generated_id)
		instance.set_meta("loot_slot_id", record.slot_id)
		instance.set_meta("loot_manifest_hash", manifest.manifest_hash())
		result[int(bindings[record.slot_id])] = instance
	for slot_id in removed_slot_ids:
		if not bindings.has(slot_id):
			return {"valid": false, "errors": ["UNKNOWN_SLOT"]}
		result[int(bindings[slot_id])] = null
	if require_empty and not result.filter(func(item: ItemData): return item != null).is_empty():
		return {"valid": false, "errors": ["EMPTY_PROFILE_MATERIALIZED_LOOT"]}
	return {"valid": true, "errors": [], "slots": result}
