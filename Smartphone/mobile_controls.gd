extends CanvasLayer
class_name MobileControls

const ACTION_BUTTON_TEXTURE: Texture2D = preload("res://Smartphone/ActionBtn.png")
const INVENTORY_BUTTON_TEXTURE: Texture2D = preload("res://Smartphone/InventoryBtn.png")
const RELOAD_BUTTON_TEXTURE: Texture2D = preload("res://Smartphone/ReloadBtn.png")
const SCOPE_BUTTON_TEXTURE: Texture2D = preload("res://Smartphone/ScopeBtn.png")
const STEALTH_BUTTON_TEXTURE: Texture2D = preload("res://Smartphone/StealthBtn.png")
const SWITCH_WEAPON_BUTTON_TEXTURE: Texture2D = preload("res://Smartphone/switchWeapon.png")

@export var player_path: NodePath
@export var inventory_root_path: NodePath
@export var joystick_radius_px: float = 92.0
@export var aim_distance_px: float = 420.0
@export var deadzone: float = 0.18
@export_range(0.2, 1.0, 0.05) var fire_stick_threshold: float = 0.55
@export var mobile_button_size: Vector2 = Vector2(76.0, 76.0)
@export var mobile_safe_margin: Vector2 = Vector2(24.0, 24.0)
@export_range(0.35, 1.0, 0.05) var controls_opacity: float = 0.82
@export var auto_fire_enabled: bool = true
@export var aim_touch_zone_enabled: bool = true
@export var aim_touch_zone_fire_enabled: bool = true
@export_range(0.0, 0.9, 0.05) var aim_touch_zone_left_edge_ratio: float = 0.3
@export_range(0.1, 0.8, 0.05) var move_touch_zone_right_edge_ratio: float = 0.3
@export var aim_cursor_screen_margin_px: float = 42.0

var _player: Node
var _inventory_root: Node
var _move_touch_id: int = -1
var _aim_touch_id: int = -1
var _aim_zone_touch_id: int = -1
var _move_touch_origin: Vector2 = Vector2.ZERO
var _move_vector: Vector2 = Vector2.ZERO
var _aim_vector: Vector2 = Vector2.ZERO
var _move_touch_zone: Control
var _aim_touch_zone: Control
var _move_base: Control
var _move_knob: ColorRect
var _aim_base: Control
var _aim_knob: ColorRect
var _aim_cursor: TextureRect
var _scope_ready: bool = false
var _stealth_enabled: bool = false


func _ready() -> void:
	layer = 80
	_resolve_targets()
	if not _bind_layout():
		_build_layout()
	set_process(true)


func _exit_tree() -> void:
	_release_move_actions()
	_set_scope_ready(false)
	_set_stealth_enabled(false)
	_release_action(&"aim")
	_release_action(&"shoot")
	_release_action(&"melee_attack")
	_release_action(&"stealth")
	_aim_zone_touch_id = -1
	var weapon_controller: Node = _get_weapon_controller()
	if weapon_controller != null and weapon_controller.has_method("set_mobile_shoot_active"):
		weapon_controller.call("set_mobile_shoot_active", false)
	if weapon_controller != null and weapon_controller.has_method("clear_mobile_aim"):
		weapon_controller.call("clear_mobile_aim")


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_resolve_targets()
	if _scope_ready or _aim_vector != Vector2.ZERO or _aim_zone_touch_id != -1:
		_update_mobile_aim_cursor_texture()


func _input(event: InputEvent) -> void:
	if not _scope_ready or _aim_zone_touch_id == -1:
		return
	if not _event_matches_aim_zone_touch(event):
		return

	get_viewport().set_input_as_handled()
	if event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed:
		_aim_zone_touch_id = -1
		_release_aim_zone()
		return
	if event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
		_aim_zone_touch_id = -1
		_release_aim_zone()
		return

	var screen_position := Vector2.ZERO
	var has_screen_position := true
	if event is InputEventScreenTouch:
		screen_position = (event as InputEventScreenTouch).position
	elif event is InputEventScreenDrag:
		screen_position = (event as InputEventScreenDrag).position
	elif event is InputEventMouseButton:
		screen_position = (event as InputEventMouseButton).position
	elif event is InputEventMouseMotion:
		screen_position = (event as InputEventMouseMotion).position
	else:
		has_screen_position = false

	if not has_screen_position or _aim_touch_zone == null:
		return
	var local_position := _aim_touch_zone.get_global_transform().affine_inverse() * screen_position
	_update_aim_zone(local_position)


