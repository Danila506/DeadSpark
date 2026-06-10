extends Node2D

const FARM_ROW_TEXTURE: Texture2D = preload("res://Assets/Farming/FarmRowTiles.png")
const BULGARIAN_PEPPER_SCENE: PackedScene = preload("res://Assets/Farming/Scenes/BulgarianPepper.tscn")
const TOMATO_SCENE: PackedScene = preload("res://Assets/Farming/Scenes/Tomatos.tscn")
const EGGPLANT_SCENE: PackedScene = preload("res://Assets/Farming/Scenes/Eggplant.tscn")
const FARM_PLANT_INTERACTOR_SCRIPT: Script = preload("res://Assets/Farming/farm_plant_interactor.gd")
const PEPPER_ITEM_DATA: ItemData = preload("res://Resources/Food/pepper.tres")
const TOMATO_ITEM_DATA: ItemData = preload("res://Resources/Food/tomate.tres")
const EGGPLANT_ITEM_DATA: ItemData = preload("res://Resources/Food/eggplant.tres")
const FARM_SOURCE_ID: int = 0
const FARM_ALTERNATIVE_ID: int = 0
const SAVE_KEY: String = "level/farm_rows"
const CROP_TYPE_PEPPER: StringName = &"pepper"
const CROP_TYPE_TOMATO: StringName = &"tomate"
const CROP_TYPE_EGGPLANT: StringName = &"eggplant"

@export var ground_layer_path: NodePath = NodePath("../SnowLayer")
@export var player_path: NodePath = NodePath("../Y-Sort_Objects/Player2")
@export var crop_parent_path: NodePath = NodePath("../Y-Sort_Objects")
@export var blocked_layer_paths: Array[NodePath] = [
	NodePath("../RoadLayer"),
	NodePath("../Y-Sort_Objects/LakeLayer"),
	NodePath("../Y-Sort_Objects/Biom1/Biom1Layer"),
	NodePath("../Y-Sort_Objects/Biom2/Biom2Layer"),
	NodePath("../Y-Sort_Objects/xz")
]
@export var max_placement_distance_px: float = 180.0
@export var farm_tile_texture_size: Vector2i = Vector2i(32, 32)
@export_range(0.1, 2.0, 0.05) var farm_layer_scale_multiplier: float = 0.5
@export_flags_2d_physics var placement_collision_mask: int = 0xFFFFFFFF
@export_range(0.1, 1.0, 0.05) var placement_collision_cell_scale: float = 0.82
@export var plant_interaction_distance_px: float = 84.0
@export var crop_z_index_offset: int = 1
@export_range(0.1, 120.0, 0.1) var pepper_stage_duration_game_minutes: float = 5.0
@export_range(0.1, 240.0, 0.1) var pepper_taint_after_ready_game_minutes: float = 20.0

var _ground_layer: TileMapLayer
var _farm_layer: TileMapLayer
var _preview_layer: TileMapLayer
var _crop_root: Node2D
var _plant_label: Label
var _plant_interactor: Node2D
var _placement_collision_shape: RectangleShape2D = RectangleShape2D.new()
var _blocked_layers: Array[TileMapLayer] = []
var _placement_active: bool = false
var _preview_atlas: Vector2i = Vector2i.ZERO
var _farm_atlas_tiles: Array[Vector2i] = []
var _hover_cell: Vector2i = Vector2i.ZERO
var _has_hover_cell: bool = false
var _setup_finished: bool = false
var _crop_configs_by_type: Dictionary = {}
var _crops_by_cell: Dictionary = {}
var _crop_type_by_cell: Dictionary = {}


func _ready() -> void:
	add_to_group("farming_placement_controller")
	_resolve_layers()
	call_deferred("_finish_ready_setup")
	set_process(true)


func _finish_ready_setup() -> void:
	_build_crop_configs()
	_ensure_farm_layers()
	_ensure_crop_root()
	_ensure_plant_label()
	_ensure_plant_interactor()
	if GameSaveManager != null and GameSaveManager.has_method("register_persistent_node"):
		GameSaveManager.register_persistent_node(self)
	_setup_finished = true
	set_process(true)


