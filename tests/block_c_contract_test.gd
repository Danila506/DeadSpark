extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_occupancy()
	_test_authored_ids()
	_test_poi_template()
	print("BLOCK_C_CONTRACT_TEST=PASS")
	get_tree().quit(0)

func _test_occupancy() -> void:
	var a := WorldOccupancyMap.new()
	a.reset(Rect2i(Vector2i.ZERO, Vector2i(8, 8)))
	_assert(bool(a.claim_cells([Vector2i(1, 1)], WorldOccupancyMap.ROAD, "road", "test").valid), "road claim")
	_assert(a.has_flags([Vector2i(1, 1)], WorldOccupancyMap.ROAD), "ROAD blocking")
	_assert(bool(a.claim_cells([Vector2i(2, 2)], WorldOccupancyMap.ROAD_CLEARANCE, "clear", "test").valid), "clearance claim")
	_assert(a.has_flags([Vector2i(2, 2)], WorldOccupancyMap.ROAD_CLEARANCE), "ROAD_CLEARANCE blocking")
	_assert(bool(a.claim_cells([Vector2i(3, 3)], WorldOccupancyMap.WATER, "water", "test").valid), "water claim")
	_assert(a.has_flags([Vector2i(3, 3)], WorldOccupancyMap.WATER), "WATER blocking")
	_assert(not bool(a.claim_cells([Vector2i(8, 8)], WorldOccupancyMap.POI, "outside", "test").valid), "finite bounds")
	_assert(not bool(a.claim_cells([Vector2i(1, 2)], WorldOccupancyMap.POI, "road", "test").valid), "duplicate owner validation")
	var b := WorldOccupancyMap.new()
	b.reset(Rect2i(Vector2i.ZERO, Vector2i(8, 8)))
	b.claim_cells([Vector2i(3, 3)], WorldOccupancyMap.WATER, "water", "test")
	b.claim_cells([Vector2i(1, 1)], WorldOccupancyMap.ROAD, "road", "test")
	b.claim_cells([Vector2i(2, 2)], WorldOccupancyMap.ROAD_CLEARANCE, "clear", "test")
	_assert(GenerationHashes.sha256_of(a.canonical_manifest()) == GenerationHashes.sha256_of(b.canonical_manifest()), "claim manifest insertion-order independence")

func _test_authored_ids() -> void:
	var valid := AuthoredGenerationValidator.validate_structural_markers([{"stable_id":"m1", "local_position":Vector2.ZERO, "local_rotation":0.0, "rotation_used":false}])
	_assert(bool(valid.valid), "valid stable ID")
	_assert(not bool(AuthoredGenerationValidator.validate_structural_markers([{"stable_id":"", "local_position":Vector2.ZERO}]).valid), "missing stable ID blocks")
	_assert(not bool(AuthoredGenerationValidator.validate_structural_markers([{"stable_id":"same", "local_position":Vector2.ZERO}, {"stable_id":"same", "local_position":Vector2.ONE}]).valid), "duplicate stable ID blocks")
	var fingerprint_a := AuthoredGenerationValidator.structural_spatial_fingerprint([{"stable_id":"m", "local_position":Vector2(1, 2), "rotation_used":false}])
	var fingerprint_b := AuthoredGenerationValidator.structural_spatial_fingerprint([{"stable_id":"m", "local_position":Vector2(2, 2), "rotation_used":false}])
	_assert(GenerationHashes.sha256_of(fingerprint_a) != GenerationHashes.sha256_of(fingerprint_b), "marker transform is generation relevant")

func _test_poi_template() -> void:
	var template := load("res://Resources/WorldGen/village_poi_template.tres") as PoiTemplate
	_assert(template != null and bool(template.validate().valid), "Village POI template must validate")
	var old := template.allowed_rotations.duplicate()
	template.allowed_rotations = [90.0]
	_assert(not bool(template.validate().valid), "unsupported POI orientation rejects")
	template.allowed_rotations = old

func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error("Block C contract test: " + message)
		get_tree().quit(1)
