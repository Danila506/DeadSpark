class_name PoiPlacementPass
extends Node

const PHASE := "poi_placement"
const ACCEPTED := "ACCEPTED"
const OUT_OF_BOUNDS := "OUT_OF_BOUNDS"
const ROAD_OVERLAP := "ROAD_OVERLAP"
const ROAD_CLEARANCE_OVERLAP := "ROAD_CLEARANCE_OVERLAP"
const WATER_OVERLAP := "WATER_OVERLAP"
const POI_OVERLAP := "POI_OVERLAP"
const INVALID_CONNECTOR := "INVALID_CONNECTOR"
const UNSUPPORTED_ORIENTATION := "UNSUPPORTED_ORIENTATION"
const INSUFFICIENT_CLEARANCE := "INSUFFICIENT_CLEARANCE"
const INVALID_AUTHORED_DATA := "INVALID_AUTHORED_DATA"
@export var enabled := true
@export var road_graph_pass_path: NodePath = NodePath("../RoadGraphPass")
@export var road_raster_pass_path: NodePath = NodePath("../RoadRasterizationPass")
@export var template: PoiTemplate
@export var spawn_parent_path: NodePath = NodePath("../../Y-Sort_Objects")
@export_range(1, 32, 1) var max_accepted_pois := 1

var occupancy := WorldOccupancyMap.new()
var candidates: Array[Dictionary] = []
var accepted: Array[Dictionary] = []
var _generated := false

func get_generation_phase() -> String: return PHASE
func has_generation_pending() -> bool: return enabled and not _generated
func run_generation_pass() -> void:
	if not enabled or _generated: return
	var road_pass := get_node_or_null(road_graph_pass_path) as RoadGraphPass
	if road_pass == null or road_pass.graph == null or template == null: push_error("PoiPlacementPass: missing road graph or template"); return
	var template_check := template.validate()
	if not bool(template_check["valid"]): push_error("PoiPlacementPass: invalid template"); return
	occupancy.reset(road_pass.graph.bounds)
	_import_road_claims()
	_build_candidates(road_pass.graph)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary): return String(a["candidate_id"]) < String(b["candidate_id"]))
	for candidate in candidates:
		if accepted.size() >= max_accepted_pois:
			candidate["status"] = POI_OVERLAP
			continue
		_resolve_candidate(candidate)
	_generated = true

func _import_road_claims() -> void:
	var raster := get_node_or_null(road_raster_pass_path)
	if raster == null: return
	var layer := raster.get_node_or_null("../../Y-Sort_Objects/RoadLayer") as TileMapLayer
	if layer == null: return
	var raw: Dictionary = layer.get_meta(&"world_generation_road_occupancy", {})
	var roads: Array[Vector2i] = []; var clearance: Array[Vector2i] = []
	for cell_variant in raw.keys():
		var cell := cell_variant as Vector2i
		if String(raw[cell]) == "ROAD": roads.append(cell)
		else: clearance.append(cell)
	occupancy.claim_cells(roads, WorldOccupancyMap.ROAD, "road:v1", "RoadRasterizationPass")
	occupancy.claim_cells(clearance, WorldOccupancyMap.ROAD_CLEARANCE, "road-clearance:v1", "RoadRasterizationPass")

func _build_candidates(graph: RoadGraph) -> void:
	for node in graph.canonical_manifest()["nodes"]:
		var data := node as Dictionary
		var topology := String(data["topology"])
		if topology != "DEAD_END_POI_CANDIDATE" and topology != "DEAD_END" and topology != "SEGMENT": continue
		var road_cell := data["cell"] as Vector2i
		if topology == "SEGMENT" and posmod(WorldSeedService.derive_seed(0, "poi/candidate-sample", [road_cell.x, road_cell.y]), 17) != 0: continue
		# V1 Village is authored with its sole connector facing down.  With rotation
		# unsupported, only the opposite road side is a valid alignment.
		for side in [Vector2i.UP]:
			var id := "poi-candidate:v1:%s:%d,%d" % [String(data["id"]), side.x, side.y]
			candidates.append({"candidate_id": id, "source_id": data["id"], "road_cell": road_cell, "side": side, "template_id": template.template_id, "connector_id": template.connector_id, "accepted": false, "status": ""})

