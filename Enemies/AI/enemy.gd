extends CharacterBody2D
class_name EnemyAI

const DamageZones = preload("res://Enemies/AI/damage_zones.gd")

signal state_changed(from_state: StringName, to_state: StringName)
signal animation_requested(animation_name: StringName)
signal attack_performed(target: Node2D, damage: float)
signal died(enemy: EnemyAI)

const STATE_IDLE: StringName = &"IDLE"
const STATE_PATROL: StringName = &"PATROL"
const STATE_SUSPICIOUS: StringName = &"SUSPICIOUS"
const STATE_CHASE: StringName = &"CHASE"
const STATE_ATTACK: StringName = &"ATTACK"
const STATE_SEARCH: StringName = &"SEARCH"
const STATE_RETURN: StringName = &"RETURN"
const STATE_HOUSE_SEARCH: StringName = &"HOUSE_SEARCH"
const STATE_STUN: StringName = &"STUN"
const STATE_DEAD: StringName = &"DEAD"
const INSIDE_HOUSE_GROUP: StringName = &"inside_house"
const INSIDE_HOUSE_ANCHOR_META: StringName = &"inside_house_anchor"
const DEFAULT_LOOT_SLOT_COUNT: int = 4
const DEFAULT_LOOT_MAX_AMMO: int = 10
const DEFAULT_BANDIT_AMMO_POOL: Array[ItemData] = [
	preload("res://Resources/AR_Weapons/akp_52/ammo_boxAkp52.tres"),
	preload("res://Resources/AR_Weapons/kar92l/ammo_boxKar92l.tres"),
	preload("res://Resources/Pistols/chizh_43/ammo_boxChizh.tres")
]
const DEFAULT_BANDIT_FOOD_POOL: Array[ItemData] = [
	preload("res://Resources/Food/apple.tres"),
	preload("res://Resources/Food/tomate.tres"),
	preload("res://Resources/Food/pepper.tres"),
	preload("res://Resources/Food/eggplant.tres"),
	preload("res://Resources/Food/malina.tres")
]
const DEFAULT_BANDIT_MEDICAL_POOL: Array[ItemData] = [
	preload("res://Resources/Medicine/antidote.tres"),
	preload("res://Resources/Medicine/bandage.tres"),
	preload("res://Resources/Medicine/bloodBag.tres"),
	preload("res://Resources/Medicine/healthBox.tres"),
	preload("res://Resources/Medicine/hemostat.tres"),
	preload("res://Resources/Medicine/improvised_splint.tres"),
	preload("res://Resources/Medicine/potassium_iodide.tres"),
	preload("res://Resources/Medicine/restorer.tres"),
	preload("res://Resources/Medicine/saline.tres"),
	preload("res://Resources/Medicine/splint.tres")
]

@export var config: EnemyConfig
@export var player_path: NodePath
@export var patrol_points_root_path: NodePath
@export var player_group: StringName = &"player"
@export var role_group: StringName = &""
@export var use_builtin_animation_adapter: bool = true
@export var loot_interaction_distance: float = 30.0
@export var loot_slot_count: int = DEFAULT_LOOT_SLOT_COUNT
@export var loot_max_ammo_per_slot: int = DEFAULT_LOOT_MAX_AMMO
@export var loot_include_ammo: bool = true
@export var loot_include_food: bool = false
@export var loot_include_medical: bool = false
@export var loot_ammo_pool: Array[ItemData] = DEFAULT_BANDIT_AMMO_POOL.duplicate()
@export var loot_food_pool: Array[ItemData] = DEFAULT_BANDIT_FOOD_POOL.duplicate()
@export var loot_medical_pool: Array[ItemData] = DEFAULT_BANDIT_MEDICAL_POOL.duplicate()
@export var hit_blood_frames: SpriteFrames = preload("res://Resources/Effects/Bloody.tres")
@export var hit_blood_animation_names: Array[String] = ["bloodyVariant1", "BloodyVariant2"]
@export var hit_blood_anim_fps: float = 16.0
@export var hit_blood_effect_scale: Vector2 = Vector2(0.9, 0.9)
@export var hit_blood_offset: Vector2 = Vector2(0.0, -10.0)
@export var hit_blood_fly_distance: float = 14.0
@export var hit_blood_fly_duration_sec: float = 0.16
@export var hit_blood_z_index: int = 35
@export var use_directional_death_animation: bool = true
@export_range(0.1, 6.0, 0.05) var head_damage_multiplier: float = 2.0
@export_range(0.1, 6.0, 0.05) var body_damage_multiplier: float = 1.0
@export_range(0.1, 6.0, 0.05) var legs_damage_multiplier: float = 0.6

@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
@onready var state_machine: EnemyStateMachine = $StateMachine
@onready var body_sprite: AnimatedSprite2D = _resolve_body_sprite()
@onready var health_bar_root: Control = get_node_or_null("ActionBarRoot") as Control
@onready var health_bar: TextureProgressBar = get_node_or_null("ActionBarRoot/ActionBarFill") as TextureProgressBar

var health: float = 100
var spawn_position: Vector2 = Vector2.ZERO
var current_target: Node2D = null
var _last_known_target_position: Vector2 = Vector2.ZERO
var _has_last_known_target_position: bool = false
var _pending_noise_position: Vector2 = Vector2.ZERO
var _has_pending_noise: bool = false

var _has_move_target: bool = false
var _move_target_position: Vector2 = Vector2.ZERO
var _move_speed: float = 0.0
var _facing_direction: Vector2 = Vector2.RIGHT
var _path_retry_left: float = 0.0
var _move_stuck_anim_timer: float = 0.0
var _moved_last_frame_distance: float = 0.0
var _obstacle_bypass_target: Vector2 = Vector2.ZERO
var _obstacle_bypass_time_left: float = 0.0

var _attack_cooldown_left: float = 0.0
var _ranged_burst_shots_left: int = 0
var _ranged_burst_pause_left: float = 0.0
var _sensor_tick_left: float = 0.0
var _visible_accum: float = 0.0
var _invisible_accum: float = 0.0
var _target_confirmed: bool = false
var _is_dead: bool = false
var _ally_alert_cooldown_left: float = 0.0

var _patrol_points: Array[Vector2] = []
var _patrol_index: int = 0

var _safe_velocity: Vector2 = Vector2.ZERO
var _safe_velocity_ready: bool = false
var _post_shot_move_direction: Vector2 = Vector2.ZERO
var _post_shot_move_timer: float = 0.0
var _post_shot_stand_timer: float = 0.0
var _house_search_time_left: float = 0.0
var _house_search_wait_timer: float = 0.0
var _house_search_stuck_timer: float = 0.0
var _house_search_last_position: Vector2 = Vector2.ZERO
var _house_search_point_index: int = 0
var _house_search_center: Vector2 = Vector2.ZERO
var _house_search_target: Vector2 = Vector2.ZERO
var _house_search_resolved_for_current_hide: bool = false
var _local_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _loot_slots: Array[ItemData] = []
var _loot_initialized: bool = false
var _nearest_bandit_cache_left: float = 0.0
var _nearest_bandit_cache_point: Vector2 = Vector2.ZERO
var _nearest_bandit_cache_result: bool = false
var _last_lethal_hit_direction: StringName = DamageZones.DIR_DOWN
const MOVE_TARGET_REPATH_FACTOR: float = 1.75