func start_farm_row_placement() -> bool:
	if not _setup_finished:
		_finish_ready_setup()

	if _ground_layer == null:
		push_warning("FarmingPlacementController: ground_layer_path is not configured.")
		return false

	_ensure_farm_layers()
	if _farm_layer == null or _preview_layer == null:
		return false

	_placement_active = true
	_preview_atlas = _pick_random_farm_atlas()
	_has_hover_cell = false
	_update_preview()
	set_process(true)
	return true


func cancel_farm_row_placement() -> void:
	if not _placement_active:
		return

	_placement_active = false
	_clear_preview()


func is_farm_row_placement_active() -> bool:
	return _placement_active


func get_save_key() -> String:
	return SAVE_KEY


func get_save_data() -> Dictionary:
	_ensure_farm_layers()
	var cells: Array[Dictionary] = []
	if _farm_layer == null:
		return {"cells": cells}

	for cell in _farm_layer.get_used_cells():
		var source_id := _farm_layer.get_cell_source_id(cell)
		if source_id == -1:
			continue
		var atlas := _farm_layer.get_cell_atlas_coords(cell)
		cells.append({
			"x": cell.x,
			"y": cell.y,
			"atlas_x": atlas.x,
			"atlas_y": atlas.y
		})

	var crops: Array[Dictionary] = []
	for cell_key in _crops_by_cell.keys():
		var crop := _crops_by_cell.get(cell_key, null) as Node
		if crop == null or not is_instance_valid(crop):
			continue
		if crop.has_method("get_save_data"):
			var crop_save_data: Variant = crop.call("get_save_data")
			if crop_save_data is Dictionary:
				var typed_save_data: Dictionary = (crop_save_data as Dictionary).duplicate(true)
				var crop_cell: Vector2i = cell_key if cell_key is Vector2i else Vector2i.ZERO
				var crop_type_id: String = String(_crop_type_by_cell.get(crop_cell, CROP_TYPE_PEPPER))
				typed_save_data["crop_type_id"] = crop_type_id
				crops.append(typed_save_data)

	return {
		"cells": cells,
		"crops": crops
	}


func apply_save_data(save_data: Dictionary) -> void:
	_ensure_farm_layers()
	if _farm_layer == null:
		return

	_farm_layer.clear()
	_clear_all_crops()
	var raw_cells: Array = save_data.get("cells", [])
	for raw_cell in raw_cells:
		if not (raw_cell is Dictionary):
			continue
		var cell_data := raw_cell as Dictionary
		var cell := Vector2i(int(cell_data.get("x", 0)), int(cell_data.get("y", 0)))
		var atlas := Vector2i(int(cell_data.get("atlas_x", 0)), int(cell_data.get("atlas_y", 0)))
		if not _farm_atlas_tiles.has(atlas):
			atlas = _pick_random_farm_atlas()
		_farm_layer.set_cell(cell, FARM_SOURCE_ID, atlas, FARM_ALTERNATIVE_ID)

	var raw_crops: Array = save_data.get("crops", [])
	if raw_crops.is_empty():
		raw_crops = save_data.get("pepper_crops", [])
	for raw_crop in raw_crops:
		if not (raw_crop is Dictionary):
			continue
		var crop_data := raw_crop as Dictionary
		var crop_cell := Vector2i(int(crop_data.get("cell_x", 0)), int(crop_data.get("cell_y", 0)))
		if _farm_layer.get_cell_source_id(crop_cell) == -1:
			continue
		var crop_type_raw: String = String(crop_data.get("crop_type_id", ""))
		var crop_type_id: StringName = StringName(crop_type_raw) if not crop_type_raw.is_empty() else CROP_TYPE_PEPPER
		_spawn_crop(crop_cell, float(crop_data.get("planted_at_game_minutes", _get_current_game_minutes())), crop_type_id)


