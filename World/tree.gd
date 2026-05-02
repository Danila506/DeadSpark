extends Node2D

const AXE_CHOPPABLE_GROUP: StringName = &"axe_choppable"

@onready var outline_sprite: Sprite2D = $OutlineSprite
@onready var normal_sprite: Sprite2D = $NormalSprite
@onready var felled_sprite: Sprite2D = $FelledTree
@onready var interact_area: Area2D = $Area2D
@onready var interact_label: Label = $InteractLabel
@onready var trunk_body: StaticBody2D = $StaticBody2D

@export var hits_to_chop: int = 3
@export var chop_duration: float = 1.4
@export var pickup_scene: PackedScene = preload("res://items/scenes/pickup_item.tscn")
@export var wood_item_data: ItemData = preload("res://Resources/Misc/wood.tres")
@export var wood_drop_count: int = 1
@export var wood_drop_spread_radius: float = 12.0
@export var interaction_radius_px: float = 86.0
@export var persistent_id: String = ""
@export var required_axe_item_names: Array[String] = ["Топор"]

var player_in_range: bool = false
var chop_hits: int = 0
var is_felled: bool = false


func _ready() -> void:
	add_to_group("secondary_interactable")
	add_to_group(AXE_CHOPPABLE_GROUP)
	set_process(false)
	if felled_sprite != null:
		felled_sprite.visible = false
	if normal_sprite != null:
		normal_sprite.visible = true
	if trunk_body != null:
		trunk_body.add_to_group("bullet_passthrough")
	interact_area.body_entered.connect(_on_area_body_entered)
	interact_area.body_exited.connect(_on_area_body_exited)
	_update_visual_state()
	if GameSaveManager != null and GameSaveManager.has_method("register_persistent_node"):
		GameSaveManager.register_persistent_node(self)


func _on_area_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	player_in_range = true
	_connect_equipment_signal()
	_update_visual_state()


func _on_area_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	player_in_range = false
	_disconnect_equipment_signal()
	_update_visual_state()


func _update_visual_state() -> void:
	if is_felled:
		outline_sprite.visible = false
		interact_label.visible = false
		return

	var can_interact: bool = _is_player_ready_to_interact() and _can_show_interact_label()
	outline_sprite.visible = can_interact
	interact_label.visible = can_interact


func _can_show_interact_label() -> bool:
	if is_felled:
		return false

	if InventoryManager == null or not InventoryManager.has_method("get_active_weapon_item"):
		return false

	var active_weapon: ItemData = InventoryManager.get_active_weapon_item()
	return _is_axe_item(active_weapon)


func _on_equipment_changed(_slot_type: int, _item: ItemData) -> void:
	_update_visual_state()


func _connect_equipment_signal() -> void:
	if InventoryManager == null or not InventoryManager.has_signal("equipment_changed"):
		return
	if not InventoryManager.equipment_changed.is_connected(_on_equipment_changed):
		InventoryManager.equipment_changed.connect(_on_equipment_changed)


func _disconnect_equipment_signal() -> void:
	if InventoryManager == null or not InventoryManager.has_signal("equipment_changed"):
		return
	if InventoryManager.equipment_changed.is_connected(_on_equipment_changed):
		InventoryManager.equipment_changed.disconnect(_on_equipment_changed)


func handle_secondary_interaction(interactor: Node) -> bool:
	if is_felled:
		return false
	if not _can_show_interact_label():
		return false
	if interactor == null or not interactor.is_in_group("player"):
		return false
	if interactor is Node2D:
		var interactor_pos := (interactor as Node2D).global_position
		if not player_in_range and interactor_pos.distance_to(global_position) > interaction_radius_px:
			return false
	elif not player_in_range:
		return false
	if interactor.has_method("start_timed_action"):
		return bool(interactor.start_timed_action(chop_duration, Callable(self, "_finish_chop"), "Рубка"))
	return false


func _is_player_ready_to_interact() -> bool:
	return player_in_range


func _finish_chop() -> void:
	if is_felled:
		return
	_apply_chop_hit()


