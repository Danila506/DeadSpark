extends Node2D
const ITEM_INSTANCE_SCRIPT = preload("res://items/scripts/item_instance.gd")

@export var pickup_scene: PackedScene
@export var possible_items: Array[ItemData]
@export var spawn_count: int = 3
@export var force_include_ts39_scope: bool = false
@export var force_include_craft_test_items: bool = false
@export var include_new_craft_materials_in_world_spawn: bool = true
@export var spawn_all_possible_items_near_player: bool = false
@export var spawn_all_item_resources_from_resources: bool = false
@export var spawn_all_resources_root: String = "res://Resources"
@export var spawn_all_near_player_spacing: float = 56.0
@export var spawn_all_near_player_offset: Vector2 = Vector2(120.0, 0.0)
@export var spawn_starter_items_near_player: bool = false
@export var starter_items_near_player_spacing: float = 52.0
@export var starter_items_near_player_offset: Vector2 = Vector2(120.0, 72.0)

const TS_39_SCOPE_RESOURCE: ItemData = preload("res://Resources/AR_Weapons/akp_52/TS_39.tres")
const AKP_103_RESOURCE: ItemData = preload("res://Resources/AR_Weapons/akp_103/akp_103.tres")
const AKP_207_RESOURCE: ItemData = preload("res://Resources/AR_Weapons/akp_207/akp_207.tres")
const AKP_52_RESOURCE: ItemData = preload("res://Resources/AR_Weapons/akp_52/akp_52.tres")
const AKP_52_AMMO_RESOURCE: ItemData = preload("res://Resources/AR_Weapons/akp_52/ammo_boxAkp52.tres")
const FN_S_RESOURCE: ItemData = preload("res://Resources/Pistols/fn-s/fn-s.tres")
const AXE_RESOURCE: ItemData = preload("res://Resources/Melee/axe.tres")
const CLEAVER_RESOURCE: ItemData = preload("res://Resources/Misc/cleaver.tres")
const BANDAGE_RESOURCE: ItemData = preload("res://Resources/Medicine/bandage.tres")
const WOOD_RESOURCE: ItemData = preload("res://Resources/Misc/wood.tres")
const STONE_RESOURCE: ItemData = preload("res://Resources/Misc/stone.tres")
const BAG_RESOURCE: ItemData = preload("res://Resources/Clothes/bag.tres")
const MATCHES_RESOURCE: ItemData = preload("res://Resources/Misc/matches.tres")
const ROPE_RESOURCE: ItemData = preload("res://Resources/Misc/rope.tres")
const LIGHTER_RESOURCE: ItemData = preload("res://Resources/Misc/lighter.tres")
const CIGARETTES_PACK_RESOURCE: ItemData = preload("res://Resources/Misc/cigarettes_pack.tres")
const GAS_CYLINDER_RESOURCE: ItemData = preload("res://Resources/Misc/gas_cylinder.tres")
const BATTERIES_RESOURCE: ItemData = preload("res://Resources/Misc/batteries.tres")
const ELECTRICAL_TAPE_RESOURCE: ItemData = preload("res://Resources/Misc/electrical_tape.tres")
const BURLAP_FABRIC_RESOURCE: ItemData = preload("res://Resources/Misc/burlap_fabric.tres")
const GAS_BURNER_RESOURCE: ItemData = preload("res://Resources/Misc/gas_burner.tres")
const SEWING_KIT_RESOURCE: ItemData = preload("res://Resources/Misc/sewing_kit.tres")
const GLUE_RESOURCE: ItemData = preload("res://Resources/Misc/glue.tres")
const WEAPON_CLEANING_KIT_RESOURCE: ItemData = preload("res://Resources/Misc/weapon_cleaning_kit.tres")
const GEIGER_COUNTER_RESOURCE: ItemData = preload("res://Resources/Misc/geiger_counter.tres")
const TUSHENKA_RESOURCE: ItemData = preload("res://Resources/Food/tushenka.tres")
const CANNED_TOMATOES_RESOURCE: ItemData = preload("res://Resources/Food/konservirovannye_tomaty.tres")
const RASPBERRY_SODA_RESOURCE: ItemData = preload("res://Resources/Food/malinovaya_gazirovka.tres")
const NONSTER_RESOURCE: ItemData = preload("res://Resources/Food/nonster.tres")

