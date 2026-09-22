extends Node
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _ready() -> void:
	call_deferred("run")
func run() -> void:
	check(multiplayer.multiplayer_peer == null, "fresh start is offline")
	var gui = preload("res://gui/GUI.tscn").instantiate()
	gui.name = "UI"
	add_child(gui)
	var players := Node2D.new()
	add_child(players)
	var actor = preload("res://Player/player.tscn").instantiate()
	players.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	var ui = gui.get_node("InventoryRoot")
	var wc = actor.weapon_controller
	wc.set_process(false)
	var bag = preload("res://Resources/Clothes/bag.tres").create_instance(1)
	InventoryManager.set_equipped(ItemData.ItemType.Bag, bag)
	var weapon = preload("res://Resources/AR_Weapons/akp_103/akp_103.tres").create_instance(1)
	InventoryManager.set_equipped(ItemData.ItemType.AR_Weapon, weapon)
	InventoryManager.set_active_weapon_slot(ItemData.ItemType.AR_Weapon)
	wc._update_current_weapon()
	wc._set_ammo_state(2, 5)
	var normal_speed: float = actor._get_current_speed_multiplier()
	wc._start_reload()
	check(wc.is_reloading and actor.action_in_progress, "reload starts real timed action")
	check(is_equal_approx(actor._get_current_speed_multiplier(), normal_speed * 0.5), "actual reload halves speed")
	check(wc._get_ammo_in_mag() == 2 and wc._get_reserve_ammo() == 5, "reload does not grant ammo early")
	wc._cancel_reload()
	check(not actor.action_in_progress and wc._get_ammo_in_mag() == 2 and wc._get_reserve_ammo() == 5, "cancel reload preserves ammo")
	wc._start_reload()
	actor.timed_action_controller.update_timed_action(10.0)
	check(wc._get_ammo_in_mag() == 7 and wc._get_reserve_ammo() == 0, "reload conserves ammo")
	check(not wc.is_reloading and is_equal_approx(actor._get_current_speed_multiplier(), normal_speed), "reload restores speed")
	var med = preload("res://Resources/Medicine/healthBox.tres").create_instance(1)
	bag.runtime_storage_items[0] = med
	ui.refresh_ui()
	actor.health = 10.0
	ui._begin_consumable(ui.storage_slots_by_type[ItemData.ItemType.Bag][0], 10.0)
	wc._set_ammo_state(7, 5)
	wc._start_reload()
	check(not wc.is_reloading and actor.action_blocks_movement, "cannot reload while healing")
	var fired: bool = wc.shooting_controller.shoot(Vector2.RIGHT, true)
	check(not fired and wc._get_ammo_in_mag() == 7, "cannot fire while healing")
	var save_path := "user://alpha_gameplay_flow_test.json"
	check(GameSaveManager.save_game(save_path) == OK, "save during healing succeeds")
	check(not actor.action_in_progress and bag.runtime_storage_items[0] == med and actor.health == 10.0, "save returns reserved medicine without healing")
	bag.runtime_storage_items[0] = null
	actor.health = 80.0
	check(GameSaveManager.load_game(save_path) == OK, "load saved game succeeds")
	await get_tree().process_frame
	await get_tree().process_frame
	var restored_bag = InventoryManager.get_equipped(ItemData.ItemType.Bag)
	check(restored_bag.runtime_storage_items[0] != null, "medicine survives save/load")
	check(actor.health == 10.0, "health restored")
	check(not actor.action_in_progress, "no stale action after load")
	wc._update_current_weapon()
	check(wc._get_ammo_in_mag() == 7 and wc._get_reserve_ammo() == 5, "ammo survives save/load")
	check(wc.shooting_controller.shoot(Vector2.RIGHT, true), "shoot succeeds after action")
	check(wc._get_ammo_in_mag() == 6 and wc._get_reserve_ammo() == 5, "shot spends exactly one round")
	await get_tree().create_timer(0.6).timeout
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	for failure in failures: push_error(failure)
	print("ALPHA_GAMEPLAY_FLOW_TEST=" + ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)
