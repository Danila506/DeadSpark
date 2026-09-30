extends Node2D
const BuildingLoot = preload("res://World/Generation/building_loot_provider.gd")
const BUNKER_EMPTY_PROFILE = preload("res://Resources/WorldGen/bunker_empty_loot_profile.tres")
const LootPersistence = preload("res://World/Generation/loot_container_persistence.gd")
const LootRestock = preload("res://World/Generation/loot_container_restock.gd")

const INSIDE_HOUSE_GROUP: StringName = &"inside_house"
const INSIDE_HOUSE_ANCHOR_META: StringName = &"inside_house_anchor"
const ENEMY_GROUP: StringName = &"enemy"
const HOUSE_ENEMY_EJECT_MARGIN: float = 6.0
const PLAYER_PRE_BUNKER_Z_INDEX_META: StringName = &"pre_bunker_z_index"
const PLAYER_PRE_BUNKER_Z_AS_RELATIVE_META: StringName = &"pre_bunker_z_as_relative"
const PLAYER_BUNKER_Z_INDEX: int = 2000
const INSIDE_BUNKER_Z: int = -1
const OUTSIDE_BUNKER_Z: int = 0
const BUNKER_SPAWN_MARKER_PREFIX: String = "SpawnMarker"
const ITEM_SPAWNER_GROUP: StringName = &"item_spawner_network"
const WorldGenerationBlockerUtils = preload("res://World/world_generation_blocker_utils.gd")

@onready var outside_sprite: Sprite2D = $BunkerOutside
@onready var inside_sprite: Sprite2D = $BunkerInside
@onready var house_area: Area2D = get_node_or_null("BunkerArea") as Area2D
@onready var house_area_collision: CollisionShape2D = get_node_or_null("BunkerArea/CollisionShape2D") as CollisionShape2D
@onready var shadow_area: Area2D = $ShadowArea
@onready var collision_outside: StaticBody2D = $CollisionOutside
@onready var collision_inside: StaticBody2D = $CollisionInside
@onready var box_closed_sprite: Sprite2D = $BunkerInside/BunkerBox
@onready var box_closed_outline_sprite: Sprite2D = $BunkerInside/BunkerBoxOutline
@onready var box_opened_sprite: Sprite2D = $BunkerInside/BunkerBoxOpened
@onready var box_opened_outline_sprite: Sprite2D = $BunkerInside/BunkerBoxOpenedOutline
@onready var box_area: Area2D = $BunkerInside/BoxArea
@onready var interact_label: Label = $BunkerInside/InteractLabel

@export_range(0.0, 1.0, 0.01) var outside_alpha_when_inside: float = 0.28
@export_range(0.0, 1.0, 0.01) var outside_alpha_when_shadowed: float = 1.0
@export var interaction_distance: float = 50.0
@export var box_slot_count: int = 3
@export_range(0.0, 1.0, 0.01) var generated_box_chance: float = 0.5
@export var box_spawn_min: int = 0
@export var box_spawn_max: int = 0
@export var guaranteed_items: Array[ItemData] = []
@export var loot_pool: Array[ItemData] = []
@export var persistent_id: String = ""
@export var world_generated_mode := false
@export var building_generated_object_id := ""
@export var local_loot_container_id := "bunker_box_main"
@export var loot_profile: LootProfile = preload("res://Resources/WorldGen/Loot/bunker_loot_profile.tres")
@export var loot_slot_ids: Array[String] = ["slot_00", "slot_01", "slot_02"]

var player_in_house: bool = false
var player_in_shadow_zone: bool = false
var player_near_box: bool = false
var box_opened: bool = false
var loot_initialized: bool = false
var loot_slots: Array[ItemData] = []
var applied_loot_manifest: LootContainerManifest
var _loot_persistence_state := LootPersistence.STATE_UNOPENED
var _removed_loot_slot_ids: Array[String] = []
var legacy_random_path_used := false
var _loot_restock_state: Dictionary = {}
var box_present: bool = true
var _generated_content_seed: int = 0


