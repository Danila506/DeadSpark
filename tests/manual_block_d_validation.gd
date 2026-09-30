@tool
extends Node2D

# This scene deliberately builds the same pass sequence as the fixed-seed matrix,
# but does not instantiate that test scene: test runners own the SceneTree and quit
# when complete, which is inappropriate for an editor/F6 preview.
const BOUNDS := Rect2i(Vector2i(-48, -48), Vector2i(96, 96))
const ROAD_PROFILE = preload("res://Resources/WorldGen/road_generation_profile.tres")
const ENV_PROFILE = preload("res://Resources/WorldGen/environment_generation_profile.tres")
const TEMPLATE = preload("res://Resources/WorldGen/village_poi_template.tres")
const ROAD_TILESET = preload("res://Assets/World/Roads/RoadTileSet.tres")
const ROAD = preload("res://World/Generation/road_graph_pass.gd")
const RASTER = preload("res://World/Generation/road_rasterization_pass.gd")
const POI = preload("res://World/Generation/poi_placement_pass.gd")
const ENV = preload("res://World/Generation/environment_generation_pass.gd")

class SeedSource extends Node:
	var seed := 0
	func get_debug_world_generation_info() -> Dictionary: return {"seed": seed}

@export var world_seed := 1337
@export var show_world_bounds := true
@export var show_road := true
@export var show_road_clearance := true
@export var show_water := true
@export var show_poi_bounds := true
@export var show_building_bounds := true
@export var show_environment_footprints := true
@export var show_environment_clearance := true
@export var show_spacing := true
@export var show_occupancy_claims := true
@export var show_generated_object_ids := true
@export var show_rejected_candidates := false
@export var show_tilemap_environment := true
@export var show_scene_environment := true
@export var show_biom1 := true
@export var show_biom2 := true
@export var show_xz := true
@export var show_trees := true
@export var show_bushes := true
@export var show_puddles := true
@export var show_stones := true
@export var show_deadwood := true
@export var show_berry_bushes := true
@export_multiline var status := "Set world_seed, then use Generate prerequisites or Generate full world in the Inspector."
@export_multiline var road_raster_diagnostics := "RoadRaster connectivity diagnostics appear after generation."

var _preview_world: Node2D
var _road: RoadGraphPass
var _raster: RoadRasterizationPass
var _poi: PoiPlacementPass
var _environment: EnvironmentGenerationPass
var _output := {}
var _busy := false
var _runtime_status_label: Label

func _ready() -> void:
	# CI must opt into smoke mode explicitly.  A normal F6 run builds the same
	# preview as the Inspector button and deliberately stays open for inspection.
	if "--manual-block-d-smoke" in OS.get_cmdline_user_args():
		call_deferred("_headless_smoke")
	elif not Engine.is_editor_hint():
		call_deferred("_start_runtime_preview")

func _start_runtime_preview() -> void:
	_ensure_runtime_overlay()
	generate_full_world()
	await get_tree().process_frame
	var camera := get_node_or_null("PreviewCamera") as Camera2D
	if is_instance_valid(_preview_world) and camera != null and camera.enabled:
		print("MANUAL_BLOCK_D_RUNTIME_PREVIEW=READY seed=%d world_root=%s camera=%s" % [world_seed, _preview_world.name, camera.name])

func _ensure_runtime_overlay() -> void:
	if _runtime_status_label != null:
		return
	var canvas := CanvasLayer.new()
	canvas.name = "RuntimeStatusOverlay"
	canvas.layer = 10
	add_child(canvas)
	var panel := ColorRect.new()
	panel.color = Color(0.02, 0.02, 0.02, 0.78)
	panel.position = Vector2(12, 12)
	panel.size = Vector2(1060, 88)
	canvas.add_child(panel)
	_runtime_status_label = Label.new()
	_runtime_status_label.position = Vector2(14, 10)
	_runtime_status_label.size = Vector2(1030, 68)
	_runtime_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_runtime_status_label)

@export_tool_button("Generate prerequisites") var generate_prerequisites = func(): generate_prerequisites_preview()
@export_tool_button("Generate Block D") var generate_block_d = func(): generate_block_d_preview()
@export_tool_button("Clear Block D") var clear_block_d = func(): clear_block_d_preview()
@export_tool_button("Regenerate Block D") var regenerate_block_d = func(): regenerate()
@export_tool_button("Generate full world") var generate_full_world_button = func(): generate_full_world()