func _resolve_targets() -> void:
	if player_path != NodePath(""):
		_player = get_node_or_null(player_path)
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")

	if inventory_root_path != NodePath(""):
		_inventory_root = get_node_or_null(inventory_root_path)
	if _inventory_root == null:
		_inventory_root = get_node_or_null("../UI/InventoryRoot")


func _bind_layout() -> bool:
	var root := get_node_or_null("Root") as Control
	if root == null:
		return false

	_move_touch_zone = root.get_node_or_null("MoveTouchZone") as Control
	if _move_touch_zone != null:
		_configure_move_touch_zone(_move_touch_zone)
		_move_touch_zone.gui_input.connect(_on_move_stick_input)

	_ensure_aim_touch_zone(root)

	_move_base = root.get_node_or_null("MoveStick") as Control
	if _move_base != null:
		_move_base.gui_input.connect(_on_move_stick_input)
		_move_knob = _move_base.get_node_or_null("Knob") as ColorRect
		if _move_knob == null:
			_move_knob = _create_knob(_move_base)
		_apply_joystick_style(_move_base)
		_apply_knob_style(_move_base, _move_knob)

	_aim_base = root.find_child("AimStick", true, false) as Control
	if _aim_base == null:
		_aim_base = _create_joystick("AimStick", Vector2(-48.0, -48.0), Control.PRESET_BOTTOM_RIGHT)
		root.add_child(_aim_base)
	_aim_knob = _aim_base.get_node_or_null("Knob") as ColorRect
	if _aim_knob == null:
		_aim_knob = _create_knob(_aim_base)
	_disable_aim_stick()

	var shoot_button := root.find_child("ShootButton", true, false) as CanvasItem
	if shoot_button != null:
		shoot_button.visible = false
	_connect_hold_button(root.find_child("MeleeButton", true, false) as BaseButton, &"melee_attack")
	_connect_pressed_button(root.find_child("ReloadButton", true, false) as BaseButton, Callable(self, "_pulse_action").bind(&"reload"))
	_connect_pressed_button(root.find_child("StealthButton", true, false) as BaseButton, Callable(self, "_toggle_stealth"))
	_connect_pressed_button(root.find_child("InventoryButton", true, false) as BaseButton, Callable(self, "_toggle_inventory"))
	_connect_pressed_button(root.find_child("ActionButton", true, false) as BaseButton, Callable(self, "_primary_interaction"))
	_connect_pressed_button(root.find_child("ScopeButton", true, false) as BaseButton, Callable(self, "_toggle_scope_ready"))
	_connect_pressed_button(root.find_child("SwitchWeaponButton", true, false) as BaseButton, Callable(self, "_cycle_weapon").bind(1))
	_connect_pressed_button(root.find_child("NextWeaponButton", true, false) as BaseButton, Callable(self, "_cycle_weapon").bind(1))
	var pause_button := _ensure_text_button(root, "PauseButton", "Esc", Vector2(-128.0, 24.0), Control.PRESET_TOP_RIGHT)
	_connect_pressed_button(pause_button, Callable(self, "_toggle_pause_menu_mobile"))
	_apply_scene_control_settings(root)
	_ensure_mobile_aim_cursor(root)
	_set_stealth_enabled(false)
	_set_scope_ready(false)

	return _move_base != null and _move_knob != null


func _apply_scene_control_settings(root: Control) -> void:
	var button_size := Vector2(
		clamp(mobile_button_size.x, 64.0, 88.0),
		clamp(mobile_button_size.y, 64.0, 88.0)
	)
	mobile_button_size = button_size
	_configure_move_touch_zone(_move_touch_zone)
	_configure_aim_touch_zone(_aim_touch_zone)

	for child in root.find_children("*", "CanvasItem", true, false):
		var item := child as CanvasItem
		if item == _aim_cursor:
			continue
		item.modulate.a = controls_opacity


func _configure_move_touch_zone(zone: Control) -> void:
	if zone == null:
		return
	zone.mouse_filter = Control.MOUSE_FILTER_STOP
	zone.scale = Vector2.ONE
	zone.anchor_left = 0.0
	zone.anchor_top = 0.0
	zone.anchor_right = clamp(move_touch_zone_right_edge_ratio, 0.1, 0.8)
	zone.anchor_bottom = 1.0
	zone.offset_left = 0.0
	zone.offset_top = 0.0
	zone.offset_right = 0.0
	zone.offset_bottom = 0.0