func _process(_delta: float) -> void:
	if _placement_active:
		_update_preview()
	_update_plant_prompt()


func handle_primary_interaction(interactor: Node) -> bool:
	if interactor == null or not interactor.is_in_group("player"):
		return false
	var raw_cell: Variant = _get_nearest_plantable_farm_cell(interactor as Node2D)
	if not (raw_cell is Vector2i):
		return false
	var cell: Vector2i = raw_cell
	var seed_stack := _find_seed_stack()
	if seed_stack.is_empty():
		return false
	var crop_type_id: StringName = StringName(String(seed_stack.get("crop_type_id", "")))
	if String(crop_type_id).is_empty():
		return false
	if not _consume_one_seed_stack(seed_stack):
		return false

	_spawn_crop(cell, _get_current_game_minutes(), crop_type_id)
	_hide_plant_prompt()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not _placement_active:
		return

	if event.is_action_pressed("ui_cancel"):
		cancel_farm_row_placement()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if not mouse_event.pressed:
			return
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_farm_row_placement()
			get_viewport().set_input_as_handled()
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_try_place_at_mouse()
			get_viewport().set_input_as_handled()


func _resolve_layers() -> void:
	_ground_layer = get_node_or_null(ground_layer_path) as TileMapLayer
	_blocked_layers.clear()

	for layer_path in blocked_layer_paths:
		var layer := get_node_or_null(layer_path) as TileMapLayer
		if layer != null and layer != _ground_layer:
			_blocked_layers.append(layer)


func _ensure_farm_layers() -> void:
	if _ground_layer == null:
		_resolve_layers()
	if _ground_layer == null:
		return

	if _farm_layer == null or not is_instance_valid(_farm_layer):
		_farm_layer = _create_layer("FarmRowsLayer", 0, false)
	if _preview_layer == null or not is_instance_valid(_preview_layer):
		_preview_layer = _create_layer("FarmRowsPreviewLayer", 0, false)
		_preview_layer.modulate = Color(0.3, 1.0, 0.35, 0.58)
		_preview_layer.visible = false


func _ensure_crop_root() -> void:
	if _ground_layer == null:
		return
	var crop_parent: Node2D = _resolve_crop_parent()
	if crop_parent == null:
		return
	if _crop_root != null and is_instance_valid(_crop_root):
		if _crop_root.get_parent() != crop_parent:
			_crop_root.reparent(crop_parent, true)
		_apply_crop_root_render_settings()
		return

	_crop_root = crop_parent.get_node_or_null("FarmCrops") as Node2D
	if _crop_root == null:
		var legacy_parent: Node = _ground_layer.get_parent()
		var legacy_crop_root: Node2D = legacy_parent.get_node_or_null("FarmCrops") as Node2D if legacy_parent != crop_parent else null
		if legacy_crop_root != null:
			_crop_root = legacy_crop_root
			_crop_root.reparent(crop_parent, true)
		else:
			_crop_root = Node2D.new()
			_crop_root.name = "FarmCrops"
			if crop_parent.is_node_ready():
				crop_parent.add_child(_crop_root)
			else:
				crop_parent.add_child.call_deferred(_crop_root)

	_apply_crop_root_render_settings()


func _resolve_crop_parent() -> Node2D:
	var configured_parent: Node2D = get_node_or_null(crop_parent_path) as Node2D
	if configured_parent != null:
		return configured_parent

	var player_node: Node2D = _resolve_player()
	if player_node != null and player_node.get_parent() is Node2D:
		return player_node.get_parent() as Node2D

	return _ground_layer.get_parent() as Node2D


func _apply_crop_root_render_settings() -> void:
	if _crop_root == null or _ground_layer == null:
		return
	# Keep the farm crops in the same effective Z-space as the player Y-sort
	# container so per-crop Y-sorting can interleave correctly with characters.
	_crop_root.z_as_relative = false
	_crop_root.z_index = _ground_layer.z_index + crop_z_index_offset
	_crop_root.y_sort_enabled = true


