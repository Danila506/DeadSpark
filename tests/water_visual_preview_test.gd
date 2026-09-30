extends Node2D

const WATER_PASS := preload("res://World/Generation/water_generation_pass.gd")
const WATER_PROFILE := preload("res://Resources/WorldGen/water_generation_profile.tres")
const LEVEL_SCENE := preload("res://level.tscn")
const OUTPUT_DIRECTORY := "res://tests/artifacts/water_visual"
const BOUNDS := Rect2i(Vector2i(-48, -48), Vector2i(96, 96))
const SEEDS: Array[int] = [42, 1337, 2026, 7331, 99999]

var _water_layer: TileMapLayer
var _camera: Camera2D


func _ready() -> void:
	call_deferred("_capture_previews")


func _capture_previews() -> void:
	RenderingServer.set_default_clear_color(Color("d9e1e5"))
	get_window().size = Vector2i(1400, 1000)
	var source_level := LEVEL_SCENE.instantiate()
	var source_layer := source_level.get_node("Y-Sort_Objects/LakeLayer") as TileMapLayer
	_water_layer = TileMapLayer.new()
	_water_layer.name = "LakeLayer"
	_water_layer.tile_set = source_layer.tile_set
	_water_layer.scale = source_layer.scale
	_water_layer.material = source_layer.material
	add_child(_water_layer)
	source_level.free()

	_camera = Camera2D.new()
	_camera.enabled = true
	add_child(_camera)

	var generator := WATER_PASS.new() as WaterGenerationPass
	generator.profile = WATER_PROFILE
	add_child(generator)
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	DirAccess.make_dir_recursive_absolute(output_path)

	for seed in SEEDS:
		_water_layer.clear()
		var result := generator.build_cells_for_inputs(BOUNDS, seed)
		var cells: Array[Vector2i] = []
		cells.assign(result.get("cells", []))
		_water_layer.set_cells_terrain_connect(
			cells,
			WATER_PROFILE.terrain_set_id,
			WATER_PROFILE.terrain_id,
			WATER_PROFILE.terrain_ignore_empty
		)
		WaterVisualRenderer.rebuild(_water_layer, result.get("components", []))
		_frame_largest_component(result.get("components", []))
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var filename := "%s/lake_%d.png" % [output_path, seed]
		var error := get_viewport().get_texture().get_image().save_png(filename)
		if error != OK:
			push_error("Water visual preview: cannot save %s (%s)" % [filename, error])
			get_tree().quit(1)
			return
		print("WATER_VISUAL_PREVIEW seed=%d cells=%d screenshot=%s" % [seed, cells.size(), filename])

	print("WATER_VISUAL_PREVIEW=PASS")
	get_tree().quit(0)


func _frame_largest_component(components: Array) -> void:
	var largest: Array = []
	for component in components:
		if component is Array and component.size() > largest.size():
			largest = component
	if largest.is_empty():
		_camera.position = Vector2.ZERO
		_camera.zoom = Vector2.ONE
		return

	var min_cell := largest[0] as Vector2i
	var max_cell := min_cell
	for cell_variant in largest:
		var cell := cell_variant as Vector2i
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
	var center_cell := Vector2(min_cell + max_cell) * 0.5
	var center_local := _water_layer.map_to_local(Vector2i(roundi(center_cell.x), roundi(center_cell.y)))
	_camera.position = _water_layer.to_global(center_local)
	var pixel_size := Vector2(max_cell - min_cell + Vector2i.ONE) * Vector2(_water_layer.tile_set.tile_size) * _water_layer.scale
	var available := Vector2(1180.0, 780.0)
	var fit_zoom := minf(available.x / maxf(pixel_size.x, 1.0), available.y / maxf(pixel_size.y, 1.0))
	_camera.zoom = Vector2.ONE * clampf(fit_zoom, 0.45, 1.15)
