extends Node
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _ready() -> void:
	call_deferred("run")
func run() -> void:
	var actor = preload("res://Player/player.tscn").instantiate()
	var gui = preload("res://gui/GUI.tscn").instantiate()
	gui.name = "UI"
	add_child(gui)
	var players := Node2D.new()
	add_child(players)
	players.add_child(actor)
	actor.set_physics_process(false)
	var ui = gui.get_node("InventoryRoot")
	var bag = preload("res://Resources/Clothes/bag.tres").duplicate(true)
	InventoryManager.set_equipped(ItemData.ItemType.Bag, bag)
	var weapon = preload("res://Resources/AR_Weapons/akp_52/akp_52.tres").duplicate(true)
	InventoryManager.set_equipped(ItemData.ItemType.AR_Weapon, weapon)
	InventoryManager.set_active_weapon_slot(ItemData.ItemType.AR_Weapon)
	var weapon_visual: EquipmentVisualSlot = null
	for visual_slot in actor.equipment_visual_slots:
		if visual_slot.item_type == ItemData.ItemType.AR_Weapon:
			weapon_visual = visual_slot
			break
	check(weapon_visual != null and weapon_visual.visible, "equipped weapon visible before use")
	ui.open_inventory()
	for count in [1, 3]:
		var food = preload("res://Resources/Food/apple.tres").duplicate(true)
		food.stack_count = count
		bag.runtime_storage_items[0] = food
		ui.refresh_ui()
		actor.food = 20.0
		ui._begin_consumable(ui.storage_slots_by_type[ItemData.ItemType.Bag][0], 0.8)
		check(not ui.is_inventory_open, "inventory must close")
		check(actor.action_in_progress, "action must start")
		check(weapon_visual != null and not weapon_visual.visible, "weapon hidden during Using action")
		check(bag.runtime_storage_items[0] == null if count == 1 else food.stack_count == count - 1, "reserve exactly one")
		check(actor._play_action_animation_if_available(), "Using animation must exist")
		Input.action_press("right")
		actor.movement_controller.movement_loop(0.1, ui, actor.weapon_controller)
		check(actor._get_network_input_vector() == Vector2.ZERO, "network input must be blocked")
		var locked_position: Vector2 = actor.global_position
		actor._apply_network_movement(0.1, Vector2.RIGHT)
		check(actor.velocity == Vector2.ZERO and actor.global_position == locked_position, "network movement must be blocked")
		check(actor.timed_action_controller.cancel_hint.is_visible_in_tree(), "cancel hint visible during use")
		Input.action_release("right")
		check(actor.action_in_progress and actor.velocity == Vector2.ZERO, "movement must not interrupt")
		var cancel = InputEventKey.new()
		cancel.physical_keycode = KEY_E
		cancel.pressed = true
		actor._unhandled_input(cancel)
		check(not actor.action_in_progress, "E must cancel")
		check(weapon_visual != null and weapon_visual.visible, "weapon restored after Using cancellation")
		check(not actor.timed_action_controller.cancel_hint.is_visible_in_tree(), "cancel hint hidden after cancel")
		actor._apply_network_movement(0.1, Vector2.RIGHT)
		check(actor.velocity.x > 0.0, "movement restored after cancel")
		check(bag.runtime_storage_items[0] == food and food.stack_count == count, "cancel restores original stack")
		check(actor.food == 20.0, "cancel must not apply effect")
		ui._begin_consumable(ui.storage_slots_by_type[ItemData.ItemType.Bag][0], 0.8)
		actor.timed_action_controller.update_timed_action(1.0)
		check(actor.food == 25.0, "food effect applied once")
		check(weapon_visual != null and weapon_visual.visible, "weapon restored after Using completion")
		actor.timed_action_controller.update_timed_action(1.0)
		check(actor.food == 25.0, "no duplicate effect")
		check(bag.runtime_storage_items[0] == null if count == 1 else food.stack_count == count - 1, "completion consumes exactly one")
	var med = preload("res://Resources/Medicine/healthBox.tres").duplicate(true)
	bag.runtime_storage_items[0] = med
	ui.refresh_ui()
	actor.health = 10.0
	ui._begin_consumable(ui.storage_slots_by_type[ItemData.ItemType.Bag][0], 10.0)
	check(bag.runtime_storage_items[0] == null, "medkit reserved")
	ui.cancel_pending_consumable()
	check(bag.runtime_storage_items[0] == med and actor.health == 10.0, "interruption returns medkit without healing")
	ui._begin_consumable(ui.storage_slots_by_type[ItemData.ItemType.Bag][0], 10.0)
	actor.timed_action_controller.update_timed_action(11.0)
	check(actor.health > 10.0 and bag.runtime_storage_items[0] == null, "medkit heals and consumed")
	actor.weapon_controller.is_reloading = false
	var normal: float = actor._get_current_speed_multiplier()
	actor.weapon_controller.is_reloading = true
	check(is_equal_approx(actor._get_current_speed_multiplier(), normal * 0.5), "reload halves speed")
	actor.weapon_controller.is_reloading = false
	check(is_equal_approx(actor._get_current_speed_multiplier(), normal), "speed restored")
	actor.velocity = Vector2.RIGHT * actor.base_move_speed
	actor._update_walk_snow_sfx(Vector2.RIGHT, 0.1)
	check(actor.walk_snow_sfx.playing and actor.walk_snow_sfx.stream == actor.WALK_SNOW_STREAM, "snow footsteps play outdoors")
	actor.add_to_group("inside_house")
	actor._update_walk_snow_sfx(Vector2.RIGHT, 0.1)
	check(actor.walk_snow_sfx.playing and actor.walk_snow_sfx.stream == actor.WALK_HOUSE_STREAM, "the sole footstep player switches to the house stream indoors")
	actor.weapon_controller._stop_weapon_audio()
	check(actor.walk_snow_sfx.playing, "weapon audio cleanup must not stop house footsteps")
	check(actor.walk_snow_sfx.stream != null and actor.walk_snow_sfx.stream.get_length() > 2.0, "house footstep loop is loaded")
	var house_walk_stream := actor.walk_snow_sfx.stream as AudioStreamWAV
	check(house_walk_stream != null and house_walk_stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "house footstep asset loops continuously")
	check(actor.walk_snow_sfx.volume_db >= 0.0, "house footsteps remain audible in the Sounds mix")
	actor.remove_from_group("inside_house")
	actor._update_walk_snow_sfx(Vector2.RIGHT, 0.1)
	check(actor.walk_snow_sfx.playing and actor.walk_snow_sfx.stream == actor.WALK_SNOW_STREAM, "the sole footstep player switches back to snow after leaving house")
	actor.velocity = Vector2.ZERO
	actor._update_walk_snow_sfx(Vector2.ZERO, 0.1)
	await get_tree().process_frame
	await get_tree().process_frame
	for failure in failures: push_error(failure)
	print("CONSUMABLE_ACTION_TEST=" + ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)
