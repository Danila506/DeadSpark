@abstract
extends Node
class_name NilDevDirectionalInput2D

var is_pressed := false:
    get:
        return _is_pressed()

@abstract
func get_input_vector() -> Vector2

@abstract
func _is_pressed() -> bool