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


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	if lifetime_sec > 0.0:
		var timer: SceneTreeTimer = get_tree().create_timer(lifetime_sec)
		timer.timeout.connect(queue_free)


func _physics_process(delta: float) -> void:
	var from_pos: Vector2 = global_position
	var to_pos: Vector2 = from_pos + _direction * speed * delta
	var hit: Dictionary = _raycast_to_position(from_pos, to_pos)
	if not hit.is_empty():
		if _handle_raycast_hit(hit):
			return
	global_position = to_pos

	if _max_distance > 0.0 and _start_position.distance_to(global_position) >= _max_distance:
		queue_free()


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
	_max_distance = new_max_distance
	_shooter = shooter
	if new_damage >= 0.0:
		damage = new_damage
	collision_layer_override = layer
	collision_mask_override = mask
	collision_layer = layer
	collision_mask = mask
	rotation = _direction.angle()


func setup(direction: Vector2, new_damage: float, new_speed: float) -> void:
	_direction = direction.normalized()
	_start_position = global_position
	damage = new_damage
	speed = new_speed
	_max_distance = 420.0
	rotation = _direction.angle()


func _on_body_entered(body: Node) -> void:
	if body == _shooter:
		return
	if body.is_in_group("bandit") and (_shooter == null or _shooter.is_in_group("bandit")):
		return
	if _should_ignore_collision(body):
		return

	var hit_context: Dictionary = _build_hit_context_for_body_hit()
	_apply_damage_to_target(body, hit_context)
	queue_free()


func _on_area_entered(area: Area2D) -> void:
	if area == null:
		return
	if not _is_damage_hitbox_area(area):
		return

	var target: Node = _resolve_damage_target_from_area(area)
	if target == null:
		return
	if target == _shooter:
		return
	if _should_ignore_collision(target):
		return

	var hit_context: Dictionary = _build_hit_context_for_area_hit(area)
	_apply_damage_to_target(target, hit_context)
	queue_free()


func _is_damage_hitbox_area(area: Area2D) -> bool:
	if area == null:
		return false
	if area.is_in_group("damage_hitbox"):
		return true
	if area.has_meta(&"damage_zone"):
		return true
	return area.name == "HitboxArea"


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
	if target.has_method("take_damage_from"):
		target.call("take_damage_from", damage, _shooter, hit_context)
	elif target.has_method("take_damage"):
		target.call("take_damage", damage)


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
	if _node_looks_like_bush(body):
		return true

	var parent: Node = body.get_parent()
	if parent != null and _is_dead_target(parent):
		return true
	if parent != null and parent.is_in_group("bullet_passthrough"):
		return true
	if parent != null and _node_looks_like_bush(parent):
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


func _node_looks_like_bush(node: Node) -> bool:
	if node == null:
		return false

	var name_lower: String = node.name.to_lower()
	return name_lower.contains("bush") or name_lower.contains("куст")


func _raycast_to_position(from_pos: Vector2, to_pos: Vector2) -> Dictionary:
	var world := get_world_2d()
	if world == null:
		return {}
	var query := PhysicsRayQueryParameters2D.create(from_pos, to_pos, collision_mask)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	var exclude: Array[RID] = [get_rid()]
	if _shooter is CollisionObject2D:
		exclude.append((_shooter as CollisionObject2D).get_rid())
	query.exclude = exclude
	return world.direct_space_state.intersect_ray(query)


func _handle_raycast_hit(hit: Dictionary) -> bool:
	var collider: Variant = hit.get("collider")
	if not (collider is Node):
		queue_free()
		return true
	var target_node: Node = collider as Node
	global_position = hit.get("position", global_position)
	if _should_ignore_collision(target_node):
		return false
	if target_node == _shooter:
		return false
	if target_node is Area2D and _is_damage_hitbox_area(target_node as Area2D):
		var target: Node = _resolve_damage_target_from_area(target_node as Area2D)
		if target != null and target != _shooter and not _should_ignore_collision(target):
			var hit_context: Dictionary = _build_hit_context_for_area_hit(target_node as Area2D)
			_apply_damage_to_target(target, hit_context)
		queue_free()
		return true
	var body_context: Dictionary = _build_hit_context_for_body_hit()
	_apply_damage_to_target(target_node, body_context)
	queue_free()
	return true
