extends Node

const HOST_WEAPON = preload("res://Resources/AR_Weapons/akp_103/akp_103.tres")
const CLIENT_WEAPON = preload("res://Resources/Pistols/pv/pv.tres")

var failures: Array[String] = []


class RemotePlayer:
	extends CharacterBody2D
	var peer_id: int = 42

	func _is_local_network_player() -> bool:
		return false


func _ready() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func _run() -> void:
	InventoryManager.reset_state()
	var host_weapon: ItemData = HOST_WEAPON.create_instance(1, 100)
	InventoryManager.set_equipped(ItemData.ItemType.AR_Weapon, host_weapon)
	InventoryManager.set_ammo_state(host_weapon, 7, 21)

	var client_weapon: ItemData = CLIENT_WEAPON.create_instance(1, 80)
	InventoryManager.set_equipped(ItemData.ItemType.AR_Weapon, null)
	InventoryManager.set_equipped(ItemData.ItemType.Pistols, client_weapon)
	InventoryManager.set_active_weapon_slot(ItemData.ItemType.Pistols)
	InventoryManager.set_ammo_state(client_weapon, 3, 11)
	var client_snapshot: Dictionary = InventoryManager.get_network_inventory_snapshot()

	InventoryManager.reset_state()
	InventoryManager.set_equipped(ItemData.ItemType.AR_Weapon, host_weapon)
	InventoryManager.set_active_weapon_slot(ItemData.ItemType.AR_Weapon)
	_check(InventoryManager.apply_network_peer_inventory_snapshot(42, client_snapshot), "peer snapshot rejected")

	var restored_client_weapon: ItemData = InventoryManager.get_network_peer_equipped(42, ItemData.ItemType.Pistols)
	_check(restored_client_weapon != null, "client weapon missing")
	_check(restored_client_weapon != host_weapon, "client weapon aliases host weapon")
	_check(InventoryManager.get_network_peer_active_weapon_slot(42) == ItemData.ItemType.Pistols, "client active slot mismatch")
	_check(InventoryManager.get_ammo_in_mag(restored_client_weapon) == 3, "client magazine state mismatch")
	_check(InventoryManager.get_ammo_in_mag(host_weapon) == 7, "host magazine changed while restoring peer")

	InventoryManager.set_network_peer_ammo_state(42, ItemData.ItemType.Pistols, 2, 11)
	_check(InventoryManager.get_ammo_in_mag(restored_client_weapon) == 2, "peer ammo mutation failed")
	_check(InventoryManager.get_ammo_in_mag(host_weapon) == 7, "peer shot consumed host ammo")
	InventoryManager.apply_endurance_percent_loss_to_network_peer_equipped(42, ItemData.ItemType.Pistols, 10.0)
	_check(restored_client_weapon.endurance == 70, "peer durability mutation failed")
	_check(host_weapon.endurance == 100, "peer durability mutation affected host")

	var network_peer := ENetMultiplayerPeer.new()
	var listen_error: int = network_peer.create_server(2491)
	_check(listen_error == OK, "test network server setup failed")
	if listen_error == OK:
		multiplayer.multiplayer_peer = network_peer
		var remote_player := RemotePlayer.new()
		add_child(remote_player)
		var controller := WeaponController.new()
		controller.player = remote_player
		controller._update_current_weapon()
		_check(controller.current_weapon == restored_client_weapon, "remote WeaponController did not select peer weapon")
		_check(controller.current_weapon != host_weapon, "remote WeaponController selected host weapon")
		controller._set_ammo_state(1, 9)
		_check(InventoryManager.get_ammo_in_mag(restored_client_weapon) == 1, "remote WeaponController did not mutate peer magazine")
		_check(InventoryManager.get_ammo_in_mag(host_weapon) == 7, "remote WeaponController consumed host magazine")
		controller.free()
		remote_player.free()
		network_peer.close()
		multiplayer.multiplayer_peer = null

	InventoryManager.clear_network_peer_inventory(42)
	_check(not InventoryManager.has_network_peer_inventory(42), "peer inventory cleanup failed")
	for failure in failures:
		push_error(failure)
	print("LAN_PEER_INVENTORY_TEST=" + ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)
