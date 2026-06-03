extends Node2D

signal harvest_requested(crop: Node)
signal clear_requested(crop: Node)

enum CropState {
	GROWING,
	READY,
	TAINTED
}

@export_range(0.1, 120.0, 0.1) var stage_duration_game_minutes: float = 5.0
@export_range(0.1, 240.0, 0.1) var taint_after_ready_game_minutes: float = 20.0
@export var interaction_radius_px: float = 72.0

@onready var stage_sprites: Array[Sprite2D] = _collect_stage_sprites()
@onready var cultivated_outline: Sprite2D = $CultivatedOutline
@onready var tainted_crop_sprite: Sprite2D = _resolve_tainted_crop_sprite()
@onready var tainted_outline: Sprite2D = $TaintedOutline
@onready var interact_label: Label = $InteractLabel

var farm_cell: Vector2i = Vector2i.ZERO
var planted_at_game_minutes: float = 0.0
var state: CropState = CropState.GROWING
var _fallback_game_minutes: float = 0.0


func _ready() -> void:
	add_to_group("primary_interactable")
	_fallback_game_minutes = planted_at_game_minutes
	_update_visuals()
	set_process(true)


func setup(cell: Vector2i, planted_at_minutes: float, stage_minutes: float, taint_minutes: float) -> void:
	farm_cell = cell
	planted_at_game_minutes = maxf(planted_at_minutes, 0.0)
	stage_duration_game_minutes = maxf(stage_minutes, 0.1)
	taint_after_ready_game_minutes = maxf(taint_minutes, 0.1)
	_fallback_game_minutes = planted_at_game_minutes
	_update_visuals()


func _process(delta: float) -> void:
	_fallback_game_minutes += maxf(delta, 0.0)
	_refresh_growth_state()
	_update_interaction_feedback()


func handle_primary_interaction(interactor: Node) -> bool:
	if not _is_player_in_range(interactor):
		return false

	match state:
		CropState.READY:
			harvest_requested.emit(self)
			return true
		CropState.TAINTED:
			clear_requested.emit(self)
			return true
		_:
			return false


func get_save_data() -> Dictionary:
	return {
		"cell_x": farm_cell.x,
		"cell_y": farm_cell.y,
		"planted_at_game_minutes": planted_at_game_minutes
	}


func apply_save_data(save_data: Dictionary) -> void:
	farm_cell = Vector2i(int(save_data.get("cell_x", farm_cell.x)), int(save_data.get("cell_y", farm_cell.y)))
	planted_at_game_minutes = maxf(float(save_data.get("planted_at_game_minutes", planted_at_game_minutes)), 0.0)
	_fallback_game_minutes = planted_at_game_minutes
	_refresh_growth_state()


func _refresh_growth_state() -> void:
	var elapsed_minutes := maxf(_get_current_game_minutes() - planted_at_game_minutes, 0.0)
	var total_growth_minutes := stage_duration_game_minutes * float(max(stage_sprites.size(), 1))
	var next_state := CropState.GROWING
	if elapsed_minutes >= total_growth_minutes + taint_after_ready_game_minutes:
		next_state = CropState.TAINTED
	elif elapsed_minutes >= total_growth_minutes:
		next_state = CropState.READY

	if next_state != state:
		state = next_state
	_update_visuals()


func _update_visuals() -> void:
	var elapsed_minutes := maxf(_get_current_game_minutes() - planted_at_game_minutes, 0.0)
	var stage_count: int = max(stage_sprites.size(), 1)
	var stage_index := clampi(int(floor(elapsed_minutes / maxf(stage_duration_game_minutes, 0.1))), 0, stage_count - 1)

	for i in range(stage_sprites.size()):
		var stage_sprite := stage_sprites[i]
		if stage_sprite != null:
			stage_sprite.visible = state != CropState.TAINTED and i == stage_index

	if tainted_crop_sprite != null:
		tainted_crop_sprite.visible = state == CropState.TAINTED
	if cultivated_outline != null:
		cultivated_outline.visible = false
	if tainted_outline != null:
		tainted_outline.visible = false
	if interact_label != null:
		interact_label.visible = false


func _update_interaction_feedback() -> void:
	var player := get_tree().get_first_node_in_group("player")
	var actionable := state == CropState.READY or state == CropState.TAINTED
	var player_near := actionable and _is_player_in_range(player)

	if cultivated_outline != null:
		cultivated_outline.visible = player_near and state == CropState.READY
	if tainted_outline != null:
		tainted_outline.visible = player_near and state == CropState.TAINTED
	if interact_label != null:
		interact_label.text = "[E] - собрать" if state == CropState.READY else "[E] - очистить"
		interact_label.visible = player_near


func _is_player_in_range(candidate: Node) -> bool:
	if candidate == null or not candidate.is_in_group("player"):
		return false
	if not (candidate is Node2D):
		return false
	return (candidate as Node2D).global_position.distance_to(global_position) <= maxf(interaction_radius_px, 1.0)


func _get_current_game_minutes() -> float:
	var clock := get_tree().get_first_node_in_group("game_clock")
	if clock != null and clock.has_method("get_game_time_total_minutes"):
		return float(clock.call("get_game_time_total_minutes"))
	return _fallback_game_minutes


func _collect_stage_sprites() -> Array[Sprite2D]:
	var indexed_stages: Array[Dictionary] = []
	for child in get_children():
		var sprite := child as Sprite2D
		if sprite == null:
			continue
		var node_name: String = String(sprite.name)
		if not node_name.begins_with("Stage"):
			continue
		var suffix: String = node_name.substr(5)
		var order_index: int = int(suffix) if suffix.is_valid_int() else 9999
		indexed_stages.append({
			"order_index": order_index,
			"sprite": sprite
		})

	indexed_stages.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("order_index", 0)) < int(b.get("order_index", 0))
	)

	var result: Array[Sprite2D] = []
	for stage_entry in indexed_stages:
		var stage_sprite := stage_entry.get("sprite", null) as Sprite2D
		if stage_sprite != null:
			result.append(stage_sprite)
	return result


func _resolve_tainted_crop_sprite() -> Sprite2D:
	var fallback: Sprite2D = null
	for child in get_children():
		var sprite := child as Sprite2D
		if sprite == null:
			continue
		var node_name: String = String(sprite.name)
		if node_name == "TaintedOutline":
			continue
		if node_name.begins_with("Tainted"):
			return sprite
		if fallback == null and node_name.to_lower().contains("tainted"):
			fallback = sprite
	return fallback
