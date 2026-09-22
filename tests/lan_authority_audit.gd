extends Node

class TickProbe:
	extends "res://Player/player.gd"
	var sent := 0
	func _is_networked_game() -> bool: return true
	func _broadcast_player_snapshot_interest(_elapsed: float) -> void: sent += 1

func _ready() -> void:
	var jacket := ItemData.new()
	jacket.item_type = ItemData.ItemType.Jacket
	jacket.storage_category = ItemData.StorageCategory.CLOTHING
	jacket.clothing_armor = 20.0
	jacket.endurance = 100
	var remote_vitals := PlayerVitalsController.new(null)
	InventoryManager.set_equipped(ItemData.ItemType.Jacket, null)
	var without_host_armor := remote_vitals._get_damage_after_armor(50.0, ItemData.DamageType.BULLET)
	InventoryManager.set_equipped(ItemData.ItemType.Jacket, jacket)
	var with_host_armor := remote_vitals._get_damage_after_armor(50.0, ItemData.DamageType.BULLET)
	print("LAN_AUDIT host_armor_affects_other_controller=%s damage_before=%s damage_after=%s" % [without_host_armor != with_host_armor, without_host_armor, with_host_armor])
	InventoryManager.set_equipped(ItemData.ItemType.Jacket, null)
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(2489)
	if error != OK:
		push_error("audit server setup failed")
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	var actor := TickProbe.new()
	actor.peer_id = 1
	actor._on_network_tick(0.1, 1)
	var alive_sent := actor.sent
	actor.is_dead = true
	actor._on_network_tick(0.1, 2)
	print("LAN_AUDIT dead_tick_sends_no_final_snapshot=%s alive_sent=%s dead_sent=%s" % [alive_sent > 0 and actor.sent == alive_sent, alive_sent, actor.sent - alive_sent])
	actor.free()
	var service = load("res://World/network_shared_world.gd").new()
	var apple = preload("res://Resources/Food/apple.tres").create_instance(1)
	var original: Array = [GameSaveManager.serialize_item(apple)]
	var local_items: Array = []
	service.callbacks[77] = func(items):
		local_items.append(items[0])
		items[0] = null
	# Simulate a delayed grant after the host has expired its lock.
	service._grant(77, "/missing_container", 123, original)
	print("LAN_AUDIT local_transfer_before_rejected_commit=%s host_lock_exists=%s" % [local_items.size() == 1, service.locks.has("/missing_container")])
	service.free()
	peer.close()
	multiplayer.multiplayer_peer = null
	get_tree().quit()