func _ready() -> void:
	if config == null:
		config = EnemyConfig.new()
	_local_rng.seed = (Time.get_ticks_usec() & 0x7fffffff) ^ int(get_instance_id())

	health = config.max_health
	spawn_position = global_position
	_sensor_tick_left = config.sensor_interval_sec
	_register_combat_groups()
	_update_health_bar_ui()
	_setup_damage_hitboxes()

	navigation_agent.target_desired_distance = config.nav_target_desired_distance
	navigation_agent.path_desired_distance = config.nav_path_desired_distance
	navigation_agent.avoidance_enabled = config.use_avoidance
	if config.use_avoidance and not navigation_agent.velocity_computed.is_connected(_on_nav_velocity_computed):
		navigation_agent.velocity_computed.connect(_on_nav_velocity_computed)

	_collect_patrol_points()
	_resolve_player_reference()

	add_to_group("noise_listener")
	if state_machine != null:
		state_machine.setup(self)
		if not state_machine.state_changed.is_connected(_on_state_changed):
			state_machine.state_changed.connect(_on_state_changed)


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	_update_sensors(delta)
	if _is_dead:
		_close_bandit_loot_when_player_is_far()

	if state_machine != null:
		state_machine.physics_update(delta)

	_apply_navigation_movement(delta)
	_enforce_bandit_run_animation()


func _tick_timers(delta: float) -> void:
	_attack_cooldown_left = max(_attack_cooldown_left - delta, 0.0)
	_ranged_burst_pause_left = max(_ranged_burst_pause_left - delta, 0.0)
	_post_shot_move_timer = max(_post_shot_move_timer - delta, 0.0)
	_post_shot_stand_timer = max(_post_shot_stand_timer - delta, 0.0)
	_path_retry_left = max(_path_retry_left - delta, 0.0)
	_obstacle_bypass_time_left = max(_obstacle_bypass_time_left - delta, 0.0)
	_ally_alert_cooldown_left = max(_ally_alert_cooldown_left - delta, 0.0)
	_nearest_bandit_cache_left = max(_nearest_bandit_cache_left - delta, 0.0)


func _update_sensors(delta: float) -> void:
	_sensor_tick_left -= delta
	if _sensor_tick_left > 0.0:
		return
	var sensor_interval: float = _get_sensor_interval_for_distance()
	_sensor_tick_left = sensor_interval

	if current_target == null or not is_instance_valid(current_target):
		_resolve_player_reference()

	var sees_player_now: bool = _can_see_target()
	if sees_player_now:
		_visible_accum += sensor_interval
		_invisible_accum = 0.0
		_last_known_target_position = current_target.global_position
		_has_last_known_target_position = true
	else:
		_invisible_accum += sensor_interval
		_visible_accum = 0.0

	if not _target_confirmed and _visible_accum >= config.detect_confirm_sec:
		_target_confirmed = true
		_alert_allies_about_target(_last_known_target_position)

	if _target_confirmed and _invisible_accum >= config.lose_confirm_sec:
		_target_confirmed = false


func _get_sensor_interval_for_distance() -> float:
	if current_target == null or not is_instance_valid(current_target):
		return max(config.sensor_interval_sec, 0.01)
	var far_interval: float = max(config.sensor_far_interval_sec, config.sensor_interval_sec)
	var distance_to_target: float = global_position.distance_to(current_target.global_position)
	if distance_to_target >= max(config.sensor_far_distance, 0.0):
		return far_interval
	return max(config.sensor_interval_sec, 0.01)


func _can_see_target() -> bool:
	if current_target == null or not is_instance_valid(current_target):
		return false

	var to_target: Vector2 = current_target.global_position - global_position
	if to_target.length() > config.vision_radius:
		return false

	var forward: Vector2 = get_facing_direction()
	var direction_to_target: Vector2 = to_target.normalized()
	var half_fov: float = deg_to_rad(config.vision_fov_deg * 0.5)
	if abs(forward.angle_to(direction_to_target)) > half_fov:
		return false

	return _has_line_of_sight_to(current_target.global_position, current_target)


func _has_line_of_sight_to(target_position: Vector2, target_node: Node = null) -> bool:
	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, target_position)
	query.exclude = [self]
	query.collision_mask = 0xFFFFFFFF

	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	if target_node != null and hit.get("collider", null) == target_node:
		return true
	return false


func _has_attack_line_of_sight() -> bool:
	if current_target == null or not is_instance_valid(current_target):
		return false
	var origin: Vector2 = _resolve_projectile_origin() if is_ranged_enemy() else global_position
	var target_position: Vector2 = current_target.global_position
	var query := PhysicsRayQueryParameters2D.create(origin, target_position)
	query.exclude = [self]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	return hit.get("collider", null) == current_target


func _would_ranged_attack_hit_ally() -> bool:
	if not is_ranged_enemy() or current_target == null or not is_instance_valid(current_target):
		return false
	var origin: Vector2 = _resolve_projectile_origin()
	var target_position: Vector2 = current_target.global_position
	var query := PhysicsRayQueryParameters2D.create(origin, target_position)
	query.exclude = [self]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider: Object = hit.get("collider", null)
	if collider == null or collider == current_target:
		return false
	if collider is Node:
		return _is_ally_node(collider as Node)
	return false


func _is_ally_node(node: Node) -> bool:
	if node == null:
		return false
	var candidate: Node = node
	while candidate != null:
		if candidate == current_target:
			return false
		if is_in_group(&"bandit") and candidate.is_in_group(&"bandit"):
			return true
		if is_in_group(&"wolf") and candidate.is_in_group(&"wolf"):
			return true
		candidate = candidate.get_parent()
	return false


