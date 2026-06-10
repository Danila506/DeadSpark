extends Node

signal phase_changed(previous_phase: StringName, current_phase: StringName, minutes_of_day: float)
signal visuals_updated(phase: StringName, day_fraction: float, blend_weight: float)

const MINUTES_PER_DAY: float = 1440.0
const PHASE_DAWN: StringName = &"dawn"
const PHASE_DAY: StringName = &"day"
const PHASE_DUSK: StringName = &"dusk"
const PHASE_NIGHT: StringName = &"night"

@export_category("Bindings")
@export var clock_path: NodePath = NodePath("../Y-Sort_Objects/HUD")
@export var level_root_path: NodePath = NodePath("..")
@export var night_canvas_modulate_path: NodePath = NodePath("../NightCanvasModulate")

@export_category("Time Phases")
@export_range(0, 23, 1) var dawn_start_hour: int = 5
@export_range(0, 23, 1) var day_start_hour: int = 8
@export_range(0, 23, 1) var dusk_start_hour: int = 18
@export_range(0, 23, 1) var night_start_hour: int = 21

@export_category("Phase Colors")
@export var dawn_canvas_color: Color = Color(0.58, 0.56, 0.62, 1.0)
@export var day_canvas_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var dusk_canvas_color: Color = Color(0.62, 0.53, 0.48, 1.0)
@export var night_canvas_color: Color = Color(0.35, 0.38, 0.5, 1.0)
@export var dawn_world_mood_color: Color = Color(0.76, 0.72, 0.74, 1.0)
@export var day_world_mood_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var dusk_world_mood_color: Color = Color(0.78, 0.69, 0.62, 1.0)
@export var night_world_mood_color: Color = Color(0.62, 0.67, 0.78, 1.0)

@export_category("Transitions")
@export_range(0.0, 10.0, 0.05) var visual_smoothing_speed: float = 3.2

var _clock: Node = null
var _level_root: Node = null
var _night_canvas_modulate: CanvasModulate = null
var _current_minutes_of_day: float = 0.0
var _current_phase: StringName = PHASE_DAY
var _current_canvas_color: Color = Color.WHITE
var _current_world_mood_color: Color = Color.WHITE
var _last_emitted_phase: StringName = &""


func _ready() -> void:
	add_to_group("time_of_day_manager")
	_resolve_dependencies()
	_current_minutes_of_day = _read_minutes_of_day()
	_current_phase = _get_phase_for_minutes(_current_minutes_of_day)
	_last_emitted_phase = _current_phase
	_current_canvas_color = _get_canvas_color_for_minutes(_current_minutes_of_day)
	_current_world_mood_color = _get_world_mood_color_for_minutes(_current_minutes_of_day)
	_apply_visuals(_current_canvas_color, _current_world_mood_color)


func _process(delta: float) -> void:
	_resolve_dependencies()
	_current_minutes_of_day = _read_minutes_of_day()
	var next_phase := _get_phase_for_minutes(_current_minutes_of_day)
	if next_phase != _current_phase:
		var previous_phase := _current_phase
		_current_phase = next_phase
		_last_emitted_phase = next_phase
		phase_changed.emit(previous_phase, next_phase, _current_minutes_of_day)

	var target_canvas_color := _get_canvas_color_for_minutes(_current_minutes_of_day)
	var target_world_mood_color := _get_world_mood_color_for_minutes(_current_minutes_of_day)
	var weight := 1.0 - exp(-maxf(delta, 0.0) * maxf(visual_smoothing_speed, 0.001))
	_current_canvas_color = _current_canvas_color.lerp(target_canvas_color, weight)
	_current_world_mood_color = _current_world_mood_color.lerp(target_world_mood_color, weight)
	_apply_visuals(_current_canvas_color, _current_world_mood_color)
	visuals_updated.emit(_current_phase, get_day_fraction(), weight)


func get_minutes_of_day() -> float:
	return _current_minutes_of_day


func get_day_fraction() -> float:
	return wrapf(_current_minutes_of_day / MINUTES_PER_DAY, 0.0, 1.0)


func get_current_phase() -> StringName:
	return _current_phase


func get_phase_weighted_scalar(dawn_value: float, day_value: float, dusk_value: float, night_value: float) -> float:
	return _sample_phase_gradient_scalar(
		_current_minutes_of_day,
		dawn_value,
		day_value,
		dusk_value,
		night_value
	)


func force_refresh() -> void:
	_current_minutes_of_day = _read_minutes_of_day()
	_current_phase = _get_phase_for_minutes(_current_minutes_of_day)
	_current_canvas_color = _get_canvas_color_for_minutes(_current_minutes_of_day)
	_current_world_mood_color = _get_world_mood_color_for_minutes(_current_minutes_of_day)
	_apply_visuals(_current_canvas_color, _current_world_mood_color)


func _resolve_dependencies() -> void:
	if _clock == null or not is_instance_valid(_clock):
		_clock = get_node_or_null(clock_path)
	if _level_root == null or not is_instance_valid(_level_root):
		_level_root = get_node_or_null(level_root_path)
	if _night_canvas_modulate == null or not is_instance_valid(_night_canvas_modulate):
		_night_canvas_modulate = get_node_or_null(night_canvas_modulate_path) as CanvasModulate


