extends Node


class MockPlayer:
	extends Node
	signal stats_changed
	signal status_effects_changed
	var max_health: float = 100.0
	var max_water: float = 100.0
	var max_food: float = 100.0
	var max_stamina: float = 100.0
	var health: float = 100.0
	var water: float = 100.0
	var food: float = 100.0
	var stamina: float = 100.0
	var is_bleeding: bool = false
	var is_fractured: bool = false
	var is_diseased: bool = false

	func has_passive_regeneration() -> bool:
		return false


var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	var old_player := MockPlayer.new()
	old_player.name = "OldPlayer"
	old_player.add_to_group("player")
	add_child(old_player)

	var hud = preload("res://HUD/hud.tscn").instantiate()
	add_child(hud)
	await get_tree().process_frame
	check(hud.player == old_player, "HUD must bind its initial player")

	var network_player := MockPlayer.new()
	network_player.name = "NetworkPlayer"
	network_player.health = 37.0
	network_player.water = 61.0
	network_player.food = 72.0
	network_player.stamina = 48.0
	add_child(network_player)
	check(hud.bind_player(network_player), "HUD must accept a spawned network player")
	check(hud.player == network_player, "HUD must replace the baked player reference")
	check(is_equal_approx(hud.health_bar.value, 37.0), "HUD health must come from the network player")
	check(is_equal_approx(hud.water_bar.value, 61.0), "HUD water must come from the network player")
	check(is_equal_approx(hud.food_bar.value, 72.0), "HUD food must come from the network player")
	check(is_equal_approx(hud.stamina_bar.value, 48.0), "HUD stamina must come from the network player")

	old_player.health = 5.0
	old_player.stats_changed.emit()
	check(is_equal_approx(hud.health_bar.value, 37.0), "detached baked player signals must not update HUD")
	network_player.health = 29.0
	network_player.stats_changed.emit()
	check(is_equal_approx(hud.health_bar.value, 29.0), "spawned player signals must update HUD")

	var actor = preload("res://Player/player.tscn").instantiate()
	actor._apply_network_vitals_payload({
		"hp": 4550,
		"wa": 7025,
		"fo": 8125,
		"st": 3350,
		"ra": 925,
		"bl": true,
		"fr": true,
		"di": true,
		"dt": 1275
	})
	check(is_equal_approx(actor.health, 45.5), "network snapshot must apply health")
	check(is_equal_approx(actor.water, 70.25), "network snapshot must apply water")
	check(is_equal_approx(actor.food, 81.25), "network snapshot must apply food")
	check(is_equal_approx(actor.stamina, 33.5), "network snapshot must apply stamina")
	check(actor.is_bleeding and actor.is_fractured and actor.is_diseased, "network snapshot must apply statuses")

	var peer_id: int = 99123
	var armor := ItemData.new()
	armor.storage_category = ItemData.StorageCategory.CLOTHING
	armor.endurance = 100
	armor.clothing_armor = 100.0
	armor.clothing_endurance_loss_percent_per_damage = 1.0
	InventoryManager.network_inventory_by_peer[peer_id] = {
		"equipped": {ItemData.ItemType.HeavyArmour: armor},
		"active_weapon_slot": ItemData.ItemType.AR_Weapon
	}
	var remaining_damage: float = InventoryManager.get_damage_after_network_peer_equipped_clothing_armor(peer_id, 10.0, ItemData.DamageType.BITE)
	check(remaining_damage > 0.0, "armor must not reduce a positive hit to zero")
	check(is_equal_approx(remaining_damage, 1.5), "armor absorption must respect the 85 percent cap")
	check(InventoryManager.apply_damage_to_network_peer_equipped_clothing(peer_id, 10.0, ItemData.DamageType.BITE), "remote clothing endurance must be server-owned")
	check(armor.endurance == 90, "remote clothing must lose endurance from damage")
	InventoryManager.clear_network_peer_inventory(peer_id)
	actor.free()

	for failure in failures:
		push_error(failure)
	print("LAN_VITALS_HUD_TEST=" + ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)
