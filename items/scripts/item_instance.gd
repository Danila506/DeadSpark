extends "res://items/scripts/itemData.gd"
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
