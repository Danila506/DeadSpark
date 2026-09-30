extends Node

signal equipment_changed(slot_type: int, item: ItemData)
signal ammo_state_changed(item: ItemData)
signal item_broken(slot_type: int, item: ItemData)

var equipped: Dictionary = {}
var weapon_runtime_state: Dictionary = {}
var active_weapon_slot: int = ItemData.ItemType.AR_Weapon
var endurance_loss_remainder_by_item_id: Dictionary = {}
var network_inventory_by_peer: Dictionary = {}
var network_authoritative_update_in_progress: bool = false

const ATTACHMENT_SLOT_SCOPE: int = ItemData.AttachmentSlot.SCOPE
const ATTACHMENT_SLOT_HANDLE: int = ItemData.AttachmentSlot.HANDLE
const ATTACHMENT_SLOT_SILENCER: int = ItemData.AttachmentSlot.SILENCER
const ITEM_INSTANCE_SCRIPT = preload("res://items/scripts/item_instance.gd")
const DRAFT_SAVE_SCHEMA_VERSION: int = 1
const NETWORK_INVENTORY_SCHEMA_VERSION: int = 1
const DRAFT_SAVE_PATH: String = "user://dead_spark_inventory_draft.json"
const MAX_CLOTHING_DAMAGE_REDUCTION_RATIO: float = 0.85

@export var hot_reload_attachment_resources_enabled: bool = true
@export_range(0.1, 5.0, 0.1) var hot_reload_attachment_resources_interval_sec: float = 0.35

var _attachment_resource_signature_by_path: Dictionary = {}
var _attachment_hot_reload_timer_sec: float = 0.0


func _ready() -> void:
	set_process(hot_reload_attachment_resources_enabled)


func _process(delta: float) -> void:
	if not hot_reload_attachment_resources_enabled:
		return

	_attachment_hot_reload_timer_sec -= maxf(delta, 0.0)
	if _attachment_hot_reload_timer_sec > 0.0:
		return

	_attachment_hot_reload_timer_sec = maxf(hot_reload_attachment_resources_interval_sec, 0.1)
	_hot_reload_changed_attachment_resources()


func get_equipped(slot_type: int) -> ItemData:
	if equipped.has(slot_type):
		return equipped[slot_type]
	return null


func set_equipped(slot_type: int, item: ItemData) -> void:
	equipped[slot_type] = item
	if _is_switchable_weapon_slot(slot_type) and item != null:
		active_weapon_slot = slot_type
	_sync_active_weapon_slot(slot_type)
	equipment_changed.emit(slot_type, item)


func equip_charged_thermal_vision_if_cap_empty(
	provider_definition: ItemData,
	battery_definition: ItemData
) -> bool:
	if get_equipped(ItemData.ItemType.Cap) != null:
		return false
	if (
		provider_definition == null
		or not provider_definition.enables_thermal_vision
		or not provider_definition.accepts_thermal_battery
		or battery_definition == null
		or not battery_definition.is_battery_item
	):
		return false
	var provider: ItemData = provider_definition.create_instance(1, provider_definition.endurance)
	var battery: ItemData = battery_definition.create_instance(1, battery_definition.endurance)
	if provider == null or battery == null:
		return false
	provider.runtime_storage_items.resize(maxi(provider.runtime_storage_items.size(), 1))
	battery.battery_max_charge_seconds = maxf(
		battery.battery_max_charge_seconds,
		battery_definition.battery_max_charge_seconds
	)
	battery.battery_charge_seconds = battery.battery_max_charge_seconds
	provider.runtime_storage_items[0] = battery
	set_equipped(ItemData.ItemType.Cap, provider)
	return true


func apply_endurance_percent_loss_to_equipped(slot_type: int, percent_loss: float) -> bool:
	var item: ItemData = get_equipped(slot_type)
	if item == null:
		return false

	var consumed: bool = _consume_item_endurance_percent(item, percent_loss)
	if not consumed:
		return false

	if item.endurance > 0:
		equipment_changed.emit(slot_type, item)
		return false

	set_equipped(slot_type, null)
	item_broken.emit(slot_type, item)
	endurance_loss_remainder_by_item_id.erase(_get_runtime_item_key(item))
	return true


func apply_damage_to_equipped_clothing(damage_amount: float, damage_type: int = ItemData.DamageType.GENERIC) -> void:
	var safe_damage_amount: float = max(damage_amount, 0.0)
	if safe_damage_amount <= 0.0:
		return

	for slot_type in _get_clothing_slot_types():
		var clothing_item: ItemData = get_equipped(slot_type)
		if clothing_item == null:
			continue
		if clothing_item.storage_category != ItemData.StorageCategory.CLOTHING:
			continue

		var multiplier: float = _get_clothing_damage_multiplier(clothing_item, damage_type)
		var percent_loss: float = safe_damage_amount * max(clothing_item.clothing_endurance_loss_percent_per_damage, 0.0) * max(multiplier, 0.0)
		if not _consume_item_endurance_percent(clothing_item, percent_loss):
			continue

		if clothing_item.endurance > 0:
			equipment_changed.emit(slot_type, clothing_item)
			continue

		set_equipped(slot_type, null)
		item_broken.emit(slot_type, clothing_item)
		endurance_loss_remainder_by_item_id.erase(_get_runtime_item_key(clothing_item))


func apply_endurance_percent_loss_to_equipped_clothing(percent_loss: float) -> bool:
	var safe_percent_loss := maxf(percent_loss, 0.0)
	if safe_percent_loss <= 0.0:
		return false
	var changed := false
	for slot_type in _get_clothing_slot_types():
		var clothing_item: ItemData = get_equipped(slot_type)
		if not _is_valid_equipped_clothing(clothing_item):
			continue
		if not _consume_item_endurance_percent(clothing_item, safe_percent_loss):
			continue
		changed = true
		if clothing_item.endurance > 0:
			equipment_changed.emit(slot_type, clothing_item)
			continue
		set_equipped(slot_type, null)
		item_broken.emit(slot_type, clothing_item)
		endurance_loss_remainder_by_item_id.erase(_get_runtime_item_key(clothing_item))
	return changed


func get_equipped_clothing_warmth() -> float:
	var total_warmth: float = 0.0
	for slot_type in _get_clothing_slot_types():
		var clothing_item: ItemData = get_equipped(slot_type)
		if not _is_valid_equipped_clothing(clothing_item):
			continue
		total_warmth += max(clothing_item.clothing_warmth, 0.0) * _get_clothing_endurance_ratio(clothing_item)
	return total_warmth


func get_equipped_clothing_armor(damage_type: int = ItemData.DamageType.GENERIC) -> float:
	var total_armor: float = 0.0
	for slot_type in _get_clothing_slot_types():
		var clothing_item: ItemData = get_equipped(slot_type)
		if not _is_valid_equipped_clothing(clothing_item):
			continue

		total_armor += max(clothing_item.clothing_armor, 0.0) * _get_clothing_endurance_ratio(clothing_item)
	return maxf(total_armor, 0.0)


func get_damage_after_equipped_clothing_armor(damage_amount: float, damage_type: int = ItemData.DamageType.GENERIC) -> float:
	var safe_damage_amount: float = max(damage_amount, 0.0)
	if safe_damage_amount <= 0.0:
		return 0.0

	var armor: float = get_equipped_clothing_armor(damage_type)
	return _get_damage_after_clothing_armor(safe_damage_amount, armor)


func get_weapon_runtime_state(item: ItemData) -> Dictionary:
	if item == null:
		return Dictionary()

	if item.has_method("get_weapon_runtime_state"):
		return item.get_weapon_runtime_state()

	var item_key: Variant = _get_runtime_item_key(item)
	if not weapon_runtime_state.has(item_key):
		weapon_runtime_state[item_key] = {
			"ammo_in_mag": max(item.magazine_size, 0),
			"reserve_ammo": max(item.reserve_ammo, 0),
			"attached_scope": null,
			"attached_attachments": {}
		}
	else:
		var existing_state: Dictionary = weapon_runtime_state[item_key]
		if not existing_state.has("attached_attachments"):
			existing_state["attached_attachments"] = {}
		if existing_state.has("attached_scope") and existing_state["attached_scope"] != null:
			var attachments: Dictionary = existing_state.get("attached_attachments", {})
			attachments[ATTACHMENT_SLOT_SCOPE] = existing_state["attached_scope"]
			existing_state["attached_attachments"] = attachments
		weapon_runtime_state[item_key] = existing_state

	return weapon_runtime_state[item_key]


func get_ammo_in_mag(item: ItemData) -> int:
	var state: Dictionary = get_weapon_runtime_state(item)
	return int(state.get("ammo_in_mag", 0))


