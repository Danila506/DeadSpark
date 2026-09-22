extends Node2D
var position_at_ready := Vector2.ZERO
var persistent_value := 0
func _ready() -> void:
	position_at_ready = global_position

func get_save_data() -> Dictionary:
	return {"persistent_value": persistent_value}

func apply_save_data(data: Dictionary) -> void:
	persistent_value = int(data.get("persistent_value", persistent_value))
