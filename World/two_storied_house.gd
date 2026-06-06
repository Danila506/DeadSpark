extends Node2D

const INSIDE_HOUSE_GROUP: StringName = &"inside_house"
const INSIDE_HOUSE_ANCHOR_META: StringName = &"inside_house_anchor"
const ENEMY_GROUP: StringName = &"enemy"
const HOUSE_ENEMY_EJECT_MARGIN: float = 6.0
const FLOOR_ONE: int = 1
const FLOOR_TWO: int = 2
const PLAYER_PRE_HOUSE_Z_INDEX_META: StringName = &"pre_house_z_index"
const PLAYER_PRE_HOUSE_Z_AS_RELATIVE_META: StringName = &"pre_house_z_as_relative"
const PLAYER_HOUSE_Z_INDEX: int = 2000
const INSIDE_HOUSE_Z: int = -1
const OUTSIDE_HOUSE_Z: int = 0
const DOOR_Z_INSIDE: int = 1
const DOOR_Z_OUTSIDE: int = 3

@onready var floor1_root: Node2D = $floor1
@onready var floor2_root: Node2D = $floor2
@onready var floor1_sprite: Sprite2D = $floor1/HouseInside1floor
@onready var floor2_sprite: Sprite2D = $floor2/HouseInside2floor
@onready var floor1_stairs_sprite: Sprite2D = $floor1/Stairs
@onready var floor2_stairs_sprite: Sprite2D = $floor2/Stairs
@onready var floor_indicator_area: Area2D = $floor1/Area2D
@onready var bedside_closed_sprite: Sprite2D = $floor1/BedsideSprites/Bedside
@onready var bedside_outline_sprite: Sprite2D = $floor1/BedsideSprites/BedsideOutline
@onready var bedside_opened_outline_sprite: Sprite2D = $floor1/BedsideSprites/BedsideOutlineOpened
@onready var bedside_opened_sprite: Sprite2D = $floor1/BedsideSprites/BedsideOpened
@onready var bedside_area: Area2D = $floor1/BedsideArea
@onready var outside_sprite: Sprite2D = $HouseOutside
@onready var house_area: Area2D = $HouseArea
@onready var shadow_area: Area2D = $ShadowArea
@onready var collision_outside: StaticBody2D = $CollisionOutside
@onready var collision_floor1: StaticBody2D = $CollisionInside
@onready var collision_floor2: StaticBody2D = $floor2/StaticBody2D
@onready var door_closed_sprite: Sprite2D = $"Door'sSprites/Door"
@onready var door_closed_outline_sprite: Sprite2D = $"Door'sSprites/DoorOutline"
@onready var door_opened_sprite: Sprite2D = $"Door'sSprites/DoorOpened"
@onready var door_opened_outline_sprite: Sprite2D = $"Door'sSprites/DoorOutlineOpened"
@onready var door_area: Area2D = $DoorArea
@onready var door_blocker: CollisionShape2D = $DoorwayBlocker/CollisionShape2D
@onready var interact_label: Label = $InteractLabel

@export_range(0.01, 1.0, 0.01) var fade_duration_sec: float = 0.12
@export_range(0.0, 1.0, 0.01) var outside_alpha_when_shadowed: float = 0.9
@export_range(0.0, 128.0, 1.0) var interaction_distance: float = 52.0
@export var bedside_slot_count: int = 2
@export var bedside_spawn_min: int = 1
@export var bedside_spawn_max: int = 2
@export var bedside_food_pool: Array[ItemData] = [
	preload("res://Resources/Food/apple.tres"),
	preload("res://Resources/Food/tomate.tres"),
	preload("res://Resources/Food/tushenka.tres"),
	preload("res://Resources/Food/malinovaya_gazirovka.tres")
]
@export var bedside_medical_pool: Array[ItemData] = [
	preload("res://Resources/Medicine/bandage.tres"),
	preload("res://Resources/Medicine/healthBox.tres"),
	preload("res://Resources/Medicine/hemostat.tres"),
	preload("res://Resources/Medicine/splint.tres")
]
@export var persistent_id: String = ""

