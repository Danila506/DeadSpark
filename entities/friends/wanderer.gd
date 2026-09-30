extends CharacterBody2D
class_name WandererNPC

signal health_changed(current_health: float, max_health: float)
signal died

const SNAPSHOT_INTERVAL_SEC: float = 0.10
const REMOTE_POSITION_BLEND: float = 0.32
const ARRIVAL_DISTANCE: float = 10.0
const RELATION_ATTACK_PENALTY: int = 40

@export var npc_id: String = "wanderer_main"
@export var config: NPCConfig

@onready var body_sprite: AnimatedSprite2D = $BodySprite
@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
@onready var state_machine: FriendlyNPCStateMachine = $StateMachine
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var health_bar: ProgressBar = $HealthBar

var health: float = 100.0
var spawn_position: Vector2
var facing_direction: Vector2 = Vector2.DOWN
var is_dead: bool = false

var _state_time_left: float = 0.0
var _wander_target: Vector2
var _threat_position: Vector2
var _talking_peer_id: int = 0
var _relationships: Dictionary = {}
var _trade_stock: Array[ItemData] = []
var _rng := RandomNumberGenerator.new()
var _snapshot_time_left: float = 0.0
var _remote_target_position: Vector2
var _remote_velocity: Vector2


func _ready() -> void:
	if config == null:
		config = NPCConfig.new()
	spawn_position = global_position
	health = config.max_health
	_remote_target_position = global_position
	_rng.seed = _build_deterministic_seed()
	add_to_group(&"friendly_npc")
	add_to_group(&"primary_interactable")
	if not get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.connect(_on_tree_node_added)
	_refresh_player_collision_exceptions()
	NPCManager.register_npc(self)
	GameSaveManager.register_persistent_node(self)
	_initialize_trade_stock()
	_update_health_bar()
	state_machine.state_changed.connect(_on_state_changed)
	_enter_idle()


func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.disconnect(_on_tree_node_added)
	if NPCManager != null:
		NPCManager.unregister_npc(self)


func _physics_process(delta: float) -> void:
	if is_dead:
		velocity = Vector2.ZERO
		return
	if _is_networked() and not _is_server_authority():
		_apply_remote_snapshot()
		_update_animation()
		return

	_state_time_left = maxf(_state_time_left - delta, 0.0)
	match state_machine.current_state:
		FriendlyNPCStateMachine.State.IDLE:
			_process_idle()
		FriendlyNPCStateMachine.State.WANDER:
			_process_wander()
		FriendlyNPCStateMachine.State.TALK:
			_process_talk()
		FriendlyNPCStateMachine.State.FLEE:
			_process_flee()

	move_and_slide()
	_update_animation()
	_sync_snapshot(delta)


func get_npc_id() -> String:
	return npc_id.strip_edges()


func get_interaction_distance() -> float:
	return config.interaction_distance


func handle_primary_interaction(interactor: Node) -> bool:
	if is_dead or interactor == null or not interactor.is_in_group(&"player"):
		return false
	return NPCManager.request_interaction(StringName(get_npc_id()), interactor)


func begin_talk(interactor: Node, peer_id: int) -> void:
	if not _is_server_authority() or is_dead:
		return
	_talking_peer_id = peer_id
	if interactor is Node2D:
		face_towards((interactor as Node2D).global_position)
	state_machine.change_state(FriendlyNPCStateMachine.State.TALK, true)
	_state_time_left = 20.0
	velocity = Vector2.ZERO


func end_talk(peer_id: int) -> void:
	if not _is_server_authority():
		return
	if _talking_peer_id != 0 and peer_id != _talking_peer_id:
		return
	_talking_peer_id = 0
	_enter_idle()


func build_dialogue_payload(peer_id: int, action: StringName) -> Dictionary:
	if not _is_server_authority() or is_dead:
		return {}
	var relation := _get_relationship(peer_id)
	var text: String
	var show_stock := false
	match action:
		&"greeting":
			if not bool(relation.get("met", false)):
				relation["met"] = true
				text = config.introduction
			else:
				text = config.familiar_greeting
		&"rumor":
			text = _pick_rumor()
		&"trade":
			text = "Вот что у меня сейчас есть. Обмен станет доступен, когда появится общий контракт валюты или бартера."
			show_stock = true
		&"close":
			end_talk(peer_id)
			return {}
		_:
			return {}
	_relationships[str(peer_id)] = relation
	return {
		"display_name": config.display_name,
		"text": text,
		"relation": int(relation.get("attitude", 0)),
		"show_stock": show_stock,
		"stock": _build_stock_summary(),
	}


