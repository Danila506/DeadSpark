class_name LootContainerManifest
extends RefCounted

var container_generated_id := ""
var profile_id := ""
var slots: Array[LootSlotRecord] = []

func canonical_record() -> Dictionary:
	var records: Array[Dictionary] = []
	for slot in slots: records.append(slot.canonical_record())
	records.sort_custom(func(a: Dictionary, b: Dictionary): return String(a.slot_id) < String(b.slot_id))
	return {"container_generated_id": container_generated_id, "profile_id": profile_id, "slots": records}

func manifest_hash() -> String:
	return GenerationHashes.sha256_of(canonical_record())

static func from_canonical(record: Dictionary) -> LootContainerManifest:
	var manifest := LootContainerManifest.new()
	manifest.container_generated_id = String(record.get("container_generated_id", ""))
	manifest.profile_id = String(record.get("profile_id", ""))
	for value in record.get("slots", []):
		var raw := value as Dictionary
		var slot := LootSlotRecord.new()
		slot.container_generated_id = String(raw.get("container_generated_id", "")); slot.profile_id = String(raw.get("profile_id", "")); slot.slot_id = String(raw.get("slot_id", "")); slot.item_resource_key = String(raw.get("item_resource_key", "")); slot.quantity = int(raw.get("quantity", 0)); slot.deterministic_ordinal = int(raw.get("deterministic_ordinal", 0))
		manifest.slots.append(slot)
	return manifest