var player_in_house: bool = false
var player_in_shadow_zone: bool = false
var player_near_floor_indicator: bool = false
var player_near_door: bool = false
var player_near_bedside: bool = false
var current_floor: int = FLOOR_ONE
var door_opened: bool = false
var bedside_opened: bool = false
var bedside_loot_slots: Array[ItemData] = []
var bedside_loot_initialized: bool = false
var _is_floor_transition_active: bool = false
var _fade_layer: CanvasLayer = null
var _fade_rect: ColorRect = null


func _ready() -> void:
	randomize()
	add_to_group("primary_interactable")
	_configure_visual_layers()
	house_area.body_entered.connect(_on_house_body_entered)
	house_area.body_exited.connect(_on_house_body_exited)
	shadow_area.body_entered.connect(_on_shadow_body_entered)
	shadow_area.body_exited.connect(_on_shadow_body_exited)
	floor_indicator_area.body_entered.connect(_on_floor_indicator_body_entered)
	floor_indicator_area.body_exited.connect(_on_floor_indicator_body_exited)
	bedside_area.body_entered.connect(_on_bedside_area_body_entered)
	bedside_area.body_exited.connect(_on_bedside_area_body_exited)
	door_area.body_entered.connect(_on_door_area_body_entered)
	door_area.body_exited.connect(_on_door_area_body_exited)
	_ensure_fade_overlay()
	_update_house_visual()
	_update_floor_visual()
	_update_door_visual()
	_update_bedside_visual()
	_update_stairs_visual()
	set_physics_process(false)
	call_deferred("_eject_current_overlapping_enemies")
	if GameSaveManager != null and GameSaveManager.has_method("register_persistent_node"):
		GameSaveManager.register_persistent_node(self)


func _exit_tree() -> void:
	if _fade_layer != null and is_instance_valid(_fade_layer):
		_fade_layer.queue_free()
	_fade_layer = null
	_fade_rect = null


func handle_primary_interaction(interactor: Node) -> bool:
	if interactor == null or not interactor.is_in_group("player"):
		return false

	if current_floor == FLOOR_ONE and player_near_bedside and not bedside_opened:
		bedside_opened = true
		_ensure_bedside_loot()
		_set_bedside_loot_panel_state(true)
		_update_bedside_visual()
		_update_stairs_visual()
		return true

	if player_near_door and interactor is Node2D and current_floor == FLOOR_ONE:
		var player_node: Node2D = interactor as Node2D
		if door_area.global_position.distance_to(player_node.global_position) <= max(interaction_distance, 1.0):
			door_opened = not door_opened
			_update_door_visual()
			_update_stairs_visual()
			return true

	if not player_in_house or not player_near_floor_indicator or _is_floor_transition_active:
		return false
	if player_near_bedside or player_near_door:
		return false

	_is_floor_transition_active = true
	_update_stairs_visual()
	_transition_floor.call_deferred()
	return true


func _transition_floor() -> void:
	await _play_floor_transition_fade(1.0)
	current_floor = FLOOR_TWO if current_floor == FLOOR_ONE else FLOOR_ONE
	_update_floor_visual()
	_update_door_visual()
	_update_bedside_visual()
	_update_stairs_visual()
	await _play_floor_transition_fade(0.0)
	_is_floor_transition_active = false
	_update_stairs_visual()


func _play_floor_transition_fade(target_alpha: float) -> void:
	_ensure_fade_overlay()
	if _fade_rect == null:
		return

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_fade_rect, "modulate:a", clampf(target_alpha, 0.0, 1.0), maxf(fade_duration_sec, 0.01))
	await tween.finished


func _ensure_fade_overlay() -> void:
	if _fade_layer != null and is_instance_valid(_fade_layer):
		return

	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	add_child(_fade_layer)

	_fade_rect = ColorRect.new()
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.color = Color.BLACK
	_fade_rect.modulate.a = 0.0
	_fade_layer.add_child(_fade_rect)


