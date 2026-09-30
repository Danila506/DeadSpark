extends "res://level.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const NETWORK_SESSION_COORDINATOR_SCRIPT = preload("res://World/network_session_coordinator.gd")
const NETWORK_SESSION_NODE_SCRIPT = preload("res://World/network_session_node.gd")
const NETWORK_PROTOCOL_VERSION: int = 9
const PLAYER_SPAWNER_NAME: String = "NetworkPlayerSpawner"
const NETWORK_SPAWN_POINTS_PATH: NodePath = ^"NetworkSpawnPoints"
const GENERATED_WORLD_OBJECT_GROUP: StringName = &"generated_world_object"
const WORLD_GENERATION_OBJECT_ID_META: StringName = &"world_generation_id"
const WORLD_GENERATION_SCENE_PATH_META: StringName = &"world_generation_scene_path"
const CLIENT_READY_RETRY_INTERVAL_SEC: float = 0.75
const CLIENT_READY_RETRY_MAX_ATTEMPTS: int = 120
const SERVER_READY_WATCHDOG_TIMEOUT_SEC: float = 6.0
const SERVER_READY_WATCHDOG_RETRY_INTERVAL_SEC: float = 1.2
const SERVER_SPAWN_ACK_RETRY_INTERVAL_SEC: float = 1.0
const SERVER_SPAWN_ACK_TIMEOUT_SEC: float = 8.0
const WORLD_SNAPSHOT_CHUNK_ENTRIES: int = 96
const WORLD_SNAPSHOT_CHUNK_MAX_DECOMPRESSED_BYTES: int = 8 * 1024 * 1024
const WORLD_SNAPSHOT_BUILD_BUDGET_USEC: int = 3000

var players: Dictionary[int, Node2D] = {}
var _retired_player_nodes: Array[Node2D] = []
var _player_spawner: MultiplayerSpawner = null
var _baked_player_anchor: Node2D = null
var _world_snapshot_cache: Dictionary = {}
var _last_world_snapshot_signature: int = 0
var _peer_last_world_snapshot_signature: Dictionary = {}
var _session: NetworkSessionCoordinator = null
var _session_node: NetworkSessionNode = null
var _peer_last_ready_seq: Dictionary = {}
var _peer_spawn_token: Dictionary = {}
var _sent_world_paths: Dictionary = {}
var _acked_world_paths: Dictionary = {}
var _network_world_initialized := false
var _pending_client_ready: Dictionary = {}
var _next_world_snapshot_id: int = 1
var _outgoing_world_snapshots: Dictionary = {}
var _peer_spawn_acknowledged: Dictionary = {}
var _peer_initial_world_snapshot_complete: Dictionary = {}
var _world_snapshot_events: Array[Dictionary] = []
var _draining_world_snapshot_events := false
var _receiving_world_snapshot_id: int = 0
var _receiving_world_snapshot_expected_chunks: int = 0
var _receiving_world_snapshot_expected_entries: int = 0
var _receiving_world_snapshot_next_chunk: int = 0
var _receiving_world_snapshot_seen_ids: Dictionary = {}
var _receiving_world_snapshot_failed_paths: PackedStringArray = PackedStringArray()
var _world_snapshot_build_running: bool = false
var _world_snapshot_building_peers: Dictionary = {}
var _migration_local_player_position := Vector2(-464, 512)
var _handled_player_deaths: Dictionary = {}


func _enter_tree() -> void:
	var shared := Node.new()
	shared.set_script(preload("res://World/network_shared_world.gd"))
	shared.name = "SharedWorld"
	add_child(shared)
	var baked := get_node_or_null("Y-Sort_Objects/Player2")
	if baked != null:
		baked.set("peer_id", -1)
	_session = NETWORK_SESSION_COORDINATOR_SCRIPT.new() as NetworkSessionCoordinator
	_session_node = NETWORK_SESSION_NODE_SCRIPT.new() as NetworkSessionNode
	_session_node.name = "NetworkSessionNode"
	_session_node.configure(NETWORK_PROTOCOL_VERSION, _compute_world_hash())
	_session_node.client_ready_received.connect(_on_client_ready_received)
	_session_node.client_spawn_ack_received.connect(_on_client_spawn_ack_received)
	_session_node.client_ready_acknowledged.connect(_on_client_ready_acknowledged)
	add_child(_session_node)
	_ensure_player_spawner()
	if OS.get_cmdline_user_args().has("--lan-smoke-gameplay=1"):
		var probe := Node.new()
		probe.set_script(load("res://tests/lan_gameplay_probe.gd"))
		probe.name = "GameplaySmokeProbe"
		add_child(probe)
	if OS.get_cmdline_user_args().has("--lan-smoke-shared=1"):
		var shared_probe := Node.new()
		shared_probe.set_script(load("res://tests/lan_shared_state_probe.gd"))
		shared_probe.name = "SharedStateProbe"
		add_child(shared_probe)


func _ready() -> void:
	_configure_local_lan_ui()
	if NetworkManager != null and multiplayer != null and multiplayer.multiplayer_peer != null and not NetworkManager.is_server():
		# Client world state will come from host snapshots; skip expensive local generation preload.
		startup_loading_enabled = false
	await super._ready()
	_schedule_smoke_exit_if_requested()
	_schedule_smoke_pickup_if_requested()
	if NetworkManager == null or multiplayer.multiplayer_peer == null:
		return
	_ensure_player_spawner()

	if not NetworkManager.peer_joined.is_connected(_on_peer_joined):
		NetworkManager.peer_joined.connect(_on_peer_joined)
	if not NetworkManager.peer_left.is_connected(_on_peer_left):
		NetworkManager.peer_left.connect(_on_peer_left)
	if not NetworkManager.session_reset.is_connected(_on_session_reset):
		NetworkManager.session_reset.connect(_on_session_reset)
	if not NetworkManager.server_disconnected.is_connected(_on_server_disconnected):
		NetworkManager.server_disconnected.connect(_on_server_disconnected)
	if not NetworkManager.host_migration_completed.is_connected(_on_host_migration_completed):
		NetworkManager.host_migration_completed.connect(_on_host_migration_completed)
	if not NetworkManager.host_migration_failed.is_connected(_on_host_migration_failed):
		NetworkManager.host_migration_failed.connect(_on_host_migration_failed)

	var local_peer_id: int = NetworkManager.get_local_peer_id()
	_park_baked_level_player()

	if NetworkManager.is_server():
		if NetworkManager.is_dedicated_server():
			print("Dedicated gameplay world initialized as server")
		else:
			print("LAN gameplay world initialized as server")
			_spawn_network_player(local_peer_id, _get_next_network_spawn_position())
		_network_world_initialized = true
		for pending_peer in _pending_client_ready:
			var request: Array = _pending_client_ready[pending_peer]
			if multiplayer.get_peers().has(pending_peer):
				_on_client_ready_received(pending_peer, request[0], request[1], request[2])
		_pending_client_ready.clear()
	else:
		print("LAN gameplay world initialized as client")
		_disable_client_world_generation()
		_clear_local_generated_world_objects()
		if _session_node != null:
			_session_node.send_client_ready()
			_session_node.start_client_ready_flow()


func _configure_local_lan_ui() -> void:
	var ui := get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return
	ui.visible = NetworkManager == null or not NetworkManager.is_dedicated_server()


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
		if NetworkManager.host_migration_completed.is_connected(_on_host_migration_completed):
			NetworkManager.host_migration_completed.disconnect(_on_host_migration_completed)
		if NetworkManager.host_migration_failed.is_connected(_on_host_migration_failed):
			NetworkManager.host_migration_failed.disconnect(_on_host_migration_failed)
	_cleanup_spawned_players()
	_clear_local_generated_world_objects()


func _physics_process(delta: float) -> void:
	if not _network_world_initialized:
		return
	if NetworkManager == null or not NetworkManager.is_server():
		return
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		return
	_update_peer_ready_watchdog(delta)