func _ensure_aim_touch_zone(root: Control) -> void:
	if root == null or not aim_touch_zone_enabled:
		return

	_aim_touch_zone = root.get_node_or_null("AimTouchZone") as Control
	if _aim_touch_zone == null:
		_aim_touch_zone = Control.new()
		_aim_touch_zone.name = "AimTouchZone"
		root.add_child(_aim_touch_zone)

	_configure_aim_touch_zone(_aim_touch_zone)
	root.move_child(_aim_touch_zone, 0)
	if not _aim_touch_zone.gui_input.is_connected(_on_aim_touch_zone_input):
		_aim_touch_zone.gui_input.connect(_on_aim_touch_zone_input)


func _configure_aim_touch_zone(zone: Control) -> void:
	if zone == null:
		return
	zone.mouse_filter = Control.MOUSE_FILTER_STOP
	zone.scale = Vector2.ONE
	zone.anchor_left = max(
		clamp(aim_touch_zone_left_edge_ratio, 0.0, 0.95),
		clamp(move_touch_zone_right_edge_ratio, 0.1, 0.8)
	)
	zone.anchor_top = 0.0
	zone.anchor_right = 1.0
	zone.anchor_bottom = 1.0
	zone.offset_left = 0.0
	zone.offset_top = 0.0
	zone.offset_right = 0.0
	zone.offset_bottom = 0.0


func _ensure_text_button(root: Control, node_name: String, text: String, offset: Vector2, preset: Control.LayoutPreset) -> Button:
	var button := root.find_child(node_name, true, false) as Button
	if button == null:
		button = _create_button(text)
		button.name = node_name
		root.add_child(button)
	button.text = text
	button.custom_minimum_size = Vector2(88.0, 58.0)
	button.size = button.custom_minimum_size
	_place_control(button, offset, preset, button.custom_minimum_size)
	return button


func _ensure_texture_button(root: Control, node_name: String, texture: Texture2D, offset: Vector2, preset: Control.LayoutPreset, tooltip: String = "") -> TextureButton:
	var button := root.find_child(node_name, true, false) as TextureButton
	if button == null:
		button = _create_texture_button(texture, tooltip)
		button.name = node_name
		root.add_child(button)
	else:
		_configure_texture_button(button, texture, tooltip)
	_place_control(button, offset, preset, mobile_button_size)
	return button


func _place_control(control: Control, offset: Vector2, preset: Control.LayoutPreset, target_size: Vector2) -> void:
	if control == null:
		return
	control.scale = Vector2.ONE
	control.custom_minimum_size = target_size
	control.size = target_size
	control.set_anchors_preset(preset)
	control.offset_left = offset.x
	control.offset_top = offset.y
	control.offset_right = offset.x + target_size.x
	control.offset_bottom = offset.y + target_size.y


func _build_layout() -> void:
	var root := Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	_move_touch_zone = Control.new()
	_move_touch_zone.name = "MoveTouchZone"
	_move_touch_zone.mouse_filter = Control.MOUSE_FILTER_STOP
	_move_touch_zone.anchor_left = 0.0
	_move_touch_zone.anchor_top = 0.0
	_move_touch_zone.anchor_right = clamp(move_touch_zone_right_edge_ratio, 0.1, 0.8)
	_move_touch_zone.anchor_bottom = 1.0
	_move_touch_zone.offset_left = 0.0
	_move_touch_zone.offset_top = 0.0
	_move_touch_zone.offset_right = 0.0
	_move_touch_zone.offset_bottom = 0.0
	root.add_child(_move_touch_zone)
	_move_touch_zone.gui_input.connect(_on_move_stick_input)

	_ensure_aim_touch_zone(root)

	_move_base = _create_joystick("MoveStick", Vector2(54.0, -54.0), Control.PRESET_BOTTOM_LEFT)
	root.add_child(_move_base)
	_move_base.gui_input.connect(_on_move_stick_input)
	_move_knob = _create_knob(_move_base)

	var right_column := VBoxContainer.new()
	right_column.name = "ActionButtons"
	right_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_column.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	right_column.offset_left = -112.0
	right_column.offset_top = -198.0
	right_column.offset_right = -24.0
	right_column.offset_bottom = 198.0
	right_column.add_theme_constant_override("separation", 10)
	root.add_child(right_column)

	_add_hold_button(right_column, "Ближ.", &"melee_attack")
	_add_texture_pulse_button(right_column, RELOAD_BUTTON_TEXTURE, Callable(self, "_pulse_action").bind(&"reload"), "Перезарядка")
	_add_hold_button(right_column, "Тихо", &"stealth")

	var top_row := HBoxContainer.new()
	top_row.name = "TopButtons"
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top_row.offset_left = -470.0
	top_row.offset_top = 24.0
	top_row.offset_right = -24.0
	top_row.offset_bottom = 82.0
	top_row.add_theme_constant_override("separation", 10)
	root.add_child(top_row)

	_add_texture_pulse_button(top_row, INVENTORY_BUTTON_TEXTURE, Callable(self, "_toggle_inventory"), "Инвентарь")
	_add_texture_pulse_button(top_row, ACTION_BUTTON_TEXTURE, Callable(self, "_primary_interaction"), "Действие")
	_add_pulse_button(top_row, ">", Callable(self, "_cycle_weapon").bind(1))
	_add_pulse_button(top_row, "Esc", Callable(self, "_toggle_pause_menu_mobile"))


