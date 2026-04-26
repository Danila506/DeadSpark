extends Panel
class_name InventorySlot

signal drop_requested(target_slot: InventorySlot, drag_data: Dictionary)

enum SlotMode {
	NEARBY,
	EQUIPMENT,
	CONTAINER
}

enum IconHAlign {
	LEFT,
	CENTER,
	RIGHT
}

enum IconVAlign {
	TOP,
	CENTER,
	BOTTOM
}

@export var slot_mode: SlotMode = SlotMode.NEARBY
@export var slot_type: ItemData.ItemType = ItemData.ItemType.AR_Weapon

@export var icon_size: Vector2 = Vector2(64, 64)
@export var icon_rotation_degrees: float = 0.0
@export var show_name: bool = true
@export var show_endurance: bool = true
@export var show_endurance_indicator: bool = true
@export var endurance_indicator_only_for_weapons: bool = false
@export var stretch_icon_to_slot: bool = false
@export var icon_padding: float = 0.0
@export var icon_offset: Vector2 = Vector2.ZERO

@export var show_background_in_nearby: bool = false
@export var show_background_in_equipment: bool = false
@export var show_background_in_container: bool = true

@export var icon_h_align: IconHAlign = IconHAlign.CENTER
@export var icon_v_align: IconVAlign = IconVAlign.CENTER

@export var allowed_storage_categories: Array[ItemData.StorageCategory] = []
@export var use_allowed_item_types: bool = false
@export var allowed_item_types: Array[ItemData.ItemType] = []

var item_data: ItemData = null
var world_item: Node = null
var nearby_index: int = -1
var container_index: int = -1

@onready var background: TextureRect = $Background
@onready var icon: TextureRect = $Icon
@onready var name_label: Label = $NameLabel
@onready var endurance_label: Label = $EnduranceLabel
@onready var scope_overlay: TextureRect = _ensure_attachment_overlay("ScopeOverlay")
@onready var handle_overlay: TextureRect = _ensure_attachment_overlay("HandleOverlay")
@onready var silencer_overlay: TextureRect = _ensure_attachment_overlay("SilencerOverlay")
@onready var endurance_indicators_root: CanvasItem = _find_endurance_indicators_root()
@onready var endurance_indicator_high: CanvasItem = _find_endurance_indicator_child("HighEndurance")
@onready var endurance_indicator_medium: CanvasItem = _find_endurance_indicator_child("MediumEndurance")
@onready var endurance_indicator_low: CanvasItem = _find_endurance_indicator_child("LowEndurance")
@onready var endurance_indicator_critical: CanvasItem = _find_endurance_indicator_child("CriticalEndurance")
@onready var legacy_endurance_indicator: CanvasItem = _find_legacy_endurance_indicator()

@export var hint_sprite_path: NodePath
@onready var slot_hint_sprite: Node = get_node_or_null(hint_sprite_path)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_ARROW

	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	endurance_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	handle_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	silencer_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_indicator_mouse_filter(endurance_indicators_root)
	_set_indicator_mouse_filter(endurance_indicator_high)
	_set_indicator_mouse_filter(endurance_indicator_medium)
	_set_indicator_mouse_filter(endurance_indicator_low)
	_set_indicator_mouse_filter(endurance_indicator_critical)
	_set_indicator_mouse_filter(legacy_endurance_indicator)

	background.anchor_left = 0.0
	background.anchor_top = 0.0
	background.anchor_right = 1.0
	background.anchor_bottom = 1.0
	background.offset_left = 0.0
	background.offset_top = 0.0
	background.offset_right = 0.0
	background.offset_bottom = 0.0

	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE

	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	_update_background_visibility()
	_apply_visual_mode()
	_update_visuals()
	

func _update_background_visibility() -> void:
	if background == null:
		return

	match slot_mode:
		SlotMode.NEARBY:
			background.visible = show_background_in_nearby
		SlotMode.EQUIPMENT:
			background.visible = show_background_in_equipment
		SlotMode.CONTAINER:
			background.visible = show_background_in_container	

func _resized() -> void:
	_apply_visual_mode()


func _apply_visual_mode() -> void:
	if icon == null:
		return

	name_label.visible = show_name
	endurance_label.visible = show_endurance or (item_data != null and (item_data.show_stack_count_in_inventory or _should_show_weapon_ammo(item_data)))

	if stretch_icon_to_slot:
		_layout_icon_to_slot()
	else:
		_layout_icon_normal()

	_layout_labels()
	_update_attachment_overlays_visual()
		
	_update_background_visibility()


