extends RefCounted
class_name DamageZones

const ZONE_HEAD: StringName = &"head"
const ZONE_BODY: StringName = &"body"
const ZONE_LEGS: StringName = &"legs"

const DIR_UP: StringName = &"up"
const DIR_DOWN: StringName = &"down"
const DIR_LEFT: StringName = &"left"
const DIR_RIGHT: StringName = &"right"

const VALID_ZONES: Array[StringName] = [ZONE_HEAD, ZONE_BODY, ZONE_LEGS]


static func resolve_hit_direction_from_positions(target_position: Vector2, from_position: Vector2) -> StringName:
	return resolve_hit_direction_from_vector(target_position - from_position)


static func resolve_hit_direction_from_vector(direction: Vector2) -> StringName:
	if abs(direction.x) > abs(direction.y):
		return DIR_RIGHT if direction.x >= 0.0 else DIR_LEFT
	return DIR_DOWN if direction.y >= 0.0 else DIR_UP


static func normalize_zone(zone_value: Variant) -> StringName:
	var zone_text: String = String(zone_value).strip_edges().to_lower()
	if zone_text == String(ZONE_HEAD):
		return ZONE_HEAD
	if zone_text == String(ZONE_LEGS):
		return ZONE_LEGS
	return ZONE_BODY


static func resolve_zone_from_area(area: Area2D) -> StringName:
	if area == null:
		return ZONE_BODY

	if area.has_meta(&"damage_zone"):
		return normalize_zone(area.get_meta(&"damage_zone"))

	if area.is_in_group(&"hitbox_head") or area.is_in_group(&"damage_zone_head"):
		return ZONE_HEAD
	if area.is_in_group(&"hitbox_legs") or area.is_in_group(&"damage_zone_legs"):
		return ZONE_LEGS
	if area.is_in_group(&"hitbox_body") or area.is_in_group(&"damage_zone_body"):
		return ZONE_BODY

	var name_lower: String = area.name.to_lower()
	if name_lower.contains("head") or name_lower.contains("голов"):
		return ZONE_HEAD
	if name_lower.contains("legs") or name_lower.contains("leg") or name_lower.contains("ног"):
		return ZONE_LEGS
	return ZONE_BODY


static func resolve_zone_from_hit_context(hit_context: Dictionary) -> StringName:
	if hit_context.has("hitbox_type"):
		return normalize_zone(hit_context.get("hitbox_type"))
	if hit_context.has("damage_zone"):
		return normalize_zone(hit_context.get("damage_zone"))
	return ZONE_BODY
