extends Area2D

@export var item_data: ItemData
@export var world_sprite_scale: Vector2 = Vector2(1, 1)

const BELOW_PLAYER_Z_INDEX: int = -1
const NETWORK_PICKUP_DISTANCE_MAX: float = 96.0

var player_in_range: bool = false
var _network_pickup_locked: bool = false
var _removed_from_world: bool = false

@onready var sprite: Sprite2D = $Sprite2D

var prompt_label: Label = null

signal network_pickup_result(accepted: bool)


func _ready() -> void:
	add_to_group("world_pickup")
	add_to_group("bullet_passthrough")
	_apply_render_order()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_ensure_prompt_label()

	if item_data != null:
		sprite.texture = item_data.world_icon
		sprite.scale = world_sprite_scale * max(item_data.world_icon_scale, 0.1)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	player_in_range = true
	NearbyItemsManager.add_item(self)
	_update_prompt_visibility()


func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	player_in_range = false
	NearbyItemsManager.remove_item(self)
	_update_prompt_visibility()


func remove_from_world() -> void:
	if _removed_from_world:
		return
	_removed_from_world = true
	NearbyItemsManager.remove_item(self)
	queue_free()
	
func setup_from_item_data(data: ItemData) -> void:
	item_data = data

	if sprite == null:
		sprite = $Sprite2D

	_apply_render_order()

	if item_data != null:
		sprite.texture = item_data.world_icon
		sprite.scale = world_sprite_scale * max(item_data.world_icon_scale, 0.1)
	_update_prompt_visibility()


func _apply_render_order() -> void:
	z_index = BELOW_PLAYER_Z_INDEX


func _ensure_prompt_label() -> void:
	if prompt_label != null:
		return

	prompt_label = Label.new()
	prompt_label.text = _get_prompt_text()
	prompt_label.position = Vector2(-10.0, -20.0)
	prompt_label.visible = false
	prompt_label.z_index = 10
	prompt_label.add_theme_color_override("font_color", Color(0.0, 0.35, 0.0))
	prompt_label.add_theme_font_size_override("font_size", 9)
	add_child(prompt_label)


func _update_prompt_visibility() -> void:
	if prompt_label == null:
		return

	prompt_label.text = _get_prompt_text()
	prompt_label.visible = player_in_range


func _get_prompt_text() -> String:
	if item_data != null and not item_data.item_name.strip_edges().is_empty():
		return item_data.item_name
	return "Предмет"


@rpc("any_peer", "reliable")
func rpc_request_pickup_authorization(requester_peer_id: int) -> void:
	if _network_pickup_locked or _removed_from_world:
		return
	if NetworkManager == null or not NetworkManager.is_server():
		return
	if requester_peer_id <= 0:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != requester_peer_id:
		return
	_authorize_pickup_for_peer(requester_peer_id)


func authorize_pickup_locally(requester_peer_id: int) -> void:
	if _network_pickup_locked or _removed_from_world:
		return
	if NetworkManager == null or not NetworkManager.is_server():
		return
	if requester_peer_id <= 0:
		return
	_authorize_pickup_for_peer(requester_peer_id)


func _authorize_pickup_for_peer(requester_peer_id: int) -> void:
	if _removed_from_world:
		return
	var granted: bool = _can_authorize_pickup_for_peer(requester_peer_id)
	if granted:
		_network_pickup_locked = true
		_request_global_despawn()
	rpc("rpc_finalize_pickup_authorization", requester_peer_id, granted)


@rpc("any_peer", "call_local", "reliable")
func rpc_finalize_pickup_authorization(requester_peer_id: int, granted: bool) -> void:
	if granted:
		_remove_pickups_with_same_runtime_id()
	if NetworkManager != null and requester_peer_id == NetworkManager.get_local_peer_id():
		network_pickup_result.emit(granted)


func _can_authorize_pickup_for_peer(peer_id: int) -> bool:
	if item_data == null:
		return false
	var player_node: Node2D = _find_player_by_peer_id(peer_id)
	if player_node == null:
		return false
	return player_node.global_position.distance_to(global_position) <= NETWORK_PICKUP_DISTANCE_MAX


func _find_player_by_peer_id(peer_id: int) -> Node2D:
	var scene_tree: SceneTree = get_tree()
	if scene_tree == null:
		return null
	for node_variant: Variant in scene_tree.get_nodes_in_group("player"):
		var node: Node = node_variant as Node
		if node == null or not is_instance_valid(node):
			continue
		if not (node is Node2D):
			continue
		if int(node.get("peer_id")) == peer_id:
			return node as Node2D
	return null


func _remove_pickups_with_same_runtime_id() -> void:
	var runtime_id: String = ""
	if item_data != null:
		runtime_id = String(item_data.get("runtime_id"))
	if runtime_id.is_empty():
		remove_from_world()
		return
	var scene_tree: SceneTree = get_tree()
	if scene_tree == null:
		remove_from_world()
		return
	for node_variant: Variant in scene_tree.get_nodes_in_group("world_pickup"):
		var pickup_node: Node = node_variant as Node
		if pickup_node == null or not is_instance_valid(pickup_node):
			continue
		var pickup_item: ItemData = pickup_node.get("item_data") as ItemData
		if pickup_item == null:
			continue
		if String(pickup_item.get("runtime_id")) != runtime_id:
			continue
		if pickup_node.has_method("remove_from_world"):
			pickup_node.call("remove_from_world")
		else:
			pickup_node.queue_free()


func _request_global_despawn() -> void:
	if item_data == null:
		return
	var runtime_id: String = String(item_data.get("runtime_id")).strip_edges()
	if runtime_id.is_empty():
		return
	var scene_tree: SceneTree = get_tree()
	if scene_tree == null:
		return
	for node_variant: Variant in scene_tree.get_nodes_in_group("item_spawner_network"):
		var spawner: Node = node_variant as Node
		if spawner == null or not is_instance_valid(spawner):
			continue
		if spawner.has_method("request_network_despawn_by_runtime_id"):
			spawner.call("request_network_despawn_by_runtime_id", runtime_id)
			return
