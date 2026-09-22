extends Node

const VILLAGE := preload("res://Villages/Village.tscn")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var village := VILLAGE.instantiate() as VillageGenerator
	_assert(village != null, "Village.tscn must instantiate")
	add_child(village)
	await get_tree().process_frame
	village.generate_from_poi("scene-test-poi")
	await get_tree().process_frame
	var generated := village.get_node_or_null("GeneratedContent")
	_assert(generated != null, "GeneratedContent must exist")
	_assert(generated.get_child_count() == 25, "Village parity counts must be 6+3+16")
	var hash_a := village.get_village_content_hash()
	var selected: Dictionary = {}
	for node in generated.get_children():
		var object_id := String(node.get_meta("generated_object_id", ""))
		_assert(object_id.begins_with("v2/poi:"), "GeneratedObjectId must identify a POI slot")
		_assert(not object_id.contains(String(node.get_meta("selected_entry_id", ""))), "GeneratedObjectId must not contain selected entry_id")
		selected[object_id] = String(node.get_meta("selected_entry_id", ""))
	_assert(selected.size() == 25, "GeneratedObjectIds must be unique")
	_assert(village.get_node("StaticContent").is_inside_tree(), "Authored static content must remain")
	village.clear_generated()
	_assert(generated.get_child_count() > 0, "queue_free deletion is deferred")
	await get_tree().process_frame
	_assert(generated.get_child_count() == 0, "GeneratedContent must clear after process_frame")
	_assert(village.get_node("Houses").is_inside_tree(), "Authored groups must remain")
	village.generate()
	await get_tree().process_frame
	_assert(hash_a == village.get_village_content_hash(), "Repeated Village generation must be deterministic")
	_assert(generated.get_child_count() == 25, "Repeated Village generation preserves parity")
	for group in ["Houses", "Remains", "SmallObjects"]:
		for marker in village.get_node(group).get_spawn_markers():
			_assert(not String(marker.get_meta("stable_id", "")).is_empty(), "All structural markers need stable IDs")
	for node in generated.get_children():
		_assert(node is Node2D, "All approved PackedScene entries must instantiate as Node2D")
	await _test_permutation_and_uniqueness()
	print("VILLAGE_SCENE_TEST=" + JSON.stringify({"hash": hash_a, "selected": selected}))
	get_tree().quit(0)

func _test_permutation_and_uniqueness() -> void:
	var groups_a := await _make_test_village(false, false)
	var groups_b := await _make_test_village(true, false)
	_assert(groups_a.get_village_content_hash() == groups_b.get_village_content_hash(), "VillageSpawnGroup order must not change selections")
	var markers_a := await _make_test_village(false, false)
	var markers_b := await _make_test_village(false, true)
	_assert(markers_a.get_village_content_hash() == markers_b.get_village_content_hash(), "Marker order must not change content hash")
	_assert(_selection_manifest(markers_a) == _selection_manifest(markers_b), "Marker order must not change GeneratedObjectIds")
	var unique := await _make_test_village(false, false, true)
	var selected := _selection_manifest(unique)
	var unique_count := 0
	for entry_id in selected.values():
		if entry_id == "shared_unique": unique_count += 1
	_assert(unique_count == 1, "unique_per_template may be selected only once across groups")
	var insufficient := await _make_test_village(false, false, false, true)
	_assert(insufficient.get_node("GeneratedContent").get_child_count() == 0, "Insufficient unique pool blocks generation")
	_assert(not insufficient.last_generation_errors.is_empty() and insufficient.last_generation_errors[0].contains("profile=unique_profile") and insufficient.last_generation_errors[0].contains("pool=unique_pool") and insufficient.last_generation_errors[0].contains("required=2") and insufficient.last_generation_errors[0].contains("available=1"), "Blocking unique error contains profile/pool/group/required/available")

func _make_test_village(reverse_groups: bool, reverse_markers: bool, cross_group_unique: bool = false, insufficient_unique: bool = false) -> VillageGenerator:
	var village := VillageGenerator.new()
	village.generation_seed = 777
	var generated := Node2D.new()
	generated.name = "GeneratedContent"
	village.spawn_parent_path = NodePath("GeneratedContent")
	village.add_child(generated)
	var entries: Array[VillageObjectEntry] = []
	var shared := _entry("shared_unique", true, true, 1.0)
	if insufficient_unique:
		entries.append(shared)
		entries.append(_entry("disabled", true, false, 1.0))
		entries.append(_entry("zero_weight", true, true, 0.0))
		village.add_child(_group("only", entries, 2, reverse_markers))
	else:
		var first_entries: Array[VillageObjectEntry] = []
		var second_entries: Array[VillageObjectEntry] = []
		if cross_group_unique:
			first_entries.append(shared)
			second_entries.append(shared)
			second_entries.append(_entry("fallback", false, true, 1.0))
		else:
			first_entries.append(_entry("alpha", false, true, 1.0))
			first_entries.append(_entry("beta", false, true, 1.0))
			second_entries.append(_entry("gamma", false, true, 1.0))
			second_entries.append(_entry("delta", false, true, 1.0))
		var spawn_count := 1 if cross_group_unique else 2
		var first := _group("a", first_entries, spawn_count, reverse_markers)
		var second := _group("b", second_entries, spawn_count, reverse_markers)
		if reverse_groups:
			village.add_child(second); village.add_child(first)
		else:
			village.add_child(first); village.add_child(second)
	add_child(village)
	await get_tree().process_frame
	village.generate_from_poi("permutation-poi")
	await get_tree().process_frame
	return village

func _entry(id: String, unique: bool, enabled: bool, weight: float) -> VillageObjectEntry:
	var entry := VillageObjectEntry.new()
	entry.entry_id = id
	entry.unique_per_template = unique
	entry.enabled = enabled
	entry.weight = weight
	entry.scene = preload("res://World/Assets/Village/Ruins.tscn")
	return entry

func _group(id: String, entries: Array[VillageObjectEntry], count: int, reverse_markers: bool) -> VillageSpawnGroup:
	var pool := VillageObjectPool.new()
	pool.pool_id = "unique_pool" if id == "only" else "pool_" + id
	pool.entries = entries
	var profile := VillageSpawnProfile.new()
	profile.profile_id = "unique_profile" if id == "only" else "profile_" + id
	profile.object_pool = pool
	profile.min_spawn_count = count
	profile.max_spawn_count = count
	var group := VillageSpawnGroup.new()
	group.group_id = id
	group.spawn_profile = profile
	for suffix in ["01", "02"]:
		var marker := Marker2D.new()
		marker.set_meta("stable_id", "m_" + id + "_" + suffix)
		group.add_child(marker)
	if reverse_markers:
		group.move_child(group.get_child(0), 1)
	return group

func _selection_manifest(village: VillageGenerator) -> Dictionary:
	var result := {}
	for node in village.get_node("GeneratedContent").get_children():
		result[String(node.get_meta("generated_object_id"))] = String(node.get_meta("selected_entry_id"))
	return result

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("Village scene test: " + message)
	get_tree().quit(1)
