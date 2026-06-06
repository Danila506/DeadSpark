extends Control

const SLOT_SCENE = preload("res://gui/slots/InventorySlot.tscn")
const LOOT_PROVIDER_SLOT_TYPE: int = 999
const LOOT_CONTEXT_WARDROBE: StringName = &"wardrobe"
const LOOT_CONTEXT_BANDIT: StringName = &"bandit"
const WOOD_ITEM: ItemData = preload("res://Resources/Misc/wood.tres")
const STONE_ITEM: ItemData = preload("res://Resources/Misc/stone.tres")
const BANDAGE_ITEM: ItemData = preload("res://Resources/Medicine/bandage.tres")
const IMPROVISED_SPLINT_ITEM: ItemData = preload("res://Resources/Medicine/improvised_splint.tres")
const MEDICAL_SPLINT_ITEM: ItemData = preload("res://Resources/Medicine/splint.tres")
const AXE_ITEM: ItemData = preload("res://Resources/Melee/axe.tres")
const SHOVEL_ITEM: ItemData = preload("res://Resources/Melee/lopata/lopata.tres")
const CLEAVER_ITEM: ItemData = preload("res://Resources/Misc/cleaver.tres")
const HEMOSTAT_ITEM: ItemData = preload("res://Resources/Medicine/hemostat.tres")
const SALINE_ITEM: ItemData = preload("res://Resources/Medicine/saline.tres")
const HEALTH_BOX_ITEM: ItemData = preload("res://Resources/Medicine/healthBox.tres")
const BLOOD_BAG_ITEM: ItemData = preload("res://Resources/Medicine/bloodBag.tres")
const ANTIDOTE_ITEM: ItemData = preload("res://Resources/Medicine/antidote.tres")
const RESTORER_ITEM: ItemData = preload("res://Resources/Medicine/restorer.tres")
const POTASSIUM_IODIDE_ITEM: ItemData = preload("res://Resources/Medicine/potassium_iodide.tres")
const APPLE_ITEM: ItemData = preload("res://Resources/Food/apple.tres")
const MALINA_ITEM: ItemData = preload("res://Resources/Food/malina.tres")
const TOMATE_ITEM: ItemData = preload("res://Resources/Food/tomate.tres")
const PEPPER_ITEM: ItemData = preload("res://Resources/Food/pepper.tres")
const WOLF_MEAT_ITEM: ItemData = preload("res://Resources/Food/wolf_meat.tres")
const MATCHES_ITEM: ItemData = preload("res://Resources/Misc/matches.tres")
const ROPE_ITEM: ItemData = preload("res://Resources/Misc/rope.tres")
const LIGHTER_ITEM: ItemData = preload("res://Resources/Misc/lighter.tres")
const CIGARETTES_PACK_ITEM: ItemData = preload("res://Resources/Misc/cigarettes_pack.tres")
const GAS_CYLINDER_ITEM: ItemData = preload("res://Resources/Misc/gas_cylinder.tres")
const BATTERIES_ITEM: ItemData = preload("res://Resources/Misc/batteries.tres")
const ELECTRICAL_TAPE_ITEM: ItemData = preload("res://Resources/Misc/electrical_tape.tres")
const BURLAP_FABRIC_ITEM: ItemData = preload("res://Resources/Misc/burlap_fabric.tres")
const GAS_BURNER_ITEM: ItemData = preload("res://Resources/Misc/gas_burner.tres")
const SEWING_KIT_ITEM: ItemData = preload("res://Resources/Misc/sewing_kit.tres")
const GLUE_ITEM: ItemData = preload("res://Resources/Misc/glue.tres")
const WEAPON_CLEANING_KIT_ITEM: ItemData = preload("res://Resources/Misc/weapon_cleaning_kit.tres")
const GEIGER_COUNTER_ITEM: ItemData = preload("res://Resources/Misc/geiger_counter.tres")
const TWO_CRAFT_TEXTURE: Texture2D = preload("res://gui/Craft/twoCraft.png")
const THREE_CRAFT_TEXTURE: Texture2D = preload("res://gui/Craft/threeCraft.png")
const TWO_CRAFT_OUTLINE_TEXTURE: Texture2D = preload("res://gui/Craft/twoCraftOutline.png")
const THREE_CRAFT_OUTLINE_TEXTURE: Texture2D = preload("res://gui/Craft/threeCraftoutline.png")
const CRAFT_BUTTON_WIDTH: float = 28.0
const CRAFT_CATEGORY_ALL: StringName = &"all"
const CRAFT_CATEGORY_MEDICAL: StringName = &"medical"
const CRAFT_CATEGORY_FOOD: StringName = &"food"
const CRAFT_CATEGORY_TOOLS: StringName = &"tools"
const CRAFT_CATEGORY_BUILD: StringName = &"build"
const NETWORK_PICKUP_TIMEOUT_SEC: float = 1.5
const NETWORK_INVENTORY_ACTION_TIMEOUT_SEC: float = 1.5
const NETWORK_INVENTORY_ACTION_MIN_INTERVAL_MS: int = 60
const NETWORK_INVENTORY_ACTION_CRAFT_MIN_INTERVAL_MS: int = 150
const NETWORK_ALLOWED_INVENTORY_ACTIONS: Array[StringName] = [
	&"craft",
	&"consume_food",
	&"consume_food_finish",
	&"use_medical",
	&"finish_use_medical",
	&"equip_ammo"
]

@export var pickup_item_scene: PackedScene
@export var remove_attachment_dropdown_offset: Vector2 = Vector2(0.0, 6.0)
@export var remove_attachment_button_offset: Vector2 = Vector2(0.0, 40.0)
@export var craft_recipe_list_position: Vector2 = Vector2(148, 120)
@export var craft_recipe_list_size: Vector2 = Vector2(376, 414)
@export var craft_scroll_texture_travel_distance: float = 350.0
@export var mobile_safe_margin: Vector2 = Vector2(32.0, 32.0)
@export_range(0.5, 1.0, 0.01) var mobile_min_inventory_scale: float = 0.72
@export_range(0.2, 1.0, 0.05) var mobile_long_press_seconds: float = 0.45
@export var mobile_touch_drag_cancel_distance: float = 18.0

@onready var inventory_content: Control = $InventoryContent
@onready var nav_inv: Control = $InventoryContent/NavInv
@onready var nav_map: Control = $InventoryContent/NavMap
@onready var nav_craft: Control = $InventoryContent/NavCraft
@onready var inventory_grid: GridContainer = $InventoryContent/NavInv/NearbyPanel/InventoryGrid
@onready var drag_anchor: Control = $InventoryContent/Anchor
@onready var wardrobe_loot_panel: Control = $InventoryContent/Lut/Lut
@onready var wardrobe_loot_grid: GridContainer = $InventoryContent/Lut/Lut/CenterContainer/LutContainer
@onready var bandit_loot_panel: Control = $InventoryContent/Lut/BanditLut
@onready var bandit_loot_grid: GridContainer = $InventoryContent/Lut/BanditLut/CenterContainer/GridContainer

@onready var inv_btn: Control = $InventoryContent/NavBtns/InvBtn
@onready var map_btn: Control = $InventoryContent/NavBtns/MapBtn
@onready var craft_btn: Control = $InventoryContent/NavBtns/CraftBtn
@onready var craft_scroll_texture: Control = $InventoryContent/NavCraft/ScrollTexture if has_node("InventoryContent/NavCraft/ScrollTexture") else $InventoryContent/NavCraft/TextureButton
@onready var craft_right_panel: Control = $InventoryContent/NavCraft/RightPanel
@onready var craft_right_panel_center: CenterContainer = $InventoryContent/NavCraft/RightPanel/CenterContainer
@onready var craft_category_panel: Control = $InventoryContent/NavCraft/Categorypanel if has_node("InventoryContent/NavCraft/Categorypanel") else $InventoryContent/NavCraft/CategoryPanel

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
var nearby_slots: Array[InventorySlot] = []

var storage_slots_by_type: Dictionary = {}
var consume_button: Button = null
var consume_slot: InventorySlot = null
var use_medical_button: Button = null
var use_medical_slot: InventorySlot = null
var till_farm_row_button: Button = null
var till_farm_row_slot: InventorySlot = null
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
var craft_recipes: Array[Dictionary] = []
var craft_row_buttons: Array[Button] = []
var craft_row_recipe_indices: Array[int] = []
var craft_scroll: ScrollContainer = null
var craft_list: VBoxContainer = null
var craft_row_controls: Array[Control] = []
var craft_scroll_texture_start_y: float = 0.0
var craft_scroll_texture_travel: float = 0.0
var craft_scroll_texture_dragging: bool = false
var craft_scroll_texture_drag_start_mouse_y: float = 0.0
var craft_scroll_texture_drag_start_value: float = 0.0
var craft_scroll_texture_hit_rect: Rect2 = Rect2()
var selected_craft_recipe_index: int = -1
var craft_detail_icon: TextureRect = null
var craft_detail_title_label: Label = null
var craft_detail_description_label: Label = null
var craft_detail_button: Button = null
var active_craft_category: StringName = CRAFT_CATEGORY_ALL
var craft_category_buttons: Dictionary = {}
var mobile_touch_slot: InventorySlot = null
var mobile_touch_start_position: Vector2 = Vector2.ZERO
var mobile_touch_time_left: float = 0.0
var mobile_touch_long_press_triggered: bool = false
var mobile_touch_index: int = -1
var mobile_drag_active: bool = false
var mobile_drag_data: Dictionary = {}
var _network_pickup_pending: Dictionary = {}
var _network_inventory_action_next_request_id: int = 1
var _network_inventory_action_pending: Dictionary = {}
var _network_inventory_action_bypass: bool = false
var _network_server_last_inventory_action_ms_by_peer: Dictionary = {}
var _dev_console_panel: PanelContainer = null
var _dev_console_output: RichTextLabel = null
var _dev_console_input: LineEdit = null
var _dev_console_suggestions: ItemList = null
var _dev_console_open: bool = false
var _dev_item_path_by_id: Dictionary = {}
var _dev_item_ids_sorted: Array[String] = []
var _dev_item_paths_by_name: Dictionary = {}
var _dev_console_suggestion_values: Array[String] = []
var _dev_console_selected_suggestion: int = -1
var _dev_console_history: Array[String] = []
var _dev_console_history_index: int = -1
var _dev_console_aliases: Dictionary = {
	"g": "give",
	"gi": "give_inv",
	"s": "spawn",
	"ls": "list_items",
	"f": "find_item",
	"h": "help"
}


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
	_setup_storage_panel(heavy_armour_storage_panel, heavy_armour_storage_grid, 3)
	_setup_storage_panel(trousers_storage_panel, trousers_storage_grid)
	_setup_storage_panel(bag_storage_panel, bag_storage_grid)
	storage_slots_by_type[ItemData.ItemType.Jacket] = []
	storage_slots_by_type[ItemData.ItemType.HeavyArmour] = []
	storage_slots_by_type[ItemData.ItemType.Trousers] = []
	storage_slots_by_type[ItemData.ItemType.Bag] = []
	_ensure_consume_button()
	_ensure_use_medical_button()
	_ensure_till_farm_row_button()
	_ensure_equip_ammo_button()
	_ensure_scope_buttons()

	_setup_nav_buttons_z()
	_setup_nav_pages()
	_ensure_dev_console()
	_setup_craft_recipes()
	_setup_craft_categories()
	_setup_craft_rows()
	_setup_craft_detail_panel()

	_collect_equipment_slots()
	_connect_equipment_slots()
	_setup_equipment_slot_visuals()
	_apply_mobile_inventory_layout()
	set_process(true)

	if not NearbyItemsManager.nearby_items_changed.is_connected(_on_nearby_items_changed):
		NearbyItemsManager.nearby_items_changed.connect(_on_nearby_items_changed)
	if InventoryManager.has_signal("equipment_changed") and not InventoryManager.equipment_changed.is_connected(_on_equipment_changed):
		InventoryManager.equipment_changed.connect(_on_equipment_changed)
	if InventoryManager.has_signal("ammo_state_changed") and not InventoryManager.ammo_state_changed.is_connected(_on_ammo_state_changed):
		InventoryManager.ammo_state_changed.connect(_on_ammo_state_changed)

	refresh_ui()


func _input(event: InputEvent) -> void:
	if _handle_dev_console_input(event):
		get_viewport().set_input_as_handled()
		return

	if craft_scroll_texture_dragging:
		if event is InputEventScreenDrag:
			_drag_craft_scroll_texture((event as InputEventScreenDrag).position.y)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed:
			craft_scroll_texture_dragging = false
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseMotion:
			_drag_craft_scroll_texture((event as InputEventMouseMotion).global_position.y)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and not (event as InputEventMouseButton).pressed:
			craft_scroll_texture_dragging = false
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		var scroll_mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if scroll_mouse_button.button_index == MOUSE_BUTTON_LEFT and scroll_mouse_button.pressed and _is_mouse_over_craft_scroll_texture(scroll_mouse_button.global_position):
			_start_craft_scroll_texture_drag(scroll_mouse_button.global_position.y)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventScreenTouch:
		var scroll_touch: InputEventScreenTouch = event as InputEventScreenTouch
		if scroll_touch.pressed and _is_screen_position_over_craft_scroll_texture(scroll_touch.position):
			_start_craft_scroll_texture_drag(scroll_touch.position.y)
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("inventory_toggle"):
		toggle_inventory()
		get_viewport().set_input_as_handled()
		return

	if not is_inventory_open:
		inventory_drag_active = false
		_cancel_mobile_slot_touch()
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
	if event is InputEventScreenTouch:
		var touch_event: InputEventScreenTouch = event as InputEventScreenTouch
		if not touch_event.pressed and _event_matches_mobile_touch(touch_event.index):
			_finish_mobile_slot_touch(touch_event.position)
			return
		if touch_event.pressed and _is_screen_position_in_inventory_drag_zone(touch_event.position):
			inventory_drag_active = true
			inventory_drag_offset = inventory_content.global_position - touch_event.position
			get_viewport().set_input_as_handled()
		else:
			inventory_drag_active = false
		return

	if event is InputEventMouseMotion and inventory_drag_active:
		inventory_content.global_position = get_global_mouse_position() + inventory_drag_offset
		_clamp_inventory_content_to_viewport()
		get_viewport().set_input_as_handled()
	if event is InputEventScreenDrag and inventory_drag_active:
		inventory_content.global_position = (event as InputEventScreenDrag).position + inventory_drag_offset
		_clamp_inventory_content_to_viewport()
		get_viewport().set_input_as_handled()
	if event is InputEventScreenDrag and mobile_touch_slot != null:
		var slot_drag := event as InputEventScreenDrag
		if not _event_matches_mobile_touch(slot_drag.index):
			return
		if mobile_drag_active:
			get_viewport().set_input_as_handled()
			return
		if slot_drag.position.distance_to(mobile_touch_start_position) > mobile_touch_drag_cancel_distance:
			_start_mobile_slot_drag(slot_drag.position)
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if mobile_touch_slot == null or mobile_touch_long_press_triggered or mobile_drag_active:
		return
	mobile_touch_time_left -= delta
	if mobile_touch_time_left > 0.0:
		return
	mobile_touch_long_press_triggered = true
	_handle_slot_primary_press(mobile_touch_slot)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_mobile_inventory_layout.call_deferred()
		return

	if what == Node.NOTIFICATION_DRAG_BEGIN:
		var data: Variant = get_viewport().gui_get_drag_data()
		if typeof(data) == TYPE_DICTIONARY and data.has("item"):
			drag_in_progress_data = (data as Dictionary).duplicate()
			_cancel_mobile_slot_touch()

	elif what == Node.NOTIFICATION_DRAG_END:
		if drag_in_progress_data.is_empty():
			return

		var drag_successful: bool = get_viewport().gui_is_drag_successful()

		if not drag_successful:
			_drop_dragged_item_to_world(drag_in_progress_data)

		drag_in_progress_data.clear()
		_cancel_mobile_slot_touch()
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
	_apply_mobile_inventory_layout()
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
	var show_on_inventory_page: bool = nav_inv == null or nav_inv.visible
	var show_wardrobe_loot: bool = loot_context_active and is_inventory_open and show_on_inventory_page and active_loot_context == LOOT_CONTEXT_WARDROBE
	var show_bandit_loot: bool = loot_context_active and is_inventory_open and show_on_inventory_page and active_loot_context == LOOT_CONTEXT_BANDIT
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

	loot_provider.runtime_storage_items = slot_items
	_rebuild_loot_slots(loot_provider.runtime_storage_items.size())

	if is_inventory_open:
		_set_active_nav_button(inv_btn)
	else:
		open_inventory()
	set_loot_context_active(true, context)
	refresh_ui()


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
		if button.has_signal("pressed") and not button.pressed.is_connected(_on_nav_button_pressed.bind(button)):
			button.pressed.connect(_on_nav_button_pressed.bind(button))


