extends "res://level.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const NETWORK_PROTOCOL_VERSION: int = 1

var players: Dictionary[int, Node2D] = {}
var _retired_player_nodes: Array[Node2D] = []


func _ready() -> void:
	await super._ready()
	_schedule_smoke_exit_if_requested()
	if NetworkManager == null or multiplayer.multiplayer_peer == null:
		return

	if not NetworkManager.peer_joined.is_connected(_on_peer_joined):
		NetworkManager.peer_joined.connect(_on_peer_joined)
	if not NetworkManager.peer_left.is_connected(_on_peer_left):
		NetworkManager.peer_left.connect(_on_peer_left)
	if not NetworkManager.session_reset.is_connected(_on_session_reset):
		NetworkManager.session_reset.connect(_on_session_reset)
	if not NetworkManager.server_disconnected.is_connected(_on_server_disconnected):
		NetworkManager.server_disconnected.connect(_on_server_disconnected)

	var local_peer_id: int = NetworkManager.get_local_peer_id()
	_register_existing_local_player(local_peer_id)

	if NetworkManager.is_server():
		print("LAN gameplay world initialized as server")
	else:
		print("LAN gameplay world initialized as client")
		rpc_id(1, "rpc_client_ready", local_peer_id, NETWORK_PROTOCOL_VERSION)


func _exit_tree() -> void:
	if NetworkManager != null:
		if NetworkManager.peer_joined.is_connected(_on_peer_joined):
			NetworkManager.peer_joined.disconnect(_on_peer_joined)
		if NetworkManager.peer_left.is_connected(_on_peer_left):
			NetworkManager.peer_left.disconnect(_on_peer_left)
		if NetworkManager.session_reset.is_connected(_on_session_reset):
			NetworkManager.session_reset.disconnect(_on_session_reset)
		if NetworkManager.server_disconnected.is_connected(_on_server_disconnected):
			NetworkManager.server_disconnected.disconnect(_on_server_disconnected)
	_cleanup_spawned_players()


func _register_existing_local_player(local_peer_id: int) -> void:
	var existing_local: Node2D = get_node_or_null("Y-Sort_Objects/Player2") as Node2D
	if existing_local == null:
		push_error("Default level player Player2 not found")
		return

	existing_local.name = "Player_%s" % local_peer_id
	existing_local.set("peer_id", local_peer_id)
	existing_local.set_multiplayer_authority(local_peer_id)
	players[local_peer_id] = existing_local

	_update_local_references(existing_local)
	print("Spawning player peer_id: %d" % local_peer_id)


func _update_local_references(local_player: Node2D) -> void:
	_player = local_player
	player_path = get_path_to(local_player)

	var hud := get_node_or_null("Y-Sort_Objects/HUD")
	if hud != null:
		hud.set("player_path", get_path_to(local_player))

	var controls := get_node_or_null("MobileControls")
	if controls != null:
		controls.set("player_path", get_path_to(local_player))


func _on_peer_joined(peer_id: int) -> void:
	if not NetworkManager.is_server():
		return

	for existing_peer_variant: Variant in players.keys():
		var existing_peer_id: int = int(existing_peer_variant)
		var existing_player: Node2D = players[existing_peer_id]
		if existing_player != null:
			rpc_id(peer_id, "rpc_spawn_player", existing_peer_id, existing_player.global_position)

	var spawn_position: Vector2 = Vector2(100 + players.size() * 48, 100)
	rpc("rpc_spawn_player", peer_id, spawn_position)


func _on_peer_left(peer_id: int) -> void:
	if not NetworkManager.is_server():
		return
	rpc("rpc_remove_player", peer_id)


func _on_session_reset() -> void:
	_cleanup_spawned_players()


func _on_server_disconnected() -> void:
	_cleanup_spawned_players()
	if get_tree() != null:
		get_tree().change_scene_to_file.call_deferred("res://Menu/Menu.tscn")


