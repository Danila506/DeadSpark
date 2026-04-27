extends Node2D

@onready var interact_area: Area2D = $InteractArea
@onready var interact_label: Label = $InteractLabel

@export var interaction_distance: float = 50.0
@export var loot_slot_count: int = 3
@export var loot_spawn_min: int = 1
@export var loot_spawn_max: int = 3
@export var medicine_pool: Array[ItemData] = [
	preload("res://Resources/Medicine/antidote.tres"),
	preload("res://Resources/Medicine/bandage.tres"),
	preload("res://Resources/Medicine/bloodBag.tres"),
	preload("res://Resources/Medicine/healthBox.tres"),
	preload("res://Resources/Medicine/hemostat.tres"),
	preload("res://Resources/Medicine/improvised_splint.tres"),
	preload("res://Resources/Medicine/potassium_iodide.tres"),
	preload("res://Resources/Medicine/restorer.tres"),
	preload("res://Resources/Medicine/saline.tres"),
	preload("res://Resources/Medicine/splint.tres")
]

var player_near: bool = false
var is_opened: bool = false
var loot_initialized: bool = false
var loot_slots: Array[ItemData] = []


func _ready() -> void:
	randomize()
	add_to_group("primary_interactable")
	interact_area.body_entered.connect(_on_interact_area_body_entered)
	interact_area.body_exited.connect(_on_interact_area_body_exited)
	_update_interact_label()
	if GameSaveManager != null and GameSaveManager.has_method("register_persistent_node"):
		GameSaveManager.register_persistent_node(self)


func handle_primary_interaction(interactor: Node) -> bool:
	if interactor == null or not interactor.is_in_group("player"):
		return false
	if not player_near:
		return false
	if not (interactor is Node2D):
		return false

	var player_node: Node2D = interactor as Node2D
	if global_position.distance_to(player_node.global_position) > max(interaction_distance, 1.0):
		return false

	is_opened = true
	_ensure_loot()
	_set_loot_panel_state(true)
	_update_interact_label()
	return true


func _on_interact_area_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	player_near = true
	_update_interact_label()


func _on_interact_area_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	player_near = false
	is_opened = false
	_set_loot_panel_state(false)
	_update_interact_label()


func _set_loot_panel_state(active: bool) -> void:
	var inventory_root: Node = get_tree().get_first_node_in_group("inventory_root")
	if inventory_root == null:
		return

	if active and inventory_root.has_method("open_loot_slots"):
		inventory_root.call("open_loot_slots", loot_slots)
	elif inventory_root.has_method("set_loot_context_active"):
		inventory_root.call("set_loot_context_active", false)


func _update_interact_label() -> void:
	if interact_label == null:
		return

	interact_label.text = "[E] - открыть"
	interact_label.visible = player_near and not is_opened


func _ensure_loot() -> void:
	if loot_initialized:
		return

	loot_initialized = true
	loot_slots.clear()
	var safe_slot_count: int = max(loot_slot_count, 0)
	loot_slots.resize(safe_slot_count)

	if safe_slot_count <= 0 or medicine_pool.is_empty():
		return

	var min_spawn: int = clamp(loot_spawn_min, 0, safe_slot_count)
	var max_spawn: int = clamp(loot_spawn_max, min_spawn, safe_slot_count)
	var spawn_count: int = randi_range(min_spawn, max_spawn)
	if spawn_count <= 0:
		return

	var free_indices: Array[int] = []
	for i in range(safe_slot_count):
		free_indices.append(i)

	for _i in range(spawn_count):
		if free_indices.is_empty():
			break

		var random_free_idx: int = randi_range(0, free_indices.size() - 1)
		var slot_index: int = free_indices[random_free_idx]
		free_indices.remove_at(random_free_idx)

		var template_item: ItemData = medicine_pool[randi_range(0, medicine_pool.size() - 1)]
		if template_item == null:
			continue

		var item_instance: ItemData = template_item.create_instance(1)
		loot_slots[slot_index] = item_instance


func get_save_key() -> String:
	return "medicine_kit:%s" % [str(global_position)]


func get_save_data() -> Dictionary:
	return {
		"loot_initialized": loot_initialized,
		"loot_slots": _serialize_item_array(loot_slots)
	}


func apply_save_data(save_data: Dictionary) -> void:
	is_opened = false
	loot_initialized = bool(save_data.get("loot_initialized", false))
	loot_slots = _deserialize_item_array(save_data.get("loot_slots", []))
	_set_loot_panel_state(false)
	_update_interact_label()


func _serialize_item_array(items: Array) -> Array:
	var out: Array = []
	for item in items:
		if item == null:
			out.append(null)
		elif GameSaveManager != null and GameSaveManager.has_method("serialize_item"):
			out.append(GameSaveManager.serialize_item(item))
		else:
			out.append({})
	return out


func _deserialize_item_array(raw_items: Variant) -> Array[ItemData]:
	var out: Array[ItemData] = []
	if not (raw_items is Array):
		return out
	for raw_item in raw_items:
		if raw_item == null:
			out.append(null)
		elif GameSaveManager != null and GameSaveManager.has_method("deserialize_item"):
			out.append(GameSaveManager.deserialize_item(raw_item))
		else:
			out.append(null)
	return out
