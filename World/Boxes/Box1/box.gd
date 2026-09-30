extends Node2D
const ProviderContract = preload("res://World/Generation/loot_container_provider_contract.gd")
const LootPersistence = preload("res://World/Generation/loot_container_persistence.gd")
const LootRestock = preload("res://World/Generation/loot_container_restock.gd")

@onready var box_closed_sprite: Sprite2D = $Box
@onready var box_closed_outline_sprite: Sprite2D = $BoxOutline
@onready var box_opened_sprite: Sprite2D = $BoxOpened
@onready var box_opened_outline_sprite: Sprite2D = $BoxOpenedOutline
@onready var interact_area: Area2D = $InteractArea
@onready var interact_label: Label = $InteractLabel

@export var interaction_distance: float = 50.0
@export var loot_slot_count: int = 8
@export var loot_spawn_min: int = 0
@export var loot_spawn_max: int = 0
@export var guaranteed_items: Array[ItemData] = [
	preload("res://Resources/AR_Weapons/akp_103/VX_25.tres"),
	preload("res://Resources/AR_Weapons/akp_103/handle.tres"),
	preload("res://Resources/AR_Weapons/akp_103/silencer.tres")
]
@export var loot_pool: Array[ItemData] = []
@export var persistent_id: String = ""
@export var world_generated_loot := false
@export var generated_container_id := ""
@export var loot_profile: LootProfile = preload("res://Resources/WorldGen/Loot/box_loot_profile.tres")
@export var loot_slot_ids: Array[String] = ["slot_00", "slot_01", "slot_02", "slot_03", "slot_04", "slot_05", "slot_06", "slot_07"]

var player_near_box: bool = false
var box_opened: bool = false
var loot_initialized: bool = false
var loot_slots: Array[ItemData] = []
var _loot_manifest: LootContainerManifest
var _loot_persistence_state := LootPersistence.STATE_UNOPENED
var _removed_loot_slot_ids: Array[String] = []
var _legacy_overflow_items: Array[ItemData] = []
var _loot_restock_state: Dictionary = {}


func _ready() -> void:
	if not world_generated_loot: randomize()
	add_to_group("primary_interactable")
	interact_area.body_entered.connect(_on_interact_area_body_entered)
	interact_area.body_exited.connect(_on_interact_area_body_exited)
	_update_box_visual()
	if GameSaveManager != null and GameSaveManager.has_method("register_persistent_node"):
		GameSaveManager.register_persistent_node(self)
	call_deferred("_restore_loot_restock_cycle")


func handle_primary_interaction(interactor: Node) -> bool:
	if interactor == null or not interactor.is_in_group("player"):
		return false
	if not player_near_box:
		return false
	if box_opened:
		return false
	if not (interactor is Node2D):
		return false

	var player_node: Node2D = interactor as Node2D
	if global_position.distance_to(player_node.global_position) > max(interaction_distance, 1.0):
		return false

	box_opened = true
	_ensure_loot()
	mark_loot_opened()
	_set_loot_panel_state(true)
	_update_box_visual()
	return true


func _on_interact_area_body_entered(body: Node) -> void:
	if not ProviderContract.is_local_interactor(body):
		return

	player_near_box = true
	_update_box_visual()


func _on_interact_area_body_exited(body: Node) -> void:
	if not ProviderContract.is_local_interactor(body):
		return

	player_near_box = false
	box_opened = false
	_set_loot_panel_state(false)
	_update_box_visual()


func _update_box_visual() -> void:
	if not box_opened:
		box_closed_sprite.visible = true
		box_closed_outline_sprite.visible = player_near_box
		box_opened_sprite.visible = false
		box_opened_outline_sprite.visible = false
		interact_label.text = "[E] - открыть"
		interact_label.visible = player_near_box
		return

	box_closed_sprite.visible = false
	box_closed_outline_sprite.visible = false
	box_opened_sprite.visible = true
	box_opened_outline_sprite.visible = player_near_box
	interact_label.text = ""
	interact_label.visible = false