func get_reserve_ammo(item: ItemData) -> int:
	var state: Dictionary = get_weapon_runtime_state(item)
	return int(state.get("reserve_ammo", 0))


func set_ammo_state(item: ItemData, ammo_in_mag: int, reserve_ammo: int) -> void:
	if item == null:
		return

	var clamped_magazine: int = int(clamp(ammo_in_mag, 0, max(item.magazine_size, 0)))
	var clamped_reserve: int = int(clamp(reserve_ammo, 0, max(item.reserve_ammo, 0)))
	var current_state: Dictionary = get_weapon_runtime_state(item)
	var next_state: Dictionary = {
		"ammo_in_mag": clamped_magazine,
		"reserve_ammo": clamped_reserve,
		"attached_scope": current_state.get("attached_scope", null),
		"attached_attachments": current_state.get("attached_attachments", {}).duplicate(true)
	}
	if item.has_method("set_weapon_runtime_state"):
		item.set_weapon_runtime_state(next_state)
	else:
		weapon_runtime_state[_get_runtime_item_key(item)] = next_state
	ammo_state_changed.emit(item)


func reset_state() -> void:
	equipped.clear()
	weapon_runtime_state.clear()
	active_weapon_slot = ItemData.ItemType.AR_Weapon
	endurance_loss_remainder_by_item_id.clear()
	network_inventory_by_peer.clear()


func get_network_inventory_snapshot() -> Dictionary:
	var snapshot: Dictionary = get_save_data()
	snapshot["schema_version"] = NETWORK_INVENTORY_SCHEMA_VERSION
	return snapshot


func apply_network_peer_inventory_snapshot(peer_id: int, snapshot: Dictionary) -> bool:
	if peer_id <= 1:
		return false
	if int(snapshot.get("schema_version", 0)) != NETWORK_INVENTORY_SCHEMA_VERSION:
		return false
	var raw_equipped: Variant = snapshot.get("equipped", {})
	if not (raw_equipped is Dictionary):
		return false
	var equipped_payload := raw_equipped as Dictionary
	if equipped_payload.size() > ItemData.ItemType.size():
		return false

	var peer_equipped: Dictionary = {}
	for raw_slot_key in equipped_payload.keys():
		var slot_text: String = String(raw_slot_key)
		if not slot_text.is_valid_int():
			return false
		var slot_type: int = slot_text.to_int()
		if slot_type < 0 or slot_type >= ItemData.ItemType.size():
			return false
		var raw_item: Variant = equipped_payload.get(raw_slot_key, null)
		if raw_item == null:
			peer_equipped[slot_type] = null
			continue
		var restored_item: ItemData = _deserialize_item_from_save(raw_item)
		if restored_item == null:
			return false
		peer_equipped[slot_type] = restored_item

	var requested_active_slot: int = int(snapshot.get("active_weapon_slot", ItemData.ItemType.AR_Weapon))
	var peer_active_slot: int = _resolve_active_weapon_slot(peer_equipped, requested_active_slot)
	network_inventory_by_peer[peer_id] = {
		"active_weapon_slot": peer_active_slot,
		"equipped": peer_equipped
	}
	return true


func reconcile_network_peer_inventory_layout(peer_id: int, snapshot: Dictionary) -> bool:
	if not network_inventory_by_peer.has(peer_id):
		return apply_network_peer_inventory_snapshot(peer_id, snapshot)
	var previous_state: Dictionary = network_inventory_by_peer.get(peer_id, {})
	var previous_fingerprints: Array[String] = _get_network_inventory_item_fingerprints(previous_state)
	if not apply_network_peer_inventory_snapshot(peer_id, snapshot):
		return false
	var candidate_state: Dictionary = network_inventory_by_peer.get(peer_id, {})
	if not _is_network_inventory_layout_valid(candidate_state) or _get_network_inventory_item_fingerprints(candidate_state) != previous_fingerprints:
		network_inventory_by_peer[peer_id] = previous_state
		return false
	return true


func _get_network_inventory_item_fingerprints(state: Dictionary) -> Array[String]:
	var fingerprints: Array[String] = []
	var peer_equipped: Dictionary = state.get("equipped", {})
	for raw_item in peer_equipped.values():
		_collect_network_item_fingerprints(raw_item as ItemData, fingerprints)
	fingerprints.sort()
	return fingerprints


func _collect_network_item_fingerprints(item: ItemData, fingerprints: Array[String]) -> void:
	if item == null:
		return
	var serialized: Dictionary = _serialize_item_for_save(item)
	serialized["runtime_storage_items"] = []
	fingerprints.append(JSON.stringify(serialized, "", true))
	for stored_item in item.runtime_storage_items:
		_collect_network_item_fingerprints(stored_item, fingerprints)


func _is_network_inventory_layout_valid(state: Dictionary) -> bool:
	var peer_equipped: Dictionary = state.get("equipped", {})
	for raw_slot in peer_equipped.keys():
		var slot_type: int = int(raw_slot)
		var item: ItemData = peer_equipped.get(raw_slot, null) as ItemData
		if item == null:
			continue
		if slot_type == ItemData.ItemType.Lefthand:
			if not item.can_be_held_in_left_hand and item.item_type != ItemData.ItemType.Lefthand:
				return false
		elif item.item_type != slot_type:
			return false
		if item.runtime_storage_items.size() > maxi(item.extra_storage_slots, 0):
			return false
		for stored_item in item.runtime_storage_items:
			if stored_item == null:
				continue
			if not item.can_store_items or not stored_item.can_be_stored_in_clothing:
				return false
			if stored_item.storage_category not in [ItemData.StorageCategory.FOOD, ItemData.StorageCategory.MEDICAL, ItemData.StorageCategory.MISC]:
				return false
	return true


func clear_network_peer_inventory(peer_id: int) -> void:
	network_inventory_by_peer.erase(peer_id)


func drain_network_peer_inventory_for_death(peer_id: int) -> Array[ItemData]:
	if peer_id <= 1 or not network_inventory_by_peer.has(peer_id):
		return []
	var state: Dictionary = network_inventory_by_peer.get(peer_id, {})
	var peer_equipped: Dictionary = state.get("equipped", {})
	var drops: Array[ItemData] = []
	var seen: Dictionary = {}
	var slot_types: Array = peer_equipped.keys()
	slot_types.sort()
	for raw_slot_type in slot_types:
		_detach_item_tree_for_death_drop(peer_equipped.get(raw_slot_type, null) as ItemData, drops, seen)
	network_inventory_by_peer.erase(peer_id)
	return drops


func drain_local_inventory_for_death() -> Array[ItemData]:
	var drops: Array[ItemData] = []
	var seen: Dictionary = {}
	var slot_types: Array = equipped.keys()
	slot_types.sort()
	for raw_slot_type in slot_types:
		_detach_item_tree_for_death_drop(equipped.get(raw_slot_type, null) as ItemData, drops, seen)
	equipped.clear()
	weapon_runtime_state.clear()
	active_weapon_slot = ItemData.ItemType.AR_Weapon
	endurance_loss_remainder_by_item_id.clear()
	for slot_type in range(ItemData.ItemType.size()):
		equipment_changed.emit(slot_type, null)
	return drops


func _detach_item_tree_for_death_drop(
	item: ItemData,
	drops: Array[ItemData],
	seen: Dictionary
) -> void:
	if item == null:
		return
	var instance_id: int = item.get_instance_id()
	if seen.has(instance_id):
		return
	seen[instance_id] = true
	var stored_items: Array[ItemData] = item.runtime_storage_items.duplicate()
	for index in range(item.runtime_storage_items.size()):
		item.runtime_storage_items[index] = null
	drops.append(item)
	for stored_item in stored_items:
		_detach_item_tree_for_death_drop(stored_item, drops, seen)


func has_network_peer_inventory(peer_id: int) -> bool:
	return network_inventory_by_peer.has(peer_id)


func get_network_peer_equipped(peer_id: int, slot_type: int) -> ItemData:
	var state: Dictionary = network_inventory_by_peer.get(peer_id, {})
	var peer_equipped: Dictionary = state.get("equipped", {})
	return peer_equipped.get(slot_type, null) as ItemData


func get_network_peer_equipped_clothing_armor(peer_id: int, damage_type: int = ItemData.DamageType.GENERIC) -> float:
	var total_armor: float = 0.0
	for slot_type in _get_clothing_slot_types():
		var clothing_item: ItemData = get_network_peer_equipped(peer_id, slot_type)
		if not _is_valid_equipped_clothing(clothing_item):
			continue
		total_armor += max(clothing_item.clothing_armor, 0.0) * _get_clothing_endurance_ratio(clothing_item)
	return maxf(total_armor, 0.0)