func _setup_nav_pages() -> void:
	if nav_inv != null:
		nav_inv.visible = true
	if nav_map != null:
		nav_map.visible = false
	if nav_craft != null:
		nav_craft.visible = false


func _on_nav_button_pressed(active_button: Control) -> void:
	_set_active_nav_button(active_button)


func _set_active_nav_button(active_button: Control) -> void:
	var nav_buttons: Array[Control] = [inv_btn, map_btn, craft_btn]

	for button in nav_buttons:
		if button == null:
			continue
		button.z_index = 0

	if active_button != null:
		active_button.z_index = 1

	if nav_inv != null:
		nav_inv.visible = active_button == inv_btn
	if nav_map != null:
		nav_map.visible = active_button == map_btn
	if nav_craft != null:
		nav_craft.visible = active_button == craft_btn

	set_loot_context_active(loot_context_active, active_loot_context)


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
	_refresh_craft_ui()


func _rebuild_nearby_slots() -> void:
	var nearby_items: Array = NearbyItemsManager.get_items()
	var visible_slot_index: int = 0

	for i in range(nearby_items.size()):
		var world_item: Node = nearby_items[i]

		if not is_instance_valid(world_item):
			continue

		if world_item.item_data == null:
			continue

		var slot: InventorySlot = _get_or_create_nearby_slot(visible_slot_index)
		slot.visible = true
		slot.set_nearby_item(world_item.item_data, world_item, i)
		visible_slot_index += 1

	for i in range(visible_slot_index, nearby_slots.size()):
		var slot: InventorySlot = nearby_slots[i]
		if not is_instance_valid(slot):
			continue
		slot.clear_slot()
		slot.visible = false


func _get_or_create_nearby_slot(slot_index: int) -> InventorySlot:
	if slot_index < nearby_slots.size():
		var existing_slot: InventorySlot = nearby_slots[slot_index]
		if is_instance_valid(existing_slot):
			return existing_slot

	var slot: InventorySlot = SLOT_SCENE.instantiate()
	slot.name = "NearbySlot_%d" % slot_index

	_setup_nearby_slot(slot)
	_connect_slot(slot)

	inventory_grid.add_child(slot)
	if slot_index < nearby_slots.size():
		nearby_slots[slot_index] = slot
	else:
		nearby_slots.append(slot)
	return slot


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


func _setup_storage_panel(panel: Control, grid: GridContainer, columns: int = 2) -> void:
	grid.columns = max(columns, 1)
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
	slot.icon_size = Vector2(64, 64)
	slot.icon_rotation_degrees = 0.0
	slot.icon_h_align = InventorySlot.IconHAlign.CENTER
	slot.icon_v_align = InventorySlot.IconVAlign.CENTER
	slot.show_name = false
	slot.show_endurance = false
	slot.stretch_icon_to_slot = false
	slot.icon_padding = 0.0


func _setup_craft_recipes() -> void:
	craft_recipes = [
		{"category": CRAFT_CATEGORY_MEDICAL, "ingredients": [{"item": WOOD_ITEM, "count": 1}, {"item": BANDAGE_ITEM, "count": 1}], "result": {"item": IMPROVISED_SPLINT_ITEM, "count": 1}},
		{"category": CRAFT_CATEGORY_MEDICAL, "ingredients": [{"item": WOOD_ITEM, "count": 2}, {"item": STONE_ITEM, "count": 1}, {"item": BANDAGE_ITEM, "count": 1}], "result": {"item": MEDICAL_SPLINT_ITEM, "count": 1}},
		{"category": CRAFT_CATEGORY_MEDICAL, "ingredients": [{"item": BANDAGE_ITEM, "count": 1}, {"item": HEMOSTAT_ITEM, "count": 1}], "result": {"item": HEALTH_BOX_ITEM, "count": 1}},
		{"category": CRAFT_CATEGORY_MEDICAL, "ingredients": [{"item": SALINE_ITEM, "count": 1}, {"item": BANDAGE_ITEM, "count": 1}], "result": {"item": BLOOD_BAG_ITEM, "count": 1}},
		{"category": CRAFT_CATEGORY_FOOD, "ingredients": [{"item": APPLE_ITEM, "count": 1}, {"item": MALINA_ITEM, "count": 1}], "result": {"item": RESTORER_ITEM, "count": 1}},
		{"category": CRAFT_CATEGORY_FOOD, "ingredients": [{"item": TOMATE_ITEM, "count": 1}, {"item": PEPPER_ITEM, "count": 1}], "result": {"item": ANTIDOTE_ITEM, "count": 1}},
		{"category": CRAFT_CATEGORY_TOOLS, "ingredients": [{"item": WOOD_ITEM, "count": 2}, {"item": STONE_ITEM, "count": 2}], "result": {"item": AXE_ITEM, "count": 1}},
		{"category": CRAFT_CATEGORY_TOOLS, "ingredients": [{"item": AXE_ITEM, "count": 1}, {"item": WOOD_ITEM, "count": 1}], "result": {"item": CLEAVER_ITEM, "count": 1}},
		{"category": CRAFT_CATEGORY_MEDICAL, "ingredients": [{"item": POTASSIUM_IODIDE_ITEM, "count": 1}, {"item": SALINE_ITEM, "count": 1}], "result": {"item": RESTORER_ITEM, "count": 1}},
		{"category": CRAFT_CATEGORY_TOOLS, "ingredients": [{"item": WOOD_ITEM, "count": 1}, {"item": MATCHES_ITEM, "count": 1}], "result": {"item": GAS_BURNER_ITEM, "count": 1}},
		{"category": CRAFT_CATEGORY_TOOLS, "ingredients": [{"item": GAS_CYLINDER_ITEM, "count": 1}, {"item": GAS_BURNER_ITEM, "count": 1}], "result": {"item": LIGHTER_ITEM, "count": 1}},
		{"category": CRAFT_CATEGORY_TOOLS, "ingredients": [{"item": BURLAP_FABRIC_ITEM, "count": 1}, {"item": GLUE_ITEM, "count": 1}], "result": {"item": ROPE_ITEM, "count": 1}},
		{"category": CRAFT_CATEGORY_TOOLS, "ingredients": [{"item": BURLAP_FABRIC_ITEM, "count": 1}, {"item": ROPE_ITEM, "count": 1}], "result": {"item": SEWING_KIT_ITEM, "count": 1}},
		{"category": CRAFT_CATEGORY_TOOLS, "ingredients": [{"item": BATTERIES_ITEM, "count": 1}, {"item": ELECTRICAL_TAPE_ITEM, "count": 1}], "result": {"item": GEIGER_COUNTER_ITEM, "count": 1}},
		{"category": CRAFT_CATEGORY_TOOLS, "ingredients": [{"item": GLUE_ITEM, "count": 1}, {"item": BURLAP_FABRIC_ITEM, "count": 1}, {"item": ELECTRICAL_TAPE_ITEM, "count": 1}], "result": {"item": WEAPON_CLEANING_KIT_ITEM, "count": 1}},
		{"category": CRAFT_CATEGORY_TOOLS, "ingredients": [{"item": CIGARETTES_PACK_ITEM, "count": 1}, {"item": MATCHES_ITEM, "count": 1}], "result": {"item": LIGHTER_ITEM, "count": 1}}
	]


func _setup_craft_categories() -> void:
	if craft_category_panel == null:
		return

	craft_category_buttons.clear()
	_register_craft_category_button("EverythingCategory", CRAFT_CATEGORY_ALL)
	_register_craft_category_button("BuildCategory", CRAFT_CATEGORY_BUILD)
	_register_craft_category_button("WeaponCategory", CRAFT_CATEGORY_TOOLS)
	_register_craft_category_button("MedicineCategory", CRAFT_CATEGORY_MEDICAL)

	_refresh_craft_category_buttons()


func _register_craft_category_button(button_name: StringName, category_id: StringName) -> void:
	var button: BaseButton = craft_category_panel.get_node_or_null(NodePath(String(button_name))) as BaseButton
	if button == null:
		push_warning("InventoryRoot: craft category button '%s' was not found" % String(button_name))
		return

	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	if not button.pressed.is_connected(_set_active_craft_category.bind(category_id)):
		button.pressed.connect(_set_active_craft_category.bind(category_id))
	craft_category_buttons[category_id] = button


func _set_active_craft_category(category_id: StringName) -> void:
	active_craft_category = category_id
	if selected_craft_recipe_index >= 0 and not _does_recipe_match_active_category(craft_recipes[selected_craft_recipe_index]):
		selected_craft_recipe_index = -1
		_clear_craft_detail_panel()
	_setup_craft_rows()
	_refresh_craft_category_buttons()
	_refresh_craft_ui()


func _refresh_craft_category_buttons() -> void:
	for category_id in craft_category_buttons.keys():
		var button: BaseButton = craft_category_buttons[category_id] as BaseButton
		if button == null or not is_instance_valid(button):
			continue
		button.button_pressed = category_id == active_craft_category


func _does_recipe_match_active_category(recipe: Dictionary) -> bool:
	if active_craft_category == CRAFT_CATEGORY_ALL:
		return true
	return recipe.get("category", CRAFT_CATEGORY_ALL) == active_craft_category


func _setup_craft_rows() -> void:
	var two_craft_row: Node = get_node_or_null("InventoryContent/NavCraft/TwoCraft")
	if two_craft_row is CanvasItem:
		(two_craft_row as CanvasItem).visible = false
	var three_craft_row: Node = get_node_or_null("InventoryContent/NavCraft/ThreeCraft")
	if three_craft_row is CanvasItem:
		(three_craft_row as CanvasItem).visible = false

	_ensure_craft_scroll()
	if craft_list != null:
		for child in craft_list.get_children():
			child.queue_free()
	craft_row_buttons.clear()
	craft_row_controls.clear()
	craft_row_recipe_indices.clear()

	for i in range(craft_recipes.size()):
		if not _does_recipe_match_active_category(craft_recipes[i]):
			continue
		_create_craft_recipe_row(craft_recipes[i], i)

	call_deferred("_update_craft_scroll_texture")


func _setup_craft_detail_panel() -> void:
	if craft_right_panel_center == null:
		return

	for child in craft_right_panel_center.get_children():
		child.queue_free()

	var detail_layout := VBoxContainer.new()
	detail_layout.name = "CraftDetailLayout"
	detail_layout.custom_minimum_size = Vector2(260, 440)
	detail_layout.add_theme_constant_override("separation", 14)
	craft_right_panel_center.add_child(detail_layout)

	craft_detail_icon = TextureRect.new()
	craft_detail_icon.name = "CraftDetailIcon"
	craft_detail_icon.custom_minimum_size = Vector2(128, 128)
	craft_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	craft_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	detail_layout.add_child(craft_detail_icon)

	craft_detail_title_label = Label.new()
	craft_detail_title_label.name = "CraftDetailTitle"
	craft_detail_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	craft_detail_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_layout.add_child(craft_detail_title_label)

	craft_detail_description_label = Label.new()
	craft_detail_description_label.name = "CraftDetailDescription"
	craft_detail_description_label.custom_minimum_size = Vector2(240, 160)
	craft_detail_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_layout.add_child(craft_detail_description_label)

	craft_detail_button = Button.new()
	craft_detail_button.name = "CraftDetailButton"
	craft_detail_button.text = "Скрафтить"
	craft_detail_button.custom_minimum_size = Vector2(160, 40)
	craft_detail_button.pressed.connect(_craft_selected_recipe)
	detail_layout.add_child(craft_detail_button)

	_clear_craft_detail_panel()


