extends Node

const SAVE_FILE_PATH: String = "user://savegame.json"
const SAVE_SCHEMA_VERSION: int = 2
const FALLBACK_LEVEL_PATH: String = "res://level.tscn"
const MENU_SCENE_PATH: String = "res://Menu/Menu.tscn"
const ITEM_INSTANCE_SCRIPT = preload("res://items/scripts/item_instance.gd")
const PICKUP_ITEM_SCENE: PackedScene = preload("res://items/scenes/pickup_item.tscn")

var _has_pending_load: bool = false
var _pending_world_nodes: Dictionary = {}
var _pending_world_pickups: Array = []


func _ready() -> void:
	if not get_tree().scene_changed.is_connected(_on_scene_changed):
		get_tree().scene_changed.connect(_on_scene_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game_if_possible()


func save_game(path: String = SAVE_FILE_PATH) -> int:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return ERR_UNCONFIGURED

	var scene_path: String = scene_root.scene_file_path
	if scene_path.is_empty():
		scene_path = FALLBACK_LEVEL_PATH

	var save_payload: Dictionary = {
		"schema_version": SAVE_SCHEMA_VERSION,
		"scene_path": scene_path,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"inventory": InventoryManager.get_save_data() if InventoryManager != null and InventoryManager.has_method("get_save_data") else {},
		"world_nodes": _collect_world_nodes_save_data(scene_root),
		"world_pickups": _collect_world_pickups(scene_root)
	}

	return _write_json_file(path, save_payload)


func save_game_if_possible(path: String = SAVE_FILE_PATH) -> int:
	if not _is_gameplay_context():
		return ERR_UNCONFIGURED
	return save_game(path)


func load_game(path: String = SAVE_FILE_PATH) -> int:
	var save_payload_result: Variant = _read_json_file(path)
	if save_payload_result is int:
		return int(save_payload_result)
	if not (save_payload_result is Dictionary):
		return ERR_PARSE_ERROR

	var save_payload: Dictionary = save_payload_result as Dictionary
	var scene_path: String = String(save_payload.get("scene_path", FALLBACK_LEVEL_PATH))
	if scene_path.is_empty():
		scene_path = FALLBACK_LEVEL_PATH
	if not ResourceLoader.exists(scene_path):
		return ERR_FILE_NOT_FOUND

	var schema_version: int = int(save_payload.get("schema_version", 0))
	var has_runtime_state: bool = schema_version == SAVE_SCHEMA_VERSION
	if has_runtime_state:
		_queue_runtime_state(save_payload)

	var current_scene_path: String = ""
	var current_scene: Node = get_tree().current_scene
	if current_scene != null:
		current_scene_path = current_scene.scene_file_path

	if current_scene_path == scene_path:
		if has_runtime_state:
			call_deferred("_apply_pending_runtime_state")
		return OK

	get_tree().change_scene_to_file(scene_path)
	return OK


func register_persistent_node(node: Node) -> void:
	if not _has_pending_load:
		return
	_apply_state_to_node(node)


func serialize_item(item: ItemData) -> Dictionary:
	if item == null:
		return {}
	if item.has_method("to_save_dict"):
		return item.to_save_dict()

	var runtime_copy: ItemData = item.create_instance(item.stack_count, item.endurance) if item.has_method("create_instance") else null
	if runtime_copy != null and runtime_copy.has_method("to_save_dict"):
		runtime_copy.runtime_storage_items = item.runtime_storage_items.duplicate(true)
		if InventoryManager != null and InventoryManager.has_method("copy_runtime_state"):
			InventoryManager.copy_runtime_state(item, runtime_copy)
		return runtime_copy.to_save_dict()

	return {
		"runtime_id": str(item.get_instance_id()),
		"definition_path": item.resource_path,
		"stack_count": int(item.stack_count),
		"endurance": int(item.endurance),
		"runtime_storage_items": [],
		"weapon_runtime_state": {}
	}


func deserialize_item(raw_item: Variant) -> ItemData:
	if not (raw_item is Dictionary):
		return null
	return ITEM_INSTANCE_SCRIPT.from_save_dict(raw_item as Dictionary)


func _queue_runtime_state(save_payload: Dictionary) -> void:
	_pending_world_nodes = save_payload.get("world_nodes", {}).duplicate(true)
	_pending_world_pickups = save_payload.get("world_pickups", []).duplicate(true)
	_has_pending_load = true

	var inventory_payload: Dictionary = save_payload.get("inventory", {})
	if InventoryManager != null and InventoryManager.has_method("apply_save_data") and inventory_payload is Dictionary:
		InventoryManager.apply_save_data(inventory_payload)


func _on_scene_changed() -> void:
	if not _has_pending_load:
		return
	call_deferred("_apply_pending_runtime_state")


func _apply_pending_runtime_state() -> void:
	if not _has_pending_load:
		return

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return

	var persistent_nodes: Array[Node] = _collect_persistent_nodes(scene_root)
	for node in persistent_nodes:
		_apply_state_to_node(node)

	_restore_world_pickups(scene_root)
	_pending_world_nodes.clear()
	_pending_world_pickups.clear()
	_has_pending_load = false


func _apply_state_to_node(node: Node) -> void:
	if node == null:
		return
	if not node.has_method("get_save_key"):
		return
	if not node.has_method("apply_save_data"):
		return

	var save_key: String = String(node.call("get_save_key"))
	if save_key.is_empty():
		return
	var matched_key: String = save_key
	if not _pending_world_nodes.has(matched_key):
		if node.has_method("get_legacy_save_keys"):
			var legacy_keys: Variant = node.call("get_legacy_save_keys")
			if legacy_keys is Array:
				for legacy_key_variant in legacy_keys:
					var legacy_key: String = String(legacy_key_variant)
					if legacy_key.is_empty():
						continue
					if _pending_world_nodes.has(legacy_key):
						matched_key = legacy_key
						break
		if not _pending_world_nodes.has(matched_key):
			return

	var save_data: Variant = _pending_world_nodes.get(matched_key, {})
	if save_data is Dictionary:
		node.call("apply_save_data", save_data as Dictionary)
	_pending_world_nodes.erase(matched_key)


func _collect_world_nodes_save_data(scene_root: Node) -> Dictionary:
	var result: Dictionary = {}
	for node in _collect_persistent_nodes(scene_root):
		var save_key: String = String(node.call("get_save_key"))
		if save_key.is_empty():
			continue
		var save_data: Variant = node.call("get_save_data")
		if not (save_data is Dictionary):
			continue
		result[save_key] = (save_data as Dictionary).duplicate(true)
	return result


func _collect_persistent_nodes(scene_root: Node) -> Array[Node]:
	var result: Array[Node] = []
	var stack: Array[Node] = [scene_root]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current != scene_root and current.has_method("get_save_key") and current.has_method("get_save_data"):
			result.append(current)
		for child in current.get_children():
			if child is Node:
				stack.append(child)
	return result


func _collect_world_pickups(scene_root: Node) -> Array:
	var result: Array = []
	var pickups: Array = get_tree().get_nodes_in_group("world_pickup")
	for pickup in pickups:
		if not (pickup is Node):
			continue
		var pickup_node: Node = pickup as Node
		if not scene_root.is_ancestor_of(pickup_node):
			continue
		if not ("item_data" in pickup_node):
			continue

		var item: ItemData = pickup_node.item_data as ItemData
		if item == null:
			continue

		var position: Vector2 = Vector2.ZERO
		if pickup_node is Node2D:
			position = (pickup_node as Node2D).global_position
		var parent_node: Node = pickup_node.get_parent()
		var parent_path: String = str(scene_root.get_path_to(parent_node)) if parent_node != null else "."
		result.append({
			"item": serialize_item(item),
			"position": {"x": position.x, "y": position.y},
			"parent_path": parent_path
		})
	return result


func _restore_world_pickups(scene_root: Node) -> void:
	var pickups: Array = get_tree().get_nodes_in_group("world_pickup")
	for pickup in pickups:
		if not (pickup is Node):
			continue
		var pickup_node: Node = pickup as Node
		if not scene_root.is_ancestor_of(pickup_node):
			continue
		if pickup_node.has_method("remove_from_world"):
			pickup_node.call("remove_from_world")
		else:
			pickup_node.queue_free()

	for raw_pickup in _pending_world_pickups:
		if not (raw_pickup is Dictionary):
			continue
		var pickup_data: Dictionary = raw_pickup as Dictionary
		var item: ItemData = deserialize_item(pickup_data.get("item", {}))
		if item == null:
			continue

		var parent_path: String = String(pickup_data.get("parent_path", "."))
		var parent_node: Node = scene_root.get_node_or_null(NodePath(parent_path))
		if parent_node == null:
			parent_node = scene_root

		var pickup_instance: Node = PICKUP_ITEM_SCENE.instantiate()
		parent_node.add_child(pickup_instance)
		if pickup_instance.has_method("setup_from_item_data"):
			pickup_instance.call("setup_from_item_data", item)
		elif "item_data" in pickup_instance:
			pickup_instance.item_data = item

		if pickup_instance is Node2D:
			var pos_dict: Dictionary = pickup_data.get("position", {})
			(pickup_instance as Node2D).global_position = Vector2(
				float(pos_dict.get("x", 0.0)),
				float(pos_dict.get("y", 0.0))
			)


func _write_json_file(path: String, payload: Dictionary) -> int:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	return OK


func _read_json_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()

	var raw_json: String = file.get_as_text()
	if raw_json.is_empty():
		return ERR_PARSE_ERROR

	var parsed: Variant = JSON.parse_string(raw_json)
	if parsed is Dictionary:
		return parsed
	return ERR_PARSE_ERROR


func _is_gameplay_context() -> bool:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return false
	if scene_root.scene_file_path == MENU_SCENE_PATH:
		return false
	return get_tree().get_first_node_in_group("player") != null