func _create_joystick(node_name: String, offset: Vector2, preset: Control.LayoutPreset) -> Control:
	var stick := Panel.new()
	stick.name = node_name
	stick.custom_minimum_size = Vector2(joystick_radius_px * 2.0, joystick_radius_px * 2.0)
	stick.size = stick.custom_minimum_size
	stick.mouse_filter = Control.MOUSE_FILTER_STOP
	stick.set_anchors_preset(preset)
	stick.offset_left = offset.x
	stick.offset_top = -joystick_radius_px * 2.0 + offset.y
	stick.offset_right = joystick_radius_px * 2.0 + offset.x
	stick.offset_bottom = offset.y
	_apply_joystick_style(stick)
	return stick


func _apply_joystick_style(stick: Control) -> void:
	if stick == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.07, 0.32)
	style.border_color = Color(0.84, 0.9, 0.95, 0.38)
	style.set_border_width_all(2)
	style.set_corner_radius_all(int(joystick_radius_px))
	if stick is Panel:
		(stick as Panel).add_theme_stylebox_override("panel", style)


func _create_knob(parent: Control) -> ColorRect:
	var knob := ColorRect.new()
	knob.name = "Knob"
	parent.add_child(knob)
	_apply_knob_style(parent, knob)
	return knob


func _apply_knob_style(parent: Control, knob: ColorRect) -> void:
	if parent == null or knob == null:
		return
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	knob.color = Color(0.82, 0.88, 0.93, 0.58)
	var knob_size := maxf(joystick_radius_px * 0.54, 36.0)
	knob.size = Vector2(knob_size, knob_size)
	knob.position = (parent.size - knob.size) * 0.5


func _disable_aim_stick() -> void:
	if _aim_base == null:
		return
	_aim_base.visible = false
	_aim_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _aim_knob != null:
		_aim_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _add_hold_button(parent: Control, text: String, action: StringName) -> void:
	var button := _create_button(text)
	parent.add_child(button)
	_connect_hold_button(button, action)


func _add_pulse_button(parent: Control, text: String, callback: Callable) -> void:
	var button := _create_button(text)
	parent.add_child(button)
	_connect_pressed_button(button, callback)


func _add_texture_pulse_button(parent: Control, texture: Texture2D, callback: Callable, tooltip: String = "") -> void:
	var button := _create_texture_button(texture, tooltip)
	parent.add_child(button)
	_connect_pressed_button(button, callback)


func _connect_hold_button(button: BaseButton, action: StringName) -> void:
	if button == null:
		return
	var down_callback := Callable(self, "_press_action").bind(action)
	var up_callback := Callable(self, "_release_action").bind(action)
	if not button.button_down.is_connected(down_callback):
		button.button_down.connect(down_callback)
	if not button.button_up.is_connected(up_callback):
		button.button_up.connect(up_callback)


func _connect_pressed_button(button: BaseButton, callback: Callable) -> void:
	if button == null:
		return
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


func _create_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(88.0, 58.0)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_size_override("font_size", 16)
	return button


func _create_texture_button(texture: Texture2D, tooltip: String = "") -> TextureButton:
	var button := TextureButton.new()
	_configure_texture_button(button, texture, tooltip)
	return button