func _ensure_craft_scroll() -> void:
	if craft_scroll != null and is_instance_valid(craft_scroll):
		return

	craft_scroll = ScrollContainer.new()
	craft_scroll.name = "CraftRecipeScroll"
	craft_scroll.position = craft_recipe_list_position
	craft_scroll.size = craft_recipe_list_size
	craft_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	craft_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	craft_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	nav_craft.add_child(craft_scroll)
	craft_scroll.clip_contents = true
	craft_scroll.get_v_scroll_bar().modulate = Color(1, 1, 1, 0)
	craft_scroll.get_v_scroll_bar().mouse_filter = Control.MOUSE_FILTER_IGNORE
	craft_scroll.get_v_scroll_bar().value_changed.connect(_on_craft_scroll_changed)

	craft_list = VBoxContainer.new()
	craft_list.name = "CraftRecipeList"
	craft_list.add_theme_constant_override("separation", 6)
	craft_scroll.add_child(craft_list)

	if craft_scroll_texture != null:
		craft_scroll_texture_start_y = craft_scroll_texture.position.y
		craft_scroll_texture_travel = craft_scroll_texture_travel_distance
		craft_scroll_texture.z_index = 5
		craft_scroll_texture.mouse_filter = Control.MOUSE_FILTER_STOP
		nav_craft.move_child(craft_scroll_texture, nav_craft.get_child_count() - 1)
		craft_scroll_texture_hit_rect = _get_craft_scroll_texture_hit_rect()
		if craft_scroll_texture.has_signal("gui_input") and not craft_scroll_texture.gui_input.is_connected(_on_craft_scroll_texture_gui_input):
			craft_scroll_texture.gui_input.connect(_on_craft_scroll_texture_gui_input)


func _create_craft_recipe_row(recipe: Dictionary, recipe_index: int) -> void:
	if craft_list == null:
		return

	var ingredients: Array = recipe.get("ingredients", [])
	var row_texture: Texture2D = THREE_CRAFT_TEXTURE if ingredients.size() >= 3 else TWO_CRAFT_TEXTURE
	var row_outline_texture: Texture2D = THREE_CRAFT_OUTLINE_TEXTURE if ingredients.size() >= 3 else TWO_CRAFT_OUTLINE_TEXTURE
	if row_texture == null:
		return

	var row_size: Vector2 = row_texture.get_size() * 2.0
	var row := Control.new()
	row.name = "CraftRecipeRow_%d" % recipe_index
	row.custom_minimum_size = row_size
	row.size = row_size
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	craft_list.add_child(row)
	craft_row_controls.append(row)
	craft_row_recipe_indices.append(recipe_index)

	var background := TextureRect.new()
	background.texture = row_texture
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.size = row_size
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(background)

	var slot_positions: Array[Vector2] = _get_craft_slot_positions(ingredients.size())
	for i in range(min(ingredients.size(), slot_positions.size())):
		var ingredient: Dictionary = ingredients[i]
		_add_craft_preview_slot(row, slot_positions[i], ingredient.get("item", null), int(ingredient.get("count", 1)))

	var result: Dictionary = recipe.get("result", {})
	_add_craft_preview_slot(row, Vector2(223, 9), result.get("item", null), int(result.get("count", 1)))

	var button := Button.new()
	button.name = "CraftRecipeButton_%d" % recipe_index
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.text = ""
	button.tooltip_text = "Создать"
	button.position = Vector2(max(row_size.x - CRAFT_BUTTON_WIDTH, 0.0), 0.0)
	button.size = Vector2(CRAFT_BUTTON_WIDTH, row_size.y)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(_select_craft_recipe.bind(recipe_index))
	button.mouse_entered.connect(_set_craft_row_outline.bind(background, row_outline_texture))
	button.mouse_exited.connect(_restore_craft_row_texture.bind(background, row_texture, recipe_index))
	button.gui_input.connect(_on_craft_recipe_button_gui_input.bind(background, row_outline_texture, row_texture, recipe_index))
	row.add_child(button)
	craft_row_buttons.append(button)


func _set_craft_row_outline(background: TextureRect, texture: Texture2D) -> void:
	if background == null or not is_instance_valid(background):
		return
	if texture == null:
		return
	background.texture = texture


func _restore_craft_row_texture(background: TextureRect, texture: Texture2D, recipe_index: int) -> void:
	if recipe_index == selected_craft_recipe_index:
		return
	_set_craft_row_outline(background, texture)


func _on_craft_recipe_button_gui_input(event: InputEvent, background: TextureRect, outline_texture: Texture2D, normal_texture: Texture2D, recipe_index: int) -> void:
	if event is InputEventMouseMotion:
		_set_craft_row_outline(background, outline_texture)
		return
	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_button.pressed:
			_set_craft_row_outline(background, outline_texture)
		elif recipe_index != selected_craft_recipe_index:
			_set_craft_row_outline(background, normal_texture)


func _select_craft_recipe(recipe_index: int) -> void:
	if recipe_index < 0 or recipe_index >= craft_recipes.size():
		return

	selected_craft_recipe_index = recipe_index
	_refresh_craft_row_textures()
	_refresh_craft_detail_panel()
	_refresh_craft_ui()


func _craft_selected_recipe() -> void:
	if selected_craft_recipe_index < 0 or selected_craft_recipe_index >= craft_recipes.size():
		return
	_on_craft_recipe_pressed(selected_craft_recipe_index)
	_refresh_craft_detail_panel()


func _clear_craft_detail_panel() -> void:
	if craft_detail_icon != null:
		craft_detail_icon.texture = null
	if craft_detail_title_label != null:
		craft_detail_title_label.text = "Выберите рецепт"
	if craft_detail_description_label != null:
		craft_detail_description_label.text = ""
	if craft_detail_button != null:
		craft_detail_button.disabled = true


func _refresh_craft_detail_panel() -> void:
	if selected_craft_recipe_index < 0 or selected_craft_recipe_index >= craft_recipes.size():
		_clear_craft_detail_panel()
		return

	var recipe: Dictionary = craft_recipes[selected_craft_recipe_index]
	var result: Dictionary = recipe.get("result", {})
	var result_item: ItemData = result.get("item", null)
	var result_count: int = int(result.get("count", 1))
	if result_item == null:
		_clear_craft_detail_panel()
		return

	if craft_detail_icon != null:
		craft_detail_icon.texture = result_item.inventory_icon
	if craft_detail_title_label != null:
		craft_detail_title_label.text = "%s x%d" % [result_item.item_name, max(result_count, 1)]
	if craft_detail_description_label != null:
		craft_detail_description_label.text = _get_craft_recipe_description(recipe)
	if craft_detail_button != null:
		craft_detail_button.disabled = not _can_craft_recipe(recipe)


func _get_craft_recipe_description(recipe: Dictionary) -> String:
	var lines: Array[String] = []
	var result: Dictionary = recipe.get("result", {})
	var result_item: ItemData = result.get("item", null)
	if result_item != null and not result_item.description.strip_edges().is_empty():
		lines.append(result_item.description.strip_edges())

	lines.append("Требуется:")
	for ingredient in recipe.get("ingredients", []):
		var item: ItemData = ingredient.get("item", null)
		if item == null:
			continue
		lines.append("%s x%d" % [item.item_name, int(ingredient.get("count", 1))])

	return "\n".join(lines)


func _refresh_craft_row_textures() -> void:
	for i in range(craft_row_controls.size()):
		var row: Control = craft_row_controls[i]
		if row == null or not is_instance_valid(row):
			continue

		var background: TextureRect = null
		for child in row.get_children():
			if child is TextureRect:
				background = child as TextureRect
				break
		if background == null:
			continue

		var recipe_index: int = craft_row_recipe_indices[i] if i < craft_row_recipe_indices.size() else -1
		var recipe: Dictionary = craft_recipes[recipe_index] if recipe_index >= 0 and recipe_index < craft_recipes.size() else {}
		var ingredients: Array = recipe.get("ingredients", [])
		if recipe_index == selected_craft_recipe_index:
			background.texture = THREE_CRAFT_OUTLINE_TEXTURE if ingredients.size() >= 3 else TWO_CRAFT_OUTLINE_TEXTURE
		else:
			background.texture = THREE_CRAFT_TEXTURE if ingredients.size() >= 3 else TWO_CRAFT_TEXTURE


func _on_craft_scroll_changed(_value: float) -> void:
	_update_craft_scroll_texture()


func _on_craft_scroll_texture_gui_input(event: InputEvent) -> void:
	if craft_scroll == null:
		return

	var scroll_bar: VScrollBar = craft_scroll.get_v_scroll_bar()
	var max_scroll: float = max(scroll_bar.max_value - scroll_bar.page, 0.0)
	if max_scroll <= 0.0:
		return

	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return

		if mouse_button.pressed:
			_start_craft_scroll_texture_drag(mouse_button.global_position.y)
		else:
			craft_scroll_texture_dragging = false
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and craft_scroll_texture_dragging:
		var mouse_motion: InputEventMouseMotion = event as InputEventMouseMotion
		_drag_craft_scroll_texture(mouse_motion.global_position.y)
		get_viewport().set_input_as_handled()
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			_start_craft_scroll_texture_drag(touch.position.y)
		else:
			craft_scroll_texture_dragging = false
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenDrag and craft_scroll_texture_dragging:
		_drag_craft_scroll_texture((event as InputEventScreenDrag).position.y)
		get_viewport().set_input_as_handled()


func _start_craft_scroll_texture_drag(mouse_global_y: float) -> void:
	if craft_scroll == null:
		return

	craft_scroll_texture_dragging = true
	craft_scroll_texture_drag_start_mouse_y = mouse_global_y
	craft_scroll_texture_drag_start_value = craft_scroll.get_v_scroll_bar().value


func _is_mouse_over_craft_scroll_texture(mouse_global_position: Vector2) -> bool:
	if craft_scroll_texture == null or not is_instance_valid(craft_scroll_texture):
		return false
	if nav_craft == null or not nav_craft.visible:
		return false
	if not is_inventory_open:
		return false

	var rect: Rect2 = _get_craft_scroll_texture_hit_rect()
	return craft_scroll_texture.visible and rect.has_point(mouse_global_position)


func _get_craft_scroll_texture_hit_rect() -> Rect2:
	if craft_scroll_texture == null or not is_instance_valid(craft_scroll_texture):
		return Rect2()

	if craft_scroll_texture is TextureButton:
		var texture_button: TextureButton = craft_scroll_texture as TextureButton
		var texture: Texture2D = texture_button.texture_normal
		if texture != null:
			return Rect2(texture_button.global_position, texture.get_size() * texture_button.scale.abs())

	if craft_scroll_texture is TextureRect:
		var texture_rect: TextureRect = craft_scroll_texture as TextureRect
		if texture_rect.texture != null:
			return Rect2(texture_rect.global_position, texture_rect.texture.get_size() * texture_rect.scale.abs())

	var rect: Rect2 = craft_scroll_texture.get_global_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		rect = Rect2(craft_scroll_texture.global_position, Vector2(26, 58) * craft_scroll_texture.scale.abs())
	return rect


func _drag_craft_scroll_texture(mouse_global_y: float) -> void:
	if craft_scroll == null:
		return

	var scroll_bar: VScrollBar = craft_scroll.get_v_scroll_bar()
	var max_scroll: float = max(scroll_bar.max_value - scroll_bar.page, 0.0)
	if max_scroll <= 0.0:
		return

	var drag_delta: float = mouse_global_y - craft_scroll_texture_drag_start_mouse_y
	var scroll_delta: float = drag_delta / max(craft_scroll_texture_travel, 1.0) * max_scroll
	scroll_bar.value = clamp(craft_scroll_texture_drag_start_value + scroll_delta, 0.0, max_scroll)


func _update_craft_scroll_texture() -> void:
	if craft_scroll_texture == null or craft_scroll == null:
		return

	var scroll_bar: VScrollBar = craft_scroll.get_v_scroll_bar()
	var max_scroll: float = max(scroll_bar.max_value - scroll_bar.page, 0.0)
	var scroll_ratio: float = 0.0 if max_scroll <= 0.0 else clamp(scroll_bar.value / max_scroll, 0.0, 1.0)
	craft_scroll_texture.visible = true
	craft_scroll_texture.position.y = craft_scroll_texture_start_y + craft_scroll_texture_travel * scroll_ratio
	craft_scroll_texture_hit_rect = _get_craft_scroll_texture_hit_rect()


func _get_craft_slot_positions(ingredient_count: int) -> Array[Vector2]:
	if ingredient_count >= 3:
		return [Vector2(8, 9), Vector2(70, 9), Vector2(132, 9)]
	return [Vector2(38, 9), Vector2(100, 9)]


func _add_craft_preview_slot(parent: Control, position: Vector2, item: ItemData, count: int) -> void:
	var slot: InventorySlot = SLOT_SCENE.instantiate()
	slot.slot_mode = InventorySlot.SlotMode.CONTAINER
	slot.position = position
	slot.custom_minimum_size = Vector2(30, 30)
	slot.size = Vector2(60, 60)
	slot.icon_size = Vector2(42, 42)
	slot.icon_rotation_degrees = 0.0
	slot.show_name = false
	slot.show_endurance = false
	slot.stretch_icon_to_slot = true
	slot.icon_padding = 1.0
	slot.show_background_in_container = false
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(slot)

	if item == null:
		slot.clear_slot()
		return

	var preview_item: ItemData = item.create_instance(count, item.endurance) if item.has_method("create_instance") else item.duplicate(true)
	preview_item.stack_count = max(count, 1)
	preview_item.show_stack_count_in_inventory = count > 1 or item.show_stack_count_in_inventory
	slot.set_container_item(preview_item, -1)


func _on_craft_recipe_pressed(recipe_index: int) -> void:
	if _is_network_client_inventory_mutation_blocked() and not _network_inventory_action_bypass:
		_request_server_inventory_action(
			"craft",
			{"recipe_index": recipe_index, "selected_recipe_index": selected_craft_recipe_index},
			Callable(self, "_on_craft_recipe_server_approved").bind(recipe_index)
		)
		return
	if recipe_index < 0 or recipe_index >= craft_recipes.size():
		return

	var recipe: Dictionary = craft_recipes[recipe_index]
	if not _can_craft_recipe(recipe):
		return

	var result: Dictionary = recipe.get("result", {})
	var result_item: ItemData = result.get("item", null)
	var result_count: int = int(result.get("count", 1))
	if result_item == null:
		return

	var crafted_item: ItemData = result_item.create_instance(result_count, result_item.endurance) if result_item.has_method("create_instance") else result_item.duplicate(true)
	crafted_item.stack_count = max(result_count, 1)
	if not _can_place_crafted_item(crafted_item):
		return

	if not _consume_craft_ingredients(recipe.get("ingredients", [])):
		refresh_ui()
		return

	if not _try_store_crafted_item(crafted_item):
		_spawn_world_item(crafted_item)

	refresh_ui()


func _on_craft_recipe_server_approved(recipe_index: int) -> void:
	_network_inventory_action_bypass = true
	_on_craft_recipe_pressed(recipe_index)
	_network_inventory_action_bypass = false


