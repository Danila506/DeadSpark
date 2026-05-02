extends Node2D

@export var level_scene: PackedScene = preload("res://level.tscn")

@onready var preview_root: Node2D = $PreviewRoot
@onready var seed_edit: LineEdit = $CanvasLayer/PanelContainer/HBoxContainer/SeedEdit
@onready var regenerate_button: Button = $CanvasLayer/PanelContainer/HBoxContainer/RegenerateButton

var _level_instance: Node


func _ready() -> void:
	if seed_edit != null:
		seed_edit.text = str(Time.get_unix_time_from_system())
	if regenerate_button != null and not regenerate_button.pressed.is_connected(_regenerate):
		regenerate_button.pressed.connect(_regenerate)
	_regenerate()


func _regenerate() -> void:
	if level_scene == null or preview_root == null:
		return

	if _level_instance != null and is_instance_valid(_level_instance):
		preview_root.remove_child(_level_instance)
		_level_instance.queue_free()
		_level_instance = null

	var seed := _parse_seed()
	if GameSaveManager != null and GameSaveManager.has_method("set_world_generation_seed"):
		GameSaveManager.set_world_generation_seed(seed)

	_level_instance = level_scene.instantiate()
	preview_root.add_child(_level_instance)


func _parse_seed() -> int:
	if seed_edit == null:
		return int(Time.get_unix_time_from_system())
	var raw := seed_edit.text.strip_edges()
	if raw.is_valid_int():
		return int(raw)
	return abs(hash(raw))
