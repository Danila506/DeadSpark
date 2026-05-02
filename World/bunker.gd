extends Node2D

const INSIDE_HOUSE_GROUP: StringName = &"inside_house"
const INSIDE_HOUSE_ANCHOR_META: StringName = &"inside_house_anchor"
const ENEMY_GROUP: StringName = &"enemy"
const HOUSE_ENEMY_EJECT_MARGIN: float = 6.0
const PLAYER_PRE_BUNKER_Z_INDEX_META: StringName = &"pre_bunker_z_index"
const PLAYER_PRE_BUNKER_Z_AS_RELATIVE_META: StringName = &"pre_bunker_z_as_relative"
const PLAYER_BUNKER_Z_INDEX: int = 2000

@onready var outside_sprite: Sprite2D = $BunkerOutside
@onready var inside_sprite: Sprite2D = $BunkerInside
@onready var house_area: Area2D = get_node_or_null("BunkerArea") as Area2D
@onready var house_area_collision: CollisionShape2D = get_node_or_null("BunkerArea/CollisionShape2D") as CollisionShape2D
@onready var shadow_area: Area2D = $ShadowArea
@onready var collision_outside: StaticBody2D = $CollisionOutside
@onready var collision_inside: StaticBody2D = $CollisionInside
@onready var box_closed_sprite: Sprite2D = $BunkerInside/BunkerBox
@onready var box_closed_outline_sprite: Sprite2D = $BunkerInside/BunkerBoxOutline
@onready var box_opened_sprite: Sprite2D = $BunkerInside/BunkerBoxOpened
@onready var box_opened_outline_sprite: Sprite2D = $BunkerInside/BunkerBoxOpenedOutline
@onready var box_area: Area2D = $BunkerInside/BoxArea
@onready var interact_label: Label = $BunkerInside/InteractLabel

@export_range(0.0, 1.0, 0.01) var outside_alpha_when_inside: float = 0.28
@export_range(0.0, 1.0, 0.01) var outside_alpha_when_shadowed: float = 1.0
@export var interaction_distance: float = 50.0
@export var box_slot_count: int = 8
@export var box_spawn_min: int = 0
@export var box_spawn_max: int = 0
@export var guaranteed_items: Array[ItemData] = []
@export var loot_pool: Array[ItemData] = []
@export var persistent_id: String = ""

var player_in_house: bool = false
var player_in_shadow_zone: bool = false
var player_near_box: bool = false
var box_opened: bool = false
var loot_initialized: bool = false
var loot_slots: Array[ItemData] = []


func _ready() -> void:
	randomize()
	if house_area == null:
		house_area = $HouseArea
	if house_area_collision == null:
		house_area_collision = $HouseArea/CollisionShape2D
	add_to_group("primary_interactable")
	house_area.body_entered.connect(_on_house_body_entered)
	house_area.body_exited.connect(_on_house_body_exited)
	shadow_area.body_entered.connect(_on_shadow_body_entered)
	shadow_area.body_exited.connect(_on_shadow_body_exited)
	box_area.body_entered.connect(_on_box_area_body_entered)
	box_area.body_exited.connect(_on_box_area_body_exited)
	_update_house_visual()
	_update_box_visual()
	set_physics_process(false)
	call_deferred("_eject_current_overlapping_enemies")
	if GameSaveManager != null and GameSaveManager.has_method("register_persistent_node"):
		GameSaveManager.register_persistent_node(self)


func _eject_current_overlapping_enemies() -> void:
	if house_area == null:
		return

	for body in house_area.get_overlapping_bodies():
		_try_eject_enemy_from_house(body)


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
	if box_area.global_position.distance_to(player_node.global_position) > max(interaction_distance, 1.0):
		return false

	box_opened = true
	_ensure_loot()
	_set_loot_panel_state(true)
	_update_box_visual()
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
	if body is Node2D:
		_force_player_visible_in_bunker(body as Node2D)
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
	if body is Node2D:
		_restore_player_visibility_state(body as Node2D)
	_update_house_visual()


