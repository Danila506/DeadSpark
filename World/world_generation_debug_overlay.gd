extends Node2D

@export var enabled: bool = false
@export var max_cells_drawn_per_layer: int = 600
@export var id_draw_radius_px: float = 900.0

var _canvas_layer: CanvasLayer
var _label: Label


func _ready() -> void:
	_ensure_label()
	set_process(enabled)
	set_process_unhandled_input(true)
	_apply_visibility()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.physical_keycode == KEY_F3:
			enabled = not enabled
			_apply_visibility()
			queue_redraw()


func _process(_delta: float) -> void:
	if not enabled:
		return
	_update_label()
	queue_redraw()


func _draw() -> void:
	if not enabled:
		return

	var source_index := 0
	for source in _get_debug_sources():
		var info: Dictionary = source.call("get_debug_world_generation_info")
		var color := _source_color(source_index)
		_draw_source_chunks(info, color)
		_draw_source_cells(info, color)
		_draw_blockers(info)
		_draw_spawn_positions(info)
		source_index += 1
	_draw_generated_ids()


func _ensure_label() -> void:
	if _canvas_layer != null:
		return
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.name = "DebugOverlayCanvas"
	add_child(_canvas_layer)

	_label = Label.new()
	_label.name = "DebugOverlayLabel"
	_label.position = Vector2(12.0, 12.0)
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(0.92, 0.98, 0.76, 1.0))
	_canvas_layer.add_child(_label)


func _apply_visibility() -> void:
	visible = enabled
	set_process(enabled)
	if _canvas_layer != null:
		_canvas_layer.visible = enabled


func _update_label() -> void:
	if _label == null:
		return
	var lines: Array[String] = ["WorldGen Debug"]
	if GameSaveManager != null and GameSaveManager.has_method("get_world_generation_state"):
		var state: Dictionary = GameSaveManager.get_world_generation_state()
		var modified_count := 0
		var raw_modified: Variant = state.get("modified_objects", {})
		if raw_modified is Dictionary:
			modified_count = (raw_modified as Dictionary).size()
		lines.append("world_seed=%s generator_v=%s dirty_objects=%d" % [
			str(state.get("seed", 0)),
			str(state.get("generator_version", 0)),
			modified_count
		])
	for source in _get_debug_sources():
		var info: Dictionary = source.call("get_debug_world_generation_info")
		var active_chunks := 0
		var raw_chunks: Variant = info.get("loaded_chunks", [])
		if raw_chunks is Array:
			active_chunks = (raw_chunks as Array).size()
		lines.append("%s seed=%s active_chunks=%d" % [
			String(info.get("name", source.name)),
			str(info.get("seed", 0)),
			active_chunks
		])
		var watched_stats: Variant = info.get("watched_tile_stats", {})
		if watched_stats is Dictionary:
			for atlas_key in (watched_stats as Dictionary).keys():
				var stat_value: Variant = (watched_stats as Dictionary).get(atlas_key, {})
				if not (stat_value is Dictionary):
					continue
				var stats := stat_value as Dictionary
				lines.append(
					"  atlas %s pick=%d place=%d avoid=%d fit=%d block=%d phys=%d" % [
						String(atlas_key),
						int(stats.get("picked", 0)),
						int(stats.get("placed", 0)),
						int(stats.get("blocked_by_avoid", 0)),
						int(stats.get("chunk_fit_or_occupied", 0)),
						int(stats.get("blocked_node", 0)),
						int(stats.get("physics_collision", 0))
					]
				)
	_label.text = "\n".join(lines)


func _get_debug_sources() -> Array[Node]:
	var result: Array[Node] = []
	var parent_node := get_parent()
	if parent_node == null:
		return result
	for child in parent_node.get_children():
		if child == self:
			continue
		if child.has_method("get_debug_world_generation_info"):
			result.append(child)
	return result


func _draw_source_chunks(info: Dictionary, color: Color) -> void:
	var loaded_chunks: Array = info.get("loaded_chunks", [])
	if loaded_chunks.is_empty():
		return
	var chunk_size := int(info.get("chunk_size_tiles", 16))
	var tile_size: Vector2 = info.get("tile_size_px", Vector2(60.0, 60.0))
	if tile_size.x <= 0.0 or tile_size.y <= 0.0:
		return
	var chunk_px := tile_size * float(chunk_size)
	for chunk_value in loaded_chunks:
		var chunk := chunk_value as Vector2i
		var rect := Rect2(Vector2(chunk) * chunk_px, chunk_px)
		draw_rect(rect, color, false, 2.0)


func _draw_source_cells(info: Dictionary, color: Color) -> void:
	var cells: Array = info.get("protected_cells", [])
	var generated: Array = info.get("generated_cells", [])
	var tile_size: Vector2 = info.get("tile_size_px", Vector2.ZERO)
	if tile_size.x <= 0.0 or tile_size.y <= 0.0:
		return
	_draw_cell_array(cells, tile_size, Color(1.0, 0.25, 0.1, 0.38))
	_draw_cell_array(generated, tile_size, Color(color.r, color.g, color.b, 0.22))


func _draw_cell_array(cells: Array, tile_size: Vector2, color: Color) -> void:
	var limit := mini(max_cells_drawn_per_layer, cells.size())
	for i in range(limit):
		var cell := cells[i] as Vector2i
		var pos := Vector2(cell) * tile_size
		draw_rect(Rect2(pos, tile_size), color, false, 1.0)


func _draw_blockers(info: Dictionary) -> void:
	var blockers: Array = info.get("blocked_world_positions", [])
	for blocker in blockers:
		draw_circle(to_local(blocker as Vector2), 8.0, Color(1.0, 0.1, 0.1, 0.75))


func _draw_spawn_positions(info: Dictionary) -> void:
	var positions_by_chunk: Dictionary = info.get("spawn_positions_by_chunk", {})
	for positions_value in positions_by_chunk.values():
		var positions := positions_value as Array
		for position_value in positions:
			var pos := position_value as Vector2
			draw_circle(to_local(pos), 3.0, Color(0.45, 1.0, 0.45, 0.8))


func _draw_generated_ids() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var font := ThemeDB.fallback_font
	if font == null:
		return
	for candidate in get_tree().get_nodes_in_group("generated_world_object"):
		if not (candidate is Node2D):
			continue
		var node := candidate as Node2D
		if player != null and player.global_position.distance_to(node.global_position) > id_draw_radius_px:
			continue
		var object_id := String(node.get_meta("world_generation_id", ""))
		if object_id.is_empty():
			continue
		draw_string(font, to_local(node.global_position + Vector2(6.0, -8.0)), object_id, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9, Color(1.0, 0.94, 0.35, 0.9))


func _source_color(index: int) -> Color:
	var colors: Array[Color] = [
		Color(0.3, 0.8, 1.0, 0.65),
		Color(0.4, 1.0, 0.45, 0.65),
		Color(1.0, 0.78, 0.25, 0.65),
		Color(1.0, 0.35, 0.65, 0.65),
		Color(0.72, 0.55, 1.0, 0.65)
	]
	return colors[index % colors.size()]