func _apply_navigation_movement(delta: float) -> void:
	if _is_dead:
		_move_stuck_anim_timer = 0.0
		_moved_last_frame_distance = 0.0
		velocity = velocity.move_toward(Vector2.ZERO, config.deceleration * delta)
		move_and_slide()
		return

	if not _has_move_target and not has_active_post_shot_strafe():
		_move_stuck_anim_timer = 0.0
		_moved_last_frame_distance = 0.0
		velocity = velocity.move_toward(Vector2.ZERO, config.deceleration * delta)
		move_and_slide()
		return

	var desired_velocity: Vector2 = Vector2.ZERO
	var effective_target: Vector2 = _get_effective_move_target()
	if _post_shot_stand_timer > 0.0:
		desired_velocity = Vector2.ZERO
	elif _post_shot_move_timer > 0.0:
		desired_velocity = _post_shot_move_direction * max(config.chase_speed * max(config.post_shot_move_speed_ratio, 0.0), config.patrol_speed * 0.3)
	else:
		var has_nav_path: bool = has_reachable_path()
		if has_nav_path and not navigation_agent.is_navigation_finished():
			var next_point: Vector2 = navigation_agent.get_next_path_position()
			var to_next: Vector2 = next_point - global_position
			if to_next.length() <= max(config.nav_path_desired_distance * 0.5, 1.0):
				var to_target: Vector2 = effective_target - global_position
				if to_target.length() > config.nav_target_desired_distance:
					desired_velocity = to_target.normalized() * _move_speed
			else:
				desired_velocity = to_next.normalized() * _move_speed
		else:
			# Fallback: если нав-путь не построен/недоступен, не зависаем.
			# Движемся напрямую к целевой точке (без телепортации, через velocity + move_and_slide).
			var to_target: Vector2 = effective_target - global_position
			if to_target.length() > config.nav_target_desired_distance:
				desired_velocity = to_target.normalized() * _move_speed
			if _path_retry_left <= 0.0:
				navigation_agent.target_position = effective_target
				_path_retry_left = max(config.path_retry_sec, 0.05)

	if config.use_avoidance:
		navigation_agent.velocity = desired_velocity
		if _safe_velocity_ready:
			desired_velocity = _safe_velocity
			_safe_velocity_ready = false

	velocity = velocity.move_toward(desired_velocity, config.acceleration * delta)
	if desired_velocity.length_squared() > 0.01:
		_facing_direction = desired_velocity.normalized()

	var previous_position: Vector2 = global_position
	move_and_slide()
	var moved_distance: float = previous_position.distance_to(global_position)
	_moved_last_frame_distance = moved_distance
	if desired_velocity.length() > 12.0 and moved_distance < 0.12:
		_move_stuck_anim_timer += delta
	else:
		_move_stuck_anim_timer = 0.0
		_try_clear_obstacle_bypass()

	if _has_move_target and _move_stuck_anim_timer >= max(config.obstacle_stuck_repath_sec, 0.05):
		_move_stuck_anim_timer = 0.0
		_start_bypass_around_obstacle()


func _on_nav_velocity_computed(safe_velocity: Vector2) -> void:
	_safe_velocity = safe_velocity
	_safe_velocity_ready = true


func _get_effective_move_target() -> Vector2:
	if _obstacle_bypass_time_left > 0.0:
		return _obstacle_bypass_target
	return _move_target_position


func _try_clear_obstacle_bypass() -> void:
	if _obstacle_bypass_time_left <= 0.0:
		return
	if global_position.distance_to(_obstacle_bypass_target) <= max(config.obstacle_bypass_reach_distance, 1.0):
		_obstacle_bypass_time_left = 0.0
		navigation_agent.target_position = _move_target_position
		_path_retry_left = max(config.path_retry_sec, 0.05)


func _start_bypass_around_obstacle() -> void:
	if not _has_move_target:
		return

	var to_target: Vector2 = (_move_target_position - global_position).normalized()
	if to_target == Vector2.ZERO:
		return

	var left: Vector2 = Vector2(-to_target.y, to_target.x)
	var right: Vector2 = -left
	var probe_distance: float = max(config.obstacle_bypass_probe_distance, 8.0)
	var forward_bias: float = max(config.obstacle_bypass_forward_bias, 0.0)
	var left_point: Vector2 = global_position + left * probe_distance + to_target * forward_bias
	var right_point: Vector2 = global_position + right * probe_distance + to_target * forward_bias
	var left_clear: bool = _has_clear_path_to_point(left_point)
	var right_clear: bool = _has_clear_path_to_point(right_point)

	if left_clear and right_clear:
		_obstacle_bypass_target = left_point if _local_rng.randf() < 0.5 else right_point
	elif left_clear:
		_obstacle_bypass_target = left_point
	elif right_clear:
		_obstacle_bypass_target = right_point
	else:
		_obstacle_bypass_target = left_point if _local_rng.randf() < 0.5 else right_point

	_obstacle_bypass_time_left = max(config.obstacle_bypass_hold_sec, 0.12)
	navigation_agent.target_position = _obstacle_bypass_target
	_path_retry_left = max(config.path_retry_sec, 0.05)


func move_to(world_position: Vector2, speed: float) -> void:
	_has_move_target = true
	_move_target_position = world_position
	_move_speed = max(speed, 0.0)
	_obstacle_bypass_time_left = 0.0
	var repath_distance: float = max(config.nav_path_desired_distance * MOVE_TARGET_REPATH_FACTOR, 2.0)
	if navigation_agent.target_position.distance_to(world_position) >= repath_distance:
		navigation_agent.target_position = world_position


func get_chase_destination() -> Vector2:
	var target: Vector2 = get_target_position()
	if is_ranged_enemy():
		return target

	var to_target: Vector2 = target - global_position
	var distance: float = to_target.length()
	if distance <= 0.001:
		return global_position

	var keep_distance: float = clamp(config.attack_range * 0.72, 8.0, max(config.attack_range - 1.0, 8.0))
	if distance <= keep_distance:
		return global_position

	return target - to_target.normalized() * keep_distance


func stop_move() -> void:
	_has_move_target = false
	_move_speed = 0.0
	_obstacle_bypass_time_left = 0.0
	navigation_agent.target_position = global_position
	_post_shot_move_timer = 0.0
	_post_shot_stand_timer = 0.0
	_post_shot_move_direction = Vector2.ZERO


func is_close_to(point: Vector2, distance_threshold: float) -> bool:
	return global_position.distance_to(point) <= distance_threshold


func has_reachable_path() -> bool:
	if not _has_move_target:
		return false
	if navigation_agent.has_method("is_target_reachable"):
		return bool(navigation_agent.is_target_reachable())
	return not navigation_agent.get_current_navigation_path().is_empty()


func is_navigation_done() -> bool:
	if not _has_move_target:
		return true
	if not has_reachable_path():
		return false
	return navigation_agent.is_navigation_finished()


func should_chase_target() -> bool:
	return _target_confirmed and current_target != null and is_instance_valid(current_target)


func get_target_position() -> Vector2:
	if current_target == null or not is_instance_valid(current_target):
		return _last_known_target_position
	return current_target.global_position


func has_last_known_target_position() -> bool:
	return _has_last_known_target_position


func get_last_known_target_position() -> Vector2:
	return _last_known_target_position


func can_attack_target() -> bool:
	if not should_chase_target():
		return false
	if global_position.distance_to(get_target_position()) > config.attack_range:
		return false
	if config.require_line_of_sight_for_attack and not _has_attack_line_of_sight():
		return false
	if is_ranged_enemy() and config.prevent_friendly_fire and _would_ranged_attack_hit_ally():
		return false
	return true


func should_leave_attack() -> bool:
	if not should_chase_target():
		return true
	var leave_range: float = config.attack_range * config.attack_range_exit_multiplier
	return global_position.distance_to(get_target_position()) > leave_range


func is_attack_ready() -> bool:
	return _attack_cooldown_left <= 0.0


func perform_attack() -> bool:
	if not can_attack_target():
		return false
	if is_ranged_enemy():
		if _ranged_burst_pause_left > 0.0 or not is_attack_ready():
			return false
		if _ranged_burst_shots_left <= 0:
			var min_shots: int = max(config.ranged_burst_min_shots, 1)
			var max_shots: int = max(config.ranged_burst_max_shots, min_shots)
			_ranged_burst_shots_left = randi_range(min_shots, max_shots)
	else:
		if not is_attack_ready():
			return false

	animation_requested.emit(&"attack")
	if config.is_ranged_enemy:
		_fire_ranged_projectile()
		_ranged_burst_shots_left -= 1
		_attack_cooldown_left = max(config.ranged_burst_shot_interval_sec, 0.03)
		if _ranged_burst_shots_left <= 0:
			_ranged_burst_pause_left = max(config.ranged_burst_pause_sec, 0.0)
	else:
		_apply_melee_damage_to_target()
		_attack_cooldown_left = config.attack_cooldown_sec
	attack_performed.emit(current_target, config.attack_damage)
	return true


