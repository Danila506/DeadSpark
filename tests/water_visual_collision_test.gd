extends Node2D

const WATER_PASS := preload("res://World/Generation/water_generation_pass.gd")
const WATER_PROFILE := preload("res://Resources/WorldGen/water_generation_profile.tres")
const LEVEL_SCENE := preload("res://level.tscn")
const BOUNDS := Rect2i(Vector2i(-48, -48), Vector2i(96, 96))


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var source_level := LEVEL_SCENE.instantiate()
	var source_layer := source_level.get_node("Y-Sort_Objects/LakeLayer") as TileMapLayer
	var layer := TileMapLayer.new()
	layer.tile_set = source_layer.tile_set
	layer.scale = source_layer.scale
	add_child(layer)
	source_level.free()

	var generator := WATER_PASS.new() as WaterGenerationPass
	generator.profile = WATER_PROFILE
	add_child(generator)
	var result := generator.build_cells_for_inputs(BOUNDS, 2026)
	var cells: Array[Vector2i] = []
	cells.assign(result.get("cells", []))
	layer.set_cells_terrain_connect(cells, WATER_PROFILE.terrain_set_id, WATER_PROFILE.terrain_id, WATER_PROFILE.terrain_ignore_empty)
	var visual_root := WaterVisualRenderer.rebuild(layer, result.get("components", []))
	if visual_root == null or visual_root.get_child_count() == 0:
		_fail("visual renderer did not create a lake")
		return
	if layer.collision_enabled:
		_fail("legacy TileMap collision must be disabled")
		return

	var lake := visual_root.get_child(0) as Node2D
	var surface := lake.get_node("Surface") as Polygon2D
	var boundary_collision := lake.get_node("LakeBoundary/BoundaryShape") as CollisionShape2D
	var boundary_shape := boundary_collision.shape as ConcavePolygonShape2D
	if surface == null or boundary_shape == null:
		_fail("surface and boundary collision must both exist")
		return
	var segments := boundary_shape.segments
	if segments.size() != surface.polygon.size() * 2:
		_fail("collision segment count does not match visual contour")
		return
	for index in range(surface.polygon.size()):
		if not segments[index * 2].is_equal_approx(surface.polygon[index]):
			_fail("collision boundary diverges from visual point %d" % index)
			return

	var a := surface.polygon[0]
	var b := surface.polygon[1]
	var midpoint := (a + b) * 0.5
	var centroid := Vector2.ZERO
	for point in surface.polygon:
		centroid += point
	centroid /= float(surface.polygon.size())
	var outward := Vector2(-(b - a).y, (b - a).x).normalized()
	if outward.dot(midpoint - centroid) < 0.0:
		outward = -outward

	var actor := CharacterBody2D.new()
	actor.name = "CollisionProbe"
	actor.collision_layer = 1
	actor.collision_mask = 1
	actor.position = midpoint + outward * 80.0
	var actor_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	actor_shape.shape = circle
	actor.add_child(actor_shape)
	add_child(actor)
	await get_tree().physics_frame
	var collision := actor.move_and_collide(-outward * 160.0)
	if collision == null:
		_fail("character probe crossed the visible lake boundary")
		return
	if collision.get_position().distance_to(midpoint) > 12.0:
		_fail("physical contact is not aligned with visual boundary")
		return
	print("WATER_VISUAL_COLLISION_TEST=PASS contact_error=%.3f" % collision.get_position().distance_to(midpoint))
	get_tree().quit(0)


func _fail(message: String) -> void:
	push_error("Water visual collision: " + message)
	get_tree().quit(1)