func _refresh_craft_ui() -> void:
	for i in range(craft_row_recipe_indices.size()):
		var recipe_index: int = craft_row_recipe_indices[i]
		if recipe_index < 0 or recipe_index >= craft_recipes.size():
			continue
		var recipe: Dictionary = craft_recipes[recipe_index]
		var can_craft: bool = _can_craft_recipe(recipe)
		var is_selected: bool = recipe_index == selected_craft_recipe_index
		if i < craft_row_controls.size() and is_instance_valid(craft_row_controls[i]):
			craft_row_controls[i].modulate = Color(1, 1, 1, 1) if can_craft or is_selected else Color(0.55, 0.55, 0.55, 0.85)
		if i < craft_row_buttons.size() and is_instance_valid(craft_row_buttons[i]):
			craft_row_buttons[i].disabled = false
			craft_row_buttons[i].tooltip_text = "Показать рецепт" if can_craft else "Показать рецепт: не хватает ресурсов"
	if selected_craft_recipe_index >= 0:
		_refresh_craft_detail_panel()
	_update_craft_scroll_texture()


func _can_craft_recipe(recipe: Dictionary) -> bool:
	var required_counts: Dictionary = _get_required_crafting_counts(recipe.get("ingredients", []))
	if required_counts.is_empty():
		return false

	for item_key in required_counts.keys():
		var requirement: Dictionary = required_counts[item_key]
		var item: ItemData = requirement.get("item", null)
		if item == null:
			return false
		if _get_available_crafting_count(item) < int(requirement.get("count", 0)):
			return false
	return true


func _get_required_crafting_counts(ingredients: Array) -> Dictionary:
	var required_counts: Dictionary = {}
	for ingredient in ingredients:
		var item: ItemData = ingredient.get("item", null)
		var required_count: int = int(ingredient.get("count", 1))
		if item == null or required_count <= 0:
			return {}

		var item_key: String = _get_crafting_item_key(item)
		if item_key.is_empty():
			return {}

		var current: Dictionary = {}
		if required_counts.has(item_key):
			current = required_counts[item_key]
		else:
			current = {"item": item, "count": 0}
		current["count"] = int(current.get("count", 0)) + required_count
		required_counts[item_key] = current
	return required_counts


func _get_available_crafting_count(item: ItemData) -> int:
	if item == null:
		return 0

	var total: int = 0
	for slot_type in _get_crafting_equipped_slot_types():
		var equipped_item: ItemData = InventoryManager.get_equipped(slot_type)
		if _is_same_crafting_item(equipped_item, item):
			total += max(equipped_item.stack_count, 1)

	for provider in _get_crafting_storage_providers():
		for stored_item in provider.runtime_storage_items:
			if _is_same_crafting_item(stored_item, item):
				total += max(stored_item.stack_count, 1)

	for world_item in NearbyItemsManager.get_items():
		if not is_instance_valid(world_item):
			continue
		var nearby_item: ItemData = world_item.get("item_data") as ItemData
		if _is_same_crafting_item(nearby_item, item):
			total += max(nearby_item.stack_count, 1)
	return total


func _consume_craft_ingredients(ingredients: Array) -> bool:
	var required_counts: Dictionary = _get_required_crafting_counts(ingredients)
	if required_counts.is_empty():
		return false

	for item_key in required_counts.keys():
		var requirement: Dictionary = required_counts[item_key]
		var consumed_count: int = _consume_crafting_item(requirement.get("item", null), int(requirement.get("count", 0)))
		if consumed_count < int(requirement.get("count", 0)):
			push_warning("Crafting failed to consume all ingredients for %s" % item_key)
			return false
	return true


func _consume_crafting_item(item: ItemData, amount: int) -> int:
	if item == null or amount <= 0:
		return 0

	var remaining: int = amount
	for slot_type in _get_crafting_equipped_slot_types():
		if remaining <= 0:
			return amount - remaining

		var equipped_item: ItemData = InventoryManager.get_equipped(slot_type)
		if not _is_same_crafting_item(equipped_item, item):
			continue

		var equipped_available: int = max(equipped_item.stack_count, 1)
		var equipped_taken: int = min(equipped_available, remaining)
		equipped_item.stack_count -= equipped_taken
		remaining -= equipped_taken
		if equipped_item.stack_count <= 0:
			InventoryManager.set_equipped(slot_type, null)

	for provider in _get_crafting_storage_providers():
		for i in range(provider.runtime_storage_items.size()):
			if remaining <= 0:
				return amount - remaining

			var stored_item: ItemData = provider.runtime_storage_items[i]
			if not _is_same_crafting_item(stored_item, item):
				continue

			var available: int = max(stored_item.stack_count, 1)
			var taken: int = min(available, remaining)
			stored_item.stack_count -= taken
			remaining -= taken
			if stored_item.stack_count <= 0:
				provider.runtime_storage_items[i] = null

	for world_item in NearbyItemsManager.get_items():
		if remaining <= 0:
			return amount - remaining
		if not is_instance_valid(world_item):
			continue

		var nearby_item: ItemData = world_item.get("item_data") as ItemData
		if not _is_same_crafting_item(nearby_item, item):
			continue

		var nearby_available: int = max(nearby_item.stack_count, 1)
		var nearby_taken: int = min(nearby_available, remaining)
		nearby_item.stack_count -= nearby_taken
		remaining -= nearby_taken
		if nearby_item.stack_count <= 0:
			if world_item.has_method("remove_from_world"):
				world_item.remove_from_world()
			else:
				world_item.queue_free()

	return amount - remaining


func _get_crafting_equipped_slot_types() -> Array[int]:
	return [
		ItemData.ItemType.AR_Weapon,
		ItemData.ItemType.Pistols,
		ItemData.ItemType.MeleeWeapon,
		ItemData.ItemType.Lefthand
	]


func _get_crafting_storage_providers() -> Array[ItemData]:
	var providers: Array[ItemData] = []
	for slot_type in [ItemData.ItemType.Jacket, ItemData.ItemType.HeavyArmour, ItemData.ItemType.Trousers, ItemData.ItemType.Bag]:
		var provider: ItemData = InventoryManager.get_equipped(slot_type)
		if provider == null or not provider.can_store_items or provider.extra_storage_slots <= 0:
			continue
		_ensure_storage_provider_size(provider)
		providers.append(provider)
	return providers


func _is_same_crafting_item(left_item: ItemData, right_item: ItemData) -> bool:
	if left_item == null or right_item == null:
		return false
	var left_key: String = _get_crafting_item_key(left_item)
	var right_key: String = _get_crafting_item_key(right_item)
	if left_key.is_empty() or right_key.is_empty():
		return false
	return left_key == right_key


func _get_crafting_item_key(item: ItemData) -> String:
	if item == null:
		return ""

	var definition: ItemData = item.get_definition() if item.has_method("get_definition") else item
	if definition != null and not definition.resource_path.is_empty():
		return definition.resource_path
	if not item.resource_path.is_empty():
		return item.resource_path
	return item.item_name.strip_edges().to_lower()


func _on_slot_drop_requested(target_slot: InventorySlot, data: Dictionary) -> void:
	if _is_network_client_inventory_mutation_blocked() and not _network_inventory_action_bypass:
		_notify_local_pickup_status("Действие инвентаря только через сервер", Color(1.0, 0.55, 0.4, 1.0))
		return
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

			if not _is_storage_binding_valid(source_binding):
				return

			var source_provider: ItemData = source_binding.get("provider", null)
			var source_slot_index: int = int(source_binding.get("slot_index", -1))
			var source_item: ItemData = _get_bound_storage_item(source_binding)
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

	if not _is_storage_binding_valid(target_binding):
		return

	var target_provider: ItemData = target_binding.get("provider", null)
	var target_index: int = int(target_binding.get("slot_index", -1))
	var target_item: ItemData = _get_bound_storage_item(target_binding)

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

			if not _is_storage_binding_valid(source_binding):
				return

			var source_provider: ItemData = source_binding.get("provider", null)
			var source_slot_index: int = int(source_binding.get("slot_index", -1))
			var source_item: ItemData = _get_bound_storage_item(source_binding)
			if source_item == null:
				return

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
	if multiplayer != null and multiplayer.multiplayer_peer != null and NetworkManager != null:
		return _request_network_pickup(world_item)

	return _pickup_world_item(world_item)


func try_store_item_or_drop(item: ItemData) -> bool:
	if item == null:
		return false
	var runtime_item: ItemData = _clone_item_data(item)
	if runtime_item == null:
		return false
	if _try_store_picked_item(runtime_item):
		refresh_ui()
		return true
	_spawn_world_item(runtime_item)
	refresh_ui()
	return false


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
	if _is_network_client_inventory_mutation_blocked() and not _network_inventory_action_bypass:
		_notify_local_pickup_status("Сброс предмета только через сервер", Color(1.0, 0.55, 0.4, 1.0))
		return
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

			var source_item: ItemData = source_slot.item_data
			var equipped_item: ItemData = _extract_equipped_item_for_world_drop(source_item, source_slot.slot_type)
			if equipped_item == null:
				return

			_spawn_world_item(equipped_item)

		InventorySlot.SlotMode.CONTAINER:
			var source_index: int = data.get("container_index", -1)
			var source_binding: Dictionary = _decode_storage_binding(source_index)
			if source_binding.is_empty():
				return

			if not _is_storage_binding_valid(source_binding):
				return

			var source_provider: ItemData = source_binding.get("provider", null)
			var source_slot_index: int = int(source_binding.get("slot_index", -1))
			var stored_item: ItemData = _get_bound_storage_item(source_binding)
			if stored_item == null:
				return

			source_provider.runtime_storage_items[source_slot_index] = null
			_spawn_world_item(stored_item)


func _extract_equipped_item_for_world_drop(source_item: ItemData, preferred_slot_type: int) -> ItemData:
	if source_item == null:
		return null
	var source_runtime_id: String = _get_runtime_item_id(source_item)
	var extracted: ItemData = null

	if preferred_slot_type >= 0:
		var preferred_item: ItemData = InventoryManager.get_equipped(preferred_slot_type)
		if preferred_item != null and _is_same_runtime_item(preferred_item, source_item, source_runtime_id):
			extracted = preferred_item
			InventoryManager.set_equipped(preferred_slot_type, null)

	for slot_type in _get_all_equipment_slot_types():
		var equipped_item: ItemData = InventoryManager.get_equipped(slot_type)
		if equipped_item == null:
			continue
		if not _is_same_runtime_item(equipped_item, source_item, source_runtime_id):
			continue
		if extracted == null:
			extracted = equipped_item
		InventoryManager.set_equipped(slot_type, null)

	return extracted


func _get_all_equipment_slot_types() -> Array[int]:
	return [
		ItemData.ItemType.AR_Weapon,
		ItemData.ItemType.Pistols,
		ItemData.ItemType.MeleeWeapon,
		ItemData.ItemType.Lefthand,
		ItemData.ItemType.T_shirts,
		ItemData.ItemType.Jacket,
		ItemData.ItemType.HeavyArmour,
		ItemData.ItemType.Trousers,
		ItemData.ItemType.Bag,
		ItemData.ItemType.Cap
	]


func _is_same_runtime_item(candidate: ItemData, reference: ItemData, reference_runtime_id: String) -> bool:
	if candidate == null or reference == null:
		return false
	if candidate == reference:
		return true
	if reference_runtime_id.is_empty():
		return false
	return _get_runtime_item_id(candidate) == reference_runtime_id


func _get_runtime_item_id(item: ItemData) -> String:
	if item == null:
		return ""
	if item.has_method("get_runtime_id"):
		return String(item.call("get_runtime_id"))
	return ""


func _spawn_world_item(item: ItemData) -> bool:
	if pickup_item_scene == null:
		push_warning("pickup_item_scene не назначена в inventory_root")
		return false

	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		push_warning("Игрок не найден в группе 'player'")
		return false

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

	return true


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

	if _store_world_item_data(item, world_item):
		if world_item.has_method("remove_from_world"):
			world_item.remove_from_world()
		else:
			world_item.queue_free()
		refresh_ui()
		return true

	return false


func _request_network_pickup(world_item: Node) -> bool:
	if world_item == null or not is_instance_valid(world_item):
		return false
	if NetworkManager == null:
		return false
	if not world_item.has_method("rpc_request_pickup_authorization"):
		return false
	var world_item_id: int = world_item.get_instance_id()
	if _network_pickup_pending.has(world_item_id):
		return false
	var item: ItemData = world_item.get("item_data") as ItemData
	if item == null:
		return false
	var runtime_copy: ItemData = _clone_item_data(item)
	if runtime_copy == null:
		return false
	_network_pickup_pending[world_item_id] = true
	_start_network_pickup_timeout(world_item_id)
	if world_item.has_signal("network_pickup_result"):
		var callback: Callable = Callable(self, "_on_network_pickup_result").bind(runtime_copy, world_item_id)
		if not world_item.is_connected("network_pickup_result", callback):
			world_item.connect("network_pickup_result", callback, CONNECT_ONE_SHOT)
	var local_peer_id: int = NetworkManager.get_local_peer_id()
	if NetworkManager.is_server():
		if world_item.has_method("authorize_pickup_locally"):
			world_item.call("authorize_pickup_locally", local_peer_id)
		else:
			world_item.rpc_id(1, "rpc_request_pickup_authorization", local_peer_id)
	else:
		world_item.rpc_id(1, "rpc_request_pickup_authorization", local_peer_id)
	return true


func _on_network_pickup_result(accepted: bool, runtime_item: ItemData, world_item_id: int) -> void:
	_network_pickup_pending.erase(world_item_id)
	if not accepted:
		_notify_local_pickup_status("Подбор отклонен", Color(1.0, 0.55, 0.4, 1.0))
		return
	if runtime_item == null:
		return
	var stored: bool = _store_world_item_data(runtime_item, null)
	if not stored:
		_spawn_world_item(runtime_item)
		_notify_local_pickup_status("Нет места: предмет сброшен рядом", Color(1.0, 0.8, 0.45, 1.0))
		refresh_ui()
		return
	refresh_ui()
	_notify_local_pickup_status("Предмет подобран", Color(0.45, 0.95, 0.65, 1.0))


func _store_world_item_data(item: ItemData, world_item: Node) -> bool:
	if item == null:
		return false

	if item.is_ammo_item:
		_try_apply_picked_ammo_to_weapon_reserve(item)
		if item.stack_count <= 0:
			return true

	var equip_slot_type: int = -1
	if item.auto_place_into_equipment_on_pickup:
		equip_slot_type = _get_auto_equip_slot_type(item)
	if equip_slot_type != -1:
		var equipped_item: ItemData = InventoryManager.get_equipped(equip_slot_type)
		var moved_to_equip_slot: int = _stack_items(equipped_item, item)
		if item.stack_count <= 0:
			return true
		if moved_to_equip_slot > 0:
			if _try_store_item_in_first_free_container(item):
				return true
			if item.stack_count <= 0:
				return true
			return false

		if world_item != null:
			_replace_equipped_item_from_world(equip_slot_type, world_item, item)
		else:
			var old_item: ItemData = InventoryManager.get_equipped(equip_slot_type)
			if old_item != null:
				_spawn_world_item(old_item)
			InventoryManager.set_equipped(equip_slot_type, item)
		return true

	return _try_store_picked_item(item)