func request_animation(animation_name: StringName) -> void:
	var resolved_animation: StringName = _resolve_animation_request(animation_name)
	animation_requested.emit(resolved_animation)
	if use_builtin_animation_adapter:
		_play_builtin_animation(resolved_animation)


func get_facing_direction() -> Vector2:
	if _facing_direction.length_squared() <= 0.001:
		return Vector2.RIGHT
	return _facing_direction.normalized()


func face_towards(world_position: Vector2) -> void:
	var to_point: Vector2 = world_position - global_position
	if to_point.length_squared() <= 0.0001:
		return
	_facing_direction = to_point.normalized()


func is_ranged_enemy() -> bool:
	return config != null and config.is_ranged_enemy


func is_too_close_for_ranged() -> bool:
	if not is_ranged_enemy() or not should_chase_target():
		return false
	return global_position.distance_to(get_target_position()) < config.ranged_min_distance


func get_ranged_retreat_point() -> Vector2:
	if not should_chase_target():
		return global_position
	var away: Vector2 = (global_position - get_target_position()).normalized()
	if away == Vector2.ZERO:
		away = -get_facing_direction()
	return global_position + away * config.ranged_retreat_step_distance


func start_post_shot_strafe() -> void:
	if not is_ranged_enemy():
		return
	if not should_chase_target():
		_post_shot_move_timer = 0.0
		_post_shot_stand_timer = 0.0
		_post_shot_move_direction = Vector2.ZERO
		return

	var to_target: Vector2 = (get_target_position() - global_position).normalized()
	if to_target == Vector2.ZERO:
		return

	var side_direction: Vector2 = Vector2(-to_target.y, to_target.x)
	if _local_rng.randf() < 0.5:
		side_direction = -side_direction

	var move_direction: Vector2 = side_direction + to_target * clamp(config.post_shot_forward_bias, -1.0, 1.0)
	if move_direction == Vector2.ZERO:
		move_direction = side_direction
	move_direction = move_direction.normalized()

	var step_distance: float = max(config.chase_speed * max(config.post_shot_move_speed_ratio, 0.0) * 0.45, 14.0)
	var primary_point: Vector2 = global_position + move_direction * step_distance
	if not _has_clear_path_to_point(primary_point):
		var alternative_direction: Vector2 = (-side_direction + to_target * clamp(config.post_shot_forward_bias, -1.0, 1.0)).normalized()
		var alternative_point: Vector2 = global_position + alternative_direction * step_distance
		if _has_clear_path_to_point(alternative_point):
			move_direction = alternative_direction
		else:
			move_direction = Vector2.ZERO

	_post_shot_move_direction = move_direction
	_post_shot_move_timer = _local_rng.randf_range(
		min(config.post_shot_move_duration_min_sec, config.post_shot_move_duration_max_sec),
		max(config.post_shot_move_duration_min_sec, config.post_shot_move_duration_max_sec)
	)
	_post_shot_stand_timer = max(config.post_shot_stand_time_sec, 0.0)


func has_active_post_shot_strafe() -> bool:
	return _post_shot_move_timer > 0.0 or _post_shot_stand_timer > 0.0


func should_start_house_search() -> bool:
	if _is_dead or not is_in_group(&"bandit"):
		return false

	var player_node: Node2D = get_tree().get_first_node_in_group(player_group) as Node2D
	if player_node == null or not is_instance_valid(player_node):
		return false

	if not _is_player_inside_house(player_node):
		if _house_search_resolved_for_current_hide:
			_house_search_resolved_for_current_hide = false
		return false

	if _house_search_resolved_for_current_hide:
		return false
	if _should_keep_current_non_player_target():
		return false

	var center: Vector2 = _resolve_house_search_center(player_node)
	if not _is_nearest_bandit_to_point(center):
		return false

	return true


func build_house_search_enter_data() -> Dictionary:
	var player_node: Node2D = get_tree().get_first_node_in_group(player_group) as Node2D
	return {"center": _resolve_house_search_center(player_node)}


func begin_house_search(data: Dictionary = {}) -> void:
	_house_search_time_left = max(config.house_search_duration_sec, 0.1)
	_house_search_wait_timer = 0.0
	_house_search_stuck_timer = 0.0
	_house_search_point_index = 0
	_house_search_resolved_for_current_hide = false
	_house_search_center = data.get("center", _resolve_house_search_center(get_tree().get_first_node_in_group(player_group) as Node2D))
	_house_search_last_position = global_position
	_pick_new_house_search_point()
	move_to(_house_search_target, config.search_speed)


func update_house_search(delta: float) -> StringName:
	_house_search_time_left = max(_house_search_time_left - delta, 0.0)
	if _house_search_time_left <= 0.0:
		_finish_house_search()
		return STATE_RETURN

	if _house_search_wait_timer > 0.0:
		_house_search_wait_timer = max(_house_search_wait_timer - delta, 0.0)
		stop_move()
		request_animation(&"idle")
		if _house_search_wait_timer <= 0.0:
			_pick_new_house_search_point()
			move_to(_house_search_target, config.search_speed)
			request_animation(&"walk")
		return StringName("")

	if is_close_to(_house_search_target, 8.0):
		_house_search_wait_timer = _local_rng.randf_range(
			min(config.house_search_wait_min_sec, config.house_search_wait_max_sec),
			max(config.house_search_wait_min_sec, config.house_search_wait_max_sec)
		)
		stop_move()
		request_animation(&"idle")
		return StringName("")

	request_animation(&"walk")
	var moved_distance: float = _house_search_last_position.distance_to(global_position)
	if moved_distance < 2.0:
		_house_search_stuck_timer += delta
	else:
		_house_search_stuck_timer = 0.0
		_house_search_last_position = global_position

	if _house_search_stuck_timer >= 0.8:
		_house_search_stuck_timer = 0.0
		_pick_new_house_search_point()
		move_to(_house_search_target, config.search_speed)

	return StringName("")


func is_target_inside_house() -> bool:
	return current_target != null and is_instance_valid(current_target) and _is_player_inside_house(current_target)


func hear_noise(world_position: Vector2, loudness: float = 1.0, _source: Node = null) -> void:
	if _is_dead:
		return

	var hearing_distance: float = config.hearing_radius * max(loudness, 0.0)
	if global_position.distance_to(world_position) > hearing_distance:
		return

	_apply_bandit_hearing_turn(world_position)
	_pending_noise_position = world_position
	_has_pending_noise = true


func on_player_noise_emitted(noise_position: Vector2, noise_radius: float) -> void:
	if _is_dead:
		return
	if global_position.distance_to(noise_position) > max(noise_radius, 0.0):
		return
	_apply_bandit_hearing_turn(noise_position)
	_pending_noise_position = noise_position
	_has_pending_noise = true


func has_pending_noise() -> bool:
	return _has_pending_noise


