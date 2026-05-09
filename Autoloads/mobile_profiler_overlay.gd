extends CanvasLayer
class_name MobileProfilerOverlay

@export var world_generation_root_path: NodePath = NodePath("WorldGeneration")
@export var update_interval_sec: float = 0.25
@export var spike_threshold_ms: float = 33.0
@export var safe_margin: Vector2 = Vector2(18.0, 92.0)

var _label: Label
var _update_timer: float = 0.0
var _last_frame_ms: float = 0.0
var _spike_count: int = 0
var _max_spike_ms: float = 0.0


func _ready() -> void:
	layer = 95
	_build_ui()
	set_process(true)


func _process(delta: float) -> void:
	_last_frame_ms = delta * 1000.0
	if _last_frame_ms >= spike_threshold_ms:
		_spike_count += 1
		_max_spike_ms = maxf(_max_spike_ms, _last_frame_ms)

	_update_timer -= delta
	if _update_timer > 0.0:
		return
	_update_timer = update_interval_sec
	_refresh_text()


func _build_ui() -> void:
	var root := Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.offset_left = safe_margin.x
	root.offset_top = safe_margin.y
	root.offset_right = safe_margin.x + 260.0
	root.offset_bottom = safe_margin.y + 112.0
	add_child(root)

	var panel := Panel.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 0.0
	panel.offset_top = 0.0
	panel.offset_right = 0.0
	panel.offset_bottom = 0.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.025, 0.03, 0.68)
	style.border_color = Color(0.85, 0.9, 0.95, 0.28)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	_label = Label.new()
	_label.name = "Stats"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.offset_left = 10.0
	_label.offset_top = 8.0
	_label.offset_right = -10.0
	_label.offset_bottom = -8.0
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	panel.add_child(_label)


func _refresh_text() -> void:
	if _label == null:
		return

	var chunk_stats := _collect_chunk_stats()
	_label.text = "FPS %d  frame %.1fms\nspikes %d  max %.1fms\nchunks %d  pending %d\ndraw calls %d" % [
		int(round(Performance.get_monitor(Performance.TIME_FPS))),
		_last_frame_ms,
		_spike_count,
		_max_spike_ms,
		int(chunk_stats.get("loaded", 0)),
		int(chunk_stats.get("pending", 0)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	]


func _collect_chunk_stats() -> Dictionary:
	var loaded_total := 0
	var pending_total := 0
	var root := _resolve_world_generation_root()
	if root == null:
		return {"loaded": loaded_total, "pending": pending_total}

	for child in root.get_children():
		if not child.has_method("get_debug_world_generation_info"):
			continue
		var info: Variant = child.call("get_debug_world_generation_info")
		if not (info is Dictionary):
			continue
		var data := info as Dictionary
		var loaded: Variant = data.get("loaded_chunks", [])
		if loaded is Array:
			loaded_total += (loaded as Array).size()
		if child.has_method("get_pending_generation_chunk_count"):
			pending_total += int(child.call("get_pending_generation_chunk_count"))
		else:
			pending_total += int(data.get("pending_load", 0))
			pending_total += int(data.get("pending_unload", 0))

	return {"loaded": loaded_total, "pending": pending_total}


func _resolve_world_generation_root() -> Node:
	var owner_node := get_parent()
	if owner_node != null:
		var from_parent := owner_node.get_node_or_null(world_generation_root_path)
		if from_parent != null:
			return from_parent
	return get_tree().current_scene.get_node_or_null(world_generation_root_path) if get_tree().current_scene != null else null
