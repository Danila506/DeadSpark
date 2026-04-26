@tool
extends RefCounted
class_name NilDevKeyboardActions2D

const DEFAULT_MOVE_RIGHT_ACTION: StringName = &"nildevgames_move_right"
const DEFAULT_MOVE_LEFT_ACTION: StringName = &"nildevgames_move_left"
const DEFAULT_MOVE_UP_ACTION: StringName = &"nildevgames_move_up"
const DEFAULT_MOVE_DOWN_ACTION: StringName = &"nildevgames_move_down"

const _ACTION_DIRECTIONS := [&"right", &"left", &"up", &"down"]
const _ACTION_DEADZONE := 0.2


static func build_configured_actions(
    move_right_action: StringName,
    move_left_action: StringName,
    move_up_action: StringName,
    move_down_action: StringName
) -> Dictionary:
    return {
        &"right": normalize_action_name(move_right_action, DEFAULT_MOVE_RIGHT_ACTION),
        &"left": normalize_action_name(move_left_action, DEFAULT_MOVE_LEFT_ACTION),
        &"up": normalize_action_name(move_up_action, DEFAULT_MOVE_UP_ACTION),
        &"down": normalize_action_name(move_down_action, DEFAULT_MOVE_DOWN_ACTION),
    }


static func normalize_action_name(action_name: StringName, fallback_action_name: StringName) -> StringName:
    var normalized_action_name := String(action_name).strip_edges()
    if normalized_action_name.is_empty():
        return fallback_action_name
    return StringName(normalized_action_name)


static func ensure_runtime_actions(configured_actions: Dictionary) -> void:
    for direction in _ACTION_DIRECTIONS:
        ensure_runtime_action(configured_actions.get(direction, get_default_action_name(direction)), direction)


static func ensure_runtime_action(action_name: StringName, direction: String) -> bool:
    var normalized_action_name := normalize_action_name(action_name, get_default_action_name(direction))
    if InputMap.has_action(normalized_action_name):
        return false

    InputMap.add_action(normalized_action_name, _ACTION_DEADZONE)
    for event in create_default_events(direction):
        InputMap.action_add_event(normalized_action_name, event)
    return true


static func set_missing_default_project_actions() -> bool:
    var changed := false

    for direction in _ACTION_DIRECTIONS:
        var action_name := get_default_action_name(direction)
        var setting_name := get_project_setting_name(action_name)
        if ProjectSettings.has_setting(setting_name):
            continue

        ProjectSettings.set_setting(setting_name, create_action_setting(direction))
        changed = true

    return changed


static func uses_custom_actions(configured_actions: Dictionary) -> bool:
    return (
        configured_actions.get(&"right", DEFAULT_MOVE_RIGHT_ACTION) != DEFAULT_MOVE_RIGHT_ACTION
        or configured_actions.get(&"left", DEFAULT_MOVE_LEFT_ACTION) != DEFAULT_MOVE_LEFT_ACTION
        or configured_actions.get(&"up", DEFAULT_MOVE_UP_ACTION) != DEFAULT_MOVE_UP_ACTION
        or configured_actions.get(&"down", DEFAULT_MOVE_DOWN_ACTION) != DEFAULT_MOVE_DOWN_ACTION
    )


static func get_default_action_name(direction: String) -> StringName:
    match direction:
        &"right":
            return DEFAULT_MOVE_RIGHT_ACTION
        &"left":
            return DEFAULT_MOVE_LEFT_ACTION
        &"up":
            return DEFAULT_MOVE_UP_ACTION
        &"down":
            return DEFAULT_MOVE_DOWN_ACTION
    return &""


static func get_project_setting_name(action_name: StringName) -> String:
    return "input/%s" % String(action_name)


static func create_action_setting(direction: String) -> Dictionary:
    return {
        "deadzone": _ACTION_DEADZONE,
        "events": create_default_events(direction),
    }


static func create_default_events(direction: String) -> Array[InputEvent]:
    var events: Array[InputEvent] = []

    for key_code in _get_default_key_codes(direction):
        var event := InputEventKey.new()
        event.physical_keycode = key_code
        events.append(event)

    return events


static func _get_default_key_codes(direction: String) -> Array:
    match direction:
        &"right":
            return [KEY_D, KEY_RIGHT]
        &"left":
            return [KEY_A, KEY_LEFT]
        &"up":
            return [KEY_W, KEY_UP]
        &"down":
            return [KEY_S, KEY_DOWN]
    return []