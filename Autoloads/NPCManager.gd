extends Node

signal npc_registered(npc_id: StringName, npc: Node)
signal npc_unregistered(npc_id: StringName)
signal active_dialogue_changed(npc_id: StringName)

const DIALOGUE_PANEL_SCENE: PackedScene = preload("res://gui/NPCDialoguePanel.tscn")
const MAX_INTERACTION_REQUEST_DISTANCE: float = 160.0

var _npcs: Dictionary = {}
var _dialogue_layer: CanvasLayer
var _dialogue_panel: NPCDialoguePanel
var _active_npc_id: StringName = &""


func _ready() -> void:
	_ensure_dialogue_ui()


func register_npc(npc: Node) -> bool:
	if npc == null or not npc.has_method("get_npc_id"):
		return false
	var npc_id := StringName(String(npc.call("get_npc_id")).strip_edges())
	if npc_id == &"":
		push_error("NPCManager: NPC registration requires a stable npc_id")
		return false
	var existing: Node = get_npc(npc_id)
	if existing != null and existing != npc:
		push_error("NPCManager: duplicate npc_id '%s'" % npc_id)
		return false
	_npcs[npc_id] = weakref(npc)
	npc_registered.emit(npc_id, npc)
	return true


func unregister_npc(npc: Node) -> void:
	if npc == null or not npc.has_method("get_npc_id"):
		return
	var npc_id := StringName(npc.call("get_npc_id"))
	var existing := get_npc(npc_id)
	if existing != npc:
		return
	_npcs.erase(npc_id)
	if _active_npc_id == npc_id:
		_close_active_dialogue()
	npc_unregistered.emit(npc_id)


func get_npc(npc_id: StringName) -> Node:
	var reference: Variant = _npcs.get(npc_id)
	if not (reference is WeakRef):
		return null
	var npc: Variant = (reference as WeakRef).get_ref()
	if npc is Node and is_instance_valid(npc):
		return npc as Node
	_npcs.erase(npc_id)
	return null


func get_registered_npc_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for raw_id in _npcs.keys():
		var npc_id := StringName(raw_id)
		if get_npc(npc_id) != null:
			result.append(npc_id)
	return result


func is_dialogue_open() -> bool:
	return (
		_active_npc_id != &""
		and _dialogue_panel != null
		and is_instance_valid(_dialogue_panel)
		and _dialogue_panel.visible
	)


func request_interaction(npc_id: StringName, interactor: Node) -> bool:
	if _is_networked() and not NetworkManager.is_server():
		rpc_id(1, "rpc_request_npc_interaction", String(npc_id))
		return true
	var peer_id: int = _resolve_interactor_peer_id(interactor)
	return _open_server_authorized_dialogue(npc_id, interactor, peer_id)


func request_dialogue_action(action: StringName) -> void:
	if _active_npc_id == &"":
		return
	if _is_networked() and not NetworkManager.is_server():
		rpc_id(1, "rpc_request_npc_dialogue_action", String(_active_npc_id), String(action))
		return
	var interactor := _find_player_for_peer(_local_peer_id())
	var payload := _build_action_payload(_active_npc_id, action, interactor, _local_peer_id())
	if not payload.is_empty():
		_show_dialogue_payload(_active_npc_id, payload)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_npc_interaction(raw_npc_id: String) -> void:
	if not _is_networked() or not NetworkManager.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var interactor := _find_player_for_peer(peer_id)
	_open_server_authorized_dialogue(StringName(raw_npc_id), interactor, peer_id)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_npc_dialogue_action(raw_npc_id: String, raw_action: String) -> void:
	if not _is_networked() or not NetworkManager.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var interactor := _find_player_for_peer(peer_id)
	var npc_id := StringName(raw_npc_id)
	if not _is_valid_interaction(get_npc(npc_id), interactor):
		return
	var payload := _build_action_payload(npc_id, StringName(raw_action), interactor, peer_id)
	if not payload.is_empty():
		rpc_id(peer_id, "rpc_receive_npc_dialogue", raw_npc_id, payload)


@rpc("any_peer", "call_remote", "reliable")
func rpc_end_npc_dialogue(raw_npc_id: String) -> void:
	if not _is_networked() or not NetworkManager.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var npc := get_npc(StringName(raw_npc_id))
	if npc != null and npc.has_method("end_talk"):
		npc.call("end_talk", peer_id)


