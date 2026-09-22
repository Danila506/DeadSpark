extends Node

const BATTERY = preload("res://Resources/Misc/batteries.tres")
const BAG = preload("res://Resources/Clothes/bag.tres")
var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _roundtrip(item: ItemData) -> ItemData:
	return GameSaveManager.deserialize_item(JSON.parse_string(JSON.stringify(GameSaveManager.serialize_item(item))))

func _run() -> void:
	var gui := preload("res://gui/GUI.tscn").instantiate()
	add_child(gui)
	var ui := gui.get_node("InventoryRoot")
	var player := Node2D.new()
	player.add_to_group("player")
	add_child(player)
	for charge in [0.0, 10.25, 480.0]:
		var battery := BATTERY.create_instance(1)
		battery.battery_charge_seconds = charge
		_check(_roundtrip(battery).battery_charge_seconds == charge, "save charge %s" % charge)
		_check(battery.create_runtime_copy().battery_charge_seconds == charge, "copy charge %s" % charge)
		battery.refresh_definition_values(BATTERY)
		_check(battery.battery_charge_seconds == charge, "definition refresh charge %s" % charge)
		var provider := BAG.create_instance(1)
		provider.runtime_storage_items = [battery]
		_check(_roundtrip(provider).runtime_storage_items[0].battery_charge_seconds == charge, "nested save charge %s" % charge)
		_check(provider.create_runtime_copy().runtime_storage_items[0].battery_charge_seconds == charge, "nested copy charge %s" % charge)
		var plain := BATTERY
		var original_charge: float = plain.battery_charge_seconds
		plain.battery_charge_seconds = charge
		_check(_roundtrip(plain).battery_charge_seconds == charge, "plain resource charge %s" % charge)
		plain.battery_charge_seconds = original_charge
		_check(ui._spawn_world_item(battery), "world drop failed")
		var pickup := player.get_parent().get_child(player.get_parent().get_child_count() - 1)
		_check(pickup.get("item_data").battery_charge_seconds == charge, "world pickup charge %s" % charge)
		pickup.queue_free()
		battery.stack_count = 2
		var split: ItemData = ui._take_one_battery_from_drag_source({"item": battery})
		_check(split.battery_charge_seconds == charge and battery.stack_count == 1, "split or install recharged battery %s" % charge)
	var legacy := GameSaveManager.serialize_item(BATTERY.create_instance(1))
	legacy.erase("battery_charge_seconds")
	_check(GameSaveManager.deserialize_item(legacy).battery_charge_seconds == BATTERY.battery_charge_seconds, "legacy save default")
	for failure in failures: push_error(failure)
	print("BATTERY_CHARGE_PERSISTENCE_TEST=" + ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)
