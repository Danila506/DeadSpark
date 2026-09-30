extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var level := (load("res://level.tscn") as PackedScene).instantiate()
	var records: Array[Dictionary] = []
	_collect_tile_records(level, records)
	_collect_environment_scene_records(level, records)
	var groups := {}
	for record in records:
		var visual_hash := String(record.get("hash", ""))
		if visual_hash.is_empty():
			continue
		var matches: Array = groups.get(visual_hash, [])
		matches.append(record)
		groups[visual_hash] = matches
	var duplicates: Array[Dictionary] = []
	for visual_hash in groups:
		var matches: Array = groups[visual_hash]
		if matches.size() < 2:
			continue
		var kinds := {}
		var layers := {}
		for match in matches:
			kinds[String(match.get("kind", ""))] = true
			if match.has("layer"):
				layers[String(match.layer)] = true
		if kinds.size() > 1 or layers.size() > 1:
			duplicates.append({"hash": visual_hash, "matches": matches})
	duplicates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return JSON.stringify(a.matches) < JSON.stringify(b.matches)
	)
	print("WORLDGEN_VISUAL_DUPLICATES=" + JSON.stringify(duplicates))
	print("WORLDGEN_VISUAL_AUDIT records=%d duplicate_groups=%d" % [records.size(), duplicates.size()])
	level.free()
	quit(0 if duplicates.is_empty() else 1)

func _collect_tile_records(level: Node, records: Array[Dictionary]) -> void:
	for candidate in level.find_children("*", "TileMapLayer", true, false):
		var layer := candidate as TileMapLayer
		if layer == null or layer.tile_set == null:
			continue
		var tile_set := layer.tile_set
		for source_index in range(tile_set.get_source_count()):
			var source_id := tile_set.get_source_id(source_index)
			var source := tile_set.get_source(source_id) as TileSetAtlasSource
			if source == null or source.texture == null:
				continue
			var texture_image := source.texture.get_image()
			if texture_image == null or texture_image.is_empty():
				continue
			for tile_index in range(source.get_tiles_count()):
				var atlas := source.get_tile_id(tile_index)
				var region := source.get_tile_texture_region(atlas, 0)
				var image := texture_image.get_region(region)
				var visual_hash := _visible_pixel_hash(image)
				if visual_hash.is_empty():
					continue
				records.append({
					"kind": "tile",
					"layer": _local_path(layer, level),
					"source_id": source_id,
					"atlas": "%d,%d" % [atlas.x, atlas.y],
					"texture": source.texture.resource_path,
					"hash": visual_hash,
				})

func _collect_environment_scene_records(level: Node, records: Array[Dictionary]) -> void:
	var environment := level.get_node("WorldGeneration/EnvironmentGenerationPass") as EnvironmentGenerationPass
	if environment == null or environment.profile == null:
		return
	var visited := {}
	for entry in environment.profile.entries:
		if entry == null or not entry.enabled or entry.kind != EnvironmentEntry.Kind.SCENE or entry.scene == null:
			continue
		var scene_path := entry.scene.resource_path
		if visited.has(scene_path):
			continue
		visited[scene_path] = true
		var instance := entry.scene.instantiate()
		var sprites: Array[Sprite2D] = []
		if instance is Sprite2D:
			sprites.append(instance as Sprite2D)
		for candidate in instance.find_children("*", "Sprite2D", true, false):
			sprites.append(candidate as Sprite2D)
		for sprite in sprites:
			if sprite == null or not sprite.visible or sprite.texture == null:
				continue
			var image := sprite.texture.get_image()
			var visual_hash := _visible_pixel_hash(image)
			if visual_hash.is_empty():
				continue
			records.append({
				"kind": "scene_sprite",
				"entry_id": entry.entry_id,
				"scene": scene_path,
				"node": _local_path(sprite, instance),
				"texture": sprite.texture.resource_path,
				"hash": visual_hash,
			})
		instance.free()

func _visible_pixel_hash(source: Image) -> String:
	if source == null or source.is_empty():
		return ""
	var image := source.duplicate()
	image.convert(Image.FORMAT_RGBA8)
	var used: Rect2i = image.get_used_rect()
	if used.size == Vector2i.ZERO:
		return ""
	image = image.get_region(used)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color: Color = image.get_pixel(x, y)
			if color.a <= 0.001:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(image.save_png_to_buffer())
	return context.finish().hex_encode()

func _local_path(node: Node, root: Node) -> String:
	var parts: Array[String] = []
	var current := node
	while current != null and current != root:
		parts.push_front(current.name)
		current = current.get_parent()
	return "/".join(parts)
