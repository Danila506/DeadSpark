class_name LootSlotRecord
extends RefCounted

var container_generated_id := ""
var profile_id := ""
var slot_id := ""
var item_resource_key := ""
var quantity := 0
var deterministic_ordinal := 0

func canonical_record() -> Dictionary:
	return {"container_generated_id": container_generated_id, "profile_id": profile_id, "slot_id": slot_id, "item_resource_key": item_resource_key, "quantity": quantity, "deterministic_ordinal": deterministic_ordinal}