func generate_prerequisites_preview() -> void:
	if _busy: return
	_busy = true
	var preflight := _validate_preview_resources()
	if not preflight.is_empty():
		_fail_preview(preflight)
		return
	_dispose_preview_world()
	_build_preview_world()
	_poi.run_generation_pass()
	var connector_cells: Array[Vector2i] = []
	for connector_world in _poi.get_connector_world_positions(): connector_cells.append(_road_layer.local_to_map(connector_world))
	_road.build_graph_for_inputs(BOUNDS, world_seed, {}, connector_cells)
	if _road.graph == null:
		_fail_preview("Road graph generation failed for seed %d." % world_seed)
		return
	_road.graph_hash = GenerationHashes.sha256_of(_road.graph.canonical_manifest())
	_raster.run_generation_pass()
	_update_road_raster_diagnostics()
	_poi.import_road_claims_after_raster()
	if _poi.occupancy.bounds.size == Vector2i.ZERO:
		_fail_preview("POI generation did not produce a valid occupancy map for seed %d." % world_seed)
		return
	status = "Prerequisites generated for seed %d. Generate Block D to place Environment." % world_seed
	_busy = false
	_update_inspector_and_view()

func generate_block_d_preview() -> void:
	if _busy: return
	if not is_instance_valid(_preview_world):
		generate_prerequisites_preview()
	_busy = true
	_environment.run_generation_pass()
	_output = _environment.get_generation_output_manifest()
	if not _environment.blocking_errors.is_empty():
		_fail_preview("Environment generation failed: " + "; ".join(_environment.blocking_errors))
		return
	status = _status_for_output()
	_busy = false
	_update_inspector_and_view()

func generate_full_world() -> void:
	if _busy: return
	generate_prerequisites_preview()
	generate_block_d_preview()

func clear_block_d_preview() -> void:
	if is_instance_valid(_environment): _environment._clear_generated()
	_output = {}
	road_raster_diagnostics = "RoadRaster connectivity diagnostics cleared with preview world."
	# Keep Road/POI/Village prerequisites alive: Clear Block D is intentionally
	# scoped to Environment-owned content, exactly like the production pass.
	if not _busy: status = "Block D preview cleared; road, POI, Village and terrain prerequisites remain visible."
	_update_inspector_and_view()

func _dispose_preview_world() -> void:
	if is_instance_valid(_environment): _environment._clear_generated()
	_environment = null
	if is_instance_valid(_preview_world): _preview_world.queue_free()
	_preview_world = null; _road = null; _raster = null; _poi = null

func _validate_preview_resources() -> String:
	# These Resources are @tool because this method is also called by Inspector
	# buttons.  Their validation methods are pure and do not mutate project data.
	if TEMPLATE == null:
		return "Missing POI template resource."
	var poi_check := TEMPLATE.validate()
	if not bool(poi_check.get("valid", false)):
		return "Invalid POI template: " + "; ".join(poi_check.get("errors", []))
	if ENV_PROFILE == null:
		return "Missing Environment generation profile resource."
	var environment_check := ENV_PROFILE.validate()
	if not bool(environment_check.get("valid", false)):
		return "Invalid Environment profile: " + "; ".join(environment_check.get("errors", []))
	return ""

func _fail_preview(message: String) -> void:
	_dispose_preview_world()
	_output = {}
	_busy = false
	status = "BLOCKING ERROR: " + message
	_update_inspector_and_view()

func regenerate() -> void:
	if _busy: return
	generate_full_world()

