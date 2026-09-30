extends Node
# Reliable shared state and serialized container edits. Inventory contents remain local.
var subscribers: Dictionary = {}
var locks: Dictionary = {}
var callbacks: Dictionary = {}
var next_request := 1
var next_token := 1
var sync_timer := 0.0

func _ready() -> void:
	add_to_group("network_shared_world")
	NetworkManager.peer_left.connect(_on_peer_left)

func _process(delta: float) -> void:
	if not NetworkManager.is_server(): return
	sync_timer -= delta
	if sync_timer > 0.0: return
	sync_timer = 0.25
	var clock := get_tree().get_first_node_in_group("game_clock")
	if clock != null:
		for peer in NetworkManager.get_ready_client_peers():
			rpc_id(peer, "rpc_clock", clock.get_save_data())
	for path in locks.keys():
		if Time.get_ticks_msec() - int(locks[path].created) > 20000:
			locks.erase(path)

@rpc("authority", "call_remote", "unreliable_ordered")
func rpc_clock(state: Dictionary) -> void:
	if NetworkManager.is_server(): return
	var clock := get_tree().get_first_node_in_group("game_clock")
	if clock != null: clock.apply_save_data(state)

func _source(path: String) -> Node:
	var node := get_node_or_null(NodePath(path))
	if node == null or not get_parent().is_ancestor_of(node) or not node.has_method("get_network_loot_items"): return null
	return node

func _can_access(peer: int, source: Node) -> bool:
	var actor: Node2D = get_parent().players.get(peer)
	# Large buildings have their interaction marker away from the scene origin.
	return actor != null and source is Node2D and actor.global_position.distance_to(source.global_position) <= 900.0

func _encode(items: Array) -> Array:
	var result: Array = []
	for item in items: result.append(GameSaveManager.serialize_item(item) if item != null else {})
	return result

func decode(items: Array) -> Array[ItemData]:
	var result: Array[ItemData] = []
	for item in items: result.append(GameSaveManager.deserialize_item(item) if item is Dictionary and not item.is_empty() else null)
	return result

func open_container(source: Node) -> void:
	if NetworkManager.is_server(): _open_for_peer(1, String(source.get_path()))
	else: rpc_id(1, "rpc_open", String(source.get_path()))

func notify_container_refreshed(source: Node) -> void:
	if not NetworkManager.is_server() or source == null or not source.has_method("get_network_loot_items"):
		return
	var path := String(source.get_path())
	# A completed refill invalidates any transfer that started from the previous snapshot.
	locks.erase(path)
	for peer in subscribers.get(path, {}):
		_send_state(int(peer), path, _encode(source.get_network_loot_items()))

func drop_container_item(source: Node, slot_index: int) -> void:
	if source == null or slot_index < 0: return
	if NetworkManager.is_server(): _drop_container_item_for_peer(1, String(source.get_path()), slot_index)
	else: rpc_id(1, "rpc_drop_container_item", String(source.get_path()), slot_index)

@rpc("any_peer", "call_remote", "reliable")
func rpc_drop_container_item(path: String, slot_index: int) -> void:
	if NetworkManager.is_server(): _drop_container_item_for_peer(multiplayer.get_remote_sender_id(), path, slot_index)

func _drop_container_item_for_peer(peer: int, path: String, slot_index: int) -> void:
	var source := _source(path)
	if source == null or not _can_access(peer, source) or locks.has(path): return
	var authoritative: Array = source.get_network_loot_items()
	if slot_index < 0 or slot_index >= authoritative.size(): return
	var item: ItemData = authoritative[slot_index]
	if item == null: return
	var actor: Node2D = get_parent().players.get(peer)
	var spawner := get_tree().get_first_node_in_group("item_spawner_network")
	if actor == null or spawner == null or not spawner.spawn_dropped_item(item, actor.global_position + Vector2(32.0, 0.0)): return
	authoritative[slot_index] = null
	for target in subscribers.get(path, {}): _send_state(target, path, _encode(authoritative))

@rpc("any_peer", "call_remote", "reliable")
func rpc_open(path: String) -> void:
	if NetworkManager.is_server(): _open_for_peer(multiplayer.get_remote_sender_id(), path)

func _open_for_peer(peer: int, path: String) -> void:
	var source := _source(path)
	if source == null or not _can_access(peer, source): return
	if source.has_method("mark_loot_opened"):
		source.call("mark_loot_opened")
	var peers: Dictionary = subscribers.get(path, {})
	peers[peer] = true
	subscribers[path] = peers
	_send_state(peer, path, _encode(source.get_network_loot_items()))

func _send_state(peer: int, path: String, items: Array) -> void:
	if peer == 1: _receive_state(path, items)
	else: rpc_id(peer, "rpc_container_state", path, items)

@rpc("authority", "call_remote", "reliable")
func rpc_container_state(path: String, items: Array) -> void:
	_receive_state(path, items)

func _receive_state(path: String, items: Array) -> void:
	var ui := get_tree().get_first_node_in_group("inventory_root")
	if ui != null: ui.apply_network_loot_state(path, decode(items))

func transact(source: Node, callback: Callable) -> void:
	var request := next_request
	next_request += 1
	callbacks[request] = callback
	if NetworkManager.is_server(): _acquire(1, request, String(source.get_path()))
	else: rpc_id(1, "rpc_acquire", request, String(source.get_path()))

