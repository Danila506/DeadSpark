class_name NetworkSessionNode
extends Node

signal client_ready_received(peer_id: int, ready_seq: int, protocol_version: int, world_hash: int)
signal client_spawn_ack_received(peer_id: int, spawn_token: int)
signal client_ready_acknowledged(ack_peer_id: int, ready_seq: int, protocol_version: int, spawn_token: int)

const CLIENT_READY_RETRY_INTERVAL_SEC: float = 0.75
const CLIENT_READY_RETRY_MAX_ATTEMPTS: int = 20

var _client_ready_confirmed: bool = false
var _client_ready_retry_attempts: int = 0
var _client_ready_retry_active: bool = false
var _protocol_version: int = 1
var _client_ready_seq: int = 0
var _client_world_hash: int = 0
var _expected_spawn_token: int = 0


func configure(protocol_version: int, client_world_hash: int = 0) -> void:
	_protocol_version = protocol_version
	_client_world_hash = client_world_hash


func is_client_ready_confirmed() -> bool:
	return _client_ready_confirmed


func start_client_ready_flow() -> void:
	if NetworkManager == null or NetworkManager.is_server():
		return
	if _client_ready_confirmed:
		return
	if _client_ready_retry_active:
		return
	_client_ready_confirmed = false
	_client_ready_retry_attempts = 0
	_client_ready_retry_active = true
	call_deferred("_client_ready_retry_loop")


func stop_client_ready_flow() -> void:
	_client_ready_retry_active = false


func send_client_ready() -> void:
	if NetworkManager == null or NetworkManager.is_server():
		return
	if _client_ready_confirmed:
		return
	var local_peer_id: int = NetworkManager.get_local_peer_id()
	if local_peer_id <= 1:
		return
	_client_ready_seq += 1
	rpc_id(1, "rpc_client_ready", local_peer_id, _client_ready_seq, _protocol_version, _client_world_hash)


func send_client_spawn_ack(peer_id: int, spawn_token: int) -> void:
	if NetworkManager == null or NetworkManager.is_server():
		return
	if peer_id <= 1:
		return
	if spawn_token <= 0:
		return
	rpc_id(1, "rpc_client_spawn_ack", peer_id, spawn_token)


func send_server_ready_ack(target_peer_id: int, ack_peer_id: int, ready_seq: int, spawn_token: int) -> void:
	if NetworkManager == null or not NetworkManager.is_server():
		return
	if target_peer_id <= 1:
		return
	rpc_id(target_peer_id, "rpc_server_ready_ack", ack_peer_id, ready_seq, _protocol_version, spawn_token)


func request_client_ready_for_peer(target_peer_id: int) -> void:
	if NetworkManager == null or not NetworkManager.is_server():
		return
	if target_peer_id <= 1:
		return
	rpc_id(target_peer_id, "rpc_server_request_client_ready")


func request_spawn_ack_for_peer(target_peer_id: int, spawn_token: int) -> void:
	if NetworkManager == null or not NetworkManager.is_server():
		return
	if target_peer_id <= 1:
		return
	if spawn_token <= 0:
		return
	rpc_id(target_peer_id, "rpc_server_request_spawn_ack", spawn_token)


func _client_ready_retry_loop() -> void:
	while _client_ready_retry_active and not _client_ready_confirmed:
		if NetworkManager == null or NetworkManager.is_server():
			_client_ready_retry_active = false
			return
		if _client_ready_retry_attempts >= CLIENT_READY_RETRY_MAX_ATTEMPTS:
			_client_ready_retry_active = false
			print("Client ready retry budget exhausted")
			return
		_client_ready_retry_attempts += 1
		send_client_ready()
		await get_tree().create_timer(CLIENT_READY_RETRY_INTERVAL_SEC).timeout


@rpc("any_peer", "call_remote", "reliable")
func rpc_client_ready(peer_id: int, ready_seq: int, protocol_version: int, world_hash: int) -> void:
	if NetworkManager == null or not NetworkManager.is_server():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	client_ready_received.emit(peer_id, ready_seq, protocol_version, world_hash)


@rpc("authority", "call_remote", "reliable")
func rpc_server_ready_ack(ack_peer_id: int, ready_seq: int, protocol_version: int, spawn_token: int) -> void:
	if NetworkManager == null or NetworkManager.is_server():
		return
	if ready_seq < _client_ready_seq:
		return
	_client_ready_confirmed = true
	_client_ready_retry_active = false
	_expected_spawn_token = spawn_token
	client_ready_acknowledged.emit(ack_peer_id, ready_seq, protocol_version, spawn_token)


@rpc("authority", "call_remote", "reliable")
func rpc_server_request_client_ready() -> void:
	if NetworkManager == null or NetworkManager.is_server():
		return
	send_client_ready()


@rpc("any_peer", "call_remote", "reliable")
func rpc_client_spawn_ack(peer_id: int, spawn_token: int) -> void:
	if NetworkManager == null or not NetworkManager.is_server():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	client_spawn_ack_received.emit(peer_id, spawn_token)


@rpc("authority", "call_remote", "reliable")
func rpc_server_request_spawn_ack(spawn_token: int) -> void:
	if NetworkManager == null or NetworkManager.is_server():
		return
	var local_peer_id: int = NetworkManager.get_local_peer_id()
	if local_peer_id <= 1:
		return
	if spawn_token <= 0:
		return
	send_client_spawn_ack(local_peer_id, spawn_token)
