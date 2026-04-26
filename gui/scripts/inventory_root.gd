extends Control

const SLOT_SCENE = preload("res://gui/slots/InventorySlot.tscn")
const LOOT_PROVIDER_SLOT_TYPE: int = 999
const LOOT_CONTEXT_WARDROBE: StringName = &"wardrobe"
const LOOT_CONTEXT_BANDIT: StringName = &"bandit"

@export var pickup_item_scene: PackedScene
@export var remove_attachment_dropdown_offset: Vector2 = Vector2(0.0, 6.0)
@export var remove_attachment_button_offset: Vector2 = Vector2(0.0, 40.0)

@onready var inventory_content: Control = $InventoryContent
@onready var inventory_grid: GridContainer = $InventoryContent/NavInv/NearbyPanel/InventoryGrid
@onready var drag_anchor: Control = $InventoryContent/Anchor
@onready var wardrobe_loot_panel: Control = $InventoryContent/Lut/Lut
@onready var wardrobe_loot_grid: GridContainer = $InventoryContent/Lut/Lut/CenterContainer/LutContainer
@onready var bandit_loot_panel: Control = $InventoryContent/Lut/BanditLut
@onready var bandit_loot_grid: GridContainer = $InventoryContent/Lut/BanditLut/CenterContainer/GridContainer

@onready var inv_btn: Control = $InventoryContent/NavBtns/InvBtn
@onready var map_btn: Control = $InventoryContent/NavBtns/MapBtn
@onready var craft_btn: Control = $InventoryContent/NavBtns/CraftBtn

@onready var jacket_storage_panel: Control = $InventoryContent/NavInv/Jacket/ClothingStoragePanel
@onready var jacket_storage_grid: GridContainer = $InventoryContent/NavInv/Jacket/ClothingStoragePanel/ClothingStorageGrid
@onready var heavy_armour_storage_panel: Control = $InventoryContent/NavInv/HeavyArmour/HeavyArmourStoragePanel
@onready var heavy_armour_storage_grid: GridContainer = $InventoryContent/NavInv/HeavyArmour/HeavyArmourStoragePanel/HeavyArmourStorageGrid
@onready var trousers_storage_panel: Control = $InventoryContent/NavInv/Trousers/TrousersStoragePanel
@onready var trousers_storage_grid: GridContainer = $InventoryContent/NavInv/Trousers/TrousersStoragePanel/TrousersStorageGrid
@onready var bag_storage_panel: Control = $InventoryContent/NavInv/Bag/BagStoragePanel
@onready var bag_storage_grid: GridContainer = $InventoryContent/NavInv/Bag/BagStoragePanel/BagStorageGrid

var is_inventory_open: bool = false
var drag_in_progress_data: Dictionary = {}
var inventory_drag_active: bool = false
var inventory_drag_offset: Vector2 = Vector2.ZERO
var loot_context_active: bool = false
var active_loot_context: StringName = LOOT_CONTEXT_WARDROBE
var active_bandit_loot_source_id: int = 0
var loot_slots: Array[InventorySlot] = []
var loot_provider: ItemData = null

var equipment_slots: Array[InventorySlot] = []

var storage_slots_by_type: Dictionary = {}
var consume_button: Button = null
var consume_slot: InventorySlot = null
var use_medical_button: Button = null
var use_medical_slot: InventorySlot = null
var pending_medical_item: ItemData = null
var pending_medical_mode: int = -1
var pending_medical_slot_type: int = -1
var pending_medical_container_index: int = -1
var equip_ammo_button: Button = null
var equip_ammo_slot: InventorySlot = null
var install_scope_button: Button = null
var install_scope_slot: InventorySlot = null
var remove_scope_button: Button = null
var remove_scope_slot: InventorySlot = null
var remove_attachment_dropdown: OptionButton = null


func _ready() -> void:
	add_to_group("inventory_root")
	loot_provider = ItemData.new()
	inventory_content.visible = false
	_setup_loot_grids()
	set_loot_context_active(false, active_loot_context)

	inventory_grid.columns = 1
	inventory_grid.add_theme_constant_override("h_separation", 8)
	inventory_grid.add_theme_constant_override("v_separation", 10)

	_setup_storage_panel(jacket_storage_panel, jacket_storage_grid)
	_setup_storage_panel(heavy_armour_storage_panel, heavy_armour_storage_grid)
	_setup_storage_panel(trousers_storage_panel, trousers_storage_grid)
	_setup_storage_panel(bag_storage_panel, bag_storage_grid)
	storage_slots_by_type[ItemData.ItemType.Jacket] = []
	storage_slots_by_type[ItemData.ItemType.HeavyArmour] = []
	storage_slots_by_type[ItemData.ItemType.Trousers] = []
	storage_slots_by_type[ItemData.ItemType.Bag] = []
	_ensure_consume_button()
	_ensure_use_medical_button()
	_ensure_equip_ammo_button()
	_ensure_scope_buttons()

	_setup_nav_buttons_z()

	_collect_equipment_slots()
	_connect_equipment_slots()
	_setup_equipment_slot_visuals()

	if not NearbyItemsManager.nearby_items_changed.is_connected(_on_nearby_items_changed):
		NearbyItemsManager.nearby_items_changed.connect(_on_nearby_items_changed)
	if InventoryManager.has_signal("equipment_changed") and not InventoryManager.equipment_changed.is_connected(_on_equipment_changed):
		InventoryManager.equipment_changed.connect(_on_equipment_changed)
	if InventoryManager.has_signal("ammo_state_changed") and not InventoryManager.ammo_state_changed.is_connected(_on_ammo_state_changed):
		InventoryManager.ammo_state_changed.connect(_on_ammo_state_changed)

	refresh_ui()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory_toggle"):
		toggle_inventory()
		get_viewport().set_input_as_handled()
		return

	if not is_inventory_open:
		inventory_drag_active = false
		return

	if event is InputEventMouseButton:
		var mouse_button_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_button_event.pressed and _is_mouse_in_inventory_drag_zone():
				inventory_drag_active = true
				inventory_drag_offset = inventory_content.global_position - get_global_mouse_position()
				get_viewport().set_input_as_handled()
			else:
				inventory_drag_active = false
		return

	if event is InputEventMouseMotion and inventory_drag_active:
		inventory_content.global_position = get_global_mouse_position() + inventory_drag_offset
		_clamp_inventory_content_to_viewport()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == Node.NOTIFICATION_DRAG_BEGIN:
		var data: Variant = get_viewport().gui_get_drag_data()
		if typeof(data) == TYPE_DICTIONARY and data.has("item"):
			drag_in_progress_data = (data as Dictionary).duplicate()

	elif what == Node.NOTIFICATION_DRAG_END:
		if drag_in_progress_data.is_empty():
			return

		var drag_successful: bool = get_viewport().gui_is_drag_successful()

		if not drag_successful:
			_drop_dragged_item_to_world(drag_in_progress_data)

		drag_in_progress_data.clear()
		refresh_ui()


func _on_bag_button_pressed() -> void:
	toggle_inventory()


func toggle_inventory() -> void:
	if is_inventory_open:
		close_inventory()
	else:
		open_inventory()


func open_inventory() -> void:
	is_inventory_open = true
	inventory_content.visible = true
	_clamp_inventory_content_to_viewport()
	_set_active_nav_button(inv_btn)
	set_loot_context_active(loot_context_active, active_loot_context)
	refresh_ui()


func close_inventory() -> void:
	is_inventory_open = false
	inventory_content.visible = false
	inventory_drag_active = false