func _build_preview_world() -> void:
	_preview_world = Node2D.new(); _preview_world.name = "ProductionDerivedBlockDPreview"; add_child(_preview_world)
	var ysort := Node2D.new(); ysort.name = "Y-Sort_Objects"; _preview_world.add_child(ysort)
	var road_layer := TileMapLayer.new(); road_layer.name = "RoadLayer"; road_layer.tile_set = ROAD_TILESET; ysort.add_child(road_layer)
	for biome in ["Biom1", "Biom2"]:
		var container := Node2D.new(); container.name = biome; ysort.add_child(container)
		var names := ["Biom1Layer", "Trees", "Bushes"] if biome == "Biom1" else ["Biom2Layer", "Trees", "Stones", "Puddles", "DeadWoodTrees", "BerryBushes"]
		for child_name in names:
			var child: Node = TileMapLayer.new() if child_name.ends_with("Layer") else Node2D.new()
			child.name = child_name
			if child is TileMapLayer: (child as TileMapLayer).tile_set = ROAD_TILESET
			container.add_child(child)
	var xz := TileMapLayer.new(); xz.name = "xz"; xz.tile_set = ROAD_TILESET; ysort.add_child(xz)
	var generator := Node.new(); generator.name = "GenerationPipeline"; _preview_world.add_child(generator)
	var source := SeedSource.new(); source.name = "ChunkWorldGenerator"; source.seed = world_seed; generator.add_child(source)
	_road = ROAD.new(); _road.name = "RoadGraphPass"; _road.profile = ROAD_PROFILE; generator.add_child(_road)
	_raster = RASTER.new(); _raster.name = "RoadRasterizationPass"; _raster.profile = ROAD_PROFILE; generator.add_child(_raster)
	_poi = POI.new(); _poi.name = "PoiPlacementPass"; _poi.template = TEMPLATE; generator.add_child(_poi)
	_environment = ENV.new(); _environment.name = "EnvironmentGenerationPass"; _environment.profile = ENV_PROFILE; generator.add_child(_environment)

func _status_for_output() -> String:
	if not _environment.blocking_errors.is_empty(): return "BLOCKING ERROR: " + "; ".join(_environment.blocking_errors)
	var out := _output
	return "Seed %d | Environment placements: %d | manifest: %s | content: %s | RoadGraph: %s | RoadRaster: %s" % [world_seed, (out.accepted as Array).size(), out.environment_manifest_hash, out.environment_content_hash, _road.graph_hash, _raster.raster_hash]

func _update_road_raster_diagnostics() -> void:
	var diagnostics := _raster.get_connectivity_diagnostics()
	road_raster_diagnostics = "Seed %d | road components: %d | graph components: %d | isolated: %d | small components: %d\n%s" % [world_seed, int(diagnostics.road_component_count), int(diagnostics.graph_component_count), (diagnostics.isolated_road_cells as Array).size(), (diagnostics.small_disconnected_components as Array).size(), JSON.stringify(diagnostics)]
	if not (diagnostics.isolated_road_cells as Array).is_empty() or not (diagnostics.small_disconnected_components as Array).is_empty() or not bool(diagnostics.connectivity_matches_graph):
		status = "ROAD RASTER CONNECTIVITY ERROR: " + road_raster_diagnostics

func _update_inspector_and_view() -> void:
	if _runtime_status_label != null:
		_runtime_status_label.text = status
	notify_property_list_changed()
	queue_redraw()

func _headless_smoke() -> void:
	generate_full_world()
	await get_tree().process_frame
	if _output.is_empty() or not _environment.blocking_errors.is_empty():
		push_error("MANUAL_BLOCK_D_SMOKE=FAIL " + status)
		get_tree().quit(1)
		return
	var first := String(_output.environment_content_hash)
	clear_block_d_preview()
	await get_tree().process_frame
	generate_full_world()
	if first != String(_output.environment_content_hash):
		push_error("MANUAL_BLOCK_D_SMOKE=FAIL regenerate hash")
		get_tree().quit(1)
		return
	print("MANUAL_BLOCK_D_SMOKE=PASS seed=%d" % world_seed)
	get_tree().quit(0)

func _draw() -> void:
	if show_world_bounds:
		draw_rect(Rect2(Vector2(BOUNDS.position) * ENV_PROFILE.logical_cell_size, Vector2(BOUNDS.size) * ENV_PROFILE.logical_cell_size), Color("5ea8ff"), false, 4.0)
	if is_instance_valid(_environment) and show_environment_footprints:
		for item in _output.get("accepted", []):
			var cells: Array = item.footprint
			for cell in cells:
				draw_rect(Rect2(Vector2(cell as Vector2i) * ENV_PROFILE.logical_cell_size, ENV_PROFILE.logical_cell_size), Color(0.2, 0.95, 0.45, 0.25), false, 1.0)
	if show_road and is_instance_valid(_road):
		draw_string(ThemeDB.fallback_font, Vector2(12, 24), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
