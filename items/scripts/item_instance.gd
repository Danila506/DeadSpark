extends "res://items/scripts/item_data.gd"
class_name ItemInstance

@export var definition: ItemData
@export var runtime_id: String = ""

var weapon_runtime_state: Dictionary = {}

const DEFINITION_COPY_SKIP: Dictionary = {
	"script": true,
	"resource_local_to_scene": true,
	"resource_name": true,
	"resource_path": true,
	"definition": true,
	"runtime_id": true,
	"weapon_runtime_state": true,
	"runtime_storage_items": true
}


func setup_from_definition(source_definition: ItemData, initial_stack_count: int = -1, initial_endurance: int = -1) -> void:
	if source_definition == null:
		return

	definition = source_definition.get_definition() if source_definition.has_method("get_definition") else source_definition
	_copy_definition_values(definition)
	runtime_id = _generate_runtime_id()
	stack_count = initial_stack_count if initial_stack_count >= 0 else max(definition.stack_count, 1)
	endurance = initial_endurance if initial_endurance >= 0 else clamp(definition.endurance, 0, 100)
	runtime_storage_items = []


func get_definition() -> ItemData:
	return definition if definition != null else self


func get_runtime_id() -> String:
	if runtime_id.is_empty():
		runtime_id = _generate_runtime_id()
	return runtime_id


func is_runtime_instance() -> bool:
	return true


func get_weapon_runtime_state() -> Dictionary:
	if weapon_runtime_state.is_empty():
		weapon_runtime_state = {
			"ammo_in_mag": max(magazine_size, 0),
			"reserve_ammo": max(reserve_ammo, 0),
			"attached_scope": null,
			"attached_attachments": {}
		}
	elif not weapon_runtime_state.has("attached_attachments"):
		weapon_runtime_state["attached_attachments"] = {}
	return weapon_runtime_state


func set_weapon_runtime_state(state: Dictionary) -> void:
	weapon_runtime_state = state.duplicate(true)


func create_runtime_copy() -> ItemData:
	var copy: ItemInstance = ItemInstance.new()
	copy.setup_from_definition(get_definition(), stack_count, endurance)
	copy.runtime_storage_items.clear()
	for stored_item in runtime_storage_items:
		if stored_item == null:
			copy.runtime_storage_items.append(null)
		elif stored_item.has_method("create_runtime_copy"):
			copy.runtime_storage_items.append(stored_item.create_runtime_copy())
		else:
			copy.runtime_storage_items.append(stored_item.duplicate(true))
	copy.weapon_runtime_state = weapon_runtime_state.duplicate(true)
	return copy


func to_save_dict() -> Dictionary:
	var save_data: Dictionary = {
		"runtime_id": get_runtime_id(),
		"definition_path": _get_definition_path(),
		"stack_count": int(stack_count),
		"endurance": int(endurance),
		"runtime_storage_items": [],
		"weapon_runtime_state": _serialize_weapon_runtime_state(get_weapon_runtime_state())
	}

	var serialized_storage: Array = []
	for stored_item in runtime_storage_items:
		if stored_item == null:
			serialized_storage.append(null)
		else:
			serialized_storage.append(_serialize_item_for_save(stored_item))
	save_data["runtime_storage_items"] = serialized_storage
	return save_data


static func from_save_dict(save_data: Dictionary) -> ItemData:
	if save_data.is_empty():
		return null

	var definition_path: String = String(save_data.get("definition_path", ""))
	if definition_path.is_empty():
		return null

	var definition_resource: ItemData = load(definition_path) as ItemData
	if definition_resource == null:
		return null

	var instance: ItemData = definition_resource.create_instance(
		int(save_data.get("stack_count", definition_resource.stack_count)),
		int(save_data.get("endurance", definition_resource.endurance))
	)
	if instance == null:
		return null

	if instance is ItemInstance:
		var typed_instance: ItemInstance = instance as ItemInstance
		typed_instance.runtime_id = String(save_data.get("runtime_id", typed_instance.get_runtime_id()))
		typed_instance.runtime_storage_items.clear()

		var raw_storage: Array = save_data.get("runtime_storage_items", [])
		for raw_item in raw_storage:
			if raw_item == null:
				typed_instance.runtime_storage_items.append(null)
			elif raw_item is Dictionary:
				typed_instance.runtime_storage_items.append(from_save_dict(raw_item as Dictionary))
			else:
				typed_instance.runtime_storage_items.append(null)

		var raw_weapon_state: Dictionary = save_data.get("weapon_runtime_state", {})
		typed_instance.set_weapon_runtime_state(_deserialize_weapon_runtime_state(raw_weapon_state))

	return instance


