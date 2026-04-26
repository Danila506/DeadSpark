@tool
@icon("res://addons/nildevgames_directional_movement_2d/icons/movement_2d_icon.svg")
extends Node
class_name NilDevMovement2D

const DEFAULT_SPEED := 200.0
const KeyboardActions = preload("res://addons/nildevgames_directional_movement_2d/internals/keyboard_actions_2d.gd")

# exported configurations --------------------------------------------------
@export var input_mode := NilDevInputMode.Mode.AUTO:
	get:
		return _input_mode
	set(value):
		if _input_mode == value:
			return
		_input_mode = value
		notify_property_list_changed()
		_update_input_nodes()
		if Engine.is_editor_hint():
			update_configuration_warnings()

@export var auto_enable_touch := true:
	get:
		return _auto_enable_touch
	set(value):
		if _auto_enable_touch == value:
			return
		_auto_enable_touch = value
		notify_property_list_changed()
		_update_input_nodes()
		if Engine.is_editor_hint():
			update_configuration_warnings()

@export var auto_enable_mouse := true:
	get:
		return _auto_enable_mouse
	set(value):
		if _auto_enable_mouse == value:
			return
		_auto_enable_mouse = value
		notify_property_list_changed()
		_update_input_nodes()
		if Engine.is_editor_hint():
			update_configuration_warnings()

@export var auto_enable_keyboard := true:
	get:
		return _auto_enable_keyboard
	set(value):
		if _auto_enable_keyboard == value:
			return
		_auto_enable_keyboard = value
		notify_property_list_changed()
		_update_input_nodes()
		if Engine.is_editor_hint():
			update_configuration_warnings()

@export var auto_ignore_zero_drag := true:
	get:
		return _auto_ignore_zero_drag
	set(value):
		if _auto_ignore_zero_drag == value:
			return
		_auto_ignore_zero_drag = value
		if Engine.is_editor_hint():
			update_configuration_warnings()

@export var speed_mode := NilDevSpeedMode.Mode.UNIFORM:
	get:
		return _speed_mode
	set(value):
		if _speed_mode == value:
			return
		_speed_mode = value
		if _speed_mode == NilDevSpeedMode.Mode.CARDINAL:
			_seed_cardinal_speeds_from_speed()
		else:
			_cardinal_speeds_seeded = false
		notify_property_list_changed()
		if Engine.is_editor_hint():
			update_configuration_warnings()

@export var speed := DEFAULT_SPEED:
	get:
		return _speed
	set(value):
		if _speed == value:
			return
		if not _can_set_uniform_speed():
			return
		_speed = value
		if Engine.is_editor_hint():
			update_configuration_warnings()

@export var cardinal_speed_right := DEFAULT_SPEED:
	get:
		return _cardinal_speed_right
	set(value):
		if _cardinal_speed_right == value:
			return
		if not _can_set_cardinal_speed("cardinal_speed_right"):
			return
		_cardinal_speed_right = value
		if Engine.is_editor_hint():
			update_configuration_warnings()

@export var cardinal_speed_left := DEFAULT_SPEED:
	get:
		return _cardinal_speed_left
	set(value):
		if _cardinal_speed_left == value:
			return
		if not _can_set_cardinal_speed("cardinal_speed_left"):
			return
		_cardinal_speed_left = value
		if Engine.is_editor_hint():
			update_configuration_warnings()

@export var cardinal_speed_up := DEFAULT_SPEED:
	get:
		return _cardinal_speed_up
	set(value):
		if _cardinal_speed_up == value:
			return
		if not _can_set_cardinal_speed("cardinal_speed_up"):
			return
		_cardinal_speed_up = value
		if Engine.is_editor_hint():
			update_configuration_warnings()

@export var cardinal_speed_down := DEFAULT_SPEED:
	get:
		return _cardinal_speed_down
	set(value):
		if _cardinal_speed_down == value:
			return
		if not _can_set_cardinal_speed("cardinal_speed_down"):
			return
		_cardinal_speed_down = value
		if Engine.is_editor_hint():
			update_configuration_warnings()

