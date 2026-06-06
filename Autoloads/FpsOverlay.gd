extends CanvasLayer

@export var update_interval_sec: float = 0.2
@export var safe_margin: Vector2 = Vector2(18.0, 18.0)

var _root: Control
var _panel: Panel
var _label: Label
var _update_timer: float = 0.0


func _ready() -> void:
	layer = 110
	_build_ui()
	set_process(true)
	if not get_viewport().size_changed.is_connected(_layout_ui):
		get_viewport().size_changed.connect(_layout_ui)
	_layout_ui()
	_refresh_text()


func _exit_tree() -> void:
	if get_viewport() != null and get_viewport().size_changed.is_connected(_layout_ui):
		get_viewport().size_changed.disconnect(_layout_ui)


func _process(delta: float) -> void:
	_update_timer -= delta
	if _update_timer > 0.0:
		return
	_update_timer = maxf(update_interval_sec, 0.05)
	_refresh_text()


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	add_child(_root)

	_panel = Panel.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.custom_minimum_size = Vector2(132.0, 38.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.025, 0.03, 0.72)
	style.border_color = Color(0.85, 0.9, 0.95, 0.28)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", style)
	_root.add_child(_panel)

	_label = Label.new()
	_label.name = "FpsLabel"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.position = Vector2(10.0, 6.0)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	_panel.add_child(_label)


func _layout_ui() -> void:
	if _root == null or _panel == null:
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_size: Vector2 = viewport.get_visible_rect().size
	var panel_size := _panel.custom_minimum_size
	_root.position = Vector2(viewport_size.x - panel_size.x - safe_margin.x, safe_margin.y)
	_panel.size = panel_size


func _refresh_text() -> void:
	if _label == null:
		return
	var fps := Engine.get_frames_per_second()
	var frame_ms := 1000.0 / maxf(float(maxi(fps, 1)), 1.0)
	_label.text = "FPS %d  %.1fms" % [fps, frame_ms]