func _ensure_plant_label() -> void:
	if _plant_label != null and is_instance_valid(_plant_label):
		return

	_plant_label = Label.new()
	_plant_label.name = "PlantPepperLabel"
	_plant_label.visible = false
	_plant_label.text = "[E] - посадить"
	_plant_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plant_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_plant_label.offset_left = -52.0
	_plant_label.offset_top = -48.0
	_plant_label.offset_right = 52.0
	_plant_label.offset_bottom = -27.0
	_plant_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plant_label.add_theme_font_size_override("font_size", 12)
	_plant_label.add_theme_color_override("font_color", Color(0.94, 0.96, 0.9, 1.0))
	_plant_label.add_theme_color_override("font_shadow_color", Color(0.04, 0.05, 0.035, 0.9))
	_plant_label.add_theme_constant_override("shadow_offset_x", 1)
	_plant_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_plant_label)


func _ensure_plant_interactor() -> void:
	if _plant_interactor != null and is_instance_valid(_plant_interactor):
		return

	_plant_interactor = Node2D.new()
	_plant_interactor.name = "PlantPepperInteractor"
	_plant_interactor.set_script(FARM_PLANT_INTERACTOR_SCRIPT)
	_plant_interactor.set("controller", self)
	add_child(_plant_interactor)
	if _plant_interactor.has_method("set_active"):
		_plant_interactor.call("set_active", false)


func _create_layer(layer_name: String, z_offset: int, y_sort_enabled: bool) -> TileMapLayer:
	var existing_layer := _ground_layer.get_parent().get_node_or_null(layer_name) as TileMapLayer
	if existing_layer != null:
		existing_layer.tile_set = _build_farm_tile_set()
		_apply_farm_layer_transform(existing_layer, z_offset, y_sort_enabled)
		return existing_layer

	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = _build_farm_tile_set()
	_apply_farm_layer_transform(layer, z_offset, y_sort_enabled)
	var parent := _ground_layer.get_parent()
	if parent.is_node_ready():
		parent.add_child(layer)
	else:
		parent.add_child.call_deferred(layer)
	return layer


func _apply_farm_layer_transform(layer: TileMapLayer, z_offset: int, y_sort_enabled: bool) -> void:
	if layer == null or _ground_layer == null:
		return

	layer.z_index = _ground_layer.z_index + z_offset
	layer.y_sort_enabled = y_sort_enabled
	layer.position = _ground_layer.position
	layer.rotation = _ground_layer.rotation
	layer.scale = _get_farm_layer_scale()


func _get_farm_layer_scale() -> Vector2:
	var ground_tile_size := _get_ground_tile_size()
	var base_scale := Vector2(
		_ground_layer.scale.x * (float(ground_tile_size.x) / float(max(farm_tile_texture_size.x, 1))),
		_ground_layer.scale.y * (float(ground_tile_size.y) / float(max(farm_tile_texture_size.y, 1)))
	)
	return base_scale * farm_layer_scale_multiplier


func _build_farm_tile_set() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = farm_tile_texture_size

	var atlas_source := TileSetAtlasSource.new()
	atlas_source.texture = FARM_ROW_TEXTURE
	atlas_source.texture_region_size = farm_tile_texture_size

	_farm_atlas_tiles = _collect_farm_atlas_tiles()
	for atlas in _farm_atlas_tiles:
		atlas_source.create_tile(atlas)

	tile_set.add_source(atlas_source, FARM_SOURCE_ID)
	return tile_set


func _get_ground_tile_size() -> Vector2i:
	if _ground_layer != null and _ground_layer.tile_set != null:
		return _ground_layer.tile_set.tile_size
	return Vector2i(60, 60)


func _collect_farm_atlas_tiles() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var texture_size := FARM_ROW_TEXTURE.get_size()
	var columns: int = max(int(floor(texture_size.x / float(max(farm_tile_texture_size.x, 1)))), 1)
	var rows: int = max(int(floor(texture_size.y / float(max(farm_tile_texture_size.y, 1)))), 1)

	for y in range(rows):
		for x in range(columns):
			result.append(Vector2i(x, y))

	if result.is_empty():
		result.append(Vector2i.ZERO)
	return result


