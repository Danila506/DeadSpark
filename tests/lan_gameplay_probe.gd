extends Node
# Enabled only by --lan-smoke-gameplay=1; uses real network player movement and enemy RPCs.
const PROBE_PISTOL = preload("res://Resources/Pistols/pv/pv.tres")
const PROBE_MELEE = preload("res://Resources/Melee/axe.tres")
const PROBE_DEATH_BAG = preload("res://Resources/Clothes/bag.tres")
const PROBE_DEATH_FOOD = preload("res://Resources/Food/apple.tres")

var checked := {}
var timer := 0.0
var weapon_probe_targets := {}
var death_probe_server_ok := {}


class WeaponProbeTarget:
	extends Node2D
	var health: float = 100.0

	func take_damage_from(amount: float, _source: Node, _context: Dictionary = {}) -> void:
		health -= amount

	func is_dead() -> bool:
		return health <= 0.0
func _process(delta: float) -> void:
	if not NetworkManager.is_server(): return
	timer += delta
	if timer < 0.5: return
	timer = 0.0
	var world = get_parent()
	for peer in NetworkManager.get_active_client_peers():
		if checked.has(peer) or world._acked_world_paths.get(peer, {}).is_empty(): continue
		for enemy in get_tree().get_nodes_in_group("enemy"):
			if not world.has_world_replica(peer, enemy) or enemy._is_dead: continue
			checked[peer] = true
			enemy.take_damage(1.0)
			rpc_id(peer, "check_client", String(enemy.get_path()), enemy.health)
			break

@rpc("authority", "call_remote", "reliable")
func check_client(enemy_path: String, expected_health: float) -> void:
	var world = get_parent()
	var actor = world.players.get(multiplayer.get_unique_id())
	if actor == null:
		push_error("LAN_GAMEPLAY_PROBE missing local player")
		return
	var enemy = get_node_or_null(NodePath(enemy_path))
	var health_ok: bool = enemy != null and is_equal_approx(enemy.health, expected_health)
	var start: Vector2 = actor.global_position
	var move_action: StringName = &"move_right" if actor._has_network_input_actions(actor.NET_INPUT_ACTIONS_PRIMARY) else &"right"
	Input.action_press(move_action)
	await get_tree().create_timer(0.4).timeout
	Input.action_release(move_action)
	await get_tree().create_timer(0.5).timeout
	var moved: bool = actor.global_position.distance_to(start) > 1.0
	print("LAN_CLIENT_GAMEPLAY damage_sync=%s moved=%s players=%d" % [health_ok, moved, world.players.size()])
	rpc_id(1, "report_client", health_ok, moved, actor.global_position, world.players.size())

@rpc("any_peer", "call_remote", "reliable")
func report_client(health_ok: bool, moved: bool, position: Vector2, player_count: int) -> void:
	if not NetworkManager.is_server(): return
	var peer := multiplayer.get_remote_sender_id()
	var world = get_parent()
	var actor = world.players.get(peer)
	var position_ok: bool = actor != null and actor.global_position.distance_to(position) < 40.0
	var peer_inventory_ok: bool = InventoryManager.has_network_peer_inventory(peer)
	var thermal: ItemData = InventoryManager.get_network_peer_equipped(peer, ItemData.ItemType.Cap)
	var thermal_battery: ItemData = thermal.runtime_storage_items[0] if thermal != null and not thermal.runtime_storage_items.is_empty() else null
	var thermal_ok: bool = (
		thermal != null
		and thermal.enables_thermal_vision
		and thermal_battery != null
		and thermal_battery.is_battery_item
		and thermal_battery.battery_charge_seconds > 0.0
	)
	var ok: bool = health_ok and moved and position_ok and peer_inventory_ok and thermal_ok and player_count == world.players.size()
	print("LAN_GAMEPLAY_PROBE=%s peer=%d damage_sync=%s movement=%s position_sync=%s peer_inventory=%s thermal=%s players=%d" % ["PASS" if ok else "FAIL", peer, health_ok, moved, position_ok, peer_inventory_ok, thermal_ok, player_count])
	if ok:
		actor.health = 73.0
		actor.water = 64.0
		actor.food = 52.0
		actor.stamina = 33.0
		actor.radiation = 7.0
		actor.is_bleeding = true
		actor.is_fractured = true
		actor.is_diseased = true
		actor.disease_time_left = 10.0
		rpc_id(peer, "check_client_vitals")
		var pistol: ItemData = PROBE_PISTOL.create_instance(1, 100)
		var melee: ItemData = PROBE_MELEE.create_instance(1, 80)
		InventoryManager.set_network_peer_equipped(peer, ItemData.ItemType.Pistols, pistol)
		InventoryManager.set_network_peer_equipped(peer, ItemData.ItemType.MeleeWeapon, melee)
		InventoryManager.set_network_peer_active_weapon_slot(peer, ItemData.ItemType.Pistols)
		InventoryManager.set_network_peer_ammo_state(peer, ItemData.ItemType.Pistols, 0, 8)
		rpc_id(peer, "prepare_weapon_actions_probe", InventoryManager.get_network_peer_inventory_snapshot(peer))