func _configure_texture_button(button: TextureButton, texture: Texture2D, tooltip: String = "") -> void:
	if button == null:
		return
	button.texture_normal = texture
	button.texture_pressed = texture
	button.texture_hover = texture
	button.texture_disabled = texture
	button.custom_minimum_size = mobile_button_size
	button.size = mobile_button_size
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	if tooltip != "":
		button.tooltip_text = tooltip


func _ensure_mobile_aim_cursor(root: Control) -> void:
	_aim_cursor = root.get_node_or_null("MobileAimCursor") as TextureRect
	if _aim_cursor == null:
		_aim_cursor = TextureRect.new()
		_aim_cursor.name = "MobileAimCursor"
		_aim_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_aim_cursor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_aim_cursor.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_aim_cursor.z_index = 100
		root.add_child(_aim_cursor)
	_aim_cursor.visible = false


func _on_move_stick_input(event: InputEvent) -> void:
	_handle_stick_input(event, true)


func _on_aim_stick_input(event: InputEvent) -> void:
	_handle_stick_input(event, false)


func _on_aim_touch_zone_input(event: InputEvent) -> void:
	if not aim_touch_zone_enabled:
		return
	if not _scope_ready:
		return
	_handle_aim_zone_input(event)


func _event_matches_aim_zone_touch(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).index == _aim_zone_touch_id
	if event is InputEventScreenDrag:
		return (event as InputEventScreenDrag).index == _aim_zone_touch_id
	if event is InputEventMouseButton:
		return _aim_zone_touch_id == -2 and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	if event is InputEventMouseMotion:
		return _aim_zone_touch_id == -2
	return false


func _handle_aim_zone_input(event: InputEvent) -> void:
	var local_position: Vector2 = Vector2.ZERO
	var pressed: bool = false
	var released: bool = false
	var event_id: int = -2

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		event_id = touch.index
		local_position = touch.position
		pressed = touch.pressed
		released = not touch.pressed
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		event_id = drag.index
		local_position = drag.position
		pressed = true
	elif event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		event_id = -2
		local_position = mouse_button.position
		pressed = mouse_button.pressed
		released = not mouse_button.pressed
	elif event is InputEventMouseMotion and _aim_zone_touch_id == -2:
		var mouse_motion := event as InputEventMouseMotion
		event_id = -2
		local_position = mouse_motion.position
		pressed = true
	else:
		return

	if event_id == _move_touch_id:
		return
	if _aim_zone_touch_id == -1 and _is_aim_zone_position_inside_move_zone(local_position):
		return

	get_viewport().set_input_as_handled()

	if pressed and _aim_zone_touch_id == -1:
		_aim_zone_touch_id = event_id
	if event_id != _aim_zone_touch_id:
		return

	if released:
		_aim_zone_touch_id = -1
		_release_aim_zone()
		return

	_update_aim_zone(local_position)


func _handle_stick_input(event: InputEvent, is_move_stick: bool) -> void:
	var current_id: int = _move_touch_id if is_move_stick else _aim_touch_id
	var local_position: Vector2 = Vector2.ZERO
	var pressed: bool = false
	var released: bool = false
	var event_id: int = -2

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		event_id = touch.index
		local_position = touch.position
		pressed = touch.pressed
		released = not touch.pressed
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		event_id = drag.index
		local_position = drag.position
		pressed = true
	elif event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		event_id = -2
		local_position = mouse_button.position
		pressed = mouse_button.pressed
		released = not mouse_button.pressed
	elif event is InputEventMouseMotion and current_id == -2:
		var mouse_motion := event as InputEventMouseMotion
		event_id = -2
		local_position = mouse_motion.position
		pressed = true
	else:
		return

	if event_id == _aim_zone_touch_id:
		return

	get_viewport().set_input_as_handled()

	if pressed and current_id == -1:
		current_id = event_id
		if is_move_stick:
			_move_touch_origin = local_position
	if event_id != current_id:
		return

	if released:
		current_id = -1
		_set_stick_vector(Vector2.ZERO, is_move_stick)
	else:
		var base: Control = _move_base if is_move_stick else _aim_base
		var center: Vector2 = _move_touch_origin if is_move_stick else base.size * 0.5
		var vector: Vector2 = (local_position - center) / maxf(joystick_radius_px, 1.0)
		if vector.length() > 1.0:
			vector = vector.normalized()
		if vector.length() < deadzone:
			vector = Vector2.ZERO
		_set_stick_vector(vector, is_move_stick)

	if is_move_stick:
		_move_touch_id = current_id
	else:
		_aim_touch_id = current_id