@export var keyboard_move_right_action: StringName = KeyboardActions.DEFAULT_MOVE_RIGHT_ACTION:
	get:
		return _keyboard_move_right_action
	set(value):
		var normalized_value := KeyboardActions.normalize_action_name(value, KeyboardActions.DEFAULT_MOVE_RIGHT_ACTION)
		if _keyboard_move_right_action == normalized_value:
			return
		_keyboard_move_right_action = normalized_value
		_apply_keyboard_settings()
		if Engine.is_editor_hint():
			update_configuration_warnings()

@export var keyboard_move_left_action: StringName = KeyboardActions.DEFAULT_MOVE_LEFT_ACTION:
	get:
		return _keyboard_move_left_action
	set(value):
		var normalized_value := KeyboardActions.normalize_action_name(value, KeyboardActions.DEFAULT_MOVE_LEFT_ACTION)
		if _keyboard_move_left_action == normalized_value:
			return
		_keyboard_move_left_action = normalized_value
		_apply_keyboard_settings()
		if Engine.is_editor_hint():
			update_configuration_warnings()

@export var keyboard_move_up_action: StringName = KeyboardActions.DEFAULT_MOVE_UP_ACTION:
	get:
		return _keyboard_move_up_action
	set(value):
		var normalized_value := KeyboardActions.normalize_action_name(value, KeyboardActions.DEFAULT_MOVE_UP_ACTION)
		if _keyboard_move_up_action == normalized_value:
			return
		_keyboard_move_up_action = normalized_value
		_apply_keyboard_settings()
		if Engine.is_editor_hint():
			update_configuration_warnings()

@export var keyboard_move_down_action: StringName = KeyboardActions.DEFAULT_MOVE_DOWN_ACTION:
	get:
		return _keyboard_move_down_action
	set(value):
		var normalized_value := KeyboardActions.normalize_action_name(value, KeyboardActions.DEFAULT_MOVE_DOWN_ACTION)
		if _keyboard_move_down_action == normalized_value:
			return
		_keyboard_move_down_action = normalized_value
		_apply_keyboard_settings()
		if Engine.is_editor_hint():
			update_configuration_warnings()

# mouse-specific options
@export var mouse_deadzone := 10.0:
	get:
		return _mouse_deadzone
	set(value):
		if _mouse_deadzone == value:
			return
		_mouse_deadzone = value
		_apply_mouse_settings()
		if Engine.is_editor_hint():
			update_configuration_warnings()

@export var mouse_max_radius := 100.0:
	get:
		return _mouse_max_radius
	set(value):
		if _mouse_max_radius == value:
			return
		_mouse_max_radius = value
		_apply_mouse_settings()
		if Engine.is_editor_hint():
			update_configuration_warnings()

@export var mouse_stop_drag_if_input_stopped := true:
	get:
		return _mouse_stop_drag_if_input_stopped
	set(value):
		if _mouse_stop_drag_if_input_stopped == value:
			return
		_mouse_stop_drag_if_input_stopped = value
		_apply_mouse_settings()
		notify_property_list_changed()
		if Engine.is_editor_hint():
			update_configuration_warnings()

@export var mouse_motion_timeout := 0.1:
	get:
		return _mouse_motion_timeout
	set(value):
		if _mouse_motion_timeout == value:
			return
		_mouse_motion_timeout = value
		_apply_mouse_settings()
		if Engine.is_editor_hint():
			update_configuration_warnings()

# touch-specific options
@export var touch_deadzone := 10.0:
	get:
		return _touch_deadzone
	set(value):
		if _touch_deadzone == value:
			return
		_touch_deadzone = value
		_apply_touch_settings()
		if Engine.is_editor_hint():
			update_configuration_warnings()

@export var touch_max_radius := 100.0:
	get:
		return _touch_max_radius
	set(value):
		if _touch_max_radius == value:
			return
		_touch_max_radius = value
		_apply_touch_settings()
		if Engine.is_editor_hint():
			update_configuration_warnings()