func consume_pending_noise() -> Vector2:
	var result: Vector2 = _pending_noise_position
	_has_pending_noise = false
	return result


func _setup_damage_hitboxes() -> void:
	var hitboxes: Array[Area2D] = _collect_damage_hitboxes()
	for hitbox_area in hitboxes:
		hitbox_area.monitoring = false
		hitbox_area.monitorable = true
		hitbox_area.collision_layer = 1
		hitbox_area.collision_mask = 0
		if not hitbox_area.is_in_group(&"damage_hitbox"):
			hitbox_area.add_to_group(&"damage_hitbox")
		if not hitbox_area.has_meta(&"damage_zone"):
			hitbox_area.set_meta(&"damage_zone", String(DamageZones.resolve_zone_from_area(hitbox_area)))


func _collect_damage_hitboxes() -> Array[Area2D]:
	var result: Array[Area2D] = []
	var hitboxes_root: Node = get_node_or_null("Hitboxes")
	if hitboxes_root != null:
		for child in hitboxes_root.get_children():
			if child is Area2D:
				result.append(child as Area2D)

	if result.is_empty():
		var legacy_hitbox: Area2D = get_node_or_null("HitboxArea") as Area2D
		if legacy_hitbox != null:
			result.append(legacy_hitbox)
	return result


func apply_damage(amount: float, hit_direction: StringName = StringName("")) -> void:
	if _is_dead:
		return
	if hit_direction != StringName(""):
		_last_lethal_hit_direction = hit_direction
	health = max(health - max(amount, 0.0), 0.0)
	_update_health_bar_ui()
	if health <= 0.0:
		kill(_last_lethal_hit_direction)
	else:
		request_animation(&"hurt")


func take_damage(amount: float, hit_direction: StringName = StringName("")) -> void:
	apply_damage(amount, hit_direction)


func take_damage_from(amount: float, source: Node, hit_context: Dictionary = {}) -> void:
	if _is_dead:
		return
	if source != null and source == self:
		return
	if _should_ignore_damage_from(source):
		return
	var hit_direction: StringName = _resolve_hit_direction(source, hit_context)
	var damage_multiplier: float = _resolve_damage_multiplier(hit_context)
	var final_damage: float = max(amount * damage_multiplier, 0.0)
	_spawn_hit_blood(source)
	apply_damage(final_damage, hit_direction)
	if source is Node2D and not _is_dead:
		current_target = source as Node2D
		_target_confirmed = true
		_last_known_target_position = current_target.global_position
		_has_last_known_target_position = true
		_alert_allies_about_target(_last_known_target_position)
		if state_machine != null and state_machine.get_current_state_name() != STATE_DEAD:
			state_machine.change_state(STATE_CHASE, {}, true)


func handle_primary_interaction(interactor: Node) -> bool:
	if not _is_dead:
		return false
	if not is_in_group(&"bandit"):
		return false
	if interactor == null or not interactor.is_in_group(player_group):
		return false
	if not (interactor is Node2D):
		return false
	var player_node: Node2D = interactor as Node2D
	if global_position.distance_to(player_node.global_position) > max(loot_interaction_distance, 1.0):
		return false

	_ensure_loot_slots()
	var inventory_root: Node = get_tree().get_first_node_in_group("inventory_root")
	if inventory_root == null:
		return false
	if inventory_root.has_method("open_bandit_loot_slots"):
		inventory_root.call("open_bandit_loot_slots", _loot_slots, self)
		return true
	if inventory_root.has_method("open_loot_slots"):
		inventory_root.call("open_loot_slots", _loot_slots)
		return true
	return false


func _should_ignore_damage_from(source: Node) -> bool:
	if source == null:
		return false
	return is_in_group(&"bandit") and source.is_in_group(&"bandit")


func get_hit_direction(from_position: Vector2) -> String:
	return String(DamageZones.resolve_hit_direction_from_positions(global_position, from_position))


func get_death_animation_from_hit_direction(hit_dir: String) -> String:
	var candidates: Array[StringName] = _build_death_candidates_for_direction(hit_dir)
	if body_sprite == null or body_sprite.sprite_frames == null:
		return ""
	for animation_name in candidates:
		if body_sprite.sprite_frames.has_animation(animation_name) and body_sprite.sprite_frames.get_frame_count(animation_name) > 0:
			return String(animation_name)
	return ""


func _build_death_candidates_for_direction(hit_dir: String) -> Array[StringName]:
	var direction_key: String = hit_dir.strip_edges().to_lower()
	if direction_key.is_empty():
		direction_key = _get_facing_dir_key()

	var result: Array[StringName] = []
	if use_directional_death_animation:
		var capitalized_direction: String = _capitalize_dir_key(direction_key)
		result.append(StringName("Die_" + direction_key))
		result.append(StringName("die_" + direction_key))
		result.append(StringName("Death_" + direction_key))
		result.append(StringName("death_" + direction_key))
		result.append(StringName("Die" + capitalized_direction))
		result.append(StringName("die" + capitalized_direction))
		result.append(StringName("Death" + capitalized_direction))
		result.append(StringName("death" + capitalized_direction))
		result.append(StringName(capitalized_direction + "_Die"))
		result.append(StringName(capitalized_direction + "_death"))
	result.append_array([&"Die", &"die", &"Death", &"death"])
	return result


func _resolve_hit_direction(source: Node, hit_context: Dictionary) -> StringName:
	if hit_context.has("source_position") and hit_context.get("source_position") is Vector2:
		return DamageZones.resolve_hit_direction_from_positions(global_position, hit_context.get("source_position"))

	if source is Node2D:
		return DamageZones.resolve_hit_direction_from_positions(global_position, (source as Node2D).global_position)

	if hit_context.has("projectile_direction") and hit_context.get("projectile_direction") is Vector2:
		return DamageZones.resolve_hit_direction_from_vector(hit_context.get("projectile_direction"))

	return StringName(_get_facing_dir_key())


func _resolve_damage_multiplier(hit_context: Dictionary) -> float:
	var damage_zone: StringName = DamageZones.resolve_zone_from_hit_context(hit_context)
	match damage_zone:
		DamageZones.ZONE_HEAD:
			return max(head_damage_multiplier, 0.1)
		DamageZones.ZONE_LEGS:
			return max(legs_damage_multiplier, 0.1)
		_:
			return max(body_damage_multiplier, 0.1)


func _alert_allies_about_target(target_position: Vector2) -> void:
	if _ally_alert_cooldown_left > 0.0:
		return
	_ally_alert_cooldown_left = max(config.ally_alert_cooldown_sec, 0.05)
	get_tree().call_group_flags(
		SceneTree.GROUP_CALL_DEFERRED,
		"enemy",
		"receive_ally_target_report",
		self,
		target_position
	)


func receive_ally_target_report(reporter: Node, target_position: Vector2) -> void:
	if _is_dead or reporter == self:
		return
	if not (reporter is Node2D):
		return
	var reporter_node: Node2D = reporter as Node2D
	if global_position.distance_to(reporter_node.global_position) > max(config.hearing_radius * 1.35, config.vision_radius):
		return
	_last_known_target_position = target_position
	_has_last_known_target_position = true
	if _target_confirmed:
		return
	_pending_noise_position = target_position
	_has_pending_noise = true