func set_loot_context_active(active: bool, context: StringName = &"") -> void:
	loot_context_active = active
	if not context.is_empty():
		active_loot_context = context
	var show_wardrobe_loot: bool = loot_context_active and is_inventory_open and active_loot_context == LOOT_CONTEXT_WARDROBE
	var show_bandit_loot: bool = loot_context_active and is_inventory_open and active_loot_context == LOOT_CONTEXT_BANDIT
	if wardrobe_loot_panel != null:
		wardrobe_loot_panel.visible = show_wardrobe_loot
	if bandit_loot_panel != null:
		bandit_loot_panel.visible = show_bandit_loot


func open_loot_slots(slot_items: Array[ItemData]) -> void:
	_open_loot_slots(slot_items, LOOT_CONTEXT_WARDROBE)


func open_bandit_loot_slots(slot_items: Array[ItemData], source: Node = null) -> void:
	active_bandit_loot_source_id = 0 if source == null else int(source.get_instance_id())
	_open_loot_slots(slot_items, LOOT_CONTEXT_BANDIT)


func _open_loot_slots(slot_items: Array[ItemData], context: StringName) -> void:
	if loot_provider == null:
		loot_provider = ItemData.new()
	if context != LOOT_CONTEXT_BANDIT:
		active_bandit_loot_source_id = 0

	set_loot_context_active(true, context)
	loot_provider.runtime_storage_items = slot_items
	_rebuild_loot_slots(loot_provider.runtime_storage_items.size())

	if is_inventory_open:
		refresh_ui()
	else:
		open_inventory()


func close_bandit_loot_for(source: Node = null) -> void:
	if active_loot_context != LOOT_CONTEXT_BANDIT:
		return
	if source != null and active_bandit_loot_source_id != 0 and int(source.get_instance_id()) != active_bandit_loot_source_id:
		return

	active_bandit_loot_source_id = 0
	set_loot_context_active(false, LOOT_CONTEXT_WARDROBE)


func _setup_nav_buttons_z() -> void:
	var nav_buttons: Array[Control] = [inv_btn, map_btn, craft_btn]

	for button in nav_buttons:
		if button == null:
			continue
		button.z_as_relative = false
		button.z_index = 0


func _set_active_nav_button(active_button: Control) -> void:
	var nav_buttons: Array[Control] = [inv_btn, map_btn, craft_btn]

	for button in nav_buttons:
		if button == null:
			continue
		button.z_index = 0

	if active_button != null:
		active_button.z_index = 1


func _collect_equipment_slots() -> void:
	equipment_slots.clear()
	_find_equipment_slots_recursive(inventory_content)


func _find_equipment_slots_recursive(node: Node) -> void:
	if node == inventory_grid:
		return

	for child in node.get_children():
		if child == inventory_grid:
			continue

		if child is InventorySlot and child.slot_mode == InventorySlot.SlotMode.EQUIPMENT:
			equipment_slots.append(child)

		_find_equipment_slots_recursive(child)


func _connect_equipment_slots() -> void:
	for slot in equipment_slots:
		_connect_slot(slot)


func _connect_slot(slot: InventorySlot) -> void:
	if not slot.drop_requested.is_connected(_on_slot_drop_requested):
		slot.drop_requested.connect(_on_slot_drop_requested)
	if not slot.gui_input.is_connected(_on_slot_gui_input.bind(slot)):
		slot.gui_input.connect(_on_slot_gui_input.bind(slot))


func _on_nearby_items_changed() -> void:
	refresh_ui()


func _on_ammo_state_changed(_item: ItemData) -> void:
	refresh_ui()


func _on_equipment_changed(_slot_type: int, _item: ItemData) -> void:
	refresh_ui()


func refresh_ui() -> void:
	_hide_action_buttons()
	_rebuild_nearby_slots()

	for slot in equipment_slots:
		slot.set_equipped_item(InventoryManager.get_equipped(slot.slot_type))

	_refresh_clothing_storage_from_equipment()
	_refresh_clothing_storage_ui()
	_refresh_loot_ui()


func _rebuild_nearby_slots() -> void:
	for child in inventory_grid.get_children():
		child.queue_free()

	var nearby_items: Array = NearbyItemsManager.get_items()

	for i in range(nearby_items.size()):
		var world_item: Node = nearby_items[i]

		if not is_instance_valid(world_item):
			continue

		if world_item.item_data == null:
			continue

		var slot: InventorySlot = SLOT_SCENE.instantiate()
		slot.name = "NearbySlot_%d" % i

		_setup_nearby_slot(slot)
		_connect_slot(slot)

		inventory_grid.add_child(slot)
		slot.set_nearby_item(world_item.item_data, world_item, i)


func _setup_nearby_slot(slot: InventorySlot) -> void:
	slot.slot_mode = InventorySlot.SlotMode.NEARBY
	slot.custom_minimum_size = Vector2(235, 92)
	slot.icon_size = Vector2(68, 68)
	slot.icon_rotation_degrees = 0.0
	slot.icon_h_align = InventorySlot.IconHAlign.LEFT
	slot.icon_v_align = InventorySlot.IconVAlign.CENTER
	slot.show_name = true
	slot.show_endurance = true
	slot.stretch_icon_to_slot = false
	slot.show_background_in_nearby = false
	slot.show_background_in_equipment = true
	slot.show_background_in_container = true


func _setup_storage_panel(panel: Control, grid: GridContainer) -> void:
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 8)
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.mouse_filter = Control.MOUSE_FILTER_PASS


func _setup_container_slot(slot: InventorySlot, index: int) -> void:
	slot.slot_mode = InventorySlot.SlotMode.CONTAINER
	slot.container_index = index
	slot.allowed_storage_categories = [
		ItemData.StorageCategory.FOOD,
		ItemData.StorageCategory.MEDICAL,
		ItemData.StorageCategory.MISC
	]

	slot.custom_minimum_size = Vector2(60, 60)
	slot.icon_size = Vector2(120, 120)
	slot.icon_rotation_degrees = 0.0
	slot.show_name = false
	slot.show_endurance = false
	slot.stretch_icon_to_slot = true
	slot.icon_padding = 12.0


func _on_slot_drop_requested(target_slot: InventorySlot, data: Dictionary) -> void:
	if not data.has("item"):
		return
	if not data.has("source_mode"):
		return

	var dragged_item: ItemData = data.get("item", null)
	var source_mode: int = data.get("source_mode", -1)
	var raw_source_slot = data.get("source_slot", null)

	if dragged_item == null:
		return

	if target_slot == null or not is_instance_valid(target_slot):
		return

	match target_slot.slot_mode:
		InventorySlot.SlotMode.EQUIPMENT:
			_handle_drop_to_equipment(target_slot, data, dragged_item, source_mode, raw_source_slot)

		InventorySlot.SlotMode.CONTAINER:
			_handle_drop_to_clothing_container(target_slot, data, dragged_item, source_mode)

	refresh_ui()