func _ready() -> void:
	if not world_generated_mode: randomize()
	if house_area == null:
		house_area = $HouseArea
	if house_area_collision == null:
		house_area_collision = $HouseArea/CollisionShape2D
	add_to_group("primary_interactable")
	_configure_visual_layers()
	_apply_box_presence()
	house_area.body_entered.connect(_on_house_body_entered)
	house_area.body_exited.connect(_on_house_body_exited)
	shadow_area.body_entered.connect(_on_shadow_body_entered)
	shadow_area.body_exited.connect(_on_shadow_body_exited)
	box_area.body_entered.connect(_on_box_area_body_entered)
	box_area.body_exited.connect(_on_box_area_body_exited)
	_update_house_visual()
	_update_box_visual()
	set_physics_process(false)
	_refresh_world_generation_blocker()
	call_deferred("_eject_current_overlapping_enemies")
	if GameSaveManager != null and GameSaveManager.has_method("register_persistent_node"):
		GameSaveManager.register_persistent_node(self)
	call_deferred("_restore_loot_restock_cycle")
	call_deferred("_spawn_world_pickups_at_markers_if_needed")


func _refresh_world_generation_blocker() -> void:
	WorldGenerationBlockerUtils.configure_blocker(self, house_area)


func get_world_generation_blocker_rect() -> Rect2:
	return WorldGenerationBlockerUtils.build_area_rect(house_area)


func _eject_current_overlapping_enemies() -> void:
	if house_area == null:
		return

	for body in house_area.get_overlapping_bodies():
		_try_eject_enemy_from_house(body)


func handle_primary_interaction(interactor: Node) -> bool:
	if not box_present:
		return false
	if interactor == null or not interactor.is_in_group("player"):
		return false
	if not player_near_box:
		return false
	if box_opened:
		return false
	if not (interactor is Node2D):
		return false

	var player_node: Node2D = interactor as Node2D
	if box_area.global_position.distance_to(player_node.global_position) > max(interaction_distance, 1.0):
		return false

	box_opened = true
	_ensure_loot()
	mark_loot_opened()
	_set_loot_panel_state(true)
	_update_box_visual()
	return true


func _on_house_body_entered(body: Node) -> void:
	_try_eject_enemy_from_house(body)
	if not body.is_in_group("player"):
		return

	player_in_house = true
	if not body.is_in_group(INSIDE_HOUSE_GROUP):
		body.add_to_group(INSIDE_HOUSE_GROUP)
	body.set_meta(INSIDE_HOUSE_ANCHOR_META, global_position)
	if body is CanvasItem:
		(body as CanvasItem).modulate = Color(0.72, 0.72, 0.72, 1.0)
	if body is Node2D:
		_force_player_visible_in_bunker(body as Node2D)
	_update_house_visual()


func _on_house_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	player_in_house = false
	if body.is_in_group(INSIDE_HOUSE_GROUP):
		body.remove_from_group(INSIDE_HOUSE_GROUP)
	if body.has_meta(INSIDE_HOUSE_ANCHOR_META):
		body.remove_meta(INSIDE_HOUSE_ANCHOR_META)
	if body is CanvasItem:
		(body as CanvasItem).modulate = Color.WHITE
	if body is Node2D:
		_restore_player_visibility_state(body as Node2D)
	_update_house_visual()


func _force_player_visible_in_bunker(player_node: Node2D) -> void:
	if player_node == null:
		return
	if not player_node.has_meta(PLAYER_PRE_BUNKER_Z_INDEX_META):
		player_node.set_meta(PLAYER_PRE_BUNKER_Z_INDEX_META, player_node.z_index)
	if not player_node.has_meta(PLAYER_PRE_BUNKER_Z_AS_RELATIVE_META):
		player_node.set_meta(PLAYER_PRE_BUNKER_Z_AS_RELATIVE_META, player_node.z_as_relative)
	player_node.z_as_relative = false
	player_node.z_index = PLAYER_BUNKER_Z_INDEX