func _read_minutes_of_day() -> float:
	if _clock != null and _clock.has_method("get_game_time_minutes_of_day"):
		return _normalize_minutes(float(_clock.call("get_game_time_minutes_of_day")))
	return 0.0


func _get_phase_for_minutes(minutes_of_day: float) -> StringName:
	var minutes := _normalize_minutes(minutes_of_day)
	var dawn_start := _hour_to_minutes(dawn_start_hour)
	var day_start := _hour_to_minutes(day_start_hour)
	var dusk_start := _hour_to_minutes(dusk_start_hour)
	var night_start := _hour_to_minutes(night_start_hour)
	if _is_minutes_in_range(minutes, dawn_start, day_start):
		return PHASE_DAWN
	if _is_minutes_in_range(minutes, day_start, dusk_start):
		return PHASE_DAY
	if _is_minutes_in_range(minutes, dusk_start, night_start):
		return PHASE_DUSK
	return PHASE_NIGHT


func _get_canvas_color_for_minutes(minutes_of_day: float) -> Color:
	return _sample_phase_gradient(
		minutes_of_day,
		dawn_canvas_color,
		day_canvas_color,
		dusk_canvas_color,
		night_canvas_color
	)


func _get_world_mood_color_for_minutes(minutes_of_day: float) -> Color:
	return _sample_phase_gradient(
		minutes_of_day,
		dawn_world_mood_color,
		day_world_mood_color,
		dusk_world_mood_color,
		night_world_mood_color
	)


func _sample_phase_gradient(
	minutes_of_day: float,
	dawn_color: Color,
	day_color: Color,
	dusk_color: Color,
	night_color: Color
) -> Color:
	var minutes := _normalize_minutes(minutes_of_day)
	var dawn_start := _hour_to_minutes(dawn_start_hour)
	var day_start := _hour_to_minutes(day_start_hour)
	var dusk_start := _hour_to_minutes(dusk_start_hour)
	var night_start := _hour_to_minutes(night_start_hour)

	if _is_minutes_in_range(minutes, dawn_start, day_start):
		return dawn_color.lerp(day_color, _range_blend(minutes, dawn_start, day_start))
	if _is_minutes_in_range(minutes, day_start, dusk_start):
		return day_color.lerp(dusk_color, _range_blend(minutes, day_start, dusk_start))
	if _is_minutes_in_range(minutes, dusk_start, night_start):
		return dusk_color.lerp(night_color, _range_blend(minutes, dusk_start, night_start))
	return night_color.lerp(dawn_color, _range_blend(minutes, night_start, dawn_start + MINUTES_PER_DAY))


func _sample_phase_gradient_scalar(
	minutes_of_day: float,
	dawn_value: float,
	day_value: float,
	dusk_value: float,
	night_value: float
) -> float:
	var minutes := _normalize_minutes(minutes_of_day)
	var dawn_start := _hour_to_minutes(dawn_start_hour)
	var day_start := _hour_to_minutes(day_start_hour)
	var dusk_start := _hour_to_minutes(dusk_start_hour)
	var night_start := _hour_to_minutes(night_start_hour)

	if _is_minutes_in_range(minutes, dawn_start, day_start):
		return lerpf(dawn_value, day_value, _range_blend(minutes, dawn_start, day_start))
	if _is_minutes_in_range(minutes, day_start, dusk_start):
		return lerpf(day_value, dusk_value, _range_blend(minutes, day_start, dusk_start))
	if _is_minutes_in_range(minutes, dusk_start, night_start):
		return lerpf(dusk_value, night_value, _range_blend(minutes, dusk_start, night_start))
	return lerpf(night_value, dawn_value, _range_blend(minutes, night_start, dawn_start + MINUTES_PER_DAY))


func _apply_visuals(canvas_color: Color, mood_color: Color) -> void:
	if _night_canvas_modulate != null:
		_night_canvas_modulate.color = canvas_color
	if _level_root != null and _level_root.has_method("apply_world_mood_color"):
		_level_root.call("apply_world_mood_color", mood_color)


func _range_blend(value: float, start_value: float, end_value: float) -> float:
	var adjusted_value := value
	var adjusted_end := end_value
	if adjusted_end <= start_value:
		adjusted_end += MINUTES_PER_DAY
	if adjusted_value < start_value:
		adjusted_value += MINUTES_PER_DAY
	return clampf(inverse_lerp(start_value, adjusted_end, adjusted_value), 0.0, 1.0)


func _hour_to_minutes(hour: int) -> float:
	return float(posmod(hour, 24) * 60)


func _normalize_minutes(value: float) -> float:
	return wrapf(value, 0.0, MINUTES_PER_DAY)


func _is_minutes_in_range(value: float, start_value: float, end_value: float) -> bool:
	if is_equal_approx(start_value, end_value):
		return true
	if start_value < end_value:
		return value >= start_value and value < end_value
	return value >= start_value or value < end_value
