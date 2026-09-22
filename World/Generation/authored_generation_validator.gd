class_name AuthoredGenerationValidator
extends RefCounted

## Shared validation contract for future POI, Village, and population templates.
## A caller must refuse to generate a template when `valid` is false.

static func validate_structural_markers(markers: Array[Dictionary]) -> Dictionary:
	var errors: Array[String] = []
	var seen_ids := {}
	for marker in markers:
		var stable_id := String(marker.get("stable_id", "")).strip_edges()
		if stable_id.is_empty():
			errors.append("Structural marker has no stable_id")
			continue
		if seen_ids.has(stable_id):
			errors.append("Duplicate structural stable_id: %s" % stable_id)
		else:
			seen_ids[stable_id] = true
		var uses_rotation := bool(marker.get("rotation_used", false))
		var rotation := float(marker.get("local_rotation", 0.0))
		if not uses_rotation and not is_zero_approx(rotation):
			errors.append("Unsupported authored orientation for marker: %s" % stable_id)
	return {"valid": errors.is_empty(), "errors": errors}


static func structural_spatial_fingerprint(markers: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for marker in markers:
		var entry := {
			"stable_id": String(marker.get("stable_id", "")),
			"local_position": marker.get("local_position", Vector2.ZERO),
			"rotation_used": bool(marker.get("rotation_used", false))
		}
		if bool(entry["rotation_used"]):
			entry["local_rotation"] = float(marker.get("local_rotation", 0.0))
		result.append(entry)
	result.sort_custom(func(a: Dictionary, b: Dictionary): return String(a["stable_id"]) < String(b["stable_id"]))
	return result