func _layout_labels() -> void:
	if name_label == null or endurance_label == null:
		return

	if slot_mode != SlotMode.NEARBY and item_data != null and (item_data.show_stack_count_in_inventory or _should_show_weapon_ammo(item_data)):
		endurance_label.offset_left = 4.0
		endurance_label.offset_top = size.y - 24.0
		endurance_label.offset_right = size.x - 4.0
		endurance_label.offset_bottom = size.y + 2.0
		endurance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		endurance_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		return

	if slot_mode == SlotMode.NEARBY:
		var icon_rect_position: Vector2 = icon.position
		var icon_rect_size: Vector2 = icon.size
		var text_left: float = icon_rect_position.x + icon_rect_size.x + 12.0
		var text_width: float = max(size.x - text_left - 12.0, 32.0)

		name_label.offset_left = text_left
		name_label.offset_top = 10.0
		name_label.offset_right = text_left + text_width
		name_label.offset_bottom = 42.0
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

		endurance_label.offset_left = text_left
		endurance_label.offset_top = 46.0
		endurance_label.offset_right = text_left + text_width
		endurance_label.offset_bottom = 78.0
		endurance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		endurance_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		return

	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	endurance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	endurance_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func _get_icon_position_for_size(target_size: Vector2) -> Vector2:
	var x: float = 0.0
	var y: float = 0.0

	match icon_h_align:
		IconHAlign.LEFT:
			x = 0.0
		IconHAlign.CENTER:
			x = (size.x - target_size.x) / 2.0
		IconHAlign.RIGHT:
			x = size.x - target_size.x

	match icon_v_align:
		IconVAlign.TOP:
			y = 0.0
		IconVAlign.CENTER:
			y = (size.y - target_size.y) / 2.0
		IconVAlign.BOTTOM:
			y = size.y - target_size.y

	return Vector2(x, y)

func _layout_icon_normal() -> void:
	icon.anchor_left = 0.0
	icon.anchor_top = 0.0
	icon.anchor_right = 0.0
	icon.anchor_bottom = 0.0

	var effective_icon_size: Vector2 = icon_size
	if item_data != null:
		effective_icon_size *= max(item_data.inventory_icon_scale, 0.1)

	icon.size = effective_icon_size
	icon.custom_minimum_size = effective_icon_size
	icon.position = _get_icon_position_for_size(icon.size) + icon_offset

	icon.pivot_offset = icon.size / 2.0
	icon.rotation_degrees = _get_effective_icon_rotation()


func _layout_icon_to_slot() -> void:
	var effective_padding: float = icon_padding
	if item_data != null:
		effective_padding = max(icon_padding / max(item_data.inventory_icon_scale, 0.1), 0.0)

	var available_size := size - Vector2(effective_padding * 2.0, effective_padding * 2.0)

	if available_size.x < 1.0 or available_size.y < 1.0:
		return

	icon.anchor_left = 0.0
	icon.anchor_top = 0.0
	icon.anchor_right = 0.0
	icon.anchor_bottom = 0.0

	icon.size = available_size
	icon.custom_minimum_size = available_size
	icon.position = _get_icon_position_for_size(icon.size) + icon_offset

	icon.pivot_offset = icon.size / 2.0
	icon.rotation_degrees = _get_effective_icon_rotation()


func _get_effective_icon_rotation() -> float:
	if slot_mode == SlotMode.NEARBY and item_data != null:
		return item_data.inventory_icon_rotation_degrees

	return icon_rotation_degrees


func set_nearby_item(item: ItemData, world_ref: Node, index: int = -1) -> void:
	item_data = item
	world_item = world_ref
	nearby_index = index
	container_index = -1
	_update_visuals()


func set_equipped_item(item: ItemData) -> void:
	item_data = item
	world_item = null
	nearby_index = -1
	container_index = -1
	_update_visuals()


func set_container_item(item: ItemData, index: int) -> void:
	item_data = item
	world_item = null
	nearby_index = -1
	container_index = index
	_update_visuals()


func clear_slot() -> void:
	item_data = null
	world_item = null
	nearby_index = -1
	container_index = -1
	_update_visuals()