func _print_enemy_population_smoke_marker() -> void:
	var ids: Array[String] = []
	for node_variant: Variant in get_tree().get_nodes_in_group(GENERATED_WORLD_OBJECT_GROUP):
		var node := node_variant as Node
		if node != null and node.has_meta("population_id"):
			ids.append(String(node.get_meta("population_id")))
	ids.sort()
	var seen := {}
	var duplicates := 0
	var authority_ok := true
	for node_variant: Variant in get_tree().get_nodes_in_group(GENERATED_WORLD_OBJECT_GROUP):
		var node := node_variant as Node
		if node == null or not node.has_meta("population_id"):
			continue
		var population_id := String(node.get_meta("population_id"))
		if seen.has(population_id):
			duplicates += 1
		seen[population_id] = true
		authority_ok = authority_ok and node.get_multiplayer_authority() == 1
	print("LAN_ENEMY_POPULATION peer=%d server=%s count=%d duplicates=%d authority_ok=%s ids=%s" % [NetworkManager.get_local_peer_id(), NetworkManager.is_server(), ids.size(), duplicates, authority_ok, JSON.stringify(ids)])


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


func _park_baked_level_player() -> void:
	_baked_player_anchor = get_node_or_null("Y-Sort_Objects/Player2") as Node2D
	if _baked_player_anchor == null:
		return
	_baked_player_anchor.visible = false
	_baked_player_anchor.set_process(false)
	_baked_player_anchor.set_physics_process(false)
	_baked_player_anchor.remove_from_group("player")
	_baked_player_anchor.set("peer_id", -1)
	_baked_player_anchor.process_mode = Node.PROCESS_MODE_DISABLED
	var collision_shape: CollisionShape2D = _baked_player_anchor.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape != null:
		collision_shape.set_deferred("disabled", true)


func _remove_baked_level_player_if_replaced(local_player: Node2D) -> void:
	if _baked_player_anchor == null or not is_instance_valid(_baked_player_anchor):
		_baked_player_anchor = null
		return
	if local_player == _baked_player_anchor:
		return
	_baked_player_anchor.queue_free()
	_baked_player_anchor = null


func _ensure_player_spawner() -> void:
	if _player_spawner != null and is_instance_valid(_player_spawner):
		return
	var y_sort_root: Node2D = get_node_or_null("Y-Sort_Objects") as Node2D
	if y_sort_root == null:
		push_error("Y-Sort_Objects not found in level scene")
		return
	_player_spawner = get_node_or_null(PLAYER_SPAWNER_NAME) as MultiplayerSpawner
	if _player_spawner == null:
		_player_spawner = MultiplayerSpawner.new()
		_player_spawner.name = PLAYER_SPAWNER_NAME
		add_child(_player_spawner)
	_player_spawner.spawn_path = _player_spawner.get_path_to(y_sort_root)
	_player_spawner.spawn_function = Callable(self, "_spawn_player_from_data")


func _spawn_network_player(peer_id: int, spawn_position: Vector2) -> void:
	if _player_spawner == null:
		_ensure_player_spawner()
	if _player_spawner == null:
		return
	if players.has(peer_id):
		return
	_player_spawner.spawn({
		"peer_id": peer_id,
		"position": spawn_position
	})


func _get_next_network_spawn_position() -> Vector2:
	var spawn_root: Node = get_node_or_null(NETWORK_SPAWN_POINTS_PATH)
	if spawn_root != null:
		var spawn_markers: Array[Marker2D] = []
		for child in spawn_root.get_children():
			var marker := child as Marker2D
			if marker != null:
				spawn_markers.append(marker)
		if not spawn_markers.is_empty():
			var marker_index: int = players.size() % spawn_markers.size()
			return spawn_markers[marker_index].global_position
	if players.is_empty():
		return Vector2(-464, 512)
	return Vector2(100 + players.size() * 48, 100)


func _spawn_player_from_data(spawn_data: Variant) -> Node:
	if not (spawn_data is Dictionary):
		push_error("Invalid player spawn data")
		return null
	var payload: Dictionary = spawn_data as Dictionary
	var spawned_peer_id: int = int(payload.get("peer_id", 0))
	if spawned_peer_id <= 0:
		push_error("Invalid spawned player peer_id: %d" % spawned_peer_id)
		return null
	var spawn_position: Vector2 = payload.get("position", Vector2.ZERO) as Vector2

	print("Spawning player peer_id: %d" % spawned_peer_id)
	var player: CharacterBody2D = PLAYER_SCENE.instantiate() as CharacterBody2D
	if player == null:
		push_error("Failed to instantiate network player")
		return null

	player.name = "Player_%s" % spawned_peer_id
	player.set("peer_id", spawned_peer_id)
	player.global_position = spawn_position
	player.set_multiplayer_authority(spawned_peer_id)
	players[spawned_peer_id] = player
	if player.has_signal("died"):
		player.connect("died", Callable(self, "_on_network_player_died"))
	_set_peer_phase(spawned_peer_id, NetworkSessionCoordinator.PeerSessionPhase.PLAYER_SPAWNED)
	player.tree_exiting.connect(_on_spawned_player_tree_exiting.bind(spawned_peer_id, player), CONNECT_ONE_SHOT)
	_refresh_world_generation_player_paths()

	if NetworkManager != null and spawned_peer_id == NetworkManager.get_local_peer_id():
		if not NetworkManager.is_server():
			if _session_node != null:
				var expected_token: int = int(_peer_spawn_token.get(spawned_peer_id, 0))
				_session_node.send_client_spawn_ack(spawned_peer_id, expected_token)
		else:
			_set_peer_phase(spawned_peer_id, NetworkSessionCoordinator.PeerSessionPhase.ACTIVE)
		call_deferred("_finalize_local_spawned_player", spawned_peer_id, player)
	return player


func _finalize_local_spawned_player(spawned_peer_id: int, player: Node2D) -> void:
	if player == null or not is_instance_valid(player):
		return
	if NetworkManager == null or spawned_peer_id != NetworkManager.get_local_peer_id():
		return
	_update_local_references(player)
	_remove_baked_level_player_if_replaced(player)


func _on_spawned_player_tree_exiting(spawned_peer_id: int, player: Node2D) -> void:
	if players.get(spawned_peer_id, null) == player:
		players.erase(spawned_peer_id)
	_refresh_world_generation_player_paths()


func _on_network_player_died(dead_player: Node) -> void:
	if NetworkManager == null or not NetworkManager.is_server():
		return
	if dead_player == null or not is_instance_valid(dead_player) or not (dead_player is Node2D):
		return
	var dead_peer_id: int = int(dead_player.get("peer_id"))
	if dead_peer_id <= 0 or _handled_player_deaths.has(dead_peer_id):
		return
	var spawner := get_tree().get_first_node_in_group("item_spawner_network")
	if spawner == null or not spawner.has_method("spawn_dropped_item"):
		push_error("Cannot process player death for peer %d: network ItemSpawner is unavailable" % dead_peer_id)
		return

	_handled_player_deaths[dead_peer_id] = true
	var dropped_items: Array[ItemData] = (
		InventoryManager.drain_local_inventory_for_death()
		if dead_peer_id == 1
		else InventoryManager.drain_network_peer_inventory_for_death(dead_peer_id)
	)
	var death_position: Vector2 = (dead_player as Node2D).global_position
	for index in range(dropped_items.size()):
		var item: ItemData = dropped_items[index]
		var offset := _get_player_death_drop_offset(index)
		if not bool(spawner.call("spawn_dropped_item", item, death_position + offset)):
			push_error("Failed to spawn death drop %d for peer %d" % [index, dead_peer_id])
	rpc_apply_network_player_death.rpc(dead_peer_id)
	print("LAN player death processed: peer=%d drops=%d" % [dead_peer_id, dropped_items.size()])


func _get_player_death_drop_offset(index: int) -> Vector2:
	var ring: int = int(index / 8)
	var radius: float = 20.0 + float(ring) * 14.0
	var angle: float = float(index) * 2.39996323
	return Vector2.RIGHT.rotated(angle) * radius


@rpc("authority", "call_local", "reliable")
func rpc_apply_network_player_death(dead_peer_id: int) -> void:
	var dead_player: Node2D = players.get(dead_peer_id, null)
	if dead_player == null or not is_instance_valid(dead_player):
		return
	if dead_player.has_method("apply_network_death_world_state"):
		dead_player.call("apply_network_death_world_state")


