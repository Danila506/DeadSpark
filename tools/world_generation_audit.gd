extends Node

const LEVEL_SCENE: PackedScene = preload("res://level.tscn")
const FIXED_SEED: int = 424242
const MAX_WAIT_FRAMES: int = 10000
const SETTLE_FRAMES: int = 30

var _level: Node
var _wait_frames: int = 0
var _settled_frames: int = 0
var _tiles_only: bool = false
var _audit_seed: int = FIXED_SEED


func _ready() -> void:
	var user_args := OS.get_cmdline_user_args()
	_tiles_only = user_args.has("--tiles-only")
	for arg in user_args:
		if arg.begins_with("--seed="):
			_audit_seed = int(arg.trim_prefix("--seed="))
	if GameSaveManager != null and GameSaveManager.has_method("set_world_generation_seed"):
		GameSaveManager.set_world_generation_seed(_audit_seed)
	_level = LEVEL_SCENE.instantiate()
	if _tiles_only:
		_disable_object_spawners_before_ready()
	add_child(_level)


func _disable_object_spawners_before_ready() -> void:
	var generation_root := _level.get_node_or_null("WorldGeneration")
	if generation_root == null:
		return
	for source in generation_root.get_children():
		if not source.has_method("has_generation_pending"):
			continue
		if source.has_method("is_world_generation_tile_source"):
			continue
		if source.has_method("_apply_config"):
			var config_variant: Variant = source.get("config")
			if config_variant is Resource:
				var runtime_config := (config_variant as Resource).duplicate(true)
				runtime_config.set("enabled", false)
				source.set("config", runtime_config)
		source.set("enabled", false)


func _process(_delta: float) -> void:
	_wait_frames += 1
	if _wait_frames > MAX_WAIT_FRAMES:
		push_error("World generation audit timed out with pending=%d details=%s" % [
			_count_pending_generation(),
			_pending_generation_details()
		])
		get_tree().quit(1)
		return

	if _count_pending_generation() > 0:
		_settled_frames = 0
		return

	_settled_frames += 1
	if _settled_frames < SETTLE_FRAMES:
		return

	_print_generation_digest()
	get_tree().quit()


func _count_pending_generation() -> int:
	if _level == null:
		return 1
	var generation_root := _level.get_node_or_null("WorldGeneration")
	if generation_root == null:
		return 1
	var pending := 0
	for source in generation_root.get_children():
		if not source.has_method("has_generation_pending"):
			continue
		if source.has_method("get_pending_generation_chunk_count"):
			pending += int(source.call("get_pending_generation_chunk_count"))
		elif bool(source.call("has_generation_pending")):
			pending += 1
	return pending


func _pending_generation_details() -> String:
	if _level == null:
		return "level=null"
	var generation_root := _level.get_node_or_null("WorldGeneration")
	if generation_root == null:
		return "WorldGeneration=null"
	var details: Array[String] = []
	for source in generation_root.get_children():
		if not source.has_method("has_generation_pending") or not bool(source.call("has_generation_pending")):
			continue
		var pending_count := 1
		if source.has_method("get_pending_generation_chunk_count"):
			pending_count = int(source.call("get_pending_generation_chunk_count"))
		details.append("%s:%d" % [source.name, pending_count])
	return ", ".join(details)


func _print_generation_digest() -> void:
	var entries: Array[String] = []
	var tile_count := 0
	for node in _collect_descendants(_level):
		if not (node is TileMapLayer):
			continue
		var layer := node as TileMapLayer
		var layer_entries: Array[String] = []
		var cells: Array[Vector2i] = layer.get_used_cells()
		cells.sort_custom(_compare_cells)
		for cell in cells:
			var tile_entry := "tile|%s|%d,%d|%d|%d,%d|%d" % [
				str(_level.get_path_to(layer)),
				cell.x,
				cell.y,
				layer.get_cell_source_id(cell),
				layer.get_cell_atlas_coords(cell).x,
				layer.get_cell_atlas_coords(cell).y,
				layer.get_cell_alternative_tile(cell)
			]
			entries.append(tile_entry)
			layer_entries.append(tile_entry)
			tile_count += 1
		print("[WORLD_GEN_AUDIT_LAYER] path=%s digest=%s tiles=%d" % [
			str(_level.get_path_to(layer)),
			_digest_entries(layer_entries),
			layer_entries.size()
		])

	var generated_count := 0
	var object_entries_by_scene: Dictionary = {}
	for candidate in get_tree().get_nodes_in_group("generated_world_object"):
		if not (candidate is Node2D):
			continue
		var node := candidate as Node2D
		if node != _level and not _level.is_ancestor_of(node):
			continue
		var scene_path := str(node.get_meta("world_generation_scene_path", ""))
		var generated_position := node.global_position
		var footprint_variant: Variant = node.get_meta("world_generation_footprint_rect", null)
		if footprint_variant is Rect2:
			generated_position = (footprint_variant as Rect2).get_center()
		var object_entry := "object|%s|%s|%.3f,%.3f" % [
			str(node.get_meta("world_generation_id", "")),
			scene_path,
			generated_position.x,
			generated_position.y
		]
		entries.append(object_entry)
		if not object_entries_by_scene.has(scene_path):
			object_entries_by_scene[scene_path] = []
		var scene_entries: Array = object_entries_by_scene[scene_path]
		scene_entries.append(object_entry)
		generated_count += 1

	entries.sort()
	var object_scene_paths: Array = object_entries_by_scene.keys()
	object_scene_paths.sort()
	for scene_path_variant in object_scene_paths:
		var scene_path := str(scene_path_variant)
		var raw_scene_entries: Array = object_entries_by_scene[scene_path]
		var scene_entries: Array[String] = []
		for raw_entry in raw_scene_entries:
			scene_entries.append(str(raw_entry))
		scene_entries.sort()
		print("[WORLD_GEN_AUDIT_OBJECTS] scene=%s digest=%s objects=%d" % [
			scene_path,
			_digest_entries(scene_entries),
			scene_entries.size()
		])
	print("[WORLD_GEN_AUDIT] mode=%s seed=%d digest=%s tiles=%d objects=%d frames=%d" % [
		"tiles" if _tiles_only else "full",
		_audit_seed,
		_digest_entries(entries),
		tile_count,
		generated_count,
		_wait_frames
	])


func _digest_entries(entries: Array[String]) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	for entry in entries:
		hashing.update((entry + "\n").to_utf8_buffer())
	return hashing.finish().hex_encode()


func _collect_descendants(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	if root == null:
		return result
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		result.append(current)
		for child in current.get_children():
			if child is Node:
				stack.append(child as Node)
	return result


func _compare_cells(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