func get_damage_after_network_peer_equipped_clothing_armor(peer_id: int, damage_amount: float, damage_type: int = ItemData.DamageType.GENERIC) -> float:
	var safe_damage_amount: float = maxf(damage_amount, 0.0)
	if safe_damage_amount <= 0.0:
		return 0.0
	return _get_damage_after_clothing_armor(
		safe_damage_amount,
		get_network_peer_equipped_clothing_armor(peer_id, damage_type)
	)


func apply_damage_to_network_peer_equipped_clothing(peer_id: int, damage_amount: float, damage_type: int = ItemData.DamageType.GENERIC) -> bool:
	if not network_inventory_by_peer.has(peer_id):
		return false
	var safe_damage_amount: float = maxf(damage_amount, 0.0)
	if safe_damage_amount <= 0.0:
		return false
	var changed: bool = false
	for slot_type in _get_clothing_slot_types():
		var clothing_item: ItemData = get_network_peer_equipped(peer_id, slot_type)
		if not _is_valid_equipped_clothing(clothing_item):
			continue
		var multiplier: float = _get_clothing_damage_multiplier(clothing_item, damage_type)
		var percent_loss: float = safe_damage_amount * maxf(clothing_item.clothing_endurance_loss_percent_per_damage, 0.0) * maxf(multiplier, 0.0)
		if not _consume_item_endurance_percent(clothing_item, percent_loss):
			continue
		changed = true
		if clothing_item.endurance <= 0:
			var state: Dictionary = network_inventory_by_peer.get(peer_id, {})
			var peer_equipped: Dictionary = state.get("equipped", {})
			peer_equipped[slot_type] = null
			state["equipped"] = peer_equipped
			state["active_weapon_slot"] = _resolve_active_weapon_slot(peer_equipped, int(state.get("active_weapon_slot", slot_type)))
			network_inventory_by_peer[peer_id] = state
			endurance_loss_remainder_by_item_id.erase(_get_runtime_item_key(clothing_item))
	return changed


func apply_endurance_percent_loss_to_network_peer_equipped_clothing(peer_id: int, percent_loss: float) -> bool:
	if not network_inventory_by_peer.has(peer_id):
		return false
	var safe_percent_loss := maxf(percent_loss, 0.0)
	if safe_percent_loss <= 0.0:
		return false
	var state: Dictionary = network_inventory_by_peer.get(peer_id, {})
	var peer_equipped: Dictionary = state.get("equipped", {})
	var changed := false
	for slot_type in _get_clothing_slot_types():
		var clothing_item := peer_equipped.get(slot_type, null) as ItemData
		if not _is_valid_equipped_clothing(clothing_item):
			continue
		if not _consume_item_endurance_percent(clothing_item, safe_percent_loss):
			continue
		changed = true
		if clothing_item.endurance <= 0:
			peer_equipped[slot_type] = null
			endurance_loss_remainder_by_item_id.erase(_get_runtime_item_key(clothing_item))
	if changed:
		state["equipped"] = peer_equipped
		state["active_weapon_slot"] = _resolve_active_weapon_slot(peer_equipped, int(state.get("active_weapon_slot", ItemData.ItemType.AR_Weapon)))
		network_inventory_by_peer[peer_id] = state
	return changed


func get_network_peer_active_weapon_slot(peer_id: int) -> int:
	var state: Dictionary = network_inventory_by_peer.get(peer_id, {})
	return int(state.get("active_weapon_slot", ItemData.ItemType.AR_Weapon))


func set_network_peer_active_weapon_slot(peer_id: int, slot_type: int) -> bool:
	if not _is_switchable_weapon_slot(slot_type) or get_network_peer_equipped(peer_id, slot_type) == null:
		return false
	var state: Dictionary = network_inventory_by_peer.get(peer_id, {})
	if state.is_empty():
		return false
	state["active_weapon_slot"] = slot_type
	network_inventory_by_peer[peer_id] = state
	return true


func set_network_peer_equipped(peer_id: int, slot_type: int, item: ItemData) -> bool:
	return _set_network_peer_item_at(peer_id, 1, slot_type, -1, item)


func get_network_peer_inventory_snapshot(peer_id: int) -> Dictionary:
	if not network_inventory_by_peer.has(peer_id):
		return {}
	var state: Dictionary = network_inventory_by_peer.get(peer_id, {})
	var peer_equipped: Dictionary = state.get("equipped", {})
	var equipped_payload: Dictionary = {}
	for slot_type in peer_equipped.keys():
		var item: ItemData = peer_equipped.get(slot_type, null) as ItemData
		equipped_payload[str(int(slot_type))] = _serialize_item_for_save(item) if item != null else null
	return {
		"schema_version": NETWORK_INVENTORY_SCHEMA_VERSION,
		"active_weapon_slot": int(state.get("active_weapon_slot", ItemData.ItemType.AR_Weapon)),
		"equipped": equipped_payload
	}


func commit_network_peer_inventory_transfer(peer_id: int, snapshot: Dictionary, world_items_before: Array, world_items_after: Array) -> bool:
	if not network_inventory_by_peer.has(peer_id):
		return false
	var previous_state: Dictionary = network_inventory_by_peer.get(peer_id, {})
	var fingerprints_before: Array[String] = _get_network_inventory_item_fingerprints(previous_state)
	_collect_network_array_item_fingerprints(world_items_before, fingerprints_before)
	fingerprints_before.sort()
	if not apply_network_peer_inventory_snapshot(peer_id, snapshot):
		return false
	var candidate_state: Dictionary = network_inventory_by_peer.get(peer_id, {})
	var fingerprints_after: Array[String] = _get_network_inventory_item_fingerprints(candidate_state)
	_collect_network_array_item_fingerprints(world_items_after, fingerprints_after)
	fingerprints_after.sort()
	if not _is_network_inventory_layout_valid(candidate_state) or fingerprints_after != fingerprints_before:
		network_inventory_by_peer[peer_id] = previous_state
		return false
	return true


func _collect_network_array_item_fingerprints(items: Array, fingerprints: Array[String]) -> void:
	for raw_item in items:
		_collect_network_item_fingerprints(raw_item as ItemData, fingerprints)


func apply_network_authoritative_local_snapshot(snapshot: Dictionary) -> bool:
	if int(snapshot.get("schema_version", 0)) != NETWORK_INVENTORY_SCHEMA_VERSION:
		return false
	network_authoritative_update_in_progress = true
	var result: int = apply_save_data(snapshot)
	network_authoritative_update_in_progress = false
	return result == OK


func get_network_peer_item_at(peer_id: int, slot_mode: int, slot_type: int, container_index: int) -> ItemData:
	# InventorySlot.SlotMode values are kept out of this autoload's dependencies.
	if slot_mode == 1:
		return get_network_peer_equipped(peer_id, slot_type)
	if slot_mode != 2 or container_index < 0:
		return null
	var provider_slot: int = int(container_index / 100.0)
	var provider_index: int = container_index % 100
	if provider_slot < 0 or provider_slot >= ItemData.ItemType.size():
		return null
	var provider: ItemData = get_network_peer_equipped(peer_id, provider_slot)
	if provider == null or not provider.can_store_items:
		return null
	if provider_index < 0 or provider_index >= provider.runtime_storage_items.size():
		return null
	return provider.runtime_storage_items[provider_index]


func take_network_peer_item_at(peer_id: int, slot_mode: int, slot_type: int, container_index: int) -> ItemData:
	var item: ItemData = get_network_peer_item_at(peer_id, slot_mode, slot_type, container_index)
	if item == null:
		return null
	if not _set_network_peer_item_at(peer_id, slot_mode, slot_type, container_index, null):
		return null
	return item


func set_network_peer_item_at(peer_id: int, slot_mode: int, slot_type: int, container_index: int, item: ItemData) -> bool:
	return _set_network_peer_item_at(peer_id, slot_mode, slot_type, container_index, item)


func consume_network_peer_item_at(peer_id: int, slot_mode: int, slot_type: int, container_index: int, expected_category: int) -> ItemData:
	var item: ItemData = get_network_peer_item_at(peer_id, slot_mode, slot_type, container_index)
	if item == null or item.storage_category != expected_category or item.stack_count <= 0:
		return null
	var consumed: ItemData = item.create_runtime_copy() if item.has_method("create_runtime_copy") else item.duplicate(true)
	consumed.stack_count = 1
	item.stack_count -= 1
	if item.stack_count <= 0:
		_set_network_peer_item_at(peer_id, slot_mode, slot_type, container_index, null)
	return consumed