func _handle_drop_to_equipment(
	target_slot: InventorySlot,
	data: Dictionary,
	dragged_item: ItemData,
	source_mode: int,
	raw_source_slot
) -> void:
	var can_equip: bool = false

	if target_slot.use_allowed_item_types and not target_slot.allowed_item_types.is_empty():
		can_equip = dragged_item.item_type in target_slot.allowed_item_types
	elif not target_slot.allowed_storage_categories.is_empty():
		can_equip = dragged_item.can_be_stored_in_clothing and dragged_item.storage_category in target_slot.allowed_storage_categories
	else:
		can_equip = dragged_item.item_type == target_slot.slot_type

	if not can_equip:
		return

	match source_mode:
		InventorySlot.SlotMode.NEARBY:
			var target_equipped: ItemData = InventoryManager.get_equipped(target_slot.slot_type)
			var moved_to_equipped: int = _stack_items(target_equipped, dragged_item)
			if dragged_item.stack_count <= 0:
				var source_world_item: Node = data.get("world_item", null)
				if is_instance_valid(source_world_item):
					if source_world_item.has_method("remove_from_world"):
						source_world_item.remove_from_world()
					else:
						source_world_item.queue_free()
				return
			if moved_to_equipped > 0:
				return

			_equip_from_nearby_to_slot(target_slot, data, dragged_item)

		InventorySlot.SlotMode.EQUIPMENT:
			if raw_source_slot == null or not is_instance_valid(raw_source_slot):
				return

			var source_slot: InventorySlot = raw_source_slot as InventorySlot

			if source_slot == target_slot:
				return

			if target_slot.use_allowed_item_types or source_slot.use_allowed_item_types:
				return

			_swap_equipped_slots(source_slot.slot_type, target_slot.slot_type)

		InventorySlot.SlotMode.CONTAINER:
			var source_index: int = data.get("container_index", -1)
			var source_binding: Dictionary = _decode_storage_binding(source_index)
			if source_binding.is_empty():
				return

			var source_provider: ItemData = source_binding.get("provider", null)
			var source_slot_index: int = int(source_binding.get("slot_index", -1))
			if source_provider == null or source_slot_index < 0:
				return

			var source_item: ItemData = source_provider.runtime_storage_items[source_slot_index]
			if source_item == null:
				return

			var existing_item: ItemData = InventoryManager.get_equipped(target_slot.slot_type)
			var moved_to_existing: int = _stack_items(existing_item, source_item)
			if source_item.stack_count <= 0:
				source_provider.runtime_storage_items[source_slot_index] = null
				return
			if moved_to_existing > 0:
				return

			var old_equipped: ItemData = InventoryManager.get_equipped(target_slot.slot_type)
			if old_equipped != null:
				_spawn_world_item(old_equipped)

			source_provider.runtime_storage_items[source_slot_index] = null
			InventoryManager.set_equipped(target_slot.slot_type, source_item)


func _handle_drop_to_clothing_container(
	target_slot: InventorySlot,
	data: Dictionary,
	dragged_item: ItemData,
	source_mode: int
) -> void:
	var target_binding: Dictionary = _decode_storage_binding(target_slot.container_index)
	if target_binding.is_empty():
		return

	var target_provider: ItemData = target_binding.get("provider", null)
	var target_index: int = int(target_binding.get("slot_index", -1))
	if target_provider == null or target_index < 0:
		return

	var target_item: ItemData = target_provider.runtime_storage_items[target_index]

	match source_mode:
		InventorySlot.SlotMode.NEARBY:
			var world_item: Node = data.get("world_item", null)
			var moved_to_target: int = _stack_items(target_item, dragged_item)
			if dragged_item.stack_count <= 0:
				if is_instance_valid(world_item):
					if world_item.has_method("remove_from_world"):
						world_item.remove_from_world()
					else:
						world_item.queue_free()
				return
			if moved_to_target > 0:
				return

			if is_instance_valid(world_item):
				if world_item.has_method("remove_from_world"):
					world_item.remove_from_world()
				else:
					world_item.queue_free()

			_set_bound_storage_item_or_drop_old(target_binding, dragged_item)

		InventorySlot.SlotMode.CONTAINER:
			var source_index: int = data.get("container_index", -1)
			var source_binding: Dictionary = _decode_storage_binding(source_index)
			if source_binding.is_empty():
				return

			if source_index == target_slot.container_index:
				return

			var source_provider: ItemData = source_binding.get("provider", null)
			var source_slot_index: int = int(source_binding.get("slot_index", -1))
			if source_provider == null or source_slot_index < 0:
				return

			var source_item: ItemData = source_provider.runtime_storage_items[source_slot_index]
			var moved_between_slots: int = _stack_items(target_item, source_item)
			if source_item.stack_count <= 0:
				source_provider.runtime_storage_items[source_slot_index] = null
				return
			if moved_between_slots > 0:
				return
			source_provider.runtime_storage_items[source_slot_index] = target_item
			target_provider.runtime_storage_items[target_index] = source_item

		InventorySlot.SlotMode.EQUIPMENT:
			var source_slot: InventorySlot = data.get("source_slot", null)
			if source_slot == null:
				return

			var equipped_item: ItemData = InventoryManager.get_equipped(source_slot.slot_type)
			if equipped_item == null:
				return

			var moved_from_equipped: int = _stack_items(target_item, equipped_item)
			if equipped_item.stack_count <= 0:
				InventoryManager.set_equipped(source_slot.slot_type, null)
				return
			if moved_from_equipped > 0:
				return

			InventoryManager.set_equipped(source_slot.slot_type, null)
			_set_bound_storage_item_or_drop_old(target_binding, equipped_item)


func _equip_from_nearby_to_slot(target_slot: InventorySlot, data: Dictionary, dragged_item: ItemData) -> void:
	var world_item: Node = data.get("world_item", null)

	if dragged_item == null:
		return

	var slot_type: int = target_slot.slot_type
	var old_equipped: ItemData = InventoryManager.get_equipped(slot_type)
	if old_equipped != null:
		_spawn_world_item(old_equipped)

	InventoryManager.set_equipped(slot_type, dragged_item)

	if is_instance_valid(world_item):
		if world_item.has_method("remove_from_world"):
			world_item.remove_from_world()
		else:
			world_item.queue_free()


func _swap_equipped_slots(source_type: int, target_type: int) -> void:
	if source_type == target_type:
		return

	var source_item: ItemData = InventoryManager.get_equipped(source_type)
	var target_item: ItemData = InventoryManager.get_equipped(target_type)

	if source_item == null:
		return

	if source_item.item_type != target_type:
		return

	if target_item != null and target_item.item_type != source_type:
		return

	InventoryManager.set_equipped(source_type, target_item)
	InventoryManager.set_equipped(target_type, source_item)


func _refresh_clothing_storage_from_equipment() -> void:
	_refresh_storage_provider(
		ItemData.ItemType.Jacket,
		jacket_storage_panel,
		jacket_storage_grid
	)
	_refresh_storage_provider(
		ItemData.ItemType.HeavyArmour,
		heavy_armour_storage_panel,
		heavy_armour_storage_grid
	)
	_refresh_storage_provider(
		ItemData.ItemType.Trousers,
		trousers_storage_panel,
		trousers_storage_grid
	)
	_refresh_storage_provider(
		ItemData.ItemType.Bag,
		bag_storage_panel,
		bag_storage_grid
	)


func _refresh_clothing_storage_ui() -> void:
	_refresh_storage_provider_ui(ItemData.ItemType.Jacket, jacket_storage_panel)
	_refresh_storage_provider_ui(ItemData.ItemType.HeavyArmour, heavy_armour_storage_panel)
	_refresh_storage_provider_ui(ItemData.ItemType.Trousers, trousers_storage_panel)
	_refresh_storage_provider_ui(ItemData.ItemType.Bag, bag_storage_panel)


func pickup_first_nearby_item() -> bool:
	var world_item: Node = _get_closest_nearby_item()
	if world_item == null or not is_instance_valid(world_item):
		return false

	return _pickup_world_item(world_item)


