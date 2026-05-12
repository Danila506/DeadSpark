extends Node

signal server_started
signal connected_to_server
signal connection_failed
signal server_disconnected
signal connection_rejected(reason: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal state_changed(state: int)
signal session_reset
signal lan_host_discovered(ip: String, port: int, host_name: String)
signal net_stats_updated(rtt_ms: float, packet_loss_percent: float)
signal network_tick(tick_delta_sec: float, tick_id: int)

const DEFAULT_MAX_PLAYERS: int = 16
const LAN_DISCOVERY_PORT: int = 24560
const LAN_DISCOVERY_PROTOCOL_VERSION: int = 1

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
var _host_port: int = 2456
var _discovery_listener: PacketPeerUDP
var _discovery_active: bool = false
var _discovery_deadline_ms: int = 0
var _discovery_seen_hosts: Dictionary = {}
var _ping_timer_sec: float = 0.0
var _ping_next_seq: int = 1
var _ping_sent_total: int = 0
var _ping_acked_total: int = 0
var _ping_pending_send_ms: Dictionary = {}
var _rtt_ms: float = -1.0
var _packet_loss_percent: float = 0.0
var _ready_world_peers: Dictionary = {}

const NET_STATS_PING_INTERVAL_SEC: float = 1.0
const NET_STATS_PENDING_TIMEOUT_MS: int = 3500
const NETWORK_TICK_RATE_HZ: int = 30
const NETWORK_TICK_MAX_STEPS_PER_FRAME: int = 5

var _network_tick_accum_sec: float = 0.0
var _network_tick_id: int = 0
var _network_tick_interval_sec: float = 1.0 / float(NETWORK_TICK_RATE_HZ)

func _ready() -> void:
	print("Current platform / OS name: %s" % OS.get_name())
	_ensure_network_signals_connected()
	_start_discovery_listener()
	set_process(true)


func _process(delta: float) -> void:
	_poll_discovery_packets()
	if _discovery_active and Time.get_ticks_msec() >= _discovery_deadline_ms:
		_discovery_active = false
	_emit_network_ticks(delta)
	_update_net_stats(delta)


func _emit_network_ticks(delta: float) -> void:
	if delta <= 0.0:
		return
	_network_tick_accum_sec += delta
	var steps: int = 0
	while _network_tick_accum_sec >= _network_tick_interval_sec and steps < NETWORK_TICK_MAX_STEPS_PER_FRAME:
		_network_tick_accum_sec -= _network_tick_interval_sec
		_network_tick_id += 1
		network_tick.emit(_network_tick_interval_sec, _network_tick_id)
		steps += 1
	if steps >= NETWORK_TICK_MAX_STEPS_PER_FRAME:
		_network_tick_accum_sec = minf(_network_tick_accum_sec, _network_tick_interval_sec)


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
	_host_port = port
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
	_ready_world_peers.clear()
	if clear_last_join_target:
		_last_join_ip = ""
		_last_join_port = 2456
	_reset_net_stats()
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


func mark_peer_world_ready(peer_id: int) -> void:
	if peer_id <= 1:
		return
	_ready_world_peers[peer_id] = true


func clear_peer_world_ready(peer_id: int) -> void:
	if peer_id <= 1:
		return
	_ready_world_peers.erase(peer_id)


func is_peer_world_ready(peer_id: int) -> bool:
	if peer_id == 1:
		return true
	return _ready_world_peers.has(peer_id)


func get_ready_client_peers() -> PackedInt32Array:
	var result: PackedInt32Array = []
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		return result
	for peer_id in multiplayer.get_peers():
		if is_peer_world_ready(peer_id):
			result.append(peer_id)
	return result


func reject_connection(reason: String) -> void:
	_last_error = reason
	connection_rejected.emit(reason)
	disconnect_from_network()


func get_local_ipv4_candidates() -> PackedStringArray:
	var candidates: Array[Dictionary] = []
	var seen: Dictionary = {}

	var interfaces: Array = IP.get_local_interfaces()
	for iface_variant in interfaces:
		if not (iface_variant is Dictionary):
			continue
		var iface: Dictionary = iface_variant as Dictionary
		var iface_name: String = String(iface.get("friendly", iface.get("name", ""))).to_lower()
		var iface_addresses: Array = iface.get("addresses", [])
		var is_virtual_iface: bool = _is_virtual_or_tunnel_interface(iface_name)

		for addr_variant in iface_addresses:
			var address: String = String(addr_variant)
			if not _is_usable_lan_ipv4(address):
				continue
			if seen.has(address):
				continue
			seen[address] = true
			candidates.append({
				"ip": address,
				"priority": _score_ipv4_candidate(address, iface_name, is_virtual_iface)
			})

	# Fallback for platforms where interface metadata is missing.
	if candidates.is_empty():
		for address_variant in IP.get_local_addresses():
			var address: String = String(address_variant)
			if not _is_usable_lan_ipv4(address):
				continue
			if seen.has(address):
				continue
			seen[address] = true
			candidates.append({
				"ip": address,
				"priority": _score_ipv4_candidate(address, "", false)
			})

	var result: PackedStringArray = []
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("priority", 0)) > int(b.get("priority", 0))
	)
	for entry in candidates:
		result.append(String((entry as Dictionary).get("ip", "")))
	return result


