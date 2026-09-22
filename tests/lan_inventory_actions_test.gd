extends Node

const BAG = preload("res://Resources/Clothes/bag.tres")
const WOOD = preload("res://Resources/Misc/wood.tres")
const BANDAGE = preload("res://Resources/Medicine/bandage.tres")
const APPLE = preload("res://Resources/Food/apple.tres")
const WEAPON = preload("res://Resources/AR_Weapons/akp_52/akp_52.tres")
const AMMO = preload("res://Resources/AR_Weapons/akp_52/ammo_boxAkp52.tres")

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func _run() -> void:
	InventoryManager.reset_state()
	var bag: ItemData = BAG.create_instance(1, 100)
	bag.runtime_storage_items.resize(maxi(bag.extra_storage_slots, 5))
	bag.runtime_storage_items[0] = WOOD.create_instance(1, 100)
	bag.runtime_storage_items[1] = APPLE.create_instance(2, 100)
	bag.runtime_storage_items[2] = AMMO.create_instance(12, 100)
	var weapon: ItemData = WEAPON.create_instance(1, 100)
	InventoryManager.set_equipped(ItemData.ItemType.Bag, bag)
	InventoryManager.set_equipped(ItemData.ItemType.AR_Weapon, weapon)
	InventoryManager.set_ammo_state(weapon, 0, 0)
	var client_snapshot: Dictionary = InventoryManager.get_network_inventory_snapshot()

	InventoryManager.reset_state()
	_check(InventoryManager.apply_network_peer_inventory_snapshot(42, client_snapshot), "peer inventory snapshot rejected")
	var forged_snapshot: Dictionary = client_snapshot.duplicate(true)
	var forged_equipped: Dictionary = forged_snapshot.get("equipped", {})
	var forged_bag: Dictionary = forged_equipped.get(str(ItemData.ItemType.Bag), {})
	var forged_storage: Array = forged_bag.get("runtime_storage_items", [])
	(forged_storage[0] as Dictionary)["stack_count"] = 99
	_check(not InventoryManager.reconcile_network_peer_inventory_layout(42, forged_snapshot), "server accepted client-forged item count")
	var unchanged_bag: ItemData = InventoryManager.get_network_peer_equipped(42, ItemData.ItemType.Bag)
	_check(unchanged_bag.runtime_storage_items[0].stack_count == 1, "rejected snapshot mutated authoritative inventory")
	var ingredients: Array = [{"item": WOOD, "count": 1}]
	_check(InventoryManager.can_network_peer_craft(42, ingredients, BANDAGE, 1), "server rejected craft with owned ingredient")
	_check(InventoryManager.craft_network_peer_item(42, ingredients, BANDAGE, 1), "server craft mutation failed")
	_check(not InventoryManager.craft_network_peer_item(42, ingredients, BANDAGE, 1), "server allowed craft without ingredient")

	var server_bag: ItemData = InventoryManager.get_network_peer_equipped(42, ItemData.ItemType.Bag)
	_check(server_bag != null and server_bag.runtime_storage_items[0] != null and server_bag.runtime_storage_items[0].item_name == BANDAGE.item_name, "crafted result missing from authoritative inventory")
	var consumed_food: ItemData = InventoryManager.consume_network_peer_item_at(42, InventorySlot.SlotMode.CONTAINER, 0, ItemData.ItemType.Bag * 100 + 1, ItemData.StorageCategory.FOOD)
	_check(consumed_food != null and consumed_food.item_name == APPLE.item_name, "server did not consume food from owned slot")
	_check(server_bag.runtime_storage_items[1] != null and server_bag.runtime_storage_items[1].stack_count == 1, "server food stack was not decremented")
	_check(InventoryManager.consume_network_peer_item_at(42, InventorySlot.SlotMode.CONTAINER, 0, ItemData.ItemType.Bag * 100 + 1, ItemData.StorageCategory.MEDICAL) == null, "server accepted wrong consumable category")

	_check(InventoryManager.equip_network_peer_ammo_at(42, InventorySlot.SlotMode.CONTAINER, 0, ItemData.ItemType.Bag * 100 + 2), "server rejected owned compatible ammo")
	var server_weapon: ItemData = InventoryManager.get_network_peer_equipped(42, ItemData.ItemType.AR_Weapon)
	_check(InventoryManager.get_reserve_ammo(server_weapon) == 12, "server reserve ammo was not updated")
	_check(server_bag.runtime_storage_items[2] == null, "equipped ammo was not removed from authoritative inventory")

	var authoritative_snapshot: Dictionary = InventoryManager.get_network_peer_inventory_snapshot(42)
	_check(not authoritative_snapshot.is_empty(), "server did not serialize authoritative inventory")

	var container_apple: ItemData = APPLE.create_instance(3, 100)
	var transfer_snapshot: Dictionary = authoritative_snapshot.duplicate(true)
	var transfer_bag: Dictionary = (transfer_snapshot.get("equipped", {}) as Dictionary).get(str(ItemData.ItemType.Bag), {})
	var transfer_storage: Array = transfer_bag.get("runtime_storage_items", [])
	transfer_storage[2] = GameSaveManager.serialize_item(container_apple)
	_check(
		InventoryManager.commit_network_peer_inventory_transfer(42, transfer_snapshot, [container_apple], [null]),
		"server rejected conserved container transfer"
	)
	server_bag = InventoryManager.get_network_peer_equipped(42, ItemData.ItemType.Bag)
	_check(server_bag.runtime_storage_items[2] != null and server_bag.runtime_storage_items[2].get_runtime_id() == container_apple.get_runtime_id(), "container transfer lost runtime identity")

	var forged_world_item: ItemData = WOOD.create_instance(1, 100)
	var forged_transfer: Dictionary = InventoryManager.get_network_peer_inventory_snapshot(42).duplicate(true)
	var forged_transfer_bag: Dictionary = (forged_transfer.get("equipped", {}) as Dictionary).get(str(ItemData.ItemType.Bag), {})
	var forged_transfer_storage: Array = forged_transfer_bag.get("runtime_storage_items", [])
	var forged_payload: Dictionary = GameSaveManager.serialize_item(forged_world_item)
	forged_payload["stack_count"] = 99
	forged_payload["runtime_id"] = "forged-runtime-id"
	forged_transfer_storage[3] = forged_payload
	_check(
		not InventoryManager.commit_network_peer_inventory_transfer(42, forged_transfer, [forged_world_item], [null]),
		"server accepted forged container item state"
	)
	server_bag = InventoryManager.get_network_peer_equipped(42, ItemData.ItemType.Bag)
	_check(server_bag.runtime_storage_items[3] == null, "rejected container transfer mutated authoritative inventory")

	_check(InventoryManager.apply_network_authoritative_local_snapshot(authoritative_snapshot), "client rejected authoritative inventory")
	var local_bag: ItemData = InventoryManager.get_equipped(ItemData.ItemType.Bag)
	_check(local_bag != null and local_bag.runtime_storage_items[1] != null and local_bag.runtime_storage_items[1].stack_count == 1, "authoritative client reconciliation lost inventory state")
	_check(not InventoryManager.network_authoritative_update_in_progress, "authoritative reconciliation guard remained enabled")

	for failure in failures:
		push_error(failure)
	print("LAN_INVENTORY_ACTIONS_TEST=" + ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)
