class_name EnemyPopulationProfile
extends Resource

@export var profile_id := ""
@export var enabled := true
@export var entries: Array[EnemyPopulationEntry] = []
@export var min_total_count := 0
@export var max_total_count := 999999
@export var allow_empty := false
@export var per_marker_cap := 1
@export var spawn_budget := 999999

func validate() -> Dictionary:
	var errors: Array[String]=[]; var seen := {}; var valid_entries:=0
	if profile_id.is_empty(): errors.append("MISSING_PROFILE_ID")
	if min_total_count<0 or max_total_count<min_total_count or spawn_budget<0 or per_marker_cap<0: errors.append("INVALID_COUNT_OR_BUDGET")
	for entry in entries:
		if entry==null: errors.append("MISSING_ENTRY"); continue
		if seen.has(entry.entry_id): errors.append("DUPLICATE_ENTRY_ID:%s"%entry.entry_id)
		seen[entry.entry_id]=true
		for error in entry.validate().errors: errors.append("%s:%s"%[error,entry.entry_id])
		if entry.enabled and entry.validate().valid: valid_entries+=1
	if enabled and not allow_empty and valid_entries==0: errors.append("PROFILE_REQUIRES_VALID_ENTRIES")
	return {"valid":errors.is_empty(),"errors":errors}

func canonical_record() -> Dictionary:
	var records:Array[Dictionary]=[]; for entry in entries: if entry!=null: records.append(entry.canonical_record())
	records.sort_custom(func(a,b):return String(a.entry_id)<String(b.entry_id))
	return {"profile_id":profile_id,"enabled":enabled,"entries":records,"min_total_count":min_total_count,"max_total_count":max_total_count,"allow_empty":allow_empty,"per_marker_cap":per_marker_cap,"spawn_budget":spawn_budget}