func _is_usable_lan_ipv4(address: String) -> bool:
	if address.is_empty():
		return false
	if ":" in address:
		return false
	if address.begins_with("127."):
		return false
	# Skip APIPA addresses; these are usually disconnected adapters.
	if address.begins_with("169.254."):
		return false
	return true


func _is_virtual_or_tunnel_interface(iface_name: String) -> bool:
	if iface_name.is_empty():
		return false
	var virtual_markers: Array[String] = [
		"tun", "tap", "vpn", "virtual", "vbox", "vmware", "hyper-v",
		"wsl", "loopback", "bluetooth", "happ", "hamachi", "tailscale"
	]
	for marker in virtual_markers:
		if iface_name.contains(marker):
			return true
	return false


func _score_ipv4_candidate(address: String, iface_name: String, is_virtual_iface: bool) -> int:
	var score: int = 0
	if is_virtual_iface:
		score -= 1000

	if iface_name.contains("wireless") or iface_name.contains("wi-fi") or iface_name.contains("wlan"):
		score += 120
	elif iface_name.contains("ethernet"):
		score += 90

	var octets: PackedStringArray = address.split(".")
	if octets.size() == 4:
		var a: int = int(octets[0])
		var b: int = int(octets[1])
		# Prefer typical home LAN ranges.
		if a == 192 and b == 168:
			score += 300
		elif a == 10:
			score += 250
		elif a == 172 and b >= 16 and b <= 31:
			score += 120
		# De-prioritize very common virtual defaults.
		if a == 172 and (b == 17 or b == 18 or b == 28):
			score -= 140

	return score


func get_rtt_ms() -> float:
	return _rtt_ms


func get_packet_loss_percent() -> float:
	return _packet_loss_percent


func request_lan_discovery(port_hint: int = 2456, duration_sec: float = 1.2) -> int:
	if port_hint <= 0 or port_hint > 65535:
		_last_error = "Invalid discovery port hint"
		return ERR_INVALID_PARAMETER
	if _discovery_listener == null:
		_last_error = "LAN discovery listener is unavailable"
		return ERR_CANT_CREATE
	_discovery_active = true
	_discovery_deadline_ms = Time.get_ticks_msec() + int(maxf(duration_sec, 0.25) * 1000.0)
	_discovery_seen_hosts.clear()
	var payload: Dictionary = {
		"type": "discover_request",
		"protocol": LAN_DISCOVERY_PROTOCOL_VERSION,
		"port_hint": port_hint
	}
	var data: PackedByteArray = JSON.stringify(payload).to_utf8_buffer()
	_discovery_listener.set_broadcast_enabled(true)
	var destinations: PackedStringArray = _get_lan_broadcast_addresses()
	var sent_any: bool = false
	for dest_ip: String in destinations:
		var dest_result: int = _discovery_listener.set_dest_address(dest_ip, LAN_DISCOVERY_PORT)
		if dest_result != OK:
			continue
		var send_result: int = _discovery_listener.put_packet(data)
		if send_result != OK:
			continue
		sent_any = true
	if not sent_any:
		_last_error = "No discovery packets sent"
		return ERR_CANT_CONNECT
	return OK


func _ensure_network_signals_connected() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if multiplayer.has_signal("server_disconnected") and not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_peer_connected(peer_id: int) -> void:
	print("Peer connected: %d" % peer_id)
	peer_joined.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer disconnected: %d" % peer_id)
	clear_peer_world_ready(peer_id)
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


func _on_server_disconnected() -> void:
	print("Server disconnected")
	_last_error = "Host disconnected"
	reset_session_state(false)
	server_disconnected.emit()


func _update_net_stats(delta: float) -> void:
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		return
	if is_server():
		return
	if _state != NetworkState.IN_GAME:
		return
	if not multiplayer.has_multiplayer_peer() or not multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_ping_timer_sec -= delta
	if _ping_timer_sec <= 0.0:
		_ping_timer_sec = NET_STATS_PING_INTERVAL_SEC
		_send_ping_sample()
	_cleanup_expired_ping_samples()
	_emit_net_stats()


func _send_ping_sample() -> void:
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		return
	var seq: int = _ping_next_seq
	_ping_next_seq += 1
	var now_ms: int = Time.get_ticks_msec()
	_ping_pending_send_ms[seq] = now_ms
	_ping_sent_total += 1
	rpc_id(1, "rpc_ping_request", seq, now_ms)


