extends "res://tests/manual_block_d_validation.gd"

func _ready() -> void:
	call_deferred("_capture_forest")

func _build_preview_world() -> void:
	super._build_preview_world()
	# The contract fixture uses a road tileset for every layer. Render with the
	# actual production tilesets so environment tiles do not look like roads.
	var source := (load("res://level.tscn") as PackedScene).instantiate()
	for path in ["Y-Sort_Objects/Biom1/Biom1Layer", "Y-Sort_Objects/Biom2/Biom2Layer", "Y-Sort_Objects/xz"]:
		(_preview_world.get_node(path) as TileMapLayer).tile_set = (source.get_node(path) as TileMapLayer).tile_set
		(_preview_world.get_node(path) as TileMapLayer).transform = (source.get_node(path) as TileMapLayer).transform
	source.free()

func _capture_forest() -> void:
	world_seed = 1337
	show_environment_footprints = false
	show_world_bounds = false
	RenderingServer.set_default_clear_color(Color("d6dce0"))
	generate_full_world()
	if _output.is_empty() or not _environment.blocking_errors.is_empty():
		get_tree().quit(1)
		return
	print("FOREST_PREVIEW statistics=", _environment.get_forest_statistics())
	var camera := Camera2D.new()
	add_child(camera)
	camera.zoom = Vector2(0.18, 0.18)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var directory := "res://tests/artifacts/forest"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	get_viewport().get_texture().get_image().save_png(directory + "/overview.png")
	camera.position = Vector2(-1500, -1200)
	camera.zoom = Vector2(0.8, 0.8)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(directory + "/detail.png")
	print("FOREST_PREVIEW=PASS")
	get_tree().quit()
