extends Node2D

const INSIDE_HOUSE_GROUP: StringName = &"inside_house"
const INSIDE_HOUSE_ANCHOR_META: StringName = &"inside_house_anchor"

@onready var outside_sprite: Sprite2D = $ForesterHouseOutside
@onready var outside_right_sprite: Sprite2D = $ForesterHouseOutsideRight
@onready var outside_shadow_overlay: Sprite2D = $ForesterHouseOutsideShadow
@onready var inside_sprite: Sprite2D = $ForesterHouseInside
@onready var house_area: Area2D = $HouseArea
@onready var house_area_collision: CollisionShape2D = $HouseArea/CollisionShape2D
@onready var shadow_area: Area2D = $ShadowArea
@onready var collision_outside: StaticBody2D = $CollisionOutside
@onready var collision_inside: StaticBody2D = $CollisionInside
@onready var wardrobe_sprite: AnimatedSprite2D = $ForesterHouseInside/WardrobeSprite
@onready var wardrobe_area: Area2D = $ForesterHouseInside/WardrobeArea
@onready var interact_label: Label = $ForesterHouseInside/InteractLabel

@export var wardrobe_slot_count: int = 3
@export var wardrobe_spawn_min: int = 0
@export var wardrobe_spawn_max: int = 2
@export var wardrobe_guaranteed_items: Array[ItemData] = [
	preload("res://Resources/Clothes/jacket.tres"),
	preload("res://Resources/Clothes/trousers.tres")
]
@export_range(0.0, 1.0, 0.01) var outside_alpha_when_inside: float = 0.28
@export_range(0.0, 1.0, 0.01) var outside_right_alpha_when_inside: float = 0.2
@export_range(0.0, 1.0, 0.01) var outside_shadow_alpha_when_inside: float = 0.12
@export var wardrobe_food_pool: Array[ItemData] = [
	preload("res://Resources/food/apple.tres"),
	preload("res://Resources/food/tomate.tres"),
	preload("res://Resources/food/pepper.tres"),
	preload("res://Resources/food/eggplant.tres")
]

var player_in_house: bool = false
var player_in_shadow_zone: bool = false
var player_near_wardrobe: bool = false
var wardrobe_opened: bool = false
var wardrobe_loot_slots: Array[ItemData] = []
var wardrobe_loot_initialized: bool = false
const ENEMY_GROUP: StringName = &"enemy"
const HOUSE_ENEMY_EJECT_MARGIN: float = 6.0


func _ready() -> void:
	randomize()
	add_to_group("primary_interactable")
	house_area.body_entered.connect(_on_house_body_entered)
	house_area.body_exited.connect(_on_house_body_exited)
	shadow_area.body_entered.connect(_on_shadow_body_entered)
	shadow_area.body_exited.connect(_on_shadow_body_exited)
	wardrobe_area.body_entered.connect(_on_wardrobe_body_entered)
	wardrobe_area.body_exited.connect(_on_wardrobe_body_exited)
	_update_house_visual()
	_update_wardrobe_visual()


func _physics_process(_delta: float) -> void:
	if house_area == null:
		return

	for body in house_area.get_overlapping_bodies():
		_try_eject_enemy_from_house(body)


func handle_primary_interaction(interactor: Node) -> bool:
	if interactor == null or not interactor.is_in_group("player"):
		return false
	if not player_near_wardrobe:
		return false
	if wardrobe_opened:
		return false

	wardrobe_opened = true
	_ensure_wardrobe_loot()
	_set_wardrobe_loot_panel_state(true)
	_update_wardrobe_visual()
	return true


func _on_house_body_entered(body: Node) -> void:
	_try_eject_enemy_from_house(body)
	if not body.is_in_group("player"):
		return

	player_in_house = true
	if not body.is_in_group(INSIDE_HOUSE_GROUP):
		body.add_to_group(INSIDE_HOUSE_GROUP)
	body.set_meta(INSIDE_HOUSE_ANCHOR_META, global_position)
	if body is CanvasItem:
		(body as CanvasItem).modulate = Color(0.72, 0.72, 0.72, 1.0)
	_update_house_visual()


func _on_house_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	player_in_house = false
	if body.is_in_group(INSIDE_HOUSE_GROUP):
		body.remove_from_group(INSIDE_HOUSE_GROUP)
	if body.has_meta(INSIDE_HOUSE_ANCHOR_META):
		body.remove_meta(INSIDE_HOUSE_ANCHOR_META)
	if body is CanvasItem:
		(body as CanvasItem).modulate = Color.WHITE
	_update_house_visual()