func _set_loot_panel_state(active: bool) -> void:
	var inventory_root: Node = get_tree().get_first_node_in_group("inventory_root")
	if inventory_root == null:
		return

	if active and inventory_root.has_method("open_loot_slots"):
		_promote_legacy_overflow_items()
		inventory_root.call("open_loot_slots", loot_slots, self)
	elif inventory_root.has_method("close_loot_for"):
		inventory_root.call("close_loot_for", self)


func _ensure_loot() -> void:
	if multiplayer.multiplayer_peer != null and not NetworkManager.is_server():
		return
	if loot_initialized:
		return
	if world_generated_loot:
		push_error("Box: world-generated loot requires an applied LootContainerManifest")
		return

	if loot_profile != null:
		loot_slots = LootPopulationPass.roll_standalone_items(loot_profile, loot_slot_count)
		loot_initialized = true
		return

	loot_initialized = true
	loot_slots.clear()
	loot_slots.resize(max(loot_slot_count, 0))

	if loot_slot_count <= 0:
		return

	var min_spawn: int = clamp(loot_spawn_min, 0, loot_slot_count)
	var max_spawn: int = clamp(loot_spawn_max, min_spawn, loot_slot_count)

	var free_indices: Array[int] = []
	for i in range(loot_slot_count):
		free_indices.append(i)

	for guaranteed_item in guaranteed_items:
		if free_indices.is_empty():
			break
		if guaranteed_item == null:
			continue

		var guaranteed_slot_pos: int = randi_range(0, free_indices.size() - 1)
		var guaranteed_slot_index: int = free_indices[guaranteed_slot_pos]
		free_indices.remove_at(guaranteed_slot_pos)

		var guaranteed_item_instance: ItemData = guaranteed_item.create_instance(1)
		loot_slots[guaranteed_slot_index] = guaranteed_item_instance

	if loot_pool.is_empty() or free_indices.is_empty():
		return

	var spawn_count: int = randi_range(min_spawn, max_spawn)
	spawn_count = min(spawn_count, free_indices.size())
	for _i in range(spawn_count):
		if free_indices.is_empty():
			break

		var free_pos: int = randi_range(0, free_indices.size() - 1)
		var slot_index: int = free_indices[free_pos]
		free_indices.remove_at(free_pos)

		var template_item: ItemData = loot_pool[randi_range(0, loot_pool.size() - 1)]
		if template_item == null:
			continue

		var item_instance: ItemData = template_item.create_instance(1)
		loot_slots[slot_index] = item_instance

func get_loot_container_id() -> String: return generated_container_id.strip_edges()
func get_loot_profile() -> LootProfile: return loot_profile
func get_existing_loot_manifest() -> LootContainerManifest: return _loot_manifest
func has_materialized_loot() -> bool: return loot_initialized
func get_loot_slot_bindings() -> Dictionary:
	var result := {}; var ids := loot_slot_ids.duplicate(); ids.sort()
	for i in range(ids.size()): result[ids[i]] = i
	return result
func apply_loot_manifest(manifest: LootContainerManifest) -> Dictionary:
	var validation: Dictionary = ProviderContract.validate(self)
	if not validation.valid: return {"valid":false,"errors":validation.errors}
	if manifest == null or manifest.container_generated_id != get_loot_container_id() or manifest.profile_id != loot_profile.profile_id: return {"valid":false,"errors":["MANIFEST_ID_OR_PROFILE_MISMATCH"]}
	if _loot_manifest != null:
		return {"valid":_loot_manifest.manifest_hash() == manifest.manifest_hash(),"errors":[] if _loot_manifest.manifest_hash() == manifest.manifest_hash() else ["CONFLICTING_MANIFEST"]}
	var bindings := get_loot_slot_bindings(); var ids := {}; loot_slots.clear(); loot_slots.resize(loot_slot_count)
	for record in manifest.slots:
		if ids.has(record.slot_id) or not bindings.has(record.slot_id): return {"valid":false,"errors":["DUPLICATE_OR_UNKNOWN_MANIFEST_SLOT"]}
		ids[record.slot_id] = true; var item := load(record.item_resource_key) as ItemData
		if item == null: return {"valid":false,"errors":["MISSING_ITEM_RESOURCE"]}
		var instance := item.create_instance(record.quantity); instance.set_meta("loot_container_id", manifest.container_generated_id); instance.set_meta("loot_slot_id", record.slot_id); instance.set_meta("loot_manifest_hash", manifest.manifest_hash()); loot_slots[int(bindings[record.slot_id])] = instance
	_loot_manifest = manifest; loot_initialized = true; return {"valid":true,"errors":[]}