func equip_network_peer_ammo_at(peer_id: int, slot_mode: int, slot_type: int, container_index: int) -> bool:
	var ammo_item: ItemData = get_network_peer_item_at(peer_id, slot_mode, slot_type, container_index)
	if ammo_item == null or not ammo_item.is_ammo_item or ammo_item.stack_count <= 0:
		return false
	var target_weapon: ItemData = null
	for weapon_slot in _get_switchable_weapon_slots():
		var candidate: ItemData = get_network_peer_equipped(peer_id, weapon_slot)
		if candidate != null and candidate.ammo_type == ammo_item.ammo_type:
			target_weapon = candidate
			break
	if target_weapon == null:
		return false
	var current_reserve: int = get_reserve_ammo(target_weapon)
	var added: int = mini(ammo_item.stack_count, maxi(target_weapon.reserve_ammo - current_reserve, 0))
	if added <= 0:
		return false
	set_network_peer_ammo_state(peer_id, get_network_peer_active_weapon_slot(peer_id) if get_network_peer_equipped(peer_id, get_network_peer_active_weapon_slot(peer_id)) == target_weapon else target_weapon.item_type, get_ammo_in_mag(target_weapon), current_reserve + added)
	ammo_item.stack_count -= added
	if ammo_item.stack_count <= 0:
		_set_network_peer_item_at(peer_id, slot_mode, slot_type, container_index, null)
	return true


func can_network_peer_craft(peer_id: int, ingredients: Array, result_item: ItemData, result_count: int) -> bool:
	if not network_inventory_by_peer.has(peer_id) or result_item == null or result_count <= 0:
		return false
	var requirements: Dictionary = _build_network_craft_requirements(ingredients)
	if requirements.is_empty():
		return false
	for item_key in requirements.keys():
		if _count_network_peer_item(peer_id, String(item_key)) < int(requirements[item_key]):
			return false
	return _get_network_peer_storage_capacity(peer_id, result_item) >= result_count


func craft_network_peer_item(peer_id: int, ingredients: Array, result_item: ItemData, result_count: int) -> bool:
	if not can_network_peer_craft(peer_id, ingredients, result_item, result_count):
		return false
	var requirements: Dictionary = _build_network_craft_requirements(ingredients)
	for item_key in requirements.keys():
		if _consume_network_peer_item_by_key(peer_id, String(item_key), int(requirements[item_key])) != int(requirements[item_key]):
			return false
	var crafted: ItemData = result_item.create_instance(result_count, result_item.endurance) if result_item.has_method("create_instance") else result_item.duplicate(true)
	crafted.stack_count = result_count
	return _store_network_peer_item(peer_id, crafted)


func _set_network_peer_item_at(peer_id: int, slot_mode: int, slot_type: int, container_index: int, item: ItemData) -> bool:
	var state: Dictionary = network_inventory_by_peer.get(peer_id, {})
	var peer_equipped: Dictionary = state.get("equipped", {})
	if slot_mode == 1:
		if slot_type < 0 or slot_type >= ItemData.ItemType.size():
			return false
		peer_equipped[slot_type] = item
		state["equipped"] = peer_equipped
		state["active_weapon_slot"] = _resolve_active_weapon_slot(peer_equipped, int(state.get("active_weapon_slot", slot_type)))
		network_inventory_by_peer[peer_id] = state
		return true
	if slot_mode != 2 or container_index < 0:
		return false
	var provider_slot: int = int(container_index / 100.0)
	var provider_index: int = container_index % 100
	var provider: ItemData = peer_equipped.get(provider_slot, null) as ItemData
	if provider == null or not provider.can_store_items or provider_index < 0 or provider_index >= provider.runtime_storage_items.size():
		return false
	provider.runtime_storage_items[provider_index] = item
	return true


func _build_network_craft_requirements(ingredients: Array) -> Dictionary:
	var requirements: Dictionary = {}
	for raw_ingredient in ingredients:
		if not (raw_ingredient is Dictionary):
			return {}
		var ingredient: Dictionary = raw_ingredient
		var item: ItemData = ingredient.get("item", null) as ItemData
		var count: int = int(ingredient.get("count", 0))
		var item_key: String = _network_item_key(item)
		if item_key.is_empty() or count <= 0:
			return {}
		requirements[item_key] = int(requirements.get(item_key, 0)) + count
	return requirements


func _network_item_key(item: ItemData) -> String:
	if item == null:
		return ""
	var definition: ItemData = item.get_definition() if item.has_method("get_definition") else item
	if definition != null and not definition.resource_path.is_empty():
		return definition.resource_path
	return item.item_name.strip_edges().to_lower()


func _get_network_peer_owned_items(peer_id: int) -> Array[ItemData]:
	var result: Array[ItemData] = []
	var state: Dictionary = network_inventory_by_peer.get(peer_id, {})
	var peer_equipped: Dictionary = state.get("equipped", {})
	for raw_item in peer_equipped.values():
		var item: ItemData = raw_item as ItemData
		if item == null:
			continue
		result.append(item)
		if item.can_store_items:
			for stored_item in item.runtime_storage_items:
				if stored_item != null:
					result.append(stored_item)
	return result


func _count_network_peer_item(peer_id: int, item_key: String) -> int:
	var total: int = 0
	for item in _get_network_peer_owned_items(peer_id):
		if _network_item_key(item) == item_key:
			total += maxi(item.stack_count, 1)
	return total


func _consume_network_peer_item_by_key(peer_id: int, item_key: String, amount: int) -> int:
	var remaining: int = amount
	var state: Dictionary = network_inventory_by_peer.get(peer_id, {})
	var peer_equipped: Dictionary = state.get("equipped", {})
	for slot_type in peer_equipped.keys():
		if remaining <= 0:
			break
		var item: ItemData = peer_equipped.get(slot_type, null) as ItemData
		if item == null:
			continue
		if _network_item_key(item) == item_key:
			var taken: int = mini(maxi(item.stack_count, 1), remaining)
			item.stack_count -= taken
			remaining -= taken
			if item.stack_count <= 0:
				peer_equipped[slot_type] = null
				continue
		if not item.can_store_items:
			continue
		for index in range(item.runtime_storage_items.size()):
			if remaining <= 0:
				break
			var stored: ItemData = item.runtime_storage_items[index]
			if stored == null or _network_item_key(stored) != item_key:
				continue
			var stored_taken: int = mini(maxi(stored.stack_count, 1), remaining)
			stored.stack_count -= stored_taken
			remaining -= stored_taken
			if stored.stack_count <= 0:
				item.runtime_storage_items[index] = null
	state["equipped"] = peer_equipped
	state["active_weapon_slot"] = _resolve_active_weapon_slot(peer_equipped, int(state.get("active_weapon_slot", ItemData.ItemType.AR_Weapon)))
	network_inventory_by_peer[peer_id] = state
	return amount - remaining


func _get_network_peer_storage_capacity(peer_id: int, result_item: ItemData) -> int:
	var capacity: int = 0
	for owned in _get_network_peer_owned_items(peer_id):
		if _network_item_key(owned) == _network_item_key(result_item) and owned.max_stack_size > 1:
			capacity += maxi(owned.max_stack_size - owned.stack_count, 0)
	if result_item.can_be_stored_in_clothing and result_item.storage_category in [ItemData.StorageCategory.FOOD, ItemData.StorageCategory.MEDICAL, ItemData.StorageCategory.MISC]:
		var state: Dictionary = network_inventory_by_peer.get(peer_id, {})
		var peer_equipped: Dictionary = state.get("equipped", {})
		for provider_slot in [ItemData.ItemType.Jacket, ItemData.ItemType.HeavyArmour, ItemData.ItemType.Trousers, ItemData.ItemType.Bag]:
			var provider: ItemData = peer_equipped.get(provider_slot, null) as ItemData
			if provider == null or not provider.can_store_items:
				continue
			for stored in provider.runtime_storage_items:
				if stored == null:
					capacity += maxi(result_item.max_stack_size, 1)
	if capacity <= 0:
		var peer_equipped: Dictionary = network_inventory_by_peer.get(peer_id, {}).get("equipped", {})
		if peer_equipped.get(result_item.item_type, null) == null:
			capacity = maxi(result_item.max_stack_size, 1)
	return capacity


func _store_network_peer_item(peer_id: int, item: ItemData) -> bool:
	var state: Dictionary = network_inventory_by_peer.get(peer_id, {})
	var peer_equipped: Dictionary = state.get("equipped", {})
	for owned in _get_network_peer_owned_items(peer_id):
		if _network_item_key(owned) != _network_item_key(item) or owned.max_stack_size <= 1:
			continue
		var moved: int = mini(maxi(owned.max_stack_size - owned.stack_count, 0), item.stack_count)
		owned.stack_count += moved
		item.stack_count -= moved
		if item.stack_count <= 0:
			return true
	if item.can_be_stored_in_clothing and item.storage_category in [ItemData.StorageCategory.FOOD, ItemData.StorageCategory.MEDICAL, ItemData.StorageCategory.MISC]:
		for provider_slot in [ItemData.ItemType.Jacket, ItemData.ItemType.HeavyArmour, ItemData.ItemType.Trousers, ItemData.ItemType.Bag]:
			var provider: ItemData = peer_equipped.get(provider_slot, null) as ItemData
			if provider == null or not provider.can_store_items:
				continue
			for index in range(provider.runtime_storage_items.size()):
				if provider.runtime_storage_items[index] == null:
					provider.runtime_storage_items[index] = item
					return true
	if peer_equipped.get(item.item_type, null) == null:
		peer_equipped[item.item_type] = item
		state["equipped"] = peer_equipped
		state["active_weapon_slot"] = _resolve_active_weapon_slot(peer_equipped, int(state.get("active_weapon_slot", item.item_type)))
		network_inventory_by_peer[peer_id] = state
		return true
	return false