@rpc("any_peer", "call_remote", "reliable")
func rpc_acquire(request: int, path: String) -> void:
	if NetworkManager.is_server(): _acquire(multiplayer.get_remote_sender_id(), request, path)

func _acquire(peer: int, request: int, path: String) -> void:
	var source := _source(path)
	var token := 0
	var items: Array = []
	if source != null and _can_access(peer, source) and not locks.has(path):
		token = next_token
		next_token += 1
		items = _encode(source.get_network_loot_items())
		locks[path] = {"peer": peer, "token": token, "created": Time.get_ticks_msec(), "size": items.size()}
	if peer == 1: _grant(request, path, token, items)
	else: rpc_id(peer, "rpc_grant", request, path, token, items)

@rpc("authority", "call_remote", "reliable")
func rpc_grant(request: int, path: String, token: int, items: Array) -> void:
	_grant(request, path, token, items)

func _grant(request: int, path: String, token: int, items: Array) -> void:
	var callback: Callable = callbacks.get(request, Callable())
	callbacks.erase(request)
	if token == 0: return
	var detached := decode(items)
	if callback.is_valid(): callback.call(detached)
	var result := _encode(detached)
	if NetworkManager.is_server(): _commit(1, path, token, result)
	else: rpc_id(1, "rpc_commit", path, token, result, InventoryManager.get_network_inventory_snapshot())

@rpc("any_peer", "call_remote", "reliable")
func rpc_commit(path: String, token: int, items: Array, inventory_snapshot: Dictionary) -> void:
	if NetworkManager.is_server(): _commit(multiplayer.get_remote_sender_id(), path, token, items, inventory_snapshot)

func _commit(peer: int, path: String, token: int, items: Array, inventory_snapshot: Dictionary = {}) -> void:
	if not locks.has(path) or int(locks[path].peer) != peer or int(locks[path].token) != token:
		_send_inventory_state(peer)
		return
	if items.size() != int(locks[path].size):
		locks.erase(path)
		_send_inventory_state(peer)
		return
	var source := _source(path)
	if source == null:
		locks.erase(path)
		_send_inventory_state(peer)
		return
	var authoritative: Array = source.get_network_loot_items()
	var changed := decode(items)
	if changed.size() != authoritative.size():
		locks.erase(path)
		_send_state(peer, path, _encode(authoritative))
		_send_inventory_state(peer)
		return
	if peer != 1 and not InventoryManager.commit_network_peer_inventory_transfer(peer, inventory_snapshot, authoritative, changed):
		locks.erase(path)
		_send_state(peer, path, _encode(authoritative))
		_send_inventory_state(peer)
		return
	for i in range(authoritative.size()): authoritative[i] = changed[i]
	locks.erase(path)
	for target in subscribers.get(path, {}): _send_state(target, path, _encode(authoritative))
	_send_inventory_state(peer)

func _send_inventory_state(peer: int) -> void:
	if peer <= 1 or not InventoryManager.has_network_peer_inventory(peer): return
	rpc_id(peer, "rpc_inventory_state", InventoryManager.get_network_peer_inventory_snapshot(peer))

func send_inventory_state(peer: int) -> void:
	_send_inventory_state(peer)

@rpc("authority", "call_remote", "reliable")
func rpc_inventory_state(snapshot: Dictionary) -> void:
	if NetworkManager.is_server() or multiplayer.get_remote_sender_id() != 1: return
	if InventoryManager.apply_network_authoritative_local_snapshot(snapshot):
		var ui := get_tree().get_first_node_in_group("inventory_root")
		if ui != null: ui.refresh_ui()

func spawn_drop(item: ItemData, actor: Node2D, offset: Vector2) -> bool:
	if item == null or actor == null: return false
	if NetworkManager.is_server(): return _spawn_drop_on_host(GameSaveManager.serialize_item(item), 1, offset)
	return false

@rpc("any_peer", "call_remote", "reliable")
func rpc_drop(item: Dictionary, offset: Vector2) -> void:
	# Legacy endpoint is intentionally inert. A client may never provide the item
	# payload for a world spawn; drops are extracted from its server-owned inventory.
	return

func spawn_peer_inventory_drop(peer: int, item: ItemData, offset: Vector2 = Vector2(32.0, 0.0)) -> bool:
	if not NetworkManager.is_server() or peer <= 1 or item == null: return false
	return _spawn_drop_on_host(GameSaveManager.serialize_item(item), peer, offset)

func _spawn_drop_on_host(payload: Dictionary, peer: int, offset: Vector2) -> bool:
	var actor: Node2D = get_parent().players.get(peer)
	if actor == null: return false
	var item: ItemData = GameSaveManager.deserialize_item(payload)
	if item == null: return false
	var spawner := get_tree().get_first_node_in_group("item_spawner_network")
	return spawner != null and spawner.spawn_dropped_item(item, actor.global_position + offset.limit_length(96.0))

func _on_peer_left(peer: int) -> void:
	for path in subscribers: subscribers[path].erase(peer)
	for path in locks.keys():
		if int(locks[path].peer) == peer: locks.erase(path)


func reset_for_host_migration() -> void:
	# Peer IDs and outstanding requests belong to the old ENet session.
	subscribers.clear()
	locks.clear()
	callbacks.clear()
	next_request = 1
	next_token = 1
	sync_timer = 0.0
