extends Node

const MENU_SCENE := preload("res://Menu/Menu.tscn")
const GUI_SCENE := preload("res://gui/GUI.tscn")

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var menu := MENU_SCENE.instantiate()
	add_child(menu)
	await get_tree().process_frame

	var button_sfx := get_tree().root.get_node_or_null("MenuButtonPressSFX") as AudioStreamPlayer
	_check(button_sfx != null, "main menu creates one button SFX player")
	if button_sfx != null:
		_check(button_sfx.stream is AudioStreamWAV, "main menu button WAV is assigned")
		_check(button_sfx.bus == &"Sounds", "main menu button SFX uses the Sounds bus")

	var menu_root := menu.get_node("MainMenuCanvas/MainMenuRoot") as Control
	var button_callback := Callable(menu, "_play_button_press_sound")
	var menu_buttons := menu_root.find_children("*", "BaseButton", true, false)
	_check(menu_buttons.size() >= 10, "main and LAN menu buttons are discovered")
	for node in menu_buttons:
		var button := node as BaseButton
		_check(button != null and button.pressed.is_connected(button_callback), "%s has button SFX" % node.name)

	menu.queue_free()
	await get_tree().process_frame

	var gui := GUI_SCENE.instantiate()
	add_child(gui)
	await get_tree().process_frame
	var inventory_root := gui.get_node("InventoryRoot")
	var inventory_sfx := inventory_root.get_node_or_null("InventoryOpenSFX") as AudioStreamPlayer
	_check(inventory_sfx != null, "inventory creates its open SFX player")
	if inventory_sfx != null:
		_check(inventory_sfx.stream is AudioStreamWAV, "inventory open WAV is assigned")
		_check(inventory_sfx.bus == &"Sounds", "inventory open SFX uses the Sounds bus")

	inventory_root.call("open_inventory")
	_check(bool(inventory_root.get("is_inventory_open")), "inventory opens through the existing entry point")
	_check((inventory_root.get_node("InventoryContent") as Control).visible, "inventory content becomes visible")

	gui.queue_free()
	await get_tree().process_frame
	for failure in failures:
		push_error("UI audio feedback: " + failure)
	print("UI_AUDIO_FEEDBACK_TEST=" + ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
