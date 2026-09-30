extends Node

const BOX_SCENE := preload("res://World/Boxes/Box1/Box1.tscn")
const APPLE := preload("res://Resources/Food/apple.tres")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var box := BOX_SCENE.instantiate()
	add_child(box)
	_assert(box.loot_slot_count == 8, "Box1 must expose four rows of two slots")
	_assert(box.loot_slot_ids.size() == 8, "slot bindings must match visible capacity")
	var old_slots: Array = []
	for index in range(10):
		var item: ItemData = APPLE.create_instance(1)
		item.runtime_id = "legacy_box_item_%d" % index
		old_slots.append(GameSaveManager.serialize_item(item))
	box.apply_save_data({"loot_initialized": true, "loot_slots": old_slots})
	_assert(box.loot_slots.size() == 8, "old saves must migrate to eight visible slots")
	_assert(box._legacy_overflow_items.size() == 2, "overflow from old saves must be retained")
	var migrated: Dictionary = box.get_save_data()
	var restored := BOX_SCENE.instantiate()
	add_child(restored)
	restored.apply_save_data(migrated)
	_assert(restored.loot_slots.size() == 8 and restored._legacy_overflow_items.size() == 2, "migration must survive another save/load")
	var gui := preload("res://gui/GUI.tscn").instantiate()
	add_child(gui)
	var inventory_root := gui.get_node("InventoryRoot")
	inventory_root.open_loot_slots(restored.loot_slots, restored)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(inventory_root.loot_slots.size() == 8, "UI must create exactly eight Box1 slots")
	var panel_bottom: float = inventory_root.wardrobe_loot_panel.get_global_rect().end.y
	var last_slot_bottom: float = inventory_root.loot_slots[-1].get_global_rect().end.y
	_assert(last_slot_bottom <= panel_bottom, "last Box1 row must stay inside the loot panel")
	box.queue_free()
	restored.queue_free()
	gui.queue_free()
	print("BOX_LOOT_CAPACITY_TEST=PASS")
	get_tree().quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition: return
	push_error("Box loot capacity: " + message)
	get_tree().quit(1)