func _clear_clothing_storage() -> void:
	_clear_storage_provider(ItemData.ItemType.Jacket, jacket_storage_panel)
	_clear_storage_provider(ItemData.ItemType.HeavyArmour, heavy_armour_storage_panel)
	_clear_storage_provider(ItemData.ItemType.Trousers, trousers_storage_panel)
	_clear_storage_provider(ItemData.ItemType.Bag, bag_storage_panel)


func _clear_clothing_storage_ui_only() -> void:
	for slot_type in storage_slots_by_type.keys():
		var slots: Array = storage_slots_by_type.get(slot_type, [])
		for slot in slots:
			if is_instance_valid(slot):
				slot.queue_free()
		storage_slots_by_type[slot_type] = []


func _drop_dragged_item_to_world(data: Dictionary) -> void:
	if not data.has("item"):
		return
	if not data.has("source_mode"):
		return

	var item: ItemData = data.get("item", null)
	var source_mode: int = data.get("source_mode", -1)

	if item == null:
		return

	match source_mode:
		InventorySlot.SlotMode.NEARBY:
			var world_item: Node = data.get("world_item", null)

			if is_instance_valid(world_item):
				if world_item.has_method("remove_from_world"):
					world_item.remove_from_world()
				else:
					world_item.queue_free()

			_spawn_world_item(item)

		InventorySlot.SlotMode.EQUIPMENT:
			var source_slot: InventorySlot = data.get("source_slot", null)
			if source_slot == null:
				return

			var equipped_item: ItemData = InventoryManager.get_equipped(source_slot.slot_type)
			if equipped_item == null:
				return

			InventoryManager.set_equipped(source_slot.slot_type, null)
			_spawn_world_item(equipped_item)

		InventorySlot.SlotMode.CONTAINER:
			var source_index: int = data.get("container_index", -1)
			var source_binding: Dictionary = _decode_storage_binding(source_index)
			if source_binding.is_empty():
				return

			var source_provider: ItemData = source_binding.get("provider", null)
			var source_slot_index: int = int(source_binding.get("slot_index", -1))
			if source_provider == null or source_slot_index < 0:
				return

			var stored_item: ItemData = source_provider.runtime_storage_items[source_slot_index]
			if stored_item == null:
				return

			source_provider.runtime_storage_items[source_slot_index] = null
			_spawn_world_item(stored_item)


func _spawn_world_item(item: ItemData) -> void:
	if pickup_item_scene == null:
		push_warning("pickup_item_scene не назначена в inventory_root")
		return

	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		push_warning("Игрок не найден в группе 'player'")
		return

	var pickup: Node = pickup_item_scene.instantiate()
	var item_copy: ItemData = _clone_item_data(item)

	player.get_parent().add_child(pickup)

	if pickup.has_method("setup_from_item_data"):
		pickup.setup_from_item_data(item_copy)
	elif "item_data" in pickup:
		pickup.item_data = item_copy

	if pickup is Node2D and player is Node2D:
		var pickup_2d: Node2D = pickup as Node2D
		var player_2d: Node2D = player as Node2D
		var drop_offset: Vector2 = _get_drop_offset_for_player(player)
		pickup_2d.global_position = player_2d.global_position + drop_offset


func _clone_item_data(item: ItemData) -> ItemData:
	if item == null:
		return null

	if item.has_method("create_runtime_copy"):
		return item.create_runtime_copy()

	return item.duplicate(true)


func _get_closest_nearby_item() -> Node:
	var player_node: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if player_node == null:
		return null

	var best_item: Node = null
	var best_distance: float = INF
	for world_item in NearbyItemsManager.get_items():
		if not is_instance_valid(world_item):
			continue
		if not (world_item is Node2D):
			continue

		var distance: float = player_node.global_position.distance_to((world_item as Node2D).global_position)
		if distance < best_distance:
			best_distance = distance
			best_item = world_item

	return best_item


func _pickup_world_item(world_item: Node) -> bool:
	if world_item == null or not is_instance_valid(world_item):
		return false

	var item: ItemData = world_item.get("item_data") as ItemData
	if item == null:
		return false

	if item.is_ammo_item:
		_try_apply_picked_ammo_to_weapon_reserve(item)
		if item.stack_count <= 0:
			if world_item.has_method("remove_from_world"):
				world_item.remove_from_world()
			else:
				world_item.queue_free()
			refresh_ui()
			return true

	var equip_slot_type: int = -1
	if item.auto_place_into_equipment_on_pickup:
		equip_slot_type = _get_auto_equip_slot_type(item)
	if equip_slot_type != -1:
		var equipped_item: ItemData = InventoryManager.get_equipped(equip_slot_type)
		var moved_to_equip_slot: int = _stack_items(equipped_item, item)
		if item.stack_count <= 0:
			if world_item.has_method("remove_from_world"):
				world_item.remove_from_world()
			else:
				world_item.queue_free()
			refresh_ui()
			return true
		if moved_to_equip_slot > 0:
			refresh_ui()
			return true

		_replace_equipped_item_from_world(equip_slot_type, world_item, item)
		refresh_ui()
		return true

	if _try_store_picked_item(item):
		if world_item.has_method("remove_from_world"):
			world_item.remove_from_world()
		else:
			world_item.queue_free()
		refresh_ui()
		return true

	return false


func _try_apply_picked_ammo_to_weapon_reserve(ammo_item: ItemData) -> int:
	if ammo_item == null or not ammo_item.is_ammo_item:
		return 0
	if ammo_item.stack_count <= 0:
		return 0

	var target_weapon: ItemData = InventoryManager.get_equipped_weapon_by_ammo_type(ammo_item.ammo_type)
	if target_weapon == null:
		return 0

	var added_amount: int = InventoryManager.add_reserve_ammo(target_weapon, ammo_item.stack_count)
	if added_amount <= 0:
		return 0

	ammo_item.stack_count -= added_amount
	return added_amount


func _get_auto_equip_slot_type(item: ItemData) -> int:
	for slot in equipment_slots:
		if not _can_item_fit_equipment_slot(item, slot):
			continue

		if slot.allowed_storage_categories.is_empty():
			return slot.slot_type

	return -1


func _can_item_fit_equipment_slot(item: ItemData, slot: InventorySlot) -> bool:
	if slot.use_allowed_item_types and not slot.allowed_item_types.is_empty():
		return item.item_type in slot.allowed_item_types
	if not slot.allowed_storage_categories.is_empty():
		return item.can_be_stored_in_clothing and item.storage_category in slot.allowed_storage_categories
	return item.item_type == slot.slot_type


func _replace_equipped_item_from_world(slot_type: int, world_item: Node, item: ItemData) -> void:
	var old_item: ItemData = InventoryManager.get_equipped(slot_type)
	if old_item != null:
		_spawn_world_item(old_item)

	InventoryManager.set_equipped(slot_type, item)

	if world_item.has_method("remove_from_world"):
		world_item.remove_from_world()
	else:
		world_item.queue_free()


