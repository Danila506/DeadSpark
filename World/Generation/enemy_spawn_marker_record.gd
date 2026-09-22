class_name EnemySpawnMarkerRecord
extends RefCounted
var marker_id := ""
var position := Vector2.ZERO
var tags: Array[String] = []
var enabled := true
var capacity := 1
var exclusion_flags: Array[String] = []
func canonical_record() -> Dictionary:
	var ordered:=tags.duplicate(); ordered.sort(); var exclusions:=exclusion_flags.duplicate(); exclusions.sort(); return {"marker_id":marker_id,"position":position,"tags":ordered,"enabled":enabled,"capacity":capacity,"exclusion_flags":exclusions}