@rpc("authority", "call_remote", "reliable")
func check_client_vitals() -> void:
	await get_tree().create_timer(0.5).timeout
	var actor = get_parent().players.get(multiplayer.get_unique_id())
	var hud = get_tree().get_first_node_in_group("hud")
	var state_ok: bool = (
		actor != null
		and absf(actor.health - 73.0) < 1.0
		and absf(actor.water - 64.0) < 1.0
		and absf(actor.food - 52.0) < 1.0
		and absf(actor.radiation - 7.0) < 1.0
		and actor.is_bleeding
		and actor.is_fractured
		and actor.is_diseased
	)
	var hud_ok: bool = (
		hud != null
		and hud.player == actor
		and is_equal_approx(hud.health_bar.value, actor.health)
		and is_equal_approx(hud.water_bar.value, actor.water)
		and is_equal_approx(hud.food_bar.value, actor.food)
		# Stamina keeps changing between the snapshot signal and this assertion.
		and absf(hud.stamina_bar.value - actor.stamina) <= 1.0
	)
	print(
		"LAN_CLIENT_VITALS state=%s hud=%s bound=%s values=%s/%s/%s/%s actor=%s/%s/%s/%s"
		% [
			state_ok,
			hud_ok,
			hud != null and hud.player == actor,
			hud.health_bar.value if hud != null else -1.0,
			hud.water_bar.value if hud != null else -1.0,
			hud.food_bar.value if hud != null else -1.0,
			hud.stamina_bar.value if hud != null else -1.0,
			actor.health if actor != null else -1.0,
			actor.water if actor != null else -1.0,
			actor.food if actor != null else -1.0,
			actor.stamina if actor != null else -1.0,
		]
	)
	rpc_id(1, "report_vitals_probe", state_ok, hud_ok)


@rpc("any_peer", "call_remote", "reliable")
func report_vitals_probe(state_ok: bool, hud_ok: bool) -> void:
	if not NetworkManager.is_server():
		return
	var peer: int = multiplayer.get_remote_sender_id()
	var ok: bool = state_ok and hud_ok
	print("LAN_VITALS_PROBE=%s peer=%d state=%s hud=%s" % ["PASS" if ok else "FAIL", peer, state_ok, hud_ok])


@rpc("authority", "call_remote", "reliable")
func prepare_weapon_actions_probe(authoritative_inventory: Dictionary) -> void:
	var actor = get_parent().players.get(multiplayer.get_unique_id())
	if actor == null or actor.weapon_controller == null:
		rpc_id(1, "report_weapon_actions_probe", false, false)
		return
	if not InventoryManager.apply_network_authoritative_local_snapshot(authoritative_inventory):
		rpc_id(1, "report_weapon_actions_probe", false, false)
		return
	var pistol: ItemData = InventoryManager.get_equipped(ItemData.ItemType.Pistols)
	# Give equipment visuals and the weapon controller time to consume the server snapshot.
	await get_tree().create_timer(0.75).timeout
	actor.weapon_controller._update_current_weapon()
	var reload_requested: bool = actor.weapon_controller.request_network_reload()
	var reload_wait_steps: int = 0
	while InventoryManager.get_ammo_in_mag(pistol) <= 0 and reload_wait_steps < 80:
		await get_tree().create_timer(0.1).timeout
		reload_wait_steps += 1
	var reload_ok: bool = reload_requested and InventoryManager.get_ammo_in_mag(pistol) > 0 and InventoryManager.get_reserve_ammo(pistol) < 8
	print("LAN_CLIENT_RELOAD requested=%s mag=%d reserve=%d wait_steps=%d" % [reload_requested, InventoryManager.get_ammo_in_mag(pistol), InventoryManager.get_reserve_ammo(pistol), reload_wait_steps])
	InventoryManager.set_active_weapon_slot(ItemData.ItemType.MeleeWeapon)
	actor.facing_direction = "right"
	await get_tree().create_timer(0.35).timeout
	rpc_id(1, "prepare_server_melee_probe", reload_ok)


@rpc("any_peer", "call_remote", "reliable")
func prepare_server_melee_probe(reload_ok: bool) -> void:
	if not NetworkManager.is_server():
		return
	var peer: int = multiplayer.get_remote_sender_id()
	var world = get_parent()
	var actor = world.players.get(peer)
	if actor == null:
		rpc_id(peer, "execute_melee_probe", reload_ok)
		return
	var wait_steps: int = 0
	while InventoryManager.get_network_peer_active_weapon_slot(peer) != ItemData.ItemType.MeleeWeapon and wait_steps < 20:
		await get_tree().create_timer(0.1).timeout
		wait_steps += 1
	var target := WeaponProbeTarget.new()
	target.name = "LanWeaponProbeTarget_%d" % peer
	target.add_to_group("enemy")
	world.add_child(target)
	target.global_position = actor.global_position + Vector2(12.0, 0.0)
	weapon_probe_targets[peer] = target
	rpc_id(peer, "execute_melee_probe", reload_ok)


