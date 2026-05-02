extends Node2D

@export var pickup_scene: PackedScene
@export var possible_items: Array[ItemData]
@export var spawn_count: int = 3
@export var force_include_ts39_scope: bool = false
@export var force_include_craft_test_items: bool = false
@export var spawn_all_possible_items_near_player: bool = false
@export var spawn_all_item_resources_from_resources: bool = false
@export var spawn_all_resources_root: String = "res://Resources"
@export var spawn_all_near_player_spacing: float = 56.0
@export var spawn_all_near_player_offset: Vector2 = Vector2(120.0, 0.0)
@export var spawn_starter_items_near_player: bool = false
@export var starter_items_near_player_spacing: float = 52.0
@export var starter_items_near_player_offset: Vector2 = Vector2(120.0, 72.0)

const TS_39_SCOPE_RESOURCE: ItemData = preload("res://Resources/AR_Weapons/akp_52/TS_39.tres")
const AKP_52_RESOURCE: ItemData = preload("res://Resources/AR_Weapons/akp_52/akp_52.tres")
const AKP_52_AMMO_RESOURCE: ItemData = preload("res://Resources/AR_Weapons/akp_52/ammo_boxAkp52.tres")
const FN_S_RESOURCE: ItemData = preload("res://Resources/Pistols/fn-s/fn-s.tres")
const AXE_RESOURCE: ItemData = preload("res://Resources/Melee/axe.tres")
const BANDAGE_RESOURCE: ItemData = preload("res://Resources/Medicine/bandage.tres")
const MEDICAL_KIT_RESOURCE: ItemData = preload("res://Resources/Medicine/medicalKit.tres")
const WOOD_RESOURCE: ItemData = preload("res://Resources/Misc/wood.tres")
const STONE_RESOURCE: ItemData = preload("res://Resources/Misc/stone.tres")
const BAG_RESOURCE: ItemData = preload("res://Resources/Clothes/bag.tres")

const FORCED_CRAFT_TEST_ITEMS: Array[ItemData] = [
	BAG_RESOURCE,
	AXE_RESOURCE,
	BANDAGE_RESOURCE,
	BANDAGE_RESOURCE,
	WOOD_RESOURCE,
	WOOD_RESOURCE,
	STONE_RESOURCE
]

const STARTER_NEAR_PLAYER_ITEMS: Array[ItemData] = [
	AKP_52_RESOURCE,
	AKP_52_AMMO_RESOURCE,
	FN_S_RESOURCE,
	AXE_RESOURCE,
	MEDICAL_KIT_RESOURCE,
	BANDAGE_RESOURCE
]

var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	_ensure_special_scope_items()
	_ensure_craft_test_items()
	if spawn_all_possible_items_near_player:
		call_deferred("_spawn_all_possible_items_near_player", 0)
	else:
		spawn_items()


func spawn_starter_items_near_player_if_enabled() -> void:
	if not spawn_starter_items_near_player:
		return
	_spawn_starter_items_near_player(0)


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


func _append_if_missing(item: ItemData) -> void:
	if item == null:
		return

	for existing_item in possible_items:
		if existing_item == null:
			continue
		if existing_item.resource_path == item.resource_path:
			return

	possible_items.append(item)
	
func spawn_items() -> void:
	if pickup_scene == null:
		push_warning("ItemSpawner: pickup_scene is not assigned")
		return

	var spawn_points: Array = get_children()
	
	if spawn_points.is_empty():
		print("Нет точек спавна")
		return
	
	var valid_items: Array[ItemData] = []
	for template_item in possible_items:
		if template_item != null:
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


func _spawn_all_possible_items_near_player(attempt: int = 0) -> void:
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

	directory.list_dir_begin()
	var entry_name: String = directory.get_next()
	while not entry_name.is_empty():
		if entry_name.begins_with("."):
			entry_name = directory.get_next()
			continue

		var entry_path: String = directory_path.path_join(entry_name)
		if directory.current_is_dir():
			_collect_item_resources_from_directory(entry_path, result, seen_paths)
		elif entry_name.get_extension().to_lower() == "tres":
			if not _looks_like_item_data_resource(entry_path):
				entry_name = directory.get_next()
				continue

			var resource: Resource = load(entry_path)
			var item_resource: ItemData = resource as ItemData
			if item_resource != null:
				_append_item_unique(result, seen_paths, item_resource)

		entry_name = directory.get_next()
	directory.list_dir_end()


func _looks_like_item_data_resource(resource_path: String) -> bool:
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return false

	var text: String = file.get_as_text()
	return text.contains("res://items/scripts/item_data.gd")


func _append_item_unique(result: Array, seen_paths: Dictionary, item: ItemData) -> void:
	if item == null:
		return

	var item_key: String = item.resource_path
	if item_key.is_empty():
		item_key = item.item_name
	if item_key.is_empty() or seen_paths.has(item_key):
		return

	seen_paths[item_key] = true
	result.append(item)


func _spawn_pickup(item_data: ItemData, spawn_position: Vector2) -> void:
	if item_data == null or pickup_scene == null:
		return

	var item_copy: ItemData = item_data.create_instance()
	_apply_random_endurance_if_needed(item_copy)

	var pickup: Node2D = pickup_scene.instantiate()
	pickup.global_position = spawn_position
	pickup.item_data = item_copy

	if item_copy.storage_category == ItemData.StorageCategory.WEAPON:
		var max_mag: int = max(item_copy.magazine_size, 0)
		var max_reserve: int = max(item_copy.reserve_ammo, 0)
		var ammo_in_mag: int = rng.randi_range(0, max_mag)
		var reserve_ammo: int = rng.randi_range(0, max_reserve)
		InventoryManager.set_ammo_state(item_copy, ammo_in_mag, reserve_ammo)
	elif item_copy.is_ammo_item:
		item_copy.stack_count = rng.randi_range(3, max(item_copy.max_stack_size, 3))

	get_parent().add_child.call_deferred(pickup)


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
		