@export var touch_stop_drag_if_input_stopped := true:
	get:
		return _touch_stop_drag_if_input_stopped
	set(value):
		if _touch_stop_drag_if_input_stopped == value:
			return
		_touch_stop_drag_if_input_stopped = value
		_apply_touch_settings()
		notify_property_list_changed()
		if Engine.is_editor_hint():
			update_configuration_warnings()

@export var touch_motion_timeout := 0.1:
	get:
		return _touch_motion_timeout
	set(value):
		if _touch_motion_timeout == value:
			return
		_touch_motion_timeout = value
		_apply_touch_settings()
		if Engine.is_editor_hint():
			update_configuration_warnings()

# internal node references -------------------------------------------------
var _keyboard_node: NilDevKeyboardInput2D
var _mouse_node: NilDevMouseInput2D
var _touch_node: NilDevTouchInput2D

var _input_mode := NilDevInputMode.Mode.AUTO
var _auto_enable_keyboard := true
var _auto_enable_mouse := true
var _auto_enable_touch := true
var _auto_ignore_zero_drag := false
var _speed_mode := NilDevSpeedMode.Mode.UNIFORM
var _speed := DEFAULT_SPEED
var _cardinal_speed_right := DEFAULT_SPEED
var _cardinal_speed_left := DEFAULT_SPEED
var _cardinal_speed_up := DEFAULT_SPEED
var _cardinal_speed_down := DEFAULT_SPEED
var _cardinal_speeds_seeded := false

var _mouse_deadzone := 10.0
var _mouse_max_radius := 100.0
var _mouse_stop_drag_if_input_stopped := true
var _mouse_motion_timeout := 0.1

var _touch_deadzone := 10.0
var _touch_max_radius := 100.0
var _touch_stop_drag_if_input_stopped := true
var _touch_motion_timeout := 0.1

var _velocity := Vector2.ZERO
var _keyboard_move_right_action := KeyboardActions.DEFAULT_MOVE_RIGHT_ACTION
var _keyboard_move_left_action := KeyboardActions.DEFAULT_MOVE_LEFT_ACTION
var _keyboard_move_up_action := KeyboardActions.DEFAULT_MOVE_UP_ACTION
var _keyboard_move_down_action := KeyboardActions.DEFAULT_MOVE_DOWN_ACTION

# movement helpers ---------------------------------------------------------
enum MovementType {
	STOPPED,
	HORIZONTAL,
	VERTICAL,
}

# ---------------------------------------------------------------------------
func _ready() -> void:
	set_process_unhandled_input(false)
	set_process_unhandled_key_input(false)
	set_process(false)
	set_physics_process(false)
	set_process_input(true)
	_update_input_nodes()

# ---------------------------------------------------------------------------
func _apply_mouse_settings() -> void:
	if _mouse_node:
		_mouse_node.deadzone = mouse_deadzone
		_mouse_node.max_radius = mouse_max_radius
		_mouse_node.stop_drag_if_input_stopped = mouse_stop_drag_if_input_stopped
		_mouse_node.motion_timeout = mouse_motion_timeout

func _apply_keyboard_settings() -> void:
	if _keyboard_node:
		_keyboard_node.move_right_action = keyboard_move_right_action
		_keyboard_node.move_left_action = keyboard_move_left_action
		_keyboard_node.move_up_action = keyboard_move_up_action
		_keyboard_node.move_down_action = keyboard_move_down_action

func _apply_touch_settings() -> void:
	if _touch_node:
		_touch_node.deadzone = touch_deadzone
		_touch_node.max_radius = touch_max_radius
		_touch_node.stop_drag_if_input_stopped = touch_stop_drag_if_input_stopped
		_touch_node.motion_timeout = touch_motion_timeout

func _free_keyboard_node() -> void:
	if _keyboard_node and is_instance_valid(_keyboard_node):
		_keyboard_node.queue_free()
	_keyboard_node = null

func _free_mouse_node() -> void:
	if _mouse_node and is_instance_valid(_mouse_node):
		_mouse_node.queue_free()
	_mouse_node = null

func _free_touch_node() -> void:
	if _touch_node and is_instance_valid(_touch_node):
		_touch_node.queue_free()
	_touch_node = null

