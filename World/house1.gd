extends Node2D
const BuildingLoot = preload("res://World/Generation/building_loot_provider.gd")
const LootPersistence = preload("res://World/Generation/loot_container_persistence.gd")
const LootRestock = preload("res://World/Generation/loot_container_restock.gd")

const INSIDE_HOUSE_GROUP: StringName = &"inside_house"
const INSIDE_HOUSE_ANCHOR_META: StringName = &"inside_house_anchor"
const INSIDE_HOUSE_FLOOR_META: StringName = &"inside_house_floor"
const HOUSE_SCOPED_PICKUP_GROUP: StringName = &"house_scoped_pickup"
const ENEMY_GROUP: StringName = &"enemy"
const HOUSE_ENEMY_EJECT_MARGIN: float = 6.0
const HOUSE_EXIT_FAILSAFE_MARGIN: float = 12.0
const PLAYER_PRE_HOUSE_Z_INDEX_META: StringName = &"pre_house_z_index"
const PLAYER_PRE_HOUSE_Z_AS_RELATIVE_META: StringName = &"pre_house_z_as_relative"
const PLAYER_HOUSE_Z_INDEX: int = 2000
const INSIDE_HOUSE_Z: int = -1
const OUTSIDE_HOUSE_Z: int = 0
const DOOR_Z_INSIDE: int = 1
const DOOR_Z_OUTSIDE: int = 0
const HOUSE_SPAWN_MARKER_PREFIX: String = "SpawnMarker"
const ITEM_SPAWNER_GROUP: StringName = &"item_spawner_network"
const WorldGenerationBlockerUtils = preload("res://World/world_generation_blocker_utils.gd")

@onready var outside_sprite: Sprite2D = $HouseOutside
@onready var inside_sprite: Sprite2D = $HouseInside
@onready var house_area: Area2D = $HouseArea
@onready var house_area_collision: CollisionShape2D = $HouseArea/CollisionShape2D
@onready var shadow_area: Area2D = $ShadowArea
@onready var collision_outside: StaticBody2D = $CollisionOutside
@onready var collision_inside: StaticBody2D = $CollisionInside
@onready var door_closed_sprite: Sprite2D = $"Door'sSprites/Door"
@onready var door_closed_outline_sprite: Sprite2D = $"Door'sSprites/DoorOutline"
@onready var door_opened_sprite: Sprite2D = $"Door'sSprites/DoorOpened"
@onready var door_opened_outline_sprite: Sprite2D = $"Door'sSprites/DoorOutlineOpened"
@onready var door_area: Area2D = $DoorArea
@onready var door_blocker: CollisionShape2D = $DoorwayBlocker/CollisionShape2D
@onready var wardrobe_closed_sprite: Sprite2D = $WardrobeSprites/Wardrobe
@onready var wardrobe_outline_sprite: Sprite2D = $WardrobeSprites/WardrobeOutline
@onready var wardrobe_opened_outline_sprite: Sprite2D = $WardrobeSprites/WardrobeOpenedOutline
@onready var wardrobe_opened_sprite: Sprite2D = $WardrobeSprites/WardrobeOpened
@onready var wardrobe_area: Area2D = $WardrobeArea
@onready var interact_label: Label = $InteractLabel

