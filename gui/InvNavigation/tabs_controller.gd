extends Control

@export var buttons: Array[Control] = []

func _ready():
	for button in buttons:
		button.z_as_relative = false
		button.pressed.connect(_on_tab_pressed.bind(button))


func _on_tab_pressed(active_button: Control) -> void:
	for button in buttons:
		button.z_index = 0
	
	active_button.z_index = 1