func set_network_peer_ammo_state(peer_id: int, slot_type: int, ammo_in_mag: int, reserve_ammo: int) -> void:
	var item: ItemData = get_network_peer_equipped(peer_id, slot_type)
	if item == null:
		return
	var current_state: Dictionary = get_weapon_runtime_state(item)
	var next_state: Dictionary = {
		"ammo_in_mag": clampi(ammo_in_mag, 0, maxi(item.magazine_size, 0)),
		"reserve_ammo": clampi(reserve_ammo, 0, maxi(item.reserve_ammo, 0)),
		"attached_scope": current_state.get("attached_scope", null),
		"attached_attachments": current_state.get("attached_attachments", {}).duplicate(true)
	}
	_set_weapon_runtime_state_for_item(item, next_state)


func apply_endurance_percent_loss_to_network_peer_equipped(peer_id: int, slot_type: int, percent_loss: float) -> bool:
	var item: ItemData = get_network_peer_equipped(peer_id, slot_type)
	if item == null or not _consume_item_endurance_percent(item, percent_loss):
		return false
	if item.endurance > 0:
		return false
	var state: Dictionary = network_inventory_by_peer.get(peer_id, {})
	var peer_equipped: Dictionary = state.get("equipped", {})
	peer_equipped[slot_type] = null
	state["equipped"] = peer_equipped
	state["active_weapon_slot"] = _resolve_active_weapon_slot(peer_equipped, int(state.get("active_weapon_slot", slot_type)))
	network_inventory_by_peer[peer_id] = state
	endurance_loss_remainder_by_item_id.erase(_get_runtime_item_key(item))
	return true


func _resolve_active_weapon_slot(items_by_slot: Dictionary, requested_slot: int) -> int:
	if _is_switchable_weapon_slot(requested_slot) and items_by_slot.get(requested_slot, null) != null:
		return requested_slot
	for slot_type in _get_switchable_weapon_slots():
		if items_by_slot.get(slot_type, null) != null:
			return slot_type
	return ItemData.ItemType.AR_Weapon


func get_save_data() -> Dictionary:
	var save_payload: Dictionary = {
		"schema_version": DRAFT_SAVE_SCHEMA_VERSION,
		"active_weapon_slot": int(active_weapon_slot),
		"equipped": {}
	}

	var equipped_payload: Dictionary = {}
	for slot_type in equipped.keys():
		var item: ItemData = equipped.get(slot_type, null)
		equipped_payload[str(slot_type)] = _serialize_item_for_save(item) if item != null else null
	save_payload["equipped"] = equipped_payload
	return save_payload


func apply_save_data(save_payload: Dictionary) -> int:
	var schema_version: int = int(save_payload.get("schema_version", 0))
	if schema_version != DRAFT_SAVE_SCHEMA_VERSION:
		return ERR_FILE_UNRECOGNIZED

	reset_state()
	var equipped_payload: Dictionary = save_payload.get("equipped", {})
	for slot_key in equipped_payload.keys():
		var slot_type: int = int(slot_key)
		var raw_item: Variant = equipped_payload.get(slot_key, null)
		var restored_item: ItemData = _deserialize_item_from_save(raw_item)
		equipped[slot_type] = restored_item

	var desired_active_slot: int = int(save_payload.get("active_weapon_slot", ItemData.ItemType.AR_Weapon))
	if _is_switchable_weapon_slot(desired_active_slot) and get_equipped(desired_active_slot) != null:
		active_weapon_slot = desired_active_slot
	else:
		_sync_active_weapon_slot(desired_active_slot)

	for slot_type in equipped.keys():
		equipment_changed.emit(int(slot_type), equipped[slot_type])

	return OK


func save_draft(path: String = DRAFT_SAVE_PATH) -> int:
	var save_payload: Dictionary = get_save_data()
	save_payload["saved_at_unix"] = int(Time.get_unix_time_from_system())

	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	file.store_string(JSON.stringify(save_payload, "\t"))
	file.flush()
	return OK


func load_draft(path: String = DRAFT_SAVE_PATH) -> int:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()

	var raw_json: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(raw_json)
	if not (parsed is Dictionary):
		return ERR_PARSE_ERROR

	return apply_save_data(parsed as Dictionary)


func copy_runtime_state(from_item: ItemData, to_item: ItemData) -> void:
	if from_item == null or to_item == null:
		return

	var source_state: Dictionary = get_weapon_runtime_state(from_item)
	if source_state.is_empty():
		return

	var runtime_copy: Dictionary = source_state.duplicate(true)
	var attached_scope: ItemData = runtime_copy.get("attached_scope", null)
	if attached_scope != null:
		runtime_copy["attached_scope"] = _clone_runtime_item(attached_scope)
	var attached_attachments: Dictionary = runtime_copy.get("attached_attachments", {})
	if not attached_attachments.is_empty():
		var copied_attachments: Dictionary = {}
		for slot_key in attached_attachments.keys():
			var attachment_item: ItemData = attached_attachments.get(slot_key, null)
			copied_attachments[slot_key] = _clone_runtime_item(attachment_item)
		runtime_copy["attached_attachments"] = copied_attachments
	if to_item.has_method("set_weapon_runtime_state"):
		to_item.set_weapon_runtime_state(runtime_copy)
	else:
		weapon_runtime_state[_get_runtime_item_key(to_item)] = runtime_copy


func get_attached_scope(weapon_item: ItemData) -> ItemData:
	return get_attached_attachment(weapon_item, ATTACHMENT_SLOT_SCOPE)


func has_attached_scope(weapon_item: ItemData) -> bool:
	return get_attached_scope(weapon_item) != null


func can_attach_scope_to_weapon(scope_item: ItemData, weapon_item: ItemData) -> bool:
	return can_attach_attachment_to_weapon(scope_item, weapon_item)


func can_attach_attachment_to_weapon(attachment_item: ItemData, weapon_item: ItemData) -> bool:
	if attachment_item == null or weapon_item == null:
		return false
	if not (attachment_item.is_weapon_attachment or attachment_item.is_scope_attachment):
		return false
	if not (weapon_item.can_receive_weapon_attachments or weapon_item.can_receive_scope_attachment):
		return false
	if weapon_item.storage_category != ItemData.StorageCategory.WEAPON:
		return false
	if not _is_scope_weapon_allowed(attachment_item, weapon_item):
		return false

	var target_slot: int = _get_attachment_slot(attachment_item)
	return get_attached_attachment(weapon_item, target_slot) == null


func _is_scope_weapon_allowed(scope_item: ItemData, weapon_item: ItemData) -> bool:
	var allowed_by_specific_weapon: bool = false
	if not scope_item.allowed_scope_weapons.is_empty():
		for allowed_weapon in scope_item.allowed_scope_weapons:
			var allowed_weapon_data: ItemData = allowed_weapon as ItemData
			if _is_same_weapon_resource(allowed_weapon_data, weapon_item):
				allowed_by_specific_weapon = true
				break
		if not allowed_by_specific_weapon:
			return false

	if not scope_item.allowed_scope_weapon_types.is_empty() and weapon_item.item_type not in scope_item.allowed_scope_weapon_types:
		return false
	if not scope_item.allowed_scope_weapon_names.is_empty():
		var weapon_name: String = weapon_item.item_name.strip_edges().to_lower()
		var is_name_allowed: bool = false
		for allowed_name in scope_item.allowed_scope_weapon_names:
			if weapon_name == String(allowed_name).strip_edges().to_lower():
				is_name_allowed = true
				break
		if not is_name_allowed:
			return false

	return true


func _is_same_weapon_resource(left_weapon: ItemData, right_weapon: ItemData) -> bool:
	if left_weapon == null or right_weapon == null:
		return false
	if left_weapon == right_weapon:
		return true

	var left_path: String = left_weapon.resource_path
	var right_path: String = right_weapon.resource_path
	if not left_path.is_empty() and not right_path.is_empty() and left_path == right_path:
		return true

	return left_weapon.item_name.strip_edges().to_lower() == right_weapon.item_name.strip_edges().to_lower()