func take_damage_from(_damage: float, _source: Node = null, _hit_context: Dictionary = {}) -> void:
	if is_felled:
		return
	if not _is_active_axe_equipped():
		return
	_apply_chop_hit()


func _apply_chop_hit() -> void:
	chop_hits += 1
	if chop_hits < max(hits_to_chop, 1):
		_persist_generation_state()
		return

	_drop_wood()
	_set_felled_state()
	_persist_generation_state()


func _is_active_axe_equipped() -> bool:
	if InventoryManager == null or not InventoryManager.has_method("get_active_weapon_item"):
		return false
	return _is_axe_item(InventoryManager.get_active_weapon_item())


func _is_axe_item(item: ItemData) -> bool:
	if item == null:
		return false
	if item.item_type != ItemData.ItemType.MeleeWeapon:
		return false
	var item_name := item.item_name.strip_edges()
	for required_name in required_axe_item_names:
		if item_name == required_name.strip_edges():
			return true
	return false


func _set_felled_state() -> void:
	is_felled = true
	remove_from_group("secondary_interactable")
	remove_from_group(AXE_CHOPPABLE_GROUP)
	player_in_range = false
	_disconnect_equipment_signal()

	if normal_sprite != null:
		normal_sprite.visible = false
	if felled_sprite != null:
		felled_sprite.visible = true
	if outline_sprite != null:
		outline_sprite.visible = false
	if interact_label != null:
		interact_label.visible = false
	if interact_area != null:
		interact_area.monitoring = false
		interact_area.monitorable = false
	if trunk_body != null:
		trunk_body.process_mode = Node.PROCESS_MODE_DISABLED
		trunk_body.collision_layer = 0
		trunk_body.collision_mask = 0


func _drop_wood() -> void:
	if pickup_scene == null or wood_item_data == null:
		return

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		scene_root = get_parent()
	if scene_root == null:
		return

	for _i in range(max(wood_drop_count, 1)):
		var pickup: Node = pickup_scene.instantiate()
		if pickup == null:
			continue

		scene_root.add_child(pickup)
		var wood_instance: ItemData = wood_item_data.create_instance()
		if pickup.has_method("setup_from_item_data"):
			pickup.setup_from_item_data(wood_instance)
		elif "item_data" in pickup:
			pickup.item_data = wood_instance

		if pickup is Node2D:
			var drop_offset := Vector2(
				randf_range(-wood_drop_spread_radius, wood_drop_spread_radius),
				randf_range(-wood_drop_spread_radius, wood_drop_spread_radius)
			)
			(pickup as Node2D).global_position = global_position + drop_offset


func get_save_key() -> String:
	return "tree:%s" % [_get_persistent_identity()]


func get_legacy_save_keys() -> Array[String]:
	return ["tree:%s" % [str(global_position)]]


func _get_persistent_identity() -> String:
	if not persistent_id.strip_edges().is_empty():
		return persistent_id.strip_edges()
	var scene_path: String = ""
	var scene_root: Node = get_tree().current_scene
	if scene_root != null:
		scene_path = scene_root.scene_file_path
	var local_path: String = str(get_path())
	return "%s|%s" % [scene_path, local_path]


func get_save_data() -> Dictionary:
	return {
		"chop_hits": chop_hits,
		"is_felled": is_felled
	}


func apply_save_data(save_data: Dictionary) -> void:
	chop_hits = max(int(save_data.get("chop_hits", 0)), 0)
	var should_be_felled: bool = bool(save_data.get("is_felled", false))
	if should_be_felled:
		_set_felled_state()
		return
	is_felled = false
	player_in_range = false
	if normal_sprite != null:
		normal_sprite.visible = true
	if felled_sprite != null:
		felled_sprite.visible = false
	if interact_area != null:
		interact_area.monitoring = true
		interact_area.monitorable = true
	if trunk_body != null:
		trunk_body.process_mode = Node.PROCESS_MODE_INHERIT
	_update_visual_state()


func _persist_generation_state() -> void:
	if GameSaveManager == null or not GameSaveManager.has_method("record_world_generation_object_state"):
		return
	GameSaveManager.record_world_generation_object_state(self)