func get_loot_persistence_key() -> String:
	return LootPersistence.get_persistence_key(get_loot_container_id())


func get_loot_persistence_state() -> String:
	return _loot_persistence_state


func set_loot_persistence_state(state: String) -> void:
	_loot_persistence_state = state


func get_removed_loot_slot_ids() -> Array[String]:
	return _removed_loot_slot_ids.duplicate()


func serialize_loot_state() -> Dictionary:
	return LootPersistence.serialize_provider_state(self)


func restore_loot_state(data: Dictionary) -> Dictionary:
	return LootPersistence.restore_provider_state(self, data)


func mark_loot_opened() -> Dictionary:
	LootRestock.begin_open_cycle(self, _loot_restock_state, loot_slots)
	return LootPersistence.mark_opened(self)


func record_loot_slot_removed(slot_id: String) -> Dictionary:
	return LootPersistence.mark_slot_removed(self, slot_id)


func record_persisted_loot_slot_removal(slot_id: String) -> Dictionary:
	var bindings := get_loot_slot_bindings()
	if not bindings.has(slot_id) or _loot_manifest == null or not _manifest_has_slot(slot_id):
		return {"valid": false, "errors": ["UNKNOWN_SLOT"]}
	if not _removed_loot_slot_ids.has(slot_id):
		_removed_loot_slot_ids.append(slot_id)
		_removed_loot_slot_ids.sort()
	loot_slots[int(bindings[slot_id])] = null
	_loot_persistence_state = LootPersistence.STATE_PARTIALLY_EMPTIED
	return {"valid": true, "errors": []}


func restore_persisted_loot_state(manifest: LootContainerManifest, state: String, removed_slot_ids: Array[String]) -> Dictionary:
	if _loot_manifest != null and _loot_manifest.manifest_hash() != manifest.manifest_hash():
		return {"valid": false, "errors": ["INCOMPATIBLE_MATERIALIZED_STATE"]}
	if _loot_manifest == null:
		loot_slots.clear()
		loot_slots.resize(loot_slot_count)
		var bindings := get_loot_slot_bindings()
		for record in manifest.slots:
			if record.item_resource_key.is_empty() or not ResourceLoader.exists(record.item_resource_key):
				return {"valid": false, "errors": ["UNKNOWN_ITEM_RESOURCE"]}
			var item := load(record.item_resource_key) as ItemData
			if item == null:
				return {"valid": false, "errors": ["UNKNOWN_ITEM_RESOURCE"]}
			var instance := item.create_instance(record.quantity)
			instance.set_meta("loot_container_id", manifest.container_generated_id)
			instance.set_meta("loot_slot_id", record.slot_id)
			instance.set_meta("loot_manifest_hash", manifest.manifest_hash())
			loot_slots[int(bindings[record.slot_id])] = instance
		_loot_manifest = manifest
		loot_initialized = true
	_removed_loot_slot_ids = removed_slot_ids.duplicate()
	for slot_id in _removed_loot_slot_ids:
		loot_slots[int(get_loot_slot_bindings()[slot_id])] = null
	_loot_persistence_state = state
	box_opened = false
	_set_loot_panel_state(false)
	_update_box_visual()
	return {"valid": true, "errors": []}


func _manifest_has_slot(slot_id: String) -> bool:
	if _loot_manifest == null:
		return false
	for record in _loot_manifest.slots:
		if record.slot_id == slot_id:
			return true
	return false


func get_save_key() -> String:
	return "box:%s" % [_get_persistent_identity()]


func get_legacy_save_keys() -> Array[String]:
	return ["box:%s" % [str(global_position)]]


