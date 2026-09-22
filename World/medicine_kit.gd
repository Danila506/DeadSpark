extends Node2D
const ProviderContract = preload("res://World/Generation/loot_container_provider_contract.gd")
const BuildingLoot = preload("res://World/Generation/building_loot_provider.gd")
const LootPersistence = preload("res://World/Generation/loot_container_persistence.gd")

@onready var interact_area: Area2D = $InteractArea
@onready var interact_label: Label = $InteractLabel

@export var interaction_distance: float = 50.0
@export var loot_slot_count: int = 3
@export var loot_spawn_min: int = 1
@export var loot_spawn_max: int = 3
@export var medicine_pool: Array[ItemData] = [
	preload("res://Resources/Medicine/antidote.tres"),
	preload("res://Resources/Medicine/bandage.tres"),
	preload("res://Resources/Medicine/bloodBag.tres"),
	preload("res://Resources/Medicine/healthBox.tres"),
	preload("res://Resources/Medicine/hemostat.tres"),
	preload("res://Resources/Medicine/improvised_splint.tres"),
	preload("res://Resources/Medicine/potassium_iodide.tres"),
	preload("res://Resources/Medicine/restorer.tres"),
	preload("res://Resources/Medicine/saline.tres"),
	preload("res://Resources/Medicine/splint.tres")
]
@export var persistent_id: String = ""
@export var world_generated_loot := false
@export var generated_container_id := ""
@export var loot_profile: LootProfile
@export var loot_slot_ids: Array[String] = ["slot_00", "slot_01", "slot_02"]

var player_near: bool = false
var is_opened: bool = false
var loot_initialized: bool = false
var loot_slots: Array[ItemData] = []
var _loot_manifest: LootContainerManifest
var _loot_persistence_state := LootPersistence.STATE_UNOPENED
var _removed_loot_slot_ids: Array[String] = []


func _ready() -> void:
	if not world_generated_loot: randomize()
	add_to_group("primary_interactable")
	interact_area.body_entered.connect(_on_interact_area_body_entered)
	interact_area.body_exited.connect(_on_interact_area_body_exited)
	_update_interact_label()
	if GameSaveManager != null and GameSaveManager.has_method("register_persistent_node"):
		GameSaveManager.register_persistent_node(self)


func handle_primary_interaction(interactor: Node) -> bool:
	if interactor == null or not interactor.is_in_group("player"):
		return false
	if not player_near:
		return false
	if not (interactor is Node2D):
		return false

	var player_node: Node2D = interactor as Node2D
	if global_position.distance_to(player_node.global_position) > max(interaction_distance, 1.0):
		return false

	is_opened = true
	_ensure_loot()
	mark_loot_opened()
	_set_loot_panel_state(true)
	_update_interact_label()
	return true


func _on_interact_area_body_entered(body: Node) -> void:
	if not ProviderContract.is_local_interactor(body):
		return

	player_near = true
	_update_interact_label()


func _on_interact_area_body_exited(body: Node) -> void:
	if not ProviderContract.is_local_interactor(body):
		return

	player_near = false
	is_opened = false
	_set_loot_panel_state(false)
	_update_interact_label()


func _set_loot_panel_state(active: bool) -> void:
	var inventory_root: Node = get_tree().get_first_node_in_group("inventory_root")
	if inventory_root == null:
		return

	if active and inventory_root.has_method("open_loot_slots"):
		inventory_root.call("open_loot_slots", loot_slots, self)
	elif inventory_root.has_method("close_loot_for"):
		inventory_root.call("close_loot_for", self)


func _update_interact_label() -> void:
	if interact_label == null:
		return

	interact_label.text = "[E] - открыть"
	interact_label.visible = player_near and not is_opened