func _start_network_pickup_timeout(world_item_id: int) -> void:
	_network_pickup_timeout_impl(world_item_id)


func _network_pickup_timeout_impl(world_item_id: int) -> void:
	await get_tree().create_timer(NETWORK_PICKUP_TIMEOUT_SEC).timeout
	if not _network_pickup_pending.has(world_item_id):
		return
	_network_pickup_pending.erase(world_item_id)
	_notify_local_pickup_status("Таймаут подбора", Color(1.0, 0.55, 0.4, 1.0))


func _notify_local_pickup_status(text: String, color: Color) -> void:
	var player_node: Node = get_tree().get_first_node_in_group("player")
	if player_node == null:
		return
	if player_node.has_method("_enqueue_status_hint"):
		player_node.call("_enqueue_status_hint", text, color)


func _is_network_client_inventory_mutation_blocked() -> bool:
	return multiplayer != null and multiplayer.multiplayer_peer != null and NetworkManager != null and not NetworkManager.is_server()


func _block_network_inventory_action(action_name: String) -> void:
	_notify_local_pickup_status("%s только через сервер" % action_name, Color(1.0, 0.55, 0.4, 1.0))


func _on_consume_food_server_approved() -> void:
	_network_inventory_action_bypass = true
	_consume_selected_food()
	_network_inventory_action_bypass = false


func _on_finish_consume_food_server_approved() -> void:
	_network_inventory_action_bypass = true
	_finish_consume_selected_food()
	_network_inventory_action_bypass = false


func _on_use_medical_server_approved() -> void:
	_network_inventory_action_bypass = true
	_use_selected_medical()
	_network_inventory_action_bypass = false


func _on_finish_use_medical_server_approved() -> void:
	_network_inventory_action_bypass = true
	_finish_use_selected_medical()
	_network_inventory_action_bypass = false


func _on_equip_ammo_server_approved() -> void:
	_network_inventory_action_bypass = true
	_equip_selected_ammo()
	_network_inventory_action_bypass = false


func _request_server_inventory_action(action_name: String, payload: Dictionary, on_approved: Callable) -> void:
	if NetworkManager == null:
		_block_network_inventory_action(action_name)
		return
	var request_id: int = _network_inventory_action_next_request_id
	_network_inventory_action_next_request_id += 1
	_network_inventory_action_pending[request_id] = {
		"action": action_name,
		"callback": on_approved
	}
	_start_network_inventory_action_timeout(request_id, action_name)
	rpc_id(1, "rpc_request_inventory_action", action_name, payload, request_id, NetworkManager.get_local_peer_id())


func _build_slot_payload(slot: InventorySlot) -> Dictionary:
	if slot == null:
		return {}
	return {
		"slot_mode": slot.slot_mode,
		"slot_type": slot.slot_type,
		"container_index": slot.container_index
	}


func _build_pending_medical_payload() -> Dictionary:
	return {
		"slot_mode": pending_medical_mode,
		"slot_type": pending_medical_slot_type,
		"container_index": pending_medical_container_index
	}


func _start_network_inventory_action_timeout(request_id: int, action_name: String) -> void:
	_network_inventory_action_timeout_impl(request_id, action_name)


func _network_inventory_action_timeout_impl(request_id: int, action_name: String) -> void:
	await get_tree().create_timer(NETWORK_INVENTORY_ACTION_TIMEOUT_SEC).timeout
	if not _network_inventory_action_pending.has(request_id):
		return
	_network_inventory_action_pending.erase(request_id)
	_notify_local_pickup_status("%s: таймаут" % action_name, Color(1.0, 0.55, 0.4, 1.0))


@rpc("any_peer", "reliable")
func rpc_request_inventory_action(action_name: String, _payload: Dictionary, request_id: int, requester_peer_id: int) -> void:
	if NetworkManager == null or not NetworkManager.is_server():
		return
	if request_id <= 0:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != requester_peer_id:
		return
	var approved: bool = _is_server_inventory_action_authorized(sender_id, action_name, _payload)
	rpc_id(sender_id, "rpc_inventory_action_result", request_id, action_name, approved)


func _is_server_inventory_action_authorized(sender_id: int, action_name: String, payload: Dictionary) -> bool:
	var action_key: StringName = StringName(action_name)
	if not (action_key in NETWORK_ALLOWED_INVENTORY_ACTIONS):
		return false
	if not _is_server_inventory_action_rate_limited(sender_id, action_key):
		return false
	if action_key == &"craft":
		var recipe_index: int = int(payload.get("recipe_index", -1))
		if recipe_index < 0 or recipe_index >= craft_recipes.size():
			return false
		return true
	return _is_server_inventory_slot_payload_valid(payload)


func _is_server_inventory_action_rate_limited(sender_id: int, action_name: StringName) -> bool:
	var now_ms: int = Time.get_ticks_msec()
	var action_history: Dictionary = _network_server_last_inventory_action_ms_by_peer.get(sender_id, {})
	var last_ms: int = int(action_history.get(action_name, -1))
	var min_interval_ms: int = NETWORK_INVENTORY_ACTION_CRAFT_MIN_INTERVAL_MS if action_name == &"craft" else NETWORK_INVENTORY_ACTION_MIN_INTERVAL_MS
	if last_ms >= 0 and now_ms - last_ms < min_interval_ms:
		return false
	action_history[action_name] = now_ms
	_network_server_last_inventory_action_ms_by_peer[sender_id] = action_history
	return true


func _is_server_inventory_slot_payload_valid(payload: Dictionary) -> bool:
	var has_slot_mode: bool = payload.has("slot_mode")
	var has_slot_type: bool = payload.has("slot_type")
	var has_container_index: bool = payload.has("container_index")
	if not has_slot_mode or not has_slot_type or not has_container_index:
		return false
	var slot_mode: int = int(payload.get("slot_mode", -1))
	var slot_type: int = int(payload.get("slot_type", -1))
	var container_index: int = int(payload.get("container_index", -9999))
	if slot_mode != InventorySlot.SlotMode.EQUIPMENT and slot_mode != InventorySlot.SlotMode.CONTAINER:
		return false
	if slot_mode == InventorySlot.SlotMode.EQUIPMENT:
		return slot_type >= 0
	return container_index >= 0


@rpc("any_peer", "reliable")
func rpc_inventory_action_result(request_id: int, action_name: String, approved: bool) -> void:
	if NetworkManager != null and not NetworkManager.is_server():
		var sender_id: int = multiplayer.get_remote_sender_id()
		if sender_id != 1:
			return
	if not _network_inventory_action_pending.has(request_id):
		return
	var pending: Dictionary = _network_inventory_action_pending[request_id]
	_network_inventory_action_pending.erase(request_id)
	if not approved:
		_notify_local_pickup_status("%s отклонено" % action_name, Color(1.0, 0.55, 0.4, 1.0))
		return
	var callback: Callable = pending.get("callback", Callable())
	if callback.is_valid():
		callback.call()


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
			if _try_store_item_in_first_free_container(item):
				return true
			if item.stack_count <= 0:
				return true
			return false
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


func _can_place_crafted_item(item: ItemData) -> bool:
	if item == null:
		return false
	if _can_store_item_in_first_free_container(item):
		return true
	if _can_place_item_in_empty_equipment(item):
		return true
	return _can_spawn_world_item()


func _try_store_crafted_item(item: ItemData) -> bool:
	if _try_store_item_in_first_free_container(item):
		return true
	return _try_place_item_in_empty_equipment(item)


func _can_spawn_world_item() -> bool:
	return pickup_item_scene != null and get_tree().get_first_node_in_group("player") != null


func _can_place_item_in_empty_equipment(item: ItemData) -> bool:
	if item == null:
		return false

	for slot in equipment_slots:
		if slot == null or not is_instance_valid(slot):
			continue
		if InventoryManager.get_equipped(slot.slot_type) != null:
			continue
		if _can_item_fit_equipment_slot(item, slot):
			return true
	return false


func _try_place_item_in_empty_equipment(item: ItemData) -> bool:
	if item == null:
		return false

	for slot in equipment_slots:
		if slot == null or not is_instance_valid(slot):
			continue
		if InventoryManager.get_equipped(slot.slot_type) != null:
			continue
		if not _can_item_fit_equipment_slot(item, slot):
			continue

		InventoryManager.set_equipped(slot.slot_type, item)
		return true
	return false


func _can_store_item_in_first_free_container(item: ItemData) -> bool:
	if item == null or not _can_item_fit_container_storage(item):
		return false

	var remaining: int = max(item.stack_count, 1)
	for slot_type in [ItemData.ItemType.Jacket, ItemData.ItemType.HeavyArmour, ItemData.ItemType.Trousers, ItemData.ItemType.Bag]:
		var provider: ItemData = InventoryManager.get_equipped(slot_type)
		if provider == null or not provider.can_store_items:
			continue

		_ensure_storage_provider_size(provider)
		for stored_item in provider.runtime_storage_items:
			if _can_stack_more(stored_item, item):
				remaining -= max(stored_item.max_stack_size - stored_item.stack_count, 0)
				if remaining <= 0:
					return true
		for stored_item in provider.runtime_storage_items:
			if stored_item == null:
				return true
	return false


func _try_store_item_in_first_free_container(item: ItemData) -> bool:
	if item == null or not _can_item_fit_container_storage(item):
		return false

	for slot_type in [ItemData.ItemType.Jacket, ItemData.ItemType.HeavyArmour, ItemData.ItemType.Trousers, ItemData.ItemType.Bag]:
		var provider: ItemData = InventoryManager.get_equipped(slot_type)
		if provider == null or not provider.can_store_items:
			continue

		_ensure_storage_provider_size(provider)
		for i in range(provider.runtime_storage_items.size()):
			_stack_items(provider.runtime_storage_items[i], item)
			if item.stack_count <= 0:
				return true
		for i in range(provider.runtime_storage_items.size()):
			if provider.runtime_storage_items[i] == null:
				provider.runtime_storage_items[i] = item
				return true

	return false


func _can_item_fit_container_storage(item: ItemData) -> bool:
	if item == null:
		return false
	if not item.can_be_stored_in_clothing:
		return false
	return item.storage_category in [
		ItemData.StorageCategory.FOOD,
		ItemData.StorageCategory.MEDICAL,
		ItemData.StorageCategory.MISC
	]


func _can_stack_more(target_item: ItemData, source_item: ItemData) -> bool:
	if not _can_stack_items_together(target_item, source_item):
		return false
	if target_item.max_stack_size <= 1:
		return false
	return target_item.stack_count < target_item.max_stack_size


func _get_equipment_slot_by_type(slot_type: int) -> InventorySlot:
	for slot in equipment_slots:
		if slot.slot_type == slot_type:
			return slot
	return null


func _stack_items(target_item: ItemData, source_item: ItemData) -> int:
	if not _can_stack_items_together(target_item, source_item):
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


func _can_stack_items_together(target_item: ItemData, source_item: ItemData) -> bool:
	if target_item == null or source_item == null:
		return false
	if target_item == source_item:
		return false
	if source_item.stack_count <= 0:
		return false
	if target_item.is_ammo_item or source_item.is_ammo_item:
		return target_item.is_ammo_item and source_item.is_ammo_item and not target_item.ammo_type.is_empty() and target_item.ammo_type == source_item.ammo_type

	var target_key: String = _get_stack_item_key(target_item)
	var source_key: String = _get_stack_item_key(source_item)
	if target_key.is_empty() or source_key.is_empty():
		return false
	return target_key == source_key


func _get_stack_item_key(item: ItemData) -> String:
	if item == null:
		return ""
	var definition: ItemData = item.get_definition() if item.has_method("get_definition") else item
	if definition != null and not definition.resource_path.is_empty():
		return definition.resource_path
	if not item.resource_path.is_empty():
		return item.resource_path
	return item.item_name.strip_edges().to_lower()


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
		if slot.slot_type == ItemData.ItemType.Jacket or slot.slot_type == ItemData.ItemType.HeavyArmour:
			slot.stretch_icon_to_slot = false
			slot.icon_size = Vector2(52, 52)
			slot.icon_h_align = InventorySlot.IconHAlign.CENTER
			slot.icon_v_align = InventorySlot.IconVAlign.TOP
			slot.icon_rotation_degrees = 0.0
			slot.icon_padding = 0.0
			slot.icon_offset = Vector2(0, -16) if slot.slot_type == ItemData.ItemType.HeavyArmour else Vector2.ZERO
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


func _is_storage_binding_valid(binding: Dictionary) -> bool:
	var provider: ItemData = binding.get("provider", null)
	var slot_index: int = int(binding.get("slot_index", -1))
	return provider != null and slot_index >= 0 and slot_index < provider.runtime_storage_items.size()


func _get_bound_storage_item(binding: Dictionary) -> ItemData:
	if not _is_storage_binding_valid(binding):
		return null

	var provider: ItemData = binding.get("provider", null)
	var slot_index: int = int(binding.get("slot_index", -1))
	return provider.runtime_storage_items[slot_index]


func _set_bound_storage_item_or_drop_old(binding: Dictionary, new_item: ItemData) -> void:
	var provider: ItemData = binding.get("provider", null)
	var slot_index: int = int(binding.get("slot_index", -1))
	if not _is_storage_binding_valid(binding):
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
	if event is InputEventScreenTouch:
		var touch_event: InputEventScreenTouch = event as InputEventScreenTouch
		var screen_position: Vector2 = _get_screen_position_for_slot_event(slot, touch_event.position)
		if touch_event.pressed:
			_start_mobile_slot_touch(slot, screen_position, touch_event.index)
		elif mobile_touch_slot == slot:
			_finish_mobile_slot_touch(screen_position)
		return
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

	_handle_slot_primary_press(slot)


func _handle_slot_primary_press(slot: InventorySlot) -> void:
	if slot == null or slot.item_data == null:
		_hide_action_buttons()
		return

	if slot.slot_mode == InventorySlot.SlotMode.NEARBY:
		_hide_action_buttons()
		return

	if _try_show_remove_scope_button_for_weapon(slot):
		return

	if _is_farm_tool_item(slot.item_data):
		_show_till_farm_row_button_for_slot(slot)
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
	_hide_till_farm_row_button()
	consume_slot = slot
	consume_button.position = slot.global_position - inventory_content.global_position + Vector2(0.0, slot.size.y + 6.0)
	consume_button.visible = true


