extends Node

const PROFILE := preload("res://Resources/WorldGen/road_generation_profile.tres")
const TEMPLATE := preload("res://Resources/WorldGen/village_poi_template.tres")
const ROAD_PASS_SCRIPT := preload("res://World/Generation/road_graph_pass.gd")
const RASTER_SCRIPT := preload("res://World/Generation/road_rasterization_pass.gd")
const POI_SCRIPT := preload("res://World/Generation/poi_placement_pass.gd")
const ROAD_TILESET := preload("res://Assets/World/Roads/RoadTileSet.tres")
const SEEDS := [1337, 7331, 15885, 1001, 2026, 99999]
const BOUNDS := Rect2i(Vector2i(-48, -48), Vector2i(96, 96))
const DIRECTORY := "res://tests/artifacts/block_c"

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	var first := await _collect_run()
	var second := await _collect_run()
	_assert(GenerationHashes.sha256_of(first) == GenerationHashes.sha256_of(second), "two fixed-seed matrix runs must match")
	var file := FileAccess.open(ProjectSettings.globalize_path(DIRECTORY + "/fixed_seed_matrix.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(first, "\t"))
	print("BLOCK_C_MATRIX=PASS rows=%d hash=%s" % [first.size(), GenerationHashes.sha256_of(first)])
	get_tree().quit(0)

func _collect_run() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for seed in SEEDS:
		var row := await _generate_seed(seed)
		rows.append(row)
		_export_preview(seed, row)
	return rows

func _generate_seed(seed: int) -> Dictionary:
	var world := Node2D.new()
	world.name = "MatrixWorld"
	add_child(world)
	var ysort := Node2D.new()
	ysort.name = "Y-Sort_Objects"
	world.add_child(ysort)
	var road_layer := TileMapLayer.new()
	road_layer.name = "RoadLayer"
	road_layer.tile_set = ROAD_TILESET
	ysort.add_child(road_layer)
	var generation := Node.new()
	generation.name = "Generation"
	world.add_child(generation)
	var road := ROAD_PASS_SCRIPT.new() as RoadGraphPass
	road.name = "RoadGraphPass"
	road.profile = PROFILE
	generation.add_child(road)
	var raster := RASTER_SCRIPT.new() as RoadRasterizationPass
	raster.name = "RoadRasterizationPass"
	raster.profile = PROFILE
	generation.add_child(raster)
	var poi := POI_SCRIPT.new() as PoiPlacementPass
	poi.name = "PoiPlacementPass"
	poi.template = TEMPLATE
	generation.add_child(poi)
	await get_tree().process_frame
	road.build_graph_for_inputs(BOUNDS, seed)
	road.graph_hash = GenerationHashes.sha256_of(road.graph.canonical_manifest())
	raster.run_generation_pass()
	poi.run_generation_pass()
	await get_tree().process_frame
	var output := poi.get_generation_output_manifest()
	var selected := {}
	for child in ysort.get_children():
		if child is VillageGenerator:
			selected[String(child.get_meta("generated_object_id", ""))] = (child as VillageGenerator).get_village_content_hash()
	var profiles: Array[Dictionary] = [road.get_generation_compatibility_profile(), raster.get_generation_compatibility_profile(), poi.get_generation_compatibility_profile()]
	profiles.sort_custom(func(a: Dictionary, b: Dictionary): return String(a.id) < String(b.id))
	var compatibility := WorldGenerationContract.compatibility_hash(profiles)
	var manifest := WorldGenerationContract.world_manifest_hash(compatibility, seed, {"min_cell": BOUNDS.position, "max_cell": BOUNDS.end - Vector2i.ONE})
	var immutable: Array[Dictionary] = [road.get_generation_output_manifest(), raster.get_generation_output_manifest(), output]
	immutable.sort_custom(func(a: Dictionary, b: Dictionary): return String(a.id) < String(b.id))
	var rejected := {}
	for candidate in output.candidates:
		var status := String((candidate as Dictionary).status)
		if status != PoiPlacementPass.ACCEPTED: rejected[status] = int(rejected.get(status, 0)) + 1
	var row := {"seed": seed, "road_graph_hash": road.graph_hash, "road_raster_hash": raster.raster_hash, "occupancy_hash": output.occupancy_hash, "poi_candidate_hash": output.candidate_hash, "poi_placement_hash": output.placement_hash, "village_content_hash": GenerationHashes.sha256_of(selected), "generation_compatibility_hash": compatibility, "world_manifest_hash": manifest, "generation_output_hash": WorldGenerationContract.generation_output_hash(manifest, immutable), "road_cells": road.graph.cells.keys(), "candidates": output.candidates, "accepted": output.accepted, "rejected": rejected, "selected_village_entries": selected, "bounds": BOUNDS}
	world.queue_free()
	await get_tree().process_frame
	return row

func _export_preview(seed: int, row: Dictionary) -> void:
	var scale := 6
	var image := Image.create(BOUNDS.size.x * scale, BOUNDS.size.y * scale, false, Image.FORMAT_RGBA8)
	image.fill(Color("172027"))
	for road_cell in row.road_cells:
		var cell := road_cell as Vector2i
		image.fill_rect(Rect2i((cell - BOUNDS.position) * scale, Vector2i(scale, scale)), Color("6c8fb3"))
	for candidate in row.candidates:
		var data := candidate as Dictionary
		var cell: Vector2i = data.road_cell
		var status := String(data.status)
		var color := Color("e0a13b") if status == PoiPlacementPass.ACCEPTED else Color("b85a58")
		image.fill_rect(Rect2i((cell - BOUNDS.position) * scale, Vector2i(scale, scale)), color)
	for accepted in row.accepted:
		var pos: Vector2 = (accepted as Dictionary).world_position
		var top_left := Vector2i(floori(pos.x / 60.0), floori(pos.y / 60.0)) - BOUNDS.position
		var rect := Rect2i(top_left * scale, Vector2i(14 * scale, 14 * scale))
		image.fill_rect(Rect2i(rect.position, Vector2i(rect.size.x, 1)), Color("68d391"))
		image.fill_rect(Rect2i(rect.position + Vector2i(0, rect.size.y - 1), Vector2i(rect.size.x, 1)), Color("68d391"))
		image.fill_rect(Rect2i(rect.position, Vector2i(1, rect.size.y)), Color("68d391"))
		image.fill_rect(Rect2i(rect.position + Vector2i(rect.size.x - 1, 0), Vector2i(1, rect.size.y)), Color("68d391"))
	image.save_png(ProjectSettings.globalize_path("%s/block_c_%d.png" % [DIRECTORY, seed]))

func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error("Block C matrix: " + message)
		get_tree().quit(1)