func _restore_player_visibility_state(player_node: Node2D) -> void:
	if player_node == null:
		return
	if player_node.has_meta(PLAYER_PRE_BUNKER_Z_INDEX_META):
		player_node.z_index = int(player_node.get_meta(PLAYER_PRE_BUNKER_Z_INDEX_META))
		player_node.remove_meta(PLAYER_PRE_BUNKER_Z_INDEX_META)
	if player_node.has_meta(PLAYER_PRE_BUNKER_Z_AS_RELATIVE_META):
		player_node.z_as_relative = bool(player_node.get_meta(PLAYER_PRE_BUNKER_Z_AS_RELATIVE_META))
		player_node.remove_meta(PLAYER_PRE_BUNKER_Z_AS_RELATIVE_META)


func _try_eject_enemy_from_house(body: Node) -> void:
	if body == null:
		return
	if not body.is_in_group(ENEMY_GROUP):
		return
	if not (body is Node2D):
		return
	if house_area_collision == null:
		return
	if not (house_area_collision.shape is RectangleShape2D):
		return

	var enemy_node: Node2D = body as Node2D
	var rect_shape: RectangleShape2D = house_area_collision.shape as RectangleShape2D
	var house_local_pos: Vector2 = to_local(enemy_node.global_position)
	var center: Vector2 = house_area_collision.position
	var half_extents: Vector2 = rect_shape.size * 0.5
	var relative: Vector2 = house_local_pos - center

	if abs(relative.x) > half_extents.x or abs(relative.y) > half_extents.y:
		return

	var penetration_x: float = half_extents.x - abs(relative.x)
	var penetration_y: float = half_extents.y - abs(relative.y)
	if penetration_x < penetration_y:
		relative.x = (1.0 if relative.x >= 0.0 else -1.0) * (half_extents.x + HOUSE_ENEMY_EJECT_MARGIN)
	else:
		relative.y = (1.0 if relative.y >= 0.0 else -1.0) * (half_extents.y + HOUSE_ENEMY_EJECT_MARGIN)

	enemy_node.global_position = to_global(center + relative)
	if "velocity" in enemy_node:
		enemy_node.velocity = Vector2.ZERO


func _on_shadow_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	player_in_shadow_zone = true
	_update_house_visual()


func _on_shadow_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	player_in_shadow_zone = false
	_update_house_visual()


func _on_box_area_body_entered(body: Node) -> void:
	if not LootContainerProviderContract.is_local_interactor(body):
		return

	player_near_box = true
	_update_box_visual()


func _on_box_area_body_exited(body: Node) -> void:
	if not LootContainerProviderContract.is_local_interactor(body):
		return

	player_near_box = false
	box_opened = false
	_set_loot_panel_state(false)
	_update_box_visual()


func _update_house_visual() -> void:
	outside_sprite.visible = true
	if player_in_house:
		outside_sprite.modulate.a = outside_alpha_when_inside
	elif player_in_shadow_zone:
		outside_sprite.modulate.a = outside_alpha_when_shadowed
	else:
		outside_sprite.modulate.a = 1.0
	# The entrance is transparent in the exterior texture, so the authored
	# interior must remain as an underlay even while the player is outside.
	inside_sprite.visible = true
	collision_outside.process_mode = Node.PROCESS_MODE_INHERIT
	collision_inside.process_mode = Node.PROCESS_MODE_INHERIT


func _configure_visual_layers() -> void:
	inside_sprite.z_as_relative = true
	inside_sprite.z_index = INSIDE_BUNKER_Z
	outside_sprite.z_as_relative = true
	outside_sprite.z_index = OUTSIDE_BUNKER_Z


