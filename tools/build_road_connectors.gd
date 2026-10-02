extends SceneTree

const BASE_PATH := "res://Assets/World/Roads/RoadTileSet.tres"
const OUTPUT_PATH := "res://Assets/World/Roads/RoadConnected256.png"
const RAW_TILES := [Vector2i(6, 0), Vector2i(7, 0), Vector2i(6, 1), Vector2i(7, 1)]
const SIDES := ["DR", "DL", "UR", "UL"]
const BAND := 48
const BLEND := 12

func _init() -> void:
	var atlas := Image.load_from_file(ProjectSettings.globalize_path("res://Assets/World/Roads/RoadLayer256.png"))
	var tileset := load(BASE_PATH) as TileSet
	var source := tileset.get_source(0) as TileSetAtlasSource
	var output := Image.create(1024, 256, false, Image.FORMAT_RGBA8)
	for index in range(RAW_TILES.size()):
		var tile := Image.create(256, 256, false, Image.FORMAT_RGBA8)
		var origin := source.get_tile_data(RAW_TILES[index], 0).texture_origin
		tile.blit_rect(atlas, Rect2i(RAW_TILES[index] * 256, Vector2i(256, 256)), -origin)
		var authored := tile.duplicate() as Image
		for side in SIDES[index]:
			_add_transition(tile, authored, atlas, side, SIDES[index])
		output.blit_rect(tile, Rect2i(0, 0, 256, 256), Vector2i(index * 256, 0))
	var error := output.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("Cannot save connector atlas: %s" % error)
		quit(1)
		return
	print("ROAD_CONNECTORS_BUILT: 4 tiles; authored centers retained, 48px transition bands")
	quit(0)

func _point(side: String, depth: int, across: int) -> Vector2i:
	match side:
		"U": return Vector2i(across, depth)
		"D": return Vector2i(across, 255 - depth)
		"L": return Vector2i(depth, across)
		_: return Vector2i(255 - depth, across)

func _center(image: Image, side: String, depth: int, expected: float) -> float:
	var weight := 0.0
	var weighted_position := 0.0
	for across in range(maxi(0, floori(expected - 40)), mini(256, ceili(expected + 40))):
		var alpha := image.get_pixelv(_point(side, depth, across)).a
		# Favor dark road pixels over the artist's faint square shoulder patches.
		var importance := alpha * alpha * alpha
		weight += importance
		weighted_position += across * importance
	return weighted_position / weight if weight > 0.0 else expected


func _add_transition(tile: Image, authored: Image, atlas: Image, side: String, sides: String) -> void:
	var vertical := side == "U" or side == "D"
	var positive := sides.contains("R") if vertical else sides.contains("D")
	var expected := 128.0 + BAND if positive else 128.0 - BAND
	var end_center := _center(authored, side, BAND, expected)
	var next_center := _center(authored, side, BAND + 8, end_center)
	var slope := clampf((next_center - end_center) / 8.0, -1.5, 1.5)
	var straight_origin := Vector2i.ZERO if vertical else Vector2i(0, 256)
	for depth in range(BAND):
		var t := clampf((depth - 8.0) / (BAND - 8.0), 0.0, 1.0)
		# Cubic Hermite joins a flat canonical port to the authored tangent.
		var t2 := t * t
		var t3 := t2 * t
		var center := (2 * t3 - 3 * t2 + 1) * 128.0 + (-2 * t3 + 3 * t2) * end_center + (t3 - t2) * slope * (BAND - 8)
		var shift := roundi(center - 128.0)
		var blend := smoothstep(float(BAND - BLEND), float(BAND), float(depth))
		for across in range(256):
			var point := _point(side, depth, across)
			var sample_across := across - shift
			var connector := Color(0, 0, 0, 0)
			if sample_across >= 0 and sample_across < 256:
				connector = atlas.get_pixelv(straight_origin + _point(side, depth, sample_across))
			tile.set_pixelv(point, connector.lerp(authored.get_pixelv(point), blend))