func _eject_current_overlapping_enemies() -> void:
	if house_area == null:
		return

	for body in house_area.get_overlapping_bodies():
		_try_eject_enemy_from_house(body)


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
		_force_player_visible_in_house(body as Node2D)
	_update_house_visual()
	_update_floor_visual()
	_update_door_visual()
	_update_bedside_visual()
	_update_stairs_visual()


func _on_house_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	player_in_house = false
	player_near_floor_indicator = false
	player_near_bedside = false
	if body.is_in_group(INSIDE_HOUSE_GROUP):
		body.remove_from_group(INSIDE_HOUSE_GROUP)
	if body.has_meta(INSIDE_HOUSE_ANCHOR_META):
		body.remove_meta(INSIDE_HOUSE_ANCHOR_META)
	if body is CanvasItem:
		(body as CanvasItem).modulate = Color.WHITE
	if body is Node2D:
		_restore_player_visibility_state(body as Node2D)
	_set_bedside_loot_panel_state(false)
	_update_house_visual()
	_update_floor_visual()
	_update_door_visual()
	_update_bedside_visual()
	_update_stairs_visual()


func _force_player_visible_in_house(player_node: Node2D) -> void:
	if player_node == null:
		return
	if not player_node.has_meta(PLAYER_PRE_HOUSE_Z_INDEX_META):
		player_node.set_meta(PLAYER_PRE_HOUSE_Z_INDEX_META, player_node.z_index)
	if not player_node.has_meta(PLAYER_PRE_HOUSE_Z_AS_RELATIVE_META):
		player_node.set_meta(PLAYER_PRE_HOUSE_Z_AS_RELATIVE_META, player_node.z_as_relative)
	player_node.z_as_relative = false
	player_node.z_index = PLAYER_HOUSE_Z_INDEX


func _restore_player_visibility_state(player_node: Node2D) -> void:
	if player_node == null:
		return
	if player_node.has_meta(PLAYER_PRE_HOUSE_Z_INDEX_META):
		player_node.z_index = int(player_node.get_meta(PLAYER_PRE_HOUSE_Z_INDEX_META))
		player_node.remove_meta(PLAYER_PRE_HOUSE_Z_INDEX_META)
	if player_node.has_meta(PLAYER_PRE_HOUSE_Z_AS_RELATIVE_META):
		player_node.z_as_relative = bool(player_node.get_meta(PLAYER_PRE_HOUSE_Z_AS_RELATIVE_META))
		player_node.remove_meta(PLAYER_PRE_HOUSE_Z_AS_RELATIVE_META)


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


func _on_floor_indicator_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	player_near_floor_indicator = true
	_update_stairs_visual()


func _on_floor_indicator_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	player_near_floor_indicator = false
	_update_stairs_visual()


func _on_bedside_area_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	player_near_bedside = true
	_update_bedside_visual()
	_update_stairs_visual()


func _on_bedside_area_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	player_near_bedside = false
	bedside_opened = false
	_set_bedside_loot_panel_state(false)
	_update_bedside_visual()
	_update_stairs_visual()


func _on_door_area_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	player_near_door = true
	_update_door_visual()
	_update_stairs_visual()


func _on_door_area_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	player_near_door = false
	_update_door_visual()
	_update_stairs_visual()


func _update_house_visual() -> void:
	outside_sprite.visible = not player_in_house
	if outside_sprite.visible:
		outside_sprite.modulate.a = outside_alpha_when_shadowed if player_in_shadow_zone else 1.0
	collision_outside.process_mode = Node.PROCESS_MODE_INHERIT
	_update_door_draw_order()


func _update_floor_visual() -> void:
	var show_floor1: bool = player_in_house and current_floor == FLOOR_ONE
	var show_floor2: bool = player_in_house and current_floor == FLOOR_TWO

	floor1_root.visible = show_floor1
	floor1_sprite.visible = show_floor1
	floor2_root.visible = show_floor2
	floor2_sprite.visible = show_floor2
	collision_floor1.process_mode = Node.PROCESS_MODE_INHERIT if current_floor == FLOOR_ONE else Node.PROCESS_MODE_DISABLED
	collision_floor2.process_mode = Node.PROCESS_MODE_INHERIT if current_floor == FLOOR_TWO else Node.PROCESS_MODE_DISABLED


