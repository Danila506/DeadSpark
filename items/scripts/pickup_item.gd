extends Area2D

@export var item_data: ItemData
@export var world_sprite_scale: Vector2 = Vector2(1, 1)

const BELOW_PLAYER_Z_INDEX: int = -1

var player_in_range: bool = false

@onready var sprite: Sprite2D = $Sprite2D

var prompt_label: Label = null


func _ready() -> void:
	add_to_group("world_pickup")
	_apply_render_order()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_ensure_prompt_label()

	if item_data != null:
		sprite.texture = item_data.world_icon
		sprite.scale = world_sprite_scale * max(item_data.world_icon_scale, 0.1)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	player_in_range = true
	NearbyItemsManager.add_item(self)
	_update_prompt_visibility()


func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	player_in_range = false
	NearbyItemsManager.remove_item(self)
	_update_prompt_visibility()


func remove_from_world() -> void:
	NearbyItemsManager.remove_item(self)
	queue_free()
	
func setup_from_item_data(data: ItemData) -> void:
	item_data = data

	if sprite == null:
		sprite = $Sprite2D

	_apply_render_order()

	if item_data != null:
		sprite.texture = item_data.world_icon
		sprite.scale = world_sprite_scale * max(item_data.world_icon_scale, 0.1)
	_update_prompt_visibility()


func _apply_render_order() -> void:
	z_index = BELOW_PLAYER_Z_INDEX


func _ensure_prompt_label() -> void:
	if prompt_label != null:
		return

	prompt_label = Label.new()
	prompt_label.text = _get_prompt_text()
	prompt_label.position = Vector2(-10.0, -20.0)
	prompt_label.visible = false
	prompt_label.z_index = 10
	prompt_label.add_theme_color_override("font_color", Color(0.0, 0.35, 0.0))
	prompt_label.add_theme_font_size_override("font_size", 9)
	add_child(prompt_label)


func _update_prompt_visibility() -> void:
	if prompt_label == null:
		return

	prompt_label.text = _get_prompt_text()
	prompt_label.visible = player_in_range


func _get_prompt_text() -> String:
	if item_data != null and not item_data.item_name.strip_edges().is_empty():
		return item_data.item_name
	return "Предмет"