const FORCED_CRAFT_TEST_ITEMS: Array[ItemData] = [
	BAG_RESOURCE,
	AXE_RESOURCE,
	BANDAGE_RESOURCE,
	BANDAGE_RESOURCE,
	WOOD_RESOURCE,
	WOOD_RESOURCE,
	STONE_RESOURCE
]

const NEW_CRAFT_MATERIAL_ITEMS: Array[ItemData] = [
	MATCHES_RESOURCE,
	ROPE_RESOURCE,
	LIGHTER_RESOURCE,
	CIGARETTES_PACK_RESOURCE,
	GAS_CYLINDER_RESOURCE,
	BATTERIES_RESOURCE,
	ELECTRICAL_TAPE_RESOURCE,
	BURLAP_FABRIC_RESOURCE,
	GAS_BURNER_RESOURCE,
	SEWING_KIT_RESOURCE,
	GLUE_RESOURCE,
	WEAPON_CLEANING_KIT_RESOURCE,
	GEIGER_COUNTER_RESOURCE
]

const NEW_FOOD_ITEMS: Array[ItemData] = [
	TUSHENKA_RESOURCE,
	CANNED_TOMATOES_RESOURCE,
	RASPBERRY_SODA_RESOURCE,
	NONSTER_RESOURCE
]

const EXCLUDED_WORLD_SPAWN_RESOURCE_PATHS: Dictionary = {
	"res://Resources/Medicine/medicalKit.tres": true,
	"res://Resources/Misc/stone.tres": true
}

const GUARANTEED_WORLD_WEAPON_ITEMS: Array[ItemData] = [
	AKP_103_RESOURCE,
	AKP_207_RESOURCE
]

const STARTER_NEAR_PLAYER_ITEMS: Array[ItemData] = [
	AKP_103_RESOURCE,
	AKP_207_RESOURCE,
	AKP_52_RESOURCE,
	AKP_52_AMMO_RESOURCE,
	FN_S_RESOURCE,
	AXE_RESOURCE,
	CLEAVER_RESOURCE,
	BANDAGE_RESOURCE
]

var rng := RandomNumberGenerator.new()
var _spawn_all_completed: bool = false
var _world_items_spawned: bool = false
var _starter_items_spawned: bool = false

func _ready() -> void:
	add_to_group("item_spawner_network")
	rng.randomize()
	_ensure_special_scope_items()
	_ensure_craft_test_items()
	_ensure_new_craft_material_items()
	_ensure_new_food_items()
	_ensure_guaranteed_weapon_items()
	if not _can_spawn_on_this_peer():
		return
	if multiplayer != null and multiplayer.multiplayer_peer != null and multiplayer.is_server():
		if not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)
	if spawn_all_possible_items_near_player:
		call_deferred("_spawn_all_possible_items_near_player", 0)
	else:
		spawn_items()


func spawn_starter_items_near_player_if_enabled() -> void:
	if not _can_spawn_on_this_peer():
		return
	if not spawn_starter_items_near_player:
		return
	if _starter_items_spawned:
		return
	_starter_items_spawned = true
	_spawn_starter_items_near_player(0)


func spawn_random_world_pickup_at_position(spawn_position: Vector2, forced_runtime_id: String = "") -> bool:
	if not _can_spawn_on_this_peer():
		return false
	if pickup_scene == null:
		push_warning("ItemSpawner: pickup_scene is not assigned")
		return false

	var valid_items: Array[ItemData] = _get_valid_world_spawn_items()
	if valid_items.is_empty():
		return false

	var item_data: ItemData = valid_items[rng.randi_range(0, valid_items.size() - 1)]
	if item_data == null:
		return false
	return _spawn_pickup(item_data, spawn_position, forced_runtime_id)