func _pick_random_farm_atlas() -> Vector2i:
	if _farm_atlas_tiles.is_empty():
		_farm_atlas_tiles = _collect_farm_atlas_tiles()
	return _farm_atlas_tiles[randi_range(0, _farm_atlas_tiles.size() - 1)]


func _update_preview() -> void:
	if _ground_layer == null or _preview_layer == null:
		return

	var cell := _get_mouse_ground_cell()
	if _has_hover_cell and cell != _hover_cell:
		_preview_layer.erase_cell(_hover_cell)

	_hover_cell = cell
	_has_hover_cell = true

	var can_place := _can_place_at_cell(cell)
	_preview_layer.modulate = Color(0.3, 1.0, 0.35, 0.58) if can_place else Color(1.0, 0.25, 0.18, 0.5)
	_preview_layer.set_cell(cell, FARM_SOURCE_ID, _preview_atlas, FARM_ALTERNATIVE_ID)
	_preview_layer.visible = true


func _clear_preview() -> void:
	if _preview_layer != null and _has_hover_cell:
		_preview_layer.erase_cell(_hover_cell)
	if _preview_layer != null:
		_preview_layer.visible = false
	_has_hover_cell = false


func _try_place_at_mouse() -> void:
	var cell := _get_mouse_ground_cell()
	if not _can_place_at_cell(cell):
		return

	_farm_layer.set_cell(cell, FARM_SOURCE_ID, _preview_atlas, FARM_ALTERNATIVE_ID)
	cancel_farm_row_placement()


func _update_plant_prompt() -> void:
	_ensure_plant_label()
	_ensure_plant_interactor()
	if _plant_label == null:
		return

	var player := _resolve_player()
	var raw_cell: Variant = _get_nearest_plantable_farm_cell(player)
	if not (raw_cell is Vector2i) or not _has_plantable_seed():
		_hide_plant_prompt()
		return
	var cell: Vector2i = raw_cell

	var world_pos := _get_cell_world_position(cell)
	_plant_label.global_position = world_pos
	_plant_label.visible = true
	_set_plant_interactor_active(world_pos, true)


func _hide_plant_prompt() -> void:
	if _plant_label != null:
		_plant_label.visible = false
	_set_plant_interactor_active(Vector2.ZERO, false)


func _set_plant_interactor_active(world_position: Vector2, is_active: bool) -> void:
	if _plant_interactor == null or not is_instance_valid(_plant_interactor):
		return
	_plant_interactor.global_position = world_position
	if _plant_interactor.has_method("set_active"):
		_plant_interactor.call("set_active", is_active)


func _build_crop_configs() -> void:
	_crop_configs_by_type.clear()
	_register_crop_config(CROP_TYPE_PEPPER, BULGARIAN_PEPPER_SCENE, PEPPER_ITEM_DATA)
	_register_crop_config(CROP_TYPE_TOMATO, TOMATO_SCENE, TOMATO_ITEM_DATA)
	_register_crop_config(CROP_TYPE_EGGPLANT, EGGPLANT_SCENE, EGGPLANT_ITEM_DATA)


func _register_crop_config(crop_type_id: StringName, crop_scene: PackedScene, crop_item: ItemData) -> void:
	if String(crop_type_id).is_empty() or crop_scene == null or crop_item == null:
		return
	_crop_configs_by_type[crop_type_id] = {
		"scene": crop_scene,
		"item": crop_item,
		"harvest_amount": 3
	}


func _get_crop_config(crop_type_id: StringName) -> Dictionary:
	if _crop_configs_by_type.has(crop_type_id):
		return _crop_configs_by_type[crop_type_id]
	return {}


