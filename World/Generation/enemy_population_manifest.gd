class_name EnemyPopulationManifest
extends RefCounted
var owner_generated_object_id := ""
var profile_id := ""
var records: Array[EnemyPopulationRecord] = []
func canonical_record() -> Dictionary:
	var output:Array[Dictionary]=[]; for record in records: output.append(record.canonical_record())
	output.sort_custom(func(a,b):return String(a.population_id)<String(b.population_id))
	return {"owner_generated_object_id":owner_generated_object_id,"profile_id":profile_id,"records":output}
func manifest_hash() -> String: return GenerationHashes.sha256_of(canonical_record())
