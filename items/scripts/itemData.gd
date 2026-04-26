@tool
extends Resource
class_name ItemData

enum ItemType {
	AR_Weapon,
	Pistols,
	T_shirts,
	Jacket,
	HeavyArmour,
	Trousers,
	Bag,
	MeleeWeapon,
	Cap,
	Lefthand,
	Food,
	Medical,
	Misc
}

enum StorageCategory {
	NONE,
	WEAPON,
	CLOTHING,
	FOOD,
	MEDICAL,
	MISC
}

enum DamageType {
	GENERIC,
	BULLET,
	BITE,
	MELEE,
	EXPLOSION
}

enum AttachmentSlot {
	SCOPE,
	HANDLE,
	SILENCER
}

@export var storage_category: StorageCategory = StorageCategory.MISC:
	set(value):
		storage_category = value
		notify_property_list_changed()
@export var can_be_stored_in_clothing: bool = true
@export var auto_place_into_equipment_on_pickup: bool = true

@export var item_name: String = ""
@export var world_icon: Texture2D
@export var world_icon_scale: float = 1.0
@export var inventory_icon: Texture2D
@export var inventory_icon_scale: float = 1.0
@export var inventory_icon_rotation_degrees: float = 0.0
@export var stack_count: int = 1
@export var max_stack_size: int = 1
@export var show_stack_count_in_inventory: bool = false
@export var food_restore_amount: float = 0.0
@export var water_restore_amount: float = 0.0
@export var is_ammo_item: bool = false:
	set(value):
		is_ammo_item = value
		notify_property_list_changed()
@export var ammo_type: String = ""
@export var endurance: int = 100
@export_range(0.0, 100.0, 0.01) var weapon_endurance_loss_percent_per_shot: float = 1.0
@export_range(0.0, 100.0, 0.01) var weapon_endurance_loss_percent_per_melee_hit: float = 1.0
@export_range(0.0, 100.0, 0.01) var clothing_endurance_loss_percent_per_damage: float = 1.0
@export_range(0.0, 10.0, 0.01) var clothing_endurance_multiplier_generic: float = 1.0
@export_range(0.0, 10.0, 0.01) var clothing_endurance_multiplier_bullet: float = 1.0
@export_range(0.0, 10.0, 0.01) var clothing_endurance_multiplier_bite: float = 1.0
@export_range(0.0, 10.0, 0.01) var clothing_endurance_multiplier_melee: float = 1.0
@export_range(0.0, 10.0, 0.01) var clothing_endurance_multiplier_explosion: float = 1.0
@export_range(0.0, 60.0, 0.1) var medical_use_time_sec: float = 0.0
@export var medical_health_restore: float = 0.0
@export var medical_radiation_change: float = 0.0
@export var medical_stop_bleeding: bool = false
@export var medical_heal_fracture: bool = false
@export_multiline var description: String = ""
@export var item_type: ItemType = ItemType.Misc:
	set(value):
		item_type = value
		notify_property_list_changed()

# Анимации предмета поверх персонажа
@export var equipped_frames: SpriteFrames
var runtime_storage_items: Array[ItemData] = []


@export var extra_storage_slots: int = 0
@export var can_store_items: bool = false

@export var can_be_held_in_left_hand: bool = false
@export var can_skin_animals: bool = false
@export_range(0.0, 1.0, 0.01) var food_poison_chance: float = 0.0

@export var is_scope_attachment: bool = false:
	set(value):
		is_scope_attachment = value
		notify_property_list_changed()
@export var is_weapon_attachment: bool = false:
	set(value):
		is_weapon_attachment = value
		notify_property_list_changed()
@export var attachment_slot: AttachmentSlot = AttachmentSlot.SCOPE:
	set(value):
		attachment_slot = value
		notify_property_list_changed()
@export var mounted_scope_texture: Texture2D
@export var mounted_handle_texture: Texture2D
@export var mounted_silencer_texture: Texture2D
@export var mounted_scope_scale: Vector2 = Vector2(1.5, 1.5)
@export var mounted_scope_rotation_degrees: float = 0.0
@export var mounted_scope_flip_h: bool = false
@export var mounted_scope_flip_v: bool = false
@export var can_receive_scope_attachment: bool = false:
	set(value):
		can_receive_scope_attachment = value
		notify_property_list_changed()
@export var can_receive_weapon_attachments: bool = false:
	set(value):
		can_receive_weapon_attachments = value
		notify_property_list_changed()
