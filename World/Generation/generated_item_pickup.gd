extends "res://items/scripts/pickup_item.gd"

## Generated pickups keep a tombstone so a collected item does not respawn on load.
@export var persistent_id := ""

func _ready() -> void:
	if item_data != null:
		item_data = item_data.create_instance(1)
	add_to_group("generated_item_pickup")
	super._ready()

func get_save_key() -> String:
	return "generated_pickup:" + persistent_id

func get_save_data() -> Dictionary:
	return {"collected": _removed_from_world}

func apply_save_data(data: Dictionary) -> void:
	_removed_from_world = bool(data.get("collected", false))
	visible = not _removed_from_world
	set_deferred("monitoring", not _removed_from_world)
	set_deferred("monitorable", not _removed_from_world)
	if _removed_from_world:
		NearbyItemsManager.remove_item(self)
		remove_from_group("world_pickup")
	else:
		add_to_group("world_pickup")

func remove_from_world() -> void:
	if _removed_from_world: return
	apply_save_data({"collected": true})
	GameSaveManager.record_world_generation_object_state(self)