func set_attached_scope(weapon_item: ItemData, scope_item: ItemData) -> bool:
	return set_attached_attachment(weapon_item, scope_item)


func set_attached_attachment(weapon_item: ItemData, attachment_item: ItemData) -> bool:
	if not can_attach_attachment_to_weapon(attachment_item, weapon_item):
		return false

	var state: Dictionary = get_weapon_runtime_state(weapon_item)
	var attachments: Dictionary = state.get("attached_attachments", {})
	var slot_type: int = _get_attachment_slot(attachment_item)
	attachments[slot_type] = attachment_item
	state["attached_attachments"] = attachments
	state["attached_scope"] = attachments.get(ATTACHMENT_SLOT_SCOPE, null)
	_set_weapon_runtime_state_for_item(weapon_item, state)
	equipment_changed.emit(weapon_item.item_type, weapon_item)
	return true


func detach_attached_scope(weapon_item: ItemData) -> ItemData:
	return detach_attached_attachment(weapon_item, ATTACHMENT_SLOT_SCOPE)


func detach_attached_attachment(weapon_item: ItemData, slot_type: int) -> ItemData:
	if weapon_item == null:
		return null

	var state: Dictionary = get_weapon_runtime_state(weapon_item)
	var attachments: Dictionary = state.get("attached_attachments", {})
	var detached_attachment: ItemData = attachments.get(slot_type, null)
	if detached_attachment == null:
		return null

	attachments.erase(slot_type)
	state["attached_attachments"] = attachments
	state["attached_scope"] = attachments.get(ATTACHMENT_SLOT_SCOPE, null)
	_set_weapon_runtime_state_for_item(weapon_item, state)
	equipment_changed.emit(weapon_item.item_type, weapon_item)
	return detached_attachment


func get_attached_attachment(weapon_item: ItemData, slot_type: int) -> ItemData:
	if weapon_item == null:
		return null
	var state: Dictionary = get_weapon_runtime_state(weapon_item)
	var attachments: Dictionary = state.get("attached_attachments", {})
	return attachments.get(slot_type, null)


func get_attached_attachments(weapon_item: ItemData) -> Array[ItemData]:
	var result: Array[ItemData] = []
	if weapon_item == null:
		return result
	var state: Dictionary = get_weapon_runtime_state(weapon_item)
	var attachments: Dictionary = state.get("attached_attachments", {})
	for slot_key in attachments.keys():
		var attachment: ItemData = attachments.get(slot_key, null)
		if attachment != null:
			result.append(attachment)
	return result


func has_any_attached_attachments(weapon_item: ItemData) -> bool:
	return not get_attached_attachments(weapon_item).is_empty()


func detach_first_attached_attachment(weapon_item: ItemData) -> ItemData:
	if weapon_item == null:
		return null
	for slot_type in [ATTACHMENT_SLOT_SCOPE, ATTACHMENT_SLOT_HANDLE, ATTACHMENT_SLOT_SILENCER]:
		var detached: ItemData = detach_attached_attachment(weapon_item, slot_type)
		if detached != null:
			return detached
	return null


func _get_attachment_slot(attachment_item: ItemData) -> int:
	if attachment_item == null:
		return ATTACHMENT_SLOT_SCOPE
	if attachment_item.is_scope_attachment and not attachment_item.is_weapon_attachment:
		return ATTACHMENT_SLOT_SCOPE
	return int(attachment_item.attachment_slot)


func get_active_weapon_slot() -> int:
	return active_weapon_slot


func set_active_weapon_slot(slot_type: int) -> void:
	if not _is_switchable_weapon_slot(slot_type):
		return

	if get_equipped(slot_type) == null:
		return

	active_weapon_slot = slot_type
	equipment_changed.emit(slot_type, get_equipped(slot_type))


func cycle_active_weapon(direction: int) -> void:
	var available_slots: Array[int] = []
	for slot_type in _get_switchable_weapon_slots():
		if get_equipped(slot_type) != null:
			available_slots.append(slot_type)

	if available_slots.is_empty():
		return

	var current_index: int = available_slots.find(active_weapon_slot)
	if current_index == -1:
		active_weapon_slot = available_slots[0]
		equipment_changed.emit(active_weapon_slot, get_equipped(active_weapon_slot))
		return

	var step: int = 1 if direction >= 0 else -1
	var next_index: int = posmod(current_index + step, available_slots.size())
	active_weapon_slot = available_slots[next_index]
	equipment_changed.emit(active_weapon_slot, get_equipped(active_weapon_slot))


func get_active_weapon_item() -> ItemData:
	return get_equipped(active_weapon_slot)


func get_total_carried_weight() -> float:
	var total_weight: float = 0.0
	for slot_type in equipped.keys():
		total_weight += _get_item_total_weight(equipped[slot_type], true)
	return total_weight


func get_total_loose_ammo(ammo_type: String = "") -> int:
	var total: int = 0
	for slot_type in equipped.keys():
		total += _count_ammo_in_item(equipped[slot_type], ammo_type)
	return total


func consume_loose_ammo(amount: int, ammo_type: String = "") -> int:
	var remaining: int = max(amount, 0)
	if remaining <= 0:
		return 0

	for slot_type in equipped.keys():
		remaining = _consume_ammo_in_equipped_slot(slot_type, remaining, ammo_type)
		if remaining <= 0:
			break

	return amount - remaining


func get_weapon_display_text(item: ItemData) -> String:
	if item == null:
		return ""

	return "%d/%d" % [get_ammo_in_mag(item), get_reserve_ammo(item)]


func add_reserve_ammo(item: ItemData, amount: int) -> int:
	if item == null:
		return 0
	if amount <= 0:
		return 0

	var state: Dictionary = get_weapon_runtime_state(item)
	var current_reserve: int = int(state.get("reserve_ammo", 0))
	var max_reserve: int = max(item.reserve_ammo, 0)
	var ammo_to_add: int = min(amount, max(max_reserve - current_reserve, 0))
	if ammo_to_add <= 0:
		return 0

	set_ammo_state(item, get_ammo_in_mag(item), current_reserve + ammo_to_add)
	return ammo_to_add


func get_equipped_weapon_by_ammo_type(ammo_type: String) -> ItemData:
	if ammo_type.is_empty():
		return null

	for slot_type in _get_switchable_weapon_slots():
		var equipped_item: ItemData = get_equipped(slot_type)
		if equipped_item == null:
			continue
		if equipped_item.storage_category != ItemData.StorageCategory.WEAPON:
			continue
		if equipped_item.ammo_type == ammo_type:
			return equipped_item

	return null


func _sync_active_weapon_slot(changed_slot_type: int) -> void:
	if not _is_switchable_weapon_slot(changed_slot_type):
		return

	if get_equipped(active_weapon_slot) != null:
		return

	for slot_type in _get_switchable_weapon_slots():
		if get_equipped(slot_type) != null:
			active_weapon_slot = slot_type
			return

	active_weapon_slot = ItemData.ItemType.AR_Weapon


func _get_switchable_weapon_slots() -> Array[int]:
	return [
		ItemData.ItemType.AR_Weapon,
		ItemData.ItemType.Pistols,
		ItemData.ItemType.MeleeWeapon
	]


func _is_switchable_weapon_slot(slot_type: int) -> bool:
	return slot_type in _get_switchable_weapon_slots()


func _get_clothing_slot_types() -> Array[int]:
	return [
		ItemData.ItemType.T_shirts,
		ItemData.ItemType.Jacket,
		ItemData.ItemType.HeavyArmour,
		ItemData.ItemType.Trousers,
		ItemData.ItemType.Bag,
		ItemData.ItemType.Cap
	]


func _get_clothing_damage_multiplier(item: ItemData, damage_type: int) -> float:
	match damage_type:
		ItemData.DamageType.BULLET:
			return item.clothing_endurance_multiplier_bullet
		ItemData.DamageType.BITE:
			return item.clothing_endurance_multiplier_bite
		ItemData.DamageType.MELEE:
			return item.clothing_endurance_multiplier_melee
		ItemData.DamageType.EXPLOSION:
			return item.clothing_endurance_multiplier_explosion
		_:
			return item.clothing_endurance_multiplier_generic


func _is_valid_equipped_clothing(item: ItemData) -> bool:
	return item != null and item.storage_category == ItemData.StorageCategory.CLOTHING and item.endurance > 0


func _get_clothing_endurance_ratio(item: ItemData) -> float:
	if item == null:
		return 0.0
	return clampf(float(item.endurance) / 100.0, 0.0, 1.0)


func _get_damage_after_clothing_armor(damage_amount: float, armor: float) -> float:
	var max_absorption: float = damage_amount * MAX_CLOTHING_DAMAGE_REDUCTION_RATIO
	return maxf(damage_amount - minf(maxf(armor, 0.0), max_absorption), 0.0)


