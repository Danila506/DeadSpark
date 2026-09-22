@tool
class_name PoiTemplate
extends Resource

@export var template_id := ""
@export var poi_type := ""
@export var tags: Array[String] = []
@export var scene: PackedScene
@export var authored_bounds := Rect2()
@export var connector_id := ""
@export var connector_local_position := Vector2.ZERO
@export var connector_facing := Vector2.DOWN
@export var allowed_rotations: Array[float] = [0.0]
@export var required_clearance_cells := 1
@export var content_profile_id := ""

func validate() -> Dictionary:
	var errors: Array[String] = []
	if template_id.is_empty() or scene == null: errors.append("INVALID_AUTHORED_DATA")
	if authored_bounds.size.x <= 0.0 or authored_bounds.size.y <= 0.0: errors.append("INVALID_AUTHORED_DATA")
	if connector_id.is_empty() or connector_facing.length_squared() == 0.0: errors.append("INVALID_CONNECTOR")
	for rotation in allowed_rotations:
		if not is_zero_approx(rotation): errors.append("UNSUPPORTED_ORIENTATION")
	return {"valid": errors.is_empty(), "errors": errors}

func compatibility_profile() -> Dictionary:
	return {"id": "poi_template:" + template_id, "type": poi_type, "tags": tags, "bounds": authored_bounds, "connector_id": connector_id, "connector_position": connector_local_position, "connector_facing": connector_facing, "rotations": allowed_rotations, "clearance": required_clearance_cells, "content_profile_id": content_profile_id, "scene_uid": GenerationHashes.resource_uid(scene)}
