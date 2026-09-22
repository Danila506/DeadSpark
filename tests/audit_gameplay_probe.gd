extends "res://tests/loot_ui_drag_test.gd"

class AuditSeed extends Node:
	func get_debug_world_generation_info() -> Dictionary: return {"seed": 1337}

func _run() -> void:
	var gui := preload("res://gui/GUI.tscn").instantiate()
	add_child(gui)
	ui = gui.get_node("InventoryRoot")
	var player := CharacterBody2D.new()
	player.add_to_group("player")
	add_child(player)
	var food := preload("res://Resources/Food/apple.tres").create_instance(1)
	var items: Array[ItemData] = [food, null]
	ui.open_loot_slots(items)
	await get_tree().process_frame
	await get_tree().process_frame
	var source: InventorySlot = ui.loot_slots[0]
	var target: InventorySlot
	for slot in ui.equipment_slots:
		if slot.slot_type == ItemData.ItemType.Cap: target = slot; break
	var start := source.get_global_rect().get_center()
	var end := target.get_global_rect().get_center()
	await _motion(start)
	await _button(start, true)
	await _motion(start + Vector2(20, 0), true, Vector2(20, 0))
	print("AUDIT invalid_drop_drag_started=", get_viewport().gui_is_dragging())
	await _motion(end, true, end - start)
	await _button(end, false)
	_check(items[0] == food and get_tree().get_nodes_in_group("world_pickup").is_empty(), "invalid drop discarded item")
	print("AUDIT invalid_drop_source_empty=", items[0] == null, " world_pickups=", get_tree().get_nodes_in_group("world_pickup").size())
	ui._finish_mobile_slot_drag(end, ui._build_drag_data_for_slot(ui.loot_slots[0]))
	_check(items[0] == food, "touch invalid drop discarded item")
	ui._hide_action_buttons()
	await _motion(start)
	await _button(start, true)
	await _motion(start + Vector2(20, 0), true, Vector2(20, 0))
	await _motion(Vector2(20, 20), true, Vector2(20, 20) - start)
	await _button(Vector2(20, 20), false)
	_check(items[0] == null and get_tree().get_nodes_in_group("world_pickup").size() == 1, "intentional outside drop stopped working")
	var box := preload("res://World/Boxes/Box1/Box1.tscn").instantiate()
	box.position = Vector2(5000, 5000)
	add_child(box)
	ui.open_loot_slots(items)
	box._on_interact_area_body_entered(player)
	box._on_interact_area_body_exited(player)
	_check(ui.loot_context_active, "neighbor closed loot")
	ui.open_loot_slots(items, box)
	box._set_loot_panel_state(false)
	_check(not ui.loot_context_active and ui.nearby_panel.visible, "owner did not close loot")
	ui.open_loot_slots(items)
	print("AUDIT unopened_neighbor_closed_loot=", not ui.loot_context_active)
	box.queue_free()
	await get_tree().process_frame
	await _audit_tree_identity()
	var battery := preload("res://Resources/Misc/batteries.tres").create_instance(1)
	battery.battery_charge_seconds = 10.0
	var restored_battery := GameSaveManager.deserialize_item(GameSaveManager.serialize_item(battery))
	var copied_battery := battery.create_runtime_copy()
	print("AUDIT battery_before=", battery.battery_charge_seconds, " after_save=", restored_battery.battery_charge_seconds, " after_drop_copy=", copied_battery.battery_charge_seconds)

	for failure in failures: push_error(failure)
	print("REMAINING_GAMEPLAY_FIXES_TEST=" + ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)

func _audit_tree_identity() -> void:
	var world := Node2D.new(); world.name = "AuditWorld"; add_child(world)
	var seed := AuditSeed.new(); seed.name = "Seed"; world.add_child(seed)
	var poi := PoiPlacementPass.new(); poi.name = "Poi"; world.add_child(poi)
	poi.occupancy.reset(Rect2i(Vector2i.ZERO, Vector2i(16, 16)))
	var target := Node2D.new(); target.name = "Trees"; world.add_child(target)
	var generator := EnvironmentGenerationPass.new(); generator.name = "Environment"; world.add_child(generator)
	var entry := EnvironmentEntry.new(); entry.entry_id = "audit_tree"; entry.category = "trees"; entry.scene = preload("res://World/Assets/Biom1/Tree.tscn"); entry.target_path = NodePath("../Trees"); entry.density = 0.5; entry.max_instances_per_chunk = 5; entry.minimum_spacing_cells = 0
	var profile := EnvironmentGenerationProfile.new(); profile.profile_id = "audit"; profile.clearance_cells = 0; profile.entries = [entry]
	generator.profile = profile; generator.poi_pass_path = NodePath("../Poi"); generator.world_seed_source_path = NodePath("../Seed")
	generator.run_generation_pass()
	var keys := {}
	for tree in target.get_children():
		keys[tree.get_meta("generated_object_id")] = tree.get_save_key()
		GameSaveManager._pending_world_nodes[tree.get_save_key()] = {"chop_hits": 3, "is_felled": true}
	GameSaveManager._has_pending_load = true
	generator.run_generation_pass()
	var changed := 0
	var restored := 0
	for tree in target.get_children():
		if keys.get(tree.get_meta("generated_object_id")) != tree.get_save_key(): changed += 1
		if tree.is_felled: restored += 1
	print("AUDIT same_seed_tree_save_keys_changed=", changed, "/", keys.size(), " felled_states_restored=", restored)
	GameSaveManager._has_pending_load = false
	GameSaveManager._pending_world_nodes.clear()
	_check(changed == 0 and restored == keys.size(), "tree state lost")
	var synchronous: String = generator.get_generation_output_manifest().environment_content_hash
	await generator.run_generation_pass_async(1.0)
	_check(generator.get_generation_output_manifest().environment_content_hash == synchronous, "async changed placements")
	print("AUDIT async_matches_sync=", generator.get_generation_output_manifest().environment_content_hash == synchronous)
