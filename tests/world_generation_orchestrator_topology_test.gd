extends Node

const WORLD := preload("res://World/world_generation.tscn")

func _ready() -> void: call_deferred("_run")
func _assert(value: bool, message: String) -> bool:
	if value: return true
	push_error("World generation topology: " + message);get_tree().quit(1);return false
func _run() -> void:
	var world := WORLD.instantiate();add_child(world)
	var orchestrator := world as WorldGenerationOrchestrator
	if not _assert(orchestrator != null,"production orchestrator"):return
	var phases := orchestrator._build_phases()
	if not _assert(orchestrator.blocking_errors.is_empty(),"explicit registry resolves"):return
	var expected := ["base_terrain","road_graph","road_raster","poi_placement","environment","enemy_population","legacy_spawners"]
	var actual:Array[String]=[];var records:Array[Dictionary]=[]
	for phase in phases:
		var phase_id:=String(phase.id);actual.append(phase_id)
		for source in phase.sources:
			records.append({"phase":phase_id,"role":String(source.call("get_generation_phase")) if source.has_method("get_generation_phase") else "legacy"})
	if not _assert(actual==expected,"canonical phase order"):return
	var roles:Array[String]=[];for r in records:if r.role!="legacy":roles.append(String(r.role))
	roles.sort();if not _assert(roles==["environment","poi_placement","road_graph","road_raster"],"unique production source roles"):return
	var poi:=world.get_node("PoiPlacementPass") as PoiPlacementPass;var environment:=world.get_node("EnvironmentGenerationPass") as EnvironmentGenerationPass
	if not _assert(orchestrator.get_world_occupancy_context()==poi.occupancy,"occupancy accessor identity"):return
	# Environment reads the same object through PoiPlacementPass; no second map is created.
	if not _assert(environment.get_node_or_null(environment.poi_pass_path)==poi,"environment POI dependency"):return
	var invalid:=WORLD.instantiate();var bad:=invalid as WorldGenerationOrchestrator;bad.poi_source_path=NodePath("../Missing");bad._build_phases()
	if not _assert(bad.blocking_errors.has("MISSING_REQUIRED_SOURCE:poi_placement"),"missing path blocks"):return
	var digest:=GenerationHashes.sha256_of({"phases":actual,"roles":roles,"records":records,"occupancy_owner":"poi_placement","validation":"valid"})
	print("WORLD_GENERATION_ORCHESTRATOR_TOPOLOGY_TEST=PASS digest=%s"%digest);get_tree().quit(0)