func _get_nearest_plantable_farm_cell(player: Node2D) -> Variant:
	if player == null or _farm_layer == null:
		return null

	var best_cell: Vector2i = Vector2i.ZERO
	var best_distance := INF
	var found := false

	for cell in _farm_layer.get_used_cells():
		if _crops_by_cell.has(cell):
			continue
		var world_pos := _get_cell_world_position(cell)
		var distance := player.global_position.distance_to(world_pos)
		if distance > maxf(plant_interaction_distance_px, 1.0):
			continue
		if distance < best_distance:
			best_distance = distance
			best_cell = cell
			found = true

	return best_cell if found else null


func _spawn_crop(cell: Vector2i, planted_at_minutes: float, crop_type_id: StringName) -> Node:
	_ensure_crop_root()
	if _crop_root == null or _crops_by_cell.has(cell):
		return null

	var config: Dictionary = _get_crop_config(crop_type_id)
	var crop_scene := config.get("scene", null) as PackedScene
	if crop_scene == null:
		return null

	var crop := crop_scene.instantiate() as Node2D
	if crop == null:
		return null

	crop.name = "%s_%d_%d" % [String(crop_type_id), cell.x, cell.y]
	_crop_root.add_child(crop)
	crop.global_position = _get_cell_world_position(cell)
	if crop.has_method("setup"):
		crop.call(
			"setup",
			cell,
			maxf(planted_at_minutes, 0.0),
			pepper_stage_duration_game_minutes,
			pepper_taint_after_ready_game_minutes
		)
	if crop.has_signal("harvest_requested"):
		crop.connect("harvest_requested", Callable(self, "_on_crop_harvest_requested"))
	if crop.has_signal("clear_requested"):
		crop.connect("clear_requested", Callable(self, "_on_crop_clear_requested"))

	_crops_by_cell[cell] = crop
	_crop_type_by_cell[cell] = crop_type_id
	return crop


func _on_crop_harvest_requested(crop: Node) -> void:
	if crop == null or not is_instance_valid(crop):
		return
	var crop_type_id: StringName = _resolve_crop_type_for_crop(crop)
	_store_harvested_crop(crop_type_id, _get_crop_harvest_amount(crop_type_id))
	_remove_crop(crop)


func _on_crop_clear_requested(crop: Node) -> void:
	_remove_crop(crop)


func _remove_crop(crop: Node) -> void:
	if crop == null:
		return
	var raw_cell: Variant = crop.get("farm_cell")
	if raw_cell is Vector2i:
		var cell: Vector2i = raw_cell
		_crops_by_cell.erase(cell)
		_crop_type_by_cell.erase(cell)
	else:
		for cell_key in _crops_by_cell.keys():
			if _crops_by_cell[cell_key] == crop:
				var found_cell: Vector2i = cell_key if cell_key is Vector2i else Vector2i.ZERO
				_crops_by_cell.erase(found_cell)
				_crop_type_by_cell.erase(found_cell)
				break
	if is_instance_valid(crop):
		crop.queue_free()


func _clear_all_crops() -> void:
	for crop in _crops_by_cell.values():
		if crop != null and is_instance_valid(crop):
			(crop as Node).queue_free()
	_crops_by_cell.clear()
	_crop_type_by_cell.clear()


func _store_harvested_crop(crop_type_id: StringName, amount: int) -> void:
	if amount <= 0:
		return

	var config: Dictionary = _get_crop_config(crop_type_id)
	var crop_item := config.get("item", null) as ItemData
	if crop_item == null:
		return

	var crop_stack := crop_item.create_instance(amount)
	var inventory_root := get_tree().get_first_node_in_group("inventory_root")
	if inventory_root != null and inventory_root.has_method("try_store_item_or_drop"):
		inventory_root.call("try_store_item_or_drop", crop_stack)


func _get_crop_harvest_amount(crop_type_id: StringName) -> int:
	var config: Dictionary = _get_crop_config(crop_type_id)
	return max(int(config.get("harvest_amount", 1)), 1)


func _has_plantable_seed() -> bool:
	return not _find_seed_stack().is_empty()