func _set_stick_vector(vector: Vector2, is_move_stick: bool) -> void:
	var base: Control = _move_base if is_move_stick else _aim_base
	var knob: ColorRect = _move_knob if is_move_stick else _aim_knob
	if knob != null and base != null:
		knob.position = (base.size - knob.size) * 0.5 + vector * joystick_radius_px * 0.62

	if is_move_stick:
		_move_vector = vector
		_update_move_actions(vector)
	else:
		_aim_vector = vector
		_update_aim(vector)


func _update_move_actions(vector: Vector2) -> void:
	_update_axis_action(&"left", -vector.x)
	_update_axis_action(&"right", vector.x)
	_update_axis_action(&"up", -vector.y)
	_update_axis_action(&"down", vector.y)


func _update_axis_action(action: StringName, value: float) -> void:
	var strength: float = clamp(value, 0.0, 1.0)
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _release_move_actions() -> void:
	Input.action_release(&"left")
	Input.action_release(&"right")
	Input.action_release(&"up")
	Input.action_release(&"down")


func _update_aim(vector: Vector2) -> void:
	var weapon_controller: Node = _get_weapon_controller()
	if vector == Vector2.ZERO:
		Input.action_release(&"shoot")
		if _scope_ready:
			Input.action_press(&"aim")
			_set_mobile_aim_from_direction(_get_player_facing_vector(), aim_distance_px)
		else:
			Input.action_release(&"aim")
			if weapon_controller != null and weapon_controller.has_method("clear_mobile_aim"):
				weapon_controller.call("clear_mobile_aim")
			if weapon_controller != null and weapon_controller.has_method("set_mobile_shoot_active"):
				weapon_controller.call("set_mobile_shoot_active", false)
			if _aim_cursor != null:
				_aim_cursor.visible = false
		return

	Input.action_press(&"aim", vector.length())
	if weapon_controller != null and weapon_controller.has_method("set_mobile_aim_vector"):
		weapon_controller.call("set_mobile_aim_vector", vector.normalized(), aim_distance_px)
	if auto_fire_enabled and vector.length() >= fire_stick_threshold:
		Input.action_press(&"shoot")
	else:
		Input.action_release(&"shoot")

	if _player != null and _player is Node2D:
		var player_node := _player as Node2D
		var screen_position := get_viewport().get_canvas_transform() * (player_node.global_position + vector.normalized() * aim_distance_px)
		_show_mobile_aim_cursor(screen_position)


func _update_aim_zone(local_position: Vector2) -> void:
	var direction := _get_direction_from_aim_zone_position(local_position)
	if direction == Vector2.ZERO:
		return

	_aim_vector = Vector2.ZERO
	_reset_aim_stick_knob()
	Input.action_press(&"aim")
	if aim_touch_zone_fire_enabled:
		Input.action_press(&"shoot")
	else:
		Input.action_release(&"shoot")
	var weapon_controller: Node = _get_weapon_controller()
	if weapon_controller != null and weapon_controller.has_method("set_mobile_shoot_active"):
		weapon_controller.call("set_mobile_shoot_active", aim_touch_zone_fire_enabled)

	var distance := _get_aim_distance_from_zone_position(local_position)
	var screen_position := _aim_touch_zone.get_global_transform() * local_position
	_set_mobile_aim_from_direction(direction, distance, screen_position, true)


func _release_aim_zone() -> void:
	if _aim_vector != Vector2.ZERO:
		_update_aim(_aim_vector)
		return

	Input.action_release(&"shoot")
	var weapon_controller: Node = _get_weapon_controller()
	if weapon_controller != null and weapon_controller.has_method("set_mobile_shoot_active"):
		weapon_controller.call("set_mobile_shoot_active", false)
	if _scope_ready:
		Input.action_press(&"aim")
		_set_mobile_aim_from_direction(_get_player_facing_vector(), aim_distance_px)
	else:
		Input.action_release(&"aim")
		if weapon_controller != null and weapon_controller.has_method("clear_mobile_aim"):
			weapon_controller.call("clear_mobile_aim")
		if _aim_cursor != null:
			_aim_cursor.visible = false


func _reset_aim_stick_knob() -> void:
	if _aim_knob == null or _aim_base == null:
		return
	_aim_knob.position = (_aim_base.size - _aim_knob.size) * 0.5


