@tool
class_name LootEntry
extends Resource

## Authored deterministic loot candidate. entry_id, rather than its array
## position or display name, is the generative identity.
@export var entry_id := ""
@export var item: Resource
@export_range(0.0, 100000.0, 0.001) var weight := 1.0
@export_range(1, 999, 1) var min_quantity := 1
@export_range(1, 999, 1) var max_quantity := 1
@export var enabled := true
@export var unique := false

func validate() -> Dictionary:
	var errors: Array[String] = []
	if entry_id.is_empty(): errors.append("MISSING_ENTRY_ID")
	if item == null: errors.append("MISSING_ITEM_RESOURCE")
	if weight < 0.0: errors.append("NEGATIVE_WEIGHT")
	if min_quantity < 1 or max_quantity < min_quantity: errors.append("INVALID_QUANTITY_RANGE")
	return {"valid": errors.is_empty(), "errors": errors}

func item_resource_key() -> String:
	return item.resource_path if item != null else ""

func canonical_record() -> Dictionary:
	return {"entry_id": entry_id, "item_resource_key": item_resource_key(), "weight": weight, "min_quantity": min_quantity, "max_quantity": max_quantity, "enabled": enabled, "unique": unique}