func _try_store_picked_item(item: ItemData) -> bool:
	var left_hand_slot: InventorySlot = _get_equipment_slot_by_type(ItemData.ItemType.Lefthand)
	var can_place_into_left_hand: bool = item.auto_place_into_equipment_on_pickup or item.can_be_held_in_left_hand
	if can_place_into_left_hand and left_hand_slot != null and _can_item_fit_equipment_slot(item, left_hand_slot):
		var old_left_hand: ItemData = InventoryManager.get_equipped(ItemData.ItemType.Lefthand)
		var moved_to_left_hand: int = _stack_items(old_left_hand, item)
		if item.stack_count <= 0:
			return true
		if moved_to_left_hand > 0:
			return true
		if old_left_hand == null:
			InventoryManager.set_equipped(ItemData.ItemType.Lefthand, item)
			return true

	if _try_store_item_in_first_free_container(item):
		return true

	if can_place_into_left_hand and left_hand_slot != null and _can_item_fit_equipment_slot(item, left_hand_slot):
		var old_item: ItemData = InventoryManager.get_equipped(ItemData.ItemType.Lefthand)
		if old_item != null:
			_spawn_world_item(old_item)
		InventoryManager.set_equipped(ItemData.ItemType.Lefthand, item)
		return true

	return false


func _try_store_item_in_first_free_container(item: ItemData) -> bool:
	for slot_type in [ItemData.ItemType.Jacket, ItemData.ItemType.HeavyArmour, ItemData.ItemType.Trousers, ItemData.ItemType.Bag]:
		var provider: ItemData = InventoryManager.get_equipped(slot_type)
		if provider == null or not provider.can_store_items:
			continue

		_ensure_storage_provider_size(provider)
		for i in range(provider.runtime_storage_items.size()):
			var moved_to_container: int = _stack_items(provider.runtime_storage_items[i], item)
			if item.stack_count <= 0:
				return true
			if moved_to_container > 0:
				return true
		for i in range(provider.runtime_storage_items.size()):
			if provider.runtime_storage_items[i] == null:
				provider.runtime_storage_items[i] = item
				return true

	return false


func _get_equipment_slot_by_type(slot_type: int) -> InventorySlot:
	for slot in equipment_slots:
		if slot.slot_type == slot_type:
			return slot
	return null


func _stack_items(target_item: ItemData, source_item: ItemData) -> int:
	if target_item == null or source_item == null:
		return 0
	if target_item == source_item:
		return 0
	if target_item.item_name != source_item.item_name:
		return 0
	if target_item.is_ammo_item != source_item.is_ammo_item:
		return 0
	if target_item.is_ammo_item and target_item.ammo_type != source_item.ammo_type:
		return 0
	if target_item.max_stack_size <= 1:
		return 0
	if target_item.stack_count >= target_item.max_stack_size:
		return 0

	var free_space: int = target_item.max_stack_size - target_item.stack_count
	var moved: int = min(free_space, source_item.stack_count)
	if moved <= 0:
		return 0

	target_item.stack_count += moved
	source_item.stack_count -= moved
	return moved


func _get_drop_offset_for_player(player: Node) -> Vector2:
	if not ("facing_direction" in player):
		return Vector2(24, 24)

	match player.facing_direction:
		"up":
			return Vector2(0, -16)
		"down":
			return Vector2(0, 16)
		"left":
			return Vector2(-16, 0)
		"right":
			return Vector2(16, 0)
		_:
			return Vector2(14, 14)


func _setup_equipment_slot_visuals() -> void:
	for slot in equipment_slots:
		if slot.slot_type == ItemData.ItemType.Jacket:
			slot.stretch_icon_to_slot = false
			slot.icon_size = Vector2(52, 52)
			slot.icon_h_align = InventorySlot.IconHAlign.CENTER
			slot.icon_v_align = InventorySlot.IconVAlign.TOP
			slot.icon_rotation_degrees = 0.0
			slot.icon_padding = 0.0
			slot._apply_visual_mode()
		elif slot.slot_type == ItemData.ItemType.Trousers:
			slot.stretch_icon_to_slot = false
			slot.icon_size = Vector2(52, 52)
			slot.icon_h_align = InventorySlot.IconHAlign.CENTER
			slot.icon_v_align = InventorySlot.IconVAlign.TOP
			slot.icon_rotation_degrees = 0.0
			slot.icon_padding = 0.0
			slot._apply_visual_mode()
		elif slot.slot_type == ItemData.ItemType.Bag:
			slot.stretch_icon_to_slot = false
			slot.icon_h_align = InventorySlot.IconHAlign.CENTER
			slot.icon_v_align = InventorySlot.IconVAlign.TOP
			slot.icon_offset = Vector2(0, 12)
			slot._apply_visual_mode()


func _ensure_consume_button() -> void:
	if consume_button != null:
		return

	consume_button = Button.new()
	consume_button.text = "Съесть"
	consume_button.visible = false
	consume_button.custom_minimum_size = Vector2(78, 28)
	consume_button.pressed.connect(_consume_selected_food)
	inventory_content.add_child(consume_button)

func _ensure_storage_provider_size(provider: ItemData) -> void:
	if provider == null:
		return

	if provider.runtime_storage_items.size() == provider.extra_storage_slots:
		return

	var resized_storage: Array[ItemData] = []
	resized_storage.resize(provider.extra_storage_slots)

	for i in range(min(provider.runtime_storage_items.size(), provider.extra_storage_slots)):
		resized_storage[i] = provider.runtime_storage_items[i]

	provider.runtime_storage_items = resized_storage


func _set_bound_storage_item_or_drop_old(binding: Dictionary, new_item: ItemData) -> void:
	var provider: ItemData = binding.get("provider", null)
	var slot_index: int = int(binding.get("slot_index", -1))
	if provider == null or slot_index < 0 or slot_index >= provider.runtime_storage_items.size():
		return

	var old_item: ItemData = provider.runtime_storage_items[slot_index]
	if old_item != null:
		_spawn_world_item(old_item)

	provider.runtime_storage_items[slot_index] = new_item


func _refresh_storage_provider(slot_type: int, panel: Control, grid: GridContainer) -> void:
	var provider: ItemData = InventoryManager.get_equipped(slot_type)
	if provider == null or not provider.can_store_items or provider.extra_storage_slots <= 0:
		_clear_storage_provider(slot_type, panel)
		return

	_ensure_storage_provider_size(provider)

	var slots: Array = storage_slots_by_type.get(slot_type, [])
	if slots.size() != provider.extra_storage_slots:
		_rebuild_storage_provider(slot_type, panel, grid, provider.extra_storage_slots)

	panel.visible = true


func _rebuild_storage_provider(slot_type: int, panel: Control, grid: GridContainer, slots_count: int) -> void:
	var existing_slots: Array = storage_slots_by_type.get(slot_type, [])
	for slot in existing_slots:
		if is_instance_valid(slot):
			slot.queue_free()

	var new_slots: Array[InventorySlot] = []
	for i in range(slots_count):
		var slot: InventorySlot = SLOT_SCENE.instantiate()
		slot.name = "ClothingStorageSlot_%d_%d" % [slot_type, i]

		_setup_container_slot(slot, _encode_storage_index(slot_type, i))
		_connect_slot(slot)

		grid.add_child(slot)
		new_slots.append(slot)

	storage_slots_by_type[slot_type] = new_slots
	panel.visible = true


func _refresh_storage_provider_ui(slot_type: int, panel: Control) -> void:
	var provider: ItemData = InventoryManager.get_equipped(slot_type)
	var slots: Array = storage_slots_by_type.get(slot_type, [])

	if provider == null or not provider.can_store_items or provider.extra_storage_slots <= 0:
		panel.visible = false
		return

	panel.visible = true

	for i in range(slots.size()):
		var slot: InventorySlot = slots[i]
		if i >= provider.runtime_storage_items.size():
			slot.clear_slot()
			continue

		var item: ItemData = provider.runtime_storage_items[i]
		var encoded_index: int = _encode_storage_index(slot_type, i)

		if item == null:
			slot.clear_slot()
			slot.container_index = encoded_index
			slot.slot_mode = InventorySlot.SlotMode.CONTAINER
		else:
			slot.set_container_item(item, encoded_index)