func _enabled_auto_input_count() -> int:
	var enabled_count := 0
	if auto_enable_keyboard:
		enabled_count += 1
	if auto_enable_mouse:
		enabled_count += 1
	if auto_enable_touch:
		enabled_count += 1
	return enabled_count

func _can_set_uniform_speed() -> bool:
	if speed_mode == NilDevSpeedMode.Mode.UNIFORM:
		return true
	# Assert is used here instead of push_error + return false because setting speed is more likely to be done programmatically, and this way it will be more obvious to developers that they are doing something wrong. Editor warnings are more for designers who may not see assertion errors in the console.
	assert(speed_mode == NilDevSpeedMode.Mode.CARDINAL, "Invalid speed mode")
	push_error("Cannot set 'speed' while speed_mode is CARDINAL. Use cardinal_speed_right, cardinal_speed_left, cardinal_speed_up, and cardinal_speed_down instead.")
	return false

func _can_set_cardinal_speed(property_name: String) -> bool:
	if speed_mode == NilDevSpeedMode.Mode.CARDINAL:
		return true
	# Assert is used here instead of push_error + return false because setting cardinal speeds is more likely to be done programmatically, and this way it will be more obvious to developers that they are doing something wrong. Editor warnings are more for designers who may not see assertion errors in the console.
	assert(speed_mode == NilDevSpeedMode.Mode.UNIFORM, "Invalid speed mode")
	push_error("Cannot set '%s' while speed_mode is UNIFORM. Use speed instead." % property_name)
	return false

# ---------------------------------------------------------------------------
func _ensure_keyboard_node() -> void:
	if not _keyboard_node or not is_instance_valid(_keyboard_node) or _keyboard_node.is_queued_for_deletion():
		_keyboard_node = NilDevKeyboardInput2D.new()
		_keyboard_node.name = "KeyboardInput"
		_apply_keyboard_settings()
		add_child(_keyboard_node)

func _ensure_mouse_node() -> void:
	if not _mouse_node or not is_instance_valid(_mouse_node) or _mouse_node.is_queued_for_deletion():
		_mouse_node = NilDevMouseInput2D.new()
		_mouse_node.name = "MouseInput"
		_apply_mouse_settings()
		add_child(_mouse_node)

func _ensure_touch_node() -> void:
	if not _touch_node or not is_instance_valid(_touch_node) or _touch_node.is_queued_for_deletion():
		_touch_node = NilDevTouchInput2D.new()
		_touch_node.name = "TouchInput"
		_apply_touch_settings()
		add_child(_touch_node)

func _get_auto_drag_input_vector(node: NilDevDragBasedInput2D) -> Vector2:
	if not node or not is_instance_valid(node) or not node.is_pressed:
		return Vector2.ZERO

	var input_vector := node.get_input_vector()
	if auto_ignore_zero_drag and input_vector == Vector2.ZERO:
		return Vector2.ZERO

	return input_vector

func _update_input_nodes() -> void:
	if Engine.is_editor_hint():
		return

	match input_mode:
		NilDevInputMode.Mode.KEYBOARD:
			_ensure_keyboard_node()
			_free_mouse_node()
			_free_touch_node()
		NilDevInputMode.Mode.MOUSE:
			_ensure_mouse_node()
			_free_keyboard_node()
			_free_touch_node()
		NilDevInputMode.Mode.TOUCH:
			_ensure_touch_node()
			_free_keyboard_node()
			_free_mouse_node()
		NilDevInputMode.Mode.AUTO:
			if auto_enable_keyboard:
				_ensure_keyboard_node()
			else:
				_free_keyboard_node()
			if auto_enable_mouse:
				_ensure_mouse_node()
			else:
				_free_mouse_node()
			if auto_enable_touch:
				_ensure_touch_node()
			else:
				_free_touch_node()

# ---------------------------------------------------------------------------

