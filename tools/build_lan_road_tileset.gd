extends SceneTree

const BASE_PATH := "res://Assets/World/Roads/RoadTileSet.tres"
const OUTPUT_PATH := "res://Assets/World/Roads/LanRoadTileSet.tres"
const STEP := 64

func _init() -> void:
	var base := load(BASE_PATH) as TileSet
	var manual := base.duplicate(true) as TileSet
	for source_index in range(manual.get_source_count()):
		var source_id := manual.get_source_id(source_index)
		_add_offsets(manual.get_source(source_id) as TileSetAtlasSource, source_id)
	manual.set_meta("manual_road_offset_step", STEP)
	manual.set_meta("manual_road_base_tileset", BASE_PATH)
	var error := ResourceSaver.save(manual, OUTPUT_PATH)
	if error != OK:
		push_error("Cannot build LAN road tileset: %s" % error)
		quit(1)
		return
	print("Built LAN road tileset: 64px offsets; base tiles and 256px grid preserved.")
	quit(0)

func _add_offsets(source: TileSetAtlasSource, source_id: int) -> void:
	for index in range(source.get_tiles_count()):
		var coords := source.get_tile_id(index)
		if source_id == 0 and coords == Vector2i(5, 1):
			continue # Existing empty placeholder, not a road brush.
		var original := source.get_tile_data(coords, 0)
		for y in range(4):
			for x in range(4):
				var alternative := y * 4 + x
				if alternative == 0:
					continue
				source.create_alternative_tile(coords, alternative)
				var data := source.get_tile_data(coords, alternative)
				data.texture_origin = original.texture_origin + Vector2i(x, y) * STEP
				data.flip_h = original.flip_h
				data.flip_v = original.flip_v
				data.transpose = original.transpose
				data.modulate = original.modulate
				data.material = original.material
				data.z_index = original.z_index
				data.y_sort_origin = original.y_sort_origin
				# Explicit manual brushes only: terrain painting and procedural
				# rasterization must never choose a displaced sprite implicitly.
				data.terrain_set = -1
				data.probability = 0.0
