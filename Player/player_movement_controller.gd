extends RefCounted
class_name PlayerMovementController

const UNSTUCK_SEARCH_RADII: Array[float] = [2.0, 4.0, 6.0, 8.0, 12.0, 16.0, 24.0, 32.0, 48.0, 64.0]
const UNSTUCK_DIRECTION_COUNT: int = 16
const OVERLAP_QUERY_MAX_RESULTS: int = 8
const NON_BLOCKING_BODY_GROUPS: Array[StringName] = [&"player", &"enemy", &"friendly_npc"]

var player
var _collision_shape: CollisionShape2D = null
var _last_safe_global_position: Vector2 = Vector2.ZERO
var _has_last_safe_global_position: bool = false


func _init(owner) -> void:
	player = owner


func movement_loop(delta: float, inventory_root, weapon_controller) -> void:
	if player == null:
		return

	if apply_action_movement_lock(delta):
		return

	if inventory_root != null and inventory_root.is_inventory_open:
		player.velocity = Vector2.ZERO
		player._update_walk_snow_sfx(Vector2.ZERO, delta)
		player.idle()
		move_and_slide_safely()
		return

	var input_vector: Vector2 = Input.get_vector("left", "right", "up", "down")
	player.velocity = input_vector * player.base_move_speed * player._get_current_speed_multiplier()

	if weapon_controller != null and weapon_controller.has_method("sync_aim_state_for_movement"):
		weapon_controller.sync_aim_state_for_movement()

	if weapon_controller != null and weapon_controller.is_in_aim_mode() and weapon_controller.has_weapon_equipped():
		player._update_aim_movement_animation(input_vector)
	else:
		if input_vector == Vector2.ZERO:
			player.idle()
		else:
			player.update_move_animation(input_vector)

	player._apply_current_animation_speed(input_vector == Vector2.ZERO)
	player._update_walk_snow_sfx(input_vector, delta)
	move_and_slide_safely()


func apply_action_movement_lock(delta: float) -> bool:
	if player.action_in_progress and player.action_blocks_movement:
		player.velocity = Vector2.ZERO
		player._update_walk_snow_sfx(Vector2.ZERO, delta)
		if not player._play_action_animation_if_available():
			player.idle()
		move_and_slide_safely()
		return true
	return false


func move_and_slide_safely() -> void:
	if player == null:
		return
	player.move_and_slide()
	resolve_world_overlap()


func resolve_world_overlap() -> bool:
	if player == null or not player.is_inside_tree():
		return false
	var shape := _get_collision_shape()
	if shape == null or shape.disabled or shape.shape == null:
		return false

	var current_position: Vector2 = player.global_position
	if _is_position_clear(current_position):
		_last_safe_global_position = current_position
		_has_last_safe_global_position = true
		return false

	for candidate in _build_unstuck_candidates(current_position):
		if _is_position_clear(candidate):
			_apply_recovered_position(candidate)
			return true

	if _has_last_safe_global_position and _is_position_clear(_last_safe_global_position):
		_apply_recovered_position(_last_safe_global_position)
		return true
	return false


func _get_collision_shape() -> CollisionShape2D:
	if _collision_shape != null and is_instance_valid(_collision_shape):
		return _collision_shape
	_collision_shape = player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	return _collision_shape


func _is_position_clear(candidate_position: Vector2) -> bool:
	var shape := _get_collision_shape()
	if shape == null or shape.shape == null:
		return true
	var world_2d: World2D = player.get_world_2d()
	if world_2d == null:
		return true

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape.shape
	var query_transform: Transform2D = shape.global_transform
	query_transform.origin += candidate_position - player.global_position
	query.transform = query_transform
	query.collision_mask = player.collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = _get_excluded_body_rids()
	return world_2d.direct_space_state.intersect_shape(query, OVERLAP_QUERY_MAX_RESULTS).is_empty()


func _get_excluded_body_rids() -> Array[RID]:
	var excluded: Array[RID] = []
	_append_collision_object_rid(excluded, player)
	if player == null or not is_instance_valid(player) or player.get_tree() == null:
		return excluded

	# CollisionObject2D.get_collision_exceptions() asks PhysicsServer to resolve
	# every stored RID back to an Object. During LAN despawn an exception can
	# briefly reference an already-freed peer body, which makes that API emit an
	# error on every overlap query. Build the same non-blocking set from the live
	# gameplay groups instead; freed nodes are absent from these groups.
	for group_name in NON_BLOCKING_BODY_GROUPS:
		for candidate in player.get_tree().get_nodes_in_group(group_name):
			_append_collision_object_rid(excluded, candidate)
	return excluded


func _append_collision_object_rid(excluded: Array[RID], candidate: Variant) -> void:
	if not (candidate is CollisionObject2D):
		return
	var collision_object := candidate as CollisionObject2D
	if not is_instance_valid(collision_object) or not collision_object.is_inside_tree():
		return
	var rid := collision_object.get_rid()
	if rid.is_valid() and not excluded.has(rid):
		excluded.append(rid)


func _build_unstuck_candidates(origin: Vector2) -> Array[Vector2]:
	var directions: Array[Vector2] = []
	if player.velocity.length_squared() > 0.001:
		directions.append(-player.velocity.normalized())
	for index in range(UNSTUCK_DIRECTION_COUNT):
		var direction := Vector2.RIGHT.rotated(TAU * float(index) / float(UNSTUCK_DIRECTION_COUNT))
		if directions.is_empty() or absf(directions[0].dot(direction)) < 0.999:
			directions.append(direction)

	var candidates: Array[Vector2] = []
	for radius in UNSTUCK_SEARCH_RADII:
		for direction in directions:
			candidates.append(origin + direction * radius)
	return candidates


func _apply_recovered_position(recovered_position: Vector2) -> void:
	player.global_position = recovered_position
	player.velocity = Vector2.ZERO
	player.force_update_transform()
	_last_safe_global_position = recovered_position
	_has_last_safe_global_position = true


func update_stealth_state(action_name: StringName, base_noise_level: float, stealth_noise_multiplier: float) -> Dictionary:
	var is_stealth: bool = Input.is_action_pressed(action_name)
	var noise_multiplier: float = clamp(stealth_noise_multiplier, 0.05, 1.0) if is_stealth else 1.0
	return {
		"is_stealth": is_stealth,
		"current_noise_level": base_noise_level * noise_multiplier
	}
