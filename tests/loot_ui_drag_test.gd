extends Node

var failures: Array[String] = []
var ui: Control

func _ready() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _motion(point: Vector2, held := false, relative := Vector2.ZERO) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	get_viewport().push_input(event, true)
	await get_tree().process_frame

func _button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	get_viewport().push_input(event, true)
	await get_tree().process_frame

func _run() -> void:
	var gui := preload("res://gui/GUI.tscn").instantiate()
	add_child(gui)
	ui = gui.get_node("InventoryRoot")
	var bag := preload("res://Resources/Clothes/bag.tres").duplicate(true) as ItemData
	InventoryManager.set_equipped(ItemData.ItemType.Bag, bag)
	for context in [&"wardrobe", &"bandit"]:
		var food := preload("res://Resources/Food/apple.tres").duplicate(true) as ItemData
		var items: Array[ItemData] = [food, null, null, null]
		if context == &"bandit": ui.open_bandit_loot_slots(items)
		else: ui.open_loot_slots(items)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(ui.loot_slots.size() == 4, "empty slots missing")
		var slot: InventorySlot = ui.loot_slots[0]
		var empty: InventorySlot = ui.loot_slots[1]
		_check(slot.background.is_visible_in_tree() and empty.background.is_visible_in_tree(), "slot backgrounds hidden")
		var panel: Control = ui.bandit_loot_panel if context == &"bandit" else ui.wardrobe_loot_panel
		var decoration: Control = ui.bandit_loot_panel_texture if context == &"bandit" else ui.wardrobe_loot_panel_texture
		_check(decoration.get_index() < panel.get_node("CenterContainer").get_index(), "background covers grid")
		var source := slot.get_global_rect().get_center()
		await _motion(source)
		_check(get_viewport().gui_get_hovered_control() == slot, "slot mouse input obstructed: %s" % get_viewport().gui_get_hovered_control())
		var target: InventorySlot = ui.storage_slots_by_type[ItemData.ItemType.Bag][0 if context == &"wardrobe" else 1]
		var destination := target.get_global_rect().get_center()
		await _button(source, true)
		await _motion(source + Vector2(20, 0), true, Vector2(20, 0))
		_check(get_viewport().gui_is_dragging(), "drag did not start")
		await _motion(destination, true, destination - source)
		await _button(destination, false)
		_check(items[0] == null, "source item remained after drop")
		_check(bag.runtime_storage_items.has(food), "item not transferred to inventory")
		_check(ui.loot_slots[0].item_data == null, "source UI not refreshed")
		print("LOOT_UI_CONTEXT=", context, " failures=", failures)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/artifacts/loot_ui.png")
	for failure in failures: push_error(failure)
	print("LOOT_UI_DRAG_TEST=" + ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)