func stun(duration_sec: float = -1.0) -> void:
	if _is_dead or state_machine == null:
		return
	var stun_duration: float = config.stun_default_duration_sec if duration_sec <= 0.0 else duration_sec
	state_machine.change_state(STATE_STUN, {"duration_sec": stun_duration}, true)


func kill(hit_direction: StringName = StringName("")) -> void:
	if _is_dead:
		return
	if hit_direction != StringName(""):
		_last_lethal_hit_direction = hit_direction
	_is_dead = true
	stop_move()
	_house_search_time_left = 0.0
	_house_search_wait_timer = 0.0
	_house_search_stuck_timer = 0.0
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	for hitbox_area in _collect_damage_hitboxes():
		hitbox_area.set_deferred("monitorable", false)
		var hitbox_shape: CollisionShape2D = hitbox_area.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if hitbox_shape != null:
			hitbox_shape.set_deferred("disabled", true)
	if health_bar_root != null:
		health_bar_root.visible = false
	request_animation(&"death")

	if state_machine != null:
		state_machine.change_state(STATE_DEAD, {}, true)

	died.emit(self)
	if config.auto_free_after_death:
		get_tree().create_timer(config.death_free_delay_sec).timeout.connect(queue_free)


func is_dead() -> bool:
	return _is_dead


func has_patrol_points() -> bool:
	return not _patrol_points.is_empty()


func get_patrol_point(index: int) -> Vector2:
	if _patrol_points.is_empty():
		return spawn_position
	return _patrol_points[wrapi(index, 0, _patrol_points.size())]


func get_patrol_index() -> int:
	return _patrol_index


func set_patrol_index(index: int) -> void:
	_patrol_index = max(index, 0)


func advance_patrol_index() -> int:
	if _patrol_points.is_empty():
		_patrol_index = 0
		return _patrol_index
	_patrol_index = (_patrol_index + 1) % _patrol_points.size()
	return _patrol_index


func get_return_position() -> Vector2:
	if has_patrol_points():
		return get_patrol_point(_patrol_index)
	return spawn_position


