@tool
extends Node2D

const PROFILE := preload("res://Resources/WorldGen/road_generation_profile.tres")
const TEMPLATE := preload("res://Resources/WorldGen/village_poi_template.tres")
const TILESET := preload("res://Assets/World/Roads/RoadTileSet.tres")
const ROAD_PASS := preload("res://World/Generation/road_graph_pass.gd")
const RASTER_PASS := preload("res://World/Generation/road_rasterization_pass.gd")
const POI_PASS := preload("res://World/Generation/poi_placement_pass.gd")
const BOUNDS := Rect2i(Vector2i(-48, -48), Vector2i(96, 96))

@export var world_seed := 1337
@export var show_poi_bounds := true:
	set(value):
		show_poi_bounds = value
		queue_redraw()
@export var show_connector := true:
	set(value):
		show_connector = value
		queue_redraw()
@export var show_road := true:
	set(value):
		show_road = value
		queue_redraw()
@export var show_road_clearance := true:
	set(value):
		show_road_clearance = value
		queue_redraw()
@export var show_generated_object_ids := false:
	set(value):
		show_generated_object_ids = value
		_refresh_labels()
@export_tool_button("Generate Block C preview") var generate_preview_action = generate_preview
@export_tool_button("Clear Block C preview") var clear_preview_action = clear_preview

var _road: RoadGraphPass
var _poi: PoiPlacementPass
var _road_occupancy := {}

func _ready() -> void:
	if not Engine.is_editor_hint():
		generate_preview()

func generate_preview() -> void:
	clear_preview()
	var ysort := Node2D.new()
	ysort.name = "Y-Sort_Objects"
	add_child(ysort)
	var layer := TileMapLayer.new()
	layer.name = "RoadLayer"
	layer.tile_set = TILESET
	ysort.add_child(layer)
	_road = ROAD_PASS.new()
	_road.name = "RoadGraphPass"
	_road.profile = PROFILE
	add_child(_road)
	var raster := RASTER_PASS.new()
	raster.name = "RoadRasterizationPass"
	raster.profile = PROFILE
	raster.road_layer_path = NodePath("../Y-Sort_Objects/RoadLayer")
	add_child(raster)
	_poi = POI_PASS.new()
	_poi.name = "PoiPlacementPass"
	_poi.template = TEMPLATE
	_poi.road_graph_pass_path = NodePath("../RoadGraphPass")
	_poi.road_raster_pass_path = NodePath("../RoadRasterizationPass")
	_poi.spawn_parent_path = NodePath("../Y-Sort_Objects")
	add_child(_poi)
	_road.build_graph_for_inputs(BOUNDS, world_seed)
	_road.graph_hash = GenerationHashes.sha256_of(_road.graph.canonical_manifest())
	raster.run_generation_pass()
	_poi.run_generation_pass()
	_road_occupancy = layer.get_meta("world_generation_road_occupancy", {})
	_refresh_labels()
	queue_redraw()

func clear_preview() -> void:
	for child in get_children():
		child.queue_free()
	_road = null
	_poi = null
	_road_occupancy.clear()
	queue_redraw()

func _draw() -> void:
	if _road == null or _road.graph == null:
		return
	var cell_size := 60.0
	if show_road_clearance:
		for cell_variant in _road_occupancy:
			if String(_road_occupancy[cell_variant]) == "ROAD_CLEARANCE":
				draw_rect(Rect2(Vector2(cell_variant as Vector2i) * cell_size, Vector2.ONE * cell_size), Color(0.3, 0.55, 0.9, 0.12), true)
	if show_road:
		for cell in _road.graph.cells:
			draw_rect(Rect2(Vector2(cell as Vector2i) * cell_size, Vector2.ONE * cell_size), Color(1.0, 0.75, 0.2, 0.5), false, 2.0)
	if _poi != null:
		for accepted in _poi.accepted:
			var position := accepted.world_position as Vector2
			if show_poi_bounds:
				draw_rect(Rect2(position + TEMPLATE.authored_bounds.position, TEMPLATE.authored_bounds.size), Color(0.2, 1.0, 0.55, 0.8), false, 3.0)
			if show_connector:
				var connector := position + TEMPLATE.connector_local_position
				draw_circle(connector, 10.0, Color(1.0, 0.2, 0.8, 0.9))
				draw_line(connector, connector + TEMPLATE.connector_facing.normalized() * 50.0, Color(1.0, 0.2, 0.8, 0.9), 3.0)

func _refresh_labels() -> void:
	var labels := get_node_or_null("GeneratedIdLabels")
	if labels != null:
		labels.queue_free()
	if not show_generated_object_ids:
		return
	var root := Node2D.new()
	root.name = "GeneratedIdLabels"
	add_child(root)
	var ysort := get_node_or_null("Y-Sort_Objects")
	if ysort == null:
		return
	for node in ysort.get_children():
		if node is VillageGenerator:
			for generated in node.get_node("GeneratedContent").get_children():
				var label := Label.new()
				label.text = String(generated.get_meta("generated_object_id", ""))
				label.position = (generated as Node2D).position
				root.add_child(label)
