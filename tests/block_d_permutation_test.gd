extends Node

const ENV_PASS = preload("res://World/Generation/environment_generation_pass.gd")
const POI_PASS = preload("res://World/Generation/poi_placement_pass.gd")
const ENTRY = preload("res://World/Generation/environment_entry.gd")
const PROFILE = preload("res://World/Generation/environment_generation_profile.gd")
const TREE = preload("res://World/Assets/Biom1/Tree.tscn")

class SeedSource extends Node:
	func get_debug_world_generation_info() -> Dictionary: return {"seed": 1337}

func _ready() -> void: call_deferred("_run")
func _run() -> void:
	var baseline := await _scenario("original", ["tree_a", "tree_b", "tree_c"], ["road", "water", "poi"], false)
	for scenario in [
		["reversed_entries", ["tree_c", "tree_b", "tree_a"], ["road", "water", "poi"], false],
		["shuffled_entries", ["tree_b", "tree_c", "tree_a"], ["road", "water", "poi"], false],
		["occupancy_reverse", ["tree_a", "tree_b", "tree_c"], ["poi", "water", "road"], false],
		["debug_and_child_reorder", ["tree_a", "tree_b", "tree_c"], ["road", "water", "poi"], true],
		["combined", ["tree_c", "tree_a", "tree_b"], ["poi", "road", "water"], true],
	]:
		var result := await _scenario(String(scenario[0]), scenario[1], scenario[2], bool(scenario[3]))
		_assert(result.digest == baseline.digest, "%s changed canonical output" % scenario[0])
	print("BLOCK_D_PERMUTATION_DIGEST=" + baseline.digest)
	print("BLOCK_D_PERMUTATION_TEST=PASS")
	get_tree().quit(0)

func _scenario(label: String, order: Array, claim_order: Array, mutate_tree: bool) -> Dictionary:
	var root := Node.new(); root.name = "Root_" + label; add_child(root)
	var seed := SeedSource.new(); seed.name = "RenamedSeed_" + label; root.add_child(seed)
	var poi: PoiPlacementPass = POI_PASS.new(); poi.name = "RenamedPoi_" + label; root.add_child(poi); poi.occupancy.reset(Rect2i(Vector2i.ZERO, Vector2i(16, 16)))
	var target := Node2D.new(); target.name = "SceneTarget"; root.add_child(target)
	var generator: EnvironmentGenerationPass = ENV_PASS.new(); generator.name = "RenamedEnvironment_" + label; root.add_child(generator)
	var profile: EnvironmentGenerationProfile = PROFILE.new(); profile.profile_id = "permutation_environment"; profile.logical_cell_size = Vector2.ONE; profile.clearance_cells = 0
	for id in order: profile.entries.append(_entry(String(id)))
	generator.profile = profile; generator.poi_pass_path = NodePath("../" + poi.name); generator.world_seed_source_path = NodePath("../" + seed.name)
	# EnvironmentEntry has one source per entry, not a variants collection. Resource-order
	# permutations are therefore not an applicable production API in this revision.
	for claim_id in claim_order: _claim(poi.occupancy, String(claim_id))
	if mutate_tree:
		var debug_a := Node.new(); debug_a.name = "DebugA"; root.add_child(debug_a)
		var debug_b := Node.new(); debug_b.name = "DebugB"; root.add_child(debug_b)
		root.move_child(debug_b, 0); root.move_child(target, root.get_child_count() - 1)
		generator.set_meta("debug_dictionary", _dictionary_in_reverse_order())
	generator.run_generation_pass()
	var output := generator.get_generation_output_manifest()
	var generated_ids: Array[String] = []
	for placement in output.accepted: generated_ids.append(String(placement.generated_id))
	generated_ids.sort()
	var claims := poi.occupancy.canonical_manifest()
	var canonical := {"ids":generated_ids, "placements":output.accepted, "rejections":output.rejection_counts, "claims":claims, "manifest":output.environment_manifest_hash, "content":output.environment_content_hash}
	var result := {"digest":GenerationHashes.sha256_of(canonical), "canonical":canonical}
	root.queue_free(); await get_tree().process_frame; await get_tree().process_frame
	return result

func _entry(id: String) -> EnvironmentEntry:
	var entry: EnvironmentEntry = ENTRY.new()
	entry.entry_id = id; entry.category = "trees"; entry.kind = EnvironmentEntry.Kind.SCENE; entry.target_path = NodePath("../SceneTarget"); entry.scene = TREE
	entry.density = 0.40; entry.candidate_budget = 64; entry.max_instances = 5; entry.minimum_spacing_cells = 1; entry.footprint_size = Vector2i.ONE
	return entry

func _claim(occupancy: WorldOccupancyMap, id: String) -> void:
	match id:
		"road": occupancy.claim_cells([Vector2i(2, 2)], WorldOccupancyMap.ROAD, "road:v1", "road")
		"water": occupancy.claim_cells([Vector2i(5, 5)], WorldOccupancyMap.WATER, "water:v1", "water")
		"poi": occupancy.claim_cells([Vector2i(8, 8)], WorldOccupancyMap.POI | WorldOccupancyMap.BUILDING, "poi:v1", "poi")

func _dictionary_in_reverse_order() -> Dictionary:
	var value := {}; value["z"] = 3; value["b"] = 2; value["a"] = 1; return value
func _assert(condition: bool, message: String) -> void:
	if condition: return
	push_error("Block D permutation test: " + message)
	get_tree().quit(1)
