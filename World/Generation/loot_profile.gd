@tool
class_name LootProfile
extends Resource

@export var profile_id := ""
@export var enabled := true
@export var allow_empty := false
## An authored empty profile is valid only when this is true and it has no
## entries or slots. Bunker content uses this rather than a bunker special case.
@export var explicit_empty := false
@export var slot_ids: Array[String] = []
## Optional weight per populated slot count (index 0 means zero items).  An
## empty array preserves the legacy behavior and fills every authored slot.
@export var slot_count_weights: Array[float] = []
@export var entries: Array[LootEntry] = []

func validate() -> Dictionary:
	var errors: Array[String] = []
	var slot_seen := {}
	var entry_seen := {}
	if profile_id.is_empty(): errors.append("MISSING_PROFILE_ID")
	for slot_id in slot_ids:
		if slot_id.is_empty(): errors.append("MISSING_SLOT_ID")
		elif slot_seen.has(slot_id): errors.append("DUPLICATE_SLOT_ID:%s" % slot_id)
		slot_seen[slot_id] = true
	if not slot_count_weights.is_empty():
		if slot_count_weights.size() != slot_ids.size() + 1:
			errors.append("INVALID_SLOT_COUNT_WEIGHTS_SIZE")
		var has_positive_weight := false
		for count in range(slot_count_weights.size()):
			var weight := slot_count_weights[count]
			if weight < 0.0: errors.append("NEGATIVE_SLOT_COUNT_WEIGHT:%d" % count)
			if weight > 0.0: has_positive_weight = true
		if not has_positive_weight: errors.append("SLOT_COUNT_WEIGHTS_REQUIRE_POSITIVE_WEIGHT")
		if not allow_empty and slot_count_weights[0] > 0.0:
			errors.append("ZERO_SLOT_COUNT_REQUIRES_ALLOW_EMPTY")
	for entry in entries:
		if entry == null:
			errors.append("MISSING_ENTRY")
			continue
		if entry_seen.has(entry.entry_id): errors.append("DUPLICATE_ENTRY_ID:%s" % entry.entry_id)
		entry_seen[entry.entry_id] = true
		for error in entry.validate().errors: errors.append("%s:%s" % [String(error), entry.entry_id])
	if explicit_empty:
		if not allow_empty or not entries.is_empty() or not slot_ids.is_empty(): errors.append("INVALID_EXPLICIT_EMPTY_PROFILE")
	elif enabled and not allow_empty and (slot_ids.is_empty() or _valid_enabled_entries().is_empty()):
		errors.append("PROFILE_REQUIRES_SLOTS_AND_ENTRIES")
	return {"valid": errors.is_empty(), "errors": errors}

func _valid_enabled_entries() -> Array[LootEntry]:
	var result: Array[LootEntry] = []
	for entry in entries:
		if entry != null and entry.enabled and entry.weight > 0.0 and entry.item != null: result.append(entry)
	return result

func canonical_record() -> Dictionary:
	var canonical_slots: Array[String] = slot_ids.duplicate(); canonical_slots.sort()
	var canonical_entries: Array[Dictionary] = []
	for entry in entries:
		if entry != null: canonical_entries.append(entry.canonical_record())
	canonical_entries.sort_custom(func(a: Dictionary, b: Dictionary): return String(a.entry_id) < String(b.entry_id))
	var result := {"profile_id": profile_id, "enabled": enabled, "allow_empty": allow_empty, "explicit_empty": explicit_empty, "slot_ids": canonical_slots, "entries": canonical_entries}
	# Keep hashes of legacy profiles stable when they do not opt into variable
	# item counts.
	if not slot_count_weights.is_empty(): result["slot_count_weights"] = slot_count_weights.duplicate()
	return result