func _get_persistent_identity() -> String:
	if not persistent_id.strip_edges().is_empty():
		return persistent_id.strip_edges()
	var scene_path: String = ""
	var scene_root: Node = get_tree().current_scene
	if scene_root != null:
		scene_path = scene_root.scene_file_path
	var local_path: String = str(get_path())
	return "%s|%s" % [scene_path, local_path]


func _restore_loot_restock_cycle() -> void:
	_loot_restock_state = LootRestock.restore_cycle(self, _loot_restock_state)


func update_loot_restock(total_minutes: float) -> void:
	_promote_legacy_overflow_items()
	if not LootRestock.is_restock_due(self, _loot_restock_state, loot_slots, total_minutes):
		return
	var stable_id := get_loot_container_id() if world_generated_loot else _get_persistent_identity()
	LootRestock.top_up_empty_slots(self, loot_profile, loot_slots, loot_slot_count, stable_id, total_minutes)
	_removed_loot_slot_ids.clear()
	_loot_persistence_state = LootPersistence.STATE_OPENED
	LootRestock.finish_cycle(self, _loot_restock_state)
	LootRestock.notify_network_state(self)
	var inventory_root := get_tree().get_first_node_in_group("inventory_root")
	if inventory_root != null and inventory_root.has_method("refresh_ui"): inventory_root.call("refresh_ui")


func get_save_data() -> Dictionary:
	return {
		"loot_initialized": loot_initialized,
		"loot_slots": _serialize_item_array(loot_slots),
		"legacy_overflow_items": _serialize_item_array(_legacy_overflow_items),
		"loot_restock_state": LootRestock.serialize_cycle(_loot_restock_state, loot_slots)
	}


func apply_save_data(save_data: Dictionary) -> void:
	box_opened = false
	loot_initialized = bool(save_data.get("loot_initialized", false))
	var restored_slots := _deserialize_item_array(save_data.get("loot_slots", []))
	var restored_overflow := _deserialize_item_array(save_data.get("legacy_overflow_items", []))
	_migrate_loot_capacity(restored_slots, restored_overflow)
	_loot_restock_state = save_data.get("loot_restock_state", {}).duplicate(true)
	_set_loot_panel_state(false)
	_update_box_visual()
	call_deferred("_restore_loot_restock_cycle")


func _migrate_loot_capacity(restored_slots: Array[ItemData], restored_overflow: Array[ItemData] = []) -> void:
	loot_slots.clear()
	loot_slots.resize(max(loot_slot_count, 0))
	_legacy_overflow_items.clear()
	var direct_count := mini(restored_slots.size(), loot_slots.size())
	for index in range(direct_count):
		loot_slots[index] = restored_slots[index]
	var pending: Array[ItemData] = []
	for index in range(direct_count, restored_slots.size()):
		if restored_slots[index] != null: pending.append(restored_slots[index])
	for item in restored_overflow:
		if item != null: pending.append(item)
	for item in pending:
		var free_index := loot_slots.find(null)
		if free_index >= 0: loot_slots[free_index] = item
		else: _legacy_overflow_items.append(item)


func _promote_legacy_overflow_items() -> void:
	while not _legacy_overflow_items.is_empty():
		var free_index := loot_slots.find(null)
		if free_index < 0: return
		loot_slots[free_index] = _legacy_overflow_items.pop_front()


func _serialize_item_array(items: Array) -> Array:
	var out: Array = []
	for item in items:
		if item == null:
			out.append(null)
		elif GameSaveManager != null and GameSaveManager.has_method("serialize_item"):
			out.append(GameSaveManager.serialize_item(item))
		else:
			out.append({})
	return out


func _deserialize_item_array(raw_items: Variant) -> Array[ItemData]:
	var out: Array[ItemData] = []
	if not (raw_items is Array):
		return out
	for raw_item in raw_items:
		if raw_item == null:
			out.append(null)
		elif GameSaveManager != null and GameSaveManager.has_method("deserialize_item"):
			out.append(GameSaveManager.deserialize_item(raw_item))
		else:
			out.append(null)
	return out


func get_network_loot_items() -> Array[ItemData]:
	_ensure_loot()
	return loot_slots
