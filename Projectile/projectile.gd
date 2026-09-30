extends Area2D

const DamageZones = preload("res://Enemies/AI/damage_zones.gd")

@export var speed: float = 1200.0
@export var lifetime_sec: float = 2.0
@export var damage: float = 15.0
@export var collision_mask_override: int = 1
@export var collision_layer_override: int = 2
@export var pass_through_tilemap_layers: bool = false

var _direction: Vector2 = Vector2.RIGHT
var _start_position: Vector2 = Vector2.ZERO
var _max_distance: float = 420.0
var _shooter: Node = null
var _lifetime_left: float = 0.0
var _released: bool = false
func _ready() -> void:
	_lifetime_left = lifetime_sec
	_disable_physics_collision()


func _physics_process(delta: float) -> void:
	if _released:
		return
	if _lifetime_left > 0.0:
		_lifetime_left -= delta
		if _lifetime_left <= 0.0:
			_release_projectile()
			return

	var from_pos: Vector2 = global_position
	var to_pos: Vector2 = from_pos + _direction * speed * delta
	var hit: Dictionary = _raycast_to_position(from_pos, to_pos)
	if not hit.is_empty() and _handle_raycast_hit(hit):
		return
	global_position = to_pos

	if _max_distance > 0.0 and _start_position.distance_to(global_position) >= _max_distance:
		_release_projectile()


func initialize(
	origin: Vector2,
	direction: Vector2,
	new_speed: float,
	new_lifetime_sec: float,
	layer: int,
	mask: int,
	new_damage: float = -1.0,
	new_max_distance: float = 420.0,
	shooter: Node = null
) -> void:
	global_position = origin
	_start_position = origin
	_direction = direction.normalized()
	speed = new_speed
	lifetime_sec = new_lifetime_sec
	_lifetime_left = new_lifetime_sec
	_max_distance = new_max_distance
	_shooter = shooter
	if new_damage >= 0.0:
		damage = new_damage
	collision_layer_override = layer
	collision_mask_override = mask
	rotation = _direction.angle()
	_released = false
	_disable_physics_collision()
	visible = true
	set_physics_process(true)


func setup(direction: Vector2, new_damage: float, new_speed: float) -> void:
	_direction = direction.normalized()
	_start_position = global_position
	damage = new_damage
	speed = new_speed
	_max_distance = 420.0
	_lifetime_left = lifetime_sec
	rotation = _direction.angle()
	_released = false
	_disable_physics_collision()
	visible = true
	set_physics_process(true)


func _on_body_entered(body: Node) -> void:
	return
	if _released:
		return
	if body == _shooter:
		return
	if _is_friendly_target(body):
		return
	if _should_ignore_collision(body):
		return

	var hit_context: Dictionary = _build_hit_context_for_body_hit()
	_apply_damage_to_target(body, hit_context)
	_release_projectile()


func _on_area_entered(area: Area2D) -> void:
	return
	if _released:
		return
	if area == null:
		return
	if not _is_damage_hitbox_area(area):
		return

	var target: Node = _resolve_damage_target_from_area(area)
	if target == null:
		return
	if target == _shooter:
		return
	if _is_friendly_target(target):
		return
	if _should_ignore_collision(target):
		return

	var hit_context: Dictionary = _build_hit_context_for_area_hit(area)
	_apply_damage_to_target(target, hit_context)
	_release_projectile()


func _is_damage_hitbox_area(area: Area2D) -> bool:
	if area == null:
		return false
	if area.is_in_group("damage_hitbox"):
		return true
	if area.has_meta(&"damage_zone"):
		return true
	return area.name == "HitboxArea" or area.name == "Hurtbox"


func _resolve_damage_target_from_area(area: Area2D) -> Node:
	var current: Node = area
	while current != null:
		if current == _shooter:
			return null
		if current.has_method("take_damage_from") or current.has_method("take_damage"):
			return current
		current = current.get_parent()
	return null