func get_valid_world_spawn_items() -> Array[ItemData]:
	return _get_valid_world_spawn_items()


func _ensure_special_scope_items() -> void:
	if not force_include_ts39_scope:
		return
	if TS_39_SCOPE_RESOURCE == null:
		return

	_append_if_missing(TS_39_SCOPE_RESOURCE)


func _ensure_craft_test_items() -> void:
	if not force_include_craft_test_items:
		return

	for item in FORCED_CRAFT_TEST_ITEMS:
		_append_if_missing(item)


func _ensure_new_craft_material_items() -> void:
	if not include_new_craft_materials_in_world_spawn:
		return

	for item in NEW_CRAFT_MATERIAL_ITEMS:
		_append_if_missing(item)


func _ensure_new_food_items() -> void:
	for item in NEW_FOOD_ITEMS:
		_append_if_missing(item)


func _ensure_guaranteed_weapon_items() -> void:
	for item in GUARANTEED_WORLD_WEAPON_ITEMS:
		_append_if_missing(item)


func _append_if_missing(item: ItemData) -> void:
	if item == null:
		return
	if _is_excluded_world_spawn_item(item):
		return

	for existing_item in possible_items:
		if existing_item == null:
			continue
		if existing_item.resource_path == item.resource_path:
			return

	possible_items.append(item)
	
func spawn_items() -> void:
	if _world_items_spawned:
		return
	_world_items_spawned = true
	if pickup_scene == null:
		push_warning("ItemSpawner: pickup_scene is not assigned")
		return

	var spawn_points: Array = get_children()
	
	if spawn_points.is_empty():
		print("Нет точек спавна")
		return
	
	var valid_items: Array[ItemData] = []
	for template_item in possible_items:
		if template_item != null and not _is_excluded_world_spawn_item(template_item):
			valid_items.append(template_item)

	if valid_items.is_empty():
		print("Нет предметов для спавна")
		return
		
	var points_to_use: Array = spawn_points.duplicate()
	points_to_use.shuffle()
	
	var count: int = min(spawn_count, points_to_use.size())
	
	for i in range(count):
		var point: Node2D = points_to_use[i] as Node2D
		if point == null:
			continue
		var item_data: ItemData = valid_items[rng.randi_range(0, valid_items.size() - 1)]
		if item_data == null:
			continue
		_spawn_pickup(item_data, point.global_position)


func _can_spawn_on_this_peer() -> bool:
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		return true
	return multiplayer.is_server()


func _spawn_all_possible_items_near_player(attempt: int = 0) -> void:
	if _spawn_all_completed:
		return
	if pickup_scene == null:
		push_warning("ItemSpawner: pickup_scene is not assigned")
		return

	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		if attempt < 10:
			call_deferred("_spawn_all_possible_items_near_player", attempt + 1)
			return
		push_warning("ItemSpawner: player was not found for temporary spawn-all mode")
		return

	var valid_items: Array = _get_temporary_spawn_all_items()

	if valid_items.is_empty():
		print("Нет предметов для спавна")
		return

	var columns: int = int(ceil(sqrt(float(valid_items.size()))))
	var rows: int = int(ceil(float(valid_items.size()) / float(max(columns, 1))))
	var spacing: float = max(spawn_all_near_player_spacing, 16.0)
	var grid_origin: Vector2 = player.global_position + spawn_all_near_player_offset
	grid_origin -= Vector2(float(columns - 1), float(rows - 1)) * spacing * 0.5

	for i in range(valid_items.size()):
		var column: int = i % columns
		var row: int = int(i / columns)
		var spawn_position: Vector2 = grid_origin + Vector2(float(column), float(row)) * spacing
		_spawn_pickup(valid_items[i] as ItemData, spawn_position)
	_spawn_all_completed = true


