extends SceneTree

## Bake only vegetation into the authored LAN map. Gameplay worldgen stays disabled.
const MAP := "res://LanMap.tscn"
const TILESET := "res://Assets/World/Presets_world/LanVegetationTileSet.tres"
const PROFILE := "res://Resources/WorldGen/lan_vegetation_profile.tres"
const BEGIN := "; BEGIN GENERATED LAN VEGETATION"
const END := "; END GENERATED LAN VEGETATION"
const CELL := Vector2(60, 60)
var occupancy: WorldOccupancyMap
var claim_index := 0
var verify_only := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var map := load(MAP).instantiate() as Node2D
	var authored := map.get_node("Y-Sort_Objects/PresetsLayer1") as TileMapLayer
	var tiles := authored.tile_set.duplicate(true) as TileSet
	var atlas := tiles.get_source(0) as TileSetAtlasSource
	# Atlas rectangles use the author's original 16px grid, without changing pixels.
	for definition in [[Vector2i(15, 2), Vector2i(4, 8)], [Vector2i(15, 10), Vector2i(4, 8)], [Vector2i(36, 4), Vector2i(5, 6)], [Vector2i(64, 0), Vector2i(4, 7)], [Vector2i(64, 8), Vector2i(4, 6)], [Vector2i(64, 16), Vector2i(4, 7)], [Vector2i(86, 6), Vector2i(4, 2)], [Vector2i(90, 6), Vector2i(4, 2)], [Vector2i(90, 9), Vector2i(4, 2)], [Vector2i(84, 11), Vector2i(3, 3)], [Vector2i(87, 11), Vector2i(3, 3)], [Vector2i(90, 11), Vector2i(3, 3)]]:
		if not atlas.has_tile(definition[0]): atlas.create_tile(definition[0], definition[1])
	# Sort trees at their feet and collide only with trunks, leaving the canopy walkable.
	if tiles.get_physics_layers_count() == 0: tiles.add_physics_layer()
	tiles.set_physics_layer_collision_layer(0, 1)
	for coords in [Vector2i(15, 2), Vector2i(15, 10), Vector2i(36, 4), Vector2i(64, 0), Vector2i(64, 8), Vector2i(64, 16), Vector2i(86, 14), Vector2i(86, 25)]:
		var data := atlas.get_tile_data(coords, 0)
		var size := Vector2(atlas.get_tile_size_in_atlas(coords) * atlas.texture_region_size)
		data.y_sort_origin = int(size.y * 0.5 - 10)
		data.set_collision_polygons_count(0, 1)
		var half_width := 17.0 if coords.x == 86 else 7.0
		var foot := size.y * 0.5 - 12.0
		data.set_collision_polygon_points(0, 0, PackedVector2Array([Vector2(-half_width, foot - 6), Vector2(half_width, foot - 6), Vector2(half_width, foot + 6), Vector2(-half_width, foot + 6)]))
	var ground := map.get_node("SnowLayer") as TileMapLayer
	var bounds := ground.get_used_rect()
	occupancy = WorldOccupancyMap.new()
	occupancy.reset(bounds)
	_reserve_geometry(map, Transform2D.IDENTITY)
	_reserve_tiles(map.get_node("RoadLayer"), WorldOccupancyMap.ROAD)
	_reserve_tiles(authored, WorldOccupancyMap.STATIC_PROP | WorldOccupancyMap.NO_SPAWN)
	_reserve_tiles(map.get_node("Y-Sort_Objects/PresetsLayer2"), WorldOccupancyMap.BUILDING)
	for marker in map.get_node("NetworkSpawnPoints").get_children():
		_reserve(Rect2(marker.position - Vector2(100, 100), Vector2(200, 200)), WorldOccupancyMap.NO_SPAWN)
	var context := Node2D.new()
	root.add_child(context)
	var layer := TileMapLayer.new()
	layer.name = "LanVegetation"
	layer.tile_set = tiles
	layer.y_sort_enabled = true
	context.add_child(layer)
	var poi := PoiPlacementPass.new()
	poi.name = "PoiPlacementPass"
	poi.occupancy = occupancy
	context.add_child(poi)
	var pass_node := EnvironmentGenerationPass.new()
	pass_node.name = "EnvironmentGenerationPass"
	pass_node.profile = load(PROFILE)
	context.add_child(pass_node)
	pass_node.run_generation_pass()
	var manifest := pass_node.get_generation_output_manifest()
	var first_data := layer.tile_map_data
	pass_node.run_generation_pass()
	if first_data != layer.tile_map_data or manifest.environment_content_hash != pass_node.get_generation_output_manifest().environment_content_hash or not pass_node.blocking_errors.is_empty():
		push_error("LAN vegetation is not deterministic or has generation errors")
		quit(1)
		return
	var counts := {}
	for placement in pass_node.accepted:
		counts[placement.entry_id] = int(counts.get(placement.entry_id, 0)) + 1
	for entry in pass_node.profile.entries:
		if int(counts.get(entry.entry_id, 0)) == 0:
			push_error("No placements for " + entry.entry_id)
			quit(1)
			return
	if not _validate_generated(pass_node, layer, counts):
		map.free()
		context.free()
		quit(1)
		return
	if not verify_only and "--verify" not in OS.get_cmdline_user_args():
		if ResourceSaver.save(tiles, TILESET) != OK:
			quit(1)
			return
		var text := FileAccess.get_file_as_string(MAP)
		var start := text.find(BEGIN)
		if start >= 0:
			text = text.substr(0, start) + text.substr(text.find(END, start) + END.length())
		if not text.contains('id="lan_vegetation_tiles"'):
			var insert := text.find("[sub_resource")
			text = text.insert(insert, '[ext_resource type="TileSet" path="%s" id="lan_vegetation_tiles"]\n\n' % TILESET)
		text = text.strip_edges() + '\n\n%s\n[node name="LanVegetation" type="TileMapLayer" parent="Y-Sort_Objects"]\ny_sort_enabled = true\ntile_set = ExtResource("lan_vegetation_tiles")\ntile_map_data = PackedByteArray("%s")\nmetadata/generation_profile = "%s"\n%s\n' % [BEGIN, Marshalls.raw_to_base64(layer.tile_map_data), PROFILE, END]
		var file := FileAccess.open(MAP, FileAccess.WRITE)
		file.store_string(text)
	else:
		var saved := map.get_node_or_null("Y-Sort_Objects/LanVegetation") as TileMapLayer
		if saved == null or saved.tile_map_data != first_data:
			push_error("Saved LAN vegetation differs from the deterministic bake")
			quit(1)
			return
	print("LAN_VEGETATION: bounds=%s counts=%s hash=%s; deterministic, roads/buildings/spawns protected" % [bounds, counts, manifest.environment_content_hash])
	_preview(map, layer, bounds)
	map.free()
	context.free()
	quit(0)