func _update_visuals() -> void:
	if icon == null or name_label == null or endurance_label == null:
		return

	if item_data == null:
		if slot_hint_sprite != null:
			slot_hint_sprite.visible = true

		icon.texture = null
		icon.visible = false
		name_label.text = ""
		endurance_label.text = ""
		scope_overlay.visible = false
		handle_overlay.visible = false
		silencer_overlay.visible = false
		_set_endurance_indicators_visible(false)
		_update_endurance_tooltip()
		tooltip_text = ""
		return

	if slot_hint_sprite != null:
		slot_hint_sprite.visible = false

	icon.texture = item_data.inventory_icon
	icon.visible = true

	if show_name:
		name_label.text = item_data.item_name
	else:
		name_label.text = ""

	if _should_show_weapon_ammo(item_data):
		endurance_label.text = InventoryManager.get_weapon_display_text(item_data)
	elif item_data.show_stack_count_in_inventory:
		endurance_label.text = str(item_data.stack_count)
	elif show_endurance:
		endurance_label.text = str(item_data.endurance) + "%"
	else:
		endurance_label.text = ""

	_update_endurance_indicator()
	_update_endurance_tooltip()
	_update_slot_tooltip()
	_apply_visual_mode()


func _should_show_weapon_ammo(item: ItemData) -> bool:
	return item != null and item.storage_category == ItemData.StorageCategory.WEAPON and item.bullet_scene != null and item.magazine_size > 0


func _ensure_attachment_overlay(overlay_name: String) -> TextureRect:
	var existing_overlay: TextureRect = get_node_or_null(overlay_name) as TextureRect
	if existing_overlay != null:
		return existing_overlay

	var overlay := TextureRect.new()
	overlay.name = overlay_name
	overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	overlay.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	overlay.z_index = 5
	overlay.visible = false
	add_child(overlay)
	return overlay


func _update_attachment_overlays_visual() -> void:
	if scope_overlay == null or handle_overlay == null or silencer_overlay == null:
		return

	if item_data == null or item_data.storage_category != ItemData.StorageCategory.WEAPON:
		scope_overlay.visible = false
		handle_overlay.visible = false
		silencer_overlay.visible = false
		return

	if InventoryManager == null:
		scope_overlay.visible = false
		handle_overlay.visible = false
		silencer_overlay.visible = false
		return

	_update_attachment_overlay_for_slot(scope_overlay, ItemData.AttachmentSlot.SCOPE)
	_update_attachment_overlay_for_slot(handle_overlay, ItemData.AttachmentSlot.HANDLE)
	_update_attachment_overlay_for_slot(silencer_overlay, ItemData.AttachmentSlot.SILENCER)


func _update_attachment_overlay_for_slot(overlay: TextureRect, attachment_slot: int) -> void:
	if overlay == null:
		return

	var attached_attachment: ItemData = InventoryManager.get_attached_attachment(item_data, attachment_slot)
	if attached_attachment == null:
		overlay.visible = false
		return

	var attachment_texture: Texture2D = attached_attachment.get_attachment_mounted_texture() if attached_attachment.has_method("get_attachment_mounted_texture") else attached_attachment.mounted_scope_texture
	if attachment_texture == null:
		attachment_texture = attached_attachment.inventory_icon
	if attachment_texture == null:
		overlay.visible = false
		return

	overlay.texture = attachment_texture
	var safe_attachment_scale: Vector2 = _clamp_scale_vector(attached_attachment.mounted_scope_scale)
	var final_size: Vector2 = attachment_texture.get_size() * safe_attachment_scale
	if final_size.x < 2.0 or final_size.y < 2.0:
		final_size = Vector2(2.0, 2.0)

	overlay.size = final_size
	overlay.custom_minimum_size = final_size
	overlay.position = icon.position + (icon.size * 0.5) - (final_size * 0.5) + _get_inventory_offset_for_attachment_slot(attachment_slot)
	overlay.pivot_offset = final_size / 2.0
	overlay.rotation_degrees = _get_inventory_rotation_for_attachment_slot(attachment_slot, attached_attachment)
	overlay.flip_h = attached_attachment.mounted_scope_flip_h
	overlay.flip_v = attached_attachment.mounted_scope_flip_v
	overlay.visible = icon.visible


func _get_inventory_offset_for_attachment_slot(attachment_slot: int) -> Vector2:
	match attachment_slot:
		ItemData.AttachmentSlot.HANDLE:
			return item_data.handle_inventory_offset
		ItemData.AttachmentSlot.SILENCER:
			return item_data.silencer_inventory_offset
		_:
			return item_data.scope_inventory_offset