@export_range(0.0, 1.0, 0.01) var outside_alpha_when_shadowed: float = 0.9
@export var interaction_distance: float = 52.0
@export var wardrobe_slot_count: int = 5
@export var wardrobe_spawn_min: int = 1
@export var wardrobe_spawn_max: int = 5
@export var wardrobe_food_pool: Array[ItemData] = [
	preload("res://Resources/Food/apple.tres"),
	preload("res://Resources/Food/tomate.tres"),
	preload("res://Resources/Food/pepper.tres"),
	preload("res://Resources/Food/eggplant.tres"),
	preload("res://Resources/Food/tushenka.tres"),
	preload("res://Resources/Food/konservirovannye_tomaty.tres"),
	preload("res://Resources/Food/malinovaya_gazirovka.tres"),
	preload("res://Resources/Food/nonster.tres")
]
@export var wardrobe_clothing_pool: Array[ItemData] = [
	preload("res://Resources/Clothes/jacket.tres"),
	preload("res://Resources/Clothes/trousers.tres"),
	preload("res://Resources/Clothes/kurtka_demisezonka.tres"),
	preload("res://Resources/Clothes/kurtka_sanitara.tres"),
	preload("res://Resources/Clothes/plash_palatka.tres"),
	preload("res://Resources/Clothes/rabochie_shtany.tres"),
	preload("res://Resources/Clothes/shtany_mehanika.tres"),
	preload("res://Resources/Clothes/shtany_sanitara.tres"),
	preload("res://Resources/Clothes/altyn_bt.tres")
]
@export var persistent_id: String = ""
@export var world_generated_mode := false
@export var building_generated_object_id := ""
@export var local_loot_container_id := "wardrobe_main"
@export var loot_profile: LootProfile = preload("res://Resources/WorldGen/Loot/house1_wardrobe_loot_profile.tres")
@export var loot_slot_ids: Array[String] = ["slot_00", "slot_01", "slot_02", "slot_03", "slot_04"]

var player_in_house: bool = false
var player_in_shadow_zone: bool = false
var player_near_door: bool = false
var player_near_wardrobe: bool = false
var door_opened: bool = false
var wardrobe_opened: bool = false
var wardrobe_loot_slots: Array[ItemData] = []
var wardrobe_loot_initialized: bool = false
var applied_loot_manifest: LootContainerManifest
var _loot_persistence_state := LootPersistence.STATE_UNOPENED
var _removed_loot_slot_ids: Array[String] = []
var legacy_random_path_used := false
var _loot_restock_state: Dictionary = {}
var _inside_player_ref: WeakRef = null


func _ready() -> void:
	if not world_generated_mode: randomize()
	add_to_group("primary_interactable")
	_configure_visual_layers()
	house_area.body_entered.connect(_on_house_body_entered)
	house_area.body_exited.connect(_on_house_body_exited)
	shadow_area.body_entered.connect(_on_shadow_body_entered)
	shadow_area.body_exited.connect(_on_shadow_body_exited)
	door_area.body_entered.connect(_on_door_area_body_entered)
	door_area.body_exited.connect(_on_door_area_body_exited)
	wardrobe_area.body_entered.connect(_on_wardrobe_area_body_entered)
	wardrobe_area.body_exited.connect(_on_wardrobe_area_body_exited)
	_update_house_visual()
	_update_door_visual()
	_update_wardrobe_visual()
	set_physics_process(false)
	_refresh_world_generation_blocker()
	call_deferred("_eject_current_overlapping_enemies")
	call_deferred("_spawn_world_pickups_at_markers_if_needed")
	var game_save_manager := _get_game_save_manager()
	if game_save_manager != null and game_save_manager.has_method("register_persistent_node"):
		game_save_manager.register_persistent_node(self)
	call_deferred("_restore_loot_restock_cycle")


func _refresh_world_generation_blocker() -> void:
	WorldGenerationBlockerUtils.configure_blocker(self, house_area)


func get_world_generation_blocker_rect() -> Rect2:
	return WorldGenerationBlockerUtils.build_area_rect(house_area)


func _eject_current_overlapping_enemies() -> void:
	if house_area == null:
		return

	for body in house_area.get_overlapping_bodies():
		_try_eject_enemy_from_house(body)


func _physics_process(_delta: float) -> void:
	if not player_in_house or _inside_player_ref == null:
		return
	var player_node := _inside_player_ref.get_ref() as Node2D
	if player_node == null or not is_instance_valid(player_node):
		_inside_player_ref = null
		set_physics_process(false)
		return
	if not _is_point_inside_house_area(player_node.global_position):
		_on_house_body_exited(player_node)


