extends Node2D
class_name VillagePlacementController

const GENERATED_VILLAGE_GROUP: StringName = &"generated_village"
const DEFAULT_VILLAGE_SCENE_PATH: String = "res://Villages/Village.tscn"

@export var village_scene: PackedScene
@export var placement_parent_path: NodePath = NodePath("../Y-Sort_Objects")
@export var default_generation_seed: int = 1337
@export var preview_modulate: Color = Color(0.55, 1.0, 0.65, 0.72)

var _placement_parent: Node2D
var _placement_active: bool = false
var _preview_instance: Node2D
var _preview_seed: int = 0
var _preview_position: Vector2 = Vector2.ZERO
var _last_village: Node2D


func _ready() -> void:
	add_to_group("village_placement_controller")
	z_as_relative = false
	z_index = 110
	_resolve_nodes()
	set_process(false)


func _process(_delta: float) -> void:
	if not _placement_active:
		return
	if _preview_instance == null or not is_instance_valid(_preview_instance):
		return
	_preview_position = _get_mouse_world_position()
	_preview_instance.global_position = _preview_position


func _unhandled_input(event: InputEvent) -> void:
	if not _placement_active:
		return

	if event.is_action_pressed("ui_cancel"):
		cancel_village_placement()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if not mouse_event.pressed:
			return
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_village_placement()
			get_viewport().set_input_as_handled()
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			place_preview_village()
			get_viewport().set_input_as_handled()


func start_village_placement(seed_value: int = -1) -> bool:
	_resolve_nodes()
	if _placement_parent == null:
		push_warning("VillagePlacementController: placement parent is not configured.")
		return false
	if not _ensure_village_scene():
		return false

	cancel_village_placement()
	_preview_seed = _resolve_seed(seed_value)
	_preview_instance = _create_generated_village(_preview_seed)
	if _preview_instance == null:
		return false

	_preview_instance.add_to_group(GENERATED_VILLAGE_GROUP)
	_preview_instance.set_meta("village_generation_seed", _preview_seed)
	_prepare_preview_instance(_preview_instance)
	_preview_instance.modulate = preview_modulate
	add_child(_preview_instance)
	_preview_position = _get_mouse_world_position()
	_preview_instance.global_position = _preview_position
	_placement_active = true
	set_process(true)
	return true


func place_preview_village() -> bool:
	if not _placement_active or _preview_instance == null or not is_instance_valid(_preview_instance):
		return false
	if _placement_parent == null:
		return false

	var placed_position := _preview_position
	var placed_seed := _preview_seed
	_preview_instance.queue_free()
	_placement_active = false
	set_process(false)
	_preview_instance = null

	var placed_village := _create_generated_village(placed_seed)
	if placed_village == null:
		return false
	placed_village.add_to_group(GENERATED_VILLAGE_GROUP)
	placed_village.set_meta("village_generation_seed", placed_seed)
	_placement_parent.add_child(placed_village)
	placed_village.global_position = placed_position
	_last_village = placed_village
	return true


func cancel_village_placement() -> void:
	_placement_active = false
	set_process(false)
	if _preview_instance != null and is_instance_valid(_preview_instance):
		_preview_instance.queue_free()
	_preview_instance = null


func regenerate_last_village(seed_value: int = -1) -> int:
	var village := _get_last_valid_village()
	if village == null:
		return -1

	var seed_to_use := _resolve_seed(seed_value)
	var generator := _ensure_generator(village)
	if generator == null:
		return -1
	generator.generation_seed = seed_to_use
	generator.generate()
	village.set_meta("village_generation_seed", seed_to_use)
	return seed_to_use


func clear_generated_villages() -> int:
	cancel_village_placement()
	if not is_inside_tree():
		return 0
	var cleared_count := 0
	for village in get_tree().get_nodes_in_group(GENERATED_VILLAGE_GROUP):
		if village is Node and is_instance_valid(village):
			(village as Node).queue_free()
			cleared_count += 1
	_last_village = null
	return cleared_count


func get_last_village_seed() -> int:
	var village := _get_last_valid_village()
	if village == null:
		return -1
	return int(village.get_meta("village_generation_seed", -1))


func get_pending_village_seed() -> int:
	return _preview_seed if _placement_active else -1


func is_village_placement_active() -> bool:
	return _placement_active


func _resolve_nodes() -> void:
	_placement_parent = get_node_or_null(placement_parent_path) as Node2D
	if _placement_parent != null:
		return
	if not is_inside_tree():
		return
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var y_sort := scene_root.get_node_or_null("Y-Sort_Objects") as Node2D
	if y_sort != null:
		_placement_parent = y_sort


func _ensure_village_scene() -> bool:
	if village_scene != null:
		return true
	village_scene = load(DEFAULT_VILLAGE_SCENE_PATH) as PackedScene
	if village_scene == null:
		push_warning("VillagePlacementController: failed to load Village scene.")
		return false
	return true


func _create_generated_village(seed_value: int) -> Node2D:
	var village := village_scene.instantiate() as Node2D
	if village == null:
		push_warning("VillagePlacementController: Village scene root must be Node2D.")
		return null

	var generator := _ensure_generator(village)
	if generator == null:
		village.queue_free()
		return null
	generator.generation_seed = seed_value
	generator.generate()
	return village


func _ensure_generator(village: Node2D) -> VillageGenerator:
	if village == null:
		return null
	var generator := village.get_node_or_null("VillageGenerator") as VillageGenerator
	if generator == null:
		generator = VillageGenerator.new()
		generator.name = "VillageGenerator"
		village.add_child(generator)
	generator.search_root_path = NodePath("..")
	generator.clear_before_generate = true
	return generator


func _prepare_preview_instance(root: Node) -> void:
	root.process_mode = Node.PROCESS_MODE_DISABLED
	if root.get_script() != null:
		root.set_script(null)
	if root is CollisionShape2D:
		(root as CollisionShape2D).disabled = true
	if root is CollisionPolygon2D:
		(root as CollisionPolygon2D).disabled = true
	for child in root.get_children():
		_prepare_preview_instance(child)


func _get_last_valid_village() -> Node2D:
	if _last_village != null and is_instance_valid(_last_village):
		return _last_village
	if not is_inside_tree():
		return null
	var villages := get_tree().get_nodes_in_group(GENERATED_VILLAGE_GROUP)
	for index in range(villages.size() - 1, -1, -1):
		var village := villages[index] as Node2D
		if village != null and is_instance_valid(village):
			_last_village = village
			return village
	return null


func _resolve_seed(seed_value: int) -> int:
	if seed_value >= 0:
		return seed_value
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return int(rng.randi() & 0x7fffffff)


func _get_mouse_world_position() -> Vector2:
	if not is_inside_tree() or get_viewport() == null:
		return Vector2.ZERO
	return get_global_mouse_position()
