extends "res://tests/loot_ui_drag_test.gd"

const ENTRY = preload("res://Resources/WorldGen/Containers/medicine_kit.tres")

func _spawn() -> Node2D:
	var pickup := ENTRY.scene.instantiate() as Node2D
	EnvironmentContentInitializer.prepare(pickup, "medical_test_01", ENTRY)
	add_child(pickup)
	EnvironmentContentInitializer.materialize(pickup, 1337)
	return pickup

func _run() -> void:
	GameSaveManager.set_world_generation_seed(1337)
	var gui := preload("res://gui/GUI.tscn").instantiate()
	add_child(gui)
	ui = gui.get_node("InventoryRoot")
	var bag := preload("res://Resources/Clothes/bag.tres").create_instance(1)
	InventoryManager.set_equipped(ItemData.ItemType.Bag, bag)
	var player := CharacterBody2D.new()
	player.add_to_group("player")
	add_child(player)
	var pickup := _spawn()
	_check(not pickup.has_method("get_loot_container_id"), "medical kit still a loot container")
	_check(pickup.item_data.item_name == "Медицинский набор", "wrong item")
	_check(pickup.item_data.inventory_icon != null and pickup.item_data.medical_health_restore == 75.0, "medical properties missing")
	pickup._on_body_entered(player)
	ui.open_inventory()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not ui.loot_context_active, "container panel opened")
	var source: InventorySlot = ui.nearby_slots[0]
	var target: InventorySlot = ui.storage_slots_by_type[ItemData.ItemType.Bag][0]
	var start := source.get_global_rect().get_center()
	var end := target.get_global_rect().get_center()
	await _motion(start)
	await _button(start, true)
	await _motion(start + Vector2(20, 0), true, Vector2(20, 0))
	await _motion(end, true, end - start)
	await _button(end, false)
	_check(bag.runtime_storage_items[0] == pickup.item_data, "kit not moved into inventory")
	_check(not pickup.visible and pickup.get_save_data().collected, "pickup not removed")
	_check(GameSaveManager._collect_world_pickups(self).is_empty(), "generated kit saved as loose duplicate")
	var saved_inventory := GameSaveManager.serialize_item(bag)
	_check(GameSaveManager.deserialize_item(saved_inventory).runtime_storage_items[0].item_name == "Медицинский набор", "inventory save failed")
	pickup.free()
	var restored := _spawn()
	_check(not restored.visible and restored.get_save_data().collected, "collected kit respawned")
	for failure in failures: push_error(failure)
	print("MEDICAL_KIT_PICKUP_TEST=" + ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)