func _resolve_candidate(candidate: Dictionary) -> void:
	if not template.allowed_rotations.has(0.0): candidate["status"] = UNSUPPORTED_ORIENTATION; return
	var cell_size := 60.0
	var road_cell: Vector2i = candidate["road_cell"]
	var side: Vector2i = candidate["side"]
	# Leave one ROAD_CLEARANCE cell between the structural POI bounds and the road.
	var origin := Vector2(road_cell + side * 2) * cell_size - template.connector_local_position
	var cells := _rect_cells(Rect2(origin + template.authored_bounds.position, template.authored_bounds.size), cell_size)
	if cells.is_empty(): candidate["status"] = OUT_OF_BOUNDS; return
	var forbidden := WorldOccupancyMap.ROAD | WorldOccupancyMap.ROAD_CLEARANCE | WorldOccupancyMap.WATER | WorldOccupancyMap.POI | WorldOccupancyMap.NO_SPAWN
	if occupancy.has_flags(cells, WorldOccupancyMap.ROAD): candidate["status"] = ROAD_OVERLAP; return
	if occupancy.has_flags(cells, WorldOccupancyMap.ROAD_CLEARANCE): candidate["status"] = ROAD_CLEARANCE_OVERLAP; return
	if occupancy.has_flags(cells, WorldOccupancyMap.WATER): candidate["status"] = WATER_OVERLAP; return
	if occupancy.has_flags(cells, WorldOccupancyMap.POI | WorldOccupancyMap.NO_SPAWN): candidate["status"] = POI_OVERLAP; return
	var owner := "poi:v2/%s/%s" % [template.template_id, candidate["candidate_id"]]
	var result := occupancy.claim_cells(cells, WorldOccupancyMap.POI | WorldOccupancyMap.NO_SPAWN, owner, "PoiPlacementPass")
	if not bool(result["valid"]): candidate["status"] = OUT_OF_BOUNDS; return
	candidate["accepted"] = true; candidate["status"] = ACCEPTED; candidate["world_position"] = origin; candidate["rotation"] = 0.0; accepted.append(candidate)
	_instantiate_village(origin, owner)

func _rect_cells(rect: Rect2, cell_size: float) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var min_cell := Vector2i(floori(rect.position.x / cell_size), floori(rect.position.y / cell_size))
	var max_cell := Vector2i(floori((rect.end.x - 1.0) / cell_size), floori((rect.end.y - 1.0) / cell_size))
	for y in range(min_cell.y, max_cell.y + 1): for x in range(min_cell.x, max_cell.x + 1): result.append(Vector2i(x, y))
	return result

func _instantiate_village(position: Vector2, owner: String) -> void:
	var parent := get_node_or_null(spawn_parent_path)
	if parent == null: return
	var instance := template.scene.instantiate() as Node2D
	if instance == null: return
	instance.set_meta("generated_object_id", owner)
	parent.add_child(instance); instance.position = position
	if instance.has_method("generate_from_poi"): instance.call("generate_from_poi", owner)

func get_generation_compatibility_profile() -> Dictionary: return template.compatibility_profile() if template != null else {"id":"poi:missing"}
func get_generation_output_manifest() -> Dictionary:
	return {"id":"poi_placement_v1", "occupancy_hash": GenerationHashes.sha256_of(occupancy.canonical_manifest()), "candidate_hash": GenerationHashes.sha256_of(candidates), "placement_hash": GenerationHashes.sha256_of(accepted), "candidates": candidates, "accepted": accepted}
