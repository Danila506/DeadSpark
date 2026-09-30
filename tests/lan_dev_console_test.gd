extends Node

const GUI_SCENE := preload("res://gui/GUI.tscn")
const LAN_WORLD_SCENE := preload("res://World/network_test_world.tscn")

var failures: Array[String] = []


func _ready() -> void:
	_check_lan_ui_visibility()
	await _check_russian_console_toggle()
	for failure in failures:
		push_error(failure)
	print("LAN_DEV_CONSOLE_TEST=" + ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)


func _check_lan_ui_visibility() -> void:
	var world := LAN_WORLD_SCENE.instantiate()
	var ui := world.get_node_or_null("UI") as CanvasLayer
	_check(ui != null, "LAN UI missing")
	if ui != null:
		ui.visible = false
		world.call("_configure_local_lan_ui")
		_check(ui.visible, "LAN UI was not enabled for a local client")
	world.free()


func _check_russian_console_toggle() -> void:
	var gui := GUI_SCENE.instantiate()
	add_child(gui)
	await get_tree().process_frame
	var inventory_root := gui.get_node_or_null("InventoryRoot")
	_check(inventory_root != null, "inventory root missing")
	if inventory_root != null:
		var russian_layout_toggle := InputEventKey.new()
		russian_layout_toggle.pressed = true
		russian_layout_toggle.keycode = 0x0401
		russian_layout_toggle.physical_keycode = KEY_QUOTELEFT
		_check(
			bool(inventory_root.call("_handle_dev_console_input", russian_layout_toggle)),
			"Russian Ё key was not handled as the console toggle"
		)
		var console := inventory_root.get_node_or_null("DevConsole") as CanvasItem
		_check(console != null and console.visible, "developer console did not open")
	gui.queue_free()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