func _update_box_visual() -> void:
	if not box_present:
		box_closed_sprite.visible = false
		box_closed_outline_sprite.visible = false
		box_opened_sprite.visible = false
		box_opened_outline_sprite.visible = false
		interact_label.visible = false
		return
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
		inventory_root.call("open_loot_slots", loot_slots, self)
	elif inventory_root.has_method("close_loot_for"):
		inventory_root.call("close_loot_for", self)


func _ensure_loot() -> void:
	if multiplayer.multiplayer_peer != null and not NetworkManager.is_server():
		return
	if loot_initialized:
		return
	if not box_present:
		loot_initialized = true
		loot_slots.clear()
		loot_slots.resize(maxi(box_slot_count, 0))
		return
	if world_generated_mode:
		push_error("Bunker: world-generated box requires LootContainerManifest")
		return
	legacy_random_path_used = true

	if loot_profile != null:
		loot_slots = LootPopulationPass.roll_standalone_items(loot_profile, box_slot_count)
		loot_initialized = true
		return

	loot_initialized = true
	loot_slots.clear()
	loot_slots.resize(max(box_slot_count, 0))

	if box_slot_count <= 0:
		return

	var effective_loot_pool: Array[ItemData] = _get_effective_loot_pool()
	var min_spawn_source: int = box_spawn_min
	if min_spawn_source <= 0:
		min_spawn_source = 1
	var min_spawn: int = clamp(min_spawn_source, 0, box_slot_count)
	var max_spawn_source: int = box_spawn_max
	if max_spawn_source <= 0:
		max_spawn_source = box_slot_count
	var max_spawn: int = clamp(max_spawn_source, min_spawn, box_slot_count)

	var free_indices: Array[int] = []
	for i in range(box_slot_count):
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

	if effective_loot_pool.is_empty() or free_indices.is_empty():
		return

	var spawn_count: int = randi_range(min_spawn, max_spawn)
	spawn_count = min(spawn_count, free_indices.size())
	for _i in range(spawn_count):
		if free_indices.is_empty():
			break

		var free_pos: int = randi_range(0, free_indices.size() - 1)
		var slot_index: int = free_indices[free_pos]
		free_indices.remove_at(free_pos)

		var template_item: ItemData = effective_loot_pool[randi_range(0, effective_loot_pool.size() - 1)]
		if template_item == null:
			continue

		var item_instance: ItemData = template_item.create_instance(1)
		loot_slots[slot_index] = item_instance

func get_loot_container_id() -> String: return BuildingLoot.derived_id(building_generated_object_id, local_loot_container_id) if world_generated_mode else ""
func get_loot_profile() -> LootProfile: return loot_profile if box_present else BUNKER_EMPTY_PROFILE
func get_existing_loot_manifest() -> LootContainerManifest: return applied_loot_manifest
func has_materialized_loot() -> bool: return loot_initialized
func get_loot_slot_bindings() -> Dictionary:
	var ids := loot_slot_ids.duplicate(); ids.sort(); var result := {}
	for index in range(ids.size()): result[ids[index]] = index
	return result
func apply_loot_manifest(manifest: LootContainerManifest) -> Dictionary:
	var active_profile := get_loot_profile()
	if not world_generated_mode or building_generated_object_id.is_empty() or local_loot_container_id.is_empty() or active_profile == null: return {"valid":false,"errors":["INVALID_BUNKER_PROVIDER"]}
	if applied_loot_manifest != null: return {"valid":applied_loot_manifest.manifest_hash()==manifest.manifest_hash(),"errors":[] if applied_loot_manifest.manifest_hash()==manifest.manifest_hash() else ["CONFLICTING_MANIFEST"]}
	var result: Dictionary = BuildingLoot.materialize(self,manifest,box_slot_count,loot_slots)
	if result.valid and active_profile.explicit_empty and not loot_slots.filter(func(item): return item != null).is_empty(): return {"valid":false,"errors":["EMPTY_PROFILE_MATERIALIZED_LOOT"]}
	if result.valid: applied_loot_manifest=manifest; loot_initialized=true
	return result

