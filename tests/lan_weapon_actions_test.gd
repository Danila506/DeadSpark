extends Node

const HOST_PISTOL = preload("res://Resources/Pistols/fn-s/fn-s.tres")
const CLIENT_PISTOL = preload("res://Resources/Pistols/pv/pv.tres")
const MELEE_WEAPON = preload("res://Resources/Melee/axe.tres")

var failures: Array[String] = []


class RemotePlayer:
	extends CharacterBody2D
	var peer_id: int = 42
	var action_in_progress: bool = false
	var facing_direction: String = "right"

	func _is_local_network_player() -> bool:
		return false


class DamageTarget:
	extends Node2D
	var health: float = 100.0

	func take_damage_from(amount: float, _source: Node, _context: Dictionary = {}) -> void:
		health -= amount

	func is_dead() -> bool:
		return health <= 0.0


func _ready() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func _make_peer_snapshot(item: ItemData, slot_type: int, ammo_in_mag: int = 0, reserve_ammo: int = 0) -> Dictionary:
	InventoryManager.reset_state()
	InventoryManager.set_equipped(slot_type, item)
	InventoryManager.set_active_weapon_slot(slot_type)
	if item.storage_category == ItemData.StorageCategory.WEAPON:
		InventoryManager.set_ammo_state(item, ammo_in_mag, reserve_ammo)
	return InventoryManager.get_network_inventory_snapshot()


func _run() -> void:
	var network_peer := ENetMultiplayerPeer.new()
	var listen_error: int = network_peer.create_server(2492)
	_check(listen_error == OK, "test network server setup failed")
	if listen_error != OK:
		_finish(network_peer)
		return
	multiplayer.multiplayer_peer = network_peer

	var remote_player := RemotePlayer.new()
	add_child(remote_player)
	var controller := WeaponController.new()
	controller.player = remote_player
	controller.reload_controller = WeaponReloadController.new(controller)
	controller.melee_controller = WeaponMeleeController.new(controller)
	_check(not controller._can_read_local_weapon_input(), "remote server replica may read host input")

	var client_pistol: ItemData = CLIENT_PISTOL.create_instance(1, 90)
	var pistol_snapshot: Dictionary = _make_peer_snapshot(client_pistol, ItemData.ItemType.Pistols, 0, 8)
	var host_pistol: ItemData = HOST_PISTOL.create_instance(1, 100)
	InventoryManager.reset_state()
	InventoryManager.set_equipped(ItemData.ItemType.Pistols, host_pistol)
	InventoryManager.set_active_weapon_slot(ItemData.ItemType.Pistols)
	InventoryManager.set_ammo_state(host_pistol, 5, 15)
	_check(InventoryManager.apply_network_peer_inventory_snapshot(42, pistol_snapshot), "peer pistol snapshot rejected")
	controller._update_current_weapon()
	_check(controller.current_weapon != host_pistol, "remote reload selected host pistol")
	_check(controller.reload_controller.start_reload(true), "server rejected valid peer reload")
	controller.reload_controller.update(100.0)
	var server_pistol: ItemData = InventoryManager.get_network_peer_equipped(42, ItemData.ItemType.Pistols)
	_check(InventoryManager.get_ammo_in_mag(server_pistol) > 0, "server reload did not fill peer magazine")
	_check(InventoryManager.get_ammo_in_mag(host_pistol) == 5, "peer reload changed host magazine")

	var client_melee: ItemData = MELEE_WEAPON.create_instance(1, 80)
	var melee_snapshot: Dictionary = _make_peer_snapshot(client_melee, ItemData.ItemType.MeleeWeapon)
	var host_melee: ItemData = MELEE_WEAPON.create_instance(1, 100)
	InventoryManager.reset_state()
	InventoryManager.set_equipped(ItemData.ItemType.MeleeWeapon, host_melee)
	InventoryManager.set_active_weapon_slot(ItemData.ItemType.MeleeWeapon)
	_check(InventoryManager.apply_network_peer_inventory_snapshot(42, melee_snapshot), "peer melee snapshot rejected")
	controller._update_current_weapon()
	var target := DamageTarget.new()
	target.position = Vector2(12.0, 0.0)
	target.add_to_group("enemy")
	add_child(target)
	var health_before: float = target.health
	_check(controller.melee_controller.start_melee_attack(Vector2.RIGHT, true, true), "server rejected valid peer melee")
	controller.melee_controller.update_melee_attack(1.0)
	var server_melee: ItemData = InventoryManager.get_network_peer_equipped(42, ItemData.ItemType.MeleeWeapon)
	_check(target.health < health_before, "authoritative melee did not damage target")
	_check(server_melee == null or server_melee.endurance < 80, "authoritative melee did not consume peer durability")
	_check(host_melee.endurance == 100, "peer melee changed host durability")

	controller.free()
	remote_player.free()
	target.free()
	_finish(network_peer)


func _finish(network_peer: ENetMultiplayerPeer) -> void:
	InventoryManager.reset_state()
	if network_peer != null:
		network_peer.close()
	multiplayer.multiplayer_peer = null
	for failure in failures:
		push_error(failure)
	print("LAN_WEAPON_ACTIONS_TEST=" + ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)