func _get_direction_from_aim_zone_position(local_position: Vector2) -> Vector2:
	if _player == null or not (_player is Node2D) or _aim_touch_zone == null:
		return Vector2.ZERO

	var player_node := _player as Node2D
	var screen_position := _aim_touch_zone.get_global_transform() * local_position
	var player_screen_position := get_viewport().get_canvas_transform() * player_node.global_position
	var direction := screen_position - player_screen_position
	if direction.length() < deadzone * joystick_radius_px:
		return _get_player_facing_vector()
	return direction.normalized()


func _get_aim_distance_from_zone_position(local_position: Vector2) -> float:
	if _player == null or not (_player is Node2D) or _aim_touch_zone == null:
		return aim_distance_px

	var player_node := _player as Node2D
	var screen_position := _aim_touch_zone.get_global_transform() * local_position
	var player_screen_position := get_viewport().get_canvas_transform() * player_node.global_position
	var distance := player_screen_position.distance_to(screen_position)
	return clamp(distance, aim_distance_px * 0.35, aim_distance_px)


func _is_aim_zone_position_inside_move_zone(local_position: Vector2) -> bool:
	if _aim_touch_zone == null:
		return false

	var screen_position := _aim_touch_zone.get_global_transform() * local_position
	var viewport_width := get_viewport().get_visible_rect().size.x
	if viewport_width <= 0.0:
		return false

	return screen_position.x <= viewport_width * clamp(move_touch_zone_right_edge_ratio, 0.1, 0.8)


func _press_action(action: StringName) -> void:
	Input.action_press(action)


func _release_action(action: StringName) -> void:
	Input.action_release(action)


