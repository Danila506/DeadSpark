@tool
@icon("res://addons/nildevgames_directional_movement_2d/icons/touch_input_2d_icon.svg")
extends NilDevDragBasedInput2D
class_name NilDevTouchInput2D

func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed:
            _start_drag(event.position)
        else:
            _stop_drag()

    elif event is InputEventScreenDrag and _dragging:
        _update_drag(event.position)