func take_damage(amount: float, _hit_direction: StringName = &"") -> void:
	take_damage_from(amount, null)


func take_damage_from(amount: float, source: Node, hit_context: Dictionary = {}) -> void:
	if not _is_server_authority() or is_dead:
		return
	var applied_damage := maxf(amount, 0.0)
	if applied_damage <= 0.0:
		return
	health = maxf(health - applied_damage, 0.0)
	_update_health_bar()
	var attacker_peer := _resolve_source_peer_id(source)
	var relation := _get_relationship(attacker_peer)
	relation["attitude"] = clampi(int(relation.get("attitude", 0)) - RELATION_ATTACK_PENALTY, -100, 100)
	relation["attacked"] = true
	_relationships[str(attacker_peer)] = relation
	_threat_position = _resolve_threat_position(source, hit_context)
	if health <= 0.0:
		_die()
	else:
		_enter_flee()


func face_towards(world_position: Vector2) -> void:
	var direction := global_position.direction_to(world_position)
	if direction.length_squared() > 0.001:
		facing_direction = direction


func get_save_key() -> String:
	return "npc:%s" % get_npc_id()


func get_save_data() -> Dictionary:
	var serialized_stock: Array = []
	for item in _trade_stock:
		serialized_stock.append(GameSaveManager.serialize_item(item))
	return {
		"schema_version": 1,
		"position": {"x": global_position.x, "y": global_position.y},
		"health": health,
		"is_dead": is_dead,
		"facing": {"x": facing_direction.x, "y": facing_direction.y},
		"relationships": _relationships.duplicate(true),
		"trade_stock": serialized_stock,
	}


func apply_save_data(data: Dictionary) -> void:
	var position_data: Variant = data.get("position", {})
	if position_data is Dictionary:
		global_position = Vector2(
			float((position_data as Dictionary).get("x", global_position.x)),
			float((position_data as Dictionary).get("y", global_position.y))
		)
		_remote_target_position = global_position
	health = clampf(float(data.get("health", config.max_health)), 0.0, config.max_health)
	is_dead = bool(data.get("is_dead", false)) or health <= 0.0
	var facing_data: Variant = data.get("facing", {})
	if facing_data is Dictionary:
		facing_direction = Vector2(
			float((facing_data as Dictionary).get("x", 0.0)),
			float((facing_data as Dictionary).get("y", 1.0))
		).normalized()
	var raw_relationships: Variant = data.get("relationships", {})
	if raw_relationships is Dictionary:
		_relationships = (raw_relationships as Dictionary).duplicate(true)
	var raw_stock: Variant = data.get("trade_stock", [])
	if raw_stock is Array and not (raw_stock as Array).is_empty():
		_trade_stock.clear()
		for raw_item in raw_stock as Array:
			var item := GameSaveManager.deserialize_item(raw_item)
			if item != null:
				_trade_stock.append(item)
	_update_health_bar()
	if is_dead:
		_apply_dead_state()
	else:
		_enter_idle()


func _process_idle() -> void:
	var nearby_player := _get_nearest_player(config.notice_player_distance)
	if nearby_player != null:
		velocity = velocity.move_toward(Vector2.ZERO, 600.0 * get_physics_process_delta_time())
		face_towards(nearby_player.global_position)
		_state_time_left = maxf(_state_time_left, 0.35)
		return
	velocity = velocity.move_toward(Vector2.ZERO, 600.0 * get_physics_process_delta_time())
	if _state_time_left <= 0.0:
		_enter_wander()


func _process_wander() -> void:
	var nearby_player := _get_nearest_player(config.notice_player_distance)
	if nearby_player != null:
		face_towards(nearby_player.global_position)
		_enter_idle()
		return
	_move_towards_target(_wander_target, config.wander_speed)
	if global_position.distance_to(_wander_target) <= ARRIVAL_DISTANCE or _state_time_left <= 0.0:
		_enter_idle()


func _process_talk() -> void:
	velocity = velocity.move_toward(Vector2.ZERO, 800.0 * get_physics_process_delta_time())
	var player := _get_player_for_peer(_talking_peer_id)
	if player != null:
		face_towards(player.global_position)
		if global_position.distance_to(player.global_position) > config.interaction_distance * 1.5:
			end_talk(_talking_peer_id)
			return
	if _state_time_left <= 0.0:
		end_talk(_talking_peer_id)