func _update_door_visual() -> void:
	var door_visible: bool = current_floor == FLOOR_ONE
	door_closed_sprite.visible = door_visible and not door_opened
	door_closed_outline_sprite.visible = door_visible and player_near_door and not door_opened
	door_opened_sprite.visible = door_visible and door_opened
	door_opened_outline_sprite.visible = door_visible and player_near_door and door_opened
	door_blocker.set_deferred("disabled", door_opened)
	_update_door_draw_order()


func _update_bedside_visual() -> void:
	var bedside_visible: bool = current_floor == FLOOR_ONE and player_in_house
	if not bedside_visible:
		bedside_closed_sprite.visible = false
		bedside_outline_sprite.visible = false
		bedside_opened_sprite.visible = false
		bedside_opened_outline_sprite.visible = false
		return

	if not bedside_opened:
		bedside_closed_sprite.visible = not player_near_bedside
		bedside_outline_sprite.visible = player_near_bedside
		bedside_opened_sprite.visible = false
		bedside_opened_outline_sprite.visible = false
		return

	bedside_closed_sprite.visible = false
	bedside_outline_sprite.visible = false
	bedside_opened_sprite.visible = not player_near_bedside
	bedside_opened_outline_sprite.visible = player_near_bedside


func _update_stairs_visual() -> void:
	var can_use_stairs: bool = player_in_house and player_near_floor_indicator and not _is_floor_transition_active
	if player_near_door or player_near_bedside:
		can_use_stairs = false

	var show_bedside_prompt: bool = player_near_bedside and not bedside_opened
	floor1_stairs_sprite.visible = can_use_stairs and current_floor == FLOOR_ONE
	floor2_stairs_sprite.visible = can_use_stairs and current_floor == FLOOR_TWO
	interact_label.visible = player_near_door or show_bedside_prompt or can_use_stairs

	if player_near_bedside:
		interact_label.text = "" if bedside_opened else "[E] - \u043E\u0442\u043A\u0440\u044B\u0442\u044C"
		return
	if player_near_door:
		interact_label.text = "[E] - \u0437\u0430\u043A\u0440\u044B\u0442\u044C" if door_opened else "[E] - \u043E\u0442\u043A\u0440\u044B\u0442\u044C"
		return
	if not can_use_stairs:
		interact_label.text = ""
		return

	interact_label.text = "[E] - \u0441\u043F\u0443\u0441\u0442\u0438\u0442\u044C\u0441\u044F" if current_floor == FLOOR_TWO else "[E] - \u043F\u043E\u0434\u043D\u044F\u0442\u044C\u0441\u044F"


func _update_door_draw_order() -> void:
	var target_z_index: int = DOOR_Z_INSIDE if player_in_house else DOOR_Z_OUTSIDE
	for sprite in [door_closed_sprite, door_closed_outline_sprite, door_opened_sprite, door_opened_outline_sprite]:
		if sprite == null:
			continue
		sprite.z_as_relative = true
		sprite.z_index = target_z_index


func _configure_visual_layers() -> void:
	if outside_sprite != null:
		outside_sprite.z_as_relative = true
		outside_sprite.z_index = OUTSIDE_HOUSE_Z
	for sprite in [floor1_sprite, floor2_sprite]:
		if sprite == null:
			continue
		sprite.z_as_relative = true
		sprite.z_index = INSIDE_HOUSE_Z


func _set_bedside_loot_panel_state(active: bool) -> void:
	var inventory_root: Node = get_tree().get_first_node_in_group("inventory_root")
	if inventory_root == null:
		return

	if active and inventory_root.has_method("open_loot_slots"):
		inventory_root.call("open_loot_slots", bedside_loot_slots)
	elif inventory_root.has_method("set_loot_context_active"):
		inventory_root.call("set_loot_context_active", false)