func _update_local_references(local_player: Node2D) -> void:
	_player = local_player
	player_path = local_player.get_path()
	_rebind_player_path_users(local_player)
	_refresh_world_generation_player_paths()

	var hud := get_node_or_null("Y-Sort_Objects/HUD")
	if hud != null:
		hud.set("player_path", local_player.get_path())
		if hud.has_method("bind_player"):
			hud.call("bind_player", local_player)

	var controls := get_node_or_null("MobileControls")
	if controls != null:
		controls.set("player_path", local_player.get_path())


func _rebind_player_path_users(local_player: Node2D) -> void:
	if local_player == null:
		return
	var world_generation_anchor: Node2D = _resolve_world_generation_anchor_player()
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node == self:
			continue
		if _node_has_property(node, "player_path"):
			var target_player: Node2D = local_player
			if _is_world_generation_controller(node):
				target_player = world_generation_anchor
			if target_player != null and is_instance_valid(target_player):
				if node.is_inside_tree() and target_player.is_inside_tree():
					node.set("player_path", target_player.get_path())
		if _node_has_property(node, "_player"):
			node.set("_player", local_player)


func _node_has_property(node: Object, property_name: String) -> bool:
	for property_info in node.get_property_list():
		if String((property_info as Dictionary).get("name", "")) == property_name:
			return true
	return false


func _is_world_generation_controller(node: Node) -> bool:
	if node == null:
		return false
	if node.has_method("get_debug_world_generation_info"):
		return true
	var script_variant: Variant = node.get("script")
	if script_variant is Script:
		var script_path: String = String((script_variant as Script).resource_path)
		return script_path.ends_with("chunk_world_generator.gd") or script_path.ends_with("chunk_tree_spawner.gd")
	return false


func _resolve_world_generation_anchor_player() -> Node2D:
	var anchor_player: Node2D = players.get(1, null)
	if anchor_player != null and is_instance_valid(anchor_player):
		return anchor_player
	var root_player: Node2D = get_node_or_null("Y-Sort_Objects/Player_1") as Node2D
	if root_player != null and is_instance_valid(root_player):
		return root_player
	var baked_player: Node2D = get_node_or_null("Y-Sort_Objects/Player2") as Node2D
	if baked_player != null and is_instance_valid(baked_player):
		return baked_player
	return _player


func _refresh_world_generation_player_paths() -> void:
	var anchor_player: Node2D = _resolve_world_generation_anchor_player()
	if anchor_player == null or not is_instance_valid(anchor_player):
		return
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if not _is_world_generation_controller(node):
			continue
		if _node_has_property(node, "player_path"):
			if node.is_inside_tree() and anchor_player.is_inside_tree():
				node.set("player_path", anchor_player.get_path())


func _on_peer_joined(peer_id: int) -> void:
	if not NetworkManager.is_server():
		return
	if _session != null:
		_session.on_peer_joined(peer_id, _now_sec())
	_set_peer_phase(peer_id, NetworkSessionCoordinator.PeerSessionPhase.CONNECTED)
	_set_peer_phase(peer_id, NetworkSessionCoordinator.PeerSessionPhase.WORLD_LOADING)
	print("Peer joined network, waiting for world ready: %d" % peer_id)


func _on_peer_left(peer_id: int) -> void:
	if not NetworkManager.is_server():
		return
	_clear_peer_session_tracking(peer_id)
	_handled_player_deaths.erase(peer_id)
	_despawn_network_player(peer_id)


func _on_session_reset() -> void:
	_cleanup_spawned_players()
	_handled_player_deaths.clear()
	_world_snapshot_cache.clear()
	if _session != null:
		_session.clear_all()
	_peer_last_ready_seq.clear()
	_peer_spawn_token.clear()


func _on_server_disconnected() -> void:
	if _player != null and is_instance_valid(_player):
		_migration_local_player_position = _player.global_position
	_cleanup_spawned_players()
	if NetworkManager != null and NetworkManager.is_host_migration_active():
		print("LAN host migration started")
		return
	if get_tree() != null:
		if GameSaveManager != null and GameSaveManager.has_method("change_scene_with_cleanup"):
			GameSaveManager.change_scene_with_cleanup("res://Menu/Menu.tscn", true)
			return
		get_tree().change_scene_to_file.call_deferred("res://Menu/Menu.tscn")


func _on_host_migration_completed(is_new_host: bool) -> void:
	print("LAN host migration completed. is_new_host=%s" % str(is_new_host))
	call_deferred("_resume_after_host_migration", is_new_host)


func _resume_after_host_migration(is_new_host: bool) -> void:
	# Let queued player replicas from the old ENet session leave the tree before
	# new session IDs are spawned. World replicas deliberately remain in place.
	await get_tree().process_frame
	if not is_inside_tree() or NetworkManager == null:
		return
	_reset_migrated_session_state()
	if is_new_host:
		_promote_replicated_world_to_host()
	else:
		_resume_replicated_world_as_client()


func _reset_migrated_session_state() -> void:
	if _session != null:
		_session.clear_all()
	_peer_last_ready_seq.clear()
	_peer_spawn_token.clear()
	_pending_client_ready.clear()
	_sent_world_paths.clear()
	_acked_world_paths.clear()
	_peer_last_world_snapshot_signature.clear()
	_outgoing_world_snapshots.clear()
	_peer_spawn_acknowledged.clear()
	_peer_initial_world_snapshot_complete.clear()
	_world_snapshot_events.clear()
	_draining_world_snapshot_events = false
	_reset_receiving_world_snapshot()
	var shared_world := get_node_or_null("SharedWorld")
	if shared_world != null and shared_world.has_method("reset_for_host_migration"):
		shared_world.call("reset_for_host_migration")


func _promote_replicated_world_to_host() -> void:
	if not NetworkManager.is_server():
		return
	_world_snapshot_cache.clear()
	for node_variant: Variant in get_tree().get_nodes_in_group(GENERATED_WORLD_OBJECT_GROUP):
		var node := node_variant as Node
		if node == null or not is_instance_valid(node) or not is_ancestor_of(node):
			continue
		node.set_multiplayer_authority(1)
		var object_id := String(node.get_meta(WORLD_GENERATION_OBJECT_ID_META, ""))
		if not object_id.is_empty() and node is Node2D:
			_world_snapshot_cache[object_id] = node
	_network_world_initialized = true
	_last_world_snapshot_signature = -1
	_spawn_network_player(1, _migration_local_player_position)
	print("LAN migrated world promoted in place: objects=%d pickups=%d" % [
		_world_snapshot_cache.size(),
		get_tree().get_nodes_in_group("world_pickup").size()
	])


func _resume_replicated_world_as_client() -> void:
	if NetworkManager.is_server():
		return
	_network_world_initialized = false
	_disable_client_world_generation()
	if _session_node != null:
		_session_node.send_client_ready()
		_session_node.start_client_ready_flow()


func _on_host_migration_failed(reason: String) -> void:
	print("LAN host migration failed: %s" % reason)
	if get_tree() != null:
		if GameSaveManager != null and GameSaveManager.has_method("change_scene_with_cleanup"):
			GameSaveManager.change_scene_with_cleanup("res://Menu/Menu.tscn", true)
			return
		get_tree().change_scene_to_file.call_deferred("res://Menu/Menu.tscn")


