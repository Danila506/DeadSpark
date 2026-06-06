extends Node2D

const HOUSE_SCENES: Dictionary = {
	"forester_house": preload("res://World/Assets/Houses/ForesterHouse/forester_house.tscn"),
	"forester_house2": preload("res://World/Assets/Houses/ForesterHouse2/forester_house2.tscn"),
	"house1": preload("res://World/Assets/Houses/House1/house_1.tscn"),
	"two_storied_house": preload("res://World/Assets/Houses/TwoStoriedHouse/twoStoriedHouse.tscn")
}
const PREVIEW_VALID_COLOR := Color(0.55, 1.0, 0.65, 0.72)
const PREVIEW_BLOCKED_COLOR := Color(1.0, 0.45, 0.45, 0.72)
const MANUAL_PLACEMENT_GROUP: StringName = &"generated_world_object"

@export var player_path: NodePath = NodePath("../Y-Sort_Objects/Player2")
@export var placement_parent_path: NodePath = NodePath("../Y-Sort_Objects/GeneratedForesterHouses")
@export_range(32.0, 4000.0, 1.0) var max_placement_distance_px: float = 900.0
@export_flags_2d_physics var placement_collision_mask: int = 0xFFFFFFFF

var _player: Node2D = null
var _placement_parent: Node2D = null
var _placement_active: bool = false
var _selected_house_id: String = ""
var _preview_instance: Node2D = null
var _preview_collision_shapes: Array[CollisionShape2D] = []
var _preview_can_place: bool = false


func _ready() -> void:
	add_to_group("house_placement_controller")
	z_as_relative = false
	z_index = 100
	_resolve_nodes()
	set_process(false)


func _process(_delta: float) -> void:
	if not _placement_active:
		return
	_update_preview_transform()


func _unhandled_input(event: InputEvent) -> void:
	if not _placement_active:
		return

	if event.is_action_pressed("ui_cancel"):
		cancel_house_placement()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if not mouse_event.pressed:
			return
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_house_placement()
			get_viewport().set_input_as_handled()
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if _try_place_current_house():
				get_viewport().set_input_as_handled()


func start_house_placement(house_id: String) -> bool:
	_resolve_nodes()
	var normalized_house_id: String = house_id.strip_edges().to_lower()
	if not HOUSE_SCENES.has(normalized_house_id):
		push_warning("HousePlacementController: unknown house id '%s'." % house_id)
		return false
	if _player == null or _placement_parent == null:
		push_warning("HousePlacementController: player or placement parent is not configured.")
		return false

	cancel_house_placement()

	var scene: PackedScene = HOUSE_SCENES[normalized_house_id] as PackedScene
	var preview := scene.instantiate() as Node2D
	if preview == null:
		push_warning("HousePlacementController: failed to instantiate preview for '%s'." % normalized_house_id)
		return false
	_prepare_preview_instance(preview)

	_selected_house_id = normalized_house_id
	_preview_instance = preview
	_preview_collision_shapes.clear()
	add_child(_preview_instance)
	_disable_collision_shapes_for_preview(_preview_instance)
	_apply_preview_modulate(_preview_instance, PREVIEW_VALID_COLOR)
	_placement_active = true
	set_process(true)
	_update_preview_transform()
	return true


func cancel_house_placement() -> void:
	_placement_active = false
	_selected_house_id = ""
	_preview_can_place = false
	_preview_collision_shapes.clear()
	set_process(false)
	if _preview_instance != null and is_instance_valid(_preview_instance):
		_preview_instance.queue_free()
	_preview_instance = null


func is_house_placement_active() -> bool:
	return _placement_active


func get_available_house_ids() -> Array[String]:
	var ids: Array[String] = []
	for raw_id in HOUSE_SCENES.keys():
		ids.append(String(raw_id))
	ids.sort()
	return ids


func _resolve_nodes() -> void:
	_player = get_node_or_null(player_path) as Node2D
	_placement_parent = get_node_or_null(placement_parent_path) as Node2D


func _prepare_preview_instance(preview: Node2D) -> void:
	if preview == null:
		return

	if preview.get_script() != null:
		preview.set_script(null)

	_set_preview_process_mode(preview)
	_configure_preview_visuals(preview)


