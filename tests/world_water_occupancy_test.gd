extends Node

const ROAD_TILESET := preload("res://Assets/World/Roads/RoadTileSet.tres")

func _ready() -> void:
	var world := Node.new()
	world.name = "World"
	add_child(world)
	var objects := Node2D.new()
	objects.name = "Y-Sort_Objects"
	world.add_child(objects)
	var water_layer := TileMapLayer.new()
	water_layer.name = "LakeLayer"
	water_layer.tile_set = ROAD_TILESET
	objects.add_child(water_layer)
	water_layer.set_cell(Vector2i(2, 3), 0, Vector2i.ZERO)
	water_layer.set_cell(Vector2i(50, 50), 0, Vector2i.ZERO)

	var generation := Node.new()
	generation.name = "Generation"
	world.add_child(generation)
	var poi := PoiPlacementPass.new()
	poi.name = "PoiPlacementPass"
	generation.add_child(poi)
	poi.occupancy.reset(Rect2i(Vector2i.ZERO, Vector2i(20, 20)))
	poi._import_water_claims()

	var manifest := poi.occupancy.canonical_manifest()
	var claims: Array = manifest.get("claims", [])
	if claims.size() != 1:
		_fail("expected one bounded water claim, got %d" % claims.size())
		return
	var claim := claims[0] as Dictionary
	if int(claim.get("flags", 0)) != WorldOccupancyMap.WATER:
		_fail("water flag was not imported")
		return
	var claimed_cells := claim.get("cells", []) as Array
	var expected_center := Vector2i((water_layer.to_global(water_layer.map_to_local(Vector2i(2, 3))) / poi.occupancy_cell_size).floor())
	if not claimed_cells.has(expected_center):
		_fail("transformed water footprint misses its center: %s" % str(claimed_cells))
		return
	for claimed_cell in claimed_cells:
		if not poi.occupancy.bounds.has_point(claimed_cell as Vector2i):
			_fail("out-of-bounds water cell was not filtered: %s" % str(claimed_cell))
			return
	print("WORLD_WATER_OCCUPANCY_TEST=PASS")
	get_tree().quit(0)

func _fail(message: String) -> void:
	push_error("World water occupancy: " + message)
	get_tree().quit(1)