func _is_point_inside_house_area(global_point: Vector2) -> bool:
	for child in house_area.get_children():
		var collision_shape := child as CollisionShape2D
		if collision_shape == null or collision_shape.disabled or collision_shape.shape == null:
			continue
		var local_point := collision_shape.to_local(global_point)
		if collision_shape.shape is RectangleShape2D:
			var half_size := (collision_shape.shape as RectangleShape2D).size * 0.5
			half_size += Vector2.ONE * HOUSE_EXIT_FAILSAFE_MARGIN
			if Rect2(-half_size, half_size * 2.0).has_point(local_point):
				return true
	return false


func handle_primary_interaction(interactor: Node) -> bool:
	if interactor == null or not interactor.is_in_group("player"):
		return false

	if player_near_wardrobe and not wardrobe_opened:
		wardrobe_opened = true
		_ensure_wardrobe_loot()
		mark_loot_opened()
		_set_wardrobe_loot_panel_state(true)
		_update_wardrobe_visual()
		return true

	if not player_near_door:
		return false
	if not (interactor is Node2D):
		return false

	var player_node: Node2D = interactor as Node2D
	if door_area.global_position.distance_to(player_node.global_position) > max(interaction_distance, 1.0):
		return false

	door_opened = not door_opened
	_update_door_visual()
	return true


func _on_house_body_entered(body: Node) -> void:
	_try_eject_enemy_from_house(body)
	if not body.is_in_group("player"):
		return

	player_in_house = true
	_inside_player_ref = weakref(body)
	set_physics_process(true)
	if not body.is_in_group(INSIDE_HOUSE_GROUP):
		body.add_to_group(INSIDE_HOUSE_GROUP)
	body.set_meta(INSIDE_HOUSE_ANCHOR_META, global_position)
	body.set_meta(INSIDE_HOUSE_FLOOR_META, 1)
	if body is CanvasItem:
		(body as CanvasItem).modulate = Color(0.72, 0.72, 0.72, 1.0)
	if body is Node2D:
		_force_player_visible_in_house(body as Node2D)
	_update_house_visual()
	_update_wardrobe_visual()
	_refresh_house_pickups()


func _on_house_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	player_in_house = false
	_inside_player_ref = null
	set_physics_process(false)
	if body.is_in_group(INSIDE_HOUSE_GROUP):
		body.remove_from_group(INSIDE_HOUSE_GROUP)
	if body.has_meta(INSIDE_HOUSE_ANCHOR_META):
		body.remove_meta(INSIDE_HOUSE_ANCHOR_META)
	if body.has_meta(INSIDE_HOUSE_FLOOR_META):
		body.remove_meta(INSIDE_HOUSE_FLOOR_META)
	if body is CanvasItem:
		(body as CanvasItem).modulate = Color.WHITE
	if body is Node2D:
		_restore_player_visibility_state(body as Node2D)
	_set_wardrobe_loot_panel_state(false)
	_update_house_visual()
	_update_wardrobe_visual()
	_refresh_house_pickups()


func _force_player_visible_in_house(player_node: Node2D) -> void:
	if player_node == null:
		return
	if not player_node.has_meta(PLAYER_PRE_HOUSE_Z_INDEX_META):
		player_node.set_meta(PLAYER_PRE_HOUSE_Z_INDEX_META, player_node.z_index)
	if not player_node.has_meta(PLAYER_PRE_HOUSE_Z_AS_RELATIVE_META):
		player_node.set_meta(PLAYER_PRE_HOUSE_Z_AS_RELATIVE_META, player_node.z_as_relative)
	player_node.z_as_relative = false
	player_node.z_index = PLAYER_HOUSE_Z_INDEX


