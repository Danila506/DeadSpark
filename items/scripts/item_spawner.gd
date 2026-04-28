extends Node2D

@export var pickup_scene: PackedScene
@export var possible_items: Array[ItemData]
@export var spawn_count: int = 3
@export var force_include_ts39_scope: bool = true
@export var force_include_weapon_pack: bool = true

const TS_39_SCOPE_RESOURCE: ItemData = preload("res://Resources/AR_Weapons/akp_52/TS_39.tres")
const FN_S_RESOURCE: ItemData = preload("res://Resources/Pistols/fn-s/fn-s.tres")
const FN_S_SILENCER_RESOURCE: ItemData = preload("res://Resources/Pistols/fn-s/fn-s_silencer.tres")
const PV_RESOURCE: ItemData = preload("res://Resources/Pistols/pv/pv.tres")
const VPR_155_RESOURCE: ItemData = preload("res://Resources/Pistols/vpr_155/vpr_155.tres")
const MAGNUM_50_RESOURCE: ItemData = preload("res://Resources/Pistols/magnum_50/magnum_50.tres")
const ASS_RESOURCE: ItemData = preload("res://Resources/AR_Weapons/vss/vss.tres")
const SVT_50_RESOURCE: ItemData = preload("res://Resources/AR_Weapons/svt_50/svt_50.tres")

const FORCED_WEAPON_PACK: Array[ItemData] = [
	FN_S_RESOURCE,
	FN_S_SILENCER_RESOURCE,
	PV_RESOURCE,
	VPR_155_RESOURCE,
	MAGNUM_50_RESOURCE,
	ASS_RESOURCE,
	SVT_50_RESOURCE
]

var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	_ensure_special_scope_items()
	_ensure_weapon_pack_items()
	spawn_items()


func _ensure_special_scope_items() -> void:
	if not force_include_ts39_scope:
		return
	if TS_39_SCOPE_RESOURCE == null:
		return

	_append_if_missing(TS_39_SCOPE_RESOURCE)


func _ensure_weapon_pack_items() -> void:
	if not force_include_weapon_pack:
		return

	for weapon_item in FORCED_WEAPON_PACK:
		_append_if_missing(weapon_item)


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
		var item_copy: ItemData = item_data.create_instance()
		_apply_random_endurance_if_needed(item_copy)
		
		var pickup: Node2D = pickup_scene.instantiate()
		pickup.global_position = point.global_position
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
		
