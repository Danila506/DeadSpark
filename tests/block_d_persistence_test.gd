extends Node

const PATH := "user://block_d_persistence_profile.tres"
const ENV_PASS = preload("res://World/Generation/environment_generation_pass.gd")
const POI_PASS = preload("res://World/Generation/poi_placement_pass.gd")
const ENTRY = preload("res://World/Generation/environment_entry.gd")
const PROFILE = preload("res://World/Generation/environment_generation_profile.gd")
const TREE = preload("res://World/Assets/Biom1/Tree.tscn")

class Seed extends Node:
	func get_debug_world_generation_info() -> Dictionary: return {"seed": 1337}

func _ready() -> void: call_deferred("_run")
func _run() -> void:
	var original := _profile(["tree_a", "tree_b"])
	_assert(ResourceSaver.save(original, PATH) == OK, "initial ResourceSaver save")
	var loaded := _load_fresh()
	_assert(loaded != null and loaded != original, "ResourceLoader CACHE_MODE_IGNORE reload")
	_assert(_record(original) == _record(loaded), "profile fields and stable resource keys persist")
	var before := await _generate(original)
	var after := await _generate(loaded)
	_assert(before == after, "save/reopen production generation equivalence")
	_assert(ResourceSaver.save(loaded, PATH) == OK, "idempotent resave")
	var reloaded := _load_fresh()
	_assert(_record(loaded) == _record(reloaded), "resave canonical resource record")
	_assert(before == await _generate(reloaded), "resave generation equivalence")
	var reversed := _profile(["tree_b", "tree_a"])
	_assert(ResourceSaver.save(reversed, PATH) == OK, "reversed profile save")
	_assert(before == await _generate(_load_fresh()), "entry reorder after reload")
	var renamed := _profile(["tree_a", "tree_b"]); renamed.resource_name = "display-only"; renamed.entries[0].resource_name = "renamed-entry"
	_assert(ResourceSaver.save(renamed, PATH) == OK, "renamed display save")
	_assert(before == await _generate(_load_fresh()), "resource display names do not affect output")
	var invalid := _profile(["duplicate", "duplicate"])
	_assert(ResourceSaver.save(invalid, PATH) == OK, "invalid profile persists for validation")
	var invalid_loaded := _load_fresh()
	_assert(not bool(invalid_loaded.validate().valid), "duplicate stable IDs block after reload")
	var missing := _profile([""])
	_assert(ResourceSaver.save(missing, PATH) == OK, "missing-id profile persists")
	_assert(not bool(_load_fresh().validate().valid), "missing stable ID blocks after reload")
	var canonical := {"profile":_record(reloaded), "generation":before}
	print("BLOCK_D_PERSISTENCE_DIGEST=" + GenerationHashes.sha256_of(canonical))
	print("BLOCK_D_PERSISTENCE_TEST=PASS")
	get_tree().quit(0)

func _profile(ids: Array) -> EnvironmentGenerationProfile:
	var profile: EnvironmentGenerationProfile = PROFILE.new(); profile.profile_id = "persistence_environment"; profile.logical_cell_size = Vector2.ONE; profile.clearance_cells = 1
	for id in ids:
		var entry: EnvironmentEntry = ENTRY.new(); entry.entry_id = String(id); entry.category = "trees"; entry.kind = EnvironmentEntry.Kind.SCENE; entry.target_path = NodePath("../SceneTarget"); entry.scene = TREE
		entry.enabled = true; entry.density = 0.35; entry.max_instances = 5; entry.candidate_budget = 64; entry.minimum_spacing_cells = 1; entry.footprint_size = Vector2i.ONE
		profile.entries.append(entry)
	return profile
func _load_fresh() -> EnvironmentGenerationProfile:
	return ResourceLoader.load(PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as EnvironmentGenerationProfile
func _record(profile: EnvironmentGenerationProfile) -> Dictionary:
	var entries: Array[Dictionary] = []
	for entry in profile.entries: entries.append(entry.fingerprint())
	entries.sort_custom(func(a, b): return String(a.entry_id) < String(b.entry_id))
	return {"id":profile.profile_id, "cell":profile.logical_cell_size, "clearance":profile.clearance_cells, "entries":entries}
func _generate(profile: EnvironmentGenerationProfile) -> Dictionary:
	var root := Node.new(); add_child(root)
	var seed := Seed.new(); seed.name = "Seed"; root.add_child(seed)
	var poi: PoiPlacementPass = POI_PASS.new(); poi.name = "Poi"; root.add_child(poi); poi.occupancy.reset(Rect2i(Vector2i.ZERO, Vector2i(16, 16)))
	var target := Node2D.new(); target.name = "SceneTarget"; root.add_child(target)
	var generator: EnvironmentGenerationPass = ENV_PASS.new(); root.add_child(generator); generator.profile = profile; generator.poi_pass_path = NodePath("../Poi"); generator.world_seed_source_path = NodePath("../Seed")
	generator.run_generation_pass()
	var output := generator.get_generation_output_manifest()
	var result := {"accepted":output.accepted, "rejections":output.rejection_counts, "claims":poi.occupancy.canonical_manifest(), "manifest":output.environment_manifest_hash, "content":output.environment_content_hash}
	root.queue_free(); await get_tree().process_frame; await get_tree().process_frame
	return result
func _assert(condition: bool, message: String) -> void:
	if condition: return
	push_error("Block D persistence test: " + message)
	get_tree().quit(1)