@export var allowed_scope_weapon_types: Array[ItemType] = [ItemType.AR_Weapon]
@export var allowed_scope_weapons: Array[ItemData] = []
@export var allowed_scope_weapon_names: Array[String] = []
@export_range(0.1, 3.0, 0.01) var attachment_aim_settle_time_multiplier: float = 1.0
@export_range(0.1, 3.0, 0.01) var attachment_spread_multiplier: float = 1.0
@export_range(0.1, 3.0, 0.01) var attachment_shot_loudness_multiplier: float = 1.0
@export_range(0.1, 3.0, 0.01) var scope_aim_settle_time_multiplier: float = 1.0
@export_range(0.1, 3.0, 0.01) var scope_spread_multiplier: float = 1.0
@export var scope_rotation_down: float = 0.0
@export var scope_rotation_up: float = 0.0
@export var scope_rotation_left: float = 0.0
@export var scope_rotation_right: float = 0.0
@export var scope_inventory_offset: Vector2 = Vector2.ZERO
@export var handle_inventory_offset: Vector2 = Vector2.ZERO
@export var silencer_inventory_offset: Vector2 = Vector2.ZERO
@export var scope_inventory_rotation_degrees: float = 0.0

# ===== Боевые параметры оружия =====

@export var aim_cursor: Texture2D
@export var aim_cursor_low_spread: Texture2D
@export var aim_cursor_medium_spread: Texture2D
@export var aim_cursor_high_spread: Texture2D

@export var bullet_scene: PackedScene
@export var shot_sound: AudioStream
@export var reload_sound: AudioStream
@export var shot_sound_volume_db: float = 0.0
@export var reload_sound_volume_db: float = 0.0

@export var fire_delay: float = 0.12

@export var bullet_speed: float = 900.0

@export var bullet_max_distance: float = 420.0
@export var bullet_min_distance: float = 160.0

@export var damage: float = 20.0

@export var magazine_size: int = 30
@export var reserve_ammo: int = 90
@export var ammo_inventory_icon: Texture2D
@export var ammo_world_icon: Texture2D
@export var reload_time_sec: float = 2.0

@export var min_spread_degrees: float = 0.0
@export var max_spread_degrees: float = 12.0
@export var spread_increase_per_shot: float = 3.5
@export var spread_recovery_per_sec: float = 7.0
@export var running_spread_multiplier: float = 1.5

@export var pellets_per_shot: int = 1
@export var pellet_spread_degrees: float = 0.0
@export var pellet_distance_jitter_ratio: float = 0.0

@export var aim_distance_min: float = 32.0
@export var aim_distance_max: float = 260.0


func _validate_property(property: Dictionary) -> void:
	var property_name: String = str(property.get("name", ""))
	if property_name.is_empty():
		return

	if property_name in _weapon_property_names() and not _is_weapon_item():
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR
		return

	if property_name in _food_property_names() and not _is_food_item():
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR
		return
	if property_name in _medical_property_names() and not _is_medical_item():
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR
		return

	if property_name in _scope_attachment_property_names() and not _is_scope_attachment_item():
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR
		return
	if property_name in _slot_specific_attachment_icon_property_names() and not _is_property_visible_for_attachment_slot(property_name):
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR
		return
	if property_name in _scope_only_attachment_property_names() and not _is_scope_slot_attachment():
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR
		return

	if property_name in _scope_receiver_property_names() and not _is_scope_receiver_item():
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR
		return

	if property_name in _ammo_property_names() and not _uses_ammo():
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR
		return

	if property_name in _container_property_names() and not _can_be_container_item():
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR
		return

	if property_name in _weapon_durability_property_names() and not _is_weapon_item():
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR
		return

	if property_name in _clothing_durability_property_names() and not _is_clothing_item():
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR
		return

	if property_name == "equipped_frames" and not _uses_equipment_frames():
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR
		return


func _is_weapon_item() -> bool:
	return storage_category == StorageCategory.WEAPON


func _is_food_item() -> bool:
	return storage_category == StorageCategory.FOOD


func _is_medical_item() -> bool:
	return storage_category == StorageCategory.MEDICAL


func _is_clothing_item() -> bool:
	return storage_category == StorageCategory.CLOTHING


func _is_scope_attachment_item() -> bool:
	return is_scope_attachment or is_weapon_attachment


func _is_scope_receiver_item() -> bool:
	return (can_receive_scope_attachment or can_receive_weapon_attachments) and _is_weapon_item()


func _is_scope_slot_attachment() -> bool:
	if is_scope_attachment and not is_weapon_attachment:
		return true
	return is_weapon_attachment and attachment_slot == AttachmentSlot.SCOPE


func _is_handle_slot_attachment() -> bool:
	return is_weapon_attachment and attachment_slot == AttachmentSlot.HANDLE


func _is_silencer_slot_attachment() -> bool:
	return is_weapon_attachment and attachment_slot == AttachmentSlot.SILENCER