func _consume_item_endurance_percent(item: ItemData, percent_loss: float) -> bool:
	if item == null:
		return false

	var safe_percent_loss: float = max(percent_loss, 0.0)
	if safe_percent_loss <= 0.0:
		return false

	var item_key: Variant = _get_runtime_item_key(item)
	var accumulated_loss: float = safe_percent_loss + float(endurance_loss_remainder_by_item_id.get(item_key, 0.0))
	var applied_loss_int: int = int(floor(accumulated_loss))
	endurance_loss_remainder_by_item_id[item_key] = accumulated_loss - float(applied_loss_int)

	if applied_loss_int <= 0:
		return false

	item.endurance = max(item.endurance - applied_loss_int, 0)
	return true


func _get_runtime_item_key(item: ItemData) -> Variant:
	if item != null and item.has_method("get_runtime_id"):
		return item.get_runtime_id()
	return item.get_instance_id()


func _set_weapon_runtime_state_for_item(item: ItemData, state: Dictionary) -> void:
	if item == null:
		return
	if item.has_method("set_weapon_runtime_state"):
		item.set_weapon_runtime_state(state)
	else:
		weapon_runtime_state[_get_runtime_item_key(item)] = state


func _clone_runtime_item(item: ItemData) -> ItemData:
	if item == null:
		return null
	if item.has_method("create_runtime_copy"):
		return item.create_runtime_copy()
	return item.duplicate(true)


func _hot_reload_changed_attachment_resources() -> void:
	var watched_paths: Array[String] = []
	var weapon_items: Array[ItemData] = _collect_weapon_items()

	for item in equipped.values():
		_collect_item_resource_paths_recursive(item as ItemData, watched_paths)

	for attachment_path in watched_paths:
		var current_signature: int = _get_resource_change_signature(attachment_path)
		if current_signature <= 0:
			continue
		if not _attachment_resource_signature_by_path.has(attachment_path):
			_attachment_resource_signature_by_path[attachment_path] = current_signature
			_reload_item_resource_everywhere(attachment_path, weapon_items)
			continue
		var previous_signature: int = int(_attachment_resource_signature_by_path.get(attachment_path, 0))
		if current_signature == previous_signature:
			continue
		_attachment_resource_signature_by_path[attachment_path] = current_signature
		_reload_item_resource_everywhere(attachment_path, weapon_items)

	for watched_path in _attachment_resource_signature_by_path.keys():
		if not watched_paths.has(String(watched_path)):
			_attachment_resource_signature_by_path.erase(watched_path)


func _reload_item_resource_everywhere(attachment_path: String, weapon_items: Array[ItemData]) -> void:
	var changed_weapons: Array[ItemData] = []
	for weapon_item in weapon_items:
		if _get_item_definition_resource_path(weapon_item) == attachment_path and _apply_hot_reloaded_weapon_attachment_layout_from_file(weapon_item, attachment_path):
			changed_weapons.append(weapon_item)

	var reloaded_definition: ItemData = ResourceLoader.load(attachment_path, "", ResourceLoader.CACHE_MODE_IGNORE) as ItemData
	if reloaded_definition == null:
		push_warning("InventoryManager: failed to hot-reload item resource '%s'." % attachment_path)
	else:
		for weapon_item in weapon_items:
			if _reload_attachment_resource_for_weapon(weapon_item, attachment_path, reloaded_definition):
				if not changed_weapons.has(weapon_item):
					changed_weapons.append(weapon_item)
	var changed_equipped_slots: Array[int] = []
	if reloaded_definition != null:
		for slot_type in equipped.keys():
			var equipped_item: ItemData = equipped.get(slot_type, null) as ItemData
			var reload_result: Dictionary = _reload_attachment_resource_in_item_tree(equipped_item, attachment_path, reloaded_definition)
			if bool(reload_result.get("changed", false)):
				equipped[slot_type] = reload_result.get("item", equipped_item)
				changed_equipped_slots.append(int(slot_type))

	for weapon_item in changed_weapons:
		equipment_changed.emit(weapon_item.item_type, weapon_item)
		_collect_equipped_slots_containing_item(weapon_item, changed_equipped_slots)
	for slot_type in changed_equipped_slots:
		equipment_changed.emit(slot_type, equipped.get(slot_type, null))


func _apply_hot_reloaded_weapon_attachment_layout_from_file(weapon_item: ItemData, weapon_path: String) -> bool:
	if weapon_item == null or weapon_item.storage_category != ItemData.StorageCategory.WEAPON:
		return false

	var layout_values: Dictionary = _read_weapon_attachment_layout_values_from_tres(weapon_path)
	if layout_values.is_empty():
		return false

	var changed: bool = false
	for property_name in layout_values.keys():
		var next_value: Variant = layout_values.get(property_name)
		if weapon_item.get(String(property_name)) == next_value:
			continue
		weapon_item.set(String(property_name), next_value)
		changed = true

	return changed


func _read_weapon_attachment_layout_values_from_tres(resource_path: String) -> Dictionary:
	var values: Dictionary = {}
	var absolute_path: String = ProjectSettings.globalize_path(resource_path)
	if absolute_path.is_empty() or not FileAccess.file_exists(absolute_path):
		return values

	var file: FileAccess = FileAccess.open(absolute_path, FileAccess.READ)
	if file == null:
		return values

	var vector_properties: Array[String] = [
		"scope_inventory_offset",
		"handle_inventory_offset",
		"silencer_inventory_offset",
		"attached_inventory_icon_offset"
	]
	var float_properties: Array[String] = [
		"scope_rotation_down",
		"scope_rotation_up",
		"scope_rotation_left",
		"scope_rotation_right",
		"scope_inventory_rotation_degrees"
	]

	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		var separator_index: int = line.find("=")
		if separator_index < 0:
			continue
		var property_name: String = line.substr(0, separator_index).strip_edges()
		var raw_value: String = line.substr(separator_index + 1).strip_edges()
		if property_name in vector_properties:
			values[property_name] = _parse_tres_vector2(raw_value)
		elif property_name in float_properties:
			values[property_name] = raw_value.to_float()

	return values


func _parse_tres_vector2(raw_value: String) -> Vector2:
	var value: String = raw_value.strip_edges()
	if not value.begins_with("Vector2(") or not value.ends_with(")"):
		return Vector2.ZERO
	value = value.trim_prefix("Vector2(").trim_suffix(")")
	var parts: PackedStringArray = value.split(",", false)
	if parts.size() < 2:
		return Vector2.ZERO
	return Vector2(parts[0].strip_edges().to_float(), parts[1].strip_edges().to_float())


func _apply_hot_reloaded_weapon_attachment_layout(weapon_item: ItemData, reloaded_definition: ItemData) -> bool:
	if weapon_item == null or reloaded_definition == null:
		return false
	if weapon_item.storage_category != ItemData.StorageCategory.WEAPON:
		return false

	var layout_property_names: Array[String] = [
		"scope_rotation_down",
		"scope_rotation_up",
		"scope_rotation_left",
		"scope_rotation_right",
		"scope_inventory_offset",
		"handle_inventory_offset",
		"silencer_inventory_offset",
		"attached_inventory_icon_offset",
		"scope_inventory_rotation_degrees"
	]
	var previous_values: Dictionary = {}
	for property_name in layout_property_names:
		previous_values[property_name] = weapon_item.get(property_name)

	if weapon_item.has_method("refresh_definition_values"):
		weapon_item.call("refresh_definition_values", reloaded_definition)
	else:
		for property_name in layout_property_names:
			weapon_item.set(property_name, reloaded_definition.get(property_name))

	for property_name in layout_property_names:
		if previous_values.get(property_name) == weapon_item.get(property_name):
			continue
		return true

	return false


func _reload_attachment_resource_for_weapon(weapon_item: ItemData, attachment_path: String, reloaded_definition: ItemData) -> bool:
	if weapon_item == null:
		return false

	var state: Dictionary = get_weapon_runtime_state(weapon_item)
	var attachments: Dictionary = state.get("attached_attachments", {})
	if attachments.is_empty():
		return false

	var changed: bool = false
	for slot_key in attachments.keys():
		var attachment_item: ItemData = attachments.get(slot_key, null)
		if _get_item_definition_resource_path(attachment_item) != attachment_path:
			continue
		attachments[slot_key] = _create_hot_reloaded_attachment_instance(attachment_item, reloaded_definition)
		changed = true

	if not changed:
		return false

	state["attached_attachments"] = attachments
	state["attached_scope"] = attachments.get(ATTACHMENT_SLOT_SCOPE, null)
	_set_weapon_runtime_state_for_item(weapon_item, state)
	return true


