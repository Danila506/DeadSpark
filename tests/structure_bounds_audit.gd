extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for path in ["res://World/Assets/Bunker/Bunker.tscn", "res://World/Assets/Houses/ForesterHouse/forester_house.tscn", "res://World/Assets/Houses/ForesterHouse2/forester_house2.tscn", "res://Enemies/Bandits/bandit_base.tscn", "res://Enemies/Bandits/BanditBase2.tscn"]:
		var scene := (load(path) as PackedScene).instantiate()
		var bounds := _bounds(scene, Transform2D.IDENTITY)
		print("ASSET_BOUNDS ", path, " ", bounds)
		scene.free()
	quit()

func _bounds(node: Node, parent_transform: Transform2D) -> Rect2:
	var transform := parent_transform
	if node is Node2D: transform *= (node as Node2D).transform
	var result := Rect2()
	if node is Sprite2D and (node as Sprite2D).texture != null:
		result = transform * (node as Sprite2D).get_rect()
	if node is TileMapLayer and (node as TileMapLayer).tile_set != null:
		var layer := node as TileMapLayer
		var rect := layer.get_used_rect()
		result = transform * Rect2(Vector2(rect.position * layer.tile_set.tile_size), Vector2(rect.size * layer.tile_set.tile_size))
	if node is CollisionShape2D and (node as CollisionShape2D).shape != null:
		result = transform * (node as CollisionShape2D).shape.get_rect()
	if node is CollisionPolygon2D:
		for point in (node as CollisionPolygon2D).polygon:
			var position := transform * point
			result = Rect2(position, Vector2(0.001, 0.001)) if not result.has_area() else result.expand(position)
	for child in node.get_children():
		var child_bounds := _bounds(child, transform)
		if child_bounds.has_area(): result = result.merge(child_bounds) if result.has_area() else child_bounds
	return result
