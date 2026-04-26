@tool
@icon("res://addons/nildevgames_directional_movement_2d/icons/mouse_input_2d_icon.svg")
extends NilDevDragBasedInput2D
class_name NilDevMouseInput2D

func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            _start_drag(event.position)
        else:
            _stop_drag()

    elif event is InputEventMouseMotion and _dragging:
        _update_drag(event.position)