extends Node2D


@export_category("Cursor")
@export var default_cursor_texture: Texture2D
@export var aim_cursor_texture: Texture2D
@export var cursor_hotspot: Vector2 = Vector2(16, 16)

@export_category("World Bounds")
@export var world_bounds_generator_path: NodePath = NodePath("ChunkWorldGenerator")
@export var world_bounds_thickness_px: float = 128.0
@export var world_bounds_collision_layer: int = 1
@export var world_bounds_collision_mask: int = 0

@export_category("Combat")
@export var player_path: NodePath
@export var bullet_scene: PackedScene
@export var muzzle_marker_group: StringName = &"muzzle"
@export var muzzle_fallback_names: Array[StringName] = [&"Muzzle", &"GunMuzzle", &"BulletSpawn", &"FirePoint"]
@export var fire_cooldown_sec: float = 0.12
@export var bullet_speed: float = 1200.0
@export var bullet_lifetime_sec: float = 2.0
@export var projectile_layer: int = 2
@export var projectile_mask: int = 1

@export_category("Inventory")
@export var left_hand_slot_name: StringName = &"left_hand"
@export var allowed_left_hand_categories: Array[StringName] = [&"food"]
@export var blocked_left_hand_categories: Array[StringName] = [&"weapon", &"clothes"]

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
var _active_muzzle: Node2D
var _fire_cooldown_left: float = 0.0


func _ready() -> void:
	_apply_world_mood_grade()
	_player = _resolve_player()
	_setup_world_bounds()
	_register_left_hand_rule()


func _physics_process(delta: float) -> void:
	if _fire_cooldown_left > 0.0:
		_fire_cooldown_left -= delta


func _resolve_player() -> Node2D:
	if player_path != NodePath(""):
		return get_node_or_null(player_path) as Node2D

	var from_group := get_tree().get_first_node_in_group("player")
	return from_group as Node2D


func _set_mouse_cursor(is_aiming: bool) -> void:
	var texture := aim_cursor_texture if is_aiming and aim_cursor_texture != null else default_cursor_texture
	if texture == null:
		return

	Input.set_custom_mouse_cursor(texture, Input.CURSOR_ARROW, cursor_hotspot)


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


func _update_player_aim(mouse_world: Vector2) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = _resolve_player()
		if _player == null:
			return

	var direction := (mouse_world - _player.global_position).normalized()
	if direction.length_squared() <= 0.0001:
		return

	# Поддержка разных API у Player без хардкода в один метод.
	if _player.has_method("set_aim_direction"):
		_player.call("set_aim_direction", direction)
	elif _player.has_method("set_look_direction"):
		_player.call("set_look_direction", direction)
	elif _player.has_method("update_facing"):
		_player.call("update_facing", direction)
	elif _player.has_method("look_at_point"):
		_player.call("look_at_point", mouse_world)


func _try_shoot(mouse_world: Vector2) -> void:
	if _fire_cooldown_left > 0.0:
		return

	if _player == null or not is_instance_valid(_player):
		_player = _resolve_player()
		if _player == null:
			return

	var origin := _resolve_muzzle_position()
	var direction := (mouse_world - origin).normalized()
	if direction.length_squared() <= 0.0001:
		return

	# Если у игрока есть собственная логика стрельбы/оружия — используем её.
	if _player.has_method("shoot"):
		_player.call("shoot", {
			"origin": origin,
			"direction": direction,
			"speed": bullet_speed,
			"lifetime": bullet_lifetime_sec
		})
	elif bullet_scene != null:
		_spawn_bullet(origin, direction)

	_fire_cooldown_left = fire_cooldown_sec


func _resolve_muzzle_position() -> Vector2:
	if _active_muzzle == null or not is_instance_valid(_active_muzzle):
		_active_muzzle = _find_muzzle_node()

	if _active_muzzle != null:
		return _active_muzzle.global_position

	return _player.global_position


func _find_muzzle_node() -> Node2D:
	for node in get_tree().get_nodes_in_group(muzzle_marker_group):
		if node is Node2D and _player.is_ancestor_of(node):
			return node as Node2D

	for muzzle_name in muzzle_fallback_names:
		var node := _player.find_child(String(muzzle_name), true, false)
		if node is Node2D:
			return node as Node2D

	return null


func _spawn_bullet(origin: Vector2, direction: Vector2) -> void:
	var bullet := bullet_scene.instantiate()
	if bullet == null:
		return

	if bullet is Node2D:
		var bullet_2d := bullet as Node2D
		bullet_2d.global_position = origin
		bullet_2d.rotation = direction.angle()

	if bullet.has_method("initialize"):
		bullet.call("initialize", origin, direction, bullet_speed, bullet_lifetime_sec, projectile_layer, projectile_mask)

	get_tree().current_scene.add_child(bullet)


func _register_left_hand_rule() -> void:
	var inventory_manager := get_node_or_null("/root/InventoryManager")
	if inventory_manager == null:
		return

	# Адаптивная регистрация под разные реализации менеджера инвентаря.
	if inventory_manager.has_method("register_slot_validator"):
		inventory_manager.call("register_slot_validator", left_hand_slot_name, Callable(self, "_can_place_to_left_hand"))
	elif inventory_manager.has_method("set_slot_validator"):
		inventory_manager.call("set_slot_validator", left_hand_slot_name, Callable(self, "_can_place_to_left_hand"))
	elif inventory_manager.has_method("add_slot_rule"):
		inventory_manager.call("add_slot_rule", left_hand_slot_name, Callable(self, "_can_place_to_left_hand"))
	else:
		inventory_manager.set_meta("left_hand_validator", Callable(self, "_can_place_to_left_hand"))


func _can_place_to_left_hand(item: Variant, _slot: Variant = null) -> bool:
	var category := _extract_item_category(item)
	if category == StringName():
		return false

	if category in blocked_left_hand_categories:
		return false

	return category in allowed_left_hand_categories


func _extract_item_category(item: Variant) -> StringName:
	if item == null:
		return StringName()

	if item is Resource:
		if item.has_method("get_category"):
			return StringName(item.call("get_category"))
		if "category" in item:
			return StringName(item.category)
		if "item_type" in item:
			return StringName(item.item_type)

	if item is Dictionary:
		if item.has("category"):
			return StringName(item["category"])
		if item.has("item_type"):
			return StringName(item["item_type"])

	if item is Object:
		if item.has_method("get_category"):
			return StringName(item.call("get_category"))
		if item.has_method("get_item_type"):
			return StringName(item.call("get_item_type"))

	return StringName()


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