func _start_mobile_slot_touch(slot: InventorySlot, screen_position: Vector2, touch_index: int = -1) -> void:
	if slot == null or slot.item_data == null:
		_cancel_mobile_slot_touch()
		_hide_action_buttons()
		return
	mobile_touch_slot = slot
	mobile_touch_start_position = screen_position
	mobile_touch_time_left = mobile_long_press_seconds
	mobile_touch_long_press_triggered = false
	mobile_touch_index = touch_index
	mobile_drag_active = false
	mobile_drag_data.clear()
	get_viewport().set_input_as_handled()


func _finish_mobile_slot_touch(screen_position: Vector2 = Vector2.ZERO) -> void:
	var slot := mobile_touch_slot
	var was_long_press := mobile_touch_long_press_triggered
	var was_dragging := mobile_drag_active
	var drag_data := mobile_drag_data.duplicate()
	_cancel_mobile_slot_touch()
	if slot == null or not is_instance_valid(slot):
		return
	if was_dragging:
		_finish_mobile_slot_drag(screen_position, drag_data)
		get_viewport().set_input_as_handled()
		return
	if was_long_press:
		get_viewport().set_input_as_handled()
		return
	if _quick_use_or_equip_slot(slot):
		get_viewport().set_input_as_handled()
		return
	_handle_slot_primary_press(slot)
	get_viewport().set_input_as_handled()


func _cancel_mobile_slot_touch() -> void:
	mobile_touch_slot = null
	mobile_touch_time_left = 0.0
	mobile_touch_long_press_triggered = false
	mobile_touch_index = -1
	mobile_drag_active = false
	mobile_drag_data.clear()


func _event_matches_mobile_touch(touch_index: int) -> bool:
	return mobile_touch_index == -1 or mobile_touch_index == touch_index


func _start_mobile_slot_drag(screen_position: Vector2) -> void:
	if mobile_touch_slot == null or not is_instance_valid(mobile_touch_slot) or mobile_touch_slot.item_data == null:
		_cancel_mobile_slot_touch()
		return

	mobile_drag_active = true
	mobile_touch_long_press_triggered = true
	mobile_drag_data = _build_drag_data_for_slot(mobile_touch_slot)
	drag_in_progress_data.clear()
	_hide_action_buttons()


func _build_drag_data_for_slot(slot: InventorySlot) -> Dictionary:
	return {
		"source_slot": slot,
		"source_mode": slot.slot_mode,
		"item": slot.item_data,
		"world_item": slot.world_item,
		"nearby_index": slot.nearby_index,
		"container_index": slot.container_index
	}


func _finish_mobile_slot_drag(screen_position: Vector2, drag_data: Dictionary) -> void:
	if drag_data.is_empty():
		return

	var target_slot: InventorySlot = _find_inventory_slot_at_screen_position(screen_position)
	if target_slot != null and target_slot._can_drop_data(Vector2.ZERO, drag_data):
		_on_slot_drop_requested(target_slot, drag_data)
		return

	_drop_dragged_item_to_world(drag_data)
	refresh_ui()


func _find_inventory_slot_at_screen_position(screen_position: Vector2) -> InventorySlot:
	return _find_inventory_slot_at_screen_position_recursive(inventory_content, screen_position)


func _find_inventory_slot_at_screen_position_recursive(node: Node, screen_position: Vector2) -> InventorySlot:
	for i in range(node.get_child_count() - 1, -1, -1):
		var child: Node = node.get_child(i)
		var found_slot: InventorySlot = _find_inventory_slot_at_screen_position_recursive(child, screen_position)
		if found_slot != null:
			return found_slot

	if node is InventorySlot:
		var slot := node as InventorySlot
		if slot.is_visible_in_tree():
			var local_position: Vector2 = slot.get_global_transform().affine_inverse() * screen_position
			if Rect2(Vector2.ZERO, slot.size).has_point(local_position):
				return slot

	return null


func _is_screen_position_inside_inventory_content(screen_position: Vector2) -> bool:
	if inventory_content == null or not inventory_content.is_visible_in_tree():
		return false
	var local_position: Vector2 = inventory_content.get_global_transform().affine_inverse() * screen_position
	return Rect2(Vector2.ZERO, inventory_content.size).has_point(local_position)


func _get_screen_position_for_slot_event(slot: InventorySlot, event_position: Vector2) -> Vector2:
	if slot != null and Rect2(Vector2.ZERO, slot.size).has_point(event_position):
		return slot.get_global_transform() * event_position
	return event_position


func _quick_use_or_equip_slot(slot: InventorySlot) -> bool:
	if slot == null or slot.item_data == null:
		return false
	if slot.slot_mode == InventorySlot.SlotMode.NEARBY:
		if slot.world_item != null and is_instance_valid(slot.world_item):
			return _pickup_world_item(slot.world_item)
		return false

	var item: ItemData = slot.item_data
	if item.storage_category == ItemData.StorageCategory.FOOD:
		consume_slot = slot
		_consume_selected_food()
		return true
	if item.storage_category == ItemData.StorageCategory.MEDICAL:
		use_medical_slot = slot
		_use_selected_medical()
		return true
	if item.is_ammo_item:
		equip_ammo_slot = slot
		_equip_selected_ammo()
		return true
	if item.is_scope_attachment or item.is_weapon_attachment:
		install_scope_slot = slot
		_install_selected_scope()
		return true
	if slot.slot_mode == InventorySlot.SlotMode.CONTAINER and _try_equip_container_slot_to_empty_equipment(slot):
		return true
	return false


func _try_equip_container_slot_to_empty_equipment(slot: InventorySlot) -> bool:
	if slot == null or slot.item_data == null:
		return false
	var binding: Dictionary = _decode_storage_binding(slot.container_index)
	var provider: ItemData = binding.get("provider", null)
	var slot_index: int = int(binding.get("slot_index", -1))
	if provider == null or slot_index < 0 or slot_index >= provider.runtime_storage_items.size():
		return false
	var item: ItemData = provider.runtime_storage_items[slot_index]
	if item == null:
		return false
	if not _try_place_item_in_empty_equipment(item):
		return false
	provider.runtime_storage_items[slot_index] = null
	_hide_action_buttons()
	refresh_ui()
	return true


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
	_hide_till_farm_row_button()
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
	_hide_till_farm_row_button()
	_hide_install_scope_button()
	_hide_remove_scope_button()
	use_medical_slot = slot
	use_medical_button.position = slot.global_position - inventory_content.global_position + Vector2(0.0, slot.size.y + 6.0)
	use_medical_button.visible = true


func _hide_use_medical_button() -> void:
	use_medical_slot = null
	if use_medical_button != null:
		use_medical_button.visible = false


func _ensure_till_farm_row_button() -> void:
	if till_farm_row_button != null:
		return

	till_farm_row_button = Button.new()
	till_farm_row_button.text = "Вспахать"
	till_farm_row_button.visible = false
	till_farm_row_button.custom_minimum_size = Vector2(110, 28)
	till_farm_row_button.pressed.connect(_start_till_farm_row_placement)
	inventory_content.add_child(till_farm_row_button)


func _show_till_farm_row_button_for_slot(slot: InventorySlot) -> void:
	_hide_consume_button()
	_hide_use_medical_button()
	_hide_equip_ammo_button()
	_hide_install_scope_button()
	_hide_remove_scope_button()
	till_farm_row_slot = slot
	till_farm_row_button.position = slot.global_position - inventory_content.global_position + Vector2(0.0, slot.size.y + 6.0)
	till_farm_row_button.visible = true


func _hide_till_farm_row_button() -> void:
	till_farm_row_slot = null
	if till_farm_row_button != null:
		till_farm_row_button.visible = false


func _is_farm_tool_item(item: ItemData) -> bool:
	if item == null:
		return false
	var definition: ItemData = item.get_definition() if item.has_method("get_definition") else item
	if definition == SHOVEL_ITEM:
		return true
	return (
		item.item_type == ItemData.ItemType.MeleeWeapon
		and item.item_name.strip_edges().to_lower() == SHOVEL_ITEM.item_name.strip_edges().to_lower()
	)


func _start_till_farm_row_placement() -> void:
	if till_farm_row_slot == null or till_farm_row_slot.item_data == null or not _is_farm_tool_item(till_farm_row_slot.item_data):
		_hide_action_buttons()
		return

	var farming_controller: Node = get_tree().get_first_node_in_group("farming_placement_controller")
	if farming_controller == null or not farming_controller.has_method("start_farm_row_placement"):
		push_warning("InventoryRoot: farming placement controller was not found.")
		_hide_action_buttons()
		return

	_hide_action_buttons()
	close_inventory()
	farming_controller.call("start_farm_row_placement")


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
	_hide_till_farm_row_button()
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
	_hide_till_farm_row_button()
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
	_hide_till_farm_row_button()
	_hide_equip_ammo_button()
	_hide_install_scope_button()
	_hide_remove_scope_button()


func _consume_selected_food() -> void:
	if _is_network_client_inventory_mutation_blocked() and not _network_inventory_action_bypass:
		_request_server_inventory_action("consume_food", _build_slot_payload(consume_slot), Callable(self, "_on_consume_food_server_approved"))
		return
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
	if _is_network_client_inventory_mutation_blocked() and not _network_inventory_action_bypass:
		_request_server_inventory_action("consume_food_finish", _build_slot_payload(consume_slot), Callable(self, "_on_finish_consume_food_server_approved"))
		return
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
	if _is_network_client_inventory_mutation_blocked() and not _network_inventory_action_bypass:
		_request_server_inventory_action("use_medical", _build_slot_payload(use_medical_slot), Callable(self, "_on_use_medical_server_approved"))
		return
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
	if _is_network_client_inventory_mutation_blocked() and not _network_inventory_action_bypass:
		_request_server_inventory_action("finish_use_medical", _build_pending_medical_payload(), Callable(self, "_on_finish_use_medical_server_approved"))
		return
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
	if _is_network_client_inventory_mutation_blocked() and not _network_inventory_action_bypass:
		_request_server_inventory_action("equip_ammo", _build_slot_payload(equip_ammo_slot), Callable(self, "_on_equip_ammo_server_approved"))
		return
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

	return _resolve_attachment_target_weapon(scope_item) != null


func _install_selected_scope() -> void:
	if install_scope_slot == null or install_scope_slot.item_data == null:
		_hide_action_buttons()
		return

	var selected_slot: InventorySlot = install_scope_slot
	var selected_slot_mode: int = selected_slot.slot_mode
	var selected_slot_type: int = selected_slot.slot_type
	var selected_container_index: int = selected_slot.container_index
	var scope_item: ItemData = selected_slot.item_data
	var target_weapon: ItemData = _resolve_attachment_target_weapon(scope_item)
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


func _resolve_attachment_target_weapon(attachment_item: ItemData) -> ItemData:
	if attachment_item == null:
		return null

	var active_slot: int = InventoryManager.get_active_weapon_slot()
	if active_slot in [ItemData.ItemType.AR_Weapon, ItemData.ItemType.Pistols]:
		var active_weapon: ItemData = InventoryManager.get_equipped(active_slot)
		if active_weapon != null and InventoryManager.can_attach_attachment_to_weapon(attachment_item, active_weapon):
			return active_weapon

	for slot_type in [ItemData.ItemType.AR_Weapon, ItemData.ItemType.Pistols]:
		var weapon_item: ItemData = InventoryManager.get_equipped(slot_type)
		if weapon_item != null and InventoryManager.can_attach_attachment_to_weapon(attachment_item, weapon_item):
			return weapon_item

	return null


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


func _is_screen_position_in_inventory_drag_zone(screen_position: Vector2) -> bool:
	if drag_anchor == null or not is_inventory_open or not drag_anchor.visible:
		return false

	var local_position := drag_anchor.get_global_transform().affine_inverse() * screen_position
	return Rect2(Vector2.ZERO, drag_anchor.size).has_point(local_position)


func _is_screen_position_over_craft_scroll_texture(screen_position: Vector2) -> bool:
	return _is_mouse_over_craft_scroll_texture(screen_position)


func _is_mobile_inventory_layout_enabled() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("mobile")


func _apply_mobile_inventory_layout() -> void:
	if inventory_content == null or not _is_mobile_inventory_layout_enabled():
		return

	var viewport_size: Vector2 = get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	var content_size: Vector2 = inventory_content.size
	if content_size.x <= 0.0 or content_size.y <= 0.0:
		return

	var safe_margin := Vector2(
		clamp(mobile_safe_margin.x, 0.0, viewport_size.x * 0.2),
		clamp(mobile_safe_margin.y, 0.0, viewport_size.y * 0.2)
	)
	var available_size: Vector2 = Vector2(
		max(viewport_size.x - safe_margin.x * 2.0, 1.0),
		max(viewport_size.y - safe_margin.y * 2.0, 1.0)
	)
	var target_scale: float = minf(available_size.x / content_size.x, available_size.y / content_size.y)
	if target_scale >= mobile_min_inventory_scale:
		target_scale = minf(target_scale, 1.0)
	else:
		target_scale = clamp(target_scale, 0.5, 1.0)

	inventory_content.scale = Vector2(target_scale, target_scale)
	var scaled_size: Vector2 = content_size * target_scale
	inventory_content.global_position = safe_margin + (available_size - scaled_size) * 0.5


func _is_drag_blocked_by_control(control: Control) -> bool:
	var current: Node = control
	while current != null:
		if current == inv_btn or current == map_btn or current == craft_btn:
			return true
		if current is BaseButton:
			return true
		if current is InventorySlot:
			return true
		current = current.get_parent()

	return false


func _clamp_inventory_content_to_viewport() -> void:
	if inventory_content == null:
		return
	if _is_mobile_inventory_layout_enabled() and not is_inventory_open:
		return

	var viewport_size: Vector2 = get_viewport_rect().size
	var safe_margin: Vector2 = mobile_safe_margin if _is_mobile_inventory_layout_enabled() else Vector2.ZERO
	var inventory_size: Vector2 = inventory_content.size * inventory_content.scale.abs()
	var max_x: float = max(viewport_size.x - safe_margin.x - inventory_size.x, safe_margin.x)
	var max_y: float = max(viewport_size.y - safe_margin.y - inventory_size.y, safe_margin.y)
	inventory_content.global_position = Vector2(
		clamp(inventory_content.global_position.x, safe_margin.x, max_x),
		clamp(inventory_content.global_position.y, safe_margin.y, max_y)
	)


