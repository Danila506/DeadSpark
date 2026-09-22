@tool
class_name EnvironmentGenerationProfile
extends Resource

@export var profile_id := ""
@export var logical_cell_size := Vector2(60.0, 60.0)
@export_range(0, 16, 1) var clearance_cells := 1
@export var entries: Array[EnvironmentEntry] = []
## Share of available land assigned to forest; tree density is configured separately.
@export var forest_enabled := false
@export_range(0.0, 1.0) var forest_coverage := 0.75
@export_range(2.0, 64.0) var forest_patch_size_cells := 12.0

func validate() -> Dictionary:
	var errors: Array[String] = []
	var ids := {}
	if profile_id.is_empty() or logical_cell_size.x <= 0.0 or logical_cell_size.y <= 0.0: errors.append("INVALID_PROFILE")
	if forest_coverage < 0.0 or forest_coverage > 1.0 or forest_patch_size_cells <= 0.0: errors.append("INVALID_FOREST_PROFILE")
	for entry in entries:
		if entry == null:
			errors.append("MISSING_ENTRY")
			continue
		if ids.has(entry.entry_id): errors.append("DUPLICATE_ENTRY_ID:%s" % entry.entry_id)
		ids[entry.entry_id] = true
		for error in entry.validate().errors: errors.append(String(error) + ":" + entry.entry_id)
	return {"valid": errors.is_empty(), "errors": errors}

func compatibility_profile() -> Dictionary:
	var values: Array[Dictionary] = []
	for entry in entries:
		if entry != null: values.append(entry.fingerprint())
	values.sort_custom(func(a, b): return String(a.entry_id) < String(b.entry_id))
	return {"id": "environment:" + profile_id, "cell_size": logical_cell_size, "clearance": clearance_cells, "entries": values, "forest_enabled": forest_enabled, "forest_coverage": forest_coverage, "forest_patch_size": forest_patch_size_cells}