func _consume_one_seed_stack(stack_data: Dictionary) -> bool:
	if stack_data.is_empty():
		return false

	var item := stack_data.get("item", null) as ItemData
	if item == null:
		return false

	item.stack_count -= 1
	if item.stack_count <= 0:
		var source := String(stack_data.get("source", ""))
		if source == "equipment":
			InventoryManager.set_equipped(int(stack_data.get("slot_type", -1)), null)
		elif source == "storage":
			var provider := stack_data.get("provider", null) as ItemData
			var slot_index := int(stack_data.get("slot_index", -1))
			if provider != null and slot_index >= 0 and slot_index < provider.runtime_storage_items.size():
				provider.runtime_storage_items[slot_index] = null
	else:
		if String(stack_data.get("source", "")) == "equipment":
			InventoryManager.equipment_changed.emit(int(stack_data.get("slot_type", -1)), item)

	_refresh_inventory_ui()
	return true


func _find_seed_stack() -> Dictionary:
	if InventoryManager == null:
		return {}

	for slot_type in _get_seed_source_equipment_slots():
		var equipped_item := InventoryManager.get_equipped(slot_type)
		var equipped_crop_type_id: StringName = _resolve_crop_type_for_item(equipped_item)
		if not String(equipped_crop_type_id).is_empty():
			return {
				"source": "equipment",
				"slot_type": slot_type,
				"item": equipped_item,
				"crop_type_id": equipped_crop_type_id
			}

	for slot_type in [ItemData.ItemType.Jacket, ItemData.ItemType.HeavyArmour, ItemData.ItemType.Trousers, ItemData.ItemType.Bag]:
		var provider := InventoryManager.get_equipped(slot_type)
		if provider == null:
			continue
		for i in range(provider.runtime_storage_items.size()):
			var stored_item: ItemData = provider.runtime_storage_items[i]
			var stored_crop_type_id: StringName = _resolve_crop_type_for_item(stored_item)
			if not String(stored_crop_type_id).is_empty():
				return {
					"source": "storage",
					"provider": provider,
					"slot_index": i,
					"item": stored_item,
					"crop_type_id": stored_crop_type_id
				}

	return {}


func _get_seed_source_equipment_slots() -> Array[int]:
	return [
		ItemData.ItemType.Lefthand,
		ItemData.ItemType.T_shirts,
		ItemData.ItemType.Jacket,
		ItemData.ItemType.HeavyArmour,
		ItemData.ItemType.Trousers,
		ItemData.ItemType.Bag,
		ItemData.ItemType.Cap
	]


func _resolve_crop_type_for_item(item: ItemData) -> StringName:
	if item == null:
		return StringName()
	var definition := item.get_definition() if item.has_method("get_definition") else item
	for crop_type_key in _crop_configs_by_type.keys():
		var crop_type_id: StringName = crop_type_key
		var config: Dictionary = _crop_configs_by_type[crop_type_id]
		var crop_item := config.get("item", null) as ItemData
		if _is_same_crop_item(item, definition, crop_item):
			return crop_type_id
	return StringName()


func _is_same_crop_item(runtime_item: ItemData, definition: ItemData, crop_item: ItemData) -> bool:
	if runtime_item == null or crop_item == null:
		return false
	if definition == crop_item:
		return true
	if definition != null and not definition.resource_path.is_empty() and definition.resource_path == crop_item.resource_path:
		return true
	return runtime_item.item_name.strip_edges().to_lower() == crop_item.item_name.strip_edges().to_lower()


func _resolve_crop_type_for_crop(crop: Node) -> StringName:
	if crop == null:
		return CROP_TYPE_PEPPER

	var raw_cell: Variant = crop.get("farm_cell")
	if raw_cell is Vector2i:
		var cell: Vector2i = raw_cell
		if _crop_type_by_cell.has(cell):
			return _crop_type_by_cell[cell]

	for cell_key in _crops_by_cell.keys():
		if _crops_by_cell[cell_key] == crop:
			var mapped_cell: Vector2i = cell_key if cell_key is Vector2i else Vector2i.ZERO
			return _crop_type_by_cell.get(mapped_cell, CROP_TYPE_PEPPER)

	return CROP_TYPE_PEPPER


