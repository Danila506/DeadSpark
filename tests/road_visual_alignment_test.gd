extends Node2D

const ROAD_PROFILE := preload("res://Resources/WorldGen/road_generation_profile.tres")
const ROAD_TILESET := preload("res://Assets/World/Roads/RoadTileSet.tres")
const OUTPUT_PATH := "res://tests/artifacts/road_visual/road_alignment_256.png"

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("d7dde2"))
	get_window().size = Vector2i(1600, 1000)
	var layer := TileMapLayer.new()
	layer.name = "RoadLayer"
	layer.tile_set = ROAD_TILESET
	add_child(layer)

	var graph_pass := RoadGraphPass.new()
	graph_pass.name = "RoadGraphPass"
	graph_pass.profile = ROAD_PROFILE
	graph_pass.graph = _build_visual_graph()
	add_child(graph_pass)

	var raster := RoadRasterizationPass.new()
	raster.name = "RoadRasterizationPass"
	raster.profile = ROAD_PROFILE
	raster.graph_pass_path = NodePath("../RoadGraphPass")
	raster.road_layer_path = NodePath("../RoadLayer")
	add_child(raster)
	raster.run_generation_pass()

	var camera := Camera2D.new()
	camera.position = Vector2.ZERO
	camera.zoom = Vector2(0.5, 0.5)
	camera.enabled = true
	add_child(camera)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var absolute_path := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var error := get_viewport().get_texture().get_image().save_png(absolute_path)
	if error != OK:
		push_error("Road visual alignment: cannot save screenshot (%s)" % error)
		get_tree().quit(1)
		return
	print("ROAD_VISUAL_ALIGNMENT_SCREENSHOT=" + absolute_path)
	get_tree().quit(0)

func _build_visual_graph() -> RoadGraph:
	var graph := RoadGraph.new()
	graph.bounds = Rect2i(Vector2i(-5, -4), Vector2i(11, 9))
	graph.add_route(_line(Vector2i(-4, 0), Vector2i(4, 0)), "primary")
	graph.add_route(_line(Vector2i(0, -3), Vector2i(0, 3)), "primary")
	graph.add_route([
		Vector2i(-3, 0), Vector2i(-3, -1), Vector2i(-3, -2),
		Vector2i(-2, -2), Vector2i(-1, -2), Vector2i(0, -2)
	], "secondary")
	graph.add_route([
		Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2),
		Vector2i(2, 2), Vector2i(1, 2), Vector2i(0, 2)
	], "secondary")
	graph.add_route([
		Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(-1, 2),
		Vector2i(-1, 3), Vector2i(0, 3)
	], "secondary")
	return graph

func _line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var cursor := from
	result.append(cursor)
	while cursor != to:
		cursor += Vector2i(signi(to.x - cursor.x), signi(to.y - cursor.y))
		result.append(cursor)
	return result