func _get_inventory_rotation_for_attachment_slot(attachment_slot: int, attachment_item: ItemData) -> float:
	var base_rotation: float = attachment_item.mounted_scope_rotation_degrees
	if attachment_slot == ItemData.AttachmentSlot.SCOPE:
		return item_data.scope_inventory_rotation_degrees + base_rotation
	return base_rotation


func _clamp_scale_vector(value: Vector2) -> Vector2:
	return Vector2(max(value.x, 0.05), max(value.y, 0.05))


func _find_endurance_indicators_root() -> CanvasItem:
	for child in get_children():
		if not (child is CanvasItem):
			continue
		var child_name: String = String(child.name)
		if child_name.begins_with("EnduranceIndicators"):
			var root: CanvasItem = child as CanvasItem
			root.visible = false
			return root

	return null


func _find_endurance_indicator_child(child_name: String) -> CanvasItem:
	if endurance_indicators_root == null:
		return null
	var child_node: CanvasItem = endurance_indicators_root.get_node_or_null(child_name) as CanvasItem
	if child_node != null:
		child_node.visible = false
	return child_node


func _find_legacy_endurance_indicator() -> CanvasItem:
	var indicator_by_name: CanvasItem = get_node_or_null("EnduranceIndicator") as CanvasItem
	if indicator_by_name != null:
		indicator_by_name.visible = false
	return indicator_by_name


func _update_endurance_indicator() -> void:
	if item_data == null or not show_endurance_indicator:
		_set_endurance_indicators_visible(false)
		return

	if endurance_indicator_only_for_weapons and item_data.storage_category != ItemData.StorageCategory.WEAPON:
		_set_endurance_indicators_visible(false)
		return

	if item_data.endurance <= 0:
		_set_endurance_indicators_visible(false)
		return

	if _has_split_endurance_indicators():
		_show_split_endurance_indicator_for_value(item_data.endurance)
		return

	if legacy_endurance_indicator != null:
		legacy_endurance_indicator.modulate = _get_endurance_color(item_data.endurance)
		legacy_endurance_indicator.visible = true


func _set_endurance_indicators_visible(visible_state: bool) -> void:
	if endurance_indicators_root != null:
		endurance_indicators_root.visible = visible_state
	_set_split_indicator_visibility(false, false, false, false)
	if legacy_endurance_indicator != null:
		legacy_endurance_indicator.visible = visible_state


func _has_split_endurance_indicators() -> bool:
	return endurance_indicators_root != null and (
		endurance_indicator_high != null
		or endurance_indicator_medium != null
		or endurance_indicator_low != null
		or endurance_indicator_critical != null
	)


func _show_split_endurance_indicator_for_value(endurance_value: int) -> void:
	if endurance_indicators_root == null:
		return

	endurance_indicators_root.visible = true
	if legacy_endurance_indicator != null:
		legacy_endurance_indicator.visible = false

	if endurance_value >= 75:
		_set_split_indicator_by_priority(endurance_indicator_high, endurance_indicator_medium, endurance_indicator_low, endurance_indicator_critical)
	elif endurance_value >= 50:
		_set_split_indicator_by_priority(endurance_indicator_medium, endurance_indicator_high, endurance_indicator_low, endurance_indicator_critical)
	elif endurance_value >= 25:
		_set_split_indicator_by_priority(endurance_indicator_low, endurance_indicator_medium, endurance_indicator_high, endurance_indicator_critical)
	else:
		_set_split_indicator_by_priority(endurance_indicator_critical, endurance_indicator_low, endurance_indicator_medium, endurance_indicator_high)


func _set_split_indicator_visibility(high_visible: bool, medium_visible: bool, low_visible: bool, critical_visible: bool) -> void:
	if endurance_indicator_high != null:
		endurance_indicator_high.visible = high_visible
	if endurance_indicator_medium != null:
		endurance_indicator_medium.visible = medium_visible
	if endurance_indicator_low != null:
		endurance_indicator_low.visible = low_visible
	if endurance_indicator_critical != null:
		endurance_indicator_critical.visible = critical_visible


func _set_split_indicator_by_priority(primary: CanvasItem, fallback_a: CanvasItem, fallback_b: CanvasItem, fallback_c: CanvasItem) -> void:
	_set_split_indicator_visibility(false, false, false, false)

	if primary != null:
		primary.visible = true
		return
	if fallback_a != null:
		fallback_a.visible = true
		return
	if fallback_b != null:
		fallback_b.visible = true
		return
	if fallback_c != null:
		fallback_c.visible = true