func _on_slot_gui_input(event: InputEvent, slot: InventorySlot) -> void:
	if not (event is InputEventMouseButton):
		return

	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if not mouse_event.pressed:
		return

	if slot == null or slot.item_data == null:
		_hide_action_buttons()
		return

	if slot.slot_mode == InventorySlot.SlotMode.NEARBY:
		_hide_action_buttons()
		return

	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		_handle_slot_right_click(slot)
		return

	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	if _try_show_remove_scope_button_for_weapon(slot):
		return

	if slot.item_data.is_ammo_item:
		_show_equip_ammo_button_for_slot(slot)
		return

	if slot.item_data.storage_category == ItemData.StorageCategory.MEDICAL:
		_show_use_medical_button_for_slot(slot)
		return

	if slot.item_data.storage_category != ItemData.StorageCategory.FOOD:
		_hide_action_buttons()
		return

	_hide_equip_ammo_button()
	_hide_use_medical_button()
	consume_slot = slot
	consume_button.position = slot.global_position - inventory_content.global_position + Vector2(0.0, slot.size.y + 6.0)
	consume_button.visible = true


func _handle_slot_right_click(slot: InventorySlot) -> void:
	if slot == null or slot.item_data == null:
		_hide_action_buttons()
		return

	if slot.item_data.is_scope_attachment or slot.item_data.is_weapon_attachment:
		_show_install_scope_button_for_slot(slot)
		return

	_hide_action_buttons()


func _try_show_remove_scope_button_for_weapon(slot: InventorySlot) -> bool:
	var weapon_item: ItemData = slot.item_data
	if weapon_item == null:
		return false
	if weapon_item.storage_category != ItemData.StorageCategory.WEAPON:
		return false
	var attached_slots: Array[int] = _get_attached_attachment_slots(weapon_item)
	if attached_slots.is_empty():
		return false

	_hide_consume_button()
	_hide_use_medical_button()
	_hide_equip_ammo_button()
	_hide_install_scope_button()
	remove_scope_slot = slot
	_populate_remove_attachment_dropdown(weapon_item)
	var controls_origin: Vector2 = slot.global_position - inventory_content.global_position + Vector2(0.0, slot.size.y) + remove_attachment_dropdown_offset
	remove_attachment_dropdown.position = controls_origin
	remove_attachment_dropdown.visible = true
	remove_scope_button.position = controls_origin + remove_attachment_button_offset
	remove_scope_button.visible = true
	return true


func _hide_consume_button() -> void:
	consume_slot = null
	if consume_button != null:
		consume_button.visible = false


func _ensure_use_medical_button() -> void:
	if use_medical_button != null:
		return

	use_medical_button = Button.new()
	use_medical_button.text = "Использовать"
	use_medical_button.visible = false
	use_medical_button.custom_minimum_size = Vector2(120, 28)
	use_medical_button.pressed.connect(_use_selected_medical)
	inventory_content.add_child(use_medical_button)


func _show_use_medical_button_for_slot(slot: InventorySlot) -> void:
	_hide_consume_button()
	_hide_equip_ammo_button()
	_hide_install_scope_button()
	_hide_remove_scope_button()
	use_medical_slot = slot
	use_medical_button.position = slot.global_position - inventory_content.global_position + Vector2(0.0, slot.size.y + 6.0)
	use_medical_button.visible = true


func _hide_use_medical_button() -> void:
	use_medical_slot = null
	if use_medical_button != null:
		use_medical_button.visible = false


func _ensure_equip_ammo_button() -> void:
	if equip_ammo_button != null:
		return

	equip_ammo_button = Button.new()
	equip_ammo_button.text = "Снарядить"
	equip_ammo_button.visible = false
	equip_ammo_button.custom_minimum_size = Vector2(96, 28)
	equip_ammo_button.pressed.connect(_equip_selected_ammo)
	inventory_content.add_child(equip_ammo_button)


func _ensure_scope_buttons() -> void:
	if install_scope_button == null:
		install_scope_button = Button.new()
		install_scope_button.text = "Установить"
		install_scope_button.visible = false
		install_scope_button.custom_minimum_size = Vector2(110, 28)
		install_scope_button.pressed.connect(_install_selected_scope)
		inventory_content.add_child(install_scope_button)

	if remove_scope_button == null:
		remove_scope_button = Button.new()
		remove_scope_button.text = "Снять"
		remove_scope_button.visible = false
		remove_scope_button.custom_minimum_size = Vector2(86, 28)
		remove_scope_button.pressed.connect(_remove_scope_from_selected_weapon)
		inventory_content.add_child(remove_scope_button)

	if remove_attachment_dropdown == null:
		remove_attachment_dropdown = OptionButton.new()
		remove_attachment_dropdown.visible = false
		remove_attachment_dropdown.custom_minimum_size = Vector2(140, 28)
		inventory_content.add_child(remove_attachment_dropdown)


func _show_install_scope_button_for_slot(slot: InventorySlot) -> void:
	_hide_consume_button()
	_hide_use_medical_button()
	_hide_equip_ammo_button()
	_hide_remove_scope_button()
	install_scope_slot = slot
	install_scope_button.position = slot.global_position - inventory_content.global_position + Vector2(0.0, slot.size.y + 6.0)
	install_scope_button.visible = _can_install_scope(slot.item_data)


func _hide_install_scope_button() -> void:
	install_scope_slot = null
	if install_scope_button != null:
		install_scope_button.visible = false


func _hide_remove_scope_button() -> void:
	remove_scope_slot = null
	if remove_scope_button != null:
		remove_scope_button.visible = false
	if remove_attachment_dropdown != null:
		remove_attachment_dropdown.clear()
		remove_attachment_dropdown.visible = false


func _show_equip_ammo_button_for_slot(slot: InventorySlot) -> void:
	_hide_consume_button()
	_hide_use_medical_button()
	equip_ammo_slot = slot
	equip_ammo_button.position = slot.global_position - inventory_content.global_position + Vector2(0.0, slot.size.y + 6.0)
	equip_ammo_button.visible = true

	var ammo_item: ItemData = slot.item_data
	var weapon: ItemData = InventoryManager.get_equipped_weapon_by_ammo_type(ammo_item.ammo_type)
	if weapon != null and weapon.ammo_inventory_icon != null:
		equip_ammo_button.icon = weapon.ammo_inventory_icon
	else:
		equip_ammo_button.icon = null


func _hide_equip_ammo_button() -> void:
	equip_ammo_slot = null
	if equip_ammo_button != null:
		equip_ammo_button.visible = false
		equip_ammo_button.icon = null


func _hide_action_buttons() -> void:
	_hide_consume_button()
	_hide_use_medical_button()
	_hide_equip_ammo_button()
	_hide_install_scope_button()
	_hide_remove_scope_button()


func _consume_selected_food() -> void:
	if consume_slot == null or consume_slot.item_data == null:
		_hide_action_buttons()
		return

	var player_node: Node = get_tree().get_first_node_in_group("player")
	if player_node != null and player_node.has_method("start_timed_action"):
		if player_node.start_timed_action(0.8, Callable(self, "_finish_consume_selected_food"), "Еда"):
			return
		return

	_finish_consume_selected_food()