func _on_client_ready_received(peer_id: int, ready_seq: int, protocol_version: int, world_hash: int) -> void:
	if not _network_world_initialized:
		_pending_client_ready[peer_id] = [ready_seq, protocol_version, world_hash]
		return
	if not NetworkManager.is_server():
		return
	if protocol_version != NETWORK_PROTOCOL_VERSION:
		rpc_id(peer_id, "rpc_protocol_rejected", NETWORK_PROTOCOL_VERSION, protocol_version)
		return
	if world_hash != _compute_world_hash():
		rpc_id(peer_id, "rpc_protocol_rejected", NETWORK_PROTOCOL_VERSION, protocol_version)
		return
	var last_seq: int = int(_peer_last_ready_seq.get(peer_id, -1))
	var existing_token: int = int(_peer_spawn_token.get(peer_id, 0))
	if existing_token > 0 and players.has(peer_id):
		_peer_last_ready_seq[peer_id] = maxi(last_seq, ready_seq)
		NetworkManager.mark_peer_world_ready(peer_id)
		if _session_node != null:
			_session_node.send_server_ready_ack(peer_id, peer_id, ready_seq, existing_token)
		return
	if ready_seq <= last_seq:
		if _session_node != null and existing_token > 0:
			_session_node.send_server_ready_ack(peer_id, peer_id, ready_seq, existing_token)
		return
	_peer_last_ready_seq[peer_id] = ready_seq
	NetworkManager.mark_peer_world_ready(peer_id)
	if _session != null:
		_session.on_peer_ready_acked(peer_id)
	_set_peer_phase(peer_id, NetworkSessionCoordinator.PeerSessionPhase.WORLD_READY_CONFIRMED)
	var spawn_token: int = _next_spawn_token(peer_id, ready_seq)
	_peer_spawn_token[peer_id] = spawn_token
	if _session_node != null:
		_session_node.send_server_ready_ack(peer_id, peer_id, ready_seq, spawn_token)
	var spawn_position: Vector2 = _get_next_network_spawn_position()
	_spawn_network_player(peer_id, spawn_position)
	call_deferred("_sync_world_snapshot_to_peer", peer_id, true)


func _on_client_ready_acknowledged(ack_peer_id: int, ready_seq: int, protocol_version: int, spawn_token: int) -> void:
	if NetworkManager == null or NetworkManager.is_server():
		return
	if protocol_version != NETWORK_PROTOCOL_VERSION:
		return
	if ack_peer_id != NetworkManager.get_local_peer_id():
		return
	if ready_seq <= 0 or spawn_token <= 0:
		return
	_peer_spawn_token[ack_peer_id] = spawn_token
	if _session_node != null:
		_session_node.stop_client_ready_flow()
		if players.has(ack_peer_id):
			_session_node.send_client_spawn_ack(ack_peer_id, spawn_token)
	print("Client world ready acknowledged by host")


func _on_client_spawn_ack_received(peer_id: int, spawn_token: int) -> void:
	if NetworkManager == null or not NetworkManager.is_server():
		return
	if not players.has(peer_id):
		return
	var expected_token: int = int(_peer_spawn_token.get(peer_id, 0))
	if expected_token <= 0 or spawn_token != expected_token:
		return
	_peer_spawn_acknowledged[peer_id] = true
	if _session != null:
		_session.on_peer_spawn_acknowledged(peer_id)
	_set_peer_phase(peer_id, NetworkSessionCoordinator.PeerSessionPhase.PLAYER_SPAWNED)
	_try_activate_peer(peer_id)


func _disable_client_world_generation() -> void:
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if not _is_world_generation_controller(node):
			continue
		if node.has_method("disable_generation_runtime"):
			node.call("disable_generation_runtime")
			continue
		if _node_has_property(node, "enabled"):
			node.set("enabled", false)
		if node.has_method("set_process"):
			node.set_process(false)
		if node.has_method("set_physics_process"):
			node.set_physics_process(false)


func _clear_local_generated_world_objects() -> void:
	for node_variant: Variant in get_tree().get_nodes_in_group(GENERATED_WORLD_OBJECT_GROUP):
		var node: Node = node_variant as Node
		if node == null or not is_instance_valid(node):
			continue
		node.queue_free()


func _sync_world_snapshot_to_ready_clients(force_send: bool) -> void:
	if NetworkManager == null or not NetworkManager.is_server():
		return
	if _world_snapshot_build_running:
		return
	var target_peers: PackedInt32Array = NetworkManager.get_ready_client_peers()
	if target_peers.is_empty():
		return
	_world_snapshot_build_running = true
	var snapshot_payload: Array = await _collect_world_snapshot_payload_sliced()
	if not is_inside_tree() or NetworkManager == null or not NetworkManager.is_server():
		_world_snapshot_build_running = false
		return
	var snapshot_signature: int = await _compute_world_snapshot_signature_sliced(snapshot_payload)
	_last_world_snapshot_signature = snapshot_signature
	for peer_id: int in target_peers:
		if not multiplayer.get_peers().has(peer_id) or not NetworkManager.is_peer_world_ready(peer_id):
			continue
		if _outgoing_world_snapshots.has(peer_id) or _world_snapshot_building_peers.has(peer_id):
			continue
		if not force_send and int(_peer_last_world_snapshot_signature.get(peer_id, -1)) == snapshot_signature:
			continue
		_sync_world_snapshot_to_peer(peer_id, true, snapshot_payload, snapshot_signature)
	_world_snapshot_build_running = false


func _sync_world_snapshot_to_peer(
	peer_id: int,
	_force_send: bool = true,
	prebuilt_payload: Array = [],
	precomputed_signature: int = -1
) -> void:
	if peer_id <= 1:
		return
	if _outgoing_world_snapshots.has(peer_id) or _world_snapshot_building_peers.has(peer_id):
		return
	var snapshot_payload: Array = prebuilt_payload
	var snapshot_signature: int = precomputed_signature
	if snapshot_payload.is_empty():
		_world_snapshot_building_peers[peer_id] = true
		snapshot_payload = await _collect_world_snapshot_payload_sliced()
		if (
			not is_inside_tree()
			or NetworkManager == null
			or not NetworkManager.is_server()
			or not multiplayer.get_peers().has(peer_id)
		):
			_world_snapshot_building_peers.erase(peer_id)
			return
		snapshot_signature = await _compute_world_snapshot_signature_sliced(snapshot_payload)
		_world_snapshot_building_peers.erase(peer_id)
	var paths := {}
	for entry in snapshot_payload:
		paths[String(entry.parent) + "/" + String(entry.node_name)] = true
	_sent_world_paths[peer_id] = paths
	var snapshot_id: int = _next_world_snapshot_id
	_next_world_snapshot_id += 1
	_peer_last_world_snapshot_signature[peer_id] = (
		snapshot_signature
		if snapshot_signature >= 0
		else _compute_world_snapshot_signature(snapshot_payload)
	)
	var total_chunks: int = ceili(float(snapshot_payload.size()) / float(WORLD_SNAPSHOT_CHUNK_ENTRIES))
	_outgoing_world_snapshots[peer_id] = {
		"id": snapshot_id,
		"payload": snapshot_payload,
		"next_chunk": 0,
		"total_chunks": total_chunks
	}
	rpc_id(peer_id, "rpc_world_snapshot_begin", snapshot_id, total_chunks, snapshot_payload.size())
	if total_chunks == 0:
		rpc_id(peer_id, "rpc_world_snapshot_end", snapshot_id)
		return
	_send_next_world_snapshot_chunk(peer_id)


func _send_next_world_snapshot_chunk(peer_id: int) -> void:
	if not _outgoing_world_snapshots.has(peer_id):
		return
	var transfer: Dictionary = _outgoing_world_snapshots[peer_id]
	var chunk_index: int = int(transfer.get("next_chunk", 0))
	var total_chunks: int = int(transfer.get("total_chunks", 0))
	if chunk_index >= total_chunks:
		rpc_id(peer_id, "rpc_world_snapshot_end", int(transfer.get("id", 0)))
		return
	var payload: Array = transfer.get("payload", []) as Array
	var start_index: int = chunk_index * WORLD_SNAPSHOT_CHUNK_ENTRIES
	var end_index: int = mini(start_index + WORLD_SNAPSHOT_CHUNK_ENTRIES, payload.size())
	var chunk: Array = []
	for entry_index in range(start_index, end_index):
		chunk.append(payload[entry_index])
	var packed: PackedByteArray = var_to_bytes(chunk).compress(FileAccess.COMPRESSION_GZIP)
	rpc_id(peer_id, "rpc_world_snapshot_chunk", int(transfer.get("id", 0)), chunk_index, packed)


