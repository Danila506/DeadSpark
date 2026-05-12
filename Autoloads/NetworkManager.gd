extends Node

signal server_started
signal connected_to_server
signal connection_failed
signal connection_rejected(reason: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal state_changed(state: int)
signal session_reset

const DEFAULT_MAX_PLAYERS: int = 16

enum NetworkState {
	IDLE,
	HOSTING,
	JOINING,
	IN_GAME,
	DISCONNECTING
}

var _peer: ENetMultiplayerPeer
var _state: int = NetworkState.IDLE
var _last_error: String = ""
var _last_join_ip: String = ""
var _last_join_port: int = 2456

func _ready() -> void:
	print("Current platform / OS name: %s" % OS.get_name())
	_ensure_network_signals_connected()


func host_lan_game(port: int = 2456) -> int:
	_last_error = ""
	if _state == NetworkState.HOSTING or _state == NetworkState.JOINING:
		_last_error = "Network is busy"
		return ERR_BUSY
	disconnect_from_network()
	_set_state(NetworkState.HOSTING)
	_peer = ENetMultiplayerPeer.new()
	_peer.set_bind_ip("0.0.0.0")
	var result: int = _peer.create_server(port, DEFAULT_MAX_PLAYERS)
	if result != OK:
		push_error("Failed to create LAN server on port %d. Error: %d" % [port, result])
		_last_error = "Host create failed (%d)" % result
		connection_failed.emit()
		_peer = null
		_set_state(NetworkState.IDLE)
		return result

	multiplayer.multiplayer_peer = _peer
	_ensure_network_signals_connected()
	print("Local IP candidates: %s" % str(get_local_ipv4_candidates()))
	print("LAN server started on port: %d" % port)
	_set_state(NetworkState.IN_GAME)
	server_started.emit()
	return OK


func join_lan_game(ip: String, port: int = 2456) -> int:
	_last_error = ""
	if _state == NetworkState.HOSTING or _state == NetworkState.JOINING:
		_last_error = "Network is busy"
		return ERR_BUSY
	_last_join_ip = ip
	_last_join_port = port
	disconnect_from_network()
	_set_state(NetworkState.JOINING)
	_peer = ENetMultiplayerPeer.new()
	print("Join target IP and port: %s:%d" % [ip, port])
	print("Connecting to LAN server: %s:%d" % [ip, port])
	var result: int = _peer.create_client(ip, port)
	if result != OK:
		push_error("Failed to connect to LAN server %s:%d. Error: %d" % [ip, port, result])
		_last_error = "Join failed (%d)" % result
		connection_failed.emit()
		_peer = null
		_set_state(NetworkState.IDLE)
		return result

	multiplayer.multiplayer_peer = _peer
	_ensure_network_signals_connected()
	return OK


func disconnect_from_network() -> void:
	reset_session_state()


func reset_session_state(clear_last_join_target: bool = false) -> void:
	_set_state(NetworkState.DISCONNECTING)
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null
	if clear_last_join_target:
		_last_join_ip = ""
		_last_join_port = 2456
	_set_state(NetworkState.IDLE)
	session_reset.emit()


func is_server() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()


func is_client() -> bool:
	return multiplayer.multiplayer_peer != null and not multiplayer.is_server()


func get_local_peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_unique_id()


func get_state() -> int:
	return _state


func get_last_error() -> String:
	return _last_error


func can_reconnect_last_join() -> bool:
	return not _last_join_ip.is_empty() and _last_join_port > 0 and _last_join_port <= 65535


func reconnect_last_join() -> int:
	if not can_reconnect_last_join():
		_last_error = "No previous join target"
		return ERR_INVALID_PARAMETER
	return join_lan_game(_last_join_ip, _last_join_port)


func reject_connection(reason: String) -> void:
	_last_error = reason
	connection_rejected.emit(reason)
	disconnect_from_network()


func get_local_ipv4_candidates() -> PackedStringArray:
	var result: PackedStringArray = []
	for address_variant: Variant in IP.get_local_addresses():
		var address: String = String(address_variant)
		if ":" in address:
			continue
		if address.begins_with("127."):
			continue
		result.append(address)
	return result


func _ensure_network_signals_connected() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)


func _on_peer_connected(peer_id: int) -> void:
	print("Peer connected: %d" % peer_id)
	peer_joined.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer disconnected: %d" % peer_id)
	peer_left.emit(peer_id)


func _on_connected_to_server() -> void:
	print("Connected to server")
	_set_state(NetworkState.IN_GAME)
	connected_to_server.emit()


func _on_connection_failed() -> void:
	print("Connection failed")
	if _last_error.is_empty():
		_last_error = "Connection failed"
	_set_state(NetworkState.IDLE)
	connection_failed.emit()


func _set_state(next_state: int) -> void:
	if _state == next_state:
		return
	_state = next_state
	state_changed.emit(_state)