func _restore_player_visibility_state(player_node: Node2D) -> void:
	if player_node == null:
		return
	if player_node.has_meta(PLAYER_PRE_HOUSE_Z_INDEX_META):
		player_node.z_index = int(player_node.get_meta(PLAYER_PRE_HOUSE_Z_INDEX_META))
		player_node.remove_meta(PLAYER_PRE_HOUSE_Z_INDEX_META)
	if player_node.has_meta(PLAYER_PRE_HOUSE_Z_AS_RELATIVE_META):
		player_node.z_as_relative = bool(player_node.get_meta(PLAYER_PRE_HOUSE_Z_AS_RELATIVE_META))
		player_node.remove_meta(PLAYER_PRE_HOUSE_Z_AS_RELATIVE_META)


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


func _on_door_area_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	player_near_door = true
	_update_door_visual()
	_update_wardrobe_visual()


func _on_door_area_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	player_near_door = false
	_update_door_visual()
	_update_wardrobe_visual()


func _on_wardrobe_area_body_entered(body: Node) -> void:
	if not LootContainerProviderContract.is_local_interactor(body):
		return

	player_near_wardrobe = true
	_update_door_visual()
	_update_wardrobe_visual()


func _on_wardrobe_area_body_exited(body: Node) -> void:
	if not LootContainerProviderContract.is_local_interactor(body):
		return

	player_near_wardrobe = false
	wardrobe_opened = false
	_set_wardrobe_loot_panel_state(false)
	_update_wardrobe_visual()
	_update_door_visual()


func _update_house_visual() -> void:
	outside_sprite.visible = not player_in_house
	# Keep the interior below the facade so transparent door pixels reveal floor,
	# rather than the world terrain, while the player is outside.
	inside_sprite.visible = true
	if outside_sprite.visible:
		outside_sprite.modulate.a = outside_alpha_when_shadowed if player_in_shadow_zone else 1.0

	collision_outside.process_mode = Node.PROCESS_MODE_INHERIT if not player_in_house else Node.PROCESS_MODE_DISABLED
	collision_inside.process_mode = Node.PROCESS_MODE_INHERIT if player_in_house else Node.PROCESS_MODE_DISABLED
	_update_door_draw_order()


func _update_door_visual() -> void:
	door_closed_sprite.visible = not door_opened
	door_closed_outline_sprite.visible = player_near_door and not door_opened
	door_opened_sprite.visible = door_opened
	door_opened_outline_sprite.visible = player_near_door and door_opened
	door_blocker.set_deferred("disabled", door_opened)
	interact_label.text = "[E] - \u0437\u0430\u043A\u0440\u044B\u0442\u044C" if door_opened else "[E] - \u043E\u0442\u043A\u0440\u044B\u0442\u044C"
	interact_label.visible = player_near_door and not player_near_wardrobe


func _update_wardrobe_visual() -> void:
	if not player_in_house:
		wardrobe_closed_sprite.visible = false
		wardrobe_outline_sprite.visible = false
		wardrobe_opened_sprite.visible = false
		wardrobe_opened_outline_sprite.visible = false
		if not player_near_door:
			interact_label.visible = false
		return

	if not wardrobe_opened:
		wardrobe_closed_sprite.visible = not player_near_wardrobe
		wardrobe_outline_sprite.visible = player_near_wardrobe
		wardrobe_opened_sprite.visible = false
		wardrobe_opened_outline_sprite.visible = false
		interact_label.text = "[E] - \u043E\u0442\u043A\u0440\u044B\u0442\u044C"
		interact_label.visible = player_near_wardrobe
		return

	wardrobe_closed_sprite.visible = false
	wardrobe_outline_sprite.visible = false
	wardrobe_opened_sprite.visible = not player_near_wardrobe
	wardrobe_opened_outline_sprite.visible = player_near_wardrobe
	interact_label.text = ""
	interact_label.visible = false