func get_input_vector() -> Vector2:
	match input_mode:
		NilDevInputMode.Mode.KEYBOARD:
			if _keyboard_node and is_instance_valid(_keyboard_node):
				return _keyboard_node.get_input_vector()
			return Vector2.ZERO
		NilDevInputMode.Mode.MOUSE:
			if _mouse_node and is_instance_valid(_mouse_node):
				return _mouse_node.get_input_vector()
			return Vector2.ZERO
		NilDevInputMode.Mode.TOUCH:
			if _touch_node and is_instance_valid(_touch_node):
				return _touch_node.get_input_vector()
			return Vector2.ZERO
		NilDevInputMode.Mode.AUTO:
			# priority: touch > mouse > keyboard; first non-zero wins
			if auto_enable_touch:
				var touch_vector := _get_auto_drag_input_vector(_touch_node)
				if touch_vector != Vector2.ZERO or (_touch_node and is_instance_valid(_touch_node) and _touch_node.is_pressed and not auto_ignore_zero_drag):
					return touch_vector
			if auto_enable_mouse:
				var mouse_vector := _get_auto_drag_input_vector(_mouse_node)
				if mouse_vector != Vector2.ZERO or (_mouse_node and is_instance_valid(_mouse_node) and _mouse_node.is_pressed and not auto_ignore_zero_drag):
					return mouse_vector
			if auto_enable_keyboard and _keyboard_node and is_instance_valid(_keyboard_node) and _keyboard_node.is_pressed:
				return _keyboard_node.get_input_vector()
	return Vector2.ZERO

func calculate_movement(delta: float) -> Vector2:
	_velocity = calculate_velocity()
	return _velocity * delta

func calculate_velocity() -> Vector2:
	_velocity = _calculate_velocity(get_input_vector())
	return _velocity

func _calculate_velocity(input_vector: Vector2) -> Vector2:
	if input_vector == Vector2.ZERO:
		return Vector2.ZERO
	if speed_mode == NilDevSpeedMode.Mode.CARDINAL:
		return _calculate_cardinal_velocity(input_vector)
	return input_vector * speed

func _calculate_cardinal_velocity(input_vector: Vector2) -> Vector2:
	var horizontal_velocity := 0.0
	if input_vector.x > 0.0:
		horizontal_velocity = input_vector.x * cardinal_speed_right
	elif input_vector.x < 0.0:
		horizontal_velocity = input_vector.x * cardinal_speed_left

	var vertical_velocity := 0.0
	if input_vector.y > 0.0:
		vertical_velocity = input_vector.y * cardinal_speed_down
	elif input_vector.y < 0.0:
		vertical_velocity = input_vector.y * cardinal_speed_up

	return Vector2(horizontal_velocity, vertical_velocity)

func _seed_cardinal_speeds_from_speed() -> void:
	if _cardinal_speeds_seeded:
		return
	if is_equal_approx(_cardinal_speed_right, DEFAULT_SPEED):
		_cardinal_speed_right = _speed
	if is_equal_approx(_cardinal_speed_left, DEFAULT_SPEED):
		_cardinal_speed_left = _speed
	if is_equal_approx(_cardinal_speed_up, DEFAULT_SPEED):
		_cardinal_speed_up = _speed
	if is_equal_approx(_cardinal_speed_down, DEFAULT_SPEED):
		_cardinal_speed_down = _speed
	_cardinal_speeds_seeded = true

var velocity: Vector2:
	get:
		return _velocity

var movement_type: MovementType:
	get:
		if _velocity == Vector2.ZERO:
			return MovementType.STOPPED
		if abs(_velocity.x) > abs(_velocity.y):
			return MovementType.HORIZONTAL
		return MovementType.VERTICAL

var moving_left: bool:
	get:
		return _velocity.x < 0

var moving_right: bool:
	get:
		return _velocity.x > 0

var moving_up: bool:
	get:
		return _velocity.y < 0

var moving_down: bool:
	get:
		return _velocity.y > 0