func _ensure_dev_console() -> void:
	if _dev_console_panel != null:
		return

	_dev_console_panel = PanelContainer.new()
	_dev_console_panel.name = "DevConsole"
	_dev_console_panel.visible = false
	_dev_console_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_dev_console_panel.z_as_relative = false
	_dev_console_panel.z_index = 200
	_dev_console_panel.custom_minimum_size = Vector2(880.0, 300.0)
	_dev_console_panel.position = Vector2(24.0, 24.0)
	add_child(_dev_console_panel)

	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dev_console_panel.add_child(root_vbox)

	var title_label := Label.new()
	title_label.text = "Developer Console (`): help | list_items | find_item | give | give_inv | spawn | give_name | history"
	root_vbox.add_child(title_label)

	_dev_console_output = RichTextLabel.new()
	_dev_console_output.bbcode_enabled = false
	_dev_console_output.scroll_following = true
	_dev_console_output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dev_console_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dev_console_output.custom_minimum_size = Vector2(860.0, 236.0)
	root_vbox.add_child(_dev_console_output)

	_dev_console_input = LineEdit.new()
	_dev_console_input.placeholder_text = "Введите команду. Пример: give nonster 3"
	_dev_console_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dev_console_input.text_submitted.connect(_on_dev_console_command_submitted)
	_dev_console_input.text_changed.connect(_on_dev_console_input_text_changed)
	root_vbox.add_child(_dev_console_input)

	_dev_console_suggestions = ItemList.new()
	_dev_console_suggestions.custom_minimum_size = Vector2(860.0, 110.0)
	_dev_console_suggestions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dev_console_suggestions.select_mode = ItemList.SELECT_SINGLE
	_dev_console_suggestions.visible = false
	_dev_console_suggestions.item_selected.connect(_on_dev_console_suggestion_selected)
	root_vbox.add_child(_dev_console_suggestions)

	_dev_console_log("Console ready. Нажми ` чтобы скрыть.")


