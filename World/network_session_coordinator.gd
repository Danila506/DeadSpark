class_name NetworkSessionCoordinator
extends RefCounted

enum PeerSessionPhase {
	CONNECTED,
	WORLD_LOADING,
	WORLD_READY_CONFIRMED,
	PLAYER_SPAWNED,
	ACTIVE
}

var _peer_session_phase: Dictionary = {}
var _peer_join_time_sec: Dictionary = {}
var _peer_ready_watchdog_elapsed_sec: Dictionary = {}
var _peer_spawn_acknowledged: Dictionary = {}
var _peer_spawn_watchdog_elapsed_sec: Dictionary = {}


func on_peer_joined(peer_id: int, now_sec: float) -> void:
	_peer_join_time_sec[peer_id] = now_sec
	_peer_ready_watchdog_elapsed_sec[peer_id] = 0.0
	_peer_spawn_acknowledged[peer_id] = false
	_peer_spawn_watchdog_elapsed_sec[peer_id] = 0.0
	set_phase(peer_id, PeerSessionPhase.WORLD_LOADING)


func on_peer_ready_acked(peer_id: int) -> void:
	_peer_ready_watchdog_elapsed_sec.erase(peer_id)
	_peer_spawn_acknowledged[peer_id] = false
	_peer_spawn_watchdog_elapsed_sec[peer_id] = 0.0
	set_phase(peer_id, PeerSessionPhase.WORLD_READY_CONFIRMED)


func on_peer_spawned(peer_id: int) -> void:
	set_phase(peer_id, PeerSessionPhase.PLAYER_SPAWNED)


func on_peer_active(peer_id: int) -> void:
	_peer_spawn_acknowledged[peer_id] = true
	_peer_spawn_watchdog_elapsed_sec.erase(peer_id)
	set_phase(peer_id, PeerSessionPhase.ACTIVE)


func clear_peer(peer_id: int) -> void:
	_peer_session_phase.erase(peer_id)
	_peer_join_time_sec.erase(peer_id)
	_peer_ready_watchdog_elapsed_sec.erase(peer_id)
	_peer_spawn_acknowledged.erase(peer_id)
	_peer_spawn_watchdog_elapsed_sec.erase(peer_id)


func clear_all() -> void:
	_peer_session_phase.clear()
	_peer_join_time_sec.clear()
	_peer_ready_watchdog_elapsed_sec.clear()
	_peer_spawn_acknowledged.clear()
	_peer_spawn_watchdog_elapsed_sec.clear()


func set_phase(peer_id: int, phase: int) -> bool:
	if peer_id <= 0:
		return false
	var previous: int = int(_peer_session_phase.get(peer_id, -1))
	if previous == phase:
		return false
	_peer_session_phase[peer_id] = phase
	return true


func get_phase_name(phase: int) -> String:
	match phase:
		PeerSessionPhase.CONNECTED:
			return "CONNECTED"
		PeerSessionPhase.WORLD_LOADING:
			return "WORLD_LOADING"
		PeerSessionPhase.WORLD_READY_CONFIRMED:
			return "WORLD_READY_CONFIRMED"
		PeerSessionPhase.PLAYER_SPAWNED:
			return "PLAYER_SPAWNED"
		PeerSessionPhase.ACTIVE:
			return "ACTIVE"
		_:
			return "UNKNOWN"


func accumulate_ready_watchdog(
	delta: float,
	now_sec: float,
	is_peer_world_ready_cb: Callable,
	retry_interval_sec: float,
	timeout_sec: float
) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	for peer_id_variant: Variant in _peer_ready_watchdog_elapsed_sec.keys():
		var peer_id: int = int(peer_id_variant)
		if bool(is_peer_world_ready_cb.call(peer_id)):
			continue
		var next_elapsed: float = float(_peer_ready_watchdog_elapsed_sec.get(peer_id, 0.0)) + maxf(delta, 0.0)
		_peer_ready_watchdog_elapsed_sec[peer_id] = next_elapsed
		if next_elapsed >= retry_interval_sec:
			_peer_ready_watchdog_elapsed_sec[peer_id] = 0.0
			actions.append({"kind": "request_ready", "peer_id": peer_id})
		var joined_at: float = float(_peer_join_time_sec.get(peer_id, now_sec))
		var age_sec: float = now_sec - joined_at
		if age_sec >= timeout_sec:
			actions.append({"kind": "ready_timeout", "peer_id": peer_id, "age_sec": age_sec})
			_peer_join_time_sec[peer_id] = now_sec - (timeout_sec - 1.0)
	return actions


func accumulate_spawn_ack_watchdog(
	delta: float,
	now_sec: float,
	is_peer_world_ready_cb: Callable,
	has_player_cb: Callable,
	retry_interval_sec: float,
	timeout_sec: float
) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	for peer_id_variant: Variant in _peer_spawn_acknowledged.keys():
		var peer_id: int = int(peer_id_variant)
		if bool(_peer_spawn_acknowledged.get(peer_id, false)):
			continue
		if not bool(is_peer_world_ready_cb.call(peer_id)):
			continue
		if not bool(has_player_cb.call(peer_id)):
			continue
		var elapsed: float = float(_peer_spawn_watchdog_elapsed_sec.get(peer_id, 0.0)) + maxf(delta, 0.0)
		_peer_spawn_watchdog_elapsed_sec[peer_id] = elapsed
		if elapsed >= retry_interval_sec:
			_peer_spawn_watchdog_elapsed_sec[peer_id] = 0.0
			actions.append({"kind": "request_spawn_ack", "peer_id": peer_id})
		var joined_at: float = float(_peer_join_time_sec.get(peer_id, now_sec))
		var age_sec: float = now_sec - joined_at
		if age_sec >= timeout_sec:
			actions.append({"kind": "spawn_timeout", "peer_id": peer_id, "age_sec": age_sec})
			_peer_join_time_sec[peer_id] = now_sec - (timeout_sec - 1.0)
	return actions
