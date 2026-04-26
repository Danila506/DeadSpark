extends Node2D


@export_category("World Bounds")
@export var player_path: NodePath
@export var world_bounds_generator_path: NodePath = NodePath("ChunkWorldGenerator")
@export var world_bounds_thickness_px: float = 128.0
@export var world_bounds_collision_layer: int = 1
@export var world_bounds_collision_mask: int = 0

@export_category("Visual Mood")
@export var world_mood_enabled: bool = true
@export var world_mood_color: Color = Color(0.62, 0.67, 0.78, 1.0)
@export var world_mood_targets: Array[NodePath] = [
	NodePath("SnowLayer"),
	NodePath("WoodLayer"),
	NodePath("RoadLayer"),
	NodePath("RoadCustomLayer"),
	NodePath("Y-Sort_Objects"),
	NodePath("Snowfall")
]

var _player: Node2D


func _ready() -> void:
	_apply_world_mood_grade()
	_player = _resolve_player()
	_setup_world_bounds()


func _resolve_player() -> Node2D:
	if player_path != NodePath(""):
		return get_node_or_null(player_path) as Node2D

	var from_group := get_tree().get_first_node_in_group("player")
	return from_group as Node2D


func _apply_world_mood_grade() -> void:
	if not world_mood_enabled:
		return

	for target_path in world_mood_targets:
		if target_path == NodePath(""):
			continue
		var node: Node = get_node_or_null(target_path)
		if node == null or not (node is CanvasItem):
			continue
		(node as CanvasItem).modulate = world_mood_color


func _setup_world_bounds() -> void:
	var generator := get_node_or_null(world_bounds_generator_path)
	if generator == null or not generator.has_method("get_world_bounds_rect"):
		return

	var bounds: Rect2 = generator.call("get_world_bounds_rect")
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return

	_apply_camera_limits(bounds)
	_create_world_boundaries(bounds)


func _apply_camera_limits(bounds: Rect2) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = _resolve_player()
		if _player == null:
			return

	var camera := _player.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return

	camera.limit_enabled = true
	camera.limit_left = int(floor(bounds.position.x))
	camera.limit_top = int(floor(bounds.position.y))
	camera.limit_right = int(ceil(bounds.end.x))
	camera.limit_bottom = int(ceil(bounds.end.y))


func _create_world_boundaries(bounds: Rect2) -> void:
	var existing := get_node_or_null("WorldBounds")
	if existing != null:
		existing.queue_free()

	var root := Node2D.new()
	root.name = "WorldBounds"
	add_child(root)

	var thickness := maxf(16.0, world_bounds_thickness_px)
	var half := thickness * 0.5
	var min_x := bounds.position.x
	var min_y := bounds.position.y
	var max_x := bounds.end.x
	var max_y := bounds.end.y
	var mid_x := (min_x + max_x) * 0.5
	var mid_y := (min_y + max_y) * 0.5
	var vertical_size := Vector2(thickness, bounds.size.y + thickness * 2.0)
	var horizontal_size := Vector2(bounds.size.x + thickness * 2.0, thickness)

	_add_world_boundary(root, "WorldBoundLeft", Vector2(min_x - half, mid_y), vertical_size)
	_add_world_boundary(root, "WorldBoundRight", Vector2(max_x + half, mid_y), vertical_size)
	_add_world_boundary(root, "WorldBoundTop", Vector2(mid_x, min_y - half), horizontal_size)
	_add_world_boundary(root, "WorldBoundBottom", Vector2(mid_x, max_y + half), horizontal_size)


func _add_world_boundary(parent: Node, body_name: String, body_pos: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.name = body_name
	body.position = body_pos
	body.collision_layer = world_bounds_collision_layer
	body.collision_mask = world_bounds_collision_mask

	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	shape_node.shape = shape

	body.add_child(shape_node)
	parent.add_child(body)