func _apply_damage_to_target(target: Node, hit_context: Dictionary) -> void:
	if target == null:
		return
	if multiplayer != null and multiplayer.multiplayer_peer != null:
		if NetworkManager != null and not NetworkManager.is_server():
			return
	if _is_friendly_target(target):
		return
	if target.has_method("take_damage_from"):
		target.call("take_damage_from", damage, _shooter, hit_context)
	elif target.has_method("take_damage"):
		target.call("take_damage", damage)


func _is_friendly_target(target: Node) -> bool:
	if target == null:
		return false
	var target_bandit: Node = _find_group_owner(target, &"bandit")
	if target_bandit == null:
		return false
	return _shooter == null or _find_group_owner(_shooter, &"bandit") != null


func _find_group_owner(node: Node, group_name: StringName) -> Node:
	var candidate: Node = node
	while candidate != null:
		if candidate.is_in_group(group_name):
			return candidate
		candidate = candidate.get_parent()
	return null


func _build_hit_context_for_body_hit() -> Dictionary:
	var hit_context: Dictionary = {
		"hit_position": global_position,
		"hitbox_type": String(DamageZones.ZONE_BODY),
		"damage_zone": String(DamageZones.ZONE_BODY),
		"projectile_direction": _direction
	}
	if _shooter is Node2D:
		hit_context["source_position"] = (_shooter as Node2D).global_position
	return hit_context


func _build_hit_context_for_area_hit(hit_area: Area2D) -> Dictionary:
	var zone: StringName = DamageZones.resolve_zone_from_area(hit_area)
	var hit_context: Dictionary = {
		"hit_position": global_position,
		"hit_area_name": hit_area.name,
		"hitbox_type": String(zone),
		"damage_zone": String(zone),
		"projectile_direction": _direction
	}
	if _shooter is Node2D:
		hit_context["source_position"] = (_shooter as Node2D).global_position
	return hit_context


func _should_ignore_collision(body: Node) -> bool:
	if body == null:
		return false
	if _is_dead_target(body):
		return true

	if body.is_in_group("bullet_passthrough"):
		return true

	if pass_through_tilemap_layers and body is TileMapLayer:
		return true
	if _node_should_not_block_bullets(body):
		return true

	var parent: Node = body.get_parent()
	if parent != null and _is_dead_target(parent):
		return true
	if parent != null and parent.is_in_group("bullet_passthrough"):
		return true
	if parent != null and _node_should_not_block_bullets(parent):
		return true

	return false


func _is_dead_target(node: Node) -> bool:
	if node == null:
		return false

	# Безопасно поддерживаем оба варианта API цели:
	# 1) метод is_dead() -> bool
	# 2) поле is_dead: bool
	if node.has_method("is_dead"):
		var method_result: Variant = node.call("is_dead")
		return typeof(method_result) == TYPE_BOOL and method_result

	if "is_dead" in node:
		var field_value: Variant = node.get("is_dead")
		return typeof(field_value) == TYPE_BOOL and field_value

	return false


func _node_should_not_block_bullets(node: Node) -> bool:
	if node == null:
		return false

	var name_lower: String = node.name.to_lower()
	return (
		name_lower.contains("bush")
		or name_lower.contains("куст")
		or name_lower.contains("tree")
		or name_lower.contains("дерев")
		or name_lower.contains("stone")
		or name_lower.contains("кам")
		or name_lower.contains("deadwood")
	)


func _disable_physics_collision() -> void:
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false


func _raycast_to_position(from_pos: Vector2, to_pos: Vector2) -> Dictionary:
	var world := get_world_2d()
	if world == null:
		return {}
	var exclude: Array[RID] = [get_rid()]
	if is_instance_valid(_shooter) and _shooter is CollisionObject2D:
		exclude.append((_shooter as CollisionObject2D).get_rid())

	var world_query := PhysicsRayQueryParameters2D.create(from_pos, to_pos, collision_mask_override)
	world_query.collide_with_bodies = true
	world_query.collide_with_areas = true
	world_query.exclude = exclude
	var world_hit: Dictionary = world.direct_space_state.intersect_ray(world_query)

	var hurtbox_query := PhysicsRayQueryParameters2D.create(from_pos, to_pos, DamageZones.HURTBOX_COLLISION_LAYER)
	hurtbox_query.collide_with_bodies = false
	hurtbox_query.collide_with_areas = true
	hurtbox_query.exclude = exclude
	var hurtbox_hit: Dictionary = world.direct_space_state.intersect_ray(hurtbox_query)
	if hurtbox_hit.is_empty():
		return world_hit
	if world_hit.is_empty():
		return hurtbox_hit
	var world_distance_sq: float = from_pos.distance_squared_to(world_hit.get("position", to_pos))
	var hurtbox_distance_sq: float = from_pos.distance_squared_to(hurtbox_hit.get("position", to_pos))
	return hurtbox_hit if hurtbox_distance_sq <= world_distance_sq else world_hit