func _spawn_starter_items_near_player(attempt: int = 0) -> void:
	if pickup_scene == null:
		push_warning("ItemSpawner: pickup_scene is not assigned")
		return

	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		if attempt < 10:
			call_deferred("_spawn_starter_items_near_player", attempt + 1)
			return
		push_warning("ItemSpawner: player was not found for starter items")
		return

	var valid_items: Array[ItemData] = []
	for item in STARTER_NEAR_PLAYER_ITEMS:
		if item != null:
			valid_items.append(item)
	if valid_items.is_empty():
		return

	var spacing := maxf(starter_items_near_player_spacing, 16.0)
	var origin := player.global_position + starter_items_near_player_offset
	origin -= Vector2(float(valid_items.size() - 1) * spacing * 0.5, 0.0)
	for i in range(valid_items.size()):
		_spawn_pickup(valid_items[i], origin + Vector2(float(i) * spacing, 0.0))


func _get_temporary_spawn_all_items() -> Array:
	var result: Array = []
	var seen_paths: Dictionary = {}

	for template_item in possible_items:
		_append_item_unique(result, seen_paths, template_item)

	if spawn_all_item_resources_from_resources:
		_collect_item_resources_from_directory(spawn_all_resources_root, result, seen_paths)

	return result


func _collect_item_resources_from_directory(directory_path: String, result: Array, seen_paths: Dictionary) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return

	var child_directories: Array[String] = []
	var item_resource_paths: Array[String] = []
	directory.list_dir_begin()
	var entry_name: String = directory.get_next()
	while not entry_name.is_empty():
		if entry_name.begins_with("."):
			entry_name = directory.get_next()
			continue

		var entry_path: String = directory_path.path_join(entry_name)
		if directory.current_is_dir():
			child_directories.append(entry_path)
		else:
			var item_resource_path := _get_export_safe_resource_path(entry_path)
			if not item_resource_path.is_empty():
				item_resource_paths.append(item_resource_path)

		entry_name = directory.get_next()
	directory.list_dir_end()

	child_directories.sort()
	item_resource_paths.sort()

	for child_directory in child_directories:
		_collect_item_resources_from_directory(child_directory, result, seen_paths)

	for resource_path in item_resource_paths:
		var resource: Resource = load(resource_path)
		var item_resource: ItemData = resource as ItemData
		if item_resource != null:
			_append_item_unique(result, seen_paths, item_resource)


func _get_export_safe_resource_path(entry_path: String) -> String:
	var extension := entry_path.get_extension().to_lower()
	if extension == "tres" or extension == "res":
		return "" if _is_excluded_world_spawn_resource_path(entry_path) else entry_path

	if extension == "remap":
		var original_path := entry_path.trim_suffix(".remap")
		var original_extension := original_path.get_extension().to_lower()
		if (original_extension == "tres" or original_extension == "res") and not _is_excluded_world_spawn_resource_path(original_path):
			return original_path

	return ""


func _append_item_unique(result: Array, seen_paths: Dictionary, item: ItemData) -> void:
	if item == null:
		return
	if _is_excluded_world_spawn_item(item):
		return

	var item_key: String = item.resource_path
	if item_key.is_empty():
		item_key = item.item_name
	if item_key.is_empty() or seen_paths.has(item_key):
		return

	seen_paths[item_key] = true
	result.append(item)


func _get_valid_world_spawn_items() -> Array[ItemData]:
	var valid_items: Array[ItemData] = []
	var seen_paths: Dictionary = {}
	for template_item in possible_items:
		_append_item_unique(valid_items, seen_paths, template_item)
	if spawn_all_item_resources_from_resources:
		_collect_item_resources_from_directory(spawn_all_resources_root, valid_items, seen_paths)
	return valid_items


func _is_excluded_world_spawn_item(item: ItemData) -> bool:
	if item == null:
		return false
	return _is_excluded_world_spawn_resource_path(item.resource_path)


