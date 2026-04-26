extends Node2D

@onready var box_closed_sprite: Sprite2D = $Box
@onready var box_closed_outline_sprite: Sprite2D = $BoxOutline
@onready var box_opened_sprite: Sprite2D = $BoxOpened
@onready var box_opened_outline_sprite: Sprite2D = $BoxOpenedOutline
@onready var interact_area: Area2D = $InteractArea
@onready var interact_label: Label = $InteractLabel

@export var interaction_distance: float = 50.0
@export var loot_slot_count: int = 10
@export var loot_spawn_min: int = 0
@export var loot_spawn_max: int = 0
@export var guaranteed_items: Array[ItemData] = [
	preload("res://Resources/AR_Weapons/akp_103/VX_25.tres"),
	preload("res://Resources/AR_Weapons/akp_103/handle.tres"),
	preload("res://Resources/AR_Weapons/akp_103/silencer.tres")
]
@export var loot_pool: Array[ItemData] = []

var player_near_box: bool = false
var box_opened: bool = false
var loot_initialized: bool = false
var loot_slots: Array[ItemData] = []


func _ready() -> void:
	randomize()
	add_to_group("primary_interactable")
	interact_area.body_entered.connect(_on_interact_area_body_entered)
	interact_area.body_exited.connect(_on_interact_area_body_exited)
	_update_box_visual()


func handle_primary_interaction(interactor: Node) -> bool:
	if interactor == null or not interactor.is_in_group("player"):
		return false
	if not player_near_box:
		return false
	if box_opened:
		return false
	if not (interactor is Node2D):
		return false

	var player_node: Node2D = interactor as Node2D
	if global_position.distance_to(player_node.global_position) > max(interaction_distance, 1.0):
		return false

	box_opened = true
	_ensure_loot()
	_set_loot_panel_state(true)
	_update_box_visual()
	return true


func _on_interact_area_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	player_near_box = true
	_update_box_visual()


func _on_interact_area_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	player_near_box = false
	box_opened = false
	_set_loot_panel_state(false)
	_update_box_visual()


func _update_box_visual() -> void:
	if not box_opened:
		box_closed_sprite.visible = true
		box_closed_outline_sprite.visible = player_near_box
		box_opened_sprite.visible = false
		box_opened_outline_sprite.visible = false
		interact_label.text = "[E] - открыть"
		interact_label.visible = player_near_box
		return

	box_closed_sprite.visible = false
	box_closed_outline_sprite.visible = false
	box_opened_sprite.visible = true
	box_opened_outline_sprite.visible = player_near_box
	interact_label.text = ""
	interact_label.visible = false


func _set_loot_panel_state(active: bool) -> void:
	var inventory_root: Node = get_tree().get_first_node_in_group("inventory_root")
	if inventory_root == null:
		return

	if active and inventory_root.has_method("open_loot_slots"):
		inventory_root.call("open_loot_slots", loot_slots)
	elif inventory_root.has_method("set_loot_context_active"):
		inventory_root.call("set_loot_context_active", false)


func _ensure_loot() -> void:
	if loot_initialized:
		return

	loot_initialized = true
	loot_slots.clear()
	loot_slots.resize(max(loot_slot_count, 0))

	if loot_slot_count <= 0:
		return

	var min_spawn: int = clamp(loot_spawn_min, 0, loot_slot_count)
	var max_spawn: int = clamp(loot_spawn_max, min_spawn, loot_slot_count)

	var free_indices: Array[int] = []
	for i in range(loot_slot_count):
		free_indices.append(i)

	for guaranteed_item in guaranteed_items:
		if free_indices.is_empty():
			break
		if guaranteed_item == null:
			continue

		var guaranteed_slot_pos: int = randi_range(0, free_indices.size() - 1)
		var guaranteed_slot_index: int = free_indices[guaranteed_slot_pos]
		free_indices.remove_at(guaranteed_slot_pos)

		var guaranteed_item_instance: ItemData = guaranteed_item.duplicate(true)
		guaranteed_item_instance.stack_count = 1
		loot_slots[guaranteed_slot_index] = guaranteed_item_instance

	if loot_pool.is_empty() or free_indices.is_empty():
		return

	var spawn_count: int = randi_range(min_spawn, max_spawn)
	spawn_count = min(spawn_count, free_indices.size())
	for _i in range(spawn_count):
		if free_indices.is_empty():
			break

		var free_pos: int = randi_range(0, free_indices.size() - 1)
		var slot_index: int = free_indices[free_pos]
		free_indices.remove_at(free_pos)

		var template_item: ItemData = loot_pool[randi_range(0, loot_pool.size() - 1)]
		if template_item == null:
			continue

		var item_instance: ItemData = template_item.duplicate(true)
		item_instance.stack_count = 1
		loot_slots[slot_index] = item_instance