func _force_player_visible_in_bunker(player_node: Node2D) -> void:
	if player_node == null:
		return
	if not player_node.has_meta(PLAYER_PRE_BUNKER_Z_INDEX_META):
		player_node.set_meta(PLAYER_PRE_BUNKER_Z_INDEX_META, player_node.z_index)
	if not player_node.has_meta(PLAYER_PRE_BUNKER_Z_AS_RELATIVE_META):
		player_node.set_meta(PLAYER_PRE_BUNKER_Z_AS_RELATIVE_META, player_node.z_as_relative)
	player_node.z_as_relative = false
	player_node.z_index = PLAYER_BUNKER_Z_INDEX


func _restore_player_visibility_state(player_node: Node2D) -> void:
	if player_node == null:
		return
	if player_node.has_meta(PLAYER_PRE_BUNKER_Z_INDEX_META):
		player_node.z_index = int(player_node.get_meta(PLAYER_PRE_BUNKER_Z_INDEX_META))
		player_node.remove_meta(PLAYER_PRE_BUNKER_Z_INDEX_META)
	if player_node.has_meta(PLAYER_PRE_BUNKER_Z_AS_RELATIVE_META):
		player_node.z_as_relative = bool(player_node.get_meta(PLAYER_PRE_BUNKER_Z_AS_RELATIVE_META))
		player_node.remove_meta(PLAYER_PRE_BUNKER_Z_AS_RELATIVE_META)


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


func _on_box_area_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	player_near_box = true
	_update_box_visual()


func _on_box_area_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	player_near_box = false
	box_opened = false
	_set_loot_panel_state(false)
	_update_box_visual()


func _update_house_visual() -> void:
	outside_sprite.visible = true
	if player_in_house:
		outside_sprite.modulate.a = outside_alpha_when_inside
	elif player_in_shadow_zone:
		outside_sprite.modulate.a = outside_alpha_when_shadowed
	else:
		outside_sprite.modulate.a = 1.0
	inside_sprite.visible = player_in_house
	collision_outside.process_mode = Node.PROCESS_MODE_INHERIT
	collision_inside.process_mode = Node.PROCESS_MODE_INHERIT


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
	loot_slots.resize(max(box_slot_count, 0))

	if box_slot_count <= 0:
		return

	var min_spawn: int = clamp(box_spawn_min, 0, box_slot_count)
	var max_spawn: int = clamp(box_spawn_max, min_spawn, box_slot_count)

	var free_indices: Array[int] = []
	for i in range(box_slot_count):
		free_indices.append(i)

	for guaranteed_item in guaranteed_items:
		if free_indices.is_empty():
			break
		if guaranteed_item == null:
			continue

		var guaranteed_slot_pos: int = randi_range(0, free_indices.size() - 1)
		var guaranteed_slot_index: int = free_indices[guaranteed_slot_pos]
		free_indices.remove_at(guaranteed_slot_pos)

		var guaranteed_item_instance: ItemData = guaranteed_item.create_instance(1)
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

		var item_instance: ItemData = template_item.create_instance(1)
		loot_slots[slot_index] = item_instance


func get_save_key() -> String:
	return "bunker:%s" % [_get_persistent_identity()]


func get_legacy_save_keys() -> Array[String]:
	return ["bunker:%s" % [str(global_position)]]


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
		"loot_initialized": loot_initialized,
		"loot_slots": _serialize_item_array(loot_slots)
	}


func apply_save_data(save_data: Dictionary) -> void:
	box_opened = false
	loot_initialized = bool(save_data.get("loot_initialized", false))
	loot_slots = _deserialize_item_array(save_data.get("loot_slots", []))
	_set_loot_panel_state(false)
	_update_house_visual()
	_update_box_visual()


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