func _cleanup_expired_ping_samples() -> void:
	if _ping_pending_send_ms.is_empty():
		return
	var now_ms: int = Time.get_ticks_msec()
	var to_remove: Array = []
	for key in _ping_pending_send_ms.keys():
		var seq: int = int(key)
		var sent_ms: int = int(_ping_pending_send_ms.get(seq, now_ms))
		if now_ms - sent_ms >= NET_STATS_PENDING_TIMEOUT_MS:
			to_remove.append(seq)
	for seq in to_remove:
		_ping_pending_send_ms.erase(seq)


func _emit_net_stats() -> void:
	if _ping_sent_total > 0:
		_packet_loss_percent = clampf((1.0 - float(_ping_acked_total) / float(_ping_sent_total)) * 100.0, 0.0, 100.0)
	net_stats_updated.emit(_rtt_ms, _packet_loss_percent)


func _reset_net_stats() -> void:
	_ping_timer_sec = 0.0
	_ping_next_seq = 1
	_ping_sent_total = 0
	_ping_acked_total = 0
	_ping_pending_send_ms.clear()
	_rtt_ms = -1.0
	_packet_loss_percent = 0.0
	net_stats_updated.emit(_rtt_ms, _packet_loss_percent)


@rpc("any_peer", "unreliable")
func rpc_ping_request(seq: int, client_send_ms: int) -> void:
	if not is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	rpc_id(sender_id, "rpc_ping_response", seq, client_send_ms, Time.get_ticks_msec())


@rpc("any_peer", "unreliable")
func rpc_ping_response(seq: int, client_send_ms: int, _server_recv_ms: int) -> void:
	if is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 1:
		return
	if not _ping_pending_send_ms.has(seq):
		return
	var now_ms: int = Time.get_ticks_msec()
	var sent_ms: int = int(_ping_pending_send_ms.get(seq, client_send_ms))
	_ping_pending_send_ms.erase(seq)
	_ping_acked_total += 1
	_rtt_ms = float(max(now_ms - sent_ms, 0))
	_emit_net_stats()


func _start_discovery_listener() -> void:
	_discovery_listener = PacketPeerUDP.new()
	var listen_result: int = _discovery_listener.bind(LAN_DISCOVERY_PORT, "*")
	if listen_result != OK:
		push_warning("LAN discovery listener bind failed on %d: %d" % [LAN_DISCOVERY_PORT, listen_result])
		_discovery_listener = null


func _poll_discovery_packets() -> void:
	if _discovery_listener == null:
		return
	while _discovery_listener.get_available_packet_count() > 0:
		var packet: PackedByteArray = _discovery_listener.get_packet()
		var from_ip: String = _discovery_listener.get_packet_ip()
		var from_port: int = _discovery_listener.get_packet_port()
		_handle_discovery_packet(packet, from_ip, from_port)


func _handle_discovery_packet(packet: PackedByteArray, from_ip: String, from_port: int) -> void:
	if packet.is_empty():
		return
	var raw_payload: String = packet.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(raw_payload)
	if not (parsed is Dictionary):
		return
	var payload: Dictionary = parsed as Dictionary
	var packet_type: String = String(payload.get("type", ""))
	if packet_type == "discover_request":
		_handle_discovery_request(from_ip, from_port)
		return
	if packet_type == "discover_response":
		_handle_discovery_response(payload, from_ip)


func _handle_discovery_request(from_ip: String, from_port: int) -> void:
	if not is_server():
		return
	if from_port <= 0:
		return
	var response: Dictionary = {
		"type": "discover_response",
		"protocol": LAN_DISCOVERY_PROTOCOL_VERSION,
		"port": _host_port,
		"host_name": OS.get_name()
	}
	var data: PackedByteArray = JSON.stringify(response).to_utf8_buffer()
	var responder: PacketPeerUDP = PacketPeerUDP.new()
	if responder.set_dest_address(from_ip, from_port) != OK:
		return
	responder.put_packet(data)


func _handle_discovery_response(payload: Dictionary, from_ip: String) -> void:
	var protocol_version: int = int(payload.get("protocol", 0))
	if protocol_version != LAN_DISCOVERY_PROTOCOL_VERSION:
		return
	var port: int = int(payload.get("port", 0))
	if port <= 0 or port > 65535:
		return
	var host_name: String = String(payload.get("host_name", "LAN Host"))
	var ip: String = from_ip
	var key: String = "%s:%d" % [ip, port]
	if _discovery_seen_hosts.has(key):
		return
	_discovery_seen_hosts[key] = true
	lan_host_discovered.emit(ip, port, host_name)


func _get_lan_broadcast_addresses() -> PackedStringArray:
	var result: PackedStringArray = ["255.255.255.255"]
	for local_ip: String in get_local_ipv4_candidates():
		var octets: PackedStringArray = local_ip.split(".")
		if octets.size() != 4:
			continue
		var broadcast_ip: String = "%s.%s.%s.255" % [octets[0], octets[1], octets[2]]
		if not result.has(broadcast_ip):
			result.append(broadcast_ip)
	return result


func _set_state(next_state: int) -> void:
	if _state == next_state:
		return
	_state = next_state
	state_changed.emit(_state)
