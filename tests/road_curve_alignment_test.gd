extends SceneTree

const TILESET_PATH := "res://Assets/World/Roads/RoadTileSet.tres"
const RAW_TILES := [Vector2i(6, 0), Vector2i(7, 0), Vector2i(6, 1), Vector2i(7, 1)]
const PORTS := ["DR", "DL", "UR", "UL"]
const BITS := [TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_RIGHT_SIDE]
const LETTERS := ["U", "D", "L", "R"]
const OPPOSITE := [1, 0, 3, 2]

func _init() -> void:
	var raw := Image.load_from_file(ProjectSettings.globalize_path("res://Assets/World/Roads/RoadLayer256.png"))
	var authored := Image.load_from_file(ProjectSettings.globalize_path("res://Assets/World/Roads/RoadAuthoredAtlas.png"))
	var connected := Image.load_from_file(ProjectSettings.globalize_path("res://Assets/World/Roads/RoadConnected256.png"))
	var tileset := load(TILESET_PATH) as TileSet
	var original_source := tileset.get_source(0) as TileSetAtlasSource
	var connector_source := tileset.get_source(1) as TileSetAtlasSource
	var failures: Array[String] = []
	if raw.get_data() != authored.get_data():
		failures.append("Authored atlas changed")
	var tiles: Array[Dictionary] = []
	for index in range(original_source.get_tiles_count()):
		var coords := original_source.get_tile_id(index)
		var data := original_source.get_tile_data(coords, 0)
		if data.terrain_set != 0:
			continue
		var image := raw.get_region(Rect2i(coords * 256, Vector2i(256, 256)))
		tiles.append({"name": "old:%s" % coords, "data": data, "image": image, "connected": false})
	var preview := Image.create(3072, 768, false, Image.FORMAT_RGBA8)
	preview.fill(Color("d7dde2"))
	for index in range(4):
		var coords := Vector2i(index, 0)
		var data := connector_source.get_tile_data(coords, 0)
		var image := connected.get_region(Rect2i(coords * 256, Vector2i(256, 256)))
		tiles.append({"name": "connected:%d" % index, "data": data, "image": image, "connected": true})
		if original_source.get_tile_data(RAW_TILES[index], 0).terrain_set != -1:
			failures.append("Unadapted artwork still participates in terrain painting")
		var reference := Image.create(256, 256, false, Image.FORMAT_RGBA8)
		reference.blit_rect(raw, Rect2i(RAW_TILES[index] * 256, Vector2i(256, 256)), -original_source.get_tile_data(RAW_TILES[index], 0).texture_origin)
		# Only authorized end bands may differ. Every central pixel is exact.
		for y in range(256):
			for x in range(256):
				var changed_band: bool = (PORTS[index].contains("U") and y < 48) or (PORTS[index].contains("D") and y >= 208) or (PORTS[index].contains("L") and x < 48) or (PORTS[index].contains("R") and x >= 208)
				if not changed_band and image.get_pixel(x, y) != reference.get_pixel(x, y):
					failures.append("Authored center modified at %d:%s" % [index, Vector2i(x, y)])
		var center := Vector2i(index * 768 + 256, 256)
		preview.blend_rect(image, Rect2i(0, 0, 256, 256), center)
		for side_index in range(4):
			var present := data.get_terrain_peering_bit(BITS[side_index]) == 0
			if present != PORTS[index].contains(LETTERS[side_index]):
				failures.append("Wrong adapter port %d:%s" % [index, LETTERS[side_index]])
			if present:
				var direction := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT][side_index] as Vector2i
				var straight := raw.get_region(Rect2i(Vector2i.ZERO if side_index < 2 else Vector2i(0, 256), Vector2i(256, 256)))
				preview.blend_rect(straight, Rect2i(0, 0, 256, 256), center + direction * 256)
		if not _continuous(image, PORTS[index]):
			failures.append("Road broken inside connector %d" % index)
	var pairs := 0
	for a in tiles:
		for b in tiles:
			if not a.connected and not b.connected:
				continue
			for side_index in range(4):
				var opposite: int = OPPOSITE[side_index]
				if a.data.get_terrain_peering_bit(BITS[side_index]) != 0 or b.data.get_terrain_peering_bit(BITS[opposite]) != 0:
					continue
				pairs += 1
				var bad := false
				# All 256 border pixels must match in alpha AND visible color;
				# one touching pixel is no longer considered a successful seam.
				for across in range(256):
					var c1: Color = a.image.get_pixelv(_point(side_index, 0, across))
					var c2: Color = b.image.get_pixelv(_point(opposite, 0, across))
					if c1.a != c2.a or (c1.a > 0.0 and c1 != c2):
						bad = true
						break
				if bad:
					failures.append("Incompatible seam: %s %s %s" % [a.name, LETTERS[side_index], b.name])
	preview.resize(1536, 384, Image.INTERPOLATE_NEAREST)
	if preview.save_png("res://tests/artifacts/road_visual/road_connected_alignment.png") != OK:
		failures.append("Cannot save connected road preview")
	for failure in failures:
		push_error(failure)
	print("ROAD_CONNECTOR_ALIGNMENT: %d compatible pairs, %d errors" % [pairs, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _point(side: int, depth: int, across: int) -> Vector2i:
	match side:
		0: return Vector2i(across, depth)
		1: return Vector2i(across, 255 - depth)
		2: return Vector2i(depth, across)
		_: return Vector2i(255 - depth, across)

func _continuous(image: Image, ports: String) -> bool:
	# An 8px envelope tolerates the original transparent tire-rut grain while
	# detecting missing transition sections. This never modifies rendered art.
	var mask := PackedByteArray()
	mask.resize(32 * 32)
	for y in range(32):
		for x in range(32):
			var alpha := 0.0
			for dy in range(8):
				for dx in range(8):
					alpha += image.get_pixel(x * 8 + dx, y * 8 + dy).a
			mask[y * 32 + x] = 1 if alpha > 0.2 else 0
	var first: int = LETTERS.find(ports.substr(0, 1))
	var second: int = LETTERS.find(ports.substr(1, 1))
	var queue: Array[Vector2i] = []
	var seen := PackedByteArray()
	seen.resize(1024)
	for across in range(32):
		var point := _point(first, 0, across * 8) / 8
		if mask[point.y * 32 + point.x] != 0:
			queue.append(point)
			seen[point.y * 32 + point.x] = 1
	var cursor := 0
	while cursor < queue.size():
		var point := queue[cursor]
		cursor += 1
		if (second == 0 and point.y == 0) or (second == 1 and point.y == 31) or (second == 2 and point.x == 0) or (second == 3 and point.x == 31):
			return true
		for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = point + direction
			if next.x < 0 or next.x > 31 or next.y < 0 or next.y > 31:
				continue
			var key := next.y * 32 + next.x
			if mask[key] != 0 and seen[key] == 0:
				seen[key] = 1
				queue.append(next)
	return false