func _pulse_action(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	Input.action_release(action)


func _toggle_scope_ready() -> void:
	_set_scope_ready(not _scope_ready)


func _set_scope_ready(enabled: bool) -> void:
	_scope_ready = enabled
	var scope_button := get_node_or_null("Root/ScopeButton") as CanvasItem
	if scope_button != null:
		scope_button.modulate = Color(1.0, 1.0, 1.0, controls_opacity) if _scope_ready else Color(1.0, 1.0, 1.0, controls_opacity * 0.72)

	var weapon_controller: Node = _get_weapon_controller()
	if _scope_ready:
		Input.action_press(&"aim")
		_set_mobile_aim_from_direction(_get_player_facing_vector(), aim_distance_px)
	else:
		_aim_zone_touch_id = -1
		if weapon_controller != null and weapon_controller.has_method("set_mobile_shoot_active"):
			weapon_controller.call("set_mobile_shoot_active", false)
		if _aim_vector == Vector2.ZERO:
			Input.action_release(&"aim")
			Input.action_release(&"shoot")
			if weapon_controller != null and weapon_controller.has_method("clear_mobile_aim"):
				weapon_controller.call("clear_mobile_aim")
			if _aim_cursor != null:
				_aim_cursor.visible = false


func _toggle_stealth() -> void:
	_set_stealth_enabled(not _stealth_enabled)


func _set_stealth_enabled(enabled: bool) -> void:
	_stealth_enabled = enabled
	if _stealth_enabled:
		Input.action_press(&"stealth")
	else:
		Input.action_release(&"stealth")

	var stealth_button := get_node_or_null("Root/StealthButton") as CanvasItem
	if stealth_button != null:
		stealth_button.modulate = Color(1.0, 1.0, 1.0, controls_opacity) if _stealth_enabled else Color(1.0, 1.0, 1.0, controls_opacity * 0.72)


func _set_mobile_aim_from_direction(
	direction: Vector2,
	distance: float,
	cursor_screen_position: Vector2 = Vector2.ZERO,
	use_cursor_screen_position: bool = false
) -> void:
	if direction == Vector2.ZERO:
		direction = _get_player_facing_vector()

	var weapon_controller: Node = _get_weapon_controller()
	if weapon_controller != null and weapon_controller.has_method("set_mobile_aim_vector"):
		weapon_controller.call("set_mobile_aim_vector", direction.normalized(), distance)

	if use_cursor_screen_position:
		_show_mobile_aim_cursor(cursor_screen_position)
		return

	if _player != null and _player is Node2D:
		var player_node := _player as Node2D
		var world_position := player_node.global_position + direction.normalized() * maxf(distance, 8.0)
		_show_mobile_aim_cursor(get_viewport().get_canvas_transform() * world_position)


func _show_mobile_aim_cursor(screen_position: Vector2) -> void:
	if _aim_cursor == null:
		var root := get_node_or_null("Root") as Control
		if root != null:
			_ensure_mobile_aim_cursor(root)
	if _aim_cursor == null:
		return

	_update_mobile_aim_cursor_texture()
	var cursor_size := _aim_cursor.custom_minimum_size
	if cursor_size == Vector2.ZERO:
		cursor_size = _aim_cursor.size
	var clamped_position := _clamp_cursor_screen_position(screen_position, cursor_size)
	_aim_cursor.position = clamped_position - cursor_size * 0.5
	_aim_cursor.visible = _scope_ready or _aim_vector != Vector2.ZERO or _aim_zone_touch_id != -1


func _clamp_cursor_screen_position(screen_position: Vector2, cursor_size: Vector2) -> Vector2:
	var viewport_size := get_viewport().get_visible_rect().size
	var margin := maxf(aim_cursor_screen_margin_px, maxf(cursor_size.x, cursor_size.y) * 0.5)
	if viewport_size.x <= margin * 2.0 or viewport_size.y <= margin * 2.0:
		return screen_position

	return Vector2(
		clamp(screen_position.x, margin, viewport_size.x - margin),
		clamp(screen_position.y, margin, viewport_size.y - margin)
	)


func _update_mobile_aim_cursor_texture() -> void:
	if _aim_cursor == null:
		return
	var weapon_controller: Node = _get_weapon_controller()
	if weapon_controller == null:
		return

	var cursor_texture: Texture2D = null
	if weapon_controller.has_method("_get_current_aim_cursor"):
		cursor_texture = weapon_controller.call("_get_current_aim_cursor") as Texture2D
	if cursor_texture == null and "default_cursor" in weapon_controller:
		cursor_texture = weapon_controller.get("default_cursor") as Texture2D
	if cursor_texture == null:
		return

	if _aim_cursor.texture != cursor_texture:
		_aim_cursor.texture = cursor_texture
		var size := cursor_texture.get_size()
		_aim_cursor.custom_minimum_size = size
		_aim_cursor.size = size


func _get_player_facing_vector() -> Vector2:
	if _player != null and "facing_direction" in _player:
		match String(_player.facing_direction):
			"up":
				return Vector2.UP
			"left":
				return Vector2.LEFT
			"right":
				return Vector2.RIGHT
	return Vector2.DOWN


func _toggle_inventory() -> void:
	if _inventory_root == null or not is_instance_valid(_inventory_root):
		_resolve_targets()
	if _inventory_root != null and _inventory_root.has_method("toggle_inventory"):
		_inventory_root.call("toggle_inventory")


func _primary_interaction() -> void:
	if _player == null or not is_instance_valid(_player):
		_resolve_targets()
	if _player != null and _player.has_method("try_primary_interaction"):
		_player.call("try_primary_interaction")


func _secondary_interaction() -> void:
	if _player == null or not is_instance_valid(_player):
		_resolve_targets()
	if _player != null and _player.has_method("try_secondary_interaction"):
		_player.call("try_secondary_interaction")


func _action_interaction() -> void:
	if _player == null or not is_instance_valid(_player):
		_resolve_targets()
	if _player == null:
		return
	if _player.has_method("try_primary_interaction") and bool(_player.call("try_primary_interaction")):
		return
	if _player.has_method("try_secondary_interaction"):
		_player.call("try_secondary_interaction")


func _cycle_weapon(direction: int) -> void:
	var inventory_manager := get_node_or_null("/root/InventoryManager")
	if inventory_manager == null:
		return
	if inventory_manager.has_method("cycle_active_weapon"):
		inventory_manager.call("cycle_active_weapon", direction)
	if _player != null and is_instance_valid(_player):
		if _player.has_method("_refresh_equipment_visuals"):
			_player.call("_refresh_equipment_visuals")
		if _player.has_method("_force_refresh_animation"):
			_player.call("_force_refresh_animation")


func _toggle_pause_menu_mobile() -> void:
	if _player == null or not is_instance_valid(_player):
		_resolve_targets()
	if _player == null:
		return
	if _player.has_method("_toggle_pause_menu"):
		_player.call_deferred("_toggle_pause_menu")
		return
	_pulse_action(&"ui_cancel")


func _get_weapon_controller() -> Node:
	if _player == null or not is_instance_valid(_player):
		return null
	return _player.get_node_or_null("WeaponController")