func _finish_consume_selected_food() -> void:
	if consume_slot == null or consume_slot.item_data == null:
		_hide_action_buttons()
		return

	var player_node: Node = get_tree().get_first_node_in_group("player")
	if player_node != null:
		if player_node.has_method("add_food"):
			player_node.add_food(consume_slot.item_data.food_restore_amount)
		if player_node.has_method("add_water"):
			player_node.add_water(consume_slot.item_data.water_restore_amount)
		if consume_slot.item_data.food_poison_chance > 0.0 and player_node.has_method("try_apply_food_poison"):
			player_node.try_apply_food_poison(consume_slot.item_data.food_poison_chance)

	var item: ItemData = consume_slot.item_data
	item.stack_count -= 1

	if item.stack_count <= 0:
		if consume_slot.slot_mode == InventorySlot.SlotMode.EQUIPMENT:
			InventoryManager.set_equipped(consume_slot.slot_type, null)
		elif consume_slot.slot_mode == InventorySlot.SlotMode.CONTAINER:
			var binding: Dictionary = _decode_storage_binding(consume_slot.container_index)
			var provider: ItemData = binding.get("provider", null)
			var slot_index: int = int(binding.get("slot_index", -1))
			if provider != null and slot_index >= 0 and slot_index < provider.runtime_storage_items.size():
				provider.runtime_storage_items[slot_index] = null

	_hide_action_buttons()
	refresh_ui()


func _use_selected_medical() -> void:
	if use_medical_slot == null or use_medical_slot.item_data == null:
		_clear_pending_medical_context()
		_hide_action_buttons()
		return

	pending_medical_item = use_medical_slot.item_data
	pending_medical_mode = use_medical_slot.slot_mode
	pending_medical_slot_type = use_medical_slot.slot_type
	pending_medical_container_index = use_medical_slot.container_index

	var use_time_sec: float = max(use_medical_slot.item_data.medical_use_time_sec, 0.1)
	var player_node: Node = get_tree().get_first_node_in_group("player")
	if player_node != null and player_node.has_method("start_timed_action"):
		if player_node.start_timed_action(use_time_sec, Callable(self, "_finish_use_selected_medical"), "Медицина", true, "Using"):
			return
		_clear_pending_medical_context()
		return

	_finish_use_selected_medical()


func _finish_use_selected_medical() -> void:
	if pending_medical_item == null:
		_clear_pending_medical_context()
		_hide_action_buttons()
		return

	var medical_item: ItemData = pending_medical_item
	var selected_mode: int = pending_medical_mode
	var selected_slot_type: int = pending_medical_slot_type
	var selected_container_index: int = pending_medical_container_index

	var player_node: Node = get_tree().get_first_node_in_group("player")
	var applied: bool = false
	if player_node != null:
		if player_node.has_method("apply_medical_item_effect"):
			applied = bool(player_node.apply_medical_item_effect(medical_item))
		if medical_item.medical_heal_fracture and player_node.has_method("_set_fractured"):
			player_node.call("_set_fractured", false)
			applied = true
		if medical_item.medical_stop_bleeding and player_node.has_method("_set_bleeding"):
			player_node.call("_set_bleeding", false)
			applied = true

	if applied:
		_consume_medical_item_from_source(medical_item, selected_mode, selected_slot_type, selected_container_index)
	_clear_pending_medical_context()

	_hide_action_buttons()
	refresh_ui()


func _consume_medical_item_from_source(medical_item: ItemData, selected_mode: int, selected_slot_type: int, selected_container_index: int) -> void:
	if medical_item == null:
		return

	if selected_mode == InventorySlot.SlotMode.EQUIPMENT:
		if InventoryManager.get_equipped(selected_slot_type) == medical_item:
			if medical_item.stack_count > 1:
				medical_item.stack_count -= 1
			else:
				InventoryManager.set_equipped(selected_slot_type, null)
		return

	if selected_mode != InventorySlot.SlotMode.CONTAINER:
		return

	var binding: Dictionary = _decode_storage_binding(selected_container_index)
	var provider: ItemData = binding.get("provider", null)
	var slot_index: int = int(binding.get("slot_index", -1))
	if provider == null:
		return

	if slot_index >= 0 and slot_index < provider.runtime_storage_items.size() and provider.runtime_storage_items[slot_index] == medical_item:
		if medical_item.stack_count > 1:
			medical_item.stack_count -= 1
		else:
			provider.runtime_storage_items[slot_index] = null
		return

	for i in range(provider.runtime_storage_items.size()):
		if provider.runtime_storage_items[i] == medical_item:
			if medical_item.stack_count > 1:
				medical_item.stack_count -= 1
			else:
				provider.runtime_storage_items[i] = null
			return


func _clear_pending_medical_context() -> void:
	pending_medical_item = null
	pending_medical_mode = -1
	pending_medical_slot_type = -1
	pending_medical_container_index = -1


func _equip_selected_ammo() -> void:
	if equip_ammo_slot == null or equip_ammo_slot.item_data == null:
		_hide_action_buttons()
		return

	var selected_slot: InventorySlot = equip_ammo_slot
	var selected_mode: int = selected_slot.slot_mode
	var selected_slot_type: int = selected_slot.slot_type
	var selected_container_index: int = selected_slot.container_index
	var ammo_item: ItemData = selected_slot.item_data
	var applied_amount: int = _try_apply_picked_ammo_to_weapon_reserve(ammo_item)
	if applied_amount <= 0:
		return

	if ammo_item.stack_count <= 0:
		if selected_mode == InventorySlot.SlotMode.EQUIPMENT:
			InventoryManager.set_equipped(selected_slot_type, null)
		elif selected_mode == InventorySlot.SlotMode.CONTAINER:
			var binding: Dictionary = _decode_storage_binding(selected_container_index)
			var provider: ItemData = binding.get("provider", null)
			var slot_index: int = int(binding.get("slot_index", -1))
			if provider != null and slot_index >= 0 and slot_index < provider.runtime_storage_items.size():
				provider.runtime_storage_items[slot_index] = null

	_hide_action_buttons()
	refresh_ui()


func _can_install_scope(scope_item: ItemData) -> bool:
	if scope_item == null:
		return false
	if not (scope_item.is_scope_attachment or scope_item.is_weapon_attachment):
		return false

	var weapon_item: ItemData = InventoryManager.get_equipped(ItemData.ItemType.AR_Weapon)
	if weapon_item == null:
		return false

	return InventoryManager.can_attach_attachment_to_weapon(scope_item, weapon_item)


func _install_selected_scope() -> void:
	if install_scope_slot == null or install_scope_slot.item_data == null:
		_hide_action_buttons()
		return

	var selected_slot: InventorySlot = install_scope_slot
	var selected_slot_mode: int = selected_slot.slot_mode
	var selected_slot_type: int = selected_slot.slot_type
	var selected_container_index: int = selected_slot.container_index
	var scope_item: ItemData = selected_slot.item_data
	var target_weapon: ItemData = InventoryManager.get_equipped(ItemData.ItemType.AR_Weapon)
	if target_weapon == null:
		_hide_action_buttons()
		return

	if not InventoryManager.set_attached_attachment(target_weapon, scope_item):
		_hide_action_buttons()
		return

	match selected_slot_mode:
		InventorySlot.SlotMode.EQUIPMENT:
			InventoryManager.set_equipped(selected_slot_type, null)
		InventorySlot.SlotMode.CONTAINER:
			var scope_binding: Dictionary = _decode_storage_binding(selected_container_index)
			var provider: ItemData = scope_binding.get("provider", null)
			var slot_index: int = int(scope_binding.get("slot_index", -1))
			if provider != null and slot_index >= 0 and slot_index < provider.runtime_storage_items.size():
				provider.runtime_storage_items[slot_index] = null

	_hide_action_buttons()
	refresh_ui()