func _update_door_draw_order() -> void:
	var target_z_index: int = DOOR_Z_INSIDE if player_in_house else DOOR_Z_OUTSIDE
	for sprite in [door_closed_sprite, door_closed_outline_sprite, door_opened_sprite, door_opened_outline_sprite]:
		if sprite == null:
			continue
		sprite.z_as_relative = true
		sprite.z_index = target_z_index


func _configure_visual_layers() -> void:
	if outside_sprite != null:
		outside_sprite.z_as_relative = true
		outside_sprite.z_index = OUTSIDE_HOUSE_Z
	if inside_sprite != null:
		inside_sprite.z_as_relative = true
		inside_sprite.z_index = INSIDE_HOUSE_Z


func _set_wardrobe_loot_panel_state(active: bool) -> void:
	var inventory_root: Node = get_tree().get_first_node_in_group("inventory_root")
	if inventory_root == null:
		return

	if active and inventory_root.has_method("open_loot_slots"):
		inventory_root.call("open_loot_slots", wardrobe_loot_slots, self)
	elif inventory_root.has_method("close_loot_for"):
		inventory_root.call("close_loot_for", self)


func _ensure_wardrobe_loot() -> void:
	if multiplayer.multiplayer_peer != null and not NetworkManager.is_server():
		return
	if wardrobe_loot_initialized:
		return
	if world_generated_mode:
		push_error("House1: world-generated wardrobe requires LootContainerManifest")
		return
	legacy_random_path_used = true

	if loot_profile != null:
		wardrobe_loot_slots = LootPopulationPass.roll_standalone_items(loot_profile, wardrobe_slot_count)
		wardrobe_loot_initialized = true
		return

	wardrobe_loot_initialized = true
	wardrobe_loot_slots.clear()
	wardrobe_loot_slots.resize(max(wardrobe_slot_count, 0))

	if wardrobe_slot_count <= 0:
		return

	var pool: Array[ItemData] = []
	for item in wardrobe_food_pool:
		if item != null:
			pool.append(item)
	for item in wardrobe_clothing_pool:
		if item != null:
			pool.append(item)
	if pool.is_empty():
		return

	var spawn_min: int = clamp(wardrobe_spawn_min, 1, wardrobe_slot_count)
	var spawn_max: int = clamp(wardrobe_spawn_max, spawn_min, wardrobe_slot_count)
	var spawn_count: int = randi_range(spawn_min, spawn_max)
	var free_indices: Array[int] = []
	for i in range(wardrobe_slot_count):
		free_indices.append(i)

	for _i in range(spawn_count):
		if free_indices.is_empty():
			break
		var free_pos: int = randi_range(0, free_indices.size() - 1)
		var slot_index: int = free_indices[free_pos]
		free_indices.remove_at(free_pos)
		var template_item: ItemData = pool[randi_range(0, pool.size() - 1)]
		if template_item != null:
			wardrobe_loot_slots[slot_index] = template_item.create_instance(1)

func get_loot_container_id() -> String:
	return BuildingLoot.derived_id(building_generated_object_id, local_loot_container_id) if world_generated_mode else ""
func get_loot_profile() -> LootProfile: return loot_profile
func get_existing_loot_manifest() -> LootContainerManifest: return applied_loot_manifest
func has_materialized_loot() -> bool: return wardrobe_loot_initialized
func get_loot_slot_bindings() -> Dictionary:
	var ids := loot_slot_ids.duplicate(); ids.sort(); var result := {}
	for index in range(ids.size()): result[ids[index]] = index
	return result
func apply_loot_manifest(manifest: LootContainerManifest) -> Dictionary:
	if not world_generated_mode or building_generated_object_id.is_empty() or local_loot_container_id.is_empty() or loot_profile == null: return {"valid":false,"errors":["INVALID_WORLD_GENERATED_PROVIDER"]}
	if applied_loot_manifest != null:
		return {"valid":applied_loot_manifest.manifest_hash() == manifest.manifest_hash(),"errors":[] if applied_loot_manifest.manifest_hash() == manifest.manifest_hash() else ["CONFLICTING_MANIFEST"]}
	var result: Dictionary = BuildingLoot.materialize(self, manifest, wardrobe_slot_count, wardrobe_loot_slots)
	if result.valid: applied_loot_manifest = manifest; wardrobe_loot_initialized = true
	return result