func _ensure_loot() -> void:
	if multiplayer.multiplayer_peer != null and not NetworkManager.is_server():
		return
	if loot_initialized:
		return
	if world_generated_loot:
		push_error("MedicineKit: world-generated loot requires an applied LootContainerManifest")
		return

	loot_initialized = true
	loot_slots.clear()
	var safe_slot_count: int = max(loot_slot_count, 0)
	loot_slots.resize(safe_slot_count)

	if safe_slot_count <= 0 or medicine_pool.is_empty():
		return

	var min_spawn: int = clamp(loot_spawn_min, 0, safe_slot_count)
	var max_spawn: int = clamp(loot_spawn_max, min_spawn, safe_slot_count)
	var spawn_count: int = randi_range(min_spawn, max_spawn)
	if spawn_count <= 0:
		return

	var free_indices: Array[int] = []
	for i in range(safe_slot_count):
		free_indices.append(i)

	for _i in range(spawn_count):
		if free_indices.is_empty():
			break

		var random_free_idx: int = randi_range(0, free_indices.size() - 1)
		var slot_index: int = free_indices[random_free_idx]
		free_indices.remove_at(random_free_idx)

		var template_item: ItemData = medicine_pool[randi_range(0, medicine_pool.size() - 1)]
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
	if _loot_manifest != null: return {"valid":_loot_manifest.manifest_hash() == manifest.manifest_hash(),"errors":[] if _loot_manifest.manifest_hash() == manifest.manifest_hash() else ["CONFLICTING_MANIFEST"]}
	var bindings := get_loot_slot_bindings(); var ids := {}; loot_slots.clear(); loot_slots.resize(loot_slot_count)
	for record in manifest.slots:
		if ids.has(record.slot_id) or not bindings.has(record.slot_id): return {"valid":false,"errors":["DUPLICATE_OR_UNKNOWN_MANIFEST_SLOT"]}
		ids[record.slot_id] = true; var item := load(record.item_resource_key) as ItemData
		if item == null: return {"valid":false,"errors":["MISSING_ITEM_RESOURCE"]}
		var instance := item.create_instance(record.quantity); instance.set_meta("loot_container_id", manifest.container_generated_id); instance.set_meta("loot_slot_id", record.slot_id); instance.set_meta("loot_manifest_hash", manifest.manifest_hash()); loot_slots[int(bindings[record.slot_id])] = instance
	_loot_manifest = manifest; loot_initialized = true; return {"valid":true,"errors":[]}

func get_loot_persistence_key() -> String: return LootPersistence.get_persistence_key(get_loot_container_id())
func get_loot_persistence_state() -> String: return _loot_persistence_state
func set_loot_persistence_state(state: String) -> void: _loot_persistence_state = state
func get_removed_loot_slot_ids() -> Array[String]: return _removed_loot_slot_ids.duplicate()
func serialize_loot_state() -> Dictionary: return LootPersistence.serialize_provider_state(self)
func restore_loot_state(data: Dictionary) -> Dictionary: return LootPersistence.restore_provider_state(self, data)
func mark_loot_opened() -> Dictionary: return LootPersistence.mark_opened(self)
func record_loot_slot_removed(slot_id: String) -> Dictionary: return LootPersistence.mark_slot_removed(self, slot_id)
func record_persisted_loot_slot_removal(slot_id: String) -> Dictionary:
	var bindings := get_loot_slot_bindings()
	if _loot_manifest == null or not bindings.has(slot_id) or not _manifest_has_slot(slot_id): return {"valid":false,"errors":["UNKNOWN_SLOT"]}
	if not _removed_loot_slot_ids.has(slot_id): _removed_loot_slot_ids.append(slot_id); _removed_loot_slot_ids.sort()
	loot_slots[int(bindings[slot_id])] = null; _loot_persistence_state = LootPersistence.STATE_PARTIALLY_EMPTIED
	return {"valid":true,"errors":[]}
func restore_persisted_loot_state(manifest: LootContainerManifest, state: String, removed: Array[String]) -> Dictionary:
	var result := BuildingLoot.restore_persisted_slots(self, _loot_manifest, manifest, loot_slot_count, removed)
	if not result.valid: return result
	loot_slots = result.slots; _loot_manifest = manifest; loot_initialized = true; _removed_loot_slot_ids = removed.duplicate(); _loot_persistence_state = state; is_opened = false
	_set_loot_panel_state(false); _update_interact_label(); return {"valid":true,"errors":[]}
func _manifest_has_slot(slot_id: String) -> bool:
	for record in _loot_manifest.slots:
		if record.slot_id == slot_id: return true
	return false


func get_save_key() -> String:
	return "medicine_kit:%s" % [_get_persistent_identity()]


func get_legacy_save_keys() -> Array[String]:
	return ["medicine_kit:%s" % [str(global_position)]]


func _get_persistent_identity() -> String:
	if not persistent_id.strip_edges().is_empty():
		return persistent_id.strip_edges()
	var scene_path: String = ""
	var scene_root: Node = get_tree().current_scene
	if scene_root != null:
		scene_path = scene_root.scene_file_path
	var local_path: String = str(get_path())
	return "%s|%s" % [scene_path, local_path]


func get_save_data() -> Dictionary:
	return {
		"loot_initialized": loot_initialized,
		"loot_slots": _serialize_item_array(loot_slots)
	}


func apply_save_data(save_data: Dictionary) -> void:
	is_opened = false
	loot_initialized = bool(save_data.get("loot_initialized", false))
	loot_slots = _deserialize_item_array(save_data.get("loot_slots", []))
	_set_loot_panel_state(false)
	_update_interact_label()


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
