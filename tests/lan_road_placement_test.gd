extends SceneTree

const BASE_PATH := "res://Assets/World/Roads/RoadTileSet.tres"
const LAN_PATH := "res://Assets/World/Roads/LanRoadTileSet.tres"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var base := load(BASE_PATH) as TileSet
	var manual := load(LAN_PATH) as TileSet
	var normal := base.get_source(0) as TileSetAtlasSource
	var shifted := manual.get_source(0) as TileSetAtlasSource
	var failures: Array[String] = []
	if base.tile_size != Vector2i(256, 256) or manual.tile_size != base.tile_size:
		failures.append("Road grid changed")
	if normal.texture.resource_path != shifted.texture.resource_path or normal.texture_region_size != shifted.texture_region_size:
		failures.append("Road textures or their dimensions changed")
	if not manual.has_source(1):
		failures.append("LAN connector atlas is missing")
	else:
		var connected := manual.get_source(1) as TileSetAtlasSource
		for index in range(4):
			var coords := Vector2i(index, 0)
			var data := connected.get_tile_data(coords, 0)
			if data.terrain_set != 0 or data.texture_origin != Vector2i.ZERO:
				failures.append("Invalid connected road %d" % index)
			for alternative in range(1, 16):
				var brush := connected.get_tile_data(coords, alternative)
				var expected := Vector2i(alternative % 4, floori(alternative / 4.0)) * 64
				if brush.texture_origin != expected or brush.terrain_set != -1:
					failures.append("Invalid connector offset %d:%d" % [index, alternative])
	for index in range(normal.get_tiles_count()):
		var coords := normal.get_tile_id(index)
		var original := normal.get_tile_data(coords, 0)
		var unchanged := shifted.get_tile_data(coords, 0)
		if original.texture_origin != unchanged.texture_origin or original.terrain_set != unchanged.terrain_set:
			failures.append("Base tile changed at %s" % coords)
		for side in [TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_RIGHT_SIDE]:
			if original.terrain_set >= 0 and original.get_terrain_peering_bit(side) != unchanged.get_terrain_peering_bit(side):
				failures.append("Base connector changed at %s" % coords)
		if coords == Vector2i(5, 1):
			continue
		for alternative in range(1, 16):
			var data := shifted.get_tile_data(coords, alternative)
			var expected := Vector2i(alternative % 4, floori(alternative / 4.0)) * 64
			if data.texture_origin != original.texture_origin + expected or data.terrain_set != -1:
				failures.append("Invalid manual offset at %s:%d" % [coords, alternative])
	var layer := TileMapLayer.new()
	layer.tile_set = manual
	# Two adjacent rows still retain their 256px grid coordinates, while the
	# lower road is drawn 192px higher: visible centerline separation is 64px.
	layer.set_cell(Vector2i.ZERO, 0, Vector2i(0, 1), 0)
	layer.set_cell(Vector2i.DOWN, 0, Vector2i(0, 1), 12)
	var upper := layer.map_to_local(Vector2i.ZERO) - Vector2(layer.get_cell_tile_data(Vector2i.ZERO).texture_origin)
	var lower := layer.map_to_local(Vector2i.DOWN) - Vector2(layer.get_cell_tile_data(Vector2i.DOWN).texture_origin)
	if lower - upper != Vector2(0, 64):
		failures.append("Manual roads cannot be placed 64px apart")
	var atlas := normal.texture.get_image()
	var preview := Image.create(1024, 512, false, Image.FORMAT_RGBA8)
	preview.fill(Color("d7dde2"))
	var road_region := Rect2i(0, 256, 256, 256)
	for x in range(2):
		preview.blend_rect(atlas, road_region, Vector2i(x * 256, 0))
		preview.blend_rect(atlas, road_region, Vector2i(x * 256, 256))
		preview.blend_rect(atlas, road_region, Vector2i(512 + x * 256, 0))
		preview.blend_rect(atlas, road_region, Vector2i(512 + x * 256, 64))
	preview.fill_rect(Rect2i(510, 0, 4, 512), Color("a0abb5"))
	if preview.save_png("res://tests/artifacts/road_visual/lan_road_spacing.png") != OK:
		failures.append("Cannot save manual spacing preview")
	layer.clear()
	var loop: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(1, 2), Vector2i(0, 2), Vector2i(0, 1)]
	layer.set_cells_terrain_connect(loop, 0, 0)
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var bits := [TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_RIGHT_SIDE]
	for cell in loop:
		var data := layer.get_cell_tile_data(cell)
		if data == null or data.terrain_set != 0:
			failures.append("Terrain brush cannot draw road at %s" % cell)
			continue
		for index in range(4):
			var expected := 0 if loop.has(cell + directions[index]) else -1
			if data.get_terrain_peering_bit(bits[index]) != expected:
				failures.append("Terrain brush chose wrong connection at %s" % cell)
	layer.free()
	# Inspect resources without instantiating the full gameplay scene.
	var lan := load("res://LanMap.tscn") as PackedScene
	var level := load("res://level.tscn") as PackedScene
	if not _scene_uses_tileset(lan, NodePath("RoadLayer"), LAN_PATH):
		failures.append("LAN does not use the manual tileset")
	if not _scene_uses_tileset(level, NodePath("Y-Sort_Objects/RoadLayer"), BASE_PATH):
		failures.append("Procedural level tileset changed")
	for failure in failures:
		push_error(failure)
	print("LAN_ROAD_PLACEMENT: %d errors" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _scene_uses_tileset(scene: PackedScene, node_path: NodePath, resource_path: String) -> bool:
	var state := scene.get_state()
	for index in range(state.get_node_count()):
		if str(state.get_node_path(index)).trim_prefix("./") != str(node_path):
			continue
		for property in range(state.get_node_property_count(index)):
			if state.get_node_property_name(index, property) == &"tile_set":
				var tileset := state.get_node_property_value(index, property) as TileSet
				return tileset != null and tileset.resource_path == resource_path
	return false