func get_loot_persistence_key() -> String: return LootPersistence.get_persistence_key(get_loot_container_id())
func get_loot_persistence_state() -> String: return _loot_persistence_state
func set_loot_persistence_state(state: String) -> void: _loot_persistence_state = state
func get_removed_loot_slot_ids() -> Array[String]: return _removed_loot_slot_ids.duplicate()
func serialize_loot_state() -> Dictionary: return LootPersistence.serialize_provider_state(self)
func restore_loot_state(data: Dictionary) -> Dictionary: return LootPersistence.restore_provider_state(self, data)
func mark_loot_opened() -> Dictionary:
	LootRestock.begin_open_cycle(self, _loot_restock_state, wardrobe_loot_slots)
	return LootPersistence.mark_opened(self)
func record_loot_slot_removed(slot_id: String) -> Dictionary: return LootPersistence.mark_slot_removed(self, slot_id)
func record_persisted_loot_slot_removal(slot_id: String) -> Dictionary:
	var bindings := get_loot_slot_bindings()
	if applied_loot_manifest == null or not bindings.has(slot_id) or not _manifest_has_slot(slot_id): return {"valid":false,"errors":["UNKNOWN_SLOT"]}
	if not _removed_loot_slot_ids.has(slot_id): _removed_loot_slot_ids.append(slot_id); _removed_loot_slot_ids.sort()
	wardrobe_loot_slots[int(bindings[slot_id])] = null; _loot_persistence_state = LootPersistence.STATE_PARTIALLY_EMPTIED
	return {"valid":true,"errors":[]}
func restore_persisted_loot_state(manifest: LootContainerManifest, state: String, removed: Array[String]) -> Dictionary:
	var result := BuildingLoot.restore_persisted_slots(self, applied_loot_manifest, manifest, wardrobe_slot_count, removed)
	if not result.valid: return result
	wardrobe_loot_slots = result.slots; applied_loot_manifest = manifest; wardrobe_loot_initialized = true; _removed_loot_slot_ids = removed.duplicate(); _loot_persistence_state = state; wardrobe_opened = false
	_set_wardrobe_loot_panel_state(false); _update_wardrobe_visual(); return {"valid":true,"errors":[]}
func _manifest_has_slot(slot_id: String) -> bool:
	for record in applied_loot_manifest.slots:
		if record.slot_id == slot_id: return true
	return false


func _spawn_world_pickups_at_markers_if_needed() -> void:
	if Engine.is_editor_hint():
		return

	var item_spawner := _find_item_spawner()
	if item_spawner == null or not item_spawner.has_method("spawn_random_world_pickup_at_position"):
		return

	for marker in _collect_spawn_markers(self):
		item_spawner.call(
			"spawn_random_world_pickup_at_position",
			marker.global_position,
			_build_spawn_marker_runtime_id(marker),
			_build_pickup_visibility_scope()
		)


func _build_pickup_visibility_scope() -> Dictionary:
	return {
		"anchor": {"x": global_position.x, "y": global_position.y},
		"floor": 1
	}


func _refresh_house_pickups() -> void:
	for pickup in get_tree().get_nodes_in_group(HOUSE_SCOPED_PICKUP_GROUP):
		if pickup != null and pickup.has_method("refresh_visibility_scope"):
			pickup.call("refresh_visibility_scope")


