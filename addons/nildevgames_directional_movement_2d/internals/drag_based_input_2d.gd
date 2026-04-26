@abstract
extends NilDevDirectionalInput2D
class_name NilDevDragBasedInput2D

@export var deadzone := 10.0:
    get:
        return _deadzone
    set(value):
        if _deadzone == value:
            return

        _deadzone = value
        
        if Engine.is_editor_hint():
            update_configuration_warnings()
@export var max_radius := 100.0:
    get:
        return _max_radius
    set(value):
        if _max_radius == value:
            return

        _max_radius = value
        
        if Engine.is_editor_hint():
            update_configuration_warnings()
@export var stop_drag_if_input_stopped := true:
    get:
        return _stop_drag_if_input_stopped
    set(value):
        if _stop_drag_if_input_stopped == value:
            return

        _stop_drag_if_input_stopped = value
        notify_property_list_changed()
@export var motion_timeout := 0.1:
    get:
        return _motion_timeout
    set(value):
        if _motion_timeout == value:
            return

        _motion_timeout = value

        if Engine.is_editor_hint():
            update_configuration_warnings()

var _dragging := false
var _paused := false
var _current_input_vector := Vector2.ZERO
var _drag_origin := Vector2.ZERO
# Initialize to -1 to indicate that there has been no motion yet. This will be used to determine if the mouse has stopped moving.
var _last_motion_time := -1.0

var _deadzone := 10.0
var _max_radius := 100.0
var _stop_drag_if_input_stopped := true
var _motion_timeout := 0.1

func _ready() -> void:
    set_process_unhandled_input(false)
    set_process_unhandled_key_input(false)
    set_process(false)
    set_physics_process(false)
    set_process_input(true)

func _physics_process(delta: float) -> void:
    if _stop_drag_if_input_stopped and _dragging and _last_motion_time != -1.0:
        var current_time = Time.get_ticks_msec() / 1000.0

        if current_time - _last_motion_time > _motion_timeout:
            _pause()

func get_input_vector() -> Vector2:
    return _current_input_vector

func _update_drag(position: Vector2) -> void:
    if _paused:
        _resume(position)
    
    var drag_vector = position - _drag_origin
    var distance = drag_vector.length()

    if distance < _deadzone:
        _current_input_vector = drag_vector.normalized() * (distance / _deadzone) if distance > 0 else Vector2.ZERO
    else:
        var strength = min(distance, _max_radius) / _max_radius
        # drag_vector / distance gives us the normalized direction, multiplying by strength gives us the final input vector
        _current_input_vector = drag_vector.normalized() * strength
        _last_motion_time = Time.get_ticks_msec() / 1000.0

func _start_drag(position: Vector2) -> void:
    _drag_origin = position
    _dragging = true
    set_physics_process(_stop_drag_if_input_stopped)

func _stop_drag() -> void:
    _dragging = false
    _current_input_vector = Vector2.ZERO
    set_physics_process(false)
    _last_motion_time = -1.0

func _pause() -> void:
    _paused = true
    _current_input_vector = Vector2.ZERO
    set_physics_process(false)

func _resume(position: Vector2) -> void:
    _paused = false
    _drag_origin = position
    _last_motion_time = Time.get_ticks_msec() / 1000.0
    set_physics_process(stop_drag_if_input_stopped)

func _is_pressed() -> bool:
    return _dragging and not _paused

# Editor validation
func _get_configuration_warnings() -> PackedStringArray:
    var warnings := PackedStringArray()

    if _deadzone < 0.0:
        warnings.append("Deadzone cannot be negative.")
    if _max_radius < 10:
        warnings.append("Max radius should be at least 10 to allow for meaningful input.")
    if _motion_timeout < 0.1:
        warnings.append("Motion timeout should be at least 0.1 seconds.")

    return warnings

func _validate_property(property: Dictionary) -> void:
    if property.name == "motion_timeout" and not stop_drag_if_input_stopped:
        property.usage = PROPERTY_USAGE_NO_EDITOR