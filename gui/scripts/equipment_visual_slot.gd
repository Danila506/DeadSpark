extends AnimatedSprite2D
class_name EquipmentVisualSlot

@export var item_type: ItemData.ItemType

var _scope_overlay: Sprite2D = null


func _ready() -> void:
	_ensure_scope_overlay()


func set_scope_overlay(texture: Texture2D, overlay_offset: Vector2, scale_value: Vector2, rotation_deg: float, visible_state: bool) -> void:
	_ensure_scope_overlay()
	if _scope_overlay == null:
		return

	if not visible_state or texture == null:
		_scope_overlay.visible = false
		return

	_scope_overlay.texture = texture
	_scope_overlay.position = overlay_offset
	_scope_overlay.scale = scale_value
	_scope_overlay.rotation_degrees = rotation_deg
	_scope_overlay.visible = true


func clear_scope_overlay() -> void:
	if _scope_overlay != null:
		_scope_overlay.visible = false


func _ensure_scope_overlay() -> void:
	if _scope_overlay != null:
		return

	_scope_overlay = get_node_or_null("ScopeOverlay") as Sprite2D
	if _scope_overlay != null:
		return

	_scope_overlay = Sprite2D.new()
	_scope_overlay.name = "ScopeOverlay"
	_scope_overlay.z_index = 5
	_scope_overlay.centered = true
	_scope_overlay.visible = false
	add_child(_scope_overlay)