func _set_preview_process_mode(root: Node) -> void:
	root.process_mode = Node.PROCESS_MODE_DISABLED
	for child in root.get_children():
		_set_preview_process_mode(child)


func _configure_preview_visuals(preview: Node2D) -> void:
	var outside_sprite := preview.get_node_or_null("HouseOutside") as CanvasItem
	if outside_sprite != null:
		outside_sprite.visible = true

	var inside_sprite := preview.get_node_or_null("HouseInside") as CanvasItem
	if inside_sprite != null:
		inside_sprite.visible = false

	var floor1_root := preview.get_node_or_null("floor1") as CanvasItem
	if floor1_root != null:
		floor1_root.visible = false

	var floor2_root := preview.get_node_or_null("floor2") as CanvasItem
	if floor2_root != null:
		floor2_root.visible = false

	var door_sprites_root := preview.get_node_or_null("Door'sSprites") as CanvasItem
	if door_sprites_root != null:
		door_sprites_root.visible = true

	var closed_door := preview.get_node_or_null("Door'sSprites/Door") as CanvasItem
	if closed_door != null:
		closed_door.visible = true
	var closed_door_outline := preview.get_node_or_null("Door'sSprites/DoorOutline") as CanvasItem
	if closed_door_outline != null:
		closed_door_outline.visible = false
	var opened_door := preview.get_node_or_null("Door'sSprites/DoorOpened") as CanvasItem
	if opened_door != null:
		opened_door.visible = false
	var opened_door_outline := preview.get_node_or_null("Door'sSprites/DoorOutlineOpened") as CanvasItem
	if opened_door_outline != null:
		opened_door_outline.visible = false

	var interact_label := preview.get_node_or_null("InteractLabel") as CanvasItem
	if interact_label != null:
		interact_label.visible = false


func _disable_collision_shapes_for_preview(root: Node) -> void:
	if root is CollisionShape2D:
		var collision_shape := root as CollisionShape2D
		collision_shape.disabled = true
		if collision_shape.shape != null:
			_preview_collision_shapes.append(collision_shape)

	for child in root.get_children():
		_disable_collision_shapes_for_preview(child)


func _apply_preview_modulate(root: Node, color: Color) -> void:
	if root is CanvasItem:
		(root as CanvasItem).modulate = color
	for child in root.get_children():
		_apply_preview_modulate(child, color)


func _update_preview_transform() -> void:
	if _preview_instance == null or not is_instance_valid(_preview_instance):
		return

	_preview_instance.global_position = get_global_mouse_position()
	_preview_can_place = _can_place_preview()
	_apply_preview_modulate(_preview_instance, PREVIEW_VALID_COLOR if _preview_can_place else PREVIEW_BLOCKED_COLOR)


func _can_place_preview() -> bool:
	if _preview_instance == null or _player == null:
		return false
	if _preview_instance.global_position.distance_to(_player.global_position) > max_placement_distance_px:
		return false

	var space_state := get_world_2d().direct_space_state
	for collision_shape in _preview_collision_shapes:
		if collision_shape == null or not is_instance_valid(collision_shape):
			continue
		if collision_shape.shape == null:
			continue

		var params := PhysicsShapeQueryParameters2D.new()
		params.shape = collision_shape.shape
		params.transform = collision_shape.global_transform
		params.collide_with_areas = true
		params.collide_with_bodies = true
		params.collision_mask = placement_collision_mask

		var results: Array[Dictionary] = space_state.intersect_shape(params, 16)
		if not results.is_empty():
			return false

	return true


func _try_place_current_house() -> bool:
	if not _placement_active or not _preview_can_place:
		return false

	var scene: PackedScene = HOUSE_SCENES.get(_selected_house_id, null) as PackedScene
	if scene == null or _placement_parent == null:
		return false

	var placed_house := scene.instantiate() as Node2D
	if placed_house == null:
		return false

	placed_house.set_meta("manual_house_id", "manual_house:%s:%d" % [_selected_house_id, Time.get_ticks_usec()])
	placed_house.add_to_group(MANUAL_PLACEMENT_GROUP)
	_placement_parent.add_child(placed_house)
	placed_house.global_position = _preview_instance.global_position
	_update_preview_transform()
	return true