func _try_eject_enemy_from_house(body: Node) -> void:
	if body == null:
		return
	if not body.is_in_group(ENEMY_GROUP):
		return
	if not (body is Node2D):
		return
	if house_area_collision == null:
		return
	if not (house_area_collision.shape is RectangleShape2D):
		return

	var enemy_node: Node2D = body as Node2D
	var rect_shape: RectangleShape2D = house_area_collision.shape as RectangleShape2D
	var house_local_pos: Vector2 = to_local(enemy_node.global_position)
	var center: Vector2 = house_area_collision.position
	var half_extents: Vector2 = rect_shape.size * 0.5
	var relative: Vector2 = house_local_pos - center

	if abs(relative.x) > half_extents.x or abs(relative.y) > half_extents.y:
		return

	var penetration_x: float = half_extents.x - abs(relative.x)
	var penetration_y: float = half_extents.y - abs(relative.y)
	if penetration_x < penetration_y:
		relative.x = (1.0 if relative.x >= 0.0 else -1.0) * (half_extents.x + HOUSE_ENEMY_EJECT_MARGIN)
	else:
		relative.y = (1.0 if relative.y >= 0.0 else -1.0) * (half_extents.y + HOUSE_ENEMY_EJECT_MARGIN)

	enemy_node.global_position = to_global(center + relative)
	if "velocity" in enemy_node:
		enemy_node.velocity = Vector2.ZERO


func _on_shadow_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	player_in_shadow_zone = true
	_update_house_visual()


func _on_shadow_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	player_in_shadow_zone = false
	_update_house_visual()


func _on_wardrobe_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	player_near_wardrobe = true
	_update_wardrobe_visual()


func _on_wardrobe_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	player_near_wardrobe = false
	wardrobe_opened = false
	_set_wardrobe_loot_panel_state(false)
	_update_wardrobe_visual()


func _update_house_visual() -> void:
	outside_sprite.visible = true
	outside_right_sprite.visible = not player_in_shadow_zone
	outside_shadow_overlay.visible = player_in_shadow_zone
	outside_sprite.modulate.a = outside_alpha_when_inside if player_in_house else 1.0
	outside_right_sprite.modulate.a = outside_right_alpha_when_inside if player_in_house else 1.0
	outside_shadow_overlay.modulate.a = outside_shadow_alpha_when_inside if player_in_house else 1.0
	inside_sprite.visible = player_in_house
	collision_outside.process_mode = Node.PROCESS_MODE_INHERIT
	collision_inside.process_mode = Node.PROCESS_MODE_INHERIT


func _update_wardrobe_visual() -> void:
	if not wardrobe_opened:
		wardrobe_sprite.frame = 1 if player_near_wardrobe else 0
		interact_label.text = "[E] - открыть"
		interact_label.visible = player_near_wardrobe
		return

	wardrobe_sprite.frame = 3 if player_near_wardrobe else 2
	interact_label.text = ""
	interact_label.visible = false


func _set_wardrobe_loot_panel_state(active: bool) -> void:
	var inventory_root: Node = get_tree().get_first_node_in_group("inventory_root")
	if inventory_root == null:
		return

	if active and inventory_root.has_method("open_loot_slots"):
		inventory_root.call("open_loot_slots", wardrobe_loot_slots)
	elif inventory_root.has_method("set_loot_context_active"):
		inventory_root.call("set_loot_context_active", false)


func _ensure_wardrobe_loot() -> void:
	if wardrobe_loot_initialized:
		return

	wardrobe_loot_initialized = true
	wardrobe_loot_slots.clear()
	wardrobe_loot_slots.resize(max(wardrobe_slot_count, 0))

	if wardrobe_slot_count <= 0:
		return

	var min_spawn: int = clamp(wardrobe_spawn_min, 0, wardrobe_slot_count)
	var max_spawn: int = clamp(wardrobe_spawn_max, min_spawn, wardrobe_slot_count)

	var free_indices: Array[int] = []
	for i in range(wardrobe_slot_count):
		free_indices.append(i)

	for guaranteed_item in wardrobe_guaranteed_items:
		if free_indices.is_empty():
			break
		if guaranteed_item == null:
			continue

		var guaranteed_slot_pos: int = randi_range(0, free_indices.size() - 1)
		var guaranteed_slot_index: int = free_indices[guaranteed_slot_pos]
		free_indices.remove_at(guaranteed_slot_pos)

		var guaranteed_item_instance: ItemData = guaranteed_item.duplicate(true)
		guaranteed_item_instance.stack_count = 1
		wardrobe_loot_slots[guaranteed_slot_index] = guaranteed_item_instance

	if wardrobe_food_pool.is_empty() or free_indices.is_empty():
		return

	var spawn_count: int = randi_range(min_spawn, max_spawn)
	spawn_count = min(spawn_count, free_indices.size())
	for _i in range(spawn_count):
		if free_indices.is_empty():
			break

		var free_pos: int = randi_range(0, free_indices.size() - 1)
		var slot_index: int = free_indices[free_pos]
		free_indices.remove_at(free_pos)

		var template_item: ItemData = wardrobe_food_pool[randi_range(0, wardrobe_food_pool.size() - 1)]
		if template_item == null:
			continue

		var item_instance: ItemData = template_item.duplicate(true)
		item_instance.stack_count = 1
		wardrobe_loot_slots[slot_index] = item_instance