func _is_excluded_world_spawn_resource_path(resource_path: String) -> bool:
	if resource_path.is_empty():
		return false
	var normalized_path := resource_path.trim_suffix(".remap")
	return EXCLUDED_WORLD_SPAWN_RESOURCE_PATHS.has(normalized_path)


func _spawn_pickup(item_data: ItemData, spawn_position: Vector2, forced_runtime_id: String = "") -> bool:
	if item_data == null or pickup_scene == null:
		return false

	var item_copy: ItemData = item_data.create_instance()
	var normalized_runtime_id := forced_runtime_id.strip_edges()
	if not normalized_runtime_id.is_empty():
		if _has_pickup_runtime_id(normalized_runtime_id):
			return false
		if item_copy != null and item_copy.has_method("get_runtime_id"):
			item_copy.set("runtime_id", normalized_runtime_id)
	# In temporary spawn-all mode each entry should appear as a single piece.
	if spawn_all_possible_items_near_player:
		item_copy.stack_count = 1
	_apply_random_endurance_if_needed(item_copy)

	if item_copy.storage_category == ItemData.StorageCategory.WEAPON:
		var max_mag: int = max(item_copy.magazine_size, 0)
		var max_reserve: int = max(item_copy.reserve_ammo, 0)
		var ammo_in_mag: int = rng.randi_range(0, max_mag)
		var reserve_ammo: int = rng.randi_range(0, max_reserve)
		InventoryManager.set_ammo_state(item_copy, ammo_in_mag, reserve_ammo)
	elif item_copy.is_ammo_item:
		item_copy.stack_count = rng.randi_range(3, max(item_copy.max_stack_size, 3))
	var payload: Dictionary = {
		"item": item_copy.to_save_dict() if item_copy.has_method("to_save_dict") else {},
		"position": {"x": spawn_position.x, "y": spawn_position.y}
	}
	_spawn_pickup_from_payload(payload)
	if multiplayer != null and multiplayer.multiplayer_peer != null and multiplayer.is_server():
		rpc("rpc_spawn_pickup_payload", payload)
	return true


func _spawn_pickup_from_payload(payload: Dictionary) -> void:
	if pickup_scene == null:
		return
	if not (payload.get("item", {}) is Dictionary):
		return
	var item: ItemData = ITEM_INSTANCE_SCRIPT.from_save_dict(payload.get("item", {}) as Dictionary)
	if item == null:
		return
	var runtime_id := String((payload.get("item", {}) as Dictionary).get("runtime_id", ""))
	if _has_pickup_runtime_id(runtime_id):
		return
	var pickup: Node2D = pickup_scene.instantiate()
	if pickup == null:
		return
	if not runtime_id.is_empty():
		pickup.name = _build_network_pickup_node_name(runtime_id)
	if pickup.has_method("setup_from_item_data"):
		pickup.call("setup_from_item_data", item)
	elif "item_data" in pickup:
		pickup.item_data = item
	var pos_dict: Dictionary = payload.get("position", {})
	pickup.global_position = Vector2(
		float(pos_dict.get("x", 0.0)),
		float(pos_dict.get("y", 0.0))
	)
	var parent_node := get_parent()
	if parent_node == null:
		return
	parent_node.add_child.call_deferred(pickup)


func _build_network_pickup_node_name(runtime_id: String) -> String:
	var normalized: String = runtime_id.strip_edges()
	if normalized.is_empty():
		return "WorldPickup"
	normalized = normalized.replace(" ", "_")
	normalized = normalized.replace("/", "_")
	normalized = normalized.replace("\\", "_")
	normalized = normalized.replace(":", "_")
	normalized = normalized.replace(".", "_")
	return "WorldPickup_%s" % normalized


