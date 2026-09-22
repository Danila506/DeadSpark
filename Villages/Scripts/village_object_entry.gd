extends Resource
class_name VillageObjectEntry

@export var scene: PackedScene
@export var entry_id := ""
@export_range(0.0, 1000.0, 0.01, "or_greater") var weight: float = 1.0
@export var tags: Array[String] = []
@export var unique_per_template := false
@export var enabled := true


func is_valid_entry() -> bool:
	return scene != null and weight > 0.0 and enabled and not entry_id.is_empty()
