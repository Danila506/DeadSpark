extends Control
class_name NPCDialoguePanel

const ICON_ATLAS: Texture2D = preload("res://gui/NPC_Dialogue/NPC_dialogue_icons.png")
const RELATION_REGIONS: Array[Rect2] = [
	Rect2(79, 157, 149, 146),
	Rect2(287, 157, 146, 146),
	Rect2(492, 157, 144, 146),
	Rect2(694, 157, 144, 146),
	Rect2(898, 157, 147, 146),
]
const ICON_REGION_QUESTION := Rect2(551, 394, 122, 156)
const ICON_REGION_TRADE := Rect2(1017, 394, 161, 156)
const ICON_REGION_EXIT := Rect2(1947, 394, 137, 156)

signal action_requested(action: StringName)
signal dialogue_closed

@onready var title_label: Label = %TitleLabel
@onready var role_label: Label = %RoleLabel
@onready var body_label: Label = %BodyLabel
@onready var stock_label: Label = %StockLabel
@onready var relation_bar: ProgressBar = %RelationBar
@onready var relation_icon: TextureRect = %RelationIcon
@onready var rumor_button: TextureButton = %RumorButton
@onready var trade_button: TextureButton = %TradeButton
@onready var close_button: TextureButton = %CloseButton
@onready var rumor_icon: TextureRect = $PanelRoot/RumorButton/Icon
@onready var trade_icon: TextureRect = $PanelRoot/TradeButton/Icon
@onready var close_icon: TextureRect = $PanelRoot/CloseButton/Icon
@onready var panel_root: Control = %PanelRoot


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	rumor_button.pressed.connect(_request_action.bind(&"rumor"))
	trade_button.pressed.connect(_request_action.bind(&"trade"))
	close_button.pressed.connect(close_dialogue)
	rumor_icon.texture = _create_atlas_texture(ICON_REGION_QUESTION)
	trade_icon.texture = _create_atlas_texture(ICON_REGION_TRADE)
	close_icon.texture = _create_atlas_texture(ICON_REGION_EXIT)
	get_viewport().size_changed.connect(_update_panel_scale)
	_update_panel_scale()


func show_payload(payload: Dictionary) -> void:
	_set_identity(String(payload.get("display_name", "Странник")), String(payload.get("role", "")))
	body_label.text = String(payload.get("text", "..."))
	stock_label.text = _format_stock(payload.get("stock", []))
	stock_label.visible = bool(payload.get("show_stock", false))
	trade_button.disabled = (payload.get("stock", []) as Array).is_empty()
	_update_relation(int(payload.get("relation", 0)))
	show()
	rumor_button.grab_focus()


func close_dialogue() -> void:
	if not visible:
		return
	hide()
	dialogue_closed.emit()


func _request_action(action: StringName) -> void:
	action_requested.emit(action)


func _set_identity(display_name: String, explicit_role: String) -> void:
	var resolved_name := display_name.strip_edges()
	var resolved_role := explicit_role.strip_edges()
	if resolved_role.is_empty() and display_name.contains(","):
		var parts := display_name.split(",", false, 1)
		resolved_name = parts[0].strip_edges()
		resolved_role = parts[1].strip_edges() if parts.size() > 1 else ""
	title_label.text = resolved_name if not resolved_name.is_empty() else "Странник"
	role_label.text = resolved_role if not resolved_role.is_empty() else "Выживший"


func _update_relation(attitude: int) -> void:
	var clamped_attitude := clampi(attitude, -100, 100)
	relation_bar.value = float(clamped_attitude + 100) * 0.5
	if clamped_attitude >= 60:
		relation_bar.modulate = Color(0.48, 0.9, 0.38)
		relation_icon.texture = _create_atlas_texture(RELATION_REGIONS[0])
	elif clamped_attitude >= 20:
		relation_bar.modulate = Color(0.72, 0.86, 0.36)
		relation_icon.texture = _create_atlas_texture(RELATION_REGIONS[1])
	elif clamped_attitude > -20:
		relation_bar.modulate = Color(0.92, 0.75, 0.32)
		relation_icon.texture = _create_atlas_texture(RELATION_REGIONS[2])
	elif clamped_attitude > -60:
		relation_bar.modulate = Color(0.95, 0.5, 0.2)
		relation_icon.texture = _create_atlas_texture(RELATION_REGIONS[3])
	else:
		relation_bar.modulate = Color(0.9, 0.25, 0.2)
		relation_icon.texture = _create_atlas_texture(RELATION_REGIONS[4])


func _create_atlas_texture(region: Rect2) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = ICON_ATLAS
	texture.region = region
	return texture


func _update_panel_scale() -> void:
	if panel_root == null:
		return
	var viewport_size := get_viewport_rect().size
	var available_size := viewport_size - Vector2(48.0, 48.0)
	var fit_scale := minf(available_size.x / 775.0, available_size.y / 487.0)
	var safe_scale := clampf(fit_scale, 0.72, 1.65)
	panel_root.scale = Vector2.ONE * safe_scale


func _format_stock(raw_stock: Variant) -> String:
	if not (raw_stock is Array):
		return ""
	var lines: PackedStringArray = ["Доступные припасы:"]
	for raw_entry in raw_stock as Array:
		if not (raw_entry is Dictionary):
			continue
		var entry := raw_entry as Dictionary
		lines.append("• %s ×%d" % [String(entry.get("name", "Предмет")), int(entry.get("count", 1))])
	if lines.size() == 1:
		lines.append("• Сейчас ничего нет")
	return "\n".join(lines)


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close_dialogue()
		get_viewport().set_input_as_handled()