func _get_definition_path() -> String:
	var base_definition: ItemData = get_definition()
	if base_definition != null and not base_definition.resource_path.is_empty():
		return base_definition.resource_path
	return resource_path


func _serialize_item_for_save(item: ItemData) -> Dictionary:
	if item == null:
		return {}
	if item.has_method("to_save_dict"):
		return item.to_save_dict()
	if item.has_method("create_instance"):
		var instance_item: ItemData = item.create_instance(item.stack_count, item.endurance)
		if instance_item != null and instance_item.has_method("to_save_dict"):
			instance_item.runtime_storage_items = item.runtime_storage_items.duplicate(true)
			return instance_item.to_save_dict()
	return {
		"runtime_id": str(item.get_instance_id()),
		"definition_path": item.resource_path,
		"stack_count": int(item.stack_count),
		"endurance": int(item.endurance),
		"runtime_storage_items": [],
		"weapon_runtime_state": {}
	}


func _serialize_weapon_runtime_state(state: Dictionary) -> Dictionary:
	if state.is_empty():
		return {}

	var attachments_in: Dictionary = state.get("attached_attachments", {})
	var attachments_out: Dictionary = {}
	for slot_key in attachments_in.keys():
		var attachment_item: ItemData = attachments_in.get(slot_key, null)
		attachments_out[str(slot_key)] = _serialize_item_for_save(attachment_item) if attachment_item != null else null

	var scope_item: ItemData = state.get("attached_scope", null)
	return {
		"ammo_in_mag": int(state.get("ammo_in_mag", 0)),
		"reserve_ammo": int(state.get("reserve_ammo", 0)),
		"attached_scope": _serialize_item_for_save(scope_item) if scope_item != null else null,
		"attached_attachments": attachments_out
	}


static func _deserialize_weapon_runtime_state(raw_state: Dictionary) -> Dictionary:
	if raw_state.is_empty():
		return {}

	var attachments_out: Dictionary = {}
	var attachments_in: Dictionary = raw_state.get("attached_attachments", {})
	for slot_key in attachments_in.keys():
		var raw_attachment: Variant = attachments_in.get(slot_key, null)
		if raw_attachment is Dictionary:
			attachments_out[int(slot_key)] = from_save_dict(raw_attachment as Dictionary)
		else:
			attachments_out[int(slot_key)] = null

	var scope_item: ItemData = null
	var raw_scope: Variant = raw_state.get("attached_scope", null)
	if raw_scope is Dictionary:
		scope_item = from_save_dict(raw_scope as Dictionary)

	return {
		"ammo_in_mag": int(raw_state.get("ammo_in_mag", 0)),
		"reserve_ammo": int(raw_state.get("reserve_ammo", 0)),
		"attached_scope": scope_item,
		"attached_attachments": attachments_out
	}


func _copy_definition_values(source_definition: ItemData) -> void:
	for property in source_definition.get_property_list():
		var property_name: String = str(property.get("name", ""))
		if property_name.is_empty() or DEFINITION_COPY_SKIP.has(property_name):
			continue

		var usage: int = int(property.get("usage", 0))
		if (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue

		var value: Variant = source_definition.get(property_name)
		if value is Array:
			value = (value as Array).duplicate(true)
		elif value is Dictionary:
			value = (value as Dictionary).duplicate(true)
		set(property_name, value)


func _generate_runtime_id() -> String:
	return "%d-%d-%d" % [Time.get_ticks_usec(), get_instance_id(), randi()]