func _ensure_bedside_loot() -> void:
	if bedside_loot_initialized:
		return

	bedside_loot_initialized = true
	bedside_loot_slots.clear()
	bedside_loot_slots.resize(max(bedside_slot_count, 0))

	if bedside_slot_count <= 0:
		return

	var pool: Array[ItemData] = []
	for item in bedside_food_pool:
		if item != null:
			pool.append(item)
	for item in bedside_medical_pool:
		if item != null:
			pool.append(item)
	if pool.is_empty():
		return

	var spawn_min: int = clamp(bedside_spawn_min, 1, bedside_slot_count)
	var spawn_max: int = clamp(bedside_spawn_max, spawn_min, bedside_slot_count)
	var spawn_count: int = randi_range(spawn_min, spawn_max)
	var free_indices: Array[int] = []
	for i in range(bedside_slot_count):
		free_indices.append(i)

	for _i in range(spawn_count):
		if free_indices.is_empty():
			break
		var free_pos: int = randi_range(0, free_indices.size() - 1)
		var slot_index: int = free_indices[free_pos]
		free_indices.remove_at(free_pos)
		var template_item: ItemData = pool[randi_range(0, pool.size() - 1)]
		if template_item != null:
			bedside_loot_slots[slot_index] = template_item.create_instance(1)


func _try_eject_enemy_from_house(body: Node) -> void:
	if body == null or not body.is_in_group(ENEMY_GROUP):
		return
	if not (body is Node2D):
		return

	var enemy_node := body as Node2D
	var enemy_local_pos: Vector2 = to_local(enemy_node.global_position)
	var best_resolved_position := enemy_local_pos
	var best_penetration: float = INF
	var is_inside_any_shape: bool = false

	for child in house_area.get_children():
		if not (child is CollisionShape2D):
			continue
		var collision_shape := child as CollisionShape2D
		if not collision_shape.disabled and collision_shape.shape is RectangleShape2D:
			var rect_shape := collision_shape.shape as RectangleShape2D
			var center: Vector2 = collision_shape.position
			var half_extents: Vector2 = rect_shape.size * 0.5
			var relative: Vector2 = enemy_local_pos - center

			if abs(relative.x) > half_extents.x or abs(relative.y) > half_extents.y:
				continue

			is_inside_any_shape = true
			var candidate_relative := relative
			var penetration_x: float = half_extents.x - abs(relative.x)
			var penetration_y: float = half_extents.y - abs(relative.y)
			var penetration: float = minf(penetration_x, penetration_y)
			if penetration_x < penetration_y:
				candidate_relative.x = (1.0 if relative.x >= 0.0 else -1.0) * (half_extents.x + HOUSE_ENEMY_EJECT_MARGIN)
			else:
				candidate_relative.y = (1.0 if relative.y >= 0.0 else -1.0) * (half_extents.y + HOUSE_ENEMY_EJECT_MARGIN)

			if penetration < best_penetration:
				best_penetration = penetration
				best_resolved_position = center + candidate_relative

	if not is_inside_any_shape:
		return

	enemy_node.global_position = to_global(best_resolved_position)
	if "velocity" in enemy_node:
		enemy_node.velocity = Vector2.ZERO


func get_save_key() -> String:
	return "two_storied_house:%s" % [_get_persistent_identity()]


func get_legacy_save_keys() -> Array[String]:
	return ["two_storied_house:%s" % [str(global_position)]]


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
		"door_opened": door_opened,
		"bedside_loot_initialized": bedside_loot_initialized,
		"bedside_loot_slots": _serialize_item_array(bedside_loot_slots)
	}


func apply_save_data(save_data: Dictionary) -> void:
	door_opened = bool(save_data.get("door_opened", false))
	bedside_opened = false
	bedside_loot_initialized = bool(save_data.get("bedside_loot_initialized", false))
	bedside_loot_slots = _deserialize_item_array(save_data.get("bedside_loot_slots", []))
	_set_bedside_loot_panel_state(false)
	_update_house_visual()
	_update_floor_visual()
	_update_door_visual()
	_update_bedside_visual()
	_update_stairs_visual()


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