func _handle_dev_console_input(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_QUOTELEFT:
			_set_dev_console_open(not _dev_console_open)
			return true
		if _dev_console_open and key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
			_set_dev_console_open(false)
			return true
		if _dev_console_open and key_event.pressed and not key_event.echo:
			if key_event.keycode == KEY_TAB:
				_apply_dev_console_selected_suggestion()
				return true
			if key_event.keycode == KEY_UP:
				if _dev_console_suggestions != null and _dev_console_suggestions.visible:
					_move_dev_console_suggestion_selection(-1)
				else:
					_move_dev_console_history_selection(-1)
				return true
			if key_event.keycode == KEY_DOWN:
				if _dev_console_suggestions != null and _dev_console_suggestions.visible:
					_move_dev_console_suggestion_selection(1)
				else:
					_move_dev_console_history_selection(1)
				return true

	if not _dev_console_open:
		return false

	if event is InputEventMouseButton or event is InputEventMouseMotion or event is InputEventScreenTouch or event is InputEventScreenDrag:
		if _dev_console_panel != null and _dev_console_panel.visible:
			var mouse_position := get_viewport().get_mouse_position()
			var rect := Rect2(_dev_console_panel.global_position, _dev_console_panel.size)
			if rect.has_point(mouse_position):
				# Let built-in UI controls (RichTextLabel scrollbar, ItemList, LineEdit)
				# receive mouse events directly.
				return false
			# Block gameplay clicks/touches while console is open.
			return true

	return false


func _set_dev_console_open(should_open: bool) -> void:
	_dev_console_open = should_open
	if _dev_console_panel == null:
		return
	_dev_console_panel.visible = _dev_console_open
	if _dev_console_open and _dev_console_input != null:
		_dev_console_input.grab_focus()
		_dev_console_input.select_all()
		_on_dev_console_input_text_changed(_dev_console_input.text)
	else:
		_clear_dev_console_suggestions()


func _on_dev_console_command_submitted(command_text: String) -> void:
	if _dev_console_input != null:
		_dev_console_input.clear()
	_clear_dev_console_suggestions()
	_execute_dev_console_command(command_text)


func _execute_dev_console_command(command_text: String) -> void:
	var trimmed := command_text.strip_edges()
	if trimmed.is_empty():
		return

	var resolved_command_text: String = _resolve_dev_console_bang_command(trimmed)
	if resolved_command_text.is_empty():
		return

	_push_dev_console_history(trimmed)
	_push_dev_console_history(resolved_command_text)

	var effective_text: String = _apply_dev_console_alias(resolved_command_text)
	if effective_text.is_empty():
		return

	_push_dev_console_history(effective_text)
	_dev_console_log("> %s" % trimmed)
	if effective_text != trimmed:
		_dev_console_log("= %s" % effective_text)
	var tokens: Array[String] = _tokenize_dev_console_command(effective_text)
	if tokens.is_empty():
		return

	var command := tokens[0].to_lower()
	match command:
		"help":
			_dev_console_help(tokens)
		"list_items":
			_dev_console_list_items(tokens)
		"find_item":
			_dev_console_find_item(tokens)
		"give":
			_dev_console_give_by_id(tokens, "auto")
		"give_inv":
			_dev_console_give_by_id(tokens, "inventory")
		"spawn":
			_dev_console_give_by_id(tokens, "world")
		"give_name":
			_dev_console_give_by_name(tokens)
		"history":
			_dev_console_history_cmd(tokens)
		"aliases":
			_dev_console_aliases_cmd(tokens)
		"alias":
			_dev_console_alias_cmd(tokens)
		"god", "invuln":
			_dev_console_god_cmd(tokens)
		"speed":
			_dev_console_speed_cmd(tokens)
		"list_houses":
			_dev_console_list_houses_cmd()
		"place_house":
			_dev_console_place_house_cmd(tokens)
		_:
			_dev_console_log("Unknown command: %s" % command)


func _dev_console_help(tokens: Array[String]) -> void:
	if tokens.size() <= 1:
		_dev_console_log("help [command]")
		_dev_console_log("list_items [filter] [limit], find_item <text> [limit], give/give_inv/spawn <id|path> [count], give_name \"Item Name\" [count], god [on|off], speed <value>, list_houses, place_house <id>, history [limit], aliases, alias <short> <command>, !!")
		return

	var topic: String = tokens[1].to_lower()
	match topic:
		"give":
			_dev_console_log("give <id|res://path> [count] -> в инвентарь, а если не влезает, то рядом на землю.")
		"give_inv":
			_dev_console_log("give_inv <id|res://path> [count] -> только в инвентарь, без сброса на землю.")
		"spawn":
			_dev_console_log("spawn <id|res://path> [count] -> всегда спавнит рядом с игроком.")
		"give_name":
			_dev_console_log("give_name \"Название\" [count] -> выдача по item_name.")
		"list_items":
			_dev_console_log("list_items [filter] [limit] -> список id -> path.")
		"find_item":
			_dev_console_log("find_item <text> [limit] -> поиск по id, имени и пути.")
		"history":
			_dev_console_log("history [limit] -> история команд. !! -> повторить последнюю.")
		"god", "invuln":
			_dev_console_log("god [on|off] -> РІРєР»СЋС‡РёС‚СЊ/РІС‹РєР»СЋС‡РёС‚СЊ РЅРµСѓСЏР·РІРёРјРѕСЃС‚СЊ.")
		"speed":
			_dev_console_log("speed <value> -> СѓСЃС‚Р°РЅРѕРІРёС‚СЊ Р±Р°Р·РѕРІСѓСЋ СЃРєРѕСЂРѕСЃС‚СЊ РїРµСЂСЃРѕРЅР°Р¶Р°.")
		"aliases", "alias":
			_dev_console_log("aliases -> список алиасов. alias <short> <command> -> добавить/изменить.")
		"!!":
			_dev_console_log("!! -> выполнить последнюю команду из истории.")
		_:
			_dev_console_log("No help for: %s" % topic)


func _dev_console_list_items(tokens: Array[String]) -> void:
	_ensure_dev_item_index()
	var filter_text: String = ""
	var limit: int = 40
	if tokens.size() >= 2:
		filter_text = tokens[1].to_lower()
	if tokens.size() >= 3:
		limit = clampi(int(tokens[2]), 1, 300)

	var shown: int = 0
	for id in _dev_item_ids_sorted:
		var path: String = String(_dev_item_path_by_id.get(id, ""))
		if path.is_empty():
			continue
		if not filter_text.is_empty() and not id.contains(filter_text) and not path.to_lower().contains(filter_text):
			continue
		_dev_console_log("%s -> %s" % [id, path])
		shown += 1
		if shown >= limit:
			break

	_dev_console_log("Items shown: %d (total: %d)" % [shown, _dev_item_ids_sorted.size()])


func _dev_console_find_item(tokens: Array[String]) -> void:
	if tokens.size() < 2:
		_dev_console_log("Usage: find_item <text> [limit]")
		return
	_ensure_dev_item_index()

	var query: String = tokens[1].to_lower()
	var limit: int = 30
	if tokens.size() >= 3:
		limit = clampi(int(tokens[2]), 1, 300)

	var names_by_path: Dictionary = {}
	for name_key in _dev_item_paths_by_name.keys():
		var paths: Array = _dev_item_paths_by_name.get(name_key, [])
		for raw_path in paths:
			names_by_path[String(raw_path)] = String(name_key)

	var shown: int = 0
	for id in _dev_item_ids_sorted:
		var path: String = String(_dev_item_path_by_id.get(id, ""))
		if path.is_empty():
			continue
		var item_name: String = String(names_by_path.get(path, ""))
		var matches: bool = id.contains(query) or path.to_lower().contains(query) or item_name.contains(query)
		if not matches:
			continue
		_dev_console_log("%s | %s | %s" % [id, item_name, path])
		shown += 1
		if shown >= limit:
			break

	_dev_console_log("Matches: %d" % shown)


func _dev_console_give_by_id(tokens: Array[String], mode: String = "auto") -> void:
	if tokens.size() < 2:
		_dev_console_log("Usage: give|give_inv|spawn <id|res://path> [count]")
		return
	if _is_network_client_inventory_mutation_blocked():
		_dev_console_log("Команда доступна только на сервере/в одиночной игре.")
		return

	var id_or_path: String = tokens[1]
	var count: int = 1
	if tokens.size() >= 3:
		count = max(int(tokens[2]), 1)

	var item_definition: ItemData = _resolve_dev_item_definition(id_or_path)
	if item_definition == null:
		_dev_console_log("Item not found: %s" % id_or_path)
		return
	_dev_console_give_item_definition(item_definition, count, mode)


func _dev_console_give_by_name(tokens: Array[String]) -> void:
	if tokens.size() < 2:
		_dev_console_log("Usage: give_name \"Item Name\" [count]")
		return
	if _is_network_client_inventory_mutation_blocked():
		_dev_console_log("Команда доступна только на сервере/в одиночной игре.")
		return

	var item_name_query: String = tokens[1].strip_edges()
	var count: int = 1
	if tokens.size() >= 3:
		count = max(int(tokens[2]), 1)

	_ensure_dev_item_index()
	var key: String = item_name_query.to_lower()
	var candidate_paths: Array = _dev_item_paths_by_name.get(key, [])
	if candidate_paths.is_empty():
		_dev_console_log("Item name not found: %s" % item_name_query)
		return

	var definition: ItemData = load(String(candidate_paths[0])) as ItemData
	if definition == null:
		_dev_console_log("Failed to load item by name: %s" % item_name_query)
		return
	_dev_console_give_item_definition(definition, count, "auto")


func _dev_console_give_item_definition(definition: ItemData, count: int, mode: String = "auto") -> void:
	if definition == null:
		return
	var total_requested: int = max(count, 1)
	var remaining: int = total_requested
	var inventory_stacks_added: int = 0
	var world_stacks_spawned: int = 0
	var dropped_stacks: int = 0
	var stack_size: int = max(definition.max_stack_size, 1)

	while remaining > 0:
		var give_count: int = min(stack_size, remaining)
		var instance: ItemData = definition.create_instance(give_count)
		match mode:
			"inventory":
				if _try_store_picked_item(instance):
					inventory_stacks_added += 1
				else:
					dropped_stacks += 1
			"world":
				if _spawn_world_item(instance):
					world_stacks_spawned += 1
				else:
					dropped_stacks += 1
			_:
				var stored_without_drop: bool = try_store_item_or_drop(instance)
				if stored_without_drop:
					inventory_stacks_added += 1
				else:
					world_stacks_spawned += 1
		remaining -= give_count

	_dev_console_log("Issued %d x %s | inv stacks: %d | world stacks: %d | failed: %d" % [total_requested, definition.item_name, inventory_stacks_added, world_stacks_spawned, dropped_stacks])


func _resolve_dev_item_definition(id_or_path: String) -> ItemData:
	if id_or_path.begins_with("res://"):
		return load(id_or_path) as ItemData

	_ensure_dev_item_index()
	var item_path: String = String(_dev_item_path_by_id.get(id_or_path.to_lower(), ""))
	if item_path.is_empty():
		return null
	return load(item_path) as ItemData


func _ensure_dev_item_index() -> void:
	if not _dev_item_path_by_id.is_empty():
		return

	_dev_item_path_by_id.clear()
	_dev_item_ids_sorted.clear()
	_dev_item_paths_by_name.clear()
	_collect_dev_item_resources("res://Resources")
	var raw_ids: Array = _dev_item_path_by_id.keys()
	for raw_id in raw_ids:
		_dev_item_ids_sorted.append(String(raw_id))
	_dev_item_ids_sorted.sort()
	_dev_console_log("Indexed items: %d" % _dev_item_ids_sorted.size())


func _collect_dev_item_resources(directory_path: String) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return

	directory.list_dir_begin()
	var entry_name: String = directory.get_next()
	while not entry_name.is_empty():
		if entry_name.begins_with("."):
			entry_name = directory.get_next()
			continue

		var entry_path: String = directory_path.path_join(entry_name)
		if directory.current_is_dir():
			_collect_dev_item_resources(entry_path)
			entry_name = directory.get_next()
			continue

		var ext: String = entry_path.get_extension().to_lower()
		if ext == "tres" or ext == "res":
			_index_dev_item_resource(entry_path)
		elif ext == "remap":
			var original_path := entry_path.trim_suffix(".remap")
			var original_ext := original_path.get_extension().to_lower()
			if original_ext == "tres" or original_ext == "res":
				_index_dev_item_resource(original_path)

		entry_name = directory.get_next()
	directory.list_dir_end()


func _index_dev_item_resource(resource_path: String) -> void:
	if resource_path.is_empty():
		return
	var resource: Resource = load(resource_path)
	var item: ItemData = resource as ItemData
	if item == null:
		return

	var base_id: String = resource_path.get_file().get_basename().to_lower()
	var unique_id: String = base_id
	var suffix: int = 2
	while _dev_item_path_by_id.has(unique_id) and String(_dev_item_path_by_id.get(unique_id, "")) != resource_path:
		unique_id = "%s_%d" % [base_id, suffix]
		suffix += 1
	_dev_item_path_by_id[unique_id] = resource_path

	var item_name_key: String = item.item_name.to_lower()
	if not item_name_key.is_empty():
		var name_paths: Array = _dev_item_paths_by_name.get(item_name_key, [])
		if not name_paths.has(resource_path):
			name_paths.append(resource_path)
			_dev_item_paths_by_name[item_name_key] = name_paths


func _tokenize_dev_console_command(command_text: String) -> Array[String]:
	var tokens: Array[String] = []
	var current: String = ""
	var in_quotes: bool = false

	for i in range(command_text.length()):
		var ch: String = command_text[i]
		if ch == "\"":
			in_quotes = not in_quotes
			continue
		if not in_quotes and ch in [" ", "\t"]:
			if not current.is_empty():
				tokens.append(current)
				current = ""
			continue
		current += ch

	if not current.is_empty():
		tokens.append(current)
	return tokens


func _resolve_dev_console_bang_command(trimmed: String) -> String:
	if trimmed != "!!":
		return trimmed
	for i in range(_dev_console_history.size() - 1, -1, -1):
		var candidate: String = _dev_console_history[i]
		if candidate.is_empty() or candidate == "!!":
			continue
		_dev_console_log("repeat: %s" % candidate)
		return candidate
	_dev_console_log("History is empty")
	return ""


func _apply_dev_console_alias(command_text: String) -> String:
	var tokens: Array[String] = _tokenize_dev_console_command(command_text)
	if tokens.is_empty():
		return command_text
	var alias_key: String = tokens[0].to_lower()
	if not _dev_console_aliases.has(alias_key):
		return command_text
	tokens[0] = String(_dev_console_aliases.get(alias_key, tokens[0]))
	var rebuilt: String = ""
	for i in range(tokens.size()):
		if i > 0:
			rebuilt += " "
		rebuilt += tokens[i]
	return rebuilt


func _push_dev_console_history(command_text: String) -> void:
	if command_text.is_empty():
		return
	if _dev_console_history.is_empty() or _dev_console_history[_dev_console_history.size() - 1] != command_text:
		_dev_console_history.append(command_text)
		if _dev_console_history.size() > 200:
			_dev_console_history.remove_at(0)
	_dev_console_history_index = _dev_console_history.size()


func _move_dev_console_history_selection(direction: int) -> void:
	if _dev_console_input == null:
		return
	if _dev_console_history.is_empty():
		return
	if _dev_console_history_index < 0:
		_dev_console_history_index = _dev_console_history.size()
	_dev_console_history_index = clampi(_dev_console_history_index + direction, 0, _dev_console_history.size())
	if _dev_console_history_index >= _dev_console_history.size():
		_dev_console_input.text = ""
	else:
		_dev_console_input.text = _dev_console_history[_dev_console_history_index]
	_dev_console_input.caret_column = _dev_console_input.text.length()
	_on_dev_console_input_text_changed(_dev_console_input.text)


func _dev_console_history_cmd(tokens: Array[String]) -> void:
	var limit: int = 20
	if tokens.size() >= 2:
		limit = clampi(int(tokens[1]), 1, 200)
	if _dev_console_history.is_empty():
		_dev_console_log("History is empty")
		return
	var start_index: int = max(_dev_console_history.size() - limit, 0)
	for i in range(start_index, _dev_console_history.size()):
		_dev_console_log("%d: %s" % [i + 1, _dev_console_history[i]])


func _dev_console_aliases_cmd(_tokens: Array[String]) -> void:
	var keys: Array = _dev_console_aliases.keys()
	keys.sort()
	for key in keys:
		var alias_key: String = String(key)
		_dev_console_log("%s -> %s" % [alias_key, String(_dev_console_aliases.get(alias_key, ""))])


func _dev_console_alias_cmd(tokens: Array[String]) -> void:
	if tokens.size() < 3:
		_dev_console_log("Usage: alias <short> <command>")
		return
	var alias_key: String = tokens[1].strip_edges().to_lower()
	if alias_key.is_empty():
		_dev_console_log("Alias key is empty")
		return
	var command_value: String = tokens[2].strip_edges().to_lower()
	if command_value.is_empty():
		_dev_console_log("Alias target is empty")
		return
	_dev_console_aliases[alias_key] = command_value
	_dev_console_log("Alias set: %s -> %s" % [alias_key, command_value])


func _dev_console_god_cmd(tokens: Array[String]) -> void:
	if _is_network_client_inventory_mutation_blocked():
		_dev_console_log("РљРѕРјР°РЅРґР° РґРѕСЃС‚СѓРїРЅР° С‚РѕР»СЊРєРѕ РЅР° СЃРµСЂРІРµСЂРµ/РІ РѕРґРёРЅРѕС‡РЅРѕР№ РёРіСЂРµ.")
		return
	var player_node := _get_dev_console_player()
	if player_node == null:
		_dev_console_log("Player not found in group 'player'")
		return
	var enabled: bool = not bool(player_node.debug_invulnerable)
	if tokens.size() >= 2:
		var mode := tokens[1].to_lower()
		if mode in ["on", "1", "true"]:
			enabled = true
		elif mode in ["off", "0", "false"]:
			enabled = false
		else:
			_dev_console_log("Usage: god [on|off]")
			return
	if player_node.has_method("set_debug_invulnerable"):
		player_node.call("set_debug_invulnerable", enabled)
	else:
		player_node.debug_invulnerable = enabled
	_dev_console_log("Invulnerability: %s" % ("ON" if enabled else "OFF"))


func _dev_console_speed_cmd(tokens: Array[String]) -> void:
	if tokens.size() < 2:
		_dev_console_log("Usage: speed <value>")
		return
	if _is_network_client_inventory_mutation_blocked():
		_dev_console_log("РљРѕРјР°РЅРґР° РґРѕСЃС‚СѓРїРЅР° С‚РѕР»СЊРєРѕ РЅР° СЃРµСЂРІРµСЂРµ/РІ РѕРґРёРЅРѕС‡РЅРѕР№ РёРіСЂРµ.")
		return
	var speed_value := float(tokens[1])
	if speed_value <= 0.0:
		_dev_console_log("Speed must be > 0")
		return
	var player_node := _get_dev_console_player()
	if player_node == null:
		_dev_console_log("Player not found in group 'player'")
		return
	if player_node.has_method("set_debug_base_move_speed"):
		player_node.call("set_debug_base_move_speed", speed_value)
	else:
		player_node.base_move_speed = speed_value
		player_node.speed = speed_value
	_dev_console_log("Player speed set to %.2f" % speed_value)


func _get_dev_console_player() -> Node:
	return get_tree().get_first_node_in_group("player")


func _get_house_placement_controller() -> Node:
	return get_tree().get_first_node_in_group("house_placement_controller")


func _dev_console_list_houses_cmd() -> void:
	var placement_controller := _get_house_placement_controller()
	if placement_controller == null or not placement_controller.has_method("get_available_house_ids"):
		_dev_console_log("House placement controller not found")
		return

	var raw_ids: Variant = placement_controller.call("get_available_house_ids")
	if not (raw_ids is Array):
		_dev_console_log("No houses available")
		return

	var house_ids: Array = raw_ids as Array
	if house_ids.is_empty():
		_dev_console_log("No houses available")
		return

	for raw_id in house_ids:
		_dev_console_log(String(raw_id))


func _dev_console_place_house_cmd(tokens: Array[String]) -> void:
	if tokens.size() < 2:
		_dev_console_log("Usage: place_house <id>")
		return
	if _is_network_client_inventory_mutation_blocked():
		_dev_console_log("Command is available only on server or in single-player")
		return

	var placement_controller := _get_house_placement_controller()
	if placement_controller == null or not placement_controller.has_method("start_house_placement"):
		_dev_console_log("House placement controller not found")
		return

	var house_id: String = tokens[1].strip_edges().to_lower()
	var started: bool = bool(placement_controller.call("start_house_placement", house_id))
	if not started:
		_dev_console_log("Unknown or unavailable house id: %s" % house_id)
		return

	close_inventory()
	_dev_console_log("Placing house: %s | left click - place | right click/Esc - cancel" % house_id)


func _on_dev_console_input_text_changed(new_text: String) -> void:
	_refresh_dev_console_suggestions(new_text)


func _refresh_dev_console_suggestions(text: String) -> void:
	if _dev_console_suggestions == null:
		return

	_dev_console_suggestions.clear()
	_dev_console_suggestion_values.clear()
	_dev_console_selected_suggestion = -1

	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		_dev_console_suggestions.visible = false
		return

	var known_commands: Array[String] = ["help", "list_items", "find_item", "give", "give_inv", "spawn", "give_name", "god", "invuln", "speed", "list_houses", "place_house", "history", "aliases", "alias"]
	var tokens: Array[String] = _tokenize_dev_console_command(text)
	if tokens.is_empty():
		_dev_console_suggestions.visible = false
		return

	var first: String = tokens[0].to_lower()
	var max_hints: int = 12

	if tokens.size() == 1 and not text.ends_with(" "):
		for cmd in known_commands:
			if cmd.begins_with(first):
				_dev_console_suggestion_values.append(cmd)
				_dev_console_suggestions.add_item("cmd: %s" % cmd)
		_dev_console_suggestions.visible = not _dev_console_suggestion_values.is_empty()
		if _dev_console_suggestions.visible:
			_move_dev_console_suggestion_selection(1)
		return

	if first in ["give", "give_inv", "spawn"]:
		_ensure_dev_item_index()
		var item_filter: String = ""
		if tokens.size() >= 2:
			item_filter = tokens[1].to_lower()
		for id in _dev_item_ids_sorted:
			if item_filter.is_empty() or id.contains(item_filter):
				_dev_console_suggestion_values.append(id)
				_dev_console_suggestions.add_item("item: %s" % id)
			if _dev_console_suggestion_values.size() >= max_hints:
				break
	elif first == "give_name":
		_ensure_dev_item_index()
		var name_filter: String = ""
		if tokens.size() >= 2:
			name_filter = tokens[1].to_lower()
		var names: Array = _dev_item_paths_by_name.keys()
		names.sort()
		for raw_name in names:
			var item_name: String = String(raw_name)
			if name_filter.is_empty() or item_name.contains(name_filter):
				_dev_console_suggestion_values.append(item_name)
				_dev_console_suggestions.add_item("name: %s" % item_name)
			if _dev_console_suggestion_values.size() >= max_hints:
				break
	elif first == "list_items" and tokens.size() <= 2:
		var filters: Array[String] = ["food", "medical", "misc", "weapon", "ammo", "clothes"]
		var existing_filter: String = ""
		if tokens.size() >= 2:
			existing_filter = tokens[1].to_lower()
		for hint in filters:
			if existing_filter.is_empty() or hint.begins_with(existing_filter):
				_dev_console_suggestion_values.append(hint)
				_dev_console_suggestions.add_item("filter: %s" % hint)
	elif first == "place_house":
		var placement_controller := _get_house_placement_controller()
		if placement_controller != null and placement_controller.has_method("get_available_house_ids"):
			var house_filter: String = ""
			if tokens.size() >= 2:
				house_filter = tokens[1].to_lower()
			var raw_house_ids: Variant = placement_controller.call("get_available_house_ids")
			if raw_house_ids is Array:
				for raw_house_id in raw_house_ids:
					var house_id: String = String(raw_house_id)
					if house_filter.is_empty() or house_id.contains(house_filter):
						_dev_console_suggestion_values.append(house_id)
						_dev_console_suggestions.add_item("house: %s" % house_id)
					if _dev_console_suggestion_values.size() >= max_hints:
						break

	_dev_console_suggestions.visible = not _dev_console_suggestion_values.is_empty()
	if _dev_console_suggestions.visible:
		_move_dev_console_suggestion_selection(1)


func _on_dev_console_suggestion_selected(index: int) -> void:
	_dev_console_selected_suggestion = index


func _move_dev_console_suggestion_selection(direction: int) -> void:
	if _dev_console_suggestion_values.is_empty() or _dev_console_suggestions == null:
		return
	var current: int = _dev_console_selected_suggestion
	if current < 0:
		current = 0 if direction >= 0 else _dev_console_suggestion_values.size() - 1
	else:
		current = (current + direction + _dev_console_suggestion_values.size()) % _dev_console_suggestion_values.size()
	_dev_console_selected_suggestion = current
	_dev_console_suggestions.select(current)
	_dev_console_suggestions.ensure_current_is_visible()


func _apply_dev_console_selected_suggestion() -> void:
	if _dev_console_input == null:
		return
	if _dev_console_selected_suggestion < 0 or _dev_console_selected_suggestion >= _dev_console_suggestion_values.size():
		return

	var selected: String = _dev_console_suggestion_values[_dev_console_selected_suggestion]
	var text: String = _dev_console_input.text
	var tokens: Array[String] = _tokenize_dev_console_command(text)
	if tokens.is_empty():
		_dev_console_input.text = selected
		_dev_console_input.caret_column = _dev_console_input.text.length()
		return

	var first: String = tokens[0].to_lower()
	if tokens.size() == 1 and not text.ends_with(" "):
		_dev_console_input.text = selected + " "
	elif first in ["give", "give_inv", "spawn"]:
		var parts: PackedStringArray = text.split(" ", false)
		if parts.size() <= 1:
			_dev_console_input.text = "give %s " % selected
		else:
			parts[1] = selected
			var rebuilt: String = ""
			for i in range(parts.size()):
				if i > 0:
					rebuilt += " "
				rebuilt += parts[i]
			_dev_console_input.text = rebuilt + (" " if parts.size() == 2 else "")
	elif first == "give_name":
		_dev_console_input.text = "give_name \"%s\" " % selected
	elif first == "list_items":
		_dev_console_input.text = "list_items %s " % selected
	elif first == "place_house":
		_dev_console_input.text = "place_house %s " % selected
	else:
		_dev_console_input.text = selected

	_dev_console_input.caret_column = _dev_console_input.text.length()
	_on_dev_console_input_text_changed(_dev_console_input.text)


func _clear_dev_console_suggestions() -> void:
	if _dev_console_suggestions != null:
		_dev_console_suggestions.clear()
		_dev_console_suggestions.visible = false
	_dev_console_suggestion_values.clear()
	_dev_console_selected_suggestion = -1


func _dev_console_log(message: String) -> void:
	if _dev_console_output == null:
		return
	_dev_console_output.append_text("%s\n" % message)