func _process_flee() -> void:
	if _state_time_left <= 0.0:
		_enter_idle()
		return
	_move_towards_target(_wander_target, config.flee_speed)


func _move_towards_target(target: Vector2, speed: float) -> void:
	var next_point := target
	if not navigation_agent.is_navigation_finished() and navigation_agent.is_target_reachable():
		next_point = navigation_agent.get_next_path_position()
	var direction := global_position.direction_to(next_point)
	velocity = velocity.move_toward(direction * speed, 500.0 * get_physics_process_delta_time())
	if velocity.length_squared() > 1.0:
		facing_direction = velocity.normalized()


func _enter_idle() -> void:
	state_machine.change_state(FriendlyNPCStateMachine.State.IDLE)
	_state_time_left = _rng.randf_range(config.idle_time_min, maxf(config.idle_time_max, config.idle_time_min))
	velocity = Vector2.ZERO


func _enter_wander() -> void:
	state_machine.change_state(FriendlyNPCStateMachine.State.WANDER)
	var angle := _rng.randf_range(0.0, TAU)
	var distance := _rng.randf_range(config.wander_radius * 0.25, config.wander_radius)
	_wander_target = spawn_position + Vector2.from_angle(angle) * distance
	_wander_target = _closest_navigation_point(_wander_target)
	navigation_agent.target_position = _wander_target
	_state_time_left = maxf(4.0, distance / maxf(config.wander_speed, 1.0) * 2.0)


func _enter_flee() -> void:
	_talking_peer_id = 0
	state_machine.change_state(FriendlyNPCStateMachine.State.FLEE, true)
	var away := (_global_safe_position() - _threat_position).normalized()
	if away == Vector2.ZERO:
		away = Vector2.from_angle(_rng.randf_range(0.0, TAU))
	_wander_target = _closest_navigation_point(global_position + away * config.flee_distance)
	navigation_agent.target_position = _wander_target
	_state_time_left = config.flee_time


func _closest_navigation_point(candidate: Vector2) -> Vector2:
	var map_rid := navigation_agent.get_navigation_map()
	if map_rid.is_valid() and NavigationServer2D.map_get_iteration_id(map_rid) > 0:
		var closest := NavigationServer2D.map_get_closest_point(map_rid, candidate)
		if closest != Vector2.ZERO or candidate.distance_to(Vector2.ZERO) < 1.0:
			return closest
	return candidate


func _get_nearest_player(max_distance: float) -> Node2D:
	var nearest: Node2D
	var nearest_distance := max_distance
	for candidate in get_tree().get_nodes_in_group(&"player"):
		if not (candidate is Node2D) or not is_instance_valid(candidate):
			continue
		var distance := global_position.distance_to((candidate as Node2D).global_position)
		if distance <= nearest_distance:
			nearest = candidate as Node2D
			nearest_distance = distance
	return nearest


func _refresh_player_collision_exceptions() -> void:
	if get_tree() == null:
		return
	for candidate in get_tree().get_nodes_in_group(&"player"):
		_try_add_player_collision_exception(candidate)


func _on_tree_node_added(node: Node) -> void:
	call_deferred("_try_add_player_collision_exception", node)


