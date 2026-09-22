class_name EnemyPopulationRecord
extends RefCounted
var population_id := ""
var owner_generated_object_id := ""
var marker_id := ""
var profile_id := ""
var enemy_entry_id := ""
var enemy_resource_key := ""
var position := Vector2.ZERO
var ordinal := 0
var initial_state := "alive"
var materialization_state := "not_materialized"
func canonical_record() -> Dictionary: return {"population_id":population_id,"owner_generated_object_id":owner_generated_object_id,"marker_id":marker_id,"profile_id":profile_id,"enemy_entry_id":enemy_entry_id,"enemy_resource_key":enemy_resource_key,"position":position,"ordinal":ordinal,"initial_state":initial_state,"materialization_state":materialization_state}
