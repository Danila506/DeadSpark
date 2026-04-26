@icon("res://addons/nildevgames_directional_movement_2d/icons/keyboard_input_2d_icon.svg")
class_name NilDevKeyboardInput2D
extends NilDevDirectionalInput2D

const KeyboardActions = preload("res://addons/nildevgames_directional_movement_2d/internals/keyboard_actions_2d.gd")

@export var move_right_action: StringName = KeyboardActions.DEFAULT_MOVE_RIGHT_ACTION:
	get:
		return _move_right_action
	set(value):
		var normalized_value := KeyboardActions.normalize_action_name(value, KeyboardActions.DEFAULT_MOVE_RIGHT_ACTION)
		if _move_right_action == normalized_value:
			return
		_move_right_action = normalized_value
		if is_inside_tree() and not Engine.is_editor_hint():
			KeyboardActions.ensure_runtime_action(_move_right_action, "right")

@export var move_left_action: StringName = KeyboardActions.DEFAULT_MOVE_LEFT_ACTION:
	get:
		return _move_left_action
	set(value):
		var normalized_value := KeyboardActions.normalize_action_name(value, KeyboardActions.DEFAULT_MOVE_LEFT_ACTION)
		if _move_left_action == normalized_value:
			return
		_move_left_action = normalized_value
		if is_inside_tree() and not Engine.is_editor_hint():
			KeyboardActions.ensure_runtime_action(_move_left_action, "left")

@export var move_up_action: StringName = KeyboardActions.DEFAULT_MOVE_UP_ACTION:
	get:
		return _move_up_action
	set(value):
		var normalized_value := KeyboardActions.normalize_action_name(value, KeyboardActions.DEFAULT_MOVE_UP_ACTION)
		if _move_up_action == normalized_value:
			return
		_move_up_action = normalized_value
		if is_inside_tree() and not Engine.is_editor_hint():
			KeyboardActions.ensure_runtime_action(_move_up_action, "up")

@export var move_down_action: StringName = KeyboardActions.DEFAULT_MOVE_DOWN_ACTION:
	get:
		return _move_down_action
	set(value):
		var normalized_value := KeyboardActions.normalize_action_name(value, KeyboardActions.DEFAULT_MOVE_DOWN_ACTION)
		if _move_down_action == normalized_value:
			return
		_move_down_action = normalized_value
		if is_inside_tree() and not Engine.is_editor_hint():
			KeyboardActions.ensure_runtime_action(_move_down_action, "down")

var _move_right_action := KeyboardActions.DEFAULT_MOVE_RIGHT_ACTION
var _move_left_action := KeyboardActions.DEFAULT_MOVE_LEFT_ACTION
var _move_up_action := KeyboardActions.DEFAULT_MOVE_UP_ACTION
var _move_down_action := KeyboardActions.DEFAULT_MOVE_DOWN_ACTION

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_DISABLED
	if not Engine.is_editor_hint():
		KeyboardActions.ensure_runtime_actions(_get_configured_actions())

func get_input_vector() -> Vector2:
	var v := Vector2.ZERO

	if Input.is_action_pressed(move_right_action):
		v.x += 1
	if Input.is_action_pressed(move_left_action):
		v.x -= 1
	if Input.is_action_pressed(move_down_action):
		v.y += 1
	if Input.is_action_pressed(move_up_action):
		v.y -= 1

	return v.normalized()

func _is_pressed() -> bool:
	return Input.is_action_pressed(move_right_action) or Input.is_action_pressed(move_left_action) or Input.is_action_pressed(move_down_action) or Input.is_action_pressed(move_up_action)


func _get_configured_actions() -> Dictionary:
	return KeyboardActions.build_configured_actions(
		move_right_action,
		move_left_action,
		move_up_action,
		move_down_action
	)