func _set_indicator_mouse_filter(indicator: CanvasItem) -> void:
	if indicator is Control:
		(indicator as Control).mouse_filter = Control.MOUSE_FILTER_PASS


func _update_endurance_tooltip() -> void:
	var tooltip: String = _build_endurance_tooltip_text()
	_set_indicator_tooltip(endurance_indicators_root, tooltip)
	_set_indicator_tooltip(endurance_indicator_high, tooltip)
	_set_indicator_tooltip(endurance_indicator_medium, tooltip)
	_set_indicator_tooltip(endurance_indicator_low, tooltip)
	_set_indicator_tooltip(endurance_indicator_critical, tooltip)
	_set_indicator_tooltip(legacy_endurance_indicator, tooltip)


func _build_endurance_tooltip_text() -> String:
	if item_data == null:
		return ""

	var safe_endurance: int = clamp(item_data.endurance, 0, 100)
	var wear_percent: int = 100 - safe_endurance
	return "Износ: %d%%\nПрочность: %d%%" % [wear_percent, safe_endurance]


func _set_indicator_tooltip(indicator: CanvasItem, text: String) -> void:
	if indicator is Control:
		(indicator as Control).tooltip_text = text


func _update_slot_tooltip() -> void:
	tooltip_text = _build_slot_tooltip_text()


func _build_slot_tooltip_text() -> String:
	if item_data == null:
		return ""

	var lines: Array[String] = []
	if not item_data.item_name.strip_edges().is_empty():
		lines.append(item_data.item_name)

	if item_data.storage_category == ItemData.StorageCategory.MEDICAL:
		lines.append("")
		lines.append("Характеристики:")
		var effect_lines: Array[String] = _build_medical_effect_lines()
		if effect_lines.is_empty():
			lines.append("- Без эффекта")
		else:
			for effect_line in effect_lines:
				lines.append("- " + effect_line)

		lines.append("")
		lines.append("Время использования: %.1f сек" % max(item_data.medical_use_time_sec, 0.0))
		return "\n".join(lines)

	if not item_data.description.strip_edges().is_empty():
		lines.append("")
		lines.append(item_data.description.strip_edges())

	return "\n".join(lines)


func _build_medical_effect_lines() -> Array[String]:
	var lines: Array[String] = []

	if not is_zero_approx(item_data.medical_health_restore):
		lines.append("Здоровье %+d" % int(round(item_data.medical_health_restore)))
	if not is_zero_approx(item_data.medical_radiation_change):
		lines.append("Радиация %+d" % int(round(item_data.medical_radiation_change)))
	if item_data.medical_stop_bleeding:
		lines.append("Устраняет кровотечение")
	if item_data.medical_heal_fracture:
		lines.append("Устраняет перелом")

	return lines


func _get_endurance_color(endurance_value: int) -> Color:
	if endurance_value >= 75:
		return Color(0.2, 0.9, 0.2, 1.0)
	if endurance_value >= 50:
		return Color(0.95, 0.9, 0.15, 1.0)
	if endurance_value >= 25:
		return Color(1.0, 0.55, 0.05, 1.0)
	return Color(0.9, 0.15, 0.15, 1.0)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if item_data == null:
		return null

	var preview := TextureRect.new()
	preview.texture = item_data.inventory_icon
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(128, 128)
	set_drag_preview(preview)

	return {
		"source_slot": self,
		"source_mode": slot_mode,
		"item": item_data,
		"world_item": world_item,
		"nearby_index": nearby_index,
		"container_index": container_index
	}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false

	if not data.has("item"):
		return false

	var dragged_item: ItemData = data["item"]

	match slot_mode:
		SlotMode.NEARBY:
			return false

		SlotMode.EQUIPMENT:
			if use_allowed_item_types and not allowed_item_types.is_empty():
				return dragged_item.item_type in allowed_item_types

			if not allowed_storage_categories.is_empty():
				if not dragged_item.can_be_stored_in_clothing:
					return false

				return dragged_item.storage_category in allowed_storage_categories

			return dragged_item.item_type == slot_type

		SlotMode.CONTAINER:
			if not dragged_item.can_be_stored_in_clothing:
				return false

			if allowed_storage_categories.is_empty():
				return true

			return dragged_item.storage_category in allowed_storage_categories

	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return

	drop_requested.emit(self, data)