func get_loot_persistence_key() -> String: return LootPersistence.get_persistence_key(get_loot_container_id())
func get_loot_persistence_state() -> String: return _loot_persistence_state
func set_loot_persistence_state(state: String) -> void: _loot_persistence_state = state
func get_removed_loot_slot_ids() -> Array[String]: return _removed_loot_slot_ids.duplicate()
func serialize_loot_state() -> Dictionary: return LootPersistence.serialize_provider_state(self)
func restore_loot_state(data: Dictionary) -> Dictionary: return LootPersistence.restore_provider_state(self, data)
func mark_loot_opened() -> Dictionary:
	LootRestock.begin_open_cycle(self, _loot_restock_state, loot_slots)
	return LootPersistence.mark_opened(self)
func record_loot_slot_removed(slot_id: String) -> Dictionary:
	return LootPersistence.mark_slot_removed(self, slot_id)
func record_persisted_loot_slot_removal(slot_id: String) -> Dictionary:
	if applied_loot_manifest == null: return {"valid": false, "errors": ["UNKNOWN_SLOT"]}
	var found := false
	for record in applied_loot_manifest.slots:
		if record.slot_id == slot_id: found = true; break
	if not found: return {"valid": false, "errors": ["UNKNOWN_SLOT"]}
	if not _removed_loot_slot_ids.has(slot_id): _removed_loot_slot_ids.append(slot_id)
	loot_slots[int(get_loot_slot_bindings()[slot_id])] = null
	_loot_persistence_state = LootPersistence.STATE_PARTIALLY_EMPTIED
	return {"valid": true, "errors": []}
func restore_persisted_loot_state(manifest: LootContainerManifest, state: String, removed: Array[String]) -> Dictionary:
	var active_profile := get_loot_profile()
	if active_profile.explicit_empty and (state == LootPersistence.STATE_PARTIALLY_EMPTIED or not removed.is_empty()): return {"valid":false,"errors":["EMPTY_PROFILE_NO_REMOVABLE_SLOTS"]}
	var result := BuildingLoot.restore_persisted_slots(self, applied_loot_manifest, manifest, box_slot_count, removed, active_profile.explicit_empty)
	if not result.valid: return result
	loot_slots = result.slots; applied_loot_manifest = manifest; loot_initialized = true; _removed_loot_slot_ids = removed.duplicate(); _loot_persistence_state = state; box_opened = false
	_set_loot_panel_state(false); _update_box_visual(); return {"valid":true,"errors":[]}


func configure_generated_content(master_seed: int) -> void:
	_generated_content_seed = master_seed
	var roll := posmod(
		WorldSeedService.derive_seed(master_seed, "bunker/box-presence/%s" % building_generated_object_id),
		1000000
	)
	box_present = roll < int(round(clampf(generated_box_chance, 0.0, 1.0) * 1000000.0))
	if is_node_ready(): _apply_box_presence()


func _apply_box_presence() -> void:
	if box_area == null: return
	box_area.monitoring = box_present
	box_area.monitorable = box_present
	var box_collision := box_area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if box_collision != null: box_collision.set_deferred("disabled", not box_present)
	var solid_box_collision: CollisionShape2D = null
	if collision_inside != null:
		solid_box_collision = collision_inside.get_node_or_null("Box") as CollisionShape2D
	if solid_box_collision != null: solid_box_collision.set_deferred("disabled", not box_present)
	if not box_present:
		player_near_box = false
		box_opened = false
		_set_loot_panel_state(false)
	_update_box_visual()