func _collect_spawn_markers(root: Node) -> Array[Marker2D]:
	var markers: Array[Marker2D] = []
	if root == null:
		return markers

	for child in root.get_children():
		if child is Marker2D and String(child.name).begins_with(HOUSE_SPAWN_MARKER_PREFIX):
			markers.append(child as Marker2D)
		markers.append_array(_collect_spawn_markers(child))

	return markers


func _find_item_spawner() -> Node:
	var scene_tree := get_tree()
	if scene_tree == null:
		return null

	for candidate in scene_tree.get_nodes_in_group(ITEM_SPAWNER_GROUP):
		var node := candidate as Node
		if node != null and is_instance_valid(node):
			return node
	return null


func _build_spawn_marker_runtime_id(marker: Marker2D) -> String:
	return "%s:%s" % [_build_spawn_marker_seed_key(), String(get_path_to(marker))]


func _build_spawn_marker_seed_key() -> String:
	if has_meta("world_generation_id"):
		return str(get_meta("world_generation_id"))
	return get_save_key()


func get_save_key() -> String:
	return "house1:%s" % [_get_persistent_identity()]


func get_legacy_save_keys() -> Array[String]:
	return ["house1:%s" % [str(global_position)]]


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
	if not LootRestock.is_restock_due(self, _loot_restock_state, wardrobe_loot_slots, total_minutes): return
	var stable_id := get_loot_container_id() if world_generated_mode else _get_persistent_identity()
	LootRestock.top_up_empty_slots(self, loot_profile, wardrobe_loot_slots, wardrobe_slot_count, stable_id, total_minutes)
	_removed_loot_slot_ids.clear(); _loot_persistence_state = LootPersistence.STATE_OPENED
	LootRestock.finish_cycle(self, _loot_restock_state); LootRestock.notify_network_state(self)
	var inventory_root := get_tree().get_first_node_in_group("inventory_root")
	if inventory_root != null and inventory_root.has_method("refresh_ui"): inventory_root.call("refresh_ui")


func get_save_data() -> Dictionary:
	return {
		"door_opened": door_opened,
		"wardrobe_loot_initialized": wardrobe_loot_initialized,
		"wardrobe_loot_slots": _serialize_item_array(wardrobe_loot_slots),
		"loot_restock_state": LootRestock.serialize_cycle(_loot_restock_state, wardrobe_loot_slots)
	}


func apply_save_data(save_data: Dictionary) -> void:
	door_opened = bool(save_data.get("door_opened", false))
	wardrobe_opened = false
	wardrobe_loot_initialized = bool(save_data.get("wardrobe_loot_initialized", false))
	wardrobe_loot_slots = _deserialize_item_array(save_data.get("wardrobe_loot_slots", []))
	_loot_restock_state = save_data.get("loot_restock_state", {}).duplicate(true)
	_set_wardrobe_loot_panel_state(false)
	_update_house_visual()
	_update_door_visual()
	_update_wardrobe_visual()
	call_deferred("_restore_loot_restock_cycle")


func _serialize_item_array(items: Array) -> Array:
	var out: Array = []
	var game_save_manager := _get_game_save_manager()
	for item in items:
		if item == null:
			out.append(null)
		elif game_save_manager != null and game_save_manager.has_method("serialize_item"):
			out.append(game_save_manager.serialize_item(item))
		else:
			out.append({})
	return out


func _deserialize_item_array(raw_items: Variant) -> Array[ItemData]:
	var out: Array[ItemData] = []
	var game_save_manager := _get_game_save_manager()
	if not (raw_items is Array):
		return out
	for raw_item in raw_items:
		if raw_item == null:
			out.append(null)
		elif game_save_manager != null and game_save_manager.has_method("deserialize_item"):
			out.append(game_save_manager.deserialize_item(raw_item))
		else:
			out.append(null)
	return out


func _get_game_save_manager() -> Node:
	return get_node_or_null("/root/GameSaveManager")


func get_network_loot_items() -> Array[ItemData]:
	_ensure_wardrobe_loot()
	return wardrobe_loot_slots