func _try_add_player_collision_exception(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not node.is_in_group(&"player") or not (node is PhysicsBody2D):
		return
	add_collision_exception_with(node as PhysicsBody2D)
	(node as PhysicsBody2D).add_collision_exception_with(self)


func _get_player_for_peer(peer_id: int) -> Node2D:
	for candidate in get_tree().get_nodes_in_group(&"player"):
		if not (candidate is Node2D):
			continue
		if "peer_id" in candidate and int(candidate.get("peer_id")) == peer_id:
			return candidate as Node2D
		if not _is_networked() and peer_id == 1:
			return candidate as Node2D
	return null


func _update_animation() -> void:
	if is_dead:
		body_sprite.stop()
		body_sprite.modulate = Color(0.55, 0.55, 0.55, 1.0)
		return
	var moving := velocity.length() > 4.0
	var suffix := _direction_suffix(facing_direction)
	var animation := StringName(suffix if moving else "Idle_%s" % suffix.to_lower())
	if body_sprite.animation != animation:
		body_sprite.play(animation)


func _direction_suffix(direction: Vector2) -> String:
	if absf(direction.x) > absf(direction.y):
		return "Right" if direction.x >= 0.0 else "Left"
	return "Down" if direction.y >= 0.0 else "Up"


func _initialize_trade_stock() -> void:
	if not _trade_stock.is_empty():
		return
	for definition in config.trade_item_definitions:
		if definition == null:
			continue
		var max_count := mini(config.trade_stack_max, maxi(definition.max_stack_size, 1))
		var min_count := mini(config.trade_stack_min, max_count)
		_trade_stock.append(definition.create_instance(_rng.randi_range(min_count, max_count)))


func _build_stock_summary() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in _trade_stock:
		if item == null:
			continue
		result.append({"name": item.item_name, "count": item.stack_count})
	return result


func _pick_rumor() -> String:
	if config.rumor_lines.is_empty():
		return "Пока ничего нового не слышал."
	return config.rumor_lines[_rng.randi_range(0, config.rumor_lines.size() - 1)]


func _get_relationship(peer_id: int) -> Dictionary:
	var key := str(maxi(peer_id, 1))
	var raw: Variant = _relationships.get(key, {})
	if raw is Dictionary:
		return (raw as Dictionary).duplicate(true)
	return {"met": false, "attitude": 0, "attacked": false}


func _resolve_source_peer_id(source: Node) -> int:
	if source != null and "peer_id" in source:
		return maxi(int(source.get("peer_id")), 1)
	return 1


func _resolve_threat_position(source: Node, hit_context: Dictionary) -> Vector2:
	if source is Node2D:
		return (source as Node2D).global_position
	var raw_position: Variant = hit_context.get("source_position", global_position - facing_direction)
	if raw_position is Vector2:
		return raw_position as Vector2
	return global_position - facing_direction


func _die() -> void:
	is_dead = true
	health = 0.0
	_apply_dead_state()
	died.emit()


func _apply_dead_state() -> void:
	velocity = Vector2.ZERO
	collision_shape.set_deferred("disabled", true)
	remove_from_group(&"primary_interactable")
	_update_animation()


func _update_health_bar() -> void:
	health_bar.max_value = config.max_health
	health_bar.value = health
	health_bar.visible = not is_dead and health < config.max_health
	health_changed.emit(health, config.max_health)


func _on_state_changed(_previous_state: FriendlyNPCStateMachine.State, _current_state: FriendlyNPCStateMachine.State) -> void:
	pass


func _sync_snapshot(delta: float) -> void:
	if not _is_networked() or not _is_server_authority():
		return
	_snapshot_time_left -= delta
	if _snapshot_time_left > 0.0:
		return
	_snapshot_time_left = SNAPSHOT_INTERVAL_SEC
	rpc("rpc_sync_wanderer_snapshot", {
		"position": global_position,
		"velocity": velocity,
		"facing": facing_direction,
		"health": health,
		"dead": is_dead,
		"state": state_machine.current_state,
	})


@rpc("authority", "call_remote", "unreliable_ordered")
func rpc_sync_wanderer_snapshot(snapshot: Dictionary) -> void:
	if not _is_networked() or _is_server_authority():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	_remote_target_position = snapshot.get("position", global_position) as Vector2
	_remote_velocity = snapshot.get("velocity", Vector2.ZERO) as Vector2
	facing_direction = snapshot.get("facing", facing_direction) as Vector2
	health = clampf(float(snapshot.get("health", health)), 0.0, config.max_health)
	is_dead = bool(snapshot.get("dead", false))
	var remote_state := clampi(int(snapshot.get("state", 0)), 0, FriendlyNPCStateMachine.State.size() - 1)
	state_machine.change_state(remote_state)
	_update_health_bar()
	if is_dead:
		_apply_dead_state()


func _apply_remote_snapshot() -> void:
	global_position = global_position.lerp(_remote_target_position, REMOTE_POSITION_BLEND)
	velocity = _remote_velocity


func _build_deterministic_seed() -> int:
	var seed_value := int(hash(get_npc_id()))
	if GameSaveManager != null and GameSaveManager.has_method("resolve_world_generation_seed"):
		seed_value = GameSaveManager.resolve_world_generation_seed(seed_value)
	return maxi(abs(seed_value), 1)


func _global_safe_position() -> Vector2:
	return global_position


func _is_networked() -> bool:
	return multiplayer != null and multiplayer.multiplayer_peer != null and NetworkManager != null


func _is_server_authority() -> bool:
	return not _is_networked() or NetworkManager.is_server()