func _has_clear_path_to_point(point: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(global_position, point)
	query.exclude = [get_rid()]
	if current_target is CollisionObject2D:
		var target_collision: CollisionObject2D = current_target as CollisionObject2D
		query.exclude.append(target_collision.get_rid())
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	return hit.is_empty()


func _is_player_inside_house(node: Node) -> bool:
	if node == null:
		return false
	return node.is_in_group(INSIDE_HOUSE_GROUP)


func _should_keep_current_non_player_target() -> bool:
	if current_target == null or not is_instance_valid(current_target):
		return false
	return not current_target.is_in_group(player_group)


func _is_nearest_bandit_to_point(point: Vector2) -> bool:
	var cache_epsilon: float = max(config.nearest_bandit_cache_point_epsilon, 0.0)
	if _nearest_bandit_cache_left > 0.0 and _nearest_bandit_cache_point.distance_to(point) <= cache_epsilon:
		return _nearest_bandit_cache_result

	var nearest_bandit: Node2D = null
	var best_distance: float = INF
	for node in get_tree().get_nodes_in_group(&"bandit"):
		if node == null or not is_instance_valid(node):
			continue
		if not (node is Node2D):
			continue
		if node.has_method("is_dead") and bool(node.call("is_dead")):
			continue
		var candidate: Node2D = node as Node2D
		var candidate_distance: float = candidate.global_position.distance_to(point)
		if candidate_distance < best_distance:
			best_distance = candidate_distance
			nearest_bandit = candidate
	_nearest_bandit_cache_result = nearest_bandit == self
	_nearest_bandit_cache_point = point
	_nearest_bandit_cache_left = max(config.nearest_bandit_cache_sec, 0.05)
	return _nearest_bandit_cache_result


func _resolve_house_search_center(player_node: Node2D) -> Vector2:
	if player_node != null and player_node.has_meta(INSIDE_HOUSE_ANCHOR_META):
		var anchor: Variant = player_node.get_meta(INSIDE_HOUSE_ANCHOR_META)
		if anchor is Vector2:
			return anchor as Vector2
	if player_node != null and is_instance_valid(player_node):
		return player_node.global_position
	return global_position


func _pick_new_house_search_point() -> void:
	var radius: float = max(config.house_search_radius, 24.0)
	var base_angle: float = float(int(get_instance_id()) % 360) * PI / 180.0
	var angle_step: float = PI / 3.0
	var angle_jitter: float = _local_rng.randf_range(-0.45, 0.45)
	var angle: float = base_angle + float(_house_search_point_index) * angle_step + angle_jitter
	_house_search_point_index += 1
	var distance: float = _local_rng.randf_range(radius * 0.65, radius * 1.05)
	_house_search_target = _house_search_center + Vector2.RIGHT.rotated(angle) * distance


func _finish_house_search() -> void:
	if _house_search_resolved_for_current_hide:
		return
	_house_search_time_left = 0.0
	_house_search_wait_timer = 0.0
	_house_search_stuck_timer = 0.0
	_house_search_resolved_for_current_hide = true
	get_tree().call_group(&"bandit", "_command_house_retreat", _house_search_center)


func _command_house_retreat(shared_house_center: Vector2) -> void:
	if _is_dead or not is_in_group(&"bandit"):
		return
	_house_search_time_left = 0.0
	_house_search_wait_timer = 0.0
	_house_search_stuck_timer = 0.0
	_house_search_point_index = 0
	_house_search_resolved_for_current_hide = true
	_house_search_center = shared_house_center
	current_target = null

	var to_house: Vector2 = _house_search_center - global_position
	var away_direction: Vector2 = (-to_house).normalized()
	if away_direction == Vector2.ZERO:
		away_direction = Vector2.RIGHT.rotated(_local_rng.randf() * TAU)
	var angle_jitter: float = deg_to_rad(_local_rng.randf_range(-45.0, 45.0))
	away_direction = away_direction.rotated(angle_jitter).normalized()
	var offset_distance: float = max(config.post_house_patrol_distance, 0.0)
	spawn_position = global_position + away_direction * offset_distance
	stop_move()
	if state_machine != null:
		state_machine.change_state(STATE_PATROL, {}, true)


func _ensure_loot_slots() -> void:
	if _loot_initialized:
		return
	_loot_initialized = true
	_loot_slots.clear()

	var safe_slot_count: int = max(loot_slot_count, 0)
	var safe_max_ammo: int = max(loot_max_ammo_per_slot, 0)
	_loot_slots.resize(safe_slot_count)
	var available_loot_pool: Array[ItemData] = _build_available_loot_pool()
	if safe_slot_count == 0 or available_loot_pool.is_empty():
		return
	if safe_max_ammo <= 0 and loot_include_ammo:
		return

	var filled_slots_target: int = min(_roll_filled_loot_slots_count(), safe_slot_count)
	var free_indices: Array[int] = []
	for i in range(safe_slot_count):
		free_indices.append(i)

	for _i in range(filled_slots_target):
		if free_indices.is_empty():
			break
		var random_free_idx: int = randi_range(0, free_indices.size() - 1)
		var slot_index: int = free_indices[random_free_idx]
		free_indices.remove_at(random_free_idx)

		var template_item: ItemData = available_loot_pool[randi_range(0, available_loot_pool.size() - 1)]
		if template_item == null:
			continue
		var item_instance: ItemData = template_item.create_instance()
		if item_instance.is_ammo_item:
			var ammo_count: int = randi_range(1, safe_max_ammo)
			item_instance.stack_count = min(ammo_count, max(item_instance.max_stack_size, 1))
		else:
			item_instance.stack_count = 1
		_loot_slots[slot_index] = item_instance


func _build_available_loot_pool() -> Array[ItemData]:
	var available_pool: Array[ItemData] = []
	if loot_include_ammo:
		for item in loot_ammo_pool:
			if item != null:
				available_pool.append(item)
	if loot_include_food:
		for item in loot_food_pool:
			if item != null:
				available_pool.append(item)
	if loot_include_medical:
		for item in loot_medical_pool:
			if item != null:
				available_pool.append(item)
	return available_pool


func _roll_filled_loot_slots_count() -> int:
	var roll: int = randi_range(1, 100)
	if roll <= 30:
		return 1
	if roll <= 70:
		return 2
	if roll <= 90:
		return 3
	return 4


func _close_bandit_loot_when_player_is_far() -> void:
	if not is_in_group(&"bandit"):
		return
	var inventory_root: Node = get_tree().get_first_node_in_group("inventory_root")
	if inventory_root == null or not inventory_root.has_method("close_bandit_loot_for"):
		return
	var player_node: Node2D = get_tree().get_first_node_in_group(player_group) as Node2D
	if player_node == null or not is_instance_valid(player_node):
		inventory_root.call("close_bandit_loot_for", self)
		return
	if global_position.distance_to(player_node.global_position) > max(loot_interaction_distance, 1.0):
		inventory_root.call("close_bandit_loot_for", self)


func _collect_patrol_points() -> void:
	_patrol_points.clear()
	if patrol_points_root_path.is_empty():
		return

	var root: Node = get_node_or_null(patrol_points_root_path)
	if root == null:
		return

	for child in root.get_children():
		if child is Node2D:
			_patrol_points.append((child as Node2D).global_position)


func _resolve_player_reference() -> void:
	if not player_path.is_empty():
		var player_node: Node = get_node_or_null(player_path)
		if player_node is Node2D:
			current_target = player_node as Node2D
			return

	var fallback: Node = get_tree().get_first_node_in_group(player_group)
	if fallback is Node2D:
		current_target = fallback as Node2D


func _on_state_changed(from_state: StringName, to_state: StringName) -> void:
	state_changed.emit(from_state, to_state)


func _register_combat_groups() -> void:
	add_to_group("enemy")

	if not role_group.is_empty():
		add_to_group(role_group)
		return

	var name_lower: String = name.to_lower()
	if name_lower.contains("bandit"):
		add_to_group("bandit")
		add_to_group("primary_interactable")
	elif name_lower.contains("wolf"):
		add_to_group("wolf")


func _play_builtin_animation(token: StringName) -> void:
	if body_sprite == null or body_sprite.sprite_frames == null:
		return

	var candidates: Array[StringName] = []
	match token:
		&"idle":
			candidates = _build_idle_candidates()
		&"walk", &"run":
			candidates = _build_move_candidates()
		&"attack":
			candidates = _build_ranged_attack_candidates() if is_ranged_enemy() else _build_attack_candidates()
		&"hurt":
			candidates = [&"hurt", &"hit"]
			candidates.append_array(_build_idle_candidates())
		&"death":
			candidates = _build_death_candidates()
			candidates.append_array(_build_idle_candidates())
		_:
			candidates = [token]
			candidates.append_array(_build_idle_candidates())

	for animation_name in candidates:
		if body_sprite.sprite_frames.has_animation(animation_name) and body_sprite.sprite_frames.get_frame_count(animation_name) > 0:
			_apply_sprite_flip_for_animation(animation_name)
			if token == &"death":
				body_sprite.sprite_frames.set_animation_loop(animation_name, false)
			body_sprite.play(animation_name)
			return


func _get_facing_dir_key() -> String:
	var facing: Vector2 = get_facing_direction()
	if abs(facing.x) > abs(facing.y):
		return String(DamageZones.DIR_RIGHT) if facing.x >= 0.0 else String(DamageZones.DIR_LEFT)
	return String(DamageZones.DIR_DOWN) if facing.y >= 0.0 else String(DamageZones.DIR_UP)


func _capitalize_dir_key(dir_key: String) -> String:
	if dir_key.is_empty():
		return "Down"
	return dir_key.substr(0, 1).to_upper() + dir_key.substr(1)


func _build_idle_candidates() -> Array[StringName]:
	var result: Array[StringName] = []
	for dir_key in _get_direction_fallback_chain():
		result.append(StringName("Idle_" + dir_key))
		result.append(StringName("idle_" + dir_key))
		result.append(StringName("Idle_" + dir_key + "_weapon"))
	return result


func _build_move_candidates() -> Array[StringName]:
	var result: Array[StringName] = []
	for dir_key in _get_direction_fallback_chain():
		result.append(StringName(_capitalize_dir_key(dir_key)))
		result.append(StringName(dir_key))
	return result


func _build_attack_candidates() -> Array[StringName]:
	var result: Array[StringName] = []
	for dir_key in _get_direction_fallback_chain():
		result.append(StringName("attack_" + dir_key))
	result.append_array(_build_idle_candidates())
	return result


func _build_ranged_attack_candidates() -> Array[StringName]:
	var result: Array[StringName] = []
	for dir_key in _get_direction_fallback_chain():
		result.append(StringName("Aim_" + dir_key))
		result.append(StringName("aim_" + dir_key))
	result.append_array(_build_idle_weapon_candidates())
	result.append_array(_build_idle_candidates())
	return result


func _build_death_candidates() -> Array[StringName]:
	var direction_key: String = String(_last_lethal_hit_direction)
	return _build_death_candidates_for_direction(direction_key)


func _build_idle_weapon_candidates() -> Array[StringName]:
	var result: Array[StringName] = []
	for dir_key in _get_direction_fallback_chain():
		result.append(StringName("Idle_" + dir_key + "_weapon"))
		result.append(StringName("idle_" + dir_key + "_weapon"))
	return result


func _get_direction_fallback_chain() -> Array[String]:
	var facing: Vector2 = get_facing_direction()
	if abs(facing.x) > abs(facing.y):
		# Для спрайтов без left/right (как у волка) используем front/down.
		if facing.x >= 0.0:
			return ["right", "left", "front", "down"]
		return ["left", "right", "front", "down"]
	if facing.y < 0.0:
		return ["up"]
	return ["down", "front"]


func _resolve_body_sprite() -> AnimatedSprite2D:
	var sprite: AnimatedSprite2D = get_node_or_null("BodySprite") as AnimatedSprite2D
	if sprite != null:
		return sprite
	return get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D


func _apply_melee_damage_to_target() -> void:
	if current_target == null or not is_instance_valid(current_target):
		return
	if current_target.has_method("take_damage_from"):
		current_target.call("take_damage_from", config.attack_damage, self)
	elif current_target.has_method("take_enemy_damage"):
		current_target.call("take_enemy_damage", config.attack_damage, 0.25, config.attack_damage_type)
	elif current_target.has_method("take_damage"):
		current_target.call("take_damage", config.attack_damage)


func _fire_ranged_projectile() -> void:
	if config.projectile_scene == null or current_target == null or not is_instance_valid(current_target):
		_apply_melee_damage_to_target()
		return

	var projectile: Node = config.projectile_scene.instantiate()
	if projectile == null:
		return

	var root: Node = get_tree().current_scene
	if root == null:
		root = get_parent()
	if root == null:
		return

	root.add_child(projectile)

	var origin: Vector2 = _resolve_projectile_origin()
	var target_pos: Vector2 = current_target.global_position
	var shoot_direction: Vector2 = (target_pos - origin).normalized()
	if shoot_direction == Vector2.ZERO:
		shoot_direction = get_facing_direction()
	shoot_direction = shoot_direction.rotated(deg_to_rad(randf_range(
		-max(config.ranged_spread_degrees, 0.0),
		max(config.ranged_spread_degrees, 0.0)
	))).normalized()

	if projectile is Node2D:
		var projectile_2d: Node2D = projectile as Node2D
		projectile_2d.global_position = origin
		projectile_2d.rotation = shoot_direction.angle()

	var bullet_layer: int = 2
	var bullet_mask: int = 1
	if projectile is CollisionObject2D:
		var collision_object: CollisionObject2D = projectile as CollisionObject2D
		bullet_layer = collision_object.collision_layer
		bullet_mask = collision_object.collision_mask

	if projectile.has_method("initialize"):
		projectile.call(
			"initialize",
			origin,
			shoot_direction,
			config.projectile_speed,
			config.projectile_lifetime_sec,
			bullet_layer,
			bullet_mask,
			config.projectile_damage,
			config.projectile_max_distance,
			self
		)
	elif projectile.has_method("setup"):
		projectile.call("setup", shoot_direction, config.projectile_damage, config.projectile_speed)


func _resolve_projectile_origin() -> Vector2:
	var muzzles: Node = get_node_or_null("Muzzles")
	if muzzles == null:
		return global_position

	var facing: Vector2 = get_facing_direction()
	var marker_name: String = "MuzzleDown"
	if abs(facing.x) > abs(facing.y):
		marker_name = "MuzzleRight" if facing.x >= 0.0 else "MuzzleLeft"
	else:
		marker_name = "MuzzleDown" if facing.y >= 0.0 else "MuzzleUp"

	var marker: Marker2D = muzzles.get_node_or_null(marker_name) as Marker2D
	if marker != null:
		return marker.global_position
	return global_position


func _update_health_bar_ui() -> void:
	if health_bar == null:
		return
	health_bar.max_value = max(config.max_health, 1.0)
	health_bar.value = clamp(health, 0.0, health_bar.max_value)
	if health_bar_root != null:
		health_bar_root.visible = not _is_dead


func _apply_sprite_flip_for_animation(animation_name: StringName) -> void:
	if body_sprite == null:
		return

	var animation_text: String = String(animation_name).to_lower()
	var uses_front_profile: bool = animation_text == "front" or animation_text == "idle_front" or animation_text == "attack_front"
	if not uses_front_profile:
		body_sprite.flip_h = false
		body_sprite.flip_v = false
		return

	var facing: Vector2 = get_facing_direction()
	if abs(facing.x) > abs(facing.y):
		body_sprite.flip_h = facing.x < 0.0
	else:
		body_sprite.flip_h = false
	body_sprite.flip_v = false


func _resolve_animation_request(animation_name: StringName) -> StringName:
	if animation_name == &"run" or animation_name == &"walk":
		if is_in_group(&"bandit") and _did_move_last_frame():
			return &"run"
		if _is_running_in_place() or not _did_move_last_frame():
			return &"idle"
	return animation_name


func _enforce_bandit_run_animation() -> void:
	if _is_dead or not is_in_group(&"bandit"):
		return
	if state_machine == null:
		return
	if state_machine.get_current_state_name() == STATE_DEAD:
		return
	if _did_move_last_frame():
		request_animation(&"run")


func _is_running_in_place() -> bool:
	return _has_move_target and _move_stuck_anim_timer >= 0.18


func _did_move_last_frame() -> bool:
	return _moved_last_frame_distance > 0.08


func _apply_bandit_hearing_turn(noise_position: Vector2) -> void:
	if not is_in_group(&"bandit"):
		return
	face_towards(noise_position)


func _spawn_hit_blood(source: Node) -> void:
	if hit_blood_frames == null:
		return
	var animation_name: String = _resolve_hit_blood_animation_name()
	if animation_name == "":
		return

	var fx_root: Node = get_tree().current_scene
	if fx_root == null:
		fx_root = get_parent()
	if fx_root == null:
		return

	var away_direction: Vector2 = Vector2.RIGHT
	if source is Node2D:
		away_direction = (global_position - (source as Node2D).global_position).normalized()
	if away_direction == Vector2.ZERO:
		away_direction = Vector2.RIGHT

	var blood_sprite: AnimatedSprite2D = AnimatedSprite2D.new()
	blood_sprite.top_level = true
	blood_sprite.sprite_frames = hit_blood_frames
	blood_sprite.animation = animation_name
	blood_sprite.global_position = global_position + hit_blood_offset
	blood_sprite.scale = hit_blood_effect_scale
	blood_sprite.z_index = hit_blood_z_index
	blood_sprite.flip_h = away_direction.x < 0.0
	blood_sprite.flip_v = abs(away_direction.y) > abs(away_direction.x) and away_direction.y < 0.0
	fx_root.add_child(blood_sprite)

	hit_blood_frames.set_animation_loop(animation_name, false)
	hit_blood_frames.set_animation_speed(animation_name, max(hit_blood_anim_fps, 1.0))
	blood_sprite.play(animation_name)

	var fly_target: Vector2 = blood_sprite.global_position + away_direction * max(hit_blood_fly_distance, 0.0)
	var fly_tween: Tween = blood_sprite.create_tween()
	fly_tween.tween_property(
		blood_sprite,
		"global_position",
		fly_target,
		max(hit_blood_fly_duration_sec, 0.05)
	)

	blood_sprite.animation_finished.connect(func() -> void:
		if is_instance_valid(blood_sprite):
			blood_sprite.queue_free()
	)


func _resolve_hit_blood_animation_name() -> String:
	if hit_blood_frames == null:
		return ""

	var available: Array[String] = []
	for name in hit_blood_animation_names:
		var trimmed: String = String(name).strip_edges()
		if trimmed.is_empty():
			continue
		if hit_blood_frames.has_animation(trimmed):
			available.append(trimmed)

	if available.is_empty():
		var all_names: PackedStringArray = hit_blood_frames.get_animation_names()
		if all_names.is_empty():
			return ""
		return String(all_names[0])

	return available[randi() % available.size()]


static func emit_noise(tree: SceneTree, world_position: Vector2, loudness: float = 1.0, source: Node = null) -> void:
	if tree == null:
		return
	tree.call_group_flags(SceneTree.GROUP_CALL_DEFERRED, "noise_listener", "hear_noise", world_position, loudness, source)