func _has_pickup_runtime_id(runtime_id: String) -> bool:
	if runtime_id.is_empty():
		return false
	var parent_node := get_parent()
	if parent_node == null:
		return false
	for node in get_tree().get_nodes_in_group("world_pickup"):
		var pickup := node as Node
		if pickup == null or not is_instance_valid(pickup):
			continue
		if not parent_node.is_ancestor_of(pickup):
			continue
		var item: ItemData = pickup.get("item_data") as ItemData
		if item == null:
			continue
		if String(item.get("runtime_id")) == runtime_id:
			return true
	return false


func _collect_pickup_snapshot_payloads() -> Array:
	var result: Array = []
	var parent_node := get_parent()
	if parent_node == null:
		return result
	for node in get_tree().get_nodes_in_group("world_pickup"):
		var pickup := node as Node
		if pickup == null or not is_instance_valid(pickup):
			continue
		if not parent_node.is_ancestor_of(pickup):
			continue
		var item: ItemData = pickup.get("item_data") as ItemData
		if item == null or not item.has_method("to_save_dict"):
			continue
		var pickup_pos := Vector2.ZERO
		if pickup is Node2D:
			pickup_pos = (pickup as Node2D).global_position
		result.append({
			"item": item.to_save_dict(),
			"position": {"x": pickup_pos.x, "y": pickup_pos.y}
		})
	return result


func _on_peer_connected(peer_id: int) -> void:
	if peer_id <= 0:
		return
	rpc_id(peer_id, "rpc_sync_pickups_snapshot", _collect_pickup_snapshot_payloads())


@rpc("authority", "reliable")
func rpc_spawn_pickup_payload(payload: Dictionary) -> void:
	if NetworkManager != null and NetworkManager.is_server():
		return
	_spawn_pickup_from_payload(payload)


@rpc("authority", "reliable")
func rpc_sync_pickups_snapshot(payloads: Array) -> void:
	if NetworkManager != null and NetworkManager.is_server():
		return
	for payload in payloads:
		if payload is Dictionary:
			_spawn_pickup_from_payload(payload as Dictionary)


func request_network_despawn_by_runtime_id(runtime_id: String) -> void:
	var normalized_id: String = runtime_id.strip_edges()
	if normalized_id.is_empty():
		return
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		_despawn_pickups_by_runtime_id(normalized_id)
		return
	if NetworkManager == null or not NetworkManager.is_server():
		return
	_despawn_pickups_by_runtime_id(normalized_id)
	rpc("rpc_despawn_pickup_runtime_id", normalized_id)


@rpc("authority", "reliable")
func rpc_despawn_pickup_runtime_id(runtime_id: String) -> void:
	var normalized_id: String = runtime_id.strip_edges()
	if normalized_id.is_empty():
		return
	if NetworkManager != null and NetworkManager.is_server():
		return
	_despawn_pickups_by_runtime_id(normalized_id)


func _despawn_pickups_by_runtime_id(runtime_id: String) -> void:
	var parent_node := get_parent()
	if parent_node == null:
		return
	for node in get_tree().get_nodes_in_group("world_pickup"):
		var pickup := node as Node
		if pickup == null or not is_instance_valid(pickup):
			continue
		if not parent_node.is_ancestor_of(pickup):
			continue
		var item: ItemData = pickup.get("item_data") as ItemData
		if item == null:
			continue
		if String(item.get("runtime_id")) != runtime_id:
			continue
		if pickup.has_method("remove_from_world"):
			pickup.call("remove_from_world")
		else:
			pickup.queue_free()


func _apply_random_endurance_if_needed(item: ItemData) -> void:
	if item == null:
		return

	if item.storage_category == ItemData.StorageCategory.WEAPON or _is_clothing_item(item):
		item.endurance = rng.randi_range(20, 100)


func _is_clothing_item(item: ItemData) -> bool:
	return item.item_type in [
		ItemData.ItemType.T_shirts,
		ItemData.ItemType.Jacket,
		ItemData.ItemType.HeavyArmour,
		ItemData.ItemType.Trousers,
		ItemData.ItemType.Bag,
		ItemData.ItemType.Cap
	]
		