func _remove_scope_from_selected_weapon() -> void:
	if remove_scope_slot == null or remove_scope_slot.item_data == null:
		_hide_action_buttons()
		return

	var weapon_item: ItemData = remove_scope_slot.item_data
	var selected_slot_type: int = _get_selected_remove_attachment_slot()
	if selected_slot_type == -1:
		_hide_action_buttons()
		return

	var detached_scope: ItemData = InventoryManager.detach_attached_attachment(weapon_item, selected_slot_type)
	if detached_scope == null:
		_hide_action_buttons()
		return

	if not _try_store_item_in_first_free_container(detached_scope):
		_spawn_world_item(detached_scope)

	_hide_action_buttons()
	refresh_ui()


func _get_attached_attachment_slots(weapon_item: ItemData) -> Array[int]:
	var result: Array[int] = []
	if weapon_item == null:
		return result

	for slot_type in [ItemData.AttachmentSlot.SCOPE, ItemData.AttachmentSlot.HANDLE, ItemData.AttachmentSlot.SILENCER]:
		if InventoryManager.get_attached_attachment(weapon_item, slot_type) != null:
			result.append(slot_type)

	return result


func _populate_remove_attachment_dropdown(weapon_item: ItemData) -> void:
	if remove_attachment_dropdown == null:
		return

	remove_attachment_dropdown.clear()
	for slot_type in _get_attached_attachment_slots(weapon_item):
		var attached_item: ItemData = InventoryManager.get_attached_attachment(weapon_item, slot_type)
		if attached_item == null:
			continue
		var item_label: String = "%s: %s" % [_attachment_slot_display_name(slot_type), attached_item.item_name]
		remove_attachment_dropdown.add_item(item_label, slot_type)

	if remove_attachment_dropdown.item_count > 0:
		remove_attachment_dropdown.select(0)


func _get_selected_remove_attachment_slot() -> int:
	if remove_attachment_dropdown == null:
		return -1
	var selected_index: int = remove_attachment_dropdown.get_selected()
	if selected_index < 0 or selected_index >= remove_attachment_dropdown.item_count:
		return -1
	return remove_attachment_dropdown.get_item_id(selected_index)


func _attachment_slot_display_name(slot_type: int) -> String:
	match slot_type:
		ItemData.AttachmentSlot.SCOPE:
			return "Прицел"
		ItemData.AttachmentSlot.HANDLE:
			return "Рукоять"
		ItemData.AttachmentSlot.SILENCER:
			return "Глушитель"
		_:
			return "Модуль"


func _clear_storage_provider(slot_type: int, panel: Control) -> void:
	var slots: Array = storage_slots_by_type.get(slot_type, [])
	for slot in slots:
		if is_instance_valid(slot):
			slot.queue_free()

	storage_slots_by_type[slot_type] = []
	panel.visible = false


func _encode_storage_index(slot_type: int, slot_index: int) -> int:
	return slot_type * 100 + slot_index


func _decode_storage_binding(encoded_index: int) -> Dictionary:
	if encoded_index < 0:
		return {}

	var slot_type: int = int(encoded_index / 100.0)
	var slot_index: int = int(encoded_index % 100)
	if slot_type == LOOT_PROVIDER_SLOT_TYPE:
		if loot_provider == null:
			return {}
		return {
			"provider": loot_provider,
			"slot_index": slot_index
		}

	var provider: ItemData = InventoryManager.get_equipped(slot_type)
	if provider == null:
		return {}

	return {
		"provider": provider,
		"slot_index": slot_index
	}


func _setup_loot_grids() -> void:
	_setup_single_loot_grid(wardrobe_loot_grid, 2)
	_setup_single_loot_grid(bandit_loot_grid, 2)
	_rebuild_loot_slots(0)


func _setup_single_loot_grid(grid: GridContainer, columns: int) -> void:
	if grid == null:
		return

	grid.columns = max(columns, 1)
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)


func _get_active_loot_grid() -> GridContainer:
	if active_loot_context == LOOT_CONTEXT_BANDIT:
		return bandit_loot_grid
	return wardrobe_loot_grid


func _rebuild_loot_slots(slot_count: int) -> void:
	var active_loot_grid: GridContainer = _get_active_loot_grid()
	if active_loot_grid == null:
		return

	for child in active_loot_grid.get_children():
		child.queue_free()
	loot_slots.clear()

	for i in range(max(slot_count, 0)):
		var slot: InventorySlot = SLOT_SCENE.instantiate()
		_setup_loot_slot(slot, i)
		_connect_slot(slot)
		active_loot_grid.add_child(slot)
		loot_slots.append(slot)


func _setup_loot_slot(slot: InventorySlot, slot_index: int) -> void:
	slot.slot_mode = InventorySlot.SlotMode.CONTAINER
	slot.container_index = _encode_storage_index(LOOT_PROVIDER_SLOT_TYPE, slot_index)
	slot.custom_minimum_size = Vector2(62, 62)
	slot.icon_size = Vector2(110, 110)
	slot.icon_rotation_degrees = 0.0
	slot.show_name = false
	slot.show_endurance = false
	slot.stretch_icon_to_slot = true
	slot.icon_padding = 8.0
	slot.show_background_in_container = true
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.clear_slot()


func _refresh_loot_ui() -> void:
	if loot_provider == null:
		return

	for i in range(loot_slots.size()):
		var slot: InventorySlot = loot_slots[i]
		if not is_instance_valid(slot):
			continue

		var encoded_index: int = _encode_storage_index(LOOT_PROVIDER_SLOT_TYPE, i)
		var item: ItemData = null
		if i < loot_provider.runtime_storage_items.size():
			item = loot_provider.runtime_storage_items[i]

		if item == null:
			slot.clear_slot()
			slot.slot_mode = InventorySlot.SlotMode.CONTAINER
			slot.container_index = encoded_index
		else:
			slot.set_container_item(item, encoded_index)


func _is_mouse_in_inventory_drag_zone() -> bool:
	if drag_anchor == null or not is_inventory_open or not drag_anchor.visible:
		return false

	var local_mouse_pos: Vector2 = drag_anchor.get_local_mouse_position()
	if not Rect2(Vector2.ZERO, drag_anchor.size).has_point(local_mouse_pos):
		return false

	return true


func _is_drag_blocked_by_control(control: Control) -> bool:
	var current: Node = control
	while current != null:
		if current == inv_btn or current == map_btn or current == craft_btn:
			return true
		if current is Button:
			return true
		if current is InventorySlot:
			return true
		current = current.get_parent()

	return false


func _clamp_inventory_content_to_viewport() -> void:
	if inventory_content == null:
		return

	var viewport_size: Vector2 = get_viewport_rect().size
	var inventory_size: Vector2 = inventory_content.size * inventory_content.scale.abs()
	var max_x: float = max(viewport_size.x - inventory_size.x, 0.0)
	var max_y: float = max(viewport_size.y - inventory_size.y, 0.0)
	inventory_content.global_position = Vector2(
		clamp(inventory_content.global_position.x, 0.0, max_x),
		clamp(inventory_content.global_position.y, 0.0, max_y)
	)
