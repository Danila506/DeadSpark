extends Node

signal equipment_changed(slot_type: int, item: ItemData)
signal ammo_state_changed(item: ItemData)
signal item_broken(slot_type: int, item: ItemData)

var equipped: Dictionary = {}
var weapon_runtime_state: Dictionary = {}
var active_weapon_slot: int = ItemData.ItemType.AR_Weapon
var endurance_loss_remainder_by_item_id: Dictionary = {}

const ATTACHMENT_SLOT_SCOPE: int = ItemData.AttachmentSlot.SCOPE
const ATTACHMENT_SLOT_HANDLE: int = ItemData.AttachmentSlot.HANDLE
const ATTACHMENT_SLOT_SILENCER: int = ItemData.AttachmentSlot.SILENCER


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
			if _is_same_weapon_resource(allowed_weapon, weapon_item):
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
