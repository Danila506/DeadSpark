extends Node

const ENV_PASS = preload("res://World/Generation/environment_generation_pass.gd")
const POI_PASS = preload("res://World/Generation/poi_placement_pass.gd")
const ENTRY = preload("res://World/Generation/environment_entry.gd")
const PROFILE = preload("res://World/Generation/environment_generation_profile.gd")
const TREE = preload("res://World/Assets/Biom1/Tree.tscn")

class SeedSource extends Node:
	var seed := 0
	func get_debug_world_generation_info() -> Dictionary: return {"seed": seed}

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_same_seed_and_variation()
	await _test_clear_repeat_and_ownership()
	await _test_exclusions_bounds_spacing_and_rejections()
	await _test_validation_and_resource_before_claim()
	await _test_hash_debug_independence()
	await _test_position_based_visuals()
	print("BLOCK_D_CONTRACT_TEST=PASS")
	get_tree().quit(0)

func _make_world(seed: int, entries: Array[EnvironmentEntry], bounds := Rect2i(Vector2i.ZERO, Vector2i(16, 16))) -> Dictionary:
	var root := Node.new(); add_child(root)
	var source := SeedSource.new(); source.name = "Seed"; source.seed = seed; root.add_child(source)
	var poi: PoiPlacementPass = POI_PASS.new(); poi.name = "Poi"; root.add_child(poi); poi.occupancy.reset(bounds)
	var target := Node2D.new(); target.name = "SceneTarget"; root.add_child(target)
	var generator: EnvironmentGenerationPass = ENV_PASS.new(); generator.name = "Environment"; root.add_child(generator)
	var profile: EnvironmentGenerationProfile = PROFILE.new(); profile.profile_id = "contract_environment"; profile.logical_cell_size = Vector2(1.0, 1.0); profile.clearance_cells = 0; profile.entries = entries
	generator.profile = profile; generator.poi_pass_path = NodePath("../Poi"); generator.world_seed_source_path = NodePath("../Seed")
	return {"root":root, "poi":poi, "target":target, "generator":generator, "profile":profile}

func _test_position_based_visuals() -> void:
	var entry := _entry("stones", 1.0)
	entry.category = "stones"
	entry.scene = load("res://World/Assets/Biom2/Stone.tscn")
	entry.minimum_spacing_cells = 0
	entry.max_instances = 64
	var world := _make_world(1337, [entry])
	(world.profile as EnvironmentGenerationProfile).logical_cell_size = Vector2(60, 60)
	_run_pass(world)
	var textures := {}
	for instance in (world.target as Node).get_children():
		var variants: Array = instance.call("_resolve_variants")
		var position := (instance as Node2D).global_position
		var index := posmod(WorldSeedService.derive_seed(0, "environment/visual", [roundi(position.x), roundi(position.y)]), variants.size())
		var texture := (instance.get_node(instance.get("sprite_path")) as Sprite2D).texture
		_assert(texture == variants[index], "visual sees final position in ready")
		textures[texture.resource_path] = true
	_assert(textures.size() == 6, "all six stone textures are reachable on the placement grid")
	await _dispose(world)

func _entry(id := "tree", density := 1.0) -> EnvironmentEntry:
	var entry: EnvironmentEntry = ENTRY.new()
	entry.entry_id = id; entry.category = "trees"; entry.kind = EnvironmentEntry.Kind.SCENE; entry.target_path = NodePath("../SceneTarget"); entry.scene = TREE
	entry.density = density; entry.candidate_budget = 64; entry.max_instances = 5; entry.minimum_spacing_cells = 1; entry.footprint_size = Vector2i.ONE
	return entry

func _output(world: Dictionary) -> Dictionary: return (world.generator as EnvironmentGenerationPass).get_generation_output_manifest()
func _run_pass(world: Dictionary) -> Dictionary:
	(world.generator as EnvironmentGenerationPass).run_generation_pass()
	return _output(world)
func _dispose(world: Dictionary) -> void:
	(world.root as Node).queue_free(); await get_tree().process_frame; await get_tree().process_frame
func _environment_claim_count(world: Dictionary) -> int:
	var claims: Array = ((world.poi as PoiPlacementPass).occupancy.canonical_manifest().claims as Array)
	var count := 0
	for claim in claims:
		if String((claim as Dictionary).get("source", "")) == "environment": count += 1
	return count
func _assert(value: bool, message: String) -> void:
	if value: return
	push_error("Block D contract test: " + message)
	get_tree().quit(1)