func _is_property_visible_for_attachment_slot(property_name: String) -> bool:
	match property_name:
		"mounted_scope_texture":
			return _is_scope_slot_attachment()
		"mounted_handle_texture":
			return _is_handle_slot_attachment()
		"mounted_silencer_texture":
			return _is_silencer_slot_attachment()
		_:
			return true


func get_attachment_mounted_texture() -> Texture2D:
	if _is_handle_slot_attachment() and mounted_handle_texture != null:
		return mounted_handle_texture
	if _is_silencer_slot_attachment() and mounted_silencer_texture != null:
		return mounted_silencer_texture
	if mounted_scope_texture != null:
		return mounted_scope_texture
	return inventory_icon


func _uses_ammo() -> bool:
	return is_ammo_item or _is_weapon_item()


func _can_be_container_item() -> bool:
	return item_type in [
		ItemType.Jacket,
		ItemType.HeavyArmour,
		ItemType.Trousers,
		ItemType.Bag
	]


func _uses_equipment_frames() -> bool:
	return item_type in [
		ItemType.AR_Weapon,
		ItemType.Pistols,
		ItemType.MeleeWeapon,
		ItemType.T_shirts,
		ItemType.Jacket,
		ItemType.HeavyArmour,
		ItemType.Trousers,
		ItemType.Bag,
		ItemType.Cap
	]


func _weapon_property_names() -> Array[String]:
	return [
		"aim_cursor",
		"aim_cursor_low_spread",
		"aim_cursor_medium_spread",
		"aim_cursor_high_spread",
		"bullet_scene",
		"shot_sound",
		"reload_sound",
		"shot_sound_volume_db",
		"reload_sound_volume_db",
		"fire_delay",
		"bullet_speed",
		"bullet_max_distance",
		"bullet_min_distance",
		"damage",
		"magazine_size",
		"reserve_ammo",
		"ammo_inventory_icon",
		"ammo_world_icon",
		"reload_time_sec",
		"min_spread_degrees",
		"max_spread_degrees",
		"spread_increase_per_shot",
		"spread_recovery_per_sec",
		"running_spread_multiplier",
		"pellets_per_shot",
		"pellet_spread_degrees",
		"pellet_distance_jitter_ratio",
		"aim_distance_min",
		"aim_distance_max"
	]


func _food_property_names() -> Array[String]:
	return [
		"food_restore_amount",
		"water_restore_amount",
		"food_poison_chance"
	]


func _medical_property_names() -> Array[String]:
	return [
		"medical_use_time_sec",
		"medical_health_restore",
		"medical_radiation_change",
		"medical_stop_bleeding",
		"medical_heal_fracture"
	]

func _scope_attachment_property_names() -> Array[String]:
	return [
		"attachment_slot",
		"mounted_scope_texture",
		"mounted_handle_texture",
		"mounted_silencer_texture",
		"mounted_scope_scale",
		"mounted_scope_rotation_degrees",
		"mounted_scope_flip_h",
		"mounted_scope_flip_v",
		"allowed_scope_weapon_types",
		"allowed_scope_weapons",
		"allowed_scope_weapon_names",
		"attachment_aim_settle_time_multiplier",
		"attachment_spread_multiplier",
		"attachment_shot_loudness_multiplier",
		"scope_aim_settle_time_multiplier",
		"scope_spread_multiplier"
	]


func _scope_receiver_property_names() -> Array[String]:
	return [
		"scope_rotation_down",
		"scope_rotation_up",
		"scope_rotation_left",
		"scope_rotation_right",
		"scope_inventory_offset",
		"handle_inventory_offset",
		"silencer_inventory_offset",
		"scope_inventory_rotation_degrees"
	]


func _scope_only_attachment_property_names() -> Array[String]:
	return [
		"scope_aim_settle_time_multiplier",
		"scope_spread_multiplier"
	]


func _slot_specific_attachment_icon_property_names() -> Array[String]:
	return [
		"mounted_scope_texture",
		"mounted_handle_texture",
		"mounted_silencer_texture"
	]


func _ammo_property_names() -> Array[String]:
	return [
		"ammo_type"
	]


func _container_property_names() -> Array[String]:
	return [
		"extra_storage_slots",
		"can_store_items"
	]


func _weapon_durability_property_names() -> Array[String]:
	return [
		"weapon_endurance_loss_percent_per_shot",
		"weapon_endurance_loss_percent_per_melee_hit"
	]


func _clothing_durability_property_names() -> Array[String]:
	return [
		"clothing_endurance_loss_percent_per_damage",
		"clothing_endurance_multiplier_generic",
		"clothing_endurance_multiplier_bullet",
		"clothing_endurance_multiplier_bite",
		"clothing_endurance_multiplier_melee",
		"clothing_endurance_multiplier_explosion"
	]