func _spawn_world_pickups_at_markers_if_needed() -> void:
	if Engine.is_editor_hint(): return
	var item_spawner := _find_item_spawner()
	if item_spawner == null or not item_spawner.has_method("spawn_world_pickup_at_position"): return
	var seed := _generated_content_seed if world_generated_mode else LootRestock.world_seed(self)
	for marker in _collect_spawn_markers(self):
		var runtime_id := "%s:%s" % [_build_spawn_marker_seed_key(), String(get_path_to(marker))]
		var item := LootPopulationPass.select_item_definition(loot_profile, seed, runtime_id)
		if item == null: continue
		item_spawner.call(
			"spawn_world_pickup_at_position",
			item,
			marker.global_position,
			runtime_id,
			_build_pickup_visibility_scope()
		)


func _collect_spawn_markers(root: Node) -> Array[Marker2D]:
	var markers: Array[Marker2D] = []
	if root == null: return markers
	for child in root.get_children():
		if child is Marker2D and String(child.name).begins_with(BUNKER_SPAWN_MARKER_PREFIX):
			markers.append(child as Marker2D)
		markers.append_array(_collect_spawn_markers(child))
	return markers


func _build_spawn_marker_seed_key() -> String:
	if has_meta("world_generation_id"): return str(get_meta("world_generation_id"))
	return get_save_key()


func _build_pickup_visibility_scope() -> Dictionary:
	return {"anchor": {"x": global_position.x, "y": global_position.y}, "floor": 1}


func _get_effective_loot_pool() -> Array[ItemData]:
	var effective_pool: Array[ItemData] = []
	for item in loot_pool:
		if item != null:
			effective_pool.append(item)
	if not effective_pool.is_empty():
		return effective_pool

	var item_spawner := _find_item_spawner()
	if item_spawner != null and item_spawner.has_method("get_valid_world_spawn_items"):
		var fallback_items: Variant = item_spawner.call("get_valid_world_spawn_items")
		if fallback_items is Array:
			for item_variant in fallback_items:
				var item := item_variant as ItemData
				if item != null:
					effective_pool.append(item)
	return effective_pool


func _find_item_spawner() -> Node:
	var scene_tree := get_tree()
	if scene_tree == null:
		return null
	for candidate in scene_tree.get_nodes_in_group(ITEM_SPAWNER_GROUP):
		var node := candidate as Node
		if node != null and is_instance_valid(node):
			return node
	return null


func get_save_key() -> String:
	return "bunker:%s" % [_get_persistent_identity()]


func get_legacy_save_keys() -> Array[String]:
	return ["bunker:%s" % [str(global_position)]]


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
	if not box_present: return
	if not LootRestock.is_restock_due(self, _loot_restock_state, loot_slots, total_minutes): return
	var stable_id := get_loot_container_id() if world_generated_mode else _get_persistent_identity()
	LootRestock.top_up_empty_slots(self, loot_profile, loot_slots, box_slot_count, stable_id, total_minutes)
	_removed_loot_slot_ids.clear(); _loot_persistence_state = LootPersistence.STATE_OPENED
	LootRestock.finish_cycle(self, _loot_restock_state); LootRestock.notify_network_state(self)
	var inventory_root := get_tree().get_first_node_in_group("inventory_root")
	if inventory_root != null and inventory_root.has_method("refresh_ui"): inventory_root.call("refresh_ui")


func get_save_data() -> Dictionary:
	return {
		"box_present": box_present,
		"loot_initialized": loot_initialized,
		"loot_slots": _serialize_item_array(loot_slots),
		"loot_restock_state": LootRestock.serialize_cycle(_loot_restock_state, loot_slots)
	}


func apply_save_data(save_data: Dictionary) -> void:
	box_present = bool(save_data.get("box_present", box_present))
	box_opened = false
	loot_initialized = bool(save_data.get("loot_initialized", false))
	loot_slots = _deserialize_item_array(save_data.get("loot_slots", []))
	_loot_restock_state = save_data.get("loot_restock_state", {}).duplicate(true)
	_set_loot_panel_state(false)
	_update_house_visual()
	_apply_box_presence()
	_update_box_visual()
	call_deferred("_restore_loot_restock_cycle")


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