# ---------------------------------------------------------------------------
func _validate_property(property: Dictionary) -> void:
	if property.name == "speed":
		if speed_mode == NilDevSpeedMode.Mode.CARDINAL:
			property.usage = PROPERTY_USAGE_NO_EDITOR
		return
	elif property.name.begins_with("cardinal_speed_"):
		if speed_mode == NilDevSpeedMode.Mode.UNIFORM:
			property.usage = PROPERTY_USAGE_NO_EDITOR
		return

	var mode := input_mode
	if property.name.begins_with("auto_enable_"):
		if mode != NilDevInputMode.Mode.AUTO:
			property.usage = PROPERTY_USAGE_NO_EDITOR
		return
	if property.name == "auto_ignore_zero_drag":
		if mode != NilDevInputMode.Mode.AUTO:
			property.usage = PROPERTY_USAGE_NO_EDITOR
		return
	if property.name.begins_with("keyboard_"):
		if mode == NilDevInputMode.Mode.MOUSE or mode == NilDevInputMode.Mode.TOUCH:
			property.usage = PROPERTY_USAGE_NO_EDITOR
			return
	elif property.name.begins_with("mouse_"):
		if mode == NilDevInputMode.Mode.TOUCH or mode == NilDevInputMode.Mode.KEYBOARD:
			property.usage = PROPERTY_USAGE_NO_EDITOR
			return
		if property.name == "mouse_motion_timeout" and not mouse_stop_drag_if_input_stopped:
			property.usage = PROPERTY_USAGE_NO_EDITOR
	elif property.name.begins_with("touch_"):
		if mode == NilDevInputMode.Mode.MOUSE or mode == NilDevInputMode.Mode.KEYBOARD:
			property.usage = PROPERTY_USAGE_NO_EDITOR
			return
		if property.name == "touch_motion_timeout" and not touch_stop_drag_if_input_stopped:
			property.usage = PROPERTY_USAGE_NO_EDITOR

# ---------------------------------------------------------------------------
func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()

	if speed_mode == NilDevSpeedMode.Mode.UNIFORM and speed <= 0:
		w.append("Speed must be greater than zero.")
	elif speed_mode == NilDevSpeedMode.Mode.CARDINAL:
		if cardinal_speed_right <= 0:
			w.append("Cardinal right speed must be greater than zero.")
		if cardinal_speed_left <= 0:
			w.append("Cardinal left speed must be greater than zero.")
		if cardinal_speed_up <= 0:
			w.append("Cardinal up speed must be greater than zero.")
		if cardinal_speed_down <= 0:
			w.append("Cardinal down speed must be greater than zero.")

	if input_mode == NilDevInputMode.Mode.AUTO and _enabled_auto_input_count() < 2:
		w.append("AUTO mode should have at least two enabled input methods. Select a dedicated input mode if you only need one method.")

	if (input_mode == NilDevInputMode.Mode.KEYBOARD or (input_mode == NilDevInputMode.Mode.AUTO and auto_enable_keyboard)) and KeyboardActions.uses_custom_actions(_get_keyboard_actions()):
		w.append("Custom keyboard action names are created at runtime only. Add them to Project Settings -> Input Map if you want them persisted.")

	if input_mode == NilDevInputMode.Mode.KEYBOARD:
		return w

	if input_mode == NilDevInputMode.Mode.MOUSE or (input_mode == NilDevInputMode.Mode.AUTO and auto_enable_mouse):
		if mouse_deadzone < 0.0:
			w.append("Mouse deadzone cannot be negative.")
		if mouse_max_radius < 10:
			w.append("Mouse max radius should be at least 10.")
		if mouse_motion_timeout < 0.1:
		   w.append("Mouse motion timeout should be at least 0.1 seconds.")

	if input_mode == NilDevInputMode.Mode.TOUCH or (input_mode == NilDevInputMode.Mode.AUTO and auto_enable_touch):
		if touch_deadzone < 0.0:
			w.append("Touch deadzone cannot be negative.")
		if touch_max_radius < 10:
			w.append("Touch max radius should be at least 10.")
		if touch_motion_timeout < 0.1:
			w.append("Touch motion timeout should be at least 0.1 seconds.")
	return w

# ---------------------------------------------------------------------------

func _get_keyboard_actions() -> Dictionary:
	return KeyboardActions.build_configured_actions(
		keyboard_move_right_action,
		keyboard_move_left_action,
		keyboard_move_up_action,
		keyboard_move_down_action
	)