@rpc("any_peer", "reliable")
func rpc_client_ready(peer_id: int, protocol_version: int) -> void:
	if not NetworkManager.is_server():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	if protocol_version != NETWORK_PROTOCOL_VERSION:
		rpc_id(peer_id, "rpc_protocol_rejected", NETWORK_PROTOCOL_VERSION, protocol_version)
		return
	NetworkManager.mark_peer_world_ready(peer_id)

	for existing_peer_variant: Variant in players.keys():
		var existing_peer_id: int = int(existing_peer_variant)
		var existing_player: Node2D = players[existing_peer_id]
		if existing_player != null:
			rpc_id(peer_id, "rpc_spawn_player", existing_peer_id, existing_player.global_position)


@rpc("authority", "call_local", "reliable")
func rpc_protocol_rejected(expected_version: int, got_version: int) -> void:
	if NetworkManager == null:
		return
	var reason: String = "Protocol mismatch. Host=%d Client=%d" % [expected_version, got_version]
	NetworkManager.reject_connection(reason)


@rpc("authority", "call_local", "reliable")
func rpc_spawn_player(peer_id: int, spawn_position: Vector2) -> void:
	if players.has(peer_id):
		return

	var y_sort_root: Node2D = get_node_or_null("Y-Sort_Objects") as Node2D
	if y_sort_root == null:
		push_error("Y-Sort_Objects not found in level scene")
		return

	print("Spawning player peer_id: %d" % peer_id)
	var player: CharacterBody2D = PLAYER_SCENE.instantiate() as CharacterBody2D
	if player == null:
		push_error("Failed to instantiate network player")
		return

	player.name = "Player_%s" % peer_id
	player.set("peer_id", peer_id)
	player.global_position = spawn_position
	player.set_multiplayer_authority(peer_id)

	y_sort_root.add_child(player)
	players[peer_id] = player

	if peer_id == NetworkManager.get_local_peer_id():
		_update_local_references(player)


@rpc("authority", "call_local", "reliable")
func rpc_remove_player(peer_id: int) -> void:
	if not players.has(peer_id):
		return

	print("Removing player peer_id: %d" % peer_id)
	var player: Node2D = players[peer_id]
	players.erase(peer_id)
	if is_instance_valid(player):
		_soft_remove_player_node(player)


func _soft_remove_player_node(player: Node2D) -> void:
	if player == null or not is_instance_valid(player):
		return
	player.visible = false
	if player.has_method("set_physics_process"):
		player.set_physics_process(false)
	if player.has_method("set_process"):
		player.set_process(false)
	if player is CollisionObject2D:
		var collision_object: CollisionObject2D = player as CollisionObject2D
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
	var collision_shape: CollisionShape2D = player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape != null:
		collision_shape.set_deferred("disabled", true)
	_delayed_free_player(player)


func _delayed_free_player(player: Node2D) -> void:
	if player == null or not is_instance_valid(player):
		return
	if not _retired_player_nodes.has(player):
		_retired_player_nodes.append(player)


func _schedule_smoke_exit_if_requested() -> void:
	var exit_after_sec: float = _get_cli_float_arg("lan-smoke-exit-sec", -1.0)
	if exit_after_sec <= 0.0:
		return
	call_deferred("_smoke_exit_impl", exit_after_sec)


func _smoke_exit_impl(timeout_sec: float) -> void:
	await get_tree().create_timer(timeout_sec).timeout
	get_tree().quit()


func _get_cli_float_arg(key: String, default_value: float) -> float:
	for raw_arg_variant: Variant in OS.get_cmdline_user_args():
		var raw_arg: String = String(raw_arg_variant)
		if not raw_arg.begins_with("--"):
			continue
		var parts: PackedStringArray = raw_arg.substr(2).split("=", false, 1)
		if parts.size() != 2:
			continue
		if parts[0] != key:
			continue
		if not parts[1].is_valid_float():
			return default_value
		return float(parts[1])
	return default_value


func _cleanup_spawned_players() -> void:
	if not players.is_empty():
		var local_peer_id: int = NetworkManager.get_local_peer_id() if NetworkManager != null else 0
		for peer_id_variant: Variant in players.keys():
			var peer_id: int = int(peer_id_variant)
			var player: Node2D = players.get(peer_id, null)
			if player == null or not is_instance_valid(player):
				continue
			if peer_id == local_peer_id:
				continue
			player.queue_free()
		players.clear()
	for retired in _retired_player_nodes:
		if retired != null and is_instance_valid(retired):
			retired.queue_free()
	_retired_player_nodes.clear()