func _refresh_inventory_ui() -> void:
	var inventory_root := get_tree().get_first_node_in_group("inventory_root")
	if inventory_root != null and inventory_root.has_method("refresh_ui"):
		inventory_root.call("refresh_ui")


func _get_current_game_minutes() -> float:
	var clock := get_tree().get_first_node_in_group("game_clock")
	if clock != null and clock.has_method("get_game_time_total_minutes"):
		return float(clock.call("get_game_time_total_minutes"))
	return float(Time.get_ticks_msec()) / 1000.0


func _get_cell_world_position(cell: Vector2i) -> Vector2:
	if _farm_layer != null:
		return _farm_layer.to_global(_farm_layer.map_to_local(cell))
	return _ground_layer.to_global(_ground_layer.map_to_local(cell))


func _get_mouse_ground_cell() -> Vector2i:
	var world_pos := get_global_mouse_position()
	if _preview_layer != null:
		return _preview_layer.local_to_map(_preview_layer.to_local(world_pos))
	if _farm_layer != null:
		return _farm_layer.local_to_map(_farm_layer.to_local(world_pos))
	return _ground_layer.local_to_map(_ground_layer.to_local(world_pos))


func _can_place_at_cell(cell: Vector2i) -> bool:
	if _ground_layer == null or _farm_layer == null:
		return false
	var world_pos := _get_cell_world_position(cell)
	var ground_cell := _ground_layer.local_to_map(_ground_layer.to_local(world_pos))
	if _ground_layer.get_cell_source_id(ground_cell) == -1:
		return false
	if _farm_layer.get_cell_source_id(cell) != -1:
		return false
	if _is_cell_blocked_by_other_layer(world_pos):
		return false
	if _is_cell_blocked_by_collision(world_pos):
		return false
	if not _is_cell_in_player_range(world_pos):
		return false
	return true


func _is_cell_blocked_by_other_layer(world_pos: Vector2) -> bool:
	for layer in _blocked_layers:
		if layer == null or not is_instance_valid(layer):
			continue
		var layer_cell := layer.local_to_map(layer.to_local(world_pos))
		if layer.get_cell_source_id(layer_cell) != -1:
			return true
	return false


func _is_cell_blocked_by_collision(world_pos: Vector2) -> bool:
	if placement_collision_mask == 0:
		return false

	var space_state := get_world_2d().direct_space_state
	if space_state == null:
		return false

	var tile_size := _get_ground_tile_size()
	var world_scale := _ground_layer.global_scale.abs()
	_placement_collision_shape.size = Vector2(
		float(tile_size.x) * maxf(world_scale.x, 0.001) * placement_collision_cell_scale,
		float(tile_size.y) * maxf(world_scale.y, 0.001) * placement_collision_cell_scale
	)

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _placement_collision_shape
	query.transform = Transform2D(0.0, world_pos)
	query.collision_mask = placement_collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var hits := space_state.intersect_shape(query, 16)
	for hit in hits:
		var collider: Object = hit.get("collider", null)
		if collider == null:
			continue
		if _is_ignored_placement_collider(collider):
			continue
		return true

	return false


func _is_ignored_placement_collider(collider: Object) -> bool:
	return collider == _ground_layer or collider == _farm_layer or collider == _preview_layer


func _is_cell_in_player_range(world_pos: Vector2) -> bool:
	if max_placement_distance_px <= 0.0:
		return true

	var player := _resolve_player()
	if player == null:
		return true

	return player.global_position.distance_to(world_pos) <= max_placement_distance_px


func _resolve_player() -> Node2D:
	var configured_player := get_node_or_null(player_path) as Node2D
	if configured_player != null:
		return configured_player

	return get_tree().get_first_node_in_group("player") as Node2D
