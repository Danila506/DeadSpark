extends Node2D

@onready var outline_sprite: Sprite2D = $OutlineSprite
@onready var normal_sprite: Sprite2D = $NormalSprite
@onready var empty_bush_sprite: Sprite2D = $EmptyBush
@onready var interact_area: Area2D = $Area2D
@onready var interact_label: Label = $InteractLabel

@export var collect_duration_sec: float = 3.0
@export var interaction_radius_px: float = 72.0
@export var berry_item_data: ItemData = preload("res://Resources/Food/malina.tres")
@export var berry_count: int = 1
@export var persistent_id: String = ""

var player_in_range: bool = false
var is_harvested: bool = false


func _ready() -> void:
	add_to_group("secondary_interactable")
	if interact_area != null:
		interact_area.body_entered.connect(_on_area_body_entered)
		interact_area.body_exited.connect(_on_area_body_exited)
	_update_visual_state()
	if GameSaveManager != null and GameSaveManager.has_method("register_persistent_node"):
		GameSaveManager.register_persistent_node(self)


func _on_area_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	player_in_range = true
	_update_visual_state()


func _on_area_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	player_in_range = false
	_update_visual_state()


func handle_secondary_interaction(interactor: Node) -> bool:
	if is_harvested:
		return false
	if interactor == null or not interactor.is_in_group("player"):
		return false
	if not (interactor is Node2D):
		return false
	var interactor_pos: Vector2 = (interactor as Node2D).global_position
	if not player_in_range and interactor_pos.distance_to(global_position) > interaction_radius_px:
		return false
	if interactor.has_method("start_timed_action"):
		return bool(interactor.start_timed_action(collect_duration_sec, Callable(self, "_finish_collect"), "Сбор", true, "Using"))
	return false


func _finish_collect() -> void:
	if is_harvested:
		return
	is_harvested = true
	player_in_range = false
	remove_from_group("secondary_interactable")
	_grant_berries()
	_update_visual_state()


func _grant_berries() -> void:
	if berry_item_data == null:
		return
	var inventory_root: Node = get_tree().get_first_node_in_group("inventory_root")
	if inventory_root == null:
		return
	for _i in range(max(berry_count, 1)):
		var berry_instance: ItemData = berry_item_data.create_instance(1)
		if inventory_root.has_method("try_store_item_or_drop"):
			inventory_root.call("try_store_item_or_drop", berry_instance)


func _update_visual_state() -> void:
	if empty_bush_sprite != null:
		empty_bush_sprite.visible = is_harvested
	if normal_sprite != null:
		normal_sprite.visible = not is_harvested
	if outline_sprite != null:
		outline_sprite.visible = player_in_range and not is_harvested
	if interact_label != null:
		interact_label.visible = player_in_range and not is_harvested
		interact_label.text = "[F] - собрать"


func get_save_key() -> String:
	return "berry_bush:%s" % [_get_persistent_identity()]


func get_legacy_save_keys() -> Array[String]:
	return ["berry_bush:%s" % [str(global_position)]]


func get_save_data() -> Dictionary:
	return {
		"is_harvested": is_harvested
	}


func apply_save_data(save_data: Dictionary) -> void:
	is_harvested = bool(save_data.get("is_harvested", false))
	if is_harvested:
		remove_from_group("secondary_interactable")
		player_in_range = false
	_update_visual_state()


func _get_persistent_identity() -> String:
	if not persistent_id.strip_edges().is_empty():
		return persistent_id.strip_edges()
	var scene_path: String = ""
	var scene_root: Node = get_tree().current_scene
	if scene_root != null:
		scene_path = scene_root.scene_file_path
	var local_path: String = str(get_path())
	return "%s|%s" % [scene_path, local_path]