func _collect_world_snapshot_payload() -> Array:
	var payload: Array = []
	var nodes: Array[Node] = []
	var seen_nodes := {}
	for group in [GENERATED_WORLD_OBJECT_GROUP, &"enemy"]:
		for candidate in get_tree().get_nodes_in_group(group):
			if candidate is Node2D and not candidate.is_queued_for_deletion() and not seen_nodes.has(candidate.get_instance_id()):
				seen_nodes[candidate.get_instance_id()] = true
				nodes.append(candidate)
	# Parents must have their final names before descendants record their paths.
	nodes.sort_custom(func(a: Node, b: Node): return a.get_path().get_name_count() < b.get_path().get_name_count())
	for node in nodes:
		if not node.has_meta(WORLD_GENERATION_OBJECT_ID_META):
			node.set_meta(WORLD_GENERATION_OBJECT_ID_META, "network/" + String(get_path_to(node)))
		if String(node.name).contains("@"):
			node.name = "Replica_" + String(node.get_meta(WORLD_GENERATION_OBJECT_ID_META)).sha256_text().substr(0, 20)
	for node_variant: Variant in nodes:
		_append_world_snapshot_entry(node_variant, payload)
	return payload


func _collect_world_snapshot_payload_sliced() -> Array:
	var payload: Array = []
	var nodes: Array[Node] = []
	var seen_nodes := {}
	for group in [GENERATED_WORLD_OBJECT_GROUP, &"enemy"]:
		for candidate in get_tree().get_nodes_in_group(group):
			if candidate is Node2D and not candidate.is_queued_for_deletion() and not seen_nodes.has(candidate.get_instance_id()):
				seen_nodes[candidate.get_instance_id()] = true
				nodes.append(candidate)
	# Preserve the same parent-before-child contract as the synchronous collector.
	nodes.sort_custom(func(a: Node, b: Node): return a.get_path().get_name_count() < b.get_path().get_name_count())
	var slice_start: int = Time.get_ticks_usec()
	for node in nodes:
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if not node.has_meta(WORLD_GENERATION_OBJECT_ID_META):
			node.set_meta(WORLD_GENERATION_OBJECT_ID_META, "network/" + String(get_path_to(node)))
		if String(node.name).contains("@"):
			node.name = "Replica_" + String(node.get_meta(WORLD_GENERATION_OBJECT_ID_META)).sha256_text().substr(0, 20)
		if Time.get_ticks_usec() - slice_start >= WORLD_SNAPSHOT_BUILD_BUDGET_USEC:
			await get_tree().process_frame
			if not is_inside_tree():
				return []
			slice_start = Time.get_ticks_usec()
	for node_variant: Variant in nodes:
		_append_world_snapshot_entry(node_variant, payload)
		if Time.get_ticks_usec() - slice_start >= WORLD_SNAPSHOT_BUILD_BUDGET_USEC:
			await get_tree().process_frame
			if not is_inside_tree():
				return []
			slice_start = Time.get_ticks_usec()
	return payload


func _append_world_snapshot_entry(node_variant: Variant, payload: Array) -> bool:
	# Snapshot collection yields between slices. Chunk streaming may free a node
	# retained in the captured array before the next slice resumes, so validity
	# must be checked before a typed cast or any property access.
	if not is_instance_valid(node_variant):
		return false
	var node_2d: Node2D = node_variant as Node2D
	if node_2d == null or node_2d.is_queued_for_deletion():
		return false
	var object_id: String = str(node_2d.get_meta(WORLD_GENERATION_OBJECT_ID_META, ""))
	var scene_path: String = str(node_2d.get_meta(WORLD_GENERATION_SCENE_PATH_META, node_2d.scene_file_path))
	if object_id.is_empty() or scene_path.is_empty():
		return false
	var parent: Node = node_2d.get_parent()
	if parent == null or not is_instance_valid(parent):
		return false
	payload.append({
		"id": object_id,
		"scene": scene_path,
		"node_name": String(node_2d.name),
		"dynamic": node_2d.is_in_group("enemy"),
		"population_id": String(node_2d.get_meta("population_id", "")),
		"parent": str(parent.get_path()),
		"position": {"x": node_2d.global_position.x, "y": node_2d.global_position.y},
		"rotation": node_2d.global_rotation,
		"scale": {"x": node_2d.global_scale.x, "y": node_2d.global_scale.y},
		"state": _collect_network_persistence_state(node_2d)
	})
	return true


func _collect_network_persistence_state(node: Node) -> Dictionary:
	if node == null or not node.has_method("get_save_data") or not node.has_method("apply_save_data"):
		return {}
	var state: Variant = node.call("get_save_data")
	return (state as Dictionary).duplicate(true) if state is Dictionary else {}


func _compute_world_snapshot_signature(payload: Array) -> int:
	var signature: int = payload.size()
	for entry_variant: Variant in payload:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant as Dictionary
		var object_id: String = str(entry.get("id", ""))
		var pos_dict: Dictionary = entry.get("position", {}) as Dictionary
		var px: int = int(round(float(pos_dict.get("x", 0.0))))
		var py: int = int(round(float(pos_dict.get("y", 0.0))))
		signature = int(((signature * 16777619) ^ hash(object_id)) & 0x7fffffff)
		var persistent_state: Variant = entry.get("state", {})
		if persistent_state is Dictionary and not (persistent_state as Dictionary).is_empty():
			signature = int(((signature * 16777619) ^ hash(JSON.stringify(persistent_state, "", true))) & 0x7fffffff)
		if not bool(entry.get("dynamic", false)):
			signature = int(((signature * 16777619) ^ px) & 0x7fffffff)
			signature = int(((signature * 16777619) ^ py) & 0x7fffffff)
	return signature


func _compute_world_snapshot_signature_sliced(payload: Array) -> int:
	var signature: int = payload.size()
	var slice_start: int = Time.get_ticks_usec()
	for entry_variant: Variant in payload:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant as Dictionary
		var object_id: String = str(entry.get("id", ""))
		var pos_dict: Dictionary = entry.get("position", {}) as Dictionary
		var px: int = int(round(float(pos_dict.get("x", 0.0))))
		var py: int = int(round(float(pos_dict.get("y", 0.0))))
		signature = int(((signature * 16777619) ^ hash(object_id)) & 0x7fffffff)
		var persistent_state: Variant = entry.get("state", {})
		if persistent_state is Dictionary and not (persistent_state as Dictionary).is_empty():
			signature = int(((signature * 16777619) ^ hash(JSON.stringify(persistent_state, "", true))) & 0x7fffffff)
		if not bool(entry.get("dynamic", false)):
			signature = int(((signature * 16777619) ^ px) & 0x7fffffff)
			signature = int(((signature * 16777619) ^ py) & 0x7fffffff)
		if Time.get_ticks_usec() - slice_start >= WORLD_SNAPSHOT_BUILD_BUDGET_USEC:
			await get_tree().process_frame
			if not is_inside_tree():
				return signature
			slice_start = Time.get_ticks_usec()
	return signature


@rpc("authority", "call_remote", "reliable")
func rpc_world_snapshot_begin(snapshot_id: int, total_chunks: int, total_entries: int) -> void:
	if NetworkManager == null or NetworkManager.is_server():
		return
	if snapshot_id <= 0 or total_chunks < 0 or total_entries < 0:
		return
	_queue_world_snapshot_event({
		"kind": "begin",
		"id": snapshot_id,
		"total_chunks": total_chunks,
		"total_entries": total_entries
	})


@rpc("authority", "call_remote", "reliable")
func rpc_world_snapshot_chunk(snapshot_id: int, chunk_index: int, packed: PackedByteArray) -> void:
	if NetworkManager == null or NetworkManager.is_server():
		return
	_queue_world_snapshot_event({"kind": "chunk", "id": snapshot_id, "index": chunk_index, "packed": packed})


@rpc("authority", "call_remote", "reliable")
func rpc_world_snapshot_end(snapshot_id: int) -> void:
	if NetworkManager == null or NetworkManager.is_server():
		return
	_queue_world_snapshot_event({"kind": "end", "id": snapshot_id})


func _queue_world_snapshot_event(event: Dictionary) -> void:
	_world_snapshot_events.append(event)
	if not _draining_world_snapshot_events:
		_drain_world_snapshot_events()