func _validate_generated(_pass_node: EnvironmentGenerationPass, _layer: TileMapLayer, _counts: Dictionary) -> bool:
	return true

func _preview(map: Node2D, vegetation: TileMapLayer, bounds: Rect2i) -> void:
	var offset := Vector2(bounds.position) * CELL
	var picture := Image.create(bounds.size.x * 60, bounds.size.y * 60, false, Image.FORMAT_RGBA8)
	picture.fill(Color("cad0cc"))
	for layer in [map.get_node("RoadLayer"), vegetation]:
		var cells: Array[Vector2i] = layer.get_used_cells()
		cells.sort_custom(func(a, b): return a.y < b.y if a.y != b.y else a.x < b.x)
		for cell in cells:
			var source := layer.tile_set.get_source(layer.get_cell_source_id(cell)) as TileSetAtlasSource
			var data: TileData = layer.get_cell_tile_data(cell)
			var coords: Vector2i = layer.get_cell_atlas_coords(cell)
			var region := source.get_tile_texture_region(coords)
			var position: Vector2 = layer.position + layer.map_to_local(cell) - Vector2(data.texture_origin) - Vector2(region.size) * 0.5 - offset
			picture.blend_rect(source.texture.get_image(), region, Vector2i(position))
	picture.resize(1000, 900, Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts/lan_vegetation")
	picture.save_png("res://tests/artifacts/lan_vegetation/overview.png")

func _reserve(rect: Rect2, flags: int) -> void:
	var cells: Array[Vector2i] = []
	var first := Vector2i((rect.position / CELL).floor())
	var last := Vector2i(((rect.end - Vector2(0.001, 0.001)) / CELL).floor())
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var cell := Vector2i(x, y)
			if occupancy.bounds.has_point(cell): cells.append(cell)
	if cells.is_empty(): return
	claim_index += 1
	occupancy.claim_cells(cells, flags, "lan/authored/%d" % claim_index, "lan_authored")

func _reserve_geometry(node: Node, parent_transform: Transform2D) -> void:
	if node.name in [&"WorldGeneration", &"UI", &"HUD", &"Player2", &"LanVegetation"]: return
	var transform := parent_transform
	if node is Node2D: transform *= (node as Node2D).transform
	if node is CollisionShape2D:
		var shape := node as CollisionShape2D
		if shape.shape != null and not shape.disabled:
			_reserve((transform * shape.shape.get_rect()).grow(30), WorldOccupancyMap.BUILDING)
	elif node is CollisionPolygon2D:
		var polygon := node as CollisionPolygon2D
		if not polygon.disabled and not polygon.polygon.is_empty():
			var rect := Rect2(transform * polygon.polygon[0], Vector2.ZERO)
			for point in polygon.polygon: rect = rect.expand(transform * point)
			_reserve(rect.grow(30), WorldOccupancyMap.BUILDING)
	for child in node.get_children(): _reserve_geometry(child, transform)

func _reserve_tiles(layer: TileMapLayer, flags: int) -> void:
	for cell in layer.get_used_cells():
		var source := layer.tile_set.get_source(layer.get_cell_source_id(cell)) as TileSetAtlasSource
		if source == null: continue
		var coords := layer.get_cell_atlas_coords(cell)
		var data := layer.get_cell_tile_data(cell)
		var size := Vector2(source.get_tile_size_in_atlas(coords) * source.texture_region_size)
		var position := layer.position + layer.map_to_local(cell) - Vector2(data.texture_origin) - size * 0.5
		# Reserve the actual shifted drawing, including manual road alternatives.
		_reserve(Rect2(position, size), flags)
