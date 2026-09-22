extends Resource
class_name VillageObjectPool

@export var entries: Array[VillageObjectEntry] = []
@export var pool_id := ""


func is_empty_or_invalid() -> bool:
	return _get_total_valid_weight(false) <= 0.0


func pick_scene(rng: RandomNumberGenerator) -> PackedScene:
	if rng == null:
		push_warning("VillageObjectPool: RandomNumberGenerator is null.")
		return null

	var total_weight := _get_total_valid_weight(true)
	if total_weight <= 0.0:
		push_warning("VillageObjectPool: no valid object entries with scene and positive weight.")
		return null

	var roll := rng.randf_range(0.0, total_weight)
	var accumulated_weight := 0.0
	for entry in entries:
		if entry == null:
			continue
		if not entry.is_valid_entry():
			continue
		accumulated_weight += entry.weight
		if roll <= accumulated_weight:
			return entry.scene

	return _get_last_valid_scene()


func _get_total_valid_weight(warn_about_invalid_entries: bool) -> float:
	var total_weight := 0.0
	for index in entries.size():
		var entry := entries[index]
		if entry == null:
			if warn_about_invalid_entries:
				push_warning("VillageObjectPool: entry %d is null." % index)
			continue
		if entry.scene == null or entry.entry_id.is_empty():
			if warn_about_invalid_entries:
				push_warning("VillageObjectPool: entry %d has no PackedScene." % index)
			continue
		if entry.weight <= 0.0 or not entry.enabled:
			if warn_about_invalid_entries:
				push_warning("VillageObjectPool: entry %d has non-positive weight." % index)
			continue
		total_weight += entry.weight
	return total_weight


func _get_last_valid_scene() -> PackedScene:
	for index in range(entries.size() - 1, -1, -1):
		var entry := entries[index]
		if entry != null and entry.scene != null and entry.weight > 0.0:
			return entry.scene
	return null