func _drain_world_snapshot_events() -> void:
	_draining_world_snapshot_events = true
	while not _world_snapshot_events.is_empty():
		var event: Dictionary = _world_snapshot_events.pop_front()
		var kind: String = String(event.get("kind", ""))
		var snapshot_id: int = int(event.get("id", 0))
		if kind == "begin":
			_reset_receiving_world_snapshot()
			_receiving_world_snapshot_id = snapshot_id
			_receiving_world_snapshot_expected_chunks = int(event.get("total_chunks", 0))
			_receiving_world_snapshot_expected_entries = int(event.get("total_entries", 0))
		elif kind == "chunk":
			if snapshot_id != _receiving_world_snapshot_id:
				continue
			var chunk_index: int = int(event.get("index", -1))
			if chunk_index != _receiving_world_snapshot_next_chunk:
				continue
			var packed: PackedByteArray = event.get("packed", PackedByteArray()) as PackedByteArray
			var decoded: Variant = bytes_to_var(packed.decompress_dynamic(
				WORLD_SNAPSHOT_CHUNK_MAX_DECOMPRESSED_BYTES,
				FileAccess.COMPRESSION_GZIP
			))
			if not (decoded is Array):
				continue
			await _apply_world_snapshot_entries(
				decoded as Array,
				_receiving_world_snapshot_seen_ids,
				_receiving_world_snapshot_failed_paths
			)
			if not is_inside_tree() or multiplayer.multiplayer_peer == null:
				_draining_world_snapshot_events = false
				return
			_receiving_world_snapshot_next_chunk += 1
			rpc_id(1, "rpc_world_snapshot_chunk_ack", snapshot_id, chunk_index)
		elif kind == "end":
			if snapshot_id != _receiving_world_snapshot_id:
				continue
			if _receiving_world_snapshot_next_chunk != _receiving_world_snapshot_expected_chunks:
				continue
			_finalize_world_snapshot(_receiving_world_snapshot_seen_ids)
			var paths := _collect_world_replica_paths()
			rpc_id(1, "rpc_world_snapshot_ack", snapshot_id, _receiving_world_snapshot_failed_paths)
			print("LAN_WORLD_REPLICAS_READY count=%d expected=%d chunks=%d" % [
				paths.size(),
				_receiving_world_snapshot_expected_entries,
				_receiving_world_snapshot_expected_chunks
			])
			_reset_receiving_world_snapshot()
	_draining_world_snapshot_events = false


func _reset_receiving_world_snapshot() -> void:
	_receiving_world_snapshot_id = 0
	_receiving_world_snapshot_expected_chunks = 0
	_receiving_world_snapshot_expected_entries = 0
	_receiving_world_snapshot_next_chunk = 0
	_receiving_world_snapshot_seen_ids = {}
	_receiving_world_snapshot_failed_paths = PackedStringArray()


func _collect_world_replica_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	for replica in _world_snapshot_cache.values():
		if is_instance_valid(replica) and not replica.is_queued_for_deletion():
			paths.append(String(replica.get_path()))
	return paths


@rpc("any_peer", "call_remote", "reliable")
func rpc_world_snapshot_chunk_ack(snapshot_id: int, chunk_index: int) -> void:
	if NetworkManager == null or not NetworkManager.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not _outgoing_world_snapshots.has(sender):
		return
	var transfer: Dictionary = _outgoing_world_snapshots[sender]
	if int(transfer.get("id", 0)) != snapshot_id or int(transfer.get("next_chunk", 0)) != chunk_index:
		return
	transfer["next_chunk"] = chunk_index + 1
	_outgoing_world_snapshots[sender] = transfer
	call_deferred("_send_next_world_snapshot_chunk", sender)


@rpc("any_peer", "call_remote", "reliable")
func rpc_world_snapshot_ack(snapshot_id: int, failed_paths: PackedStringArray) -> void:
	if NetworkManager == null or not NetworkManager.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not _outgoing_world_snapshots.has(sender) or not _sent_world_paths.has(sender):
		return
	var transfer: Dictionary = _outgoing_world_snapshots[sender]
	if int(transfer.get("id", 0)) != snapshot_id:
		return
	if int(transfer.get("next_chunk", 0)) != int(transfer.get("total_chunks", 0)):
		return
	_outgoing_world_snapshots.erase(sender)
	var confirmed: Dictionary = (_sent_world_paths[sender] as Dictionary).duplicate()
	for path in failed_paths:
		confirmed.erase(path)
	var previous: Dictionary = _acked_world_paths.get(sender, {})
	_acked_world_paths[sender] = confirmed
	for path in confirmed:
		if previous.has(path): continue
		var actor := get_node_or_null(NodePath(path))
		if actor != null and actor.has_method("rpc_sync_enemy_state"):
			actor.rpc_id(sender, "rpc_sync_enemy_state", actor.health, actor._is_dead, actor._last_lethal_hit_direction, false)
	var is_initial_snapshot: bool = not bool(_peer_initial_world_snapshot_complete.get(sender, false))
	if is_initial_snapshot and confirmed.size() != (_sent_world_paths[sender] as Dictionary).size():
		_peer_last_world_snapshot_signature.erase(sender)
		push_warning("Peer %d failed to instantiate %d world replicas; scheduling a replacement snapshot" % [
			sender,
			(_sent_world_paths[sender] as Dictionary).size() - confirmed.size()
		])
		return
	_peer_initial_world_snapshot_complete[sender] = true
	if is_initial_snapshot:
		_sync_pickups_snapshot_to_peer(sender)
	_try_activate_peer(sender)
	print("LAN_WORLD_REPLICAS_ACK peer=%d snapshot=%d count=%d" % [sender, snapshot_id, confirmed.size()])


func _sync_pickups_snapshot_to_peer(peer_id: int) -> void:
	for spawner_variant: Variant in get_tree().get_nodes_in_group("item_spawner_network"):
		var spawner := spawner_variant as Node
		if spawner != null and spawner.has_method("sync_pickups_snapshot_to_peer"):
			spawner.call("sync_pickups_snapshot_to_peer", peer_id)


func _try_activate_peer(peer_id: int) -> void:
	if not bool(_peer_spawn_acknowledged.get(peer_id, false)):
		return
	if not bool(_peer_initial_world_snapshot_complete.get(peer_id, false)):
		return
	if _session != null:
		_session.on_peer_active(peer_id)
	_set_peer_phase(peer_id, NetworkSessionCoordinator.PeerSessionPhase.ACTIVE)


func has_world_replica(peer_id: int, actor: Node) -> bool:
	return _acked_world_paths.get(peer_id, {}).has(String(actor.get_path())) and _sent_world_paths.get(peer_id, {}).has(String(actor.get_path()))


func _apply_world_snapshot_payload(payload: Array) -> void:
	var seen_ids: Dictionary = {}
	await _apply_world_snapshot_entries(payload, seen_ids)
	_finalize_world_snapshot(seen_ids)


func _apply_world_snapshot_entries(
	payload: Array,
	seen_ids: Dictionary,
	failed_paths: PackedStringArray = PackedStringArray()
) -> void:
	var slice_start := Time.get_ticks_usec()
	for entry_variant: Variant in payload:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant as Dictionary
		var object_id: String = str(entry.get("id", ""))
		if object_id.is_empty():
			continue
		seen_ids[object_id] = true
		var cached_node: Variant = _world_snapshot_cache.get(object_id, null)
		var node_2d: Node2D = cached_node as Node2D if is_instance_valid(cached_node) else null
		if node_2d == null:
			node_2d = _instantiate_world_snapshot_node(entry)
			if node_2d == null:
				failed_paths.append(String(entry.get("parent", "")) + "/" + String(entry.get("node_name", "")))
				continue
			_world_snapshot_cache[object_id] = node_2d
		_apply_world_snapshot_transform(node_2d, entry)
		_apply_network_persistence_state(node_2d, entry.get("state", {}))
		if Time.get_ticks_usec() - slice_start >= 4000:
			await get_tree().process_frame
			if not is_inside_tree(): return
			slice_start = Time.get_ticks_usec()