@rpc("authority", "call_remote", "reliable")
func execute_melee_probe(reload_ok: bool) -> void:
	var actor = get_parent().players.get(multiplayer.get_unique_id())
	var melee_requested: bool = false
	if actor != null and actor.weapon_controller != null:
		actor.weapon_controller._update_current_weapon()
		melee_requested = actor.weapon_controller.request_network_melee(Vector2.RIGHT)
	await get_tree().create_timer(1.0).timeout
	rpc_id(1, "report_weapon_actions_probe", reload_ok, melee_requested)


@rpc("any_peer", "call_remote", "reliable")
func report_weapon_actions_probe(reload_ok: bool, melee_requested: bool) -> void:
	if not NetworkManager.is_server():
		return
	var peer: int = multiplayer.get_remote_sender_id()
	var target: WeaponProbeTarget = weapon_probe_targets.get(peer, null) as WeaponProbeTarget
	var melee_damage_ok: bool = target != null and target.health < 100.0
	var melee_item: ItemData = InventoryManager.get_network_peer_equipped(peer, ItemData.ItemType.MeleeWeapon)
	var melee_endurance_ok: bool = melee_item == null or melee_item.endurance < 80
	var ok: bool = reload_ok and melee_requested and melee_damage_ok and melee_endurance_ok
	print("LAN_WEAPON_ACTIONS_PROBE=%s peer=%d reload=%s melee_request=%s melee_damage=%s melee_endurance=%s" % ["PASS" if ok else "FAIL", peer, reload_ok, melee_requested, melee_damage_ok, melee_endurance_ok])
	weapon_probe_targets.erase(peer)
	if target != null:
		target.queue_free()
	# Death drains the authoritative inventory, so it must run only after the
	# weapon/inventory probe has finished consuming that state. The vitals/HUD
	# probe also completes earlier while the weapon probe waits for reload.
	if "--lan-smoke-death=1" in OS.get_cmdline_user_args():
		rpc_id(peer, "prepare_death_probe")


class DeathScreenProbe:
	extends PlayerDeathEffectsController
	var shown := false
	func clear_menu_continue_save() -> void: pass
	func play_death_screen_and_go_to_menu() -> void: shown = true

@rpc("authority", "call_remote", "reliable")
func prepare_death_probe() -> void:
	var actor = get_parent().players[multiplayer.get_unique_id()]
	actor.death_effects_controller = DeathScreenProbe.new(actor)
	rpc_id(1, "death_probe_prepared")

@rpc("any_peer", "call_remote", "reliable")
func death_probe_prepared() -> void:
	if not NetworkManager.is_server(): return
	var peer := multiplayer.get_remote_sender_id()
	var actor = get_parent().players.get(peer)
	if actor == null: return
	var bag: ItemData = PROBE_DEATH_BAG.create_instance(1, 71)
	bag.runtime_storage_items.resize(maxi(bag.extra_storage_slots, 1))
	var food: ItemData = PROBE_DEATH_FOOD.create_instance(2)
	bag.runtime_storage_items[0] = food
	InventoryManager.set_network_peer_equipped(peer, ItemData.ItemType.Bag, bag)
	var expected_runtime_ids: Array[String] = [bag.get_runtime_id(), food.get_runtime_id()]
	actor.health = 0.0
	actor.die()
	actor.die() # Repeated damage/death must be harmless.
	# A delayed pre-death update must not restore health.
	actor.rpc_id(peer, "rpc_sync_vitals", peer, 100.0, false)
	await get_tree().create_timer(0.5).timeout
	var found_runtime_ids: Dictionary = {}
	for pickup in get_tree().get_nodes_in_group("world_pickup"):
		var item: ItemData = pickup.get("item_data") as ItemData
		if item != null:
			found_runtime_ids[item.get_runtime_id()] = true
	var drops_ok := true
	for runtime_id in expected_runtime_ids:
		drops_ok = drops_ok and found_runtime_ids.has(runtime_id)
	death_probe_server_ok[peer] = drops_ok and not actor.anim.visible and not InventoryManager.has_network_peer_inventory(peer)
	rpc_id(peer, "check_death_probe")

@rpc("authority", "call_remote", "reliable")
func check_death_probe() -> void:
	var actor = get_parent().players[multiplayer.get_unique_id()]
	var ok: bool = actor.is_dead and is_zero_approx(actor.health) and actor.death_effects_controller.shown
	print("LAN_DEATH_PROBE=%s dead=%s health=%s screen=%s" % ["PASS" if ok else "FAIL", actor.is_dead, actor.health, actor.death_effects_controller.shown])
	rpc_id(1, "report_death_probe", ok)

@rpc("any_peer", "call_remote", "reliable")
func report_death_probe(ok: bool) -> void:
	if not NetworkManager.is_server(): return
	var peer := multiplayer.get_remote_sender_id()
	var server_ok: bool = bool(death_probe_server_ok.get(peer, false))
	print("LAN_DEATH_PROBE=" + ("PASS" if ok and server_ok else "FAIL"))
