extends Node

const BONFIRE_SCRIPT := preload("res://World/bonfire_light.gd")

class MockPlayer extends CharacterBody2D:
	var health := 100.0
	var is_dead := false
	var clothing_loss := 0.0

	func _ready() -> void:
		add_to_group("player")
		collision_layer = 1
		collision_mask = 1
		var collision := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 5.0
		collision.shape = shape
		add_child(collision)

	func take_damage(amount: float, _damage_type: int, _apply_clothing_damage: bool) -> void:
		health -= amount

	func apply_clothing_endurance_percent_loss(percent_loss: float) -> void:
		clothing_loss += percent_loss


var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_periodic_burn_damage()
	_test_exact_local_clothing_wear()
	_test_exact_network_clothing_wear()
	for failure in failures: push_error("Bonfire damage: " + failure)
	print("BONFIRE_DAMAGE_TEST=" + ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)


func _test_periodic_burn_damage() -> void:
	var bonfire := BONFIRE_SCRIPT.new() as CampfireLightController
	bonfire.smoke_enabled = false
	bonfire.distance_lod_enabled = false
	bonfire.burn_tick_interval_sec = 0.1
	bonfire.burn_damage_per_tick = 5.0
	bonfire.clothing_endurance_loss_percent = 1.5
	add_child(bonfire)
	var player := MockPlayer.new()
	add_child(player)
	for _frame in range(8): await get_tree().physics_frame
	_check(is_equal_approx(player.health, 95.0), "player must take one 5 HP tick after 0.1 seconds")
	_check(is_equal_approx(player.clothing_loss, 1.5), "burn tick must request exactly 1.5 percent clothing wear")
	_check(bonfire.get_node_or_null("BurnArea/CollisionShape2D") is CollisionShape2D, "burn area must be created for every bonfire")
	player.queue_free()
	bonfire.queue_free()
	await get_tree().process_frame


func _test_exact_local_clothing_wear() -> void:
	InventoryManager.reset_state()
	var jacket := _clothing(ItemData.ItemType.Jacket)
	var trousers := _clothing(ItemData.ItemType.Trousers)
	InventoryManager.set_equipped(ItemData.ItemType.Jacket, jacket)
	InventoryManager.set_equipped(ItemData.ItemType.Trousers, trousers)
	_check(InventoryManager.apply_endurance_percent_loss_to_equipped_clothing(1.5), "first local wear tick must mutate clothing")
	_check(InventoryManager.apply_endurance_percent_loss_to_equipped_clothing(1.5), "second local wear tick must mutate clothing")
	_check(jacket.endurance == 97 and trousers.endurance == 97, "each local clothing item must lose accumulated 3 percent after two ticks")
	InventoryManager.reset_state()


func _test_exact_network_clothing_wear() -> void:
	var peer_id := 4242
	var jacket := _clothing(ItemData.ItemType.Jacket)
	var bag := _clothing(ItemData.ItemType.Bag)
	InventoryManager.network_inventory_by_peer[peer_id] = {
		"equipped": {ItemData.ItemType.Jacket: jacket, ItemData.ItemType.Bag: bag},
		"active_weapon_slot": ItemData.ItemType.AR_Weapon
	}
	_check(InventoryManager.apply_endurance_percent_loss_to_network_peer_equipped_clothing(peer_id, 1.5), "first network wear tick must mutate clothing")
	_check(InventoryManager.apply_endurance_percent_loss_to_network_peer_equipped_clothing(peer_id, 1.5), "second network wear tick must mutate clothing")
	_check(jacket.endurance == 97 and bag.endurance == 97, "each server-owned clothing item must lose accumulated 3 percent after two ticks")
	InventoryManager.clear_network_peer_inventory(peer_id)


func _clothing(slot_type: int) -> ItemData:
	var item := ItemData.new()
	item.item_type = slot_type
	item.storage_category = ItemData.StorageCategory.CLOTHING
	item.endurance = 100
	return item


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