func _test_same_seed_and_variation() -> void:
	var a := _make_world(1337, [_entry("tree", 0.35)]); var one := _run_pass(a)
	var b := _make_world(1337, [_entry("tree", 0.35)]); var two := _run_pass(b)
	_assert(one.environment_manifest_hash == two.environment_manifest_hash and one.environment_content_hash == two.environment_content_hash, "same seed hashes")
	_assert(GenerationHashes.sha256_of(one.accepted) == GenerationHashes.sha256_of(two.accepted), "same seed placements")
	_assert(GenerationHashes.sha256_of((a.poi as PoiPlacementPass).occupancy.canonical_manifest()) == GenerationHashes.sha256_of((b.poi as PoiPlacementPass).occupancy.canonical_manifest()), "same seed claims")
	var hashes := {}
	for seed in [1337, 7331, 15885]:
		var world := _make_world(seed, [_entry("tree", 0.35)]); hashes[_run_pass(world).environment_content_hash] = true; await _dispose(world)
	_assert(hashes.size() >= 2, "different seeds must vary environment content")
	await _dispose(a); await _dispose(b)

func _test_clear_repeat_and_ownership() -> void:
	var world := _make_world(1337, [_entry()]); var poi := world.poi as PoiPlacementPass
	_assert(bool(poi.occupancy.claim_cells([Vector2i(15, 15)], WorldOccupancyMap.ROAD, "road:test", "road").valid), "setup road claim")
	var first := _run_pass(world); var nodes := (world.target as Node).get_child_count(); var claims := _environment_claim_count(world)
	var repeated := _run_pass(world)
	_assert(first.environment_manifest_hash == repeated.environment_manifest_hash and nodes == (world.target as Node).get_child_count() and claims == _environment_claim_count(world), "repeated generate must not duplicate")
	(world.generator as EnvironmentGenerationPass)._clear_generated(); await get_tree().process_frame; await get_tree().process_frame
	_assert(_environment_claim_count(world) == 0 and (world.target as Node).get_child_count() == 0, "clear removes environment content")
	_assert(poi.occupancy.has_flags([Vector2i(15, 15)], WorldOccupancyMap.ROAD), "clear preserves foreign claims")
	var second := _run_pass(world)
	_assert(first.environment_manifest_hash == second.environment_manifest_hash and first.environment_content_hash == second.environment_content_hash, "generate clear generate")
	await _dispose(world)

func _test_exclusions_bounds_spacing_and_rejections() -> void:
	var entry := _entry(); entry.max_instances = 64; entry.minimum_spacing_cells = 1
	var world := _make_world(1337, [entry], Rect2i(Vector2i.ZERO, Vector2i(8, 8))); var poi := world.poi as PoiPlacementPass
	poi.occupancy.claim_cells([Vector2i(3, 3)], WorldOccupancyMap.ROAD, "road", "road")
	poi.occupancy.claim_cells([Vector2i(4, 4)], WorldOccupancyMap.WATER, "water", "water")
	poi.occupancy.claim_cells([Vector2i(5, 5)], WorldOccupancyMap.POI | WorldOccupancyMap.BUILDING, "poi", "poi")
	var output := _run_pass(world)
	for accepted in output.accepted:
		var cells: Array[Vector2i] = accepted.footprint
		for cell in cells:
			_assert(poi.occupancy.bounds.has_point(cell), "full footprint inside bounds")
			_assert(not poi.occupancy.has_flags([cell], WorldOccupancyMap.ROAD | WorldOccupancyMap.WATER | WorldOccupancyMap.POI | WorldOccupancyMap.BUILDING), "exclusion overlap")
	for i in range(output.accepted.size()):
		for j in range(i + 1, output.accepted.size()):
			var left: Array = output.accepted[i].footprint; var right: Array = output.accepted[j].footprint
			for cell in left: _assert(not right.has(cell), "spacing is expanded-footprint separation")
	_assert((output.rejection_counts as Array).size() > 0, "rejection counters emitted")
	var sorted: Array = (output.rejection_counts as Array).duplicate(true); sorted.sort_custom(func(x, y): return String(x.reason) < String(y.reason))
	_assert(GenerationHashes.sha256_of(sorted) == GenerationHashes.sha256_of(output.rejection_counts), "rejection counters canonical")
	await _dispose(world)