func _handle_raycast_hit(hit: Dictionary) -> bool:
	var collider: Variant = hit.get("collider")
	if not (collider is Node):
		_release_projectile()
		return true
	var target_node: Node = collider as Node
	if target_node is TileMapLayer and not _tilemap_hit_is_solid(target_node as TileMapLayer, hit):
		return false
	global_position = hit.get("position", global_position)
	if _should_ignore_collision(target_node):
		return false
	if target_node == _shooter:
		return false
	if _is_friendly_target(target_node):
		return false
	if target_node is Area2D and _is_damage_hitbox_area(target_node as Area2D):
		var target: Node = _resolve_damage_target_from_area(target_node as Area2D)
		if target == null:
			_release_projectile()
			return true
		if target == _shooter or _is_friendly_target(target) or _should_ignore_collision(target):
			return false
		var hit_context: Dictionary = _build_hit_context_for_area_hit(target_node as Area2D)
		_apply_damage_to_target(target, hit_context)
		_release_projectile()
		return true
	# Actors with an explicit damage hitbox receive projectile damage only through
	# that Area2D. Their CharacterBody2D collider remains movement-only.
	if _has_damage_hitbox(target_node):
		_release_projectile()
		return true
	var body_context: Dictionary = _build_hit_context_for_body_hit()
	_apply_damage_to_target(target_node, body_context)
	_release_projectile()
	return true


func _has_damage_hitbox(target: Node) -> bool:
	if target == null:
		return false
	var hurtbox := target.get_node_or_null("Hurtbox") as Area2D
	if hurtbox != null:
		return true
	var hitboxes_root := target.get_node_or_null("HitBoxes")
	if hitboxes_root == null:
		hitboxes_root = target.get_node_or_null("Hitboxes")
	if hitboxes_root != null:
		for child in hitboxes_root.get_children():
			if child is Area2D:
				return true
	return target.get_node_or_null("HitboxArea") is Area2D


func _tilemap_hit_is_solid(tilemap_layer: TileMapLayer, hit: Dictionary) -> bool:
	if tilemap_layer == null:
		return false

	var hit_position: Vector2 = hit.get("position", global_position)
	var hit_cell: Vector2i = tilemap_layer.local_to_map(tilemap_layer.to_local(hit_position))
	if tilemap_layer.get_cell_source_id(hit_cell) == -1:
		return false

	var tile_data: TileData = tilemap_layer.get_cell_tile_data(hit_cell)
	if tile_data == null:
		return false

	var tile_set: TileSet = tilemap_layer.tile_set
	if tile_set == null:
		return false

	var physics_layers_count: int = max(tile_set.get_physics_layers_count(), 1)
	for layer_index in range(physics_layers_count):
		if tile_data.get_collision_polygons_count(layer_index) > 0:
			return true

	return false


func reset_for_pool_reuse() -> void:
	_released = false
	_lifetime_left = lifetime_sec
	_disable_physics_collision()
	visible = true
	set_physics_process(true)


func prepare_for_pool() -> void:
	_released = true
	_shooter = null
	_disable_physics_collision()
	visible = false
	set_physics_process(false)


func _release_projectile() -> void:
	if _released:
		return
	_released = true
	visible = false
	set_physics_process(false)
	if get_node_or_null("/root/ProjectilePool") != null:
		ProjectilePool.call_deferred("release_projectile", self)
	else:
		queue_free()