func _create_hot_reloaded_attachment_instance(previous_item: ItemData, reloaded_definition: ItemData) -> ItemData:
	if previous_item == null:
		return reloaded_definition

	var should_keep_runtime_instance: bool = previous_item.has_method("is_runtime_instance") and bool(previous_item.call("is_runtime_instance"))
	if not should_keep_runtime_instance:
		return reloaded_definition

	var next_item: ItemData = reloaded_definition.create_instance(previous_item.stack_count, previous_item.endurance) if reloaded_definition.has_method("create_instance") else reloaded_definition.duplicate(true)
	if next_item == null:
		return reloaded_definition

	if "runtime_id" in previous_item and "runtime_id" in next_item:
		next_item.set("runtime_id", String(previous_item.get("runtime_id")))
	next_item.runtime_storage_items.clear()
	for stored_item in previous_item.runtime_storage_items:
		if stored_item == null:
			next_item.runtime_storage_items.append(null)
		else:
			next_item.runtime_storage_items.append(_clone_runtime_item(stored_item))
	return next_item


func _collect_weapon_items() -> Array[ItemData]:
	var result: Array[ItemData] = []
	for item in equipped.values():
		_collect_weapon_items_recursive(item as ItemData, result)
	return result


func _collect_weapon_items_with_attachments() -> Array[ItemData]:
	var result: Array[ItemData] = []
	for item in equipped.values():
		_collect_weapon_items_with_attachments_recursive(item as ItemData, result)
	return result


func _collect_weapon_items_recursive(item: ItemData, result: Array[ItemData]) -> void:
	if item == null:
		return
	if item.storage_category == ItemData.StorageCategory.WEAPON:
		if not result.has(item):
			result.append(item)
	for stored_item in item.runtime_storage_items:
		_collect_weapon_items_recursive(stored_item, result)


func _collect_weapon_items_with_attachments_recursive(item: ItemData, result: Array[ItemData]) -> void:
	if item == null:
		return
	if item.storage_category == ItemData.StorageCategory.WEAPON and has_any_attached_attachments(item):
		if not result.has(item):
			result.append(item)
	for stored_item in item.runtime_storage_items:
		_collect_weapon_items_with_attachments_recursive(stored_item, result)


func _collect_equipped_slots_containing_item(target_item: ItemData, result: Array[int]) -> void:
	if target_item == null:
		return
	for slot_type in equipped.keys():
		var equipped_item: ItemData = equipped.get(slot_type, null) as ItemData
		if _item_tree_contains_item(equipped_item, target_item) and not result.has(int(slot_type)):
			result.append(int(slot_type))


func _item_tree_contains_item(root_item: ItemData, target_item: ItemData) -> bool:
	if root_item == null or target_item == null:
		return false
	if root_item == target_item:
		return true
	for stored_item in root_item.runtime_storage_items:
		if _item_tree_contains_item(stored_item, target_item):
			return true
	return false


func _collect_item_resource_paths_recursive(item: ItemData, result: Array[String]) -> void:
	if item == null:
		return
	var item_path: String = _get_item_definition_resource_path(item)
	if not item_path.is_empty() and item_path.ends_with(".tres") and not result.has(item_path):
		result.append(item_path)
	if item.storage_category == ItemData.StorageCategory.WEAPON:
		for attached_item in get_attached_attachments(item):
			_collect_item_resource_paths_recursive(attached_item, result)
	for stored_item in item.runtime_storage_items:
		_collect_item_resource_paths_recursive(stored_item, result)


func _reload_attachment_resource_in_item_tree(item: ItemData, attachment_path: String, reloaded_definition: ItemData) -> Dictionary:
	if item == null:
		return {"changed": false, "item": item}

	var result_item: ItemData = item
	var changed: bool = false
	if (item.is_scope_attachment or item.is_weapon_attachment) and _get_item_definition_resource_path(item) == attachment_path:
		result_item = _create_hot_reloaded_attachment_instance(item, reloaded_definition)
		changed = true

	for i in range(result_item.runtime_storage_items.size()):
		var stored_item: ItemData = result_item.runtime_storage_items[i]
		var reload_result: Dictionary = _reload_attachment_resource_in_item_tree(stored_item, attachment_path, reloaded_definition)
		if bool(reload_result.get("changed", false)):
			result_item.runtime_storage_items[i] = reload_result.get("item", stored_item)
			changed = true

	return {"changed": changed, "item": result_item}


func _get_item_definition_resource_path(item: ItemData) -> String:
	if item == null:
		return ""
	var definition: ItemData = item.get_definition() if item.has_method("get_definition") else item
	if definition != null and not definition.resource_path.is_empty():
		return definition.resource_path
	return item.resource_path


func _get_resource_change_signature(resource_path: String) -> int:
	if resource_path.is_empty():
		return 0
	var absolute_path: String = ProjectSettings.globalize_path(resource_path)
	if absolute_path.is_empty():
		return 0
	if not FileAccess.file_exists(absolute_path):
		return 0

	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(absolute_path)
	if bytes.is_empty():
		return int(FileAccess.get_modified_time(absolute_path))

	var checksum: int = 2166136261
	for byte_value in bytes:
		checksum = int((checksum ^ int(byte_value)) * 16777619) & 0x7fffffff

	var modified_time: int = int(FileAccess.get_modified_time(absolute_path))
	return int((checksum ^ bytes.size() ^ modified_time) & 0x7fffffff)


func _get_item_total_weight(item: ItemData, include_weapon_attachments: bool = false) -> float:
	if item == null:
		return 0.0

	var stack_size: int = max(item.stack_count, 1)
	var total_weight: float = max(item.item_weight, 0.0) * float(stack_size)

	for stored_item in item.runtime_storage_items:
		total_weight += _get_item_total_weight(stored_item, true)

	if include_weapon_attachments and item.storage_category == ItemData.StorageCategory.WEAPON:
		for attached_item in get_attached_attachments(item):
			total_weight += _get_item_total_weight(attached_item, false)

	return total_weight


func _serialize_item_for_save(item: ItemData) -> Dictionary:
	if item == null:
		return {}
	if item.has_method("to_save_dict"):
		return item.to_save_dict()

	var instance: ItemData = item.create_instance(item.stack_count, item.endurance) if item.has_method("create_instance") else null
	if instance != null:
		instance.runtime_storage_items.clear()
		for stored_item in item.runtime_storage_items:
			if stored_item == null:
				instance.runtime_storage_items.append(null)
			else:
				instance.runtime_storage_items.append(_clone_runtime_item(stored_item))

		copy_runtime_state(item, instance)
		if instance.has_method("to_save_dict"):
			return instance.to_save_dict()

	return {
		"runtime_id": str(item.get_instance_id()),
		"definition_path": item.resource_path,
		"stack_count": int(item.stack_count),
		"endurance": int(item.endurance),
		"runtime_storage_items": [],
		"weapon_runtime_state": {}
	}


func _deserialize_item_from_save(raw_item: Variant) -> ItemData:
	if not (raw_item is Dictionary):
		return null
	return ITEM_INSTANCE_SCRIPT.from_save_dict(raw_item as Dictionary)


func _count_ammo_in_item(item: ItemData, ammo_type: String = "") -> int:
	if item == null:
		return 0

	var total: int = 0
	if item.is_ammo_item and (ammo_type.is_empty() or item.ammo_type == ammo_type):
		total += max(item.stack_count, 0)

	for stored_item in item.runtime_storage_items:
		total += _count_ammo_in_item(stored_item, ammo_type)

	return total


func _consume_ammo_in_equipped_slot(slot_type: int, amount: int, ammo_type: String = "") -> int:
	var item: ItemData = get_equipped(slot_type)
	if item == null:
		return amount

	var remaining: int = _consume_ammo_in_item(item, amount, ammo_type)
	if item.is_ammo_item and (ammo_type.is_empty() or item.ammo_type == ammo_type) and item.stack_count <= 0:
		set_equipped(slot_type, null)

	return remaining


func _consume_ammo_in_item(item: ItemData, amount: int, ammo_type: String = "") -> int:
	var remaining: int = amount
	if item == null or remaining <= 0:
		return remaining

	if item.is_ammo_item and item.stack_count > 0 and (ammo_type.is_empty() or item.ammo_type == ammo_type):
		var to_take: int = min(item.stack_count, remaining)
		item.stack_count -= to_take
		remaining -= to_take

	for i in range(item.runtime_storage_items.size()):
		if remaining <= 0:
			break

		var stored_item: ItemData = item.runtime_storage_items[i]
		if stored_item == null:
			continue

		remaining = _consume_ammo_in_item(stored_item, remaining, ammo_type)
		if stored_item.is_ammo_item and (ammo_type.is_empty() or stored_item.ammo_type == ammo_type) and stored_item.stack_count <= 0:
			item.runtime_storage_items[i] = null

	return remaining