@rpc("authority", "call_remote", "reliable")
func rpc_receive_npc_dialogue(raw_npc_id: String, payload: Dictionary) -> void:
	if not _is_networked() or NetworkManager.is_server():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	_show_dialogue_payload(StringName(raw_npc_id), payload)


func _open_server_authorized_dialogue(npc_id: StringName, interactor: Node, peer_id: int) -> bool:
	var npc := get_npc(npc_id)
	if not _is_valid_interaction(npc, interactor):
		return false
	var payload: Dictionary = npc.call("build_dialogue_payload", peer_id, &"greeting")
	if payload.is_empty():
		return false
	if npc.has_method("begin_talk"):
		npc.call("begin_talk", interactor, peer_id)
	if _is_networked() and peer_id != 1:
		rpc_id(peer_id, "rpc_receive_npc_dialogue", String(npc_id), payload)
	else:
		_show_dialogue_payload(npc_id, payload)
	return true


func _build_action_payload(npc_id: StringName, action: StringName, interactor: Node, peer_id: int) -> Dictionary:
	var npc := get_npc(npc_id)
	if not _is_valid_interaction(npc, interactor):
		return {}
	if not npc.has_method("build_dialogue_payload"):
		return {}
	return npc.call("build_dialogue_payload", peer_id, action) as Dictionary


func _is_valid_interaction(npc: Node, interactor: Node) -> bool:
	if npc == null or interactor == null:
		return false
	if not (npc is Node2D) or not (interactor is Node2D):
		return false
	if not interactor.is_in_group(&"player"):
		return false
	var allowed_distance := MAX_INTERACTION_REQUEST_DISTANCE
	if npc.has_method("get_interaction_distance"):
		allowed_distance = minf(float(npc.call("get_interaction_distance")), MAX_INTERACTION_REQUEST_DISTANCE)
	return (npc as Node2D).global_position.distance_to((interactor as Node2D).global_position) <= allowed_distance


func _show_dialogue_payload(npc_id: StringName, payload: Dictionary) -> void:
	_ensure_dialogue_ui()
	_active_npc_id = npc_id
	_dialogue_panel.show_payload(payload)
	active_dialogue_changed.emit(npc_id)


func _close_active_dialogue() -> void:
	var previous_id := _active_npc_id
	_active_npc_id = &""
	if _dialogue_panel != null:
		_dialogue_panel.hide()
	var npc := get_npc(previous_id)
	if _is_networked() and not NetworkManager.is_server() and previous_id != &"":
		rpc_id(1, "rpc_end_npc_dialogue", String(previous_id))
	elif npc != null and npc.has_method("end_talk"):
		npc.call("end_talk", _local_peer_id())
	active_dialogue_changed.emit(&"")


func _ensure_dialogue_ui() -> void:
	if _dialogue_panel != null and is_instance_valid(_dialogue_panel):
		return
	_dialogue_layer = CanvasLayer.new()
	_dialogue_layer.name = "NPCDialogueLayer"
	_dialogue_layer.layer = 90
	add_child(_dialogue_layer)
	_dialogue_panel = DIALOGUE_PANEL_SCENE.instantiate() as NPCDialoguePanel
	_dialogue_layer.add_child(_dialogue_panel)
	_dialogue_panel.action_requested.connect(request_dialogue_action)
	_dialogue_panel.dialogue_closed.connect(_close_active_dialogue)


func _resolve_interactor_peer_id(interactor: Node) -> int:
	if interactor != null and "peer_id" in interactor:
		return maxi(int(interactor.get("peer_id")), 1)
	return _local_peer_id()


func _local_peer_id() -> int:
	if _is_networked():
		return multiplayer.get_unique_id()
	return 1


func _find_player_for_peer(peer_id: int) -> Node:
	for candidate in get_tree().get_nodes_in_group(&"player"):
		if candidate == null or not is_instance_valid(candidate):
			continue
		if "peer_id" in candidate and int(candidate.get("peer_id")) == peer_id:
			return candidate
		if not _is_networked() and peer_id == 1:
			return candidate
	return null


func _is_networked() -> bool:
	return multiplayer != null and multiplayer.multiplayer_peer != null and NetworkManager != null