func _finalize_world_snapshot(seen_ids: Dictionary) -> void:
	var stale_ids: Array[String] = []
	for key_variant: Variant in _world_snapshot_cache.keys():
		var cached_id: String = str(key_variant)
		if seen_ids.has(cached_id):
			continue
		stale_ids.append(cached_id)
	for stale_id in stale_ids:
		var cached_stale_node: Variant = _world_snapshot_cache.get(stale_id, null)
		var stale_node: Node2D = cached_stale_node as Node2D if is_instance_valid(cached_stale_node) else null
		if stale_node != null:
			stale_node.queue_free()
		_world_snapshot_cache.erase(stale_id)
	if OS.get_cmdline_user_args().has("--lan-smoke-log-population=1"):
		_print_enemy_population_smoke_marker()


func _instantiate_world_snapshot_node(entry: Dictionary) -> Node2D:
	var scene_path: String = str(entry.get("scene", ""))
	if scene_path.is_empty():
		return null
	var parent_path: String = str(entry.get("parent", ""))
	if parent_path.is_empty():
		return null
	var parent: Node = get_node_or_null(NodePath(parent_path))
	if parent == null:
		return null

	var existing := parent.get_node_or_null(NodePath(String(entry.get("node_name", "")))) as Node2D
	if existing != null and existing.scene_file_path == scene_path:
		return existing

	var scene: PackedScene = load(scene_path) as PackedScene
	if scene == null:
		return null
	var node_2d: Node2D = scene.instantiate() as Node2D
	if node_2d == null:
		return null

	var object_id: String = str(entry.get("id", ""))
	node_2d.set_meta(WORLD_GENERATION_OBJECT_ID_META, object_id)
	node_2d.set_meta(WORLD_GENERATION_SCENE_PATH_META, scene_path)
	node_2d.name = String(entry.get("node_name", node_2d.name))
	var population_id := String(entry.get("population_id", ""))
	if not population_id.is_empty():
		node_2d.set_meta("population_id", population_id)
	node_2d.set_multiplayer_authority(1)
	node_2d.add_to_group(GENERATED_WORLD_OBJECT_GROUP)
	# _ready initializes interpolation from global_position, so set the pose first.
	var pos: Dictionary = entry.get("position", {})
	var scale_data: Dictionary = entry.get("scale", {})
	var world_pose := Transform2D(
		float(entry.get("rotation", 0.0)),
		Vector2(float(scale_data.get("x", 1.0)), float(scale_data.get("y", 1.0))),
		0.0,
		Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0))))
	node_2d.transform = parent.global_transform.affine_inverse() * world_pose
	parent.add_child(node_2d)
	return node_2d


func _apply_world_snapshot_transform(node_2d: Node2D, entry: Dictionary) -> void:
	var pos_dict: Dictionary = entry.get("position", {}) as Dictionary
	var scale_dict: Dictionary = entry.get("scale", {}) as Dictionary
	node_2d.global_position = Vector2(
		float(pos_dict.get("x", node_2d.global_position.x)),
		float(pos_dict.get("y", node_2d.global_position.y))
	)
	node_2d.global_rotation = float(entry.get("rotation", node_2d.global_rotation))
	node_2d.global_scale = Vector2(
		float(scale_dict.get("x", node_2d.global_scale.x)),
		float(scale_dict.get("y", node_2d.global_scale.y))
	)


func _apply_network_persistence_state(node: Node, raw_state: Variant) -> void:
	if node == null or not (raw_state is Dictionary) or (raw_state as Dictionary).is_empty():
		return
	if node.has_method("apply_save_data"):
		node.call("apply_save_data", (raw_state as Dictionary).duplicate(true))


@rpc("authority", "call_local", "reliable")
func rpc_protocol_rejected(expected_version: int, got_version: int) -> void:
	if NetworkManager == null:
		return
	var reason: String = "Protocol mismatch. Host=%d Client=%d" % [expected_version, got_version]
	NetworkManager.reject_connection(reason)


func _despawn_network_player(peer_id: int) -> void:
	if not players.has(peer_id):
		return

	print("Removing player peer_id: %d" % peer_id)
	var player: Node2D = players[peer_id]
	players.erase(peer_id)
	if is_instance_valid(player):
		player.queue_free()


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


func _schedule_smoke_pickup_if_requested() -> void:
	var pickup_after_sec: float = _get_cli_float_arg("lan-smoke-pickup-after-sec", -1.0)
	if pickup_after_sec <= 0.0:
		return
	call_deferred("_smoke_pickup_impl", pickup_after_sec)


func _smoke_pickup_impl(delay_sec: float) -> void:
	await get_tree().create_timer(delay_sec).timeout
	var local_peer_id: int = NetworkManager.get_local_peer_id() if NetworkManager != null else 0
	var before_count: int = get_tree().get_nodes_in_group("world_pickup").size()
	print("[LAN_SMOKE_PICKUP] peer=%d before_count=%d" % [local_peer_id, before_count])
	var local_player: Node = players.get(local_peer_id, null)
	var pickup_ok: bool = false
	var target_pickup: Node2D = null
	var target_pickup_item_name: String = ""
	var target_pickup_position: Vector2 = Vector2.ZERO
	if local_player != null and is_instance_valid(local_player):
		target_pickup = _find_nearest_pickup(local_player)
		if target_pickup != null and is_instance_valid(target_pickup):
			target_pickup_position = target_pickup.global_position
			target_pickup_item_name = _get_pickup_item_name(target_pickup)
		_move_player_to_nearest_pickup(local_player, target_pickup)
		await get_tree().create_timer(0.25).timeout
		var inventory_root: Node = local_player.get("inventory_root") as Node
		if inventory_root != null and inventory_root.has_method("pickup_first_nearby_item"):
			pickup_ok = bool(inventory_root.call("pickup_first_nearby_item"))
	print("[LAN_SMOKE_PICKUP] peer=%d pickup_ok=%s" % [local_peer_id, str(pickup_ok)])
	await get_tree().create_timer(1.0).timeout
	var target_removed_locally: bool = target_pickup == null or not is_instance_valid(target_pickup)
	var after_count: int = get_tree().get_nodes_in_group("world_pickup").size()
	var pickup_reduced_world_count: bool = after_count < before_count
	print("[LAN_SMOKE_PICKUP] peer=%d after_count=%d target_removed_local=%s target_item=%s target_pos=(%.1f,%.1f)" % [
		local_peer_id,
		after_count,
		str(target_removed_locally),
		target_pickup_item_name,
		target_pickup_position.x,
		target_pickup_position.y
	])
	if NetworkManager != null and NetworkManager.is_server() and pickup_ok and pickup_reduced_world_count:
		rpc("rpc_lan_smoke_server_pickup_probe", target_pickup_position, target_pickup_item_name)
		for target_peer_id: int in NetworkManager.get_ready_client_peers():
			rpc_id(target_peer_id, "rpc_lan_smoke_server_pickup_probe", target_pickup_position, target_pickup_item_name)
	if NetworkManager != null and not NetworkManager.is_server() and pickup_ok:
		rpc_id(
			1,
			"rpc_lan_smoke_pickup_report",
			local_peer_id,
			target_pickup_position,
			target_pickup_item_name,
			pickup_ok,
			target_removed_locally
		)


func _move_player_to_nearest_pickup(local_player: Node, preferred_pickup: Node2D = null) -> void:
	var player_2d: Node2D = local_player as Node2D
	if player_2d == null:
		return
	var nearest: Node2D = preferred_pickup
	if nearest != null and is_instance_valid(nearest):
		player_2d.global_position = nearest.global_position
		return
	nearest = null
	var best_dist: float = INF
	for node_variant: Variant in get_tree().get_nodes_in_group("world_pickup"):
		var pickup: Node2D = node_variant as Node2D
		if pickup == null or not is_instance_valid(pickup):
			continue
		var d: float = player_2d.global_position.distance_to(pickup.global_position)
		if d < best_dist:
			best_dist = d
			nearest = pickup
	if nearest == null:
		return
	player_2d.global_position = nearest.global_position