func _test_validation_and_resource_before_claim() -> void:
	var invalids: Array[EnvironmentGenerationProfile] = []
	var missing_profile: EnvironmentGenerationProfile = null; invalids.append(missing_profile)
	var empty_profile: EnvironmentGenerationProfile = PROFILE.new(); empty_profile.profile_id = ""; invalids.append(empty_profile)
	var empty_entry := _entry(""); var p1: EnvironmentGenerationProfile = PROFILE.new(); p1.profile_id = "p"; p1.entries = [empty_entry]; invalids.append(p1)
	var duplicate_a := _entry("same"); var duplicate_b := _entry("same"); var p2: EnvironmentGenerationProfile = PROFILE.new(); p2.profile_id = "p"; p2.entries = [duplicate_a, duplicate_b]; invalids.append(p2)
	var negative := _entry("negative"); negative.density = -1.0; var p3: EnvironmentGenerationProfile = PROFILE.new(); p3.profile_id = "p"; p3.entries = [negative]; invalids.append(p3)
	var bad_budget := _entry("budget"); bad_budget.candidate_budget = 0; var p4: EnvironmentGenerationProfile = PROFILE.new(); p4.profile_id = "p"; p4.entries = [bad_budget]; invalids.append(p4)
	var unknown := _entry("unknown"); unknown.category = "not_a_category"; var p5: EnvironmentGenerationProfile = PROFILE.new(); p5.profile_id = "p"; p5.entries = [unknown]; invalids.append(p5)
	var negative_spacing := _entry("spacing"); negative_spacing.minimum_spacing_cells = -1; var p6: EnvironmentGenerationProfile = PROFILE.new(); p6.profile_id = "p"; p6.entries = [negative_spacing]; invalids.append(p6)
	var invalid_footprint := _entry("footprint"); invalid_footprint.footprint_size = Vector2i.ZERO; var p7: EnvironmentGenerationProfile = PROFILE.new(); p7.profile_id = "p"; p7.entries = [invalid_footprint]; invalids.append(p7)
	var invalid_mask := _entry("mask"); invalid_mask.blocked_occupancy_mask = 1024; var p8: EnvironmentGenerationProfile = PROFILE.new(); p8.profile_id = "p"; p8.entries = [invalid_mask]; invalids.append(p8)
	for profile in invalids:
		var world := _make_world(1, [_entry()]); (world.generator as EnvironmentGenerationPass).profile = profile; _run_pass(world)
		_assert((world.generator as EnvironmentGenerationPass).blocking_errors.size() > 0, "invalid profile blocks")
		await _dispose(world)
	var broken := _entry("missing_resource"); broken.scene = null
	var resource_world := _make_world(1, [broken]); _run_pass(resource_world)
	_assert(_environment_claim_count(resource_world) == 0, "invalid resource creates no occupancy claim")
	_assert((resource_world.generator as EnvironmentGenerationPass).blocking_errors.size() > 0, "invalid resource blocks before claim")
	await _dispose(resource_world)
	var wrong_target := _entry("wrong_target"); wrong_target.kind = EnvironmentEntry.Kind.TILE; wrong_target.scene = null
	var wrong_target_world := _make_world(1, [wrong_target]); _run_pass(wrong_target_world)
	_assert(_environment_claim_count(wrong_target_world) == 0 and (wrong_target_world.generator as EnvironmentGenerationPass).rejections.size() > 0, "incompatible target type rejects before claim")
	await _dispose(wrong_target_world)
	var no_occupancy := _make_world(1, [_entry()]); (no_occupancy.generator as EnvironmentGenerationPass).poi_pass_path = NodePath("../MissingPoi"); _run_pass(no_occupancy)
	_assert((no_occupancy.generator as EnvironmentGenerationPass).blocking_errors.size() > 0, "missing occupancy blocks")
	await _dispose(no_occupancy)

func _test_hash_debug_independence() -> void:
	var world := _make_world(2026, [_entry()]); var one := _run_pass(world)
	(world.generator as EnvironmentGenerationPass).set_meta("debug_enabled", true)
	var two := _run_pass(world)
	_assert(one.environment_manifest_hash == two.environment_manifest_hash and one.environment_content_hash == two.environment_content_hash, "debug metadata does not affect hashes")
	var changed := _make_world(2026, [_entry("other_entry")]); var three := _run_pass(changed)
	_assert(one.environment_manifest_hash != three.environment_manifest_hash and one.environment_content_hash != three.environment_content_hash, "canonical placement change changes hashes")
	await _dispose(world); await _dispose(changed)
