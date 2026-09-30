extends RefCounted
class_name BloodRenderOrder

# Ground decals and blood stay above the world floor (also commonly z = -1),
# while every living or dead actor remains on z = 0 or higher.
const BLOOD_EFFECT_MAX_Z_INDEX: int = -1
const ACTOR_MIN_Z_INDEX: int = 0


static func sanitize_blood_z_index(requested_z_index: int) -> int:
	return mini(requested_z_index, BLOOD_EFFECT_MAX_Z_INDEX)


static func sanitize_actor_z_index(requested_z_index: int) -> int:
	return maxi(requested_z_index, ACTOR_MIN_Z_INDEX)