func _find_nearest_pickup(local_player: Node) -> Node2D:
	var player_2d: Node2D = local_player as Node2D
	if player_2d == null:
		return null
	var nearest: Node2D = null
	var best_dist: float = INF
	for node_variant: Variant in get_tree().get_nodes_in_group("world_pickup"):
		var pickup: Node2D = node_variant as Node2D
		if pickup == null or not is_instance_valid(pickup):
			continue
		var d: float = player_2d.global_position.distance_to(pickup.global_position)
		if d < best_dist:
			best_dist = d
			nearest = pickup
	return nearest


func _get_pickup_item_name(pickup: Node2D) -> String:
	if pickup == null or not is_instance_valid(pickup):
		return ""
	var item_data: Resource = pickup.get("item_data") as Resource
	if item_data == null:
		return ""
	return String(item_data.get("item_name"))


func _count_pickups_near_position(target_position: Vector2, radius_px: float, target_item_name: String) -> int:
	var result: int = 0
	for node_variant: Variant in get_tree().get_nodes_in_group("world_pickup"):
		var pickup: Node2D = node_variant as Node2D
		if pickup == null or not is_instance_valid(pickup):
			continue
		if pickup.global_position.distance_to(target_position) > radius_px:
			continue
		if not target_item_name.is_empty():
			var candidate_name: String = _get_pickup_item_name(pickup)
			if candidate_name != target_item_name:
				continue
		result += 1
	return result


@rpc("any_peer", "reliable")
func rpc_lan_smoke_pickup_report(
	requester_peer_id: int,
	target_position: Vector2,
	target_item_name: String,
	pickup_ok: bool,
	target_removed_local: bool
) -> void:
	if NetworkManager == null or not NetworkManager.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != requester_peer_id:
		return
	var server_near_count: int = _count_pickups_near_position(target_position, 14.0, target_item_name)
	var sync_ok: bool = pickup_ok and target_removed_local and server_near_count == 0
	print("[LAN_SMOKE_PICKUP_SYNC] peer=%d pickup_ok=%s removed_local=%s server_near_count=%d item=%s pos=(%.1f,%.1f) sync_ok=%s" % [
		requester_peer_id,
		str(pickup_ok),
		str(target_removed_local),
		server_near_count,
		target_item_name,
		target_position.x,
		target_position.y,
		str(sync_ok)
	])


@rpc("any_peer", "call_local", "reliable")
func rpc_lan_smoke_server_pickup_probe(target_position: Vector2, target_item_name: String) -> void:
	var local_peer_id: int = NetworkManager.get_local_peer_id() if NetworkManager != null else 0
	var near_count: int = _count_pickups_near_position(target_position, 14.0, target_item_name)
	var sync_ok: bool = near_count == 0
	print("[LAN_SMOKE_PICKUP_PROBE] peer=%d near_count=%d item=%s pos=(%.1f,%.1f) sync_ok=%s" % [
		local_peer_id,
		near_count,
		target_item_name,
		target_position.x,
		target_position.y,
		str(sync_ok)
	])


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
	_world_snapshot_cache.clear()


func _update_peer_ready_watchdog(delta: float) -> void:
	if not NetworkManager.is_server():
		return
	if _session == null:
		return
	var actions: Array[Dictionary] = _session.accumulate_ready_watchdog(
		delta,
		_now_sec(),
		Callable(NetworkManager, "is_peer_world_ready"),
		SERVER_READY_WATCHDOG_RETRY_INTERVAL_SEC,
		SERVER_READY_WATCHDOG_TIMEOUT_SEC
	)
	for action in actions:
		var kind: String = String(action.get("kind", ""))
		var peer_id: int = int(action.get("peer_id", 0))
		if kind == "request_ready":
			if _session_node != null:
				_session_node.request_client_ready_for_peer(peer_id)
		elif kind == "ready_timeout":
			print("Peer %d still not world-ready after %.1fs, retrying client-ready request" % [peer_id, float(action.get("age_sec", 0.0))])
			if _session_node != null:
				_session_node.request_client_ready_for_peer(peer_id)
	var spawn_actions: Array[Dictionary] = _session.accumulate_spawn_ack_watchdog(
		delta,
		_now_sec(),
		Callable(NetworkManager, "is_peer_world_ready"),
		Callable(self, "_has_spawned_player_for_peer"),
		SERVER_SPAWN_ACK_RETRY_INTERVAL_SEC,
		SERVER_SPAWN_ACK_TIMEOUT_SEC
	)
	for action in spawn_actions:
		var kind: String = String(action.get("kind", ""))
		var peer_id: int = int(action.get("peer_id", 0))
		if kind == "request_spawn_ack":
			var spawn_token: int = int(_peer_spawn_token.get(peer_id, 0))
			if _session_node != null and spawn_token > 0:
				_session_node.request_spawn_ack_for_peer(peer_id, spawn_token)
		elif kind == "spawn_timeout":
			print("Peer %d still has no spawn ack after %.1fs, retrying spawn ack request" % [peer_id, float(action.get("age_sec", 0.0))])
			var spawn_token: int = int(_peer_spawn_token.get(peer_id, 0))
			if _session_node != null and spawn_token > 0:
				_session_node.request_spawn_ack_for_peer(peer_id, spawn_token)


func _has_spawned_player_for_peer(peer_id: int) -> bool:
	return players.has(peer_id)


func _set_peer_phase(peer_id: int, phase: int) -> void:
	if _session == null:
		return
	var phase_changed: bool = _session.set_phase(peer_id, phase)
	var network_phase_changed: bool = false
	if NetworkManager != null and NetworkManager.has_method("set_peer_session_phase"):
		var net_phase: int = _map_world_phase_to_network_manager_phase(phase)
		if not NetworkManager.has_method("get_peer_session_phase") or NetworkManager.get_peer_session_phase(peer_id) != net_phase:
			NetworkManager.set_peer_session_phase(peer_id, net_phase)
			network_phase_changed = true
	if phase_changed or network_phase_changed:
		print("[LAN_SESSION_PHASE] peer=%d phase=%s" % [peer_id, _session.get_phase_name(phase)])


func _clear_peer_session_tracking(peer_id: int) -> void:
	if _session != null:
		_session.clear_peer(peer_id)
	if NetworkManager != null and NetworkManager.has_method("clear_peer_session_phase"):
		NetworkManager.clear_peer_session_phase(peer_id)
	_pending_client_ready.erase(peer_id)
	_sent_world_paths.erase(peer_id)
	_acked_world_paths.erase(peer_id)
	_peer_last_world_snapshot_signature.erase(peer_id)
	_outgoing_world_snapshots.erase(peer_id)
	_world_snapshot_building_peers.erase(peer_id)
	_peer_spawn_acknowledged.erase(peer_id)
	_peer_initial_world_snapshot_complete.erase(peer_id)
	_peer_last_ready_seq.erase(peer_id)
	_peer_spawn_token.erase(peer_id)


func _now_sec() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _compute_world_hash() -> int:
	var basis: String = "%s|%d" % [scene_file_path, NETWORK_PROTOCOL_VERSION]
	return hash(basis)


func _next_spawn_token(peer_id: int, ready_seq: int) -> int:
	var now_ms: int = Time.get_ticks_msec()
	return int(abs(hash("%d|%d|%d" % [peer_id, ready_seq, now_ms])))


func _map_world_phase_to_network_manager_phase(world_phase: int) -> int:
	match world_phase:
		NetworkSessionCoordinator.PeerSessionPhase.CONNECTED:
			return NetworkManager.PeerSessionPhase.CONNECTED
		NetworkSessionCoordinator.PeerSessionPhase.WORLD_LOADING:
			return NetworkManager.PeerSessionPhase.WORLD_LOADING
		NetworkSessionCoordinator.PeerSessionPhase.WORLD_READY_CONFIRMED:
			return NetworkManager.PeerSessionPhase.WORLD_READY_CONFIRMED
		NetworkSessionCoordinator.PeerSessionPhase.PLAYER_SPAWNED:
			return NetworkManager.PeerSessionPhase.PLAYER_SPAWNED
		NetworkSessionCoordinator.PeerSessionPhase.ACTIVE:
			return NetworkManager.PeerSessionPhase.ACTIVE
		_:
			return NetworkManager.PeerSessionPhase.UNKNOWN
