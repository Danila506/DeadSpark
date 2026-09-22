extends SceneTree

const ROAD_PROFILE = preload("res://Resources/WorldGen/road_generation_profile.tres")
const ROAD_GRAPH_PASS = preload("res://World/Generation/road_graph_pass.gd")
const SEEDS := [1337, 7331, 15885, 1001, 2026, 99999, 42, 777, 12345, 55555]
const PREVIEW_DIRECTORY := "res://tests/artifacts/road_previews"
const CELL_PIXELS := 6

func _init() -> void:
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEW_DIRECTORY))
	if error != OK:
		push_error("Cannot create road preview directory: %s" % error)
		quit(1)
		return
	var generator: RoadGraphPass = ROAD_GRAPH_PASS.new()
	generator.profile = ROAD_PROFILE
	var bounds := Rect2i(Vector2i(-48, -48), Vector2i(96, 96))
	var report: Array[Dictionary] = []
	for seed in SEEDS:
		generator.build_graph_for_inputs(bounds, seed)
		var graph := generator.graph
		if graph == null or not bool(graph.validate().get("valid", false)):
			push_error("Road preview graph failed for seed %d: %s" % [seed, str(graph.validate() if graph != null else {})])
			quit(1)
			return
		var png_path := "%s/road_%d.png" % [PREVIEW_DIRECTORY, seed]
		_export_preview(graph, png_path)
		report.append(_collect_stats(seed, graph, png_path))
	print(JSON.stringify(report))
	quit(0)

func _collect_stats(seed: int, graph: RoadGraph, png_path: String) -> Dictionary:
	var manifest := graph.canonical_manifest()
	var nodes: Array = manifest["nodes"]
	var junctions := 0
	var dead_ends := 0
	for node in nodes:
		var topology := String((node as Dictionary).get("topology", ""))
		if topology == "JUNCTION": junctions += 1
		if topology == "DEAD_END" or topology == "DEAD_END_POI_CANDIDATE": dead_ends += 1
	return {
		"seed": seed,
		"road_graph_hash": GenerationHashes.sha256_of(manifest),
		"road_raster_hash": _raster_hash(graph),
		"road_nodes": nodes.size(),
		"road_edges": (manifest["edges"] as Array).size(),
		"junctions": junctions,
		"dead_ends": dead_ends,
		"branches": graph.branch_start_cells.size(),
		"primary_sides": graph.primary_anchor_sides,
		"primary_bends": graph.primary_bend_count,
		"branch_bends_total": graph.branch_bend_count_total,
		"route_attempts": graph.route_attempts,
		"rejected_attempts": graph.rejection_counts,
		"water_intersection": graph.rejection_counts.has("WATER_INTERSECTION"),
		"no_valid_route": graph.rejection_counts.has("NO_VALID_ROUTE"),
		"preview": png_path
	}

func _raster_hash(graph: RoadGraph) -> String:
	var raster: RoadRasterizationPass = preload("res://World/Generation/road_rasterization_pass.gd").new()
	raster.profile = ROAD_PROFILE
	var cells: Array[Dictionary] = []
	var occupancy := {}
	for cell in _sorted_cells(graph.cells.keys()):
		cells.append({"cell": cell, "atlas": raster._atlas_for(cell, graph), "source_id": ROAD_PROFILE.source_id})
		occupancy[cell] = "ROAD"
		for y in range(-1, 2):
			for x in range(-1, 2):
				var clearance := cell + Vector2i(x, y)
				if not occupancy.has(clearance): occupancy[clearance] = "ROAD_CLEARANCE"
	var occupancy_manifest: Array[Dictionary] = []
	for cell in _sorted_cells(occupancy.keys()): occupancy_manifest.append({"cell": cell, "claim": occupancy[cell]})
	return GenerationHashes.sha256_of({"id": "road_raster_v1", "cells": cells, "occupancy": occupancy_manifest})

func _count_secondary_components(graph: RoadGraph) -> int:
	var visited := {}
	var count := 0
	for cell in _sorted_cells(graph.cells.keys()):
		if visited.has(cell) or String((graph.cells[cell] as Dictionary).get("role", "")) != "secondary": continue
		count += 1
		var pending: Array[Vector2i] = [cell]
		while not pending.is_empty():
			var current: Vector2i = pending.pop_back()
			if visited.has(current): continue
			visited[current] = true
			for other in graph.neighbors(current):
				if String((graph.cells[other] as Dictionary).get("role", "")) == "secondary" and not visited.has(other): pending.append(other)
	return count

func _export_preview(graph: RoadGraph, path: String) -> void:
	var size := graph.bounds.size * CELL_PIXELS
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color("1c2229"))
	for cell in _sorted_cells(graph.cells.keys()):
		var color := Color("d6923b") if String((graph.cells[cell] as Dictionary).get("role", "")) == "primary" else Color("7ea4c9")
		var degree := graph.neighbors(cell).size()
		if degree >= 3: color = Color("f1d36b")
		elif degree == 1: color = Color("d55f5f")
		var pixel := (cell - graph.bounds.position) * CELL_PIXELS
		image.fill_rect(Rect2i(pixel, Vector2i(CELL_PIXELS, CELL_PIXELS)), color)
	var save_error := image.save_png(ProjectSettings.globalize_path(path))
	if save_error != OK: push_error("Cannot save preview %s: %s" % [path, save_error])

func _sorted_cells(raw: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for item in raw:
		if item is Vector2i: result.append(item)
	result.sort_custom(func(a: Vector2i, b: Vector2i): return a.x < b.x or (a.x == b.x and a.y < b.y))
	return result
